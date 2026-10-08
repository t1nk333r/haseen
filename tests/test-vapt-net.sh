# shellcheck shell=bash
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
import functools,http.client,http.server,os,pathlib,sys,threading
sys.path.insert(0,sys.argv[1]);from workflow_actions import ConfinedHandler
root=pathlib.Path(sys.argv[2]);directory=root/'usr/share/doc/nmap'
(directory/'outside').symlink_to(root/'usr/share/wordlists/sample.txt')
rootfd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
server=http.server.HTTPServer(('127.0.0.1',0),functools.partial(ConfinedHandler,root_fd=rootfd))
thread=threading.Thread(target=server.serve_forever);thread.start()
def request(path):
    connection=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
    connection.request('GET',path);response=connection.getresponse();status=response.status;data=response.read();connection.close();return status,data
try:
    assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
    for path in ['/outside','/../wordlists/sample.txt','/%2e%2e/wordlists/sample.txt','/']:
        assert request(path)[0]==404,path
finally:
    server.shutdown();thread.join();server.server_close();os.close(rootfd)
filefd=os.open(root/'usr/share/wordlists/sample.txt',os.O_RDONLY)
server=http.server.HTTPServer(('127.0.0.1',0),functools.partial(ConfinedHandler,root_fd=None,file_fd=filefd))
thread=threading.Thread(target=server.serve_forever);thread.start()
try:
    assert request('/file')==(200,b'data\n')
    assert request('/sample.txt')[0]==404
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
