# shellcheck shell=bash
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-services
capture haseen-vapt-service-list --json --dry-run
assert_status 'service read succeeds' 0 "$STATUS"
assert_eq 'single versioned service object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
assert_eq 'five service ids' 5 "$(jq '.services | length' <<<"$OUTPUT")"
assert_eq 'actual owned unit not package-name guess' owned-secure-login.service "$(jq -r '.services[] | select(.id=="ssh") | .unit' <<<"$OUTPUT")"
assert_eq 'FragmentPath ownership verified' verified "$(jq -r '.services[] | select(.id=="ssh") | .ownership' <<<"$OUTPUT")"
assert_eq 'inactive manager state' stopped "$(jq -r '.services[] | select(.id=="ssh") | .state' <<<"$OUTPUT")"
assert_eq 'exposure never assumed loopback' unknown "$(jq -r '.services[] | select(.id=="ssh") | .exposure' <<<"$OUTPUT")"
assert_eq 'BeEF missing is honest' false "$(jq '.services[] | select(.id=="beef") | .installed' <<<"$OUTPUT")"
for verb in start stop restart; do
    capture "haseen-vapt-service-$verb" ssh --dry-run
    assert_status "$verb dry-run" 0 "$STATUS"
    assert_contains "$verb dry plan" "$OUTPUT" 'never enable'
    capture "haseen-vapt-service-$verb" --yes ssh
    assert_status "$verb refuses fixture live action" 1 "$STATUS"
done
for verb in start stop restart; do
    capture "haseen-vapt-service-$verb" ssh --expect-unit owned-secure-login.service --expect-fragment /usr/lib/systemd/system/owned-secure-login.service --dry-run
    assert_status "$verb matching displayed snapshot" 0 "$STATUS"
    assert_contains "$verb previews snapshot check" "$OUTPUT" 'displayed snapshot expectation matched'
    capture "haseen-vapt-service-$verb" ssh --expect-unit old.service --dry-run
    assert_status "$verb changed displayed unit refused" 1 "$STATUS"
    assert_contains "$verb unit mismatch reason" "$OUTPUT" 'unit changed'
    capture "haseen-vapt-service-$verb" ssh --expect-fragment /old/fragment.service --dry-run
    assert_status "$verb changed displayed FragmentPath refused" 1 "$STATUS"
    assert_contains "$verb fragment mismatch reason" "$OUTPUT" 'FragmentPath changed'
done
assert_eq 'expectation refusals have no root call' '' "$(vapt_calls action-root)"
capture haseen-vapt-service-start nonexistent --dry-run
assert_status 'unknown service usage' 2 "$STATUS"
capture haseen-vapt-service-stop ssh extra --dry-run
assert_status 'extra service operand usage' 2 "$STATUS"
actions_api service stop ssh owned-secure-login.service /usr/lib/systemd/system/owned-secure-login.service
assert_status 'matching expectation reaches fixture root gateway' 0 "$STATUS"
assert_contains 'matching expectation exact unit' "$(vapt_calls action-root)" 'stop -- owned-secure-login.service'
rm -f "$CALLS/action-root"
actions_api service stop ssh old.service /usr/lib/systemd/system/owned-secure-login.service
assert_status 'changed displayed unit refuses actual operation' 1 "$STATUS"
assert_eq 'changed displayed unit no privilege' '' "$(vapt_calls action-root)"
actions_api service stop ssh owned-secure-login.service /old/fragment.service
assert_status 'changed displayed fragment refuses actual operation' 1 "$STATUS"
assert_eq 'changed displayed fragment no privilege' '' "$(vapt_calls action-root)"
actions_api service start ssh
assert_status 'start confirmation decline fails' 1 "$STATUS"
assert_eq 'decline no root command' '' "$(vapt_calls action-root)"
assert_contains 'start confirms exposure' "$(vapt_calls confirm)" 'exposure uncertainty'
VAPT_CONFIRM=yes actions_api service restart ssh
assert_status 'confirmed restart reaches fixture gateway' 0 "$STATUS"
assert_contains 'only restart no enable' "$(vapt_calls action-root)" '/usr/bin/systemctl restart -- owned-secure-login.service'
rm -f "$CALLS/confirm" "$CALLS/action-root"
actions_api service stop ssh
assert_status 'stop reaches gateway without confirmation' 0 "$STATUS"
assert_eq 'stop has no confirmation' '' "$(vapt_calls confirm)"
assert_contains 'stop exact owned unit' "$(vapt_calls action-root)" '/usr/bin/systemctl stop -- owned-secure-login.service'
rm -f "$CALLS/action-root"
VAPT_CONFIRM=yes VAPT_CHANGE_FRAGMENT=true actions_api service start ssh
assert_status 'changed FragmentPath refused after confirmation' 1 "$STATUS"
assert_eq 'changed FragmentPath no root call' '' "$(vapt_calls action-root)"
capture haseen-vapt-service-list --json
assert_eq 'foreign FragmentPath read refusal' refused "$(jq -r '.services[] | select(.id=="ssh") | .ownership' <<<"$OUTPUT")"
python3 - "$ROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['owned-secure-login.service']['FragmentPath']='/usr/lib/systemd/system/owned-secure-login.service'
r['owned-secure-login.service']['ActiveState']='activating';r['owned-secure-login.service']['SubState']='start'
r['owned-database.service']['ActiveState']='failed';r['owned-http.service']['ActiveState']='unrecognized'
with open(p,'w') as f:json.dump(r,f)
PY
capture haseen-vapt-service-list --json
assert_eq 'transition state retained' transitioning "$(jq -r '.services[] | select(.id=="ssh") | .state' <<<"$OUTPUT")"
assert_eq 'failure state retained' failed "$(jq -r '.services[] | select(.id=="postgresql") | .state' <<<"$OUTPUT")"
assert_eq 'unknown state retained' unknown "$(jq -r '.services[] | select(.id=="apache") | .state' <<<"$OUTPUT")"
assert_eq 'raw manager substate retained' start "$(jq -r '.services[] | select(.id=="ssh") | .subState' <<<"$OUTPUT")"
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));next(x for x in r if x['name']=='nginx')['url']='https://foreign.invalid/'
with open(p,'w') as f:json.dump(r,f)
PY
capture haseen-vapt-service-list --json
assert_eq 'installed but unverified package retained diagnostic' true "$(jq '.services[] | select(.id=="nginx") | .installed' <<<"$OUTPUT")"
assert_eq 'unverified unit cannot control' refused "$(jq -r '.services[] | select(.id=="nginx") | .ownership' <<<"$OUTPUT")"
assert_not_contains 'never enable via gateway' "$(vapt_calls action-root)" ' enable '
actions_untouched service
actions_fixture vapt-services-batch-j
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh owned-secure-login.service /usr/lib/systemd/system/owned-secure-login.service
assert_status 'stop needs no available terminal' 0 "$STATUS"
assert_contains 'terminal-free stop exact root unit' "$(vapt_calls action-root)" 'stop -- owned-secure-login.service'
rm "$CALLS/action-root"
for verb in start restart; do
    VAPT_TERMINAL_UNAVAILABLE=true VAPT_CONFIRM=yes actions_api service "$verb" ssh
    assert_status "$verb propagates unavailable terminal status" 19 "$STATUS"
    assert_contains "$verb terminal refusal" "$OUTPUT" TERMINAL-UNAVAILABLE
