# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-workflow-adversarial
# Any unexpected shell expansion can only create its marker in scratch.
pushd "$SANDBOX" >/dev/null
mkdir -p "$ROOT/etc"
printf '/usr/bin/bash\n' >"$ROOT/etc/shells"
_vapt_stub_log "$ROOT/usr/bin/bash" adversarial-shell
# An executable named after a package exists, but is not owned by it.
_vapt_stub_log "$ROOT/usr/bin/nmap" unowned-package-name
capture haseen-vapt-tool-list --json
assert_status 'discovery survives unowned package-basename executable' 0 "$STATUS"
assert_eq 'package name never creates an entry' 0 "$(jq '[.tools[] | select(.id=="nmap") | .entrypoints[] | select(.id=="/usr/bin/nmap")] | length' <<<"$OUTPUT")"
assert_eq 'data-only remains installed without inferred entry' true "$(jq '.tools[] | select(.id=="wordlists") | .dataOnly' <<<"$OUTPUT")"
for spec in 'tool-help nmap' 'tool-run nmap' 'tool-help wordlists' 'tool-run wordlists'; do
    read -r verb name <<<"$spec"
    capture "haseen-vapt-$verb" "$name" --dry-run
    assert_status "$verb refuses ambiguous/data-only $name" 1 "$STATUS"
done
capture env SHELL=/usr/bin/bash haseen-vapt-tool-run nmap --entry /usr/bin/scan-one --dry-run
assert_status 'session preview with owned documentation' 0 "$STATUS"
assert_eq 'session runs ordinary shell with no command string' '/usr/bin/bash -i' "$(jq -r '.shellArgv | join(" ")' <<<"$OUTPUT")"
# A second installed record forges ownership of an existing executable/document.
python3 -B - "$ROOT/var/lib/haseen/vapt/installed.json" <<'PY'
import json,sys
p=sys.argv[1]; r=json.load(open(p)); r.append({'name':'forged-owner','version':'1-1','url':'https://invalid.example','files':['usr/bin/scan-one','usr/share/man/man1/scan-one.1']});open(p,'w').write(json.dumps(r))
PY
capture haseen-vapt-tool-list --json
assert_status 'forged duplicate ownership returns inventory object' 0 "$STATUS"
assert_eq 'duplicate ownership removes executable authority' 0 "$(jq '[.tools[] | select(.id=="nmap") | .entrypoints[] | select(.id=="/usr/bin/scan-one")] | length' <<<"$OUTPUT")"
capture haseen-vapt-tool-help nmap --entry /usr/bin/scan-one --dry-run
assert_status 'forged ownership cannot authorize documentation' 1 "$STATUS"
# Keep attacker-controlled paths as data even when they contain shell syntax.
python3 -B - "$ROOT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); base=root/'var/lib/haseen/vapt'; p=base/'installed.json';r=json.loads(p.read_text());n=next(x for x in r if x['name']=='nmap')
name='scan;$(touch injected)'; f='usr/bin/'+name; d='usr/share/doc/nmap/'+name+'.txt';n['files'] += [f,d]
(root/f).write_text('#!/bin/sh\nexit 97\n');(root/f).chmod(0o755);(root/d).write_text('hostile basename owned documentation\n');p.write_text(json.dumps(r))
PY
capture haseen-vapt-tool-help nmap --entry '/usr/bin/scan;$(touch injected)' --dry-run
assert_status 'shell syntax in owned basename remains data' 0 "$STATUS"
assert_eq 'owned document has no executable argv' 0 "$(jq '.evidence.argv | length' <<<"$OUTPUT")"
capture haseen-vapt-tool-help nmap --entry '/usr/bin/scan;$(touch injected)'
assert_contains 'hostile basename prints only owned document' "$OUTPUT" 'hostile basename owned documentation'
assert_eq 'no command-substitution side effect' false "$([[ -e injected ]] && echo true || echo false)"
for verb in start stop restart; do
    for expectation in unit fragment absent match; do
        args=()
        case "$expectation" in
            unit) args=(--expect-unit '--no-block') ;;
            fragment) args=(--expect-fragment '/etc/systemd/system/foreign.service') ;;
            match) args=(--expect-unit sshd.service --expect-fragment /usr/lib/systemd/system/sshd.service) ;;
        esac
        capture "haseen-vapt-service-$verb" ssh "${args[@]}" --dry-run
        expected=0; [[ $expectation != unit && $expectation != fragment ]] || expected=1
        assert_status "$verb $expectation expectation guard" "$expected" "$STATUS"
    done
