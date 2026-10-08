# shellcheck shell=bash disable=SC2034  # VAPT_* outputs are consumed by provision.sh
# The private oniomarchy source (plan 087). It is opted into per operation
# (--with-oniomarchy or repo-enable); its stanza lives only in haseen's root
# state and VAPT's own transaction configuration, never in /etc/pacman.conf.
# The initial signing key comes only from the fixed HTTPS URL and must be the
# reviewed primary; no keyserver is queried and no bootstrap script runs. The
# key import extends the shared pacman keyring: that part is global and is
# retained when the source is disabled.
VAPT_ONIOMARCHY_KEY_URL=https://pkgs.oniomarchy.com/oniomarchy.gpg
VAPT_ONIOMARCHY_REPO_URL=https://pkgs.oniomarchy.com/x86_64
VAPT_ONIOMARCHY_SOURCES=/var/lib/haseen/vapt/sources
VAPT_ONIOMARCHY_DISCLOSURE='Approving oniomarchy imports its reviewed signing key into the shared pacman keyring (global trust, kept when the source is disabled). The repository stanza stays private to haseen VAPT transactions; /etc/pacman.conf is not changed.'

# vapt_oniomarchy_fetch URL OUT — HTTPS only, TLS 1.2+, no redirect followed
# (a redirect fails rather than reaching another host).
vapt_oniomarchy_fetch() {
    run curl --fail --silent --show-error --location --max-redirs 0 --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --output "$2" "$1"
}

# vapt_oniomarchy_canary — offline readiness from recorded evidence into
# VAPT_ONIO[state|architecture|hostStanza|descriptor|descriptorPolicy|
# databaseSignatureState|keyringAuthorityState|reason]. No network or lock.
vapt_oniomarchy_canary() {
    local output key value
    declare -gA VAPT_ONIO=()
    output="$(vapt_meta oniomarchy-status 2>/dev/null)" || return 1
    while IFS=$'\t' read -r key value; do
        [[ -n $key ]] && VAPT_ONIO[$key]="$value"
    done <<<"$output"
    [[ -n ${VAPT_ONIO[state]:-} ]]
}

# vapt_oniomarchy_verify DB SIG KEYDIR SIGNERS — the detached database or
# package signature must carry exactly one accepted, non-expired,
# non-revoked primary; prints that primary.
vapt_oniomarchy_verify() {
    local data="$1" signature="$2" keys="$3" signers="$4"
    run gpg --homedir "$keys" --batch --status-file "$keys/status" --verify "$signature" "$data" >/dev/null 2>&1 || return 1
    vapt_meta verify "$keys/status" "$signers"
}

