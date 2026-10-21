# shellcheck shell=bash
# haseen:covers bin/haseen-vapt-service-* share/haseen/default/vapt/** share/haseen/layers/vapt/**
# haseen:covers share/haseen/lib/terminal.sh tests/fixtures/vapt-host/**
# haseen:covers tests/fixtures/vapt-actions-lib.sh tests/fixtures/vapt-actions-runner.sh
# haseen:covers tests/fixtures/vapt-driver.py tests/fixtures/vapt-lib.sh
# haseen:covers tests/fixtures/vapt-workflow-lib.sh
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-services
capture haseen-vapt-service-list --json --dry-run
assert_status 'service read succeeds' 0 "$STATUS"
assert_eq 'single versioned service object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
assert_eq 'five service ids' 5 "$(jq '.services | length' <<<"$OUTPUT")"
assert_eq 'reviewed Arch SSH binding selected among real unit set' sshd.service "$(jq -r '.services[] | select(.id=="ssh") | .unit' <<<"$OUTPUT")"
assert_eq 'reviewed Arch Apache binding' httpd.service "$(jq -r '.services[] | select(.id=="apache") | .unit' <<<"$OUTPUT")"
assert_eq 'reviewed Arch PostgreSQL binding' postgresql.service "$(jq -r '.services[] | select(.id=="postgresql") | .unit' <<<"$OUTPUT")"
assert_eq 'reviewed Arch nginx binding' nginx.service "$(jq -r '.services[] | select(.id=="nginx") | .unit' <<<"$OUTPUT")"
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
    capture "haseen-vapt-service-$verb" ssh --expect-unit sshd.service --expect-fragment /usr/lib/systemd/system/sshd.service --dry-run
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
actions_api service stop ssh sshd.service /usr/lib/systemd/system/sshd.service
assert_status 'matching expectation reaches fixture root gateway' 0 "$STATUS"
assert_eq 'matching expectation runs the sysroot service manager' 'stop -- sshd.service' "$(vapt_calls owned-systemctl)"
rm -f "$CALLS/action-root" "$CALLS/owned-systemctl"
actions_api service stop ssh old.service /usr/lib/systemd/system/sshd.service
assert_status 'changed displayed unit refuses actual operation' 1 "$STATUS"
assert_eq 'changed displayed unit no privilege' '' "$(vapt_calls action-root)"
actions_api service stop ssh sshd.service /old/fragment.service
assert_status 'changed displayed fragment refuses actual operation' 1 "$STATUS"
assert_eq 'changed displayed fragment no privilege' '' "$(vapt_calls action-root)"
assert_eq 'changed displayed snapshot runs no service manager' '' "$(vapt_calls owned-systemctl)"
actions_api service start ssh
assert_status 'start confirmation decline fails' 1 "$STATUS"
assert_eq 'decline no root command' '' "$(vapt_calls action-root)$(vapt_calls owned-systemctl)"
assert_contains 'start confirms exposure' "$(vapt_calls confirm)" 'exposure uncertainty'
VAPT_CONFIRM=yes actions_api service restart ssh
assert_status 'confirmed restart reaches fixture gateway' 0 "$STATUS"
assert_eq 'only restart no enable, through the sysroot seam' "$ROOT/usr/bin/systemctl restart -- sshd.service" "$(vapt_calls action-root)"
assert_eq 'restart ran the sysroot service manager' 'restart -- sshd.service' "$(vapt_calls owned-systemctl)"
rm -f "$CALLS/confirm" "$CALLS/action-root" "$CALLS/owned-systemctl"
actions_api service stop ssh
assert_status 'stop reaches gateway without confirmation' 0 "$STATUS"
assert_eq 'stop has no confirmation' '' "$(vapt_calls confirm)"
assert_eq 'stop ran the sysroot service manager' 'stop -- sshd.service' "$(vapt_calls owned-systemctl)"
rm -f "$CALLS/action-root" "$CALLS/owned-systemctl"
VAPT_CONFIRM=yes VAPT_CHANGE_FRAGMENT=true actions_api service start ssh
assert_status 'changed FragmentPath refused after confirmation' 1 "$STATUS"
assert_eq 'changed FragmentPath no root call' '' "$(vapt_calls action-root)$(vapt_calls owned-systemctl)"
capture haseen-vapt-service-list --json
assert_eq 'foreign FragmentPath read refusal' refused "$(jq -r '.services[] | select(.id=="ssh") | .ownership' <<<"$OUTPUT")"
python3 - "$ROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['sshd.service']['FragmentPath']='/usr/lib/systemd/system/sshd.service'
r['sshd.service']['ActiveState']='activating';r['sshd.service']['SubState']='start'
r['postgresql.service']['ActiveState']='failed';r['httpd.service']['ActiveState']='unrecognized'
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
actions_fixture vapt-services-terminal
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh sshd.service /usr/lib/systemd/system/sshd.service
assert_status 'stop needs no available terminal' 0 "$STATUS"
assert_eq 'terminal-free stop ran the sysroot service manager' 'stop -- sshd.service' "$(vapt_calls owned-systemctl)"
rm "$CALLS/action-root" "$CALLS/owned-systemctl"
for verb in start restart; do
    VAPT_TERMINAL_UNAVAILABLE=true VAPT_CONFIRM=yes actions_api service "$verb" ssh
    assert_status "$verb propagates unavailable terminal status" 19 "$STATUS"
    assert_contains "$verb terminal refusal" "$OUTPUT" TERMINAL-UNAVAILABLE
