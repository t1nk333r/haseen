# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
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

# The indexed source lookup must give the same answer as the linear predicate.
workflow_fixture vapt-index-equivalence
capture python3 -B - "$VAPT_LAYER" "$ROOT" "$FIXTURES" <<'PY'
import copy,json,pathlib,sys
sys.path.insert(0,sys.argv[1]);import workflow as wf;import metadata as meta
def linear(record,config,repos):
    if not meta.allowed_local(record,config,repos):return []
    return [s for s in config if meta.repository_safe(s,config) and meta.ALLOWED.fullmatch(s)
            and meta.closure_identity_ok(s,record)
            and any(p.get('name')==record['name'] and p.get('version')==record.get('version')
                    and p.get('url','').rstrip('/')==record.get('url','').rstrip('/')
                    and not p.get('metadata_unknown') and not meta.forbidden(p) for p in repos.get(s,[]))]
config,repos,_=wf.source_snapshot();records=meta.installed(sys.argv[2]);checked=0
fixtures=list(pathlib.Path(sys.argv[3]).rglob('repositories.json'))
snapshots=[repos]
for path in fixtures:
    fixture=json.loads(path.read_text())
    snapshots.append({'oniomarchy':fixture['records']} if 'records' in fixture else fixture)
for snapshot in snapshots:
    index=wf.index_repositories(snapshot)
    candidates=records+[p for rows in snapshot.values() for p in rows]
    for selected_config in (config,dict(config,oniomarchy=[meta.ONIOMARCHY_POLICY,'Server = '+meta.ONIOMARCHY_SERVER]),
                            dict(config,extra=['Server = http://unreviewed.invalid'],omarchy=['Server = https://example.org'])):
        for record in candidates:
            for change in ({},{'version':'mismatch'},{'url':'https://unreviewed.invalid'},
                           {'url':record.get('url','').rstrip('/')+'/'},{'version':''},{'url':''},
                           {'metadata_unknown':True},{'depends':['omarchy']}):
                row=dict(record,**change)
                assert wf.package_sources(row,selected_config,index)==linear(row,selected_config,snapshot),(row,snapshot)
                checked+=1
# Exercise duplicate records and all rejection predicates in repository data.
for field,value in [('version','wrong'),('url','https://wrong.invalid'),('metadata_unknown',True),('depends',['omarchy'])]:
    snapshot=copy.deepcopy(repos)
    snapshot['extra'][0][field]=value
    snapshot['core']=[dict(snapshot['extra'][0]),dict(records[0])]
    index=wf.index_repositories(snapshot)
    for record in records:
        assert wf.package_sources(record,config,index)==linear(record,config,snapshot)
        checked+=1
print('indexed/linear source equivalence:',checked,'comparisons;',len(snapshots),'fixture snapshots')
# tool-help and tool-run discover only the selected tool; it must be the same record.
for tool in wf.discover()['tools']:
    if tool['state']!='missing':assert wf.discover(tool['id'])['tools']==[tool],tool['id']
PY
assert_status 'indexed source results equal reviewed linear predicates' 0 "$STATUS"
printf '%s\n' "$OUTPUT"

# Discovery must stay linear in installed metadata. The fixture holds 2,103
# installed and 30,003 repository records, and one package with 2,000 owned
# executables, a man page each and 18,000 more files (metasploit ships 33,061
# files and 2,653 executables). Matching each entry against every package
# file took about 70 s for this package alone, and scanning sources per tool
# exceeded the bound at 203 installed / 17,300 records; 20 s allows slow disks.
workflow_fixture vapt-discovery-scale
python3 -B - "$ROOT" <<'PY'
import json,os,pathlib,sys
root=pathlib.Path(sys.argv[1]);base=root/'var/lib/haseen/vapt'
repos=json.loads((base/'repositories.json').read_text());installed=json.loads((base/'installed.json').read_text())
for source in ('core','extra','blackarch'):
    rows=[{'name':source+'-fixture-'+str(i),'version':'1-1','url':'https://example.org/'+source+'/'+str(i)} for i in range(10000)]
    repos.setdefault(source,[]).extend(rows)
    installed.extend(dict(row,files=['usr/share/'+row['name']+'/data']) for row in rows[:700])
files=['usr/bin/tool-%04d'%i for i in range(2000)]+['usr/share/man/man1/tool-%04d.1.gz'%i for i in range(2000)]
files+=['usr/share/nmap/data/%02d/item-%05d'%(i%100,i) for i in range(18000)]
for name in files:
    path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.touch()
    if name.startswith('usr/bin/'):path.chmod(0o755)
next(r for r in installed if r['name']=='nmap')['files'].extend(files)
(base/'repositories.json').write_text(json.dumps(repos));(base/'installed.json').write_text(json.dumps(installed))
PY
capture python3 -B - <<'PY'
import json,subprocess,time
start=time.monotonic()
result=subprocess.run(['haseen-vapt-tool-list','--json'],capture_output=True,text=True,timeout=20)
elapsed=time.monotonic()-start
assert result.returncode==0,result.stderr
data=json.loads(result.stdout)
assert len(data['tools'])==3,data['tools']
assert sum(s['cachedPackages'] for s in data['sources'])>=30000
entries=next(t for t in data['tools'] if t['id']=='nmap')['entrypoints']
assert len(entries)==2002 and all(e['usage']['state']=='ready' for e in entries),len(entries)
print('scale tool-list: 2,103 installed; 30,003 repository records; 2,002 documented entries in 20,005 files;',format(elapsed,'.3f'),'seconds; bound 20 seconds')
PY
assert_status 'large installed/repository/package fixture discovery within bound' 0 "$STATUS"
printf '%s\n' "$OUTPUT"
workflow_no_calls scale-discovery