# vapt_oniomarchy_plan — the dry-run description of approval: nothing is
# fetched, verified, imported or written, and no filename is invented. It
# describes the run the recorded state would actually perform: a re-approval
# under a recorded keyring authority fetches no key and imports no pin.
vapt_oniomarchy_plan() {
    info 'vapt: oniomarchy approval plan (dry-run: nothing is fetched, checked, imported or written)'
    info 'vapt: would refuse unless the host architecture is x86_64 and /etc/pacman.conf declares no [oniomarchy]'
    if [[ ${VAPT_ONIO[keyringAuthorityState]:-} == ok ]]; then
        info 'vapt: re-approval under the recorded keyring authority: no signing key is fetched and the pinned key is not imported again'
        info "vapt: would fetch $VAPT_ONIOMARCHY_REPO_URL/oniomarchy.db and its detached .sig and require exactly one primary the recorded authority accepts"
        info 'vapt: would fetch the oniomarchy-keyring archive the database names (<filename-unknown-until-then>) and its .sig, sealed against the database digest'
        info 'vapt: would audit the sealed keyring archive (identity, layout, dependencies, scriptlet, hooks, signer, revocations) before any trust change'
        info 'vapt: an unchanged audited keyring changes no trust; a changed one would be installed with --noscriptlet, then pacman-key --populate oniomarchy'
        info "vapt: would record the verified database and this private stanza under $VAPT_ONIOMARCHY_SOURCES:"
        printf '[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch\n' | sed 's/^/    | /'
        return 0
    fi
    info "vapt: would fetch $VAPT_ONIOMARCHY_KEY_URL over HTTPS (no redirect, no keyserver)"
    info "vapt: would require exactly one primary key, $(grep -m1 -E '^[A-F0-9]{40}$' "$VAPT_DIR/files/oniomarchy-signers.txt"), not revoked or expired"
    info "vapt: would fetch $VAPT_ONIOMARCHY_REPO_URL/oniomarchy.db and its detached .sig (no signature: the source stays unavailable)"
    info 'vapt: would require exactly one accepted primary on the database signature before reading any filename from it'
    info 'vapt: would fetch the oniomarchy-keyring archive the database names (<filename-unknown-until-then>) and its .sig, sealed against the database digest'
    info 'vapt: would audit the sealed keyring archive (identity, layout, dependencies, scriptlet, hooks, revocations) before any trust change'
    info 'vapt: would run sudo pacman-key --add/--lsign-key for the pinned primary only, install the sealed keyring with --noscriptlet, then pacman-key --populate oniomarchy'
    info "vapt: would record the keyring authority and this private stanza under $VAPT_ONIOMARCHY_SOURCES:"
    printf '[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch\n' | sed 's/^/    | /'
    info "vapt: $VAPT_ONIOMARCHY_DISCLOSURE"
}

# vapt_oniomarchy_store_database DB SIG SIGNER — root copies the verified
# database bytes into the private cache and records exactly which bytes were
# verified and by which accepted primary.
vapt_oniomarchy_store_database() {
    local db="$1" sig="$2" signer="$3" dbsum sigsum
    dbsum="$(vapt_meta file-digest "$(vapt_read_path "$db")")" || return 2
    sigsum="$(vapt_meta file-digest "$(vapt_read_path "$sig")")" || return 2
    vapt_root_meta state-write "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/sync/oniomarchy.db")" <"$(vapt_read_path "$db")" || return 1
    vapt_root_meta state-write "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/sync/oniomarchy.db.sig")" <"$(vapt_read_path "$sig")" || return 1
    printf 'haseen-vapt-oniomarchy-database-v1\ndb\t%s\nsig\t%s\nsigner\t%s\n' "$dbsum" "$sigsum" "$signer" |
        vapt_root_meta state-write "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.database")" || return 1
}

# vapt_oniomarchy_database STAGE KEYS — fetch the database and its detached
# signature, have root copy both into this run's root stage, and verify the
# root-owned copies against the accepted primaries. Sets VAPT_ONIO_DB,
# VAPT_ONIO_SIG and VAPT_ONIO_SIGNER. 3 = unreachable (nothing changed).
vapt_oniomarchy_database() {
    local stage="$1" keys="$2" file
    vapt_oniomarchy_fetch "$VAPT_ONIOMARCHY_REPO_URL/oniomarchy.db" "$stage/oniomarchy.db" || return 3
    if ! vapt_oniomarchy_fetch "$VAPT_ONIOMARCHY_REPO_URL/oniomarchy.db.sig" "$stage/oniomarchy.db.sig"; then
        VAPT_ONIOMARCHY_REASON='database detached signature unavailable; DatabaseRequired is never relaxed'
        return 2
    fi
    vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_CACHE/source" || return 1
    for file in oniomarchy.db oniomarchy.db.sig; do
        vapt_root_meta state-write "$(vapt_read_path "$VAPT_CACHE/source/$file")" <"$stage/$file" || return 1
    done
    VAPT_ONIO_DB="$VAPT_CACHE/source/oniomarchy.db" VAPT_ONIO_SIG="$VAPT_CACHE/source/oniomarchy.db.sig"
    VAPT_ONIO_SIGNER="$(vapt_oniomarchy_verify "$(vapt_read_path "$VAPT_ONIO_DB")" "$(vapt_read_path "$VAPT_ONIO_SIG")" \
        "$keys" "$stage/signers")" || {
        VAPT_ONIOMARCHY_REASON='database signature rejected: no single accepted primary'; return 2;
    }
    vapt_meta discover "$(vapt_read_path "$VAPT_ONIO_DB")" oniomarchy-keyring >/dev/null 2>&1 || {
        VAPT_ONIOMARCHY_REASON='authenticated database has no concrete oniomarchy-keyring record'; return 2;
    }
}