done
assert_eq 'terminal refusal no service root call' '' "$(vapt_calls action-root)"
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh old.service /usr/lib/systemd/system/sshd.service
assert_status 'terminal-free stop rejects changed unit expectation' 1 "$STATUS"
VAPT_TERMINAL_UNAVAILABLE=true actions_api service stop ssh sshd.service /old/fragment.service
assert_status 'terminal-free stop rejects changed fragment expectation' 1 "$STATUS"
VAPT_TERMINAL_UNAVAILABLE=true VAPT_CHANGE_BEFORE_SECOND=true actions_api service stop ssh
assert_status 'terminal-free stop revalidates current fragment before root' 1 "$STATUS"
assert_eq 'all terminal-free stale refusals no root command' '' "$(vapt_calls action-root)$(vapt_calls owned-systemctl)"
for content in '[]' null 17 '"wrong"'; do
    printf '%s\n' "$content" >"$ROOT/var/lib/haseen/vapt/services.json"
    capture bash -c 'haseen-vapt-service-list --json 2>"$1"' bash "$SANDBOX/service-json-err"
    assert_status 'wrong-shaped service container explicit refusal' 1 "$STATUS"
    assert_eq 'wrong-shaped service one object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
    assert_eq 'wrong-shaped service root refusal state' refused "$(jq -r '.state' <<<"$OUTPUT")"
    assert_contains 'wrong-shaped service diagnostic only stderr' "$(<"$SANDBOX/service-json-err")" 'vapt:'
    assert_not_contains 'wrong-shaped service has no traceback' "$(<"$SANDBOX/service-json-err")" Traceback
    printf '{"sshd.service":%s}\n' "$content" >"$ROOT/var/lib/haseen/vapt/services.json"
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
actions_untouched services-terminal

actions_fixture vapt-services-reviewed-bindings
python3 - "$ROOT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);base=root/'var/lib/haseen/vapt'
records=json.loads((base/'installed.json').read_text())
for package,unit in [('openssh','unreviewed.service'),('apache','htcacheclean.service')]:
    path='usr/lib/systemd/system/'+unit
    next(r for r in records if r['name']==package)['files'].append(path)
    (root/path).write_text('[Service]\nExecStart=/never-execute\n')
(base/'installed.json').write_text(json.dumps(records))
PY
capture haseen-vapt-service-list --json
assert_eq 'unreviewed SSH unit cannot change selection' sshd.service "$(jq -r '.services[] | select(.id=="ssh") | .unit' <<<"$OUTPUT")"
assert_eq 'auxiliary Apache unit cannot change selection' httpd.service "$(jq -r '.services[] | select(.id=="apache") | .unit' <<<"$OUTPUT")"
for family in ssh postgresql apache nginx; do
    capture haseen-vapt-service-start "$family" --dry-run
    assert_status "$family reviewed real unit set works" 0 "$STATUS"
done
python3 - "$ROOT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);base=root/'var/lib/haseen/vapt';path='usr/lib/systemd/system/beef.service'
record={'name':'beef','version':'1-1','url':'https://github.com/beefproject/beef','files':[path]}
for filename in ('installed.json','repositories.json'):
    p=base/filename;data=json.loads(p.read_text())
    (data.setdefault('blackarch',[]) if isinstance(data,dict) else data).append(record)
    p.write_text(json.dumps(data))
(root/path).write_text('[Service]\nExecStart=/never-execute\n')
PY
capture haseen-vapt-service-list --json
assert_eq 'unreviewed BeEF package/unit binding stays refused' refused "$(jq -r '.services[] | select(.id=="beef") | .ownership' <<<"$OUTPUT")"
capture haseen-vapt-service-start beef --dry-run
assert_status 'unreviewed family unit cannot start' 1 "$STATUS"
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'PY'
import json,sys
p=sys.argv[1];records=json.load(open(p));records.append(dict(next(r for r in records if r['name']=='openssh')))
with open(p,'w') as f:json.dump(records,f)
PY
capture haseen-vapt-service-list --json
assert_eq 'duplicate package ownership stays ambiguous' ambiguous "$(jq -r '.services[] | select(.id=="ssh") | .ownership' <<<"$OUTPUT")"
capture haseen-vapt-service-stop ssh --dry-run
assert_status 'duplicate package ownership refuses action' 1 "$STATUS"
actions_untouched reviewed-bindings
