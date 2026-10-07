# shellcheck shell=bash disable=SC2034  # VAPT_* outputs are consumed by provision.sh
# Official signers are explicit trust anchors, never learned from downloaded DBs.
vapt_blackarch_state() {
    if [[ ${VAPT_UNSAFE[blackarch]:-} || ${VAPT_SOURCE_BLOCKED[blackarch]:-} ]]; then echo broken
    elif [[ ! ${VAPT_ENABLED[blackarch]:-} ]]; then echo absent
    elif [[ ${VAPT_DATABASE[blackarch]:-} && ( ${VAPT_PACKAGE[blackarch/blackarch-keyring]:-} || ${VAPT_PACKAGE[blackarch/blackarch-mirrorlist]:-} ) ]]; then echo usable
    else echo unknown
    fi
}
vapt_verify_keyring() {
    local package="$1" signature="$2" keydir="$3" signer
    if $DRY_RUN; then
        run gpg --homedir "$keydir" --batch --status-file "$keydir/status" --verify "$signature" "$package"
        info 'vapt: require exactly one non-expired, non-revoked signature bound to a pinned primary signer'
        return 2
    fi
    if ! run gpg --homedir "$keydir" --batch --status-file "$keydir/status" --verify "$signature" "$package"; then return 1; fi
    signer="$(vapt_meta verify "$keydir/status" "$VAPT_DIR/files/blackarch-signers.txt")" || return 1
    VAPT_KEYRING_SIGNER="$signer"
    return 0
}
vapt_blackarch_bootstrap() {
    # The bootstrap owns one root transaction stage for its sealed keyring and
    # sudoers facts; it is always removed before the reviewed full upgrade
    # creates its own.
    local rc=0
    VAPT_CACHE=''
    vapt_blackarch_bootstrap_steps || rc=$?
    vapt_transaction_cleanup || { VAPT_MUTATION_FAILED=1; ((rc)) || rc=1; }
    VAPT_CACHE=''
    return "$rc"
}
vapt_blackarch_bootstrap_steps() {
    vapt_pacman_stage || return 1
    local stage="$VAPT_STAGE/blackarch" keys="$VAPT_STAGE/blackarch/keys" fingerprint filename digest record output rc=0
    run install -d -m 0700 "$stage" "$keys" || { VAPT_MUTATION_FAILED=1; return 1; }
    run curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$stage/blackarch.db" https://blackarch.org/blackarch/blackarch/os/x86_64/blackarch.db || { VAPT_MUTATION_FAILED=1; return 1; }
    if $DRY_RUN; then
        filename='blackarch-keyring-<discovered-version>.pkg.tar.zst'
    else
        record="$(vapt_meta discover "$stage/blackarch.db")" || return 2
        IFS=$'\t' read -r filename digest <<<"$record"
    fi
    local origin=https://blackarch.org/blackarch/blackarch/os/x86_64
    run curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$stage/$filename" "$origin/$filename" || { VAPT_MUTATION_FAILED=1; return 1; }
    run curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$stage/$filename.sig" "$origin/$filename.sig" || { VAPT_MUTATION_FAILED=1; return 1; }
    while IFS= read -r fingerprint; do
        [[ $fingerprint =~ ^[A-F0-9]{40}$ ]] || continue
        run curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$stage/$fingerprint.asc" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint" || { VAPT_MUTATION_FAILED=1; return 1; }
        if ! $DRY_RUN; then
            output="$(run gpg --homedir "$keys" --batch --with-colons --import-options show-only --import "$stage/$fingerprint.asc" 2>/dev/null)" || return 2
            # First primary fingerprint, not a short ID or signing subkey.
            local line kind found='' waiting=false
            while IFS=: read -r kind _ _ _ _ _ _ _ _ line _; do
                [[ $kind == pub ]] && waiting=true
                if $waiting && [[ $kind == fpr ]]; then found="$line"; break; fi
            done <<<"$output"
            [[ $found == "$fingerprint" ]] || return 2
        fi
        run gpg --homedir "$keys" --batch --import "$stage/$fingerprint.asc" || { VAPT_MUTATION_FAILED=1; return 1; }
    done <"$VAPT_DIR/files/blackarch-signers.txt"
    local sealed="$stage/$filename"
    if ! $DRY_RUN; then
        # Root seals exactly the DB-digest bytes (+ .sig) into this run's root
        # stage; signature verification, the keyring audit and the -U all
        # read that sealed copy, never the user-writable download.
        vapt_transaction_cache || { rc=$?; ((rc != 1)) || VAPT_MUTATION_FAILED=1; return "$rc"; }
        vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_CACHE/sealed" || { VAPT_MUTATION_FAILED=1; return 1; }
        vapt_root_meta seal "$stage/$filename" "$VAPT_CACHE/sealed/$filename" "$digest" || {
            VAPT_SOURCE_REASON='keyring archive differs from the BlackArch database digest'; return 2;
        }
        sealed="$(vapt_read_path "$VAPT_CACHE/sealed/$filename")"
        vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || { VAPT_SOURCE_REASON="$VAPT_APPLY_REASON"; return 2; }
    fi
    if $DRY_RUN; then
        vapt_verify_keyring "$sealed" "$sealed.sig" "$keys" || true
        VAPT_KEYRING_SIGNER='<verified-pinned-primary>'
    elif ! vapt_verify_keyring "$sealed" "$sealed.sig" "$keys"; then
        VAPT_SOURCE_REASON='keyring detached signature rejected'; return 2
    fi
    run gpg --homedir "$keys" --batch --output "$stage/signer.gpg" --export "$VAPT_KEYRING_SIGNER" || { VAPT_MUTATION_FAILED=1; return 1; }
    if ! $DRY_RUN; then
        vapt_root_facts || { VAPT_SOURCE_REASON="$VAPT_APPLY_REASON"; return 2; }
        vapt_meta keyring "$sealed" --sudo-plugins "$(vapt_read_path "$VAPT_CACHE/sudo-plugins")" \
            --authority-facts "$(vapt_read_path "$VAPT_CACHE/authority-facts")" >/dev/null || {
            VAPT_SOURCE_REASON='keyring identity/dependency/activation policy rejected'; return 2;
        }
    fi
    # The exact sealed archive under a repository-free configuration
    # (LocalFileSigLevel Required TrustedOnly): nothing is re-resolved.
    local config
    config="$(vapt_meta config --local)" || return 2
    printf '%s\n' "$config" | write_user_file "$stage/commit.conf" || { VAPT_MUTATION_FAILED=1; return 1; }
    vapt_root_exec /usr/bin/pacman-key --init || { VAPT_MUTATION_FAILED=1; return 1; }
    vapt_root_exec /usr/bin/pacman-key --add "$stage/signer.gpg" || { VAPT_MUTATION_FAILED=1; return 1; }
    vapt_root_exec /usr/bin/pacman-key --lsign-key "$VAPT_KEYRING_SIGNER" || { VAPT_MUTATION_FAILED=1; return 1; }
    local flags=()
    $ASSUME_YES && flags+=(--noconfirm)
    if ! $DRY_RUN; then
        vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || { VAPT_SOURCE_REASON="$VAPT_APPLY_REASON"; return 2; }
    fi
    # Only the signed, exactly reviewed population-only keyring scriptlet is
    # replaced by the explicit pacman-key action below. Hooks remain audited.
    vapt_root_pacman --config "$stage/commit.conf" -U --noscriptlet "${flags[@]}" -- \
        "${VAPT_CACHE:-<root-stage>}/sealed/$filename" || { VAPT_MUTATION_FAILED=1; return 1; }
    vapt_root_exec /usr/bin/pacman-key --populate blackarch || { VAPT_MUTATION_FAILED=1; return 1; }
    # The repository stanza is staged, not written: it becomes globally visible
    # only after the reviewed full upgrade commits (vapt_blackarch_activate).
    return 0
}
vapt_blackarch_preflight() {
    # Activation replaces one regular pacman.conf atomically; anything else
    # is refused before trust changes, a recovery record or a commit.
    $DRY_RUN && return 0
    [[ ! ${VAPT_ENABLED[blackarch]:-} ]] || return 0
    vapt_meta activation-preflight "$(vapt_read_path /etc/pacman.conf)" >/dev/null 2>&1 || return 2
}
vapt_blackarch_activate() {
    # Never rewrite/repair an existing stanza or mirrorlist.
    [[ ! ${VAPT_ENABLED[blackarch]:-} ]] || return 0
    if $DRY_RUN; then
        local stanza
        stanza="$(vapt_meta blackarch-stanza)" || return 1
        printf '%s\n' "$stanza" | append_root_file /etc/pacman.conf
        return
    fi
    # All-or-nothing: the whole new file replaces /etc/pacman.conf by rename
    # (owner/mode kept); a failure leaves it byte-identical and resumable.
    vapt_root_meta activate-blackarch "$(vapt_read_path /etc/pacman.conf)"
}
# Accepted recovery of a recorded reviewed commit: when that commit staged
# BlackArch (and no stanza exists yet), review/commit the same repository set
# again and activate afterwards rather than forgetting the staged repository.
vapt_pacman_recover() {
    local marker="$HASEEN_STATE_DIR/vapt/upgrade-pending" record rc=0
    vapt_root_lock || return $?
    vapt_state_path_safe "$marker" || return 2
    # The record is an exact protocol: unreadable, redirected or unknown
    # content fails closed and is preserved, never resumed as something else.
    record="$(vapt_meta recovery-record "$(vapt_read_path "$marker")" 2>&1)" || {
        VAPT_APPLY_REASON="$record"; return 2;
    }
    case "$record" in
    generic) ;;
    blackarch-staged) [[ ${VAPT_ENABLED[blackarch]:-} ]] || VAPT_BLACKARCH_STAGED=1 ;;
    *) return 2 ;;
    esac
    VAPT_RECOVERING=1
    vapt_pacman_upgrade || rc=$?
    VAPT_RECOVERING='' VAPT_BLACKARCH_STAGED=''
    return "$rc"
}
vapt_blackarch_prepare() {
    local state rc=0
    # An existing recovery requirement outranks preparation/source canaries.
    [[ $VAPT_PACMAN_BLOCKED != 1 ]] || return 0
    state="$(vapt_blackarch_state)"
    VAPT_SOURCE_REASON="BlackArch $state"
    [[ $state != usable ]] || return 0
    if [[ $state == broken || ( $state == unknown && ${VAPT_ENABLED[blackarch]:-} ) ]]; then
        VAPT_SOURCE_BLOCKED[blackarch]=1
        VAPT_SOURCE_REASON='existing BlackArch stanza is unverified/broken; preserved, not repaired'
        return 0
    fi
    confirm 'Prepare BlackArch signed keyring and review a full allowed-repository system upgrade?' || {
        VAPT_SOURCE_REASON='BlackArch preparation declined'; return 0;
    }
    vapt_root_lock || rc=$?
    if ((rc)); then
        VAPT_SOURCE_BLOCKED[blackarch]=1
        VAPT_SOURCE_REASON="BlackArch preparation unavailable: ${VAPT_APPLY_REASON:-privileged transaction lock unavailable}"
        ((rc != 1)) || VAPT_MUTATION_FAILED=1
        return 0
    fi
    # Under the lock, before any keyring trust or package change: a recovery
    # record another user left meanwhile blocks preparation like any commit.
    if vapt_upgrade_pending; then
        VAPT_PACMAN_BLOCKED=1
        VAPT_SOURCE_BLOCKED[blackarch]=1
        VAPT_SOURCE_REASON='recorded full upgrade remains incomplete; BlackArch preparation blocked'
        return 0
    fi
    vapt_blackarch_preflight || rc=$?
    if ((rc)); then
        VAPT_SOURCE_BLOCKED[blackarch]=1
        VAPT_SOURCE_REASON='BlackArch activation unsupported: /etc/pacman.conf is not a single regular file; nothing changed'
        return 0
    fi
    vapt_blackarch_bootstrap || rc=$?
    if ((rc)); then
        VAPT_SOURCE_BLOCKED[blackarch]=1
        [[ -n ${VAPT_SOURCE_REASON:-} ]] || VAPT_SOURCE_REASON='BlackArch bootstrap unavailable'
        return 0
    fi
    VAPT_BLACKARCH_STAGED=1
    vapt_pacman_upgrade || rc=$?
    VAPT_BLACKARCH_STAGED=''
    if ((rc)); then
        VAPT_PACMAN_BLOCKED=1
        VAPT_SOURCE_BLOCKED[blackarch]=1
        local reason="${VAPT_APPLY_REASON:-}"
        VAPT_SOURCE_REASON="full upgrade failed or safety policy rejected; all package installs blocked${reason:+: ${reason//$'\n'/ }}"
        return 0
    fi
    if $DRY_RUN; then
        VAPT_SOURCE_REASON='BlackArch bootstrap planned; no source/trust evidence fabricated'
    else
        vapt_snapshot || return 1
        if [[ $(vapt_blackarch_state) != usable ]]; then
            VAPT_SOURCE_BLOCKED[blackarch]=1
            VAPT_SOURCE_REASON='BlackArch keyring/mirrorlist canary unavailable after preparation'
        else
            VAPT_SOURCE_REASON='BlackArch authenticated bootstrap and full upgrade completed'
        fi
    fi
    return 0
}