# vapt_oniomarchy_keys STAGE KEYS — the accepted primaries (authority record,
# else the reviewed pin) and their public keys in a staged GPG home: the
# installed, authority-matched keyring file, or for the initial approval the
# fixed-URL key after its single primary matched the pin.
vapt_oniomarchy_keys() {
    local stage="$1" keys="$2" signers
    run install -d -m 0700 "$stage" "$keys" || return 1
    signers="$(vapt_meta oniomarchy-signers)" || { VAPT_ONIOMARCHY_REASON='keyring authority unverified; manual review required'; return 2; }
    printf '%s\n' "$signers" | write_user_file "$stage/signers" || return 1
    if [[ ${VAPT_ONIO[keyringAuthorityState]:-} == ok ]]; then
        run gpg --homedir "$keys" --batch --import "$(vapt_read_path /usr/share/pacman/keyrings/oniomarchy.gpg)" >/dev/null 2>&1 || return 1
        return 0
    fi
    vapt_oniomarchy_fetch "$VAPT_ONIOMARCHY_KEY_URL" "$stage/oniomarchy.gpg" || {
        VAPT_ONIOMARCHY_REASON='signing key unreachable at the fixed HTTPS URL'; return 3;
    }
    run gpg --homedir "$keys" --batch --with-colons --import-options show-only --import "$stage/oniomarchy.gpg" \
        >"$stage/key.colons" 2>/dev/null || { VAPT_ONIOMARCHY_REASON='fetched signing key unreadable'; return 2; }
    VAPT_ONIO_PRIMARY="$(vapt_meta key-primary "$stage/key.colons" 2>&1)" || {
        VAPT_ONIOMARCHY_REASON="fetched signing key rejected: $VAPT_ONIO_PRIMARY"; return 2;
    }
    run gpg --homedir "$keys" --batch --import "$stage/oniomarchy.gpg" >/dev/null 2>&1 || return 1
}

# vapt_oniomarchy_lock — the shared root lock for a source step. A busy (or
# unsafe) lock is "unavailable" with nothing changed (3), never "unverified".
vapt_oniomarchy_lock() {
    local rc=0
    VAPT_APPLY_REASON=''
    vapt_root_lock || rc=$?
    if ((rc == 2)); then
        VAPT_ONIOMARCHY_REASON="privileged transaction busy (${VAPT_APPLY_REASON:-lock unavailable}); nothing changed"
        return 3
    fi
    return "$rc"
}

# vapt_oniomarchy_recheck — the offline canary again, under the root lock: the
# state the caller decided on may have changed before the lock was taken.
vapt_oniomarchy_recheck() {
    vapt_oniomarchy_canary || { VAPT_ONIOMARCHY_REASON='private source state unreadable; preserved'; return 2; }
    case "${VAPT_ONIO[state]}" in
    unsupported-architecture | broken) VAPT_ONIOMARCHY_REASON="${VAPT_ONIO[reason]}"; return 2 ;;
    esac
    if [[ ${VAPT_ONIO[keyringAuthorityState]} == mismatch ]]; then
        VAPT_ONIOMARCHY_REASON="keyring authority unverified (${VAPT_ONIO[reason]}); manual review required"
        return 2
    fi
}

