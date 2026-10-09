# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-net
capture haseen-vapt-net-addresses --json --dry-run
assert_status 'local address read' 0 "$STATUS"
assert_eq 'one address JSON object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
assert_eq 'fixture loopback assigned address' 127.0.0.1 "$(jq -r '.addresses[0].address' <<<"$OUTPUT")"
for bad in 'example.org' '127.0.0.1;bad'; do
    capture haseen-vapt-net-listener --bind "$bad" 8080 --dry-run
    assert_status 'literal addresses only' 1 "$STATUS"
done
for bad in 80 65536 '8080;bad'; do
    capture haseen-vapt-net-listener "$bad" --dry-run
    assert_status 'unelevated explicit port range' 1 "$STATUS"
done
capture haseen-vapt-net-listener --dry-run
assert_status 'blank port not implicit launch' 1 "$STATUS"
assert_contains 'blank port explicit selection' "$OUTPUT" 'selection required'
capture haseen-vapt-net-listener 8080 --dry-run
assert_status 'listener pure preview' 0 "$STATUS"
assert_contains 'listener defaults loopback' "$OUTPUT" '127.0.0.1'
assert_not_contains 'no hypothetical launch success' "$OUTPUT" 'completed'
capture haseen-vapt-net-listener --json 8080 --dry-run
assert_status 'foreground listener no JSON mode' 2 "$STATUS"
capture haseen-vapt-net-listener 8080
assert_status 'fixture listener live refusal' 1 "$STATUS"
actions_api endpoint listener --bind 0.0.0.0 8080
assert_status 'non-loopback confirmation decline' 1 "$STATUS"
assert_eq 'non-loopback decline no execution' '' "$(vapt_calls action-user)"
VAPT_CONFIRM=yes actions_api endpoint listener --bind 0.0.0.0 8080
assert_status 'accepted listener reaches fixture argv gateway' 0 "$STATUS"
assert_contains 'neutral listener exact owned adapter args' "$(vapt_calls action-user)" '/usr/bin/nc -4 -l -n -- 0.0.0.0 8080'
assert_not_contains 'no listener shell on connection' "$(vapt_calls action-user)" ' -e '
rm -f "$CALLS/action-user" "$CALLS/confirm"
actions_api endpoint listener 8080
assert_status 'loopback listener no confirmation required' 0 "$STATUS"
assert_eq 'loopback listener no confirmation' '' "$(vapt_calls confirm)"
capture haseen-vapt-net-http-server /usr/share/doc/nmap 8080 --dry-run
assert_status 'explicit directory preview' 0 "$STATUS"
capture haseen-vapt-net-http-server --dry-run
assert_status 'blank directory no implicit serving' 1 "$STATUS"
capture haseen-vapt-net-file-server --file /usr/share/wordlists/sample.txt 8080 --dry-run
assert_status 'owned single-file preview' 0 "$STATUS"
capture haseen-vapt-net-file-server --file /usr/share/wordlists 8080 --dry-run
assert_status 'single-file refuses directory' 1 "$STATUS"
ln -s /etc/passwd "$ROOT/usr/share/wordlists/escape"
capture haseen-vapt-net-file-server --file /usr/share/wordlists/escape 8080 --dry-run
assert_status 'single-file refuses unowned symlink escape' 1 "$STATUS"
ln "$ROOT/usr/share/wordlists/sample.txt" "$ROOT/linked-sample"
capture haseen-vapt-net-file-server --file /usr/share/wordlists/sample.txt 8080 --dry-run
assert_status 'single-file selection refuses multiple links' 1 "$STATUS"
rm "$ROOT/linked-sample"
capture haseen-vapt-net-remmina --dry-run
assert_status 'client UI preview' 0 "$STATUS"
assert_contains 'verified client path not target' "$OUTPUT" '/usr/bin/remmina (no connection or credentials)'
capture haseen-vapt-net-remmina
assert_status 'fixture client refuses live launch' 1 "$STATUS"
capture haseen-vapt-doctor --json --dry-run
assert_eq 'reviewed listener capability available' true "$(jq '.workflow.capabilities[] | select(.id=="listener") | .available' <<<"$OUTPUT")"
assert_eq 'single-file unset selection truth' selection-required "$(jq -r '.workflow.capabilities[] | select(.id=="enumeration-host") | .state' <<<"$OUTPUT")"
assert_eq 'single-file capability names exact CLI command' net-file-server "$(jq -r '.workflow.capabilities[] | select(.id=="enumeration-host") | .command' <<<"$OUTPUT")"
# Exercise the actual confined handler only on loopback, with inert fixture
# bytes. Requests cannot execute, escape, follow links or expose a directory.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import functools,http.client,os,pathlib,socket,sys,threading,time
from unittest.mock import patch
sys.path.insert(0,sys.argv[1]);from workflow_actions import ConfinedHandler,LiteralHTTPServer
root=pathlib.Path(sys.argv[2]);directory=root/'usr/share/doc/nmap'
(directory/'outside').symlink_to(root/'usr/share/wordlists/sample.txt')
(root/'external-secret.txt').write_bytes(b'outside selected directory\n')
os.link(root/'external-secret.txt',directory/'hardlink')
rootfd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
with patch.object(socket,'getfqdn',side_effect=AssertionError('reverse lookup')),patch.object(socket,'gethostbyaddr',side_effect=AssertionError('reverse lookup')):
    server=LiteralHTTPServer(('127.0.0.1',0),functools.partial(ConfinedHandler,root_fd=rootfd))