done
assert_eq 'terminal refusal no service root call' '' "$(vapt_calls action-root)"
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh old.service /usr/lib/systemd/system/owned-secure-login.service
assert_status 'terminal-free stop rejects changed unit expectation' 1 "$STATUS"
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh owned-secure-login.service /old/fragment.service
assert_status 'terminal-free stop rejects changed fragment expectation' 1 "$STATUS"
VAPT_TERMINAL_UNAVAILABLE=true VAPT_CHANGE_BEFORE_SECOND=true actions_api service stop ssh
assert_status 'terminal-free stop revalidates current fragment before root' 1 "$STATUS"
assert_eq 'all terminal-free stale refusals no root command' '' "$(vapt_calls action-root)"
for content in '[]' null 17 '"wrong"'; do
    printf '%s\n' "$content" >"$ROOT/var/lib/haseen/vapt/services.json"
    capture bash -c 'haseen-vapt-service-list --json 2>"$1"' bash "$SANDBOX/service-json-err"
    assert_status 'wrong-shaped service container explicit refusal' 1 "$STATUS"
    assert_eq 'wrong-shaped service one object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
    assert_eq 'wrong-shaped service root refusal state' refused "$(jq -r '.state' <<<"$OUTPUT")"
    assert_contains 'wrong-shaped service diagnostic only stderr' "$(<"$SANDBOX/service-json-err")" 'vapt:'
    assert_not_contains 'wrong-shaped service has no traceback' "$(<"$SANDBOX/service-json-err")" Traceback
    printf '{"owned-secure-login.service":%s}\n' "$content" >"$ROOT/var/lib/haseen/vapt/services.json"
    capture haseen-vapt-service-list --json
    assert_eq 'wrong-shaped service row current ownership unknown' unknown "$(jq -r '.services[] | select(.id=="ssh") | .ownership' <<<"$OUTPUT")"
done
capture python3 -B - "$VAPT_LAYER" <<'PY'
import sys
sys.path.insert(0,sys.argv[1]);from workflow_actions import manager_record
record={'FragmentPath':'/usr/lib/systemd/system/owned.service','ActiveState':'inactive','SubState':'dead','LoadState':'loaded'}
for key in record:
    for value in ([],None,17,'invalid token'):
        changed=dict(record);changed[key]=value
        assert manager_record(changed)=={},(key,value)
assert manager_record(record)==record
print('all consumed manager fields validated')
PY
assert_status 'manager consumed field types/enums refuse safely' 0 "$STATUS"
actions_untouched services-batch-j