# vapt_oniomarchy_bootstrap_steps — approve (or re-approve) the private
# source: trust anchor, verified database, audited keyring, authority record,
# cached database and finally the private descriptor. Returns 0 approved,
# 1 failed mutation, 2 refused, 3 unavailable before any trust change. Sets
# VAPT_ONIO_TRUST_CHANGED to what changed in the shared keyring, once it has.
vapt_oniomarchy_bootstrap_steps() {
    local rc=0
    vapt_oniomarchy_lock || return $?
    vapt_oniomarchy_recheck || return $?
    if vapt_upgrade_pending; then
        VAPT_PACMAN_BLOCKED=1
        VAPT_ONIOMARCHY_REASON='recorded full upgrade remains incomplete; source not prepared'
        return 2
    fi
    vapt_pacman_stage || return 1
    local stage="$VAPT_STAGE/oniomarchy" keys="$VAPT_STAGE/oniomarchy/keys" record filename digest authority current=''
    vapt_oniomarchy_keys "$stage" "$keys" || return $?
    vapt_transaction_cache || return $?
    vapt_oniomarchy_database "$stage" "$keys" || return $?
    record="$(vapt_meta discover "$(vapt_read_path "$VAPT_ONIO_DB")" oniomarchy-keyring)" || return 2
    IFS=$'\t' read -r filename digest <<<"$record"
    vapt_oniomarchy_fetch "$VAPT_ONIOMARCHY_REPO_URL/$filename" "$stage/$filename" || return 3
    vapt_oniomarchy_fetch "$VAPT_ONIOMARCHY_REPO_URL/$filename.sig" "$stage/$filename.sig" || {
        VAPT_ONIOMARCHY_REASON='keyring package detached signature unavailable'; return 3;
    }
    vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_CACHE/sealed" || return 1
    vapt_root_meta seal "$stage/$filename" "$VAPT_CACHE/sealed/$filename" "$digest" || {
        VAPT_ONIOMARCHY_REASON='keyring archive differs from the authenticated database digest'; return 2;
    }
    local sealed
    sealed="$(vapt_read_path "$VAPT_CACHE/sealed/$filename")"
    vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || { VAPT_ONIOMARCHY_REASON="$VAPT_APPLY_REASON"; return 2; }
    VAPT_ONIO_KEYRING_SIGNER="$(vapt_oniomarchy_verify "$sealed" "$sealed.sig" "$keys" "$stage/signers")" || {
        VAPT_ONIOMARCHY_REASON='keyring package signature rejected: no single accepted primary'; return 2;
    }
    vapt_root_facts || { VAPT_ONIOMARCHY_REASON="$VAPT_APPLY_REASON"; return 2; }
    # The shared keyring as root sees it: the audit refuses a package that
    # adopts or revokes a primary trust already rests on outside oniomarchy.
    vapt_root_meta keyring-primaries --out "$VAPT_CACHE/keyring-primaries" || {
        VAPT_ONIOMARCHY_REASON='shared pacman keyring unreadable; manual review required'; return 2;
    }
    authority="$(vapt_meta oniomarchy-keyring "$sealed" --db "$(vapt_read_path "$VAPT_ONIO_DB")" \
        --signer "$VAPT_ONIO_KEYRING_SIGNER" --sudo-plugins "$(vapt_read_path "$VAPT_CACHE/sudo-plugins")" \
        --authority-facts "$(vapt_read_path "$VAPT_CACHE/authority-facts")" \
        --keyring-facts "$(vapt_read_path "$VAPT_CACHE/keyring-primaries")" 2>&1)" || {
        VAPT_ONIOMARCHY_REASON="keyring package audit rejected: ${authority//$'\n'/ }"; return 2;
    }
    if [[ ${VAPT_ONIO[keyringAuthorityState]:-} == ok ]]; then
        current="$(vapt_meta state-read "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.authority")")" || return 2
    fi
    # An unchanged authority (same audited keyring) needs no trust operation.
    if [[ $current != "$authority" ]]; then
        local config flags=()
        $ASSUME_YES && flags+=(--noconfirm)
        config="$(vapt_meta config --local)" || return 2
        printf '%s\n' "$config" | write_user_file "$stage/commit.conf" || return 1
        if [[ ${VAPT_ONIO[keyringAuthorityState]:-} != ok ]]; then
            # The initial anchor: only the pinned primary is imported and
            # locally signed; the audited keyring then populates the rest.
            run gpg --homedir "$keys" --batch --output "$stage/signer.gpg" --export "$VAPT_ONIO_PRIMARY" || return 1
            vapt_root_exec /usr/bin/pacman-key --init || return 1
            VAPT_ONIO_TRUST_CHANGED='the pinned oniomarchy key is imported into the shared pacman keyring (global trust changed)'
            vapt_root_exec /usr/bin/pacman-key --add "$stage/signer.gpg" || return 1
            vapt_root_exec /usr/bin/pacman-key --lsign-key "$VAPT_ONIO_PRIMARY" || return 1
        fi
        vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || { VAPT_ONIOMARCHY_REASON="$VAPT_APPLY_REASON"; return 2; }
        # The reviewed population-only scriptlet is replaced by the explicit
        # pacman-key action below; nothing else from the package runs.
        [[ -n $VAPT_ONIO_TRUST_CHANGED ]] ||
            VAPT_ONIO_TRUST_CHANGED='the audited oniomarchy keyring update reached the shared pacman keyring (global trust changed)'
        vapt_root_pacman --config "$stage/commit.conf" -U --noscriptlet "${flags[@]}" -- "$VAPT_CACHE/sealed/$filename" || return 1
        vapt_root_exec /usr/bin/pacman-key --populate oniomarchy || return 1
        printf '%s\n' "$authority" |
            vapt_root_meta state-write "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.authority")" || return 1
    fi
    vapt_oniomarchy_store_database "$VAPT_ONIO_DB" "$VAPT_ONIO_SIG" "$VAPT_ONIO_SIGNER" || return $?
    vapt_root_meta oniomarchy-approve "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.conf")" || return 1
    return "$rc"
}