server.request_idle_seconds=.1;server.request_total_seconds=.35
thread=threading.Thread(target=server.serve_forever);thread.start()
def request(path):
    connection=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
    connection.request('GET',path);response=connection.getresponse();status=response.status;data=response.read();connection.close();return status,data
try:
    assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
    idle=socket.create_connection(('127.0.0.1',server.server_port),timeout=2)
    try:assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
    finally:idle.close()
    slow=socket.create_connection(('127.0.0.1',server.server_port),timeout=2);sent=[]
    def drip():
        for byte in b'GET /scan-two.txt HTTP/1.0\r\n':
            try:slow.sendall(bytes([byte]));sent.append(byte)
            except OSError:break
            time.sleep(.05)
    dripper=threading.Thread(target=drip);dripper.start()
    try:
        assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
        dripper.join(2);assert not dripper.is_alive() and len(sent)<26
    finally:slow.close();dripper.join(2)
    large=directory/'large.bin'
    with large.open('wb') as output:output.truncate(16*1024*1024)
    stalled=socket.socket();stalled.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024)
    stalled.settimeout(2);stalled.connect(('127.0.0.1',server.server_port))
    try:
        stalled.sendall(b'GET /large.bin HTTP/1.0\r\n\r\n')
        assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
    finally:stalled.close();large.unlink()
    for path in ['/outside','/hardlink','/../wordlists/sample.txt','/%2e%2e/wordlists/sample.txt','/']:
        assert request(path)[0]==404,path
    os.link(directory/'scan-two.txt',root/'late-link')
    assert request('/scan-two.txt')[0]==404
    (root/'late-link').unlink()
    assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
finally:
    server.shutdown();thread.join();server.server_close();os.close(rootfd)
filefd=os.open(root/'usr/share/wordlists/sample.txt',os.O_RDONLY)
server=LiteralHTTPServer(('127.0.0.1',0),functools.partial(ConfinedHandler,root_fd=None,file_fd=filefd))
thread=threading.Thread(target=server.serve_forever);thread.start()
try:
    assert request('/file')==(200,b'data\n')
    assert request('/sample.txt')[0]==404
    os.link(root/'usr/share/wordlists/sample.txt',root/'single-extra')
    assert request('/file')[0]==404
    (root/'single-extra').unlink()
    assert request('/file')==(200,b'data\n')
