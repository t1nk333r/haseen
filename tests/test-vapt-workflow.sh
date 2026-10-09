# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-workflow-lib.sh"
workflow_fixture vapt-workflow
capture haseen-vapt-tool-help nmap --dry-run
assert_status 'multiple entries require explicit selection' 1 "$STATUS"
assert_contains 'ambiguity explanation' "$OUTPUT" 'ambiguous'
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-one --dry-run
assert_status 'dry usage chooses owned man evidence' 0 "$STATUS"
assert_eq 'no guessed argv for owned man' 0 "$(jq '.evidence.argv | length' <<<"$OUTPUT")"
assert_eq 'dry usage evidence kind' man "$(jq -r '.evidence.kind' <<<"$OUTPUT")"
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-one
assert_status 'explicit document printed without executing man' 0 "$STATUS"
assert_contains 'installed own document displayed' "$OUTPUT" 'Owned usage'
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-two
assert_status 'explicit owned text document' 0 "$STATUS"
assert_contains 'text document displayed' "$OUTPUT" 'Second owned usage'
capture haseen-vapt-tool-help openssh --dry-run
assert_status 'missing help binding explicit refusal' 1 "$STATUS"
assert_contains 'no generic help fallback' "$OUTPUT" 'refused'
capture haseen-vapt-tool-help wordlists --dry-run
assert_status 'data-only cannot run' 1 "$STATUS"
capture haseen-vapt-tool-help nmap --entry '/usr/bin/scan-one; touch bad' --dry-run
assert_status 'hostile ID refusal' 1 "$STATUS"
cp "$ROOT/usr/share/man/man1/scan-one.1" "$ROOT/usr/share/man/man1/scan-one.1.gz"
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'PY'
import json, sys
p=sys.argv[1]; rows=json.load(open(p)); rows[0]['files'].append('usr/share/man/man1/scan-one.1.gz')
with open(p,'w') as f: json.dump(rows,f)
PY
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-one --dry-run
assert_status 'ambiguous matching documents refused' 1 "$STATUS"
rm "$ROOT/usr/share/man/man1/scan-one.1.gz"
mkdir -p "$ROOT/etc"
printf '/usr/bin/bash\n' >"$ROOT/etc/shells"
_vapt_stub_log "$ROOT/usr/bin/bash" workstation-shell
capture env SHELL=/usr/bin/bash haseen-vapt-tool-run nmap --entry /usr/bin/scan-two --dry-run
assert_status 'session dry-run succeeds with installed shell' 0 "$STATUS"
assert_eq 'ordinary shell only not selected tool' '/usr/bin/bash -i' "$(jq -r '.shellArgv | join(" ")' <<<"$OUTPUT")"
assert_eq 'dry-run never opens shell' '' "$(vapt_calls workstation-shell)"
capture haseen-vapt-tool-run nmap --json --dry-run
assert_status 'session JSON rejected' 2 "$STATUS"
capture haseen-vapt-menu --json
assert_status 'menu read succeeds' 0 "$STATUS"
assert_eq 'panel off when absent' false "$(jq '.enabled' <<<"$OUTPUT")"
capture haseen-vapt-menu --enabled
assert_status 'enabled predicate false exit' 1 "$STATUS"
printf '{"plugins":{"haseen.security":{"enabled":true}}}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen-vapt-menu --enabled --json --dry-run
assert_status 'explicit enabled predicate true' 0 "$STATUS"
assert_eq 'merged explicit enable true' true "$(jq '.enabled' <<<"$OUTPUT")"
printf '{"plugins":{"haseen.security":{"enabled":"true"}}}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen-vapt-menu --json
assert_eq 'string truthiness never enables surface' false "$(jq '.enabled' <<<"$OUTPUT")"
for cmd in status doctor; do
    capture "haseen-vapt-$cmd" --json --dry-run
    assert_status "$cmd missing provisioning exit" 1 "$STATUS"
    assert_eq "$cmd exactly one JSON object" 1 "$(jq -s 'length' <<<"$OUTPUT")"
    assert_eq "$cmd version" 1 "$(jq '.schemaVersion' <<<"$OUTPUT")"
    assert_eq "$cmd provisioning missing truth" missing "$(jq -r '.provisioning.state' <<<"$OUTPUT")"
    assert_eq "$cmd owned entry count" 3 "$(jq '.workflow.entrypoints' <<<"$OUTPUT")"
done
printf 'logical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\nnmap\tnetwork\textra\textra/nmap\tresolved\tinstalled\tfixture\textra\n' >"$ROOT$XDG_STATE_HOME/haseen/vapt/report.tsv"
capture haseen-vapt-status --json
assert_status 'status degraded code preserved' 2 "$STATUS"
assert_eq 'status degraded JSON state' degraded "$(jq -r '.provisioning.state' <<<"$OUTPUT")"
# No seed, lock, refresh or changes on any observational command.
assert_eq 'read operations do not seed settings' false "$([[ -e $ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json ]] && echo true || echo false)"
for cmd in tool-list tool-help tool-run doctor menu status; do
    capture "haseen-vapt-$cmd" --help
    assert_status "$cmd help" 0 "$STATUS"
    assert_contains "$cmd help usage" "$OUTPUT" 'Usage:'