# vapt_oniomarchy_refresh_steps — an approved source: fetch and verify the
# live database with the recorded accepted primaries, then cache exactly
# those bytes. No trust change happens here: a publisher key rotation is
# applied only by an approval (repo-enable, or the approval an opted-in run
# asks for when the source is not approved), so a refresh that cannot verify,
# or that sees a keyring package other than the recorded authority, names
# repo-enable (VAPT_ONIO_ROTATION_NOTE).
vapt_oniomarchy_refresh_steps() {
    local rc=0 record digest authority
    vapt_oniomarchy_lock || return $?
    vapt_oniomarchy_recheck || return $?
    if [[ ${VAPT_ONIO[descriptor]} != approved || ${VAPT_ONIO[keyringAuthorityState]} != ok ]]; then
        VAPT_ONIOMARCHY_REASON="${VAPT_ONIO[reason]}"
        return 2
    fi
    if vapt_upgrade_pending; then
        VAPT_PACMAN_BLOCKED=1
        VAPT_ONIOMARCHY_REASON='recorded full upgrade remains incomplete; source not refreshed'
        return 2
    fi
    vapt_pacman_stage || return 1
    local stage="$VAPT_STAGE/oniomarchy" keys="$VAPT_STAGE/oniomarchy/keys"
    vapt_oniomarchy_keys "$stage" "$keys" || return $?
    vapt_transaction_cache || return $?
    vapt_oniomarchy_database "$stage" "$keys" || rc=$?
    if ((rc)); then
        [[ $rc != 2 || $VAPT_ONIOMARCHY_REASON != 'database signature rejected'* ]] ||
            VAPT_ONIOMARCHY_REASON+='; a refresh never changes trust: if the publisher rotated its key, review and apply the rotation with haseen vapt repo-enable oniomarchy'
        return "$rc"
    fi
    record="$(vapt_meta discover "$(vapt_read_path "$VAPT_ONIO_DB")" oniomarchy-keyring 2>/dev/null)" &&
        IFS=$'\t' read -r _ digest <<<"$record" &&
        authority="$(vapt_meta state-read "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.authority")" 2>/dev/null)" &&
        [[ -n $digest && $authority != *$'\nsha256\t'"$digest"$'\n'* ]] &&
        VAPT_ONIO_ROTATION_NOTE='the published oniomarchy-keyring differs from the recorded authority; a refresh never applies it: review it with haseen vapt repo-enable oniomarchy'
    vapt_oniomarchy_store_database "$VAPT_ONIO_DB" "$VAPT_ONIO_SIG" "$VAPT_ONIO_SIGNER"
}