finally:
    server.shutdown();thread.join();server.server_close();os.close(filefd)
print('confined directory and fixed single-file endpoint passed')
PY
assert_status 'actual confined HTTP handler loopback exercise' 0 "$STATUS"
mkdir -p "$ROOT/certificates"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ROOT/certificates/key.pem" -out "$ROOT/certificates/ca.pem" \
    -subj /CN=local-fixture -days 1 -addext basicConstraints=critical,CA:TRUE >/dev/null 2>&1
capture haseen-vapt-net-proxy-ca inspect /certificates/ca.pem --json --dry-run
assert_status 'read-only CA inspection' 0 "$STATUS"
assert_eq 'CA classification' valid "$(jq -r '.state' <<<"$OUTPUT")"
assert_eq 'genuine extension establishes CA' true "$(jq '.certificate.isCa' <<<"$OUTPUT")"
fingerprint="$(jq -r '.certificate.sha256' <<<"$OUTPUT")"
assert_eq 'full SHA-256 fingerprint length' 64 "${#fingerprint}"
assert_not_contains 'no PEM content in JSON' "$OUTPUT" 'BEGIN CERTIFICATE'
capture haseen-vapt-net-proxy-ca inspect /certificates/key.pem --json
assert_status 'private-key refusal' 1 "$STATUS"
assert_eq 'private-key explicit classification' refused "$(jq -r '.state' <<<"$OUTPUT")"
cat "$ROOT/certificates/ca.pem" "$ROOT/certificates/ca.pem" >"$ROOT/certificates/bundle.pem"
capture haseen-vapt-net-proxy-ca inspect /certificates/bundle.pem --json
assert_status 'bundle refusal' 1 "$STATUS"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ROOT/certificates/non-ca.key" -out "$ROOT/certificates/non-ca.pem" \
    -subj /CN=non-ca-fixture -days 1 -addext basicConstraints=critical,CA:FALSE >/dev/null 2>&1
capture haseen-vapt-net-proxy-ca inspect /certificates/non-ca.pem --json
assert_status 'non-CA refusal' 1 "$STATUS"
assert_eq 'non-CA classified without admitting trust' false "$(jq '.certificate.isCa' <<<"$OUTPUT")"
# Names are attacker-controlled text, never the basicConstraints authority.
for variant in absent false malformed malformed-critical; do
    extension=()
    case "$variant" in
    false) extension=(-addext 'basicConstraints=critical,CA:FALSE') ;;
    malformed) extension=(-addext basicConstraints=DER:43:41:3A:54:52:55:45) ;;
    malformed-critical) extension=(-addext 'basicConstraints=critical,DER:43:41:3A:54:52:55:45') ;;
    esac
    /usr/bin/openssl req -new -x509 -key "$ROOT/certificates/key.pem" -config /dev/null \
        -subj /CN=CA:TRUE -days 1 "${extension[@]}" -out "$ROOT/certificates/spoof-$variant.pem" >/dev/null 2>&1
    capture haseen-vapt-net-proxy-ca inspect "/certificates/spoof-$variant.pem" --json
    assert_status "$variant extension rejects name spoofing" 1 "$STATUS"
    assert_eq "$variant extension not a CA" false "$(jq '.certificate.isCa' <<<"$OUTPUT")"
    assert_eq "$variant extension explicit refusal" refused "$(jq -r '.state' <<<"$OUTPUT")"
    assert_contains "$variant spoof present in subject" "$(jq -r '.certificate.subject' <<<"$OUTPUT")" 'CA:TRUE'
    assert_contains "$variant spoof present in issuer" "$(jq -r '.certificate.issuer' <<<"$OUTPUT")" 'CA:TRUE'
done
/usr/bin/openssl req -new -x509 -key "$ROOT/certificates/key.pem" -config /dev/null \
    -subj /CN=noncritical-fixture -days 1 -addext basicConstraints=CA:TRUE -out "$ROOT/certificates/noncritical-ca.pem" >/dev/null 2>&1
