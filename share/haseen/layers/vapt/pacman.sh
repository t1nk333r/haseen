# shellcheck shell=bash disable=SC2034  # VAPT_* outputs are consumed by provision.sh/native.sh/blackarch.sh
# VAPT never calls the general package/AUR pipeline. Every target is qualified.
# oniomarchy is admissible only through its private descriptor, for an
# operation that opted in (VAPT_ONIOMARCHY_SCOPE); pins never name it.
vapt_repo_allowed() { [[ $1 =~ ^(core|extra|multilib|blackarch|chaotic-aur|oniomarchy|cachyos(-[a-z0-9-]+)?)$ ]]; }
# A staged BlackArch bootstrap makes its reviewed stanza visible to the private
# review/frozen commit only; /etc/pacman.conf changes after that commit. The
# approved private oniomarchy stanza joins VAPT's own configuration only for
# an operation whose source state is usable (or the exact recorded recovery).
vapt_meta() {
    python3 "$VAPT_DIR/metadata.py" "$@" --root "$HASEEN_SYSROOT" ${VAPT_BLACKARCH_STAGED:+--with-blackarch} \
        ${VAPT_ONIOMARCHY_SCOPE:+--with-oniomarchy}
}
vapt_read_path() { if in_sysroot; then sysroot_path "$1"; else printf '%s\n' "$1"; fi; }
vapt_path_ancestors_safe() {
    local path="${1%/*}" seen
    while [[ -n $path && $path != / ]]; do
        seen="$(vapt_read_path "$path")"
        if [[ -L $seen || ( -e $seen && ! -d $seen ) ]]; then
            warn "VAPT symlinked/non-directory ancestor preserved: $path"; return 1
        fi
        path="${path%/*}"
    done
}
vapt_state_path_safe() {
    vapt_path_ancestors_safe "$1" || return 1
    vapt_meta state-safe "$(vapt_read_path "$1")"
}
vapt_state_write() {
    vapt_state_path_safe "$1" || return 1
    if $DRY_RUN; then write_user_file "$1"
    else run python3 "$VAPT_DIR/metadata.py" state-write "$(vapt_read_path "$1")"
    fi
}
vapt_state_clear() {
    vapt_state_path_safe "$1" || return 1
    if $DRY_RUN; then run rm -f -- "$1"
    else run python3 "$VAPT_DIR/metadata.py" state-clear "$(vapt_read_path "$1")"
    fi
}
vapt_lifecycle_lock() {
    # One same-user ownership/report transaction; offline planning neither
    # opens a lock nor waits behind a mutator. The inode is never replaced.
    $DRY_RUN && return 0
    local path
    path="$(vapt_read_path "$HASEEN_USER_STATE/vapt/lifecycle.lock")" || return 1
    run python3 "$VAPT_DIR/metadata.py" lock-prepare "$path" || return 1
    exec {VAPT_LOCK_FD}<"$path" || return 1
    if ! vapt_meta lock-fd "$path" "$VAPT_LOCK_FD"; then
        exec {VAPT_LOCK_FD}<&-
        warn 'VAPT apply/remove busy or lock authority unsafe; no lifecycle mutation performed'
        return 1
    fi
}
vapt_pacman_config() { vapt_meta config; }
# Every privileged VAPT step: absolute env, canonical PATH, C locale and no
# inherited loader/conversion overrides (LD_PRELOAD, LD_LIBRARY_PATH,
# LD_AUDIT, GLIBC_TUNABLES, LD_PROFILE, LD_PROFILE_OUTPUT, GCONV_PATH,
# LOCPATH), so neither the caller's PATH nor its loader environment selects
# what root runs. Startup selectors are removed too: PYTHONEXECUTABLE and
# __PYVENV_LAUNCHER__ (CPython's getpath applies them to the executable
# path, and so to its ._pth/pyvenv.cfg search, even under -I), and BASH_ENV,
# ENV, SHELLOPTS and PS4 (a non-interactive root shell, e.g. pacman-key or a
# reviewed hook helper, sources BASH_ENV/ENV and honours an inherited
# SHELLOPTS=xtrace with a command-substituting PS4). The inner env runs
# after sudo/PAM built the environment, so it is the authoritative scrub;
# SHELLOPTS is readonly in bash, so only the inner env drops it.
# sudo keeps the caller's umask (OR 022): pin 022 so libalpm finalizes
# downloads/DBs 0644 for the user-side review and DownloadUser fetches.
vapt_root_exec() (
    umask 022
    # The privilege gateway itself (sudo, via run_root) is resolved from
    # /usr/bin only, never from the caller's PATH.
    PATH=/usr/bin
    unset PYTHONEXECUTABLE __PYVENV_LAUNCHER__ BASH_ENV ENV PS4 GLIBC_TUNABLES LD_PROFILE LD_PROFILE_OUTPUT
    run_root /usr/bin/env -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT -u GLIBC_TUNABLES -u LD_PROFILE \
        -u LD_PROFILE_OUTPUT -u GCONV_PATH -u LOCPATH -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ \
        -u BASH_ENV -u ENV -u SHELLOPTS -u PS4 LC_ALL=C PATH=/usr/bin "$@"
)
vapt_root_pacman() { vapt_root_exec pacman "$@"; }
vapt_sealed_safe() {
    # Sealed artifacts are reopened by name: their whole ancestry must still
    # be non-replaceable right before the audit and the privileged commit.
    $DRY_RUN && return 0
    vapt_meta sealed-safe "$@" >/dev/null 2>&1 || {
        VAPT_APPLY_REASON='sealed artifact ancestry became replaceable; nothing committed'; return 2;
    }
}
# Root metadata steps: absolute interpreter, -I (ignores the PYTHON* variables
# it governs, user site and the script directory) and -S (no site module),
# running the layer's own module. getpath still honours PYTHONEXECUTABLE and
# __PYVENV_LAUNCHER__ (vapt_root_exec removes both) and its startup layout
# selectors (._pth, pyvenv.cfg, build/prefix landmarks): the audit refuses
# any such layout for this interpreter (metadata.py, root Python startup layout).
vapt_root_meta() { vapt_root_exec /usr/bin/python3 -I -S "$VAPT_DIR/metadata.py" "$@" --root "$HASEEN_SYSROOT"; }
vapt_state_repair() {
    # Root state lives only at /var/lib/haseen (a fixture sysroot prefixes it
    # through vapt_read_path): an environment override never steers a root
    # chmod or the shared lock elsewhere. Existing root state created under a
    # 077 umask (0700) would hide the shared lock and recovery record from the
    # user-side checks: root creates/repairs its state directories first.
    $DRY_RUN && return 0
    if [[ $HASEEN_STATE_DIR != /var/lib/haseen ]]; then
        VAPT_APPLY_REASON="VAPT root state is only supported at /var/lib/haseen; HASEEN_STATE_DIR override ($HASEEN_STATE_DIR) refused"
        return 2
    fi
    vapt_root_meta state-repair "$(vapt_read_path "$HASEEN_STATE_DIR")" "$(vapt_read_path "$HASEEN_STATE_DIR/vapt")" || {
        VAPT_APPLY_REASON='haseen root state directories are unsafe or not repairable; manual review required'; return 2;
    }
}
vapt_upgrade_pending() {
    # A recorded, incomplete reviewed full-upgrade commit (any haseen user).
    $DRY_RUN && return 1
    local pending
    pending="$(vapt_read_path "$HASEEN_STATE_DIR/vapt/upgrade-pending")"
    [[ -e $pending || -L $pending ]]
}
vapt_root_lock() {
    # One privileged review→commit/recovery at a time across all haseen users:
    # a root-owned shared mutex, held until this process exits. It cannot
    # serialize other package managers; administrators must not run one
    # concurrently with haseen provisioning (docs/vapt.md).
    $DRY_RUN && return 0
    [[ -z ${VAPT_ROOT_LOCK_FD:-} ]] || return 0
    local lock="$HASEEN_STATE_DIR/vapt/transaction.lock" path
    vapt_state_repair || return $?
    vapt_state_path_safe "$lock" || return 2
    path="$(vapt_read_path "$lock")"
    vapt_root_meta shared-lock-prepare "$path" || return 1
    exec {VAPT_ROOT_LOCK_FD}<"$path" || { VAPT_ROOT_LOCK_FD=''; return 1; }
    if ! vapt_meta lock-fd "$path" "$VAPT_ROOT_LOCK_FD" shared; then
        exec {VAPT_ROOT_LOCK_FD}<&-
        VAPT_ROOT_LOCK_FD=''
        VAPT_APPLY_REASON='another haseen VAPT privileged transaction is running or its lock is unsafe'
        return 2
    fi
}
vapt_pacman_stage() {
    [[ -n ${VAPT_STAGE:-} ]] && return 0
    local base="${XDG_CACHE_HOME:-$HOME/.cache}/haseen/vapt"
    vapt_state_path_safe "$base/.stage" || return 1
    if $DRY_RUN; then
        VAPT_STAGE="$base/PLAN"
        run install -d -m 0700 "$VAPT_STAGE"
    else
        run install -d -m 0700 "$(vapt_read_path "$base")" || return 1
        VAPT_STAGE="$(run mktemp -d "$(vapt_read_path "$base")/transaction.XXXXXXXX")" || return 1
    fi
}
vapt_pacman_cleanup() {
    [[ -n ${VAPT_STAGE:-} ]] || return 0
    run rm -rf -- "$VAPT_STAGE" || return 1
    VAPT_STAGE=''
}
vapt_transaction_cleanup() {
    [[ ${VAPT_CACHE:-} =~ ^/var/cache/haseen-vapt\.[A-Za-z0-9]+$ ]] || return 0
    vapt_root_exec /usr/bin/rm -rf -- "$VAPT_CACHE"
}
vapt_transaction_cache() {
    # A root-created unique stage reachable by pacman 7 DownloadUser. The
    # private user config/plan never becomes sandbox-writable.
    VAPT_CACHE=''
    vapt_meta state-safe "$(vapt_read_path /var/cache)/.vapt-stage" || return 2
    local cache
    cache="$(vapt_root_exec /usr/bin/mktemp -d /var/cache/haseen-vapt.XXXXXXXX)" || return 1
    [[ $cache =~ ^/var/cache/haseen-vapt\.[A-Za-z0-9]+$ ]] || return 1
    VAPT_CACHE="$cache"
    vapt_root_exec /usr/bin/chmod 0755 "$VAPT_CACHE" || return 1
}
vapt_transaction_prepare() {
    vapt_pacman_stage || return 1
    local content
    content="$(vapt_pacman_config)" || { VAPT_APPLY_REASON='unsafe/unreadable pacman configuration'; return 2; }
    printf '%s\n' "$content" | write_user_file "$VAPT_STAGE/pacman.conf" || return 1
    VAPT_TRANSACTION_REPOS=()
    local line section
    while IFS= read -r line; do
        if [[ $line == \[*\] ]]; then
            section="${line:1:${#line}-2}"
            vapt_repo_allowed "$section" && VAPT_TRANSACTION_REPOS+=("$section")
        fi
    done <<<"$content"
    vapt_transaction_cache || return $?
    VAPT_DB="$VAPT_CACHE/db" VAPT_BASE_DB="$VAPT_CACHE/base"
    vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_DB" "$VAPT_DB/sync" "$VAPT_BASE_DB" "$VAPT_BASE_DB/sync" \
        "$VAPT_CACHE/packages" || return 1
    vapt_root_meta cache-permissions "$VAPT_CACHE/packages" || return 1
    # Pre-refresh snapshot first, from one read of the system sync DB: the
    # installed versions' records stay provable after a private -Syuw.
    vapt_root_exec /usr/bin/cp -a -- /var/lib/pacman/sync/. "$VAPT_BASE_DB/sync/" || return 1
    vapt_root_exec /usr/bin/cp -a -- "$VAPT_BASE_DB/sync/." "$VAPT_DB/sync/" || return 1
    vapt_root_exec /usr/bin/cp -a -- /var/lib/pacman/local "$VAPT_DB/local" || return 1
    vapt_root_exec /usr/bin/cp -a -- "$VAPT_DB/local" "$VAPT_BASE_DB/local" || return 1
    if [[ -n ${VAPT_ONIOMARCHY_SCOPE:-} ]]; then
        # The private source's database is exactly the signed bytes verified
        # for this operation (never a host sync DB of the same name).
        local db
        for db in "$VAPT_DB/sync" "$VAPT_BASE_DB/sync"; do
            vapt_root_exec /usr/bin/cp -- /var/lib/haseen/vapt/sources/sync/oniomarchy.db \
                /var/lib/haseen/vapt/sources/sync/oniomarchy.db.sig "$db/" || return 1
        done
    fi
}
vapt_transaction_seal() {
    # Root copies each planned artifact (+ .sig) out of the DownloadUser cache
    # into a root-only sealed set, binding the copied bytes to the reviewed
    # DB digest. Audit and commit then use only the sealed copies.
    local plan="$1" repo name version artifact digest seen=' '
    vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_CACHE/sealed" || return 1
    while IFS=$'\t' read -r repo name version artifact; do
        [[ -n $repo ]] || continue
        vapt_repo_allowed "$repo" || { VAPT_APPLY_REASON='forbidden transaction source'; return 2; }
        # The plan names the artifact (%f), never a location: pacman prints
        # %l as file:// for already-cached artifacts. Downloads still come
        # only from the repository's configured HTTPS servers.
        [[ $artifact =~ ^[A-Za-z0-9@._+:-]+\.pkg\.tar\.(zst|xz|gz)$ && $name =~ $PKG_NAME_RE ]] || { VAPT_APPLY_REASON='invalid package artifact'; return 2; }
        [[ $seen != *" $name "* && $seen != *" $artifact "* ]] || { VAPT_APPLY_REASON='duplicate transaction plan row'; return 2; }
        seen+="$name $artifact "
        digest="$(vapt_meta artifact-digest "$repo" "$name" "$version" "$artifact" --dbpath "$(vapt_read_path "$VAPT_DB")" 2>&1)" || {
            VAPT_APPLY_REASON="$digest"; return 2;
        }
        [[ -r $(vapt_read_path "$VAPT_CACHE/packages/$artifact") ]] || { VAPT_APPLY_REASON='downloaded archive missing'; return 2; }
        vapt_root_meta seal "$VAPT_CACHE/packages/$artifact" "$VAPT_CACHE/sealed/$artifact" "$digest" || {
            VAPT_APPLY_REASON="downloaded artifact differs from the reviewed repository digest: $artifact"; return 2;
        }
    done <"$plan"
}
vapt_root_facts() {
    # Facts only root can observe, written into this transaction's root stage
    # for the unprivileged audit (which keeps parsing untrusted archives as
    # the user): sudoers group_plugin modules (sudoers is root-only), and the
    # retained access/security attributes of the guarded haseen program,
    # policy and vendor anchors (trusted.* is invisible without root).
    [[ ${VAPT_CACHE:-} =~ ^/var/cache/haseen-vapt\.[A-Za-z0-9]+$ ]] || {
        VAPT_APPLY_REASON='root transaction stage unavailable for root facts'; return 2;
    }
    vapt_root_meta sudo-plugins --out "$VAPT_CACHE/sudo-plugins" || {
        VAPT_APPLY_REASON='sudoers group_plugin configuration unsupported; manual review required'; return 2;
    }
    vapt_root_meta authority-facts --out "$VAPT_CACHE/authority-facts" || {
        VAPT_APPLY_REASON='retained haseen program/policy attributes unreadable; manual review required'; return 2;
    }
}
vapt_transaction_references() {
    # Retained runtime/stock owners are proven against the authenticated base
    # artifact of their INSTALLED version (pre-refresh snapshot or reviewed
    # DB): fetch any reference not already available, then seal it.
    local plan="$1" rows db repo name version artifact digest row base=() reviewed=() sealed=()
    shift
    vapt_root_exec /usr/bin/install -d -m 0755 "$VAPT_CACHE/reference" || return 1
    rows="$(vapt_meta reference-missing "$@" --plan "$plan" --dbpath "$(vapt_read_path "$VAPT_DB")" \
        --base-dbpath "$(vapt_read_path "$VAPT_BASE_DB")" --reference "$(vapt_read_path "$VAPT_CACHE/reference")" \
        --sudo-plugins "$(vapt_read_path "$VAPT_CACHE/sudo-plugins")" \
        --authority-facts "$(vapt_read_path "$VAPT_CACHE/authority-facts")")" || return 2
    [[ -n $rows ]] || return 0
    while IFS=$'\t' read -r db repo name version artifact digest; do
        [[ $db == base || $db == reviewed ]] && vapt_repo_allowed "$repo" && [[ $name =~ $PKG_NAME_RE &&
            $artifact =~ ^[A-Za-z0-9@._+:-]+\.pkg\.tar\.(zst|xz|gz)$ ]] || {
            VAPT_APPLY_REASON='malformed base reference request'; return 2;
        }
        if [[ $db == base ]]; then base+=("$repo/$name"); else reviewed+=("$repo/$name"); fi
        sealed+=("$db"$'\t'"$repo/$name $version"$'\t'"$artifact"$'\t'"$digest")
    done <<<"$rows"
    if ((${#reviewed[@]})); then
        vapt_root_pacman --config "$VAPT_STAGE/pacman.conf" --dbpath "$VAPT_DB" -Sw --cachedir "$VAPT_CACHE/packages" --noconfirm -- "${reviewed[@]}" || {
            VAPT_APPLY_REASON='base reference download failed'; return 1;
        }
    fi
    # The installed version through the pre-refresh snapshot: CacheDir or the
    # configured mirrors only. Unavailable is a refusal, never a substitute.
    if ((${#base[@]})) && ! vapt_root_pacman --config "$VAPT_STAGE/pacman.conf" --dbpath "$VAPT_BASE_DB" -Sw \
        --cachedir "$VAPT_CACHE/packages" --noconfirm -- "${base[@]}"; then
        VAPT_APPLY_REASON="installed-version reference unavailable: ${base[*]} is not in CacheDir and not on the configured mirrors; manual review required"
        return 2
    fi
    for row in "${sealed[@]}"; do
        IFS=$'\t' read -r db name artifact digest <<<"$row"
        if [[ ! -r $(vapt_read_path "$VAPT_CACHE/packages/$artifact") ]]; then
            if [[ $db == base ]]; then
                VAPT_APPLY_REASON="installed-version reference unavailable: $name ($artifact) is not in CacheDir and not on the configured mirrors; manual review required"
            else
                VAPT_APPLY_REASON="base reference unavailable: $name ($artifact)"
            fi
            return 2
        fi
        vapt_root_meta seal "$VAPT_CACHE/packages/$artifact" "$VAPT_CACHE/reference/$artifact" "$digest" || {
            if [[ $db == base ]]; then
                VAPT_APPLY_REASON="installed-version reference differs from the pre-refresh repository digest: $artifact"
            else
                VAPT_APPLY_REASON="base reference differs from the reviewed repository digest: $artifact"
            fi
            return 2
        }
    done
}
vapt_transaction_audit() {
    local plan="$1" repo name version artifact reason archives=()
    vapt_transaction_seal "$plan" || return $?
    # Exactly these sealed, audited archives (and names) are what a commit
    # installs; nothing is re-resolved or re-read from the download cache.
    VAPT_COMMIT_ARCHIVES=() VAPT_COMMIT_NAMES=()
    while IFS=$'\t' read -r repo name version artifact; do
        [[ -n $repo ]] || continue
        archives+=("$(vapt_read_path "$VAPT_CACHE/sealed/$artifact")")
        VAPT_COMMIT_ARCHIVES+=("$VAPT_CACHE/sealed/$artifact")
        VAPT_COMMIT_NAMES+=("$name")
    done <"$plan"
    ((${#archives[@]})) || return 0
    vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || return $?
    vapt_root_facts || return $?
    vapt_transaction_references "$plan" "${archives[@]}" || return $?
    reason="$(vapt_meta audit "${archives[@]}" --plan "$plan" --dbpath "$(vapt_read_path "$VAPT_DB")" \
        --base-dbpath "$(vapt_read_path "$VAPT_BASE_DB")" --reference "$(vapt_read_path "$VAPT_CACHE/reference")" \
        --sudo-plugins "$(vapt_read_path "$VAPT_CACHE/sudo-plugins")" \
        --authority-facts "$(vapt_read_path "$VAPT_CACHE/authority-facts")" 2>&1)" || {
        VAPT_APPLY_REASON="$reason"; return 2;
    }
}
vapt_pacman_closure() {
    local target="$1" content reason
    vapt_repo_allowed "${target%%/*}" && [[ $target == */* && ${target##*/} =~ $PKG_NAME_RE ]] || return 2
    if $DRY_RUN; then
        reason="$(vapt_meta closure "$target" 2>&1)" || { VAPT_APPLY_REASON="$reason"; return 2; }
        return 0
    fi
    vapt_transaction_prepare || return $?
    # Diagnostics go to their own file: only the printed plan becomes rows.
    content="$(LC_ALL=C pacman --config "$VAPT_STAGE/pacman.conf" --dbpath "$VAPT_DB" -Sp --print-format $'%r\t%n\t%v\t%f' -- "$target" 2>"$VAPT_STAGE/plan.err")" || {
        VAPT_APPLY_REASON="transaction resolution failed: $(<"$VAPT_STAGE/plan.err")"; return 2;
    }
    printf '%s\n' "$content" | write_user_file "$VAPT_STAGE/transaction.tsv" || return 1
    reason="$(vapt_meta closure "$target" "$VAPT_STAGE/transaction.tsv" --dbpath "$(vapt_read_path "$VAPT_DB")" 2>&1)" || {
        VAPT_APPLY_REASON="$reason"; return 2;
    }
    vapt_closure_warnings "$reason"
    if ! vapt_root_pacman --config "$VAPT_STAGE/pacman.conf" --dbpath "$VAPT_DB" -Sw --cachedir "$VAPT_CACHE/packages" --noconfirm -- "$target"; then
        VAPT_APPLY_REASON='signed package download failed'; return 1
    fi
    vapt_transaction_audit "$VAPT_STAGE/transaction.tsv"
}
vapt_pacman_apply_transaction() {
    local target="$1" observed version="${VAPT_VERSION[$1]:--}" url="${VAPT_URL[$1]:--}" flags=() rc=0
    VAPT_APPLY_REASON=''
    [[ ${VAPT_PACMAN_BLOCKED:-0} == 0 ]] || { VAPT_APPLY_REASON='incomplete full upgrade; package transactions blocked'; return 2; }
    observed="$(vapt_meta installed "${target%%/*}" "${target##*/}" "$version" "$url")" || observed=unknown
    if [[ $observed == exact ]]; then
        # Exact targets still need allowed identity evidence for retained
        # runtime providers, but no package scriptlets or downloads run.
        VAPT_APPLY_REASON="$(vapt_meta closure "$target" 2>&1)" || return 2
        VAPT_APPLY_REASON=''; VAPT_PACMAN_STATE=already-exact; return 0
    fi
    vapt_root_lock || return $?
    # Under the lock: another user's recorded full-upgrade commit blocks.
    if vapt_upgrade_pending; then
        VAPT_PACMAN_BLOCKED=1
        VAPT_APPLY_REASON='recorded full upgrade remains incomplete; package transactions blocked'
        return 2
    fi
    vapt_pacman_closure "$target" || return $?
    VAPT_PACMAN_STATE=planned
    $ASSUME_YES && flags+=(--noconfirm)
    if $DRY_RUN; then
        info "vapt: review allowed closure and package scriptlets/hooks for $target"
        vapt_root_pacman --config '<repository-free-vapt-config>' -U "${flags[@]}" -- "<audited-archives-of:$target>"
        return $?
    fi
    # One root transaction for the whole audited closure, from the exact
    # signature-checked archives (LocalFileSigLevel Required TrustedOnly) under
    # a repository-free config: sync DB drift or provider prompts cannot add
    # or swap a package. Hook views match the single audited transaction.
    local absent config name deps=()
    absent="$(vapt_meta absent "${VAPT_COMMIT_NAMES[@]}")" || { VAPT_APPLY_REASON='installed package metadata unreadable'; return 2; }
    config="$(vapt_meta config --local)" || { VAPT_APPLY_REASON='unsafe/unreadable pacman configuration'; return 2; }
    printf '%s\n' "$config" | write_user_file "$VAPT_STAGE/commit.conf" || return 1
    vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" || return $?
    if ! vapt_root_pacman --config "$VAPT_STAGE/commit.conf" -U "${flags[@]}" -- "${VAPT_COMMIT_ARCHIVES[@]}"; then
        VAPT_APPLY_REASON='pacman install failed'; return 1
    fi
    # -U marks new packages explicit and keeps an upgraded package's reason.
    # Database-only -D restores sync semantics: new dependencies are
    # dependencies, the requested target is explicit; no hook or scriptlet runs.
    while IFS= read -r name; do
        [[ -z $name || $name == "${target##*/}" ]] || deps+=("$name")
    done <<<"$absent"
    if ((${#deps[@]})) && ! vapt_root_pacman --config "$VAPT_STAGE/commit.conf" -D --asdeps -- "${deps[@]}"; then
        VAPT_APPLY_REASON='install reason bookkeeping failed'; return 1
    fi
    for name in "${deps[@]}"; do VAPT_DEPENDENCY_ROWS+=("$name"$'\t'"$target"$'\t'dependency); done
    if ! vapt_root_pacman --config "$VAPT_STAGE/commit.conf" -D --asexplicit -- "${target##*/}"; then
        VAPT_APPLY_REASON='install reason bookkeeping failed'; return 1
    fi
    observed="$(vapt_meta installed "${target%%/*}" "${target##*/}" "$version" "$url")" || observed=unknown
    [[ $observed == exact ]] || { VAPT_APPLY_REASON='installed package identity/version metadata unverified'; return 1; }
    VAPT_PACMAN_STATE=installed
}
vapt_pacman_apply() {
    local rc=0
    VAPT_CACHE=''
    vapt_pacman_apply_transaction "$@" || rc=$?
    vapt_transaction_cleanup || rc=1
    VAPT_CACHE=''
    ((rc != 1)) || VAPT_MUTATION_FAILED=1
    return "$rc"
}
vapt_closure_warnings() {
    # A passed closure prints "safe" after any warning (an identity mismatch
    # on a planned upgrade of an already-installed package); show those.
    local line
    while IFS= read -r line; do
        [[ -z $line || $line == safe ]] || warn "vapt: $line"
    done <<<"$1"
}
vapt_pacman_upgrade_transaction() {
    # The private oniomarchy source never joins a full upgrade: its Usage
    # excludes Upgrade and no prelude selects it before one runs.
    [[ -z ${VAPT_ONIOMARCHY_SCOPE:-} ]] || { VAPT_APPLY_REASON='the private oniomarchy source never joins a full upgrade'; return 2; }
    if $DRY_RUN; then
        info 'vapt: review full allowed-repository system upgrade (not reversible)'
        vapt_root_pacman --config '<reviewed-vapt-config>' -Syyu
        [[ ${VAPT_BLACKARCH_STAGED:-} != 1 ]] || vapt_blackarch_activate
        return 0
    fi
    vapt_root_lock || return $?
    # Under the shared lock: another user's recorded commit is never
    # overwritten or cleared by a fresh review; only recovery resumes it.
    if [[ ${VAPT_RECOVERING:-} != 1 ]] && vapt_upgrade_pending; then
        VAPT_APPLY_REASON='recorded full upgrade remains incomplete'; return 2
    fi
    vapt_transaction_prepare || return $?
    local config="$VAPT_STAGE/pacman.conf" content reason flags=()
    # Checkupdates-style private DB: rejected sync/download/audit leaves the
    # system databases unchanged and does not create a recovery marker.
    vapt_root_pacman --config "$config" --dbpath "$VAPT_DB" -Syuw --cachedir "$VAPT_CACHE/packages" --noconfirm || return 1
    content="$(LC_ALL=C pacman --config "$config" --dbpath "$VAPT_DB" -Sup --print-format $'%r\t%n\t%v\t%f' 2>"$VAPT_STAGE/plan.err")" || {
        VAPT_APPLY_REASON="upgrade resolution failed: $(<"$VAPT_STAGE/plan.err")"; return 2;
    }
    printf '%s\n' "$content" | write_user_file "$VAPT_STAGE/upgrade.tsv" || return 1
    reason="$(vapt_meta closure - "$VAPT_STAGE/upgrade.tsv" --dbpath "$(vapt_read_path "$VAPT_DB")" 2>&1)" || {
        VAPT_APPLY_REASON="$reason"; return 2;
    }
    vapt_closure_warnings "$reason"
    vapt_transaction_audit "$VAPT_STAGE/upgrade.tsv" || return $?
    # Freeze reviewed DB payloads: final -Syu must not pick up a newer,
    # unaudited transaction from live mirrors between review and commit.
    local repo database frozen="$VAPT_CACHE/reviewed"
    # Explicit modes (not the caller umask) so DownloadUser can read the
    # file:// mirror; install -p keeps the reviewed DB's own mtime.
    vapt_root_exec /usr/bin/install -d -m 0755 "$frozen" || return 1
    for repo in "${VAPT_TRANSACTION_REPOS[@]}"; do
        vapt_repo_allowed "$repo" && [[ $repo != oniomarchy ]] || return 2
        database="$(vapt_read_path "$VAPT_DB/sync/$repo.db")"
        [[ -f $database ]] || { VAPT_APPLY_REASON="reviewed database unavailable: $repo"; return 2; }
        vapt_root_exec /usr/bin/install -d -m 0755 "$frozen/$repo" || return 1
        vapt_root_exec /usr/bin/install -p -m 0644 -- "$VAPT_DB/sync/$repo.db" "$frozen/$repo/$repo.db" || return 1
        if [[ -f $database.sig ]]; then
            vapt_root_exec /usr/bin/install -p -m 0644 -- "$VAPT_DB/sync/$repo.db.sig" "$frozen/$repo/$repo.db.sig" || return 1
        fi
    done
    content="$(vapt_meta config --frozen "$frozen")" || return 2
    printf '%s\n' "$content" | write_user_file "$VAPT_STAGE/commit.conf" || return 1
    config="$VAPT_STAGE/commit.conf"
    # Only a reviewed real full-upgrade commit can require recovery. The
    # record also says whether the reviewed config staged BlackArch, so an
    # accepted recovery reviews/commits the same repositories and activates.
    local marker="$HASEEN_STATE_DIR/vapt/upgrade-pending" note=''
    vapt_state_path_safe "$marker" || return 2
    if [[ ${VAPT_BLACKARCH_STAGED:-} == 1 ]] && ! vapt_blackarch_preflight; then
        VAPT_APPLY_REASON='BlackArch activation unsupported: /etc/pacman.conf is not a single regular file'
        return 2
    fi
    [[ ${VAPT_BLACKARCH_STAGED:-} != 1 ]] || note=$'\tblackarch-staged'
    # A recovery rewrites only the record it parsed: changed bytes (another
    # root writer) are preserved for manual review, never overwritten.
    if [[ ${VAPT_RECOVERING:-} == 1 ]]; then
        local observed
        observed="$(vapt_meta file-digest "$(vapt_read_path "$marker")" 2>/dev/null)" || observed=''
        [[ -n $observed && $observed == "${VAPT_RECOVERY_DIGEST:-}" ]] || {
            VAPT_APPLY_REASON='recovery record changed during recovery; preserved, manual review required; nothing committed'; return 2;
        }
    fi
    printf 'reviewed-full-upgrade-commit-pending%s\n' "$note" |
        vapt_root_meta state-write "$(vapt_read_path "$marker")" || return 1
    $ASSUME_YES && flags+=(--noconfirm)
    vapt_sealed_safe "$(vapt_read_path "$VAPT_CACHE/sealed")" "$(vapt_read_path "$frozen")" || return $?
    # -yy: always fetch the frozen reviewed DBs. A plain -y is If-Modified-Since
    # the live DB, so a newer live refresh would otherwise resolve the commit.
    vapt_root_pacman --config "$config" -Syyu --cachedir "$VAPT_CACHE/sealed" "${flags[@]}" || return 1
    # Global BlackArch visibility only after the reviewed commit, and before
    # the recovery record is cleared: a failed append stays resumable.
    if [[ ${VAPT_BLACKARCH_STAGED:-} == 1 ]]; then vapt_blackarch_activate || return 1; fi
    vapt_root_meta state-clear "$(vapt_read_path "$marker")" || return 1
}
vapt_pacman_upgrade() {
    local rc=0
    VAPT_CACHE=''
    vapt_pacman_upgrade_transaction || rc=$?
    vapt_transaction_cleanup || rc=1
    VAPT_CACHE=''
    ((rc != 1)) || VAPT_MUTATION_FAILED=1
    return "$rc"
}
