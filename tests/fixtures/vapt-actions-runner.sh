#!/usr/bin/env bash
# Fixture-only confirmation/argv gateway. Never reaches live root or sockets.
set -Eeuo pipefail
source "$HASEEN_PATH/lib/common.sh"
source "$HASEEN_PATH/layers/vapt/workflow_actions.sh"
[[ -n $HASEEN_SYSROOT && $HASEEN_SYSROOT == "$VAPT_SANDBOX"/* ]] || exit 97
vapt_action_refuse_fixture() { :; }
vapt_root_exec() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/action-root"
    [[ $* != *'workflow_ca.py trust '* ]] || cat >/dev/null
}
run() { printf '%s\n' "$*" >>"$VAPT_CALLS/action-user"; }
confirm() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/confirm"
    [[ ${VAPT_CONFIRM:-no} == yes ]] || return 1
    if [[ ${VAPT_CHANGE_FRAGMENT:-false} == true ]]; then
        /usr/bin/python3 - "$HASEEN_SYSROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['owned-secure-login.service']['FragmentPath']='/etc/systemd/system/foreign.service'
with open(p,'w') as f:json.dump(r,f)
PY
    fi
}
confirm_typed() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/typed"
    [[ ${VAPT_TYPED:-} == "$2" ]]
}
CA_FLAGS=()
ASSUME_YES=${VAPT_YES:-false}
export HASEEN_INLINE=1
case "$1" in
service) shift; vapt_service_action "$@" ;;
endpoint) shift; usage() { echo 'fixture endpoint usage'; }; vapt_endpoint_action "$@" ;;
ca) shift; usage() { echo 'fixture CA usage'; }; vapt_ca_action "$@" ;;
*) exit 97 ;;
esac