capture haseen-vapt-net-proxy-ca inspect /certificates/noncritical-ca.pem --json
assert_status 'genuine noncritical CA inspection' 0 "$STATUS"
assert_eq 'genuine noncritical CA classification' valid "$(jq -r '.state' <<<"$OUTPUT")"
assert_eq 'genuine noncritical extension establishes CA' true "$(jq '.certificate.isCa' <<<"$OUTPUT")"
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import hashlib,pathlib,ssl,sys
sys.path.insert(0,sys.argv[1])
from workflow_actions import certificate_payload
from workflow_ca import mutate
from workflow_support import inspect_certificate_data
root=pathlib.Path(sys.argv[2])
for variant in ('absent','false','malformed','malformed-critical'):
    path='/certificates/spoof-'+variant+'.pem';pem=(root/path.lstrip('/')).read_bytes()
    der=ssl.PEM_cert_to_DER_cert(pem.decode('ascii'));fingerprint=hashlib.sha256(der).hexdigest().upper()
    assert inspect_certificate_data(der)['state']=='refused'
    try:certificate_payload(path,fingerprint)
    except ValueError:pass
    else:raise AssertionError('payload admitted spoofed CA '+variant)
    target=root/('rejected-'+variant)
    try:mutate('trust',fingerprint,der,root=str(target),updater=lambda:(_ for _ in ()).throw(AssertionError('updater invoked')))
    except ValueError:pass
    else:raise AssertionError('privileged validation admitted spoofed CA '+variant)
    assert not target.exists(),'rejected trust wrote state'
print('inspection, payload and privileged classifier agree')
PY
assert_status 'all CA admission paths reject adversarial extension fixtures' 0 "$STATUS"
before="$(net_manifest)"
capture haseen-vapt-service-list --json --dry-run
capture haseen-vapt-net-addresses --json --dry-run
capture haseen-vapt-net-listener 8080 --dry-run
capture haseen-vapt-net-http-server /usr/share/doc/nmap 8080 --dry-run
capture haseen-vapt-net-file-server --file /usr/share/wordlists/sample.txt 8080 --dry-run
capture haseen-vapt-net-remmina --dry-run
capture haseen-vapt-net-proxy-ca status --json --dry-run
assert_eq 'all previews leave sysroot bytes and file set unchanged' "$before" "$(net_manifest)"
capture haseen-vapt-net-proxy-ca trust /certificates/ca.pem --yes --dry-run
assert_status 'pure trust preview' 0 "$STATUS"
assert_contains 'typed fingerprint remains required' "$OUTPUT" 'require typed SHA-256'
assert_eq 'trust preview no anchor directory created' false "$([[ -d $ROOT/etc/ca-certificates/trust-source/anchors ]] && echo true || echo false)"
VAPT_YES=true actions_api ca trust /certificates/ca.pem
assert_status '--yes never bypasses typed fingerprint' 1 "$STATUS"
assert_eq 'wrong/missing typed fingerprint no root trust' '' "$(vapt_calls action-root)"
VAPT_YES=true VAPT_TYPED="$fingerprint" actions_api ca trust /certificates/ca.pem
assert_status 'typed exact fingerprint reaches fixture gateway' 0 "$STATUS"
assert_contains 'fingerprint bound root trust' "$(vapt_calls action-root)" "workflow_ca.py trust $fingerprint"
# Actual root-helper filesystem behaviour is exercised through explicit local
# library-only test seams; no real trust updater or machine anchor is touched.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import hashlib,pathlib,ssl,sys
sys.path.insert(0,sys.argv[1]);from workflow_ca import mutate,ca_status,ANCHORS
root=pathlib.Path(sys.argv[2]);der=ssl.PEM_cert_to_DER_cert((root/'certificates/ca.pem').read_text());fingerprint=hashlib.sha256(der).hexdigest().upper();updates=[]
mutate('trust',fingerprint,der,root=str(root),updater=lambda:updates.append('trust'))
assert ca_status(str(root))['state']=='owned'
anchor=root/(ANCHORS.lstrip('/')+'/haseen-vapt-'+fingerprint+'.crt');original=anchor.read_bytes();anchor.write_bytes(b'owner modification')
assert ca_status(str(root))['state']=='modified'
try:mutate('remove',fingerprint,root=str(root),updater=lambda:updates.append('remove'))
except ValueError:pass
else:raise AssertionError('modified anchor removed')
assert anchor.read_bytes()==b'owner modification';anchor.write_bytes(original)
mutate('remove',fingerprint,root=str(root),updater=lambda:updates.append('remove'))
assert ca_status(str(root))['state']=='none' and updates==['trust','remove']
failure=root/'updater-failure'
import subprocess
def failed_updater():raise subprocess.CalledProcessError(1,['fixture updater'])
try:mutate('trust',fingerprint,der,root=str(failure),updater=failed_updater)
except ValueError as error:assert 'no complete success' in str(error)
else:raise AssertionError('updater failure called success')
assert ca_status(str(failure))['state']=='unknown'
print('owned trust/removal and modified-anchor preservation passed')
PY
assert_status 'fingerprint ownership transaction fixture' 0 "$STATUS"
for cmd in service-list service-start service-stop service-restart net-addresses net-listener net-http-server net-file-server net-proxy-ca net-remmina; do
    capture "haseen-vapt-$cmd" --help
    assert_status "$cmd help" 0 "$STATUS"