done
workflow_no_calls workflow
assert_eq 'no shell executed' '' "$(vapt_calls workstation-shell)"
assert_eq 'no source refresh' '' "$(vapt_calls curl)$(vapt_calls pacman)$(vapt_calls gpg)"
# The v2 settings/capability contract stays valid on semantic refusal.
capture haseen-vapt-doctor --json --dry-run
assert_eq 'five fixed doctor capabilities' 5 "$(jq '.workflow.capabilities | length' <<<"$OUTPUT")"
assert_eq 'unsupported adapters never pretend available' false "$(jq '[.workflow.capabilities[].available] | any' <<<"$OUTPUT")"
assert_eq 'effective bind default' 127.0.0.1 "$(jq -r '.workflow.settings.bindAddress' <<<"$OUTPUT")"
assert_eq 'no alternate port preferences' false "$(jq '.workflow.settings | has("listenerPort")' <<<"$OUTPUT")"
assert_eq 'recorded resolution remains report evidence' resolved "$(jq -r '.provisioning.resolutions[] | select(.id == "nmap") | .state' <<<"$OUTPUT")"
mkdir -p "$ROOT$XDG_CONFIG_HOME/haseen/vapt"
printf '{"showLocalAddresses":true}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
printf '[{"interface":"lo","address":"127.0.0.1","prefixLength":8}]\n' >"$ROOT/var/lib/haseen/vapt/addresses.json"
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-two
assert_contains 'explicit usage may show local addresses' "$OUTPUT" 'Local address: lo 127.0.0.1'
capture haseen-vapt-tool-list --json
assert_not_contains 'inventory never discovers interface output' "$OUTPUT" 'Local address:'
assert_eq 'default list no resolution extension' false "$(jq '.tools[0] | has("resolution")' <<<"$OUTPUT")"
printf '{"bindAddress":"not-a-literal"}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
capture haseen-vapt-doctor --json
assert_eq 'invalid effective settings preserve diagnostics object' 1 "$(jq '.schemaVersion' <<<"$OUTPUT")"
assert_eq 'invalid settings refuse capabilities' true "$(jq '[.workflow.capabilities[].state == "refused"] | all' <<<"$OUTPUT")"
printf '{broken' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
haseen-vapt-doctor --json >"$SANDBOX/json-out" 2>"$SANDBOX/json-err" || true
assert_eq 'operational JSON failure one object' 1 "$(jq -s 'length' "$SANDBOX/json-out")"
assert_contains 'operational diagnostic only stderr' "$(<"$SANDBOX/json-err")" 'vapt:'

# Shared endpoint/confinement/CA inspection is exercised without a live bind,
# trust mutation, live desktop or installed fixture program execution.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import pathlib, sys
sys.path.insert(0, sys.argv[1])
import metadata
from workflow_support import validate_endpoint, confined_path, selected_owned_file
assert validate_endpoint('127.0.0.1', 1024)['loopback']
assert validate_endpoint('::1', 65535)['loopback']
assert validate_endpoint('0.0.0.0', 8080)['requiresConfirmation']
for address,port in [('example.org',8080),('127.0.0.1',80),('::1',65536),('::1','1;bad')]:
    try: validate_endpoint(address,port)
    except ValueError: pass
    else: raise AssertionError('endpoint admitted')
root=pathlib.Path(sys.argv[2])
assert confined_path(root/'usr/share/doc/nmap','scan-two.txt').is_file()
try: confined_path(root/'usr/share/doc/nmap','../../wordlists/sample.txt')
except ValueError: pass
else: raise AssertionError('filesystem escape admitted')
assert selected_owned_file('/usr/share/wordlists/sample.txt',metadata.installed(str(root)),str(root),metadata.observed_resolve).is_file()
try: selected_owned_file('/usr/share/wordlists',metadata.installed(str(root)),str(root),metadata.observed_resolve)
except ValueError: pass
else: raise AssertionError('directory admitted')
print('endpoint, confinement and owned-file checks passed')
PY
assert_status 'shared endpoint and file validators' 0 "$STATUS"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$SANDBOX/key.pem" -out "$SANDBOX/ca.pem" \
    -subj /CN=local-fixture -days 1 -addext basicConstraints=critical,CA:TRUE >/dev/null 2>&1