# vapt_oniomarchy_run FUNCTION — one root stage per step, always removed.
vapt_oniomarchy_run() {
    local rc=0
    VAPT_CACHE=''
    "$1" || rc=$?
    vapt_transaction_cleanup || { ((rc)) || rc=1; }
    VAPT_CACHE=''
    return "$rc"
}

# vapt_oniomarchy_approve — run the approval. Once the shared keyring changed,
# any later refusal or failure is a mutation failure (1) whose reason says
# the trust change happened but the source is not approved.
vapt_oniomarchy_approve() {
    local rc=0
    VAPT_ONIO_TRUST_CHANGED='' VAPT_ONIOMARCHY_REASON=''
    vapt_oniomarchy_run vapt_oniomarchy_bootstrap_steps || rc=$?
    if ((rc)) && [[ -n $VAPT_ONIO_TRUST_CHANGED ]]; then
        VAPT_ONIOMARCHY_REASON="$VAPT_ONIO_TRUST_CHANGED, but the source is not approved: ${VAPT_ONIOMARCHY_REASON:-${VAPT_APPLY_REASON:-preparation failed}}"
        return 1
    fi
    return "$rc"
}

# vapt_oniomarchy_scope — join this operation's snapshot. The scope is set
# only once that snapshot succeeded and is cleared when it fails.
vapt_oniomarchy_scope() {
    VAPT_ONIOMARCHY_SCOPE=''
    if ! VAPT_ONIOMARCHY_SCOPE=1 vapt_snapshot; then
        VAPT_ONIOMARCHY_STATE=unavailable VAPT_ONIOMARCHY_REASON='source metadata snapshot failed; not used'
        return 1
    fi
    VAPT_ONIOMARCHY_SCOPE=1
}