done
assert_eq 'no real privileged calls' '' "$(vapt_calls sudo)$(vapt_calls systemctl)"
actions_untouched net
for content in '[]' null 17 '"wrong"'; do
    printf '%s\n' "$content" >"$ROOT/var/lib/haseen/vapt/proxy-ca.json"
    capture haseen-vapt-net-proxy-ca status --json
    assert_status 'wrong-shaped CA record is refusal' 1 "$STATUS"
    assert_eq 'wrong-shaped CA status one object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
    assert_eq 'wrong-shaped CA status explicit unknown' unknown "$(jq -r '.state' <<<"$OUTPUT")"
    capture haseen-vapt-net-proxy-ca inspect /var/lib/haseen/vapt/proxy-ca.json --json
    assert_status 'wrong-shaped JSON is not certificate input' 1 "$STATUS"
    assert_eq 'wrong-shaped inspect one object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
    assert_eq 'wrong-shaped inspect explicit invalid' invalid "$(jq -r '.state' <<<"$OUTPUT")"
    for command in status doctor; do
        capture "haseen-vapt-$command" --json --dry-run
        assert_eq "$command wrong-shaped auxiliary record one object" 1 "$(jq -s 'length' <<<"$OUTPUT")"
        assert_eq "$command preserves versioned diagnostics" 1 "$(jq '.schemaVersion' <<<"$OUTPUT")"
        assert_not_contains "$command malformed record no traceback" "$OUTPUT" Traceback
    done
    assert_eq 'doctor refuses unsafe CA readiness' refused "$(jq -r '.workflow.capabilities[] | select(.id=="proxy-ca") | .state' <<<"$OUTPUT")"
done
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import json,pathlib,sys
sys.path.insert(0,sys.argv[1]);from workflow_ca import ca_status
root=pathlib.Path(sys.argv[2]);path=root/'var/lib/haseen/vapt/proxy-ca.json'
record={'schemaVersion':1,'sha256':'A'*64,'contentSha256':'0'*64,'state':'created','subject':'fixture','issuer':'fixture'}
for key in record:
    for value in ([],None,17,True):
        row=dict(record);row[key]=value;path.write_text(json.dumps(row))
        assert ca_status(str(root))['state']=='unknown',(key,value)
