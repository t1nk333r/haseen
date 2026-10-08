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
run() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/action-user"
    if [[ ${VAPT_REAL_FOREGROUND:-false} == true ]]; then "$@"; fi
}
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
if [[ ${VAPT_TERMINAL_UNAVAILABLE:-false} == true ]]; then
    export HASEEN_TERMINAL_SH=1
    in_floating_terminal() { echo TERMINAL-UNAVAILABLE >&2; return 19; }
fi
vapt_actions() {
    if [[ $1 == service-plan && ${VAPT_CHANGE_BEFORE_SECOND:-false} == true ]]; then
        if [[ -e $VAPT_CALLS/service-first-read ]]; then
            /usr/bin/python3 - "$HASEEN_SYSROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['owned-secure-login.service']['FragmentPath']='/etc/systemd/system/foreign.service'
with open(p,'w') as f:json.dump(r,f)
PY
        else
            touch "$VAPT_CALLS/service-first-read"
        fi
    fi
    if [[ $1 == endpoint-plan && -n ${VAPT_ENDPOINT_ADAPTER:-} ]]; then
        /usr/bin/python3 - "$2" "$VAPT_ENDPOINT_ADAPTER" <<'PY'
import json,sys
print(json.dumps({'schemaVersion':1,'kind':sys.argv[1],'adapter':sys.argv[2],
                  'endpoint':{'address':'127.0.0.1','port':8080,'family':'ipv4','requiresConfirmation':False}}))
PY
    else
        /usr/bin/python3 -B "$HASEEN_PATH/layers/vapt/workflow_actions.py" "$@"
    fi
}
case "$1" in
service) shift; vapt_service_action "$@" ;;
endpoint) shift; usage() { echo 'fixture endpoint usage'; }; vapt_endpoint_action "$@" ;;
ca) shift; usage() { echo 'fixture CA usage'; }; vapt_ca_action "$@" ;;
*) exit 97 ;;
esac
