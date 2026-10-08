# shellcheck shell=bash
source "$FIXTURES/vapt-workflow-lib.sh"
workflow_fixture vapt-discovery
capture haseen-vapt-tool-list --json
assert_status 'list installed succeeds' 0 "$STATUS"
assert_eq 'single versioned JSON object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
assert_eq 'schema version' 1 "$(jq '.schemaVersion' <<<"$OUTPUT")"
assert_eq 'three installed inventory roots' 3 "$(jq '.tools | length' <<<"$OUTPUT")"
assert_eq 'multiple owned entries not guessed package name' 2 "$(jq '.tools[] | select(.id == "nmap") | .entrypoints | length' <<<"$OUTPUT")"
assert_eq 'entry uses actual owned filename' /usr/bin/scan-one "$(jq -r '.tools[] | select(.id == "nmap") | .entrypoints[0].id' <<<"$OUTPUT")"
assert_eq 'data-only package truth' true "$(jq '.tools[] | select(.id == "wordlists") | .dataOnly' <<<"$OUTPUT")"
assert_eq 'owned desktop metadata' 'Inventory fixture' "$(jq -r '.tools[] | select(.id == "nmap") | .desktopEntries[0].name' <<<"$OUTPUT")"
assert_eq 'owned document readiness' ready "$(jq -r '.tools[] | select(.id == "nmap") | .entrypoints[0].usage.state' <<<"$OUTPUT")"
assert_eq 'no generic help guess' unavailable "$(jq -r '.tools[] | select(.id == "openssh") | .entrypoints[0].usage.state' <<<"$OUTPUT")"
capture haseen-vapt-tool-list --json --all --dry-run
assert_status 'offline all diagnostics succeeds' 0 "$STATUS"
assert_eq '204 inventory items retained' 204 "$(jq '.tools | length' <<<"$OUTPUT")"
assert_eq 'missing inventory evidence' missing "$(jq -r '.tools[] | select(.id == "airspy") | .state' <<<"$OUTPUT")"
capture haseen-vapt-tool-list --group privacy --json
assert_eq 'group limits output' 0 "$(jq '.tools | length' <<<"$OUTPUT")"
capture haseen-vapt-tool-list --group nonexistent
assert_status 'unknown group usage failure' 2 "$STATUS"
capture haseen-vapt-tool-list extra
assert_status 'extra operand rejected' 2 "$STATUS"
# Executable ownership must remain unique; a symlink cannot borrow a foreign entry.
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
p = root / 'var/lib/haseen/vapt/installed.json'
rows = json.loads(p.read_text())
rows.append({'name':'foreign', 'version':'1', 'url':'https://example.org', 'files':['usr/bin/scan-two']})
p.write_text(json.dumps(rows))
(root / 'usr/bin/scan-one').unlink()
(root / 'usr/bin/scan-one').symlink_to('/usr/bin/scan-two')
PY
capture haseen-vapt-tool-list --json
assert_eq 'ambiguous owner and foreign symlink excluded' 0 "$(jq '.tools[] | select(.id == "nmap") | .entrypoints | length' <<<"$OUTPUT")"
# Filesystem/package metadata is observed rather than successful report text.
printf 'logical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\nairspy\tsdr\textra\textra/airspy\tresolved\tinstalled\told report\textra\n' >"$ROOT$XDG_STATE_HOME/haseen/vapt/report.tsv"
capture haseen-vapt-tool-list --all --json
assert_eq 'report cannot fabricate installed tool' missing "$(jq -r '.tools[] | select(.id == "airspy") | .state' <<<"$OUTPUT")"
workflow_no_calls discovery
# Real pacman local file inventory, not only installed.json fixture protocol.
rm "$ROOT/var/lib/haseen/vapt/installed.json"
mkdir -p "$ROOT/var/lib/pacman/local/nmap-1-1"
printf '%%NAME%%\nnmap\n\n%%VERSION%%\n1-1\n\n%%URL%%\nhttps://nmap.org\n\n' >"$ROOT/var/lib/pacman/local/nmap-1-1/desc"
printf '%%FILES%%\nusr/bin/scan-two\nusr/share/doc/nmap/scan-two.txt\n\n' >"$ROOT/var/lib/pacman/local/nmap-1-1/files"
capture haseen-vapt-tool-list --json
assert_status 'pacman local DB discovery succeeds' 0 "$STATUS"
assert_eq 'pacman file entry discovered' /usr/bin/scan-two "$(jq -r '.tools[0].entrypoints[0].id' <<<"$OUTPUT")"
workflow_no_calls local-db
# Pinned native state is read from existing metadata verifier, and console
# entries from distribution RECORD; no importlib or installed Python runs.
workflow_fixture vapt-native-discovery
vapt_repos "${VAPT_BASE[@]}"
vapt_system_python
store="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
vapt_native_env "$store" frida-tools frida-tools==13.7.1 frida 13.7.1
info="$store/venvs/frida-tools/lib/python3.14/site-packages/frida_tools-13.7.1.dist-info"
printf '../../../bin/frida,,\n' >"$info/RECORD"
capture haseen-vapt-tool-list --all --json
assert_status 'native metadata observation succeeds' 0 "$STATUS"
assert_eq 'native pinned ownership exact' exact "$(jq -r '.tools[] | select(.id == "frida-tools") | .native.state' <<<"$OUTPUT")"
assert_eq 'native RECORD console entry' native "$(jq -r '.tools[] | select(.id == "frida-tools") | .entrypoints[0].kind' <<<"$OUTPUT")"
assert_eq 'native console path evidence' "$XDG_DATA_HOME/haseen/vapt/pipx/venvs/frida-tools/bin/frida" "$(jq -r '.tools[] | select(.id == "frida-tools") | .entrypoints[0].path' <<<"$OUTPUT")"
workflow_no_calls native-discovery