row=dict(record);row['state']='future';path.write_text(json.dumps(row))
assert ca_status(str(root))['state']=='unknown'
path.unlink()
print('all consumed CA record fields validate without exception masking')
PY
assert_status 'CA consumed field types/enums refuse safely' 0 "$STATUS"
capture python3 -B - "$FIXTURES" "$CALLS" <<'PY'
import json,os,pathlib,signal,socket,subprocess,sys,time
fixtures=pathlib.Path(sys.argv[1]);calls=pathlib.Path(sys.argv[2]);adapter=calls/'foreground-adapter'
adapter.write_text('#!/usr/bin/python3\nimport json,os,socket,time\ns=socket.socket();s.bind(("127.0.0.1",0));s.listen(1)\nwith open(os.environ["VAPT_FOREGROUND_READY"],"w") as f:json.dump({"pid":os.getpid(),"port":s.getsockname()[1]},f)\nwhile True:time.sleep(1)\n')
adapter.chmod(0o755)
for kind,args in [('listener',['8080']),('http-server',['/explicit-fixture','8080'])]:
    for stop in (signal.SIGTERM,signal.SIGHUP):
        ready=calls/('ready-'+kind+'-'+str(stop));env=dict(os.environ,VAPT_REAL_FOREGROUND='true',VAPT_ENDPOINT_ADAPTER=str(adapter),VAPT_FOREGROUND_READY=str(ready),VAPT_CONFIRM='yes')
        process=subprocess.Popen(['/usr/bin/bash',str(fixtures/'vapt-actions-runner.sh'),'endpoint',kind,*args],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        try:
            deadline=time.monotonic()+3
            while not ready.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            assert ready.exists(),process.communicate(timeout=1)
            data=json.loads(ready.read_text());assert data['pid']==process.pid,'wrapper did not hand off its pid'
            process.send_signal(stop);assert process.wait(timeout=2)==-stop,'signal/exit code not propagated'
            with socket.socket() as probe:probe.bind(('127.0.0.1',data['port']))
        finally:
            if process.poll() is None:process.kill();process.wait(timeout=2)
print('SIGTERM/SIGHUP handoff reclaims literal loopback endpoints')
PY
assert_status 'foreground wrapper signals leave no helper endpoint behind' 0 "$STATUS"
actions_fixture vapt-net-unverified
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'PY'
import json,sys
p=sys.argv[1];rows=json.load(open(p));next(r for r in rows if r['name']=='openbsd-netcat')['url']='https://foreign.invalid/'
with open(p,'w') as f:json.dump(rows,f)
PY
capture haseen-vapt-net-listener 8080 --dry-run
assert_status 'unverified installed listener adapter refused' 1 "$STATUS"
capture haseen-vapt-doctor --json --dry-run
assert_eq 'unverified prerequisite still present diagnostic' true "$(jq '.workflow.capabilities[] | select(.id=="listener") | .installed' <<<"$OUTPUT")"
assert_eq 'unverified adapter no available action' false "$(jq '.workflow.capabilities[] | select(.id=="listener") | .available' <<<"$OUTPUT")"
actions_untouched unverified-adapter
actions_fixture vapt-scoped-endpoints
for address in fe80::1%enp5s0 fe80::1%wlan0 fe80::1%lo; do
    capture haseen-vapt-net-listener --bind "$address" 8080 --dry-run
    assert_status 'scoped IPv6 literal accepted offline' 0 "$STATUS"
    assert_contains 'scoped address preserved exactly once' "$OUTPUT" "$address"
done
capture haseen-vapt-net-listener --bind fe80::1%enp5s0%enp5s0 8080 --dry-run
assert_status 'duplicate IPv6 scope refused' 1 "$STATUS"
printf '[{"interface":"enp5s0","address":"fe80::1%%enp5s0","prefixLength":64}]\n' >"$ROOT/var/lib/haseen/vapt/addresses.json"
capture haseen-vapt-net-addresses --json
assert_eq 'CLI address inventory emits one complete scoped literal' fe80::1%enp5s0 "$(jq -r '.addresses[0].address' <<<"$OUTPUT")"
actions_untouched scoped-endpoints