done
assert_eq 'expectation refusals never invoke privileged gateway' '' "$(vapt_calls action-root)"
actions_api service stop ssh old.service /usr/lib/systemd/system/sshd.service
assert_status 'live changed-unit expectation refuses' 1 "$STATUS"
assert_eq 'live changed-unit expectation refuses before privilege' '' "$(vapt_calls action-root)"
actions_api service stop ssh sshd.service /foreign/fragment.service
assert_status 'live changed-fragment expectation refuses' 1 "$STATUS"
assert_eq 'live changed-fragment expectation refuses before privilege' '' "$(vapt_calls action-root)"
actions_api service stop ssh sshd.service /usr/lib/systemd/system/sshd.service
assert_status 'live matching expectations authorize exact selected unit' 0 "$STATUS"
assert_eq 'matching expectations reach only stop argv' "$ROOT/usr/bin/systemctl stop -- sshd.service" "$(vapt_calls action-root)"
assert_eq 'matching expectations run the sysroot service manager' 'stop -- sshd.service' "$(vapt_calls owned-systemctl)"
rm -f "$CALLS/action-root" "$CALLS/owned-systemctl"
actions_api service stop ssh
assert_status 'absent expectations still require current verified ownership' 0 "$STATUS"
assert_eq 'absent expectations do not change selected unit' 'stop -- sshd.service' "$(vapt_calls owned-systemctl)"
rm -f "$CALLS/action-root" "$CALLS/owned-systemctl"
VAPT_CONFIRM=yes VAPT_CHANGE_FRAGMENT=true actions_api service start ssh
assert_status 'fragment swapped during review refuses before privilege' 1 "$STATUS"
assert_eq 'review race has zero privileged calls' '' "$(vapt_calls action-root)$(vapt_calls owned-systemctl)"
python3 -B - "$ROOT/var/lib/haseen/vapt/services.json" <<'PY'
import json,sys
p=sys.argv[1];r=json.load(open(p));r['sshd.service']['FragmentPath']='/usr/lib/systemd/system/sshd.service';open(p,'w').write(json.dumps(r))
PY
# Substitute only the launch/privilege boundary: no terminal or systemctl runs.
# A missing terminal must block start/restart, but must NOT block stop.
for verb in start restart stop; do
    capture bash -s -- "$verb" <<'SH'