# vapt_oniomarchy_prepare — the provisioning prelude for this operation's
# choice. Sets VAPT_ONIOMARCHY_STATE (not-selected, absent, declined,
# unsupported-architecture, unavailable, unverified, broken, usable),
# VAPT_ONIOMARCHY_REASON and, only when usable, VAPT_ONIOMARCHY_SCOPE=1.
vapt_oniomarchy_prepare() {
    local rc=0
    VAPT_ONIOMARCHY_SCOPE=''
    if [[ ${VAPT_ONIOMARCHY_OPT:-0} != 1 ]]; then
        VAPT_ONIOMARCHY_STATE=not-selected VAPT_ONIOMARCHY_REASON='not selected for this operation (--with-oniomarchy)'
        return 0
    fi
    if ! vapt_oniomarchy_canary; then
        VAPT_ONIOMARCHY_STATE=broken VAPT_ONIOMARCHY_REASON='private source state unreadable; preserved'
        return 0
    fi
    VAPT_ONIOMARCHY_STATE="${VAPT_ONIO[state]}" VAPT_ONIOMARCHY_REASON="${VAPT_ONIO[reason]}"
    case "$VAPT_ONIOMARCHY_STATE" in
    unsupported-architecture | broken) return 0 ;;
    esac
    if [[ $VAPT_PACMAN_BLOCKED == 1 ]]; then
        VAPT_ONIOMARCHY_STATE=unavailable VAPT_ONIOMARCHY_REASON='recorded full upgrade remains incomplete; source not prepared'
        return 0
    fi
    if $DRY_RUN; then
        if [[ $VAPT_ONIOMARCHY_STATE == absent ]]; then
            vapt_oniomarchy_plan
            VAPT_ONIOMARCHY_REASON='approval planned; no source/trust evidence fabricated'
        elif [[ $VAPT_ONIOMARCHY_STATE == usable ]]; then
            VAPT_ONIOMARCHY_REASON='dry-run plans from the cached signed database verified at the last refresh; not re-verified'
            vapt_oniomarchy_scope || return 1
        fi
        return 0
    fi
    if [[ $VAPT_ONIOMARCHY_STATE == absent ]]; then
        confirm "$VAPT_ONIOMARCHY_DISCLOSURE Approve the pinned oniomarchy source?" || {
            VAPT_ONIOMARCHY_STATE=declined VAPT_ONIOMARCHY_REASON='source approval declined for this operation'
            return 0
        }
        vapt_oniomarchy_approve || rc=$?
    elif [[ ${VAPT_ONIO[keyringAuthorityState]:-} != ok ]]; then
        # Missing proof after a local keyring change is never repaired here.
        return 0
    else
        VAPT_ONIO_TRUST_CHANGED='' VAPT_ONIOMARCHY_REASON='' VAPT_ONIO_ROTATION_NOTE=''
        vapt_oniomarchy_run vapt_oniomarchy_refresh_steps || rc=$?
    fi
    case "$rc" in
    0) ;;
    3) VAPT_ONIOMARCHY_STATE=unavailable; VAPT_ONIOMARCHY_REASON="${VAPT_ONIOMARCHY_REASON:-source unreachable; nothing changed}"; return 0 ;;
    2) VAPT_ONIOMARCHY_STATE=unverified; VAPT_ONIOMARCHY_REASON="${VAPT_ONIOMARCHY_REASON:-${VAPT_APPLY_REASON:-source verification refused}}"; return 0 ;;
    *) VAPT_ONIOMARCHY_STATE=unavailable; VAPT_ONIOMARCHY_REASON="${VAPT_ONIOMARCHY_REASON:-source preparation failed}"; return 1 ;;
    esac
    vapt_oniomarchy_canary || { VAPT_ONIOMARCHY_STATE=broken VAPT_ONIOMARCHY_REASON='private source state unreadable'; return 0; }
    VAPT_ONIOMARCHY_STATE="${VAPT_ONIO[state]}"
    if [[ $VAPT_ONIOMARCHY_STATE == usable ]]; then
        VAPT_ONIOMARCHY_REASON="signed database verified for this operation${VAPT_ONIO_ROTATION_NOTE:+; $VAPT_ONIO_ROTATION_NOTE}"
        vapt_oniomarchy_scope || return 1
    elif [[ -n $VAPT_ONIO_TRUST_CHANGED ]]; then
        # Trust changed, yet the recorded evidence does not make it usable.
        VAPT_ONIOMARCHY_REASON="$VAPT_ONIO_TRUST_CHANGED, but the source is not approved: ${VAPT_ONIO[reason]}"
        return 1
    else
        VAPT_ONIOMARCHY_REASON="${VAPT_ONIO[reason]}"
    fi
}

# --- repository commands -------------------------------------------------------
vapt_oniomarchy_status_command() {
    local json="$1" row
    if [[ $json == true ]]; then vapt_meta oniomarchy-status --json; return; fi
    vapt_oniomarchy_canary || { warn 'oniomarchy source state unreadable'; return 1; }
    printf 'oniomarchy: %s\n' "${VAPT_ONIO[state]}"
    for row in architecture hostStanza descriptorPolicy databaseSignatureState keyringAuthorityState; do
        printf '  %s: %s\n' "$row" "${VAPT_ONIO[$row]}"
    done
    printf '  selected: no (inspection never selects the source; use haseen vapt install --with-oniomarchy)\n'
    printf '  reason: %s\n' "${VAPT_ONIO[reason]}"
}