capture python3 -B - "$VAPT_LAYER" "$SANDBOX" <<'PY'
import pathlib, sys
sys.path.insert(0,sys.argv[1])
from workflow_support import inspect_certificate
base=pathlib.Path(sys.argv[2])
row=inspect_certificate(base/'ca.pem')
assert row['state']=='valid',row
assert row['certificate']['isCa'] and len(row['certificate']['sha256'])==64
assert row['certificate']['notBefore'].endswith('Z')
assert inspect_certificate(base/'key.pem')['state']=='refused'
(base/'bundle.pem').write_bytes((base/'ca.pem').read_bytes()*2)
assert inspect_certificate(base/'bundle.pem')['state']!='valid'
print('certificate inspection checks passed')
PY
assert_status 'shared read-only CA inspector' 0 "$STATUS"
workflow_no_calls shared-support
# Only explicit provisioning seeds; the helper never edits owner bytes.
workflow_fixture vapt-workflow-seed
vapt_api install --groups privacy --dry-run
assert_contains 'provisioning previews workflow seed' "$OUTPUT" 'DRYRUN: seed'
assert_eq 'seed dry-run leaves no settings' false "$([[ -e $ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json ]] && echo true || echo false)"
vapt_api install --groups privacy
assert_eq 'explicit provisioning seeds exact defaults' "$(cat "$HASEEN_PATH/default/vapt/workflow.json")" "$(cat "$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json")"
printf '{"bindAddress":"::1","owner":"keep"}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
vapt_api install --groups privacy
assert_eq 'reapply preserves owner settings bytes' '{"bindAddress":"::1","owner":"keep"}' "$(cat "$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json")"
workflow_no_calls seed
workflow_fixture vapt-workflow-doc-readability
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import argparse,contextlib,io,pathlib,sys
from unittest.mock import patch
sys.path.insert(0,sys.argv[1]);import workflow as wf
root=pathlib.Path(sys.argv[2]);real_open=wf.os.open
def deny_document(path,*args,**kwargs):
    if str(path)=='scan-one.1':raise PermissionError('fixture document denied')
    return real_open(path,*args,**kwargs)
args=argparse.Namespace(tool='nmap',entry='/usr/bin/scan-one',command='tool-help',dry_run=True)
with patch.object(wf.os,'open',side_effect=deny_document):
    tool=next(t for t in wf.discover()['tools'] if t['id']=='nmap')
    entry=next(e for e in tool['entrypoints'] if e['id']==args.entry)
    assert tool['state']=='installed' and not tool['dataOnly']
    assert '/usr/share/man/man1/scan-one.1' in tool['packages'][0]['files'],'owned identity must remain separate'
    assert not entry['documentation'] and entry['usage']['state']=='unavailable'
    try:wf.show_help(args)
    except ValueError:pass
    else:raise AssertionError('preview advertised unreadable evidence')
real_document=wf.open_document;opens=0
def revoked_document(path):
    global opens
    if path=='/usr/share/man/man1/scan-one.1':
        opens+=1
        if opens==2:raise PermissionError('fixture permission revoked after discovery')
    return real_document(path)
args.dry_run=False;output=io.StringIO()
with patch.object(wf,'open_document',side_effect=revoked_document),contextlib.redirect_stdout(output):
    try:wf.show_help(args)
    except PermissionError:pass
    else:raise AssertionError('execution did not reopen document')
assert not output.getvalue()
opens=0;document=root/'usr/share/man/man1/scan-one.1';original=document.read_bytes()
def replaced_document(path):
    global opens
    if path=='/usr/share/man/man1/scan-one.1':
        opens+=1
        if opens==2:
            document.unlink();document.symlink_to(root/'usr/share/wordlists/sample.txt')
    return real_document(path)
try:
    with patch.object(wf,'open_document',side_effect=replaced_document),contextlib.redirect_stdout(output):
        try:wf.show_help(args)
        except ValueError:pass
        else:raise AssertionError('execution did not revalidate ownership')
    assert not output.getvalue()
finally:document.unlink();document.write_bytes(original)
print('unreadable readiness, reopen and ownership revalidation passed')
PY
assert_status 'owned document readability is confined and revalidated' 0 "$STATUS"
workflow_no_calls doc-readability
mkdir -p "$ROOT$XDG_CONFIG_HOME/haseen/vapt"
for content in '[]' null 17 '"wrong"'; do
    printf '%s\n' "$content" >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
    for command in status doctor; do
        status=0
        "haseen-vapt-$command" --json --dry-run >"$SANDBOX/json-out" 2>"$SANDBOX/json-err" || status=$?
        assert_status "$command malformed settings fails honestly" 1 "$status"
        assert_eq "$command wrong-shaped settings exactly one stdout object" 1 "$(jq -s 'length' "$SANDBOX/json-out")"
        assert_eq "$command wrong-shaped settings explicit unavailable" unavailable "$(jq -r '.error.state' "$SANDBOX/json-out")"
        assert_contains "$command malformed settings diagnostics stderr" "$(<"$SANDBOX/json-err")" 'vapt:'
        assert_not_contains "$command malformed settings no traceback" "$(<"$SANDBOX/json-err")" Traceback
    done
done
