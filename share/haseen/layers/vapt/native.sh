# shellcheck shell=bash disable=SC2034  # VAPT_* outputs are consumed by provision.sh
vapt_native_paths() {
    VAPT_PIPX_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/haseen/vapt/pipx"
    VAPT_PIPX_BIN_DIR="$VAPT_PIPX_HOME/bin"
    export VAPT_PIPX_HOME VAPT_PIPX_BIN_DIR
}
vapt_native_state() {
    local logical="$1"
    local home="$VAPT_PIPX_HOME"
    # Fixture-native metadata must live under the supplied sysroot. Never
    # borrow the invoking workstation's environment or PATH as evidence.
    in_sysroot && home="$(sysroot_path "$home")"
    vapt_meta native "$home" "$logical" "${VAPT_NATIVE_SPEC[$logical]}" "$(vapt_native_probe "$logical")" "$(vapt_read_path "$HASEEN_USER_STATE")"
}
vapt_native_probe() {
    # Source inventory keeps the distro command fact; PyPI's upstream script
    # is smbserver.py, not the distro-renamed impacket-smbserver.
    if [[ $1 == impacket ]]; then printf 'smbserver.py\n'
    else printf '%s\n' "${VAPT_NATIVE_PROBE[$1]}"
    fi
}
vapt_native_apply() {
    local logical="$1" spec="${VAPT_NATIVE_SPEC[$1]}" probe state distribution envdir interpreter owner
    probe="$(vapt_native_probe "$logical")"
    VAPT_APPLY_REASON=''
    state="$(vapt_native_state "$logical")" || state=unknown
    [[ $state != exact ]] || { VAPT_APPLY_STATE=already-exact; return 0; }
    distribution="${spec%%==*}"
    [[ $spec != git+* ]] || distribution=netexec
    envdir="$VAPT_PIPX_HOME/venvs/$distribution"
    owner="$VAPT_PIPX_HOME/owned/$logical"
    local inspect_home="$VAPT_PIPX_HOME" inspect_owner="$owner" inspect_env="$envdir" owned_exists=false
    in_sysroot && { inspect_home="$(sysroot_path "$inspect_home")"; inspect_owner="$(sysroot_path "$owner")"; inspect_env="$(sysroot_path "$envdir")"; }
    local check
    for check in "$envdir" "$owner" "$VAPT_PIPX_HOME/bin" "$VAPT_PIPX_HOME/man"; do
        vapt_path_ancestors_safe "$check" || {
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='symlinked/non-directory native ancestor preserved'; return 2;
        }
        [[ ! -L $(vapt_read_path "$check") ]] || {
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='symlinked native store preserved'; return 2;
        }
    done
    vapt_state_path_safe "$owner" || { VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='native ownership conflict preserved'; return 2; }
    if [[ -e $inspect_home/bin/$probe || -L $inspect_home/bin/$probe ]]; then
        if [[ ! -r $inspect_owner || ! -d $inspect_env ]] ||
            ! vapt_meta native-link "$inspect_home/bin/$probe" "$inspect_env/bin/$probe"; then
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='native executable conflict or unowned environment; preserved'; return 2
        fi
    fi
    if [[ -e $inspect_env || -L $inspect_env ]]; then
        [[ -r $inspect_owner && $(<"$inspect_owner") == "$spec" ]] || {
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='existing native environment is unowned; preserved'; return 2;
        }
        if ! vapt_meta native-interpreter "$inspect_home" "$logical" "$spec" "$(vapt_read_path "$HASEEN_USER_STATE")"; then
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='owned native interpreter provenance missing/drifted; preserved without manager execution'; return 2
        fi
        owned_exists=true
    fi
    local deps=(python-pipx python)
    case "$logical" in
    netexec) deps+=(git rust base-devel openssl libffi) ;;
    impacket) deps+=(base-devel openssl libffi) ;;
    mitmproxy) deps+=(rust base-devel openssl) ;;
    esac
    if ! vapt_install_infra "${deps[@]}"; then
        VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='native binary build/runtime prerequisite unavailable'; return 2
    fi
    interpreter=/usr/bin/python
    # Prefer compatible owned COAE; unmanaged/degraded COAE is never borrowed.
    # A metadata-proven compatible system Python keeps PyRIT independent.
    if [[ $logical == pyrit ]]; then
        if { [[ ${VAPT_COAE_STATUS:-unselected} == planned ]] && $DRY_RUN; } || vapt_coae_interpreter_ok; then
            interpreter="${XDG_DATA_HOME:-$HOME/.local/share}/htb-coae/bin/python"
        elif ! vapt_meta interpreter >/dev/null; then
            VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='no owned COAE or system Python >=3.10,<3.15 interpreter proven by metadata'; return 2
        fi
    elif ! vapt_meta interpreter any >/dev/null; then
        VAPT_APPLY_STATE=skipped; VAPT_APPLY_REASON='intended allowed-source system Python interpreter provenance unavailable'; return 2
    fi
    local flags=(--python "$interpreter")
    $owned_exists && flags+=(--force)
    run install -d -m 0700 "$VAPT_PIPX_HOME" "$VAPT_PIPX_HOME/owned" || { VAPT_MUTATION_FAILED=1; return 1; }
    # Ownership precedes installation so interrupted installs are recoverable.
    printf '%s\n' "$spec" | vapt_state_write "$owner" || { VAPT_MUTATION_FAILED=1; return 1; }
    if ! run env PIPX_HOME="$VAPT_PIPX_HOME" PIPX_BIN_DIR="$VAPT_PIPX_BIN_DIR" PIPX_MAN_DIR="$VAPT_PIPX_HOME/man" /usr/bin/pipx install "${flags[@]}" "$spec"; then
        VAPT_MUTATION_FAILED=1; VAPT_APPLY_STATE=failed; VAPT_APPLY_REASON='pinned pipx provisioning failed'; return 1
    fi
    if $DRY_RUN; then
        VAPT_APPLY_STATE=planned; VAPT_APPLY_REASON='pinned adapter planned; metadata not verified'
    else
        state="$(vapt_native_state "$logical")" || state=unknown
        if [[ $state != exact ]]; then
            VAPT_MUTATION_FAILED=1; VAPT_APPLY_STATE=failed; VAPT_APPLY_REASON="native metadata after install: $state"; return 1
        fi
        VAPT_APPLY_STATE=installed; VAPT_APPLY_REASON='exact pinned metadata and owned executable path'
    fi
    return 0
}