vapt_oniomarchy_enable_command() {
    local rc=0
    vapt_oniomarchy_canary || { warn 'oniomarchy source state unreadable; nothing changed'; return 1; }
    case "${VAPT_ONIO[state]}" in
    unsupported-architecture | broken) warn "oniomarchy ${VAPT_ONIO[state]}: ${VAPT_ONIO[reason]}; nothing changed"; return 1 ;;
    esac
    if [[ ${VAPT_ONIO[keyringAuthorityState]} == mismatch ]]; then
        warn "oniomarchy keyring authority unverified (${VAPT_ONIO[reason]}); manual review required; nothing changed"
        return 1
    fi
    if $DRY_RUN; then vapt_oniomarchy_plan; return 0; fi
    confirm "$VAPT_ONIOMARCHY_DISCLOSURE Approve the pinned oniomarchy source?" || { warn 'declined; nothing changed'; return 1; }
    vapt_oniomarchy_approve || rc=$?
    vapt_pacman_cleanup || ((rc)) || rc=1
    if ((rc)); then
        if [[ -n $VAPT_ONIO_TRUST_CHANGED ]]; then
            warn "oniomarchy: ${VAPT_ONIOMARCHY_REASON}"
        else
            warn "oniomarchy not approved: ${VAPT_ONIOMARCHY_REASON:-${VAPT_APPLY_REASON:-preparation failed}}"
        fi
        return 1
    fi
    # Approval is claimed only when the recorded evidence makes it usable
    # (a rotation away from the signer of the cached database does not).
    if ! vapt_oniomarchy_canary || [[ ${VAPT_ONIO[state]} != usable ]]; then
        warn "oniomarchy: ${VAPT_ONIO_TRUST_CHANGED:-the approval was recorded}, but the source is not approved: ${VAPT_ONIO[state]:-unreadable}: ${VAPT_ONIO[reason]:-private source state unreadable}"
        return 1
    fi
    info 'oniomarchy approved for dedicated VAPT transactions; use haseen vapt install --with-oniomarchy per operation'
}

vapt_oniomarchy_disable_command() {
    vapt_oniomarchy_canary || { warn 'oniomarchy source state unreadable; nothing changed'; return 1; }
    case "${VAPT_ONIO[descriptor]}" in
    absent) info 'oniomarchy is not approved; nothing to disable'; return 0 ;;
    conflict) warn 'private oniomarchy descriptor or source state changed or unsafe; preserved, not removed'; return 1 ;;
    esac
    if $DRY_RUN; then
        info 'vapt: oniomarchy disable plan (dry-run: nothing is removed or written)'
        info "vapt: would remove the unchanged private descriptor $VAPT_ONIOMARCHY_SOURCES/oniomarchy.conf under the root lock"
        info 'vapt: would keep packages installed from it and the pacman keyring trust (revoking that key is a separate administrator decision)'
        return 0
    fi
    confirm 'Disable the private oniomarchy source? Installed packages and pacman keyring trust remain.' || {
        warn 'declined; nothing changed'; return 1;
    }
    vapt_root_lock || { warn "${VAPT_APPLY_REASON:-privileged transaction lock unavailable}; nothing changed"; return 1; }
    vapt_root_meta oniomarchy-withdraw "$(vapt_read_path "$VAPT_ONIOMARCHY_SOURCES/oniomarchy.conf")" || {
        warn 'private descriptor changed meanwhile; preserved'; return 1;
    }
    info 'oniomarchy private descriptor removed. Packages installed from it and the pacman keyring trust remain;'
    info 'revoking that key is a separate administrator decision (pacman-key), not part of disabling.'
}
