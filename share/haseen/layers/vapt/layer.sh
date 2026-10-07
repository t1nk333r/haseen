# shellcheck shell=bash disable=SC2034
LAYER_SUMMARY='Optional owner VAPT inventory, pinned native environments and passive workstation configuration'
LAYER_DISTROS=(arch cachyos)
LAYER_REQUIRES=()
LAYER_CONFLICTS=()
layer_usage() {
    cat <<'EOF'
Usage: haseen layer apply vapt [--dry-run] [--yes] -- --groups GROUP,...
       haseen layer apply vapt [--dry-run] [--yes] -- --all
Groups: core,network,web,passwords,ad,osint,cloud,mobile,forensics,api,
        htb-cjca,htb-cpts,htb-cwes,htb-cwee,htb-coae
There are no default tools. Provisioning never runs security tools or services.
Source order: five explicit repo pins; BlackArch; pinned native; already-enabled
Chaotic; CachyOS; Arch. Microsoft PyRIT is forced native, never WPA BlackArch pyrit.
Unavailable items are reported and skipped; actual mutation failures return 1.
Dry-run is offline and write-free; unknown fixture metadata stays unknown.
Remove reverses owned unchanged links only; packages, repository, keyring trust,
native environments, seeds and workspace/user data are retained.
EOF
}
layer_precheck() {
    require_not_root
    preflight_distro
    [[ $HASEEN_DISTRO == arch || $HASEEN_DISTRO == cachyos ]] || {
        warn "VAPT supports Arch/CachyOS only (detected $HASEEN_DISTRO)"; return 2;
    }
    local command
    for command in python3 pacman vercmp curl gpg; do
        have "$command" || { warn "VAPT prerequisite missing: $command; install it from signed official Arch/CachyOS packages before provisioning"; return 2; }
    done
    # Archives are read only through libalpm's own libarchive (ctypes).
    python3 -c 'import argparse,ctypes,email,fnmatch,glob,json,os,pathlib,re,shlex,stat,subprocess,sys; ctypes.CDLL("libarchive.so.13")' || {
        warn 'VAPT requires Python 3 with its standard library and libarchive (pacman dependency)'; return 2;
    }
    source "$LAYER_DIR/provision.sh"
    vapt_reset
    vapt_select "$@" || return $?
    vapt_manifest_validate || { warn 'invalid VAPT inventory or pins'; return 2; }
    vapt_refuse_sysroot_mutation
}
# A sysroot is fixture evidence (fixture repositories, signer declarations),
# while privileged steps would act on this machine: a mutating VAPT run with
# HASEEN_SYSROOT set is refused before anything changes. Dry-run planning and
# status stay available. Hermetic tests use their own non-live runner.
vapt_refuse_sysroot_mutation() {
    if [[ -n ${HASEEN_SYSROOT:-} ]] && ! $DRY_RUN; then
        warn 'VAPT refuses to mutate with HASEEN_SYSROOT set (fixture evidence never drives live changes); use --dry-run'
        return 2
    fi
}
layer_apply() {
    # Source providers inside functions: layer_field must be read-only and
    # independent of both provisioning managers and environment prerequisites.
    source "$LAYER_DIR/provision.sh"
    vapt_reset
    vapt_select "$@" || return $?
    vapt_manifest_validate || return 2
    vapt_refuse_sysroot_mutation || return $?
    vapt_provision
}
layer_status() {
    source "$LAYER_DIR/provision.sh"
    vapt_reset
    vapt_manifest_validate || { echo 'warn: invalid VAPT inventory'; return 2; }
    local report="$HASEEN_USER_STATE/vapt/report.tsv" logical groups source_name target resolution applied reason tiers degraded=false
    vapt_state_path_safe "$HASEEN_USER_STATE/vapt/removed" || { echo 'warn: redirected VAPT removal state'; return 2; }
    if [[ -f $(vapt_read_path "$HASEEN_USER_STATE/vapt/removed") ]]; then
        echo 'missing: per-user VAPT activation removed (packages/environments retained)'; return 1
    fi
    vapt_state_path_safe "$report" || { echo 'warn: redirected VAPT report preserved'; return 2; }
    in_sysroot && report="$(sysroot_path "$report")"
    [[ -r $report ]] || { echo 'missing: no per-user VAPT provisioning report'; return 1; }
    vapt_snapshot || { echo 'warn: VAPT source metadata unreadable'; return 2; }
    while IFS=$'\t' read -r logical groups source_name target resolution applied reason tiers; do
        [[ $logical != logical ]] || continue
        if [[ $logical == '# environment' ]]; then [[ $groups == ok ]] || degraded=true; continue; fi
        if [[ $logical == '# mutation-failed' ]]; then [[ $groups == 0 ]] || degraded=true; continue; fi
        if [[ $logical == '# infrastructure' ]]; then
            if [[ $target != ok || $source_name != */* ]] ||
                [[ $(vapt_meta installed "${source_name%%/*}" "${source_name##*/}" "${VAPT_VERSION[$source_name]:--}" "${VAPT_URL[$source_name]:--}") != exact ]] ||
                ! vapt_meta closure "$source_name" >/dev/null 2>&1; then degraded=true; fi
            continue
        fi
        [[ $logical != \#* && -n $logical ]] || continue
        [[ ,$groups, != *,htb-coae,* ]] || VAPT_COAE_REQUIRED=1
        printf '%s: %s -> %s (%s/%s) %s\n' "$source_name" "$logical" "$target" "$resolution" "$applied" "$reason"
        [[ $resolution == resolved && ( $applied == installed || $applied == already-exact ) ]] || degraded=true
        if [[ $source_name == native ]]; then
            [[ ${VAPT_NATIVE_SPEC[$logical]:-} == "$target" && $(vapt_native_state "$logical") == exact ]] || {
                echo "warn: $logical native metadata missing/drifted/unknown"; degraded=true;
            }
        elif [[ $resolution == resolved && $target == */* ]]; then
            if ! vapt_repo_usable "${target%%/*}" ||
                [[ $(vapt_meta installed "${target%%/*}" "${target##*/}" "${VAPT_VERSION[$target]:--}" "${VAPT_URL[$target]:--}") != exact ]] ||
                ! vapt_meta closure "$target" >/dev/null 2>&1; then
                echo "warn: $logical repository/package metadata unavailable or drifted"; degraded=true
            fi
        fi
    done <"$report"
    vapt_environment_status || degraded=true
    if $degraded; then echo 'warn: VAPT degraded; unavailable/skipped items are not installation evidence'; return 2; fi
    echo 'ok: recorded VAPT provisioning complete (metadata only; no security tools executed)'
}
layer_remove() (
    require_not_root
    vapt_refuse_sysroot_mutation || return $?
    source "$LAYER_DIR/provision.sh"
    vapt_reset
    vapt_lifecycle_lock || return 1
    vapt_state_path_safe "$HASEEN_USER_STATE/vapt/removed" || return 1
    vapt_environment_remove || return $?
    [[ ${VAPT_ENV_DEGRADED:-0} == 0 ]] || return 2
    printf 'owned-activation-removed\n' | vapt_state_write "$HASEEN_USER_STATE/vapt/removed"
)
