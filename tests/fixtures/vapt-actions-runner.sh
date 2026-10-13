#!/usr/bin/env bash
# Fixture-only gateway for the action orchestration. It replaces only sudo,
# the terminal prompts and the fixture refusal; it executes a program only
# when production chose it through the sysroot seam (vapt_program), so the
# fixture's own recording stub runs instead of anything on the host.
set -Eeuo pipefail
source "$HASEEN_PATH/lib/common.sh"
source "$HASEEN_PATH/layers/vapt/workflow_actions.sh"
[[ -n $HASEEN_SYSROOT && $HASEEN_SYSROOT == "$VAPT_SANDBOX"/* ]] || exit 97
vapt_action_refuse_fixture() { :; }
# fixture_routed PROGRAM — true when PROGRAM is the fixture's, never the host's.
fixture_routed() {
    [[ $1 == "$HASEEN_SYSROOT"/* ]] && return 0
    echo "fixture: $1 was not chosen through the sysroot seam; not executed" >&2
    return 97
}
fixture_foreign_fragment() {
    /usr/bin/python3 -I - "$HASEEN_SYSROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['sshd.service']['FragmentPath']='/etc/systemd/system/foreign.service'
with open(p,'w') as f:json.dump(r,f)
PY
}
# The privileged gateway: record the argv, then run it without sudo. The CA
# helper runs as the real mutation library against the fixture root, whose
# updater is the fixture's update-ca-trust stub (VAPT_CA_UPDATER_FAIL fails
# it); without VAPT_CA_MUTATE only the argv is recorded.
vapt_root_exec() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/action-root"
    if [[ " $* " == *" $HASEEN_PATH/layers/vapt/workflow_ca.py "* ]]; then
        if [[ ${VAPT_CA_MUTATE:-false} != true ]]; then
            [[ $* != *'workflow_ca.py trust '* ]] || cat >/dev/null
            return 0
        fi
        /usr/bin/python3 -I -B -c '
import base64,os,pathlib,sys
sys.path.insert(0,sys.argv[1]);import workflow_ca as ca
try:
    if os.environ.get("VAPT_CA_CHANGE_BEFORE_ROOT")=="true":
        p=pathlib.Path(os.environ["HASEEN_SYSROOT"]+ca.ANCHORS)/ca.anchor_name(sys.argv[3]);p.write_bytes(b"changed before root lock")
    der=base64.b64decode(sys.stdin.buffer.read(),validate=True) if sys.argv[2]=="trust" else None
    ca.mutate(sys.argv[2],sys.argv[3],der,root=os.environ["HASEEN_SYSROOT"])
    print("Fixture owned proxy CA "+sys.argv[2]+" completed; updater succeeded")
except (OSError,ValueError) as e:
    print("fixture: "+str(e),file=sys.stderr);sys.exit(1)
' "$HASEEN_PATH/layers/vapt" "${@: -2:1}" "${@: -1}"
        return
    fi
    fixture_routed "$1" || return
    "$@"
}
# The foreground handoff (run exec ADAPTER ...): record, then execute.
run() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/action-user"
    local program="$1"
    [[ $program != exec ]] || program="$2"
    fixture_routed "$program" || return
    "$@"
}
confirm() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/confirm"
    [[ ${VAPT_CONFIRM:-no} == yes ]] || return 1
    [[ ${VAPT_CHANGE_FRAGMENT:-false} != true ]] || fixture_foreign_fragment
}
confirm_typed() {
    printf '%s\n' "$*" >>"$VAPT_CALLS/typed"
    [[ ${VAPT_TYPED:-} == "$2" ]]
}
# shellcheck disable=SC2034  # read by the sourced vapt_ca_action
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
            fixture_foreign_fragment
        else
            touch "$VAPT_CALLS/service-first-read"
        fi
    fi
    if [[ $1 == endpoint-plan && -n ${VAPT_ENDPOINT_ADAPTER:-} ]]; then
        /usr/bin/python3 -I - "$2" "$VAPT_ENDPOINT_ADAPTER" <<'PY'
import json,sys
print(json.dumps({'schemaVersion':1,'kind':sys.argv[1],'adapter':sys.argv[2],
                  'endpoint':{'address':'127.0.0.1','port':8080,'family':'ipv4','requiresConfirmation':False}}))
PY
    else
        /usr/bin/python3 -I -B "$HASEEN_PATH/layers/vapt/workflow_actions.py" "$@"
    fi
}
case "$1" in
service) shift; vapt_service_action "$@" ;;
endpoint) shift; usage() { echo 'fixture endpoint usage'; }; vapt_endpoint_action "$@" ;;
ca) shift; usage() { echo 'fixture CA usage'; }; vapt_ca_action "$@" ;;
*) exit 97 ;;
esac