set -Eeuo pipefail
source "$HASEEN_PATH/lib/common.sh"
source "$HASEEN_PATH/layers/vapt/workflow_actions.sh"
[[ $HASEEN_SYSROOT == "$VAPT_SANDBOX"/* ]] || exit 97
vapt_action_refuse_fixture() { :; }
export HASEEN_TERMINAL_SH=1
in_floating_terminal() { echo 'TERMINAL-UNAVAILABLE' >&2; return 19; }
vapt_root_exec() { printf 'ROOT-ARGV'; printf ' <%s>' "$@"; printf '\n'; }
confirm() { return 0; }
vapt_service_action "$1" ssh
SH
    if [[ $verb == stop ]]; then
        assert_status 'stop remains usable when terminal unavailable' 0 "$STATUS"
        assert_contains 'stop reaches exact root argv without terminal' "$OUTPUT" "ROOT-ARGV <$ROOT/usr/bin/systemctl> <stop> <--> <sshd.service>"
        assert_not_contains 'stop never asks for a terminal' "$OUTPUT" 'TERMINAL-UNAVAILABLE'
    else
        assert_status "$verb fails when terminal unavailable" 19 "$STATUS"
        assert_not_contains "$verb never privileged without terminal" "$OUTPUT" 'ROOT-ARGV'
    fi
done
for address in localhost example.invalid '127.0.0.1;bad' '[::1]' '127.000.0.1'; do
    capture haseen-vapt-net-listener --bind "$address" 8080 --dry-run
    assert_status "DNS/invalid literal refused: $address" 1 "$STATUS"
done
for port in 0 1 1023 65536 -1 1e4 true '8080;bad'; do
    capture haseen-vapt-net-listener "$port" --dry-run
    assert_status "invalid/privileged port refused: $port" 1 "$STATUS"
done
mkdir -p "$ROOT$XDG_CONFIG_HOME/haseen/vapt"
printf '{"bindAddress":"0.0.0.0"}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
actions_api endpoint listener 8080
assert_status 'configured implicit public bind still requires confirmation' 1 "$STATUS"
assert_eq 'implicit public bind decline starts no program' '' "$(vapt_calls action-user)$(vapt_calls owned-nc)"
printf '{"bindAddress":"127.0.0.1"}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
# Every public phase-2 command has a pure preview, including refusal branches.
before="$(net_manifest)"
for verb in tool-list status doctor menu service-list net-addresses net-remmina; do
    capture "haseen-vapt-$verb" --dry-run --json
    assert_dry_pure "$verb" "$OUTPUT"
done
for verb in tool-help tool-run; do
    capture env SHELL=/usr/bin/bash "haseen-vapt-$verb" nmap --entry '/usr/bin/scan;$(touch injected)' --dry-run
    assert_status "$verb pure preview" 0 "$STATUS"
done
for verb in start stop restart; do
    capture "haseen-vapt-service-$verb" ssh --dry-run --yes
    assert_status "service-$verb pure preview" 0 "$STATUS"
done
capture haseen-vapt-net-listener 8080 --dry-run --yes
assert_status 'listener pure preview' 0 "$STATUS"
capture haseen-vapt-net-http-server /usr/share/doc/nmap 8080 --dry-run --yes
assert_status 'directory pure preview' 0 "$STATUS"
capture haseen-vapt-net-file-server --file /usr/share/wordlists/sample.txt 8080 --dry-run --yes
assert_status 'single-file pure preview' 0 "$STATUS"
for operation in status inspect trust remove; do
    args=(); case "$operation" in inspect|trust) args=(/missing.pem) ;; remove) args=(AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA) ;; esac
    capture haseen-vapt-net-proxy-ca "$operation" "${args[@]}" --dry-run --yes
    assert_dry_pure "CA $operation refusal preview" "$OUTPUT"
done
assert_eq 'all public previews preserve sysroot file set and bytes' "$before" "$(net_manifest)"
# JSON is parsed independently of diagnostic stderr, not by merged capture.
for verb in tool-list status doctor menu service-list net-addresses; do
    printf '{broken' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
    set +e
    "haseen-vapt-$verb" --json >"$SANDBOX/json-out" 2>"$SANDBOX/json-err"
    rc=$?
    set -e
    assert_eq "$verb JSON is exactly one versioned object" '1 1' "$(jq -s -r '"\(length) \(.[0].schemaVersion)"' "$SANDBOX/json-out")"
    assert_not_contains "$verb never puts traceback on stdout" "$(<"$SANDBOX/json-out")" 'Traceback'
    if [[ $verb == status || $verb == doctor ]]; then
        assert_status "$verb malformed-settings semantic exit" 1 "$rc"
        assert_contains "$verb diagnostics on stderr" "$(<"$SANDBOX/json-err")" 'vapt:'
    fi
done
printf '{}\n' >"$ROOT$XDG_CONFIG_HOME/haseen/vapt/workflow.json"
printf 'logical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\nnmap\tnetwork\textra\textra/nmap\tresolved\tinstalled\tfixture\textra\n' >"$ROOT$XDG_STATE_HOME/haseen/vapt/report.tsv"
capture haseen-vapt-status --json
assert_status 'degraded status preserves exit 2' 2 "$STATUS"
assert_eq 'degraded JSON remains one object' degraded "$(jq -r '.provisioning.state' <<<"$OUTPUT")"
# Wrong-shape ownership state must preserve the versioned JSON contract.
for shape in '[]' 'null' '"forged"'; do
    printf '%s\n' "$shape" >"$ROOT/var/lib/haseen/vapt/proxy-ca.json"
    set +e
    haseen-vapt-net-proxy-ca status --json >"$SANDBOX/json-out" 2>"$SANDBOX/json-err"
    rc=$?
    set -e
    assert_status "CA wrong-shape ownership refusal exit: $shape" 1 "$rc"
    capture jq -s -r '"\(length) \(.[0].schemaVersion) \(.[0].state)"' "$SANDBOX/json-out"
    assert_eq "CA wrong-shape ownership one unknown JSON object: $shape" '1 1 unknown' "$OUTPUT"
    assert_not_contains "CA wrong-shape state has no traceback diagnostic: $shape" "$(<"$SANDBOX/json-err")" 'Traceback'
done
printf '[]\n' >"$ROOT/var/lib/haseen/vapt/services.json"
set +e
haseen-vapt-service-list --json >"$SANDBOX/json-out" 2>"$SANDBOX/json-err"
rc=$?
set -e
assert_status 'service wrong-shape manager metadata refusal exit' 1 "$rc"
capture jq -s -r '"\(length) \(.[0].schemaVersion) \(.[0].state)"' "$SANDBOX/json-out"
assert_eq 'service wrong-shape manager one refused JSON object' '1 1 refused' "$OUTPUT"
assert_not_contains 'service wrong-shape manager has no traceback diagnostic' "$(<"$SANDBOX/json-err")" 'Traceback'
assert_eq 'read and preview never execute package-name candidate' '' "$(vapt_calls unowned-package-name)"
assert_eq 'read and preview never open session shell' '' "$(vapt_calls adversarial-shell)"
actions_untouched adversarial-workflow

# Preserve the independent review's nearby-sysroot escape controls. Every
# outside file is still inside this sandbox, never in the owner's HOME.
actions_fixture vapt-nearby-observation
outside="$ROOT/../outside"
mkdir -p "$outside"
services="$ROOT/var/lib/haseen/vapt/services.json"
cp "$services" "$outside/services.json"
python3 - "$outside/services.json" <<'PY'
import json,sys
p=sys.argv[1];rows=json.load(open(p));rows['sshd.service']['ActiveState']='active'
with open(p,'w') as output:json.dump(rows,output)
PY
mv "$services" "$services.saved"
for link in "$(realpath --relative-to="${services%/*}" "$outside/services.json")" "$outside/services.json"; do
    ln -s "$link" "$services"
    capture haseen-vapt-service-list --json
    assert_status 'outside manager snapshot cannot supply service authority' 1 "$STATUS"
    assert_contains 'outside manager snapshot reports observation escape' "$OUTPUT" 'symlink escapes observation root'
    rm "$services"
done
mv "$services.saved" "$services"
config="$ROOT$XDG_CONFIG_HOME/haseen"
mkdir -p "$outside/vapt"
printf '{"bindAddress":"192.0.2.77"}\n' >"$outside/vapt/workflow.json"
rm -rf "$config/vapt"
ln -s "$(realpath --relative-to="$config" "$outside/vapt")" "$config/vapt"
capture haseen-vapt-doctor --json
assert_status 'outside workflow settings ancestor is refused' 1 "$STATUS"
assert_contains 'outside workflow settings report observation escape' "$OUTPUT" 'symlink escapes observation root'
assert_not_contains 'outside workflow bind is never borrowed' "$OUTPUT" '192.0.2.77'
rm "$config/vapt"
report="$ROOT$XDG_STATE_HOME/haseen/vapt/report.tsv"
printf 'nmap\tnetwork\textra\textra/nmap\tresolved\tinstalled\tLEAKED-OUTSIDE\textra\n' >"$outside/report.tsv"
ln -sf "$(realpath --relative-to="${report%/*}" "$outside/report.tsv")" "$report"
capture haseen-vapt-tool-list --all --json
assert_status 'outside recorded resolutions are refused' 1 "$STATUS"
assert_not_contains 'outside recorded resolution diagnostic is never borrowed' "$OUTPUT" 'LEAKED-OUTSIDE'
actions_untouched nearby-observation
