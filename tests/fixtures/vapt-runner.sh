#!/usr/bin/env bash
# Fixture-only subprocess driver. Public layer/provider APIs are real; mutation
# wrappers redirect filesystem operations to the sysroot and never run managers.
set -uo pipefail
source "$HASEEN_PATH/lib/common.sh"
LAYER_DIR="$HASEEN_PATH/layers/vapt"
source "$LAYER_DIR/layer.sh"
source "$LAYER_DIR/provision.sh"
vapt_reset
vapt_manifest_validate || exit $?

run() {
    if $DRY_RUN; then printf 'DRYRUN: %s\n' "$*"; return 0; fi
    case "$1" in
    python3) "$@" ;;
    # Sandbox PATH stubs only (fixture curl/gpg); never real network or keys.
    curl|gpg) "$@" ;;
    mkdir|ln|rm|install|mktemp|chmod|cp)
        python3 "$VAPT_FIXTURE_DRIVER" user "$@" ;;
    /usr/bin/uv)
        printf '%s\n' "$*" >>"$VAPT_CALLS/uv"
        [[ ${VAPT_FAKE_UV:-false} == true ]] || return 97
        python3 "$VAPT_FIXTURE_DRIVER" uv "$@" ;;
    env)
        if [[ $* == *' /usr/bin/uv '* ]]; then
            printf '%s\n' "$*" >>"$VAPT_CALLS/uv"
            [[ ${VAPT_FAKE_UV:-false} == true ]] || return 97
            shift
            local uv_install="$1"
            [[ $uv_install == UV_PYTHON_INSTALL_DIR=* ]] || return 97
            shift
            [[ $1 == /usr/bin/uv ]] || return 97
            env "$uv_install" /usr/bin/python3 "$VAPT_FIXTURE_DRIVER" uv "$@"
            return $?
        fi
        printf '%s\n' "$*" >>"$VAPT_CALLS/pipx"
        return 97 ;;
    *) printf 'FORBIDDEN-RUN: %s\n' "$*" >&2; return 97 ;;
    esac
}
run_root() {
    if $DRY_RUN; then printf 'DRYRUN: sudo %s\n' "$*"; return 0; fi
    python3 "$VAPT_FIXTURE_DRIVER" root "$@"
}
# This runner's run/run_root never reach the live machine (every mutator is
# confined to the fixture sysroot), so the public sysroot guard does not apply.
vapt_refuse_sysroot_mutation() { :; }
# Fail the Nth durable write, regardless of permissions/euid of the test runner.
if [[ -n ${VAPT_FAIL_WRITE:-} ]]; then
    vapt_state_write() {
        local count=0
        [[ ! -f $VAPT_CALLS/writes ]] || read -r count <"$VAPT_CALLS/writes"
        count=$((count + 1))
        printf '%s\n' "$count" >"$VAPT_CALLS/writes"
        [[ $count != "$VAPT_FAIL_WRITE" ]] || { cat >/dev/null; return 1; }
        vapt_state_path_safe "$1" || return 1
        run python3 "$VAPT_DIR/metadata.py" state-write "$(vapt_read_path "$1")"
    }
fi
operation="$1"; shift
case "$operation" in
install)
    args=()
    for arg in "$@"; do
        case "$arg" in --dry-run) DRY_RUN=true ;; --yes) ASSUME_YES=true ;; *) args+=("$arg") ;; esac
    done
    vapt_select "${args[@]}" || exit $?
    vapt_provision ;;
status) layer_status ;;
remove) layer_remove ;;
env-apply)
    vapt_snapshot || exit $?
    vapt_environment_apply "$@" ;;
env-status) vapt_environment_status ;;
env-remove) vapt_environment_remove ;;
pacman)
    [[ $1 != --yes ]] || { ASSUME_YES=true; shift; }
    vapt_snapshot || exit $?
    vapt_pacman_apply "$1"; rc=$?
    reason="${VAPT_APPLY_REASON:-}"
    printf 'STATE=%s\nREASON=%s\n' "${VAPT_PACMAN_STATE:-}" "${reason//$'\n'/ }"
    vapt_pacman_cleanup
    exit "$rc" ;;
upgrade)
    ASSUME_YES=true
    vapt_snapshot || exit $?
    vapt_pacman_upgrade; rc=$?
    reason="${VAPT_APPLY_REASON:-}"
    printf 'REASON=%s\n' "${reason//$'\n'/ }"
    vapt_pacman_cleanup
    exit "$rc" ;;
blackarch)
    # The provisioning prelude: recorded recovery outranks preparation.
    ASSUME_YES=true
    vapt_snapshot || exit $?
    [[ ! -e $(vapt_read_path "$HASEEN_STATE_DIR/vapt/upgrade-pending") ]] || VAPT_PACMAN_BLOCKED=1
    vapt_blackarch_prepare; rc=$?
    printf 'SOURCE=%s\nBLOCKED=%s\nMUTATION=%s\n' "${VAPT_SOURCE_REASON:-}" "$VAPT_PACMAN_BLOCKED" "$VAPT_MUTATION_FAILED"
    vapt_pacman_cleanup
    exit "$rc" ;;
recover)
    # Accepted recovery of a recorded reviewed commit (provision prelude).
    ASSUME_YES=true
    vapt_snapshot || exit $?
    vapt_pacman_recover; rc=$?
    vapt_snapshot || exit $?
    printf 'STATE=%s\n' "$(vapt_blackarch_state)"
    vapt_pacman_cleanup
    exit "$rc" ;;
*) exit 2 ;;
esac
