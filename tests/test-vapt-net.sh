# shellcheck shell=bash
# haseen:covers bin/haseen-vapt-doctor bin/haseen-vapt-status bin/haseen-vapt-net-*
# haseen:covers bin/haseen-vapt-service-* share/haseen/VERSION share/haseen/default/shell.json
# haseen:covers share/haseen/default/vapt/** share/haseen/layers/vapt/** share/haseen/lib/layers.sh
# haseen:covers share/haseen/lib/packages.sh share/haseen/lib/preflight.sh
# haseen:covers share/haseen/lib/terminal.sh tests/fixtures/vapt-host/**
# haseen:covers tests/fixtures/vapt-actions-lib.sh tests/fixtures/vapt-actions-runner.sh
# haseen:covers tests/fixtures/vapt-driver.py tests/fixtures/vapt-lib.sh
# haseen:covers tests/fixtures/vapt-workflow-lib.sh
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-net
capture haseen-vapt-net-addresses --json --dry-run
assert_status 'local address read' 0 "$STATUS"
assert_eq 'one address JSON object' 1 "$(jq -s 'length' <<<"$OUTPUT")"
assert_eq 'fixture loopback assigned address' 127.0.0.1 "$(jq -r '.addresses[0].address' <<<"$OUTPUT")"
# Address fixtures must not borrow metadata from outside their sysroot, even
# when either the final file or its containing directory is a symlink.
addresses_fixture="$ROOT/var/lib/haseen/vapt/addresses.json"
outside_addresses="$ROOT/../outside-addresses.json"
printf '[{"interface":"fixtureoutside","address":"192.0.2.9","prefixLength":24}]\n' >"$outside_addresses"
mv "$addresses_fixture" "$addresses_fixture.saved"
ln -s ../../../../../outside-addresses.json "$addresses_fixture"
capture haseen-vapt-net-addresses --json --dry-run
assert_status 'address fixture file escape refused' 1 "$STATUS"
assert_not_contains 'external file address not returned' "$OUTPUT" '192.0.2.9'
rm "$addresses_fixture"
mv "$addresses_fixture.saved" "$addresses_fixture"
mv "$ROOT/var/lib/haseen/vapt" "$ROOT/var/lib/haseen/vapt.saved"
mkdir "$ROOT/../outside-vapt"
cp "$outside_addresses" "$ROOT/../outside-vapt/addresses.json"
ln -s ../../../../outside-vapt "$ROOT/var/lib/haseen/vapt"
capture haseen-vapt-net-addresses --json --dry-run
assert_status 'address fixture ancestor escape refused' 1 "$STATUS"
assert_not_contains 'external ancestor address not returned' "$OUTPUT" '192.0.2.9'
rm "$ROOT/var/lib/haseen/vapt"
mv "$ROOT/var/lib/haseen/vapt.saved" "$ROOT/var/lib/haseen/vapt"
rm "$ROOT/../outside-vapt/addresses.json" "$outside_addresses"
rmdir "$ROOT/../outside-vapt"
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
assert_eq 'non-loopback decline runs no adapter' '' "$(vapt_calls owned-nc)"
VAPT_CONFIRM=yes actions_api endpoint listener --bind 0.0.0.0 8080
assert_status 'accepted listener runs the owned adapter' 0 "$STATUS"
assert_eq 'neutral listener exact owned adapter args, no -e' '-4 -l -n -- 0.0.0.0 8080' "$(vapt_calls owned-nc)"
assert_eq 'listener hands over to the sysroot adapter' "exec $ROOT/usr/bin/nc -4 -l -n -- 0.0.0.0 8080" "$(vapt_calls action-user)"
rm -f "$CALLS/action-user" "$CALLS/confirm" "$CALLS/owned-nc"
actions_api endpoint listener 8080
assert_status 'loopback listener no confirmation required' 0 "$STATUS"
assert_eq 'loopback listener no confirmation' '' "$(vapt_calls confirm)"
assert_eq 'loopback listener runs the owned adapter' '-4 -l -n -- 127.0.0.1 8080' "$(vapt_calls owned-nc)"
rm -f "$CALLS/owned-nc"
# Exposure consent is interactive only: --yes and a piped terminal cannot give
# it, while a loopback listener, which exposes nothing, needs none.
VAPT_YES=true actions_api endpoint listener --bind 0.0.0.0 8080
assert_status '--yes cannot accept a non-loopback listener' 1 "$STATUS"
assert_contains '--yes refusal explains itself' "$OUTPUT" '--yes cannot accept exposing'
VAPT_YES=true actions_api endpoint http-server /usr/share/doc/nmap 8080
assert_status '--yes cannot accept serving a directory' 1 "$STATUS"
VAPT_YES=true actions_api endpoint enumeration-host --file /usr/share/wordlists/sample.txt 8080
assert_status '--yes cannot accept serving a file' 1 "$STATUS"
VAPT_INTERACTIVE=false VAPT_CONFIRM=yes actions_api endpoint listener --bind 0.0.0.0 8080
assert_status 'piped answer cannot accept a non-loopback listener' 1 "$STATUS"
assert_contains 'piped refusal explains itself' "$OUTPUT" 'needs an interactive terminal'
assert_eq 'refused consent starts no adapter or server' '' "$(vapt_calls owned-nc)$(vapt_calls owned-python)$(vapt_calls confirm)"
VAPT_YES=true actions_api endpoint listener 8080
assert_status '--yes loopback listener needs no consent' 0 "$STATUS"
assert_eq '--yes loopback listener runs the owned adapter' '-4 -l -n -- 127.0.0.1 8080' "$(vapt_calls owned-nc)"
rm -f "$CALLS/owned-nc" "$CALLS/action-user"
capture bash -c 'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/layers/vapt/workflow_actions.sh"
confirm() { echo CONFIRM-ASKED; }; vapt_exposure_consent "Expose?"' </dev/null
assert_status 'consent without a terminal on stdin is refused' 1 "$STATUS"
assert_not_contains 'consent without a terminal never prompts' "$OUTPUT" CONFIRM-ASKED
capture haseen-vapt-net-http-server /usr/share/doc/nmap 8080 --dry-run --yes
assert_contains 'server preview states interactive consent' "$OUTPUT" 'requires consent at an interactive terminal'
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
def request(path,headers={}):
    connection=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
    connection.request('GET',path,headers=headers);response=connection.getresponse();status=response.status;data=response.read();connection.close();return status,data
try:
    assert request('/scan-two.txt')==(200,b'Second owned usage.\n')
    # A DNS-rebinding page reaches the helper under its own name.
    status,data=request('/scan-two.txt',{'Host':'rebind.attacker.example:'+str(server.server_port)})
    assert status==421 and b'Second owned usage' not in data,(status,data)
    assert request('/scan-two.txt',{'Host':'localhost:'+str(server.server_port)})[0]==200
    assert request('/scan-two.txt',{'Host':'[::1]:'+str(server.server_port)})[0]==421
    with socket.create_connection(('127.0.0.1',server.server_port),timeout=3) as twice:
        twice.sendall(b'GET /scan-two.txt HTTP/1.1\r\nHost: localhost\r\nHost: rebind.attacker.example\r\nConnection: close\r\n\r\n')
        assert twice.makefile('rb').readline().split()[1]==b'421'
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
from workflow_actions import accepted_hosts
addresses=[{'address':'192.0.2.5','family':'ipv4'},{'address':'fe80::1%enp5s0','family':'ipv6'}]
with patch('workflow_actions.local_addresses',return_value=addresses):
    assert accepted_hosts('0.0.0.0')=={'localhost','192.0.2.5'}
    assert accepted_hosts('::')=={'localhost','192.0.2.5','fe80::1'}
assert accepted_hosts('192.0.2.7')=={'localhost','192.0.2.7'} and accepted_hosts('fe80::1%lo')=={'localhost','fe80::1'}
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
    assert inspect_certificate_data(der,str(root))['state']=='refused'
    try:certificate_payload(path,fingerprint)
    except ValueError:pass
    else:raise AssertionError('payload admitted spoofed CA '+variant)
    try:mutate('trust',fingerprint,der,root=str(root))
    except ValueError:pass
    else:raise AssertionError('privileged validation admitted spoofed CA '+variant)
    assert not (root/'var/lib/haseen/vapt/proxy-ca.json').exists() and not (root/'etc/ca-certificates').exists(),'rejected trust wrote state'
print('inspection, payload and privileged classifier agree')
PY
assert_status 'all CA admission paths reject adversarial extension fixtures' 0 "$STATUS"
assert_eq 'rejected trust never ran the updater' '' "$(vapt_calls owned-update-ca-trust)"
assert_contains 'inspection parses with the sysroot openssl' "$(vapt_calls owned-openssl)" 'x509 -inform PEM -noout'
rm -f "$CALLS/owned-openssl"
# These commands are often started from a cloned exploit or loot directory;
# a json.py planted there must not run, not even during a preview.
loot="$SANDBOX/loot"
mkdir -p "$loot"
printf 'import os\nopen(os.environ["VAPT_CALLS"] + "/planted-json", "a").write("imported\\n")\n' >"$loot/json.py"
pushd "$loot" >/dev/null || exit 1
capture haseen-vapt-service-start ssh --dry-run
assert_status 'service preview from a directory holding json.py' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca trust /certificates/ca.pem --dry-run
assert_status 'trust preview from a directory holding json.py' 0 "$STATUS"
actions_api endpoint listener 8080
assert_status 'listener from a directory holding json.py' 0 "$STATUS"
popd >/dev/null || exit 1
assert_eq 'planted json.py never imported' '' "$(vapt_calls planted-json)"
rm -rf "$loot" "$CALLS/action-user" "$CALLS/owned-nc" "$CALLS/owned-openssl"
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
# The root helper's transaction runs against the fixture root, where the trust
# updater is the fixture's recording stub (VAPT_CA_UPDATER_FAIL makes it fail).
capture python3 -B - "$VAPT_LAYER" "$ROOT" "$CALLS" <<'PY'
import hashlib,os,pathlib,shutil,ssl,sys
sys.path.insert(0,sys.argv[1]);from workflow_ca import mutate,ca_status,ANCHORS
root=pathlib.Path(sys.argv[2]);log=pathlib.Path(sys.argv[3])/'owned-update-ca-trust'
der=ssl.PEM_cert_to_DER_cert((root/'certificates/ca.pem').read_text());fingerprint=hashlib.sha256(der).hexdigest().upper()
def updates():return len(log.read_text().splitlines()) if log.exists() else 0
mutate('trust',fingerprint,der,root=str(root))
assert ca_status(str(root))['state']=='owned' and updates()==1
anchor=root/(ANCHORS.lstrip('/')+'/haseen-vapt-'+fingerprint+'.crt');original=anchor.read_bytes();anchor.write_bytes(b'owner modification')
assert ca_status(str(root))['state']=='modified'
try:mutate('remove',fingerprint,root=str(root))
except ValueError:pass
else:raise AssertionError('modified anchor removed')
assert anchor.read_bytes()==b'owner modification' and updates()==1;anchor.write_bytes(original)
mutate('remove',fingerprint,root=str(root))
assert ca_status(str(root))['state']=='none' and updates()==2
failure=root/'updater-failure';(failure/'usr/bin').mkdir(parents=True)
for program in ('openssl','update-ca-trust'):shutil.copy2(root/'usr/bin'/program,failure/'usr/bin'/program)
os.environ['VAPT_CA_UPDATER_FAIL']='true'
try:mutate('trust',fingerprint,der,root=str(failure))
except ValueError as error:assert 'no complete success' in str(error)
else:raise AssertionError('updater failure called success')
status=ca_status(str(failure))
assert status['state']=='unknown' and updates()==3,status
assert status['reason']=='trust transaction pending; owned anchor unchanged; system trust update incomplete',status
assert status['anchor']['transaction']=='pending' and status['anchor']['unchanged'],status
del os.environ['VAPT_CA_UPDATER_FAIL']
mutate('trust',fingerprint,der,root=str(failure))
assert ca_status(str(failure))['anchor']['transaction']=='created'
os.environ['VAPT_CA_UPDATER_FAIL']='true'
try:mutate('remove',fingerprint,root=str(failure))
except ValueError as error:assert 'no complete success' in str(error)
else:raise AssertionError('remove updater failure called success')
status=ca_status(str(failure))
assert status['state']=='unknown',status
assert status['reason']=='removal transaction incomplete; anchor absent; system trust may still contain CA',status
assert status['anchor']['transaction']=='removing' and not status['anchor']['unchanged'],status
print('owned trust/removal and modified-anchor preservation passed')
PY
assert_status 'fingerprint ownership transaction fixture' 0 "$STATUS"
rm -f "$CALLS/owned-update-ca-trust" "$CALLS/owned-openssl"

# The public orchestration crosses only the fixture gateway; its updater is
# the fixture stub. Failure/retry behavior is exercised end to end.
VAPT_CA_MUTATE=true VAPT_CA_UPDATER_FAIL=true VAPT_YES=true VAPT_TYPED="$fingerprint" actions_api ca trust /certificates/ca.pem
assert_status 'CLI failed trust reports failure' 1 "$STATUS"
assert_contains 'CLI failed trust says no success' "$OUTPUT" 'no complete success'
assert_eq 'CLI trust ran the sysroot updater once' 1 "$(vapt_calls owned-update-ca-trust | wc -l)"
capture haseen-vapt-net-proxy-ca status --json
assert_status 'pending transaction status remains nonzero' 1 "$STATUS"
assert_eq 'CLI failed trust exact state' unknown "$(jq -r '.state' <<<"$OUTPUT")"
assert_eq 'CLI failed trust exact reason' 'trust transaction pending; owned anchor unchanged; system trust update incomplete' "$(jq -r '.reason' <<<"$OUTPUT")"
assert_eq 'CLI failed trust exact transaction' pending "$(jq -r '.anchor.transaction' <<<"$OUTPUT")"
capture haseen-vapt-doctor --json
assert_eq 'doctor makes owned pending recovery available' true "$(jq '.workflow.capabilities[] | select(.id=="proxy-ca") | .available' <<<"$OUTPUT")"
VAPT_CA_MUTATE=true VAPT_YES=true actions_api ca trust /certificates/ca.pem
assert_status 'pending retry still requires typed fingerprint with --yes' 1 "$STATUS"
VAPT_CA_MUTATE=true VAPT_YES=true VAPT_TYPED="$fingerprint" actions_api ca trust /certificates/ca.pem
assert_status 'CLI pending trust retry completes through fixture gateway' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'successful retry reports owned' owned "$(jq -r '.state' <<<"$OUTPUT")"
assert_eq 'successful retry transaction created' created "$(jq -r '.anchor.transaction' <<<"$OUTPUT")"
VAPT_CA_MUTATE=true VAPT_CA_UPDATER_FAIL=true VAPT_CONFIRM=yes actions_api ca remove "$fingerprint"
assert_status 'CLI failed removal reports failure' 1 "$STATUS"
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'CLI failed removal exact state' unknown "$(jq -r '.state' <<<"$OUTPUT")"
assert_eq 'CLI failed removal exact reason' 'removal transaction incomplete; anchor absent; system trust may still contain CA' "$(jq -r '.reason' <<<"$OUTPUT")"
assert_eq 'CLI failed removal exact transaction' removing "$(jq -r '.anchor.transaction' <<<"$OUTPUT")"
capture haseen-vapt-net-proxy-ca trust /certificates/ca.pem --dry-run
assert_status 'removing transaction permits only removal retry' 1 "$STATUS"
VAPT_CA_MUTATE=true VAPT_CONFIRM=yes actions_api ca remove "$fingerprint"
assert_status 'CLI removal retry completes through fixture gateway' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'successful removal retry reports none' none "$(jq -r '.state' <<<"$OUTPUT")"
VAPT_CA_MUTATE=true VAPT_CA_UPDATER_FAIL=true VAPT_YES=true VAPT_TYPED="$fingerprint" actions_api ca trust /certificates/ca.pem
VAPT_CA_MUTATE=true VAPT_CONFIRM=yes actions_api ca remove "$fingerprint"
assert_status 'CLI removes unchanged pending anchor without trusting it' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'pending removal completes to none' none "$(jq -r '.state' <<<"$OUTPUT")"
VAPT_CA_MUTATE=true VAPT_CA_UPDATER_FAIL=true VAPT_YES=true VAPT_TYPED="$fingerprint" actions_api ca trust /certificates/ca.pem
VAPT_CA_MUTATE=true VAPT_CA_CHANGE_BEFORE_ROOT=true VAPT_CONFIRM=yes actions_api ca remove "$fingerprint"
assert_status 'root lock recheck refuses changed pending anchor' 1 "$STATUS"
assert_contains 'root lock keeps changed anchor' "$OUTPUT" 'modified or missing owned anchor preserved'
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'changed pending anchor remains modified' modified "$(jq -r '.state' <<<"$OUTPUT")"
for operation in trust remove; do
    operand=/certificates/ca.pem
    [[ $operation == trust ]] || operand=$fingerprint
    capture haseen-vapt-net-proxy-ca "$operation" "$operand" --dry-run
    assert_status "modified pending $operation refused" 1 "$STATUS"
done
# Remove only the fixture transaction created by this scenario.
rm "$ROOT/etc/ca-certificates/trust-source/anchors/haseen-vapt-$fingerprint.crt" "$ROOT/var/lib/haseen/vapt/proxy-ca.json"
rm -f "$CALLS/owned-update-ca-trust" "$CALLS/owned-openssl"
for cmd in service-list service-start service-stop service-restart net-addresses net-listener net-http-server net-file-server net-proxy-ca net-remmina; do
    capture "haseen-vapt-$cmd" --help
    assert_status "$cmd help" 0 "$STATUS"
done
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
# Interrupt a real trust under the root lock before the anchor exists, part-way
# through writing it (ENOSPC), and after it is complete. Each state must be
# completed by trust and rolled back by remove; bytes that are not haseen's
# own partial write survive both.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import errno,hashlib,json,os,pathlib,shutil,ssl,sys
from unittest.mock import patch
sys.path.insert(0,sys.argv[1]);import workflow_ca as ca
base=pathlib.Path(sys.argv[2]);der=ssl.PEM_cert_to_DER_cert((base/'certificates/ca.pem').read_text())
fp=hashlib.sha256(der).hexdigest().upper();pem=ssl.DER_cert_to_PEM_cert(der).encode()
real_open,real_write,real_run=os.open,os.write,ca.subprocess.run
def no_space_for_anchor(path,flags,*args,**kwargs):
    if path==ca.anchor_name(fp) and flags&os.O_CREAT:raise OSError(errno.ENOSPC,'fixture: no space')
    return real_open(path,flags,*args,**kwargs)
def half_written(fd,data):
    if bytes(data[:27])==b'-----BEGIN CERTIFICATE-----':
        real_write(fd,data[:len(data)//2]);raise OSError(errno.ENOSPC,'fixture: no space')
    return real_write(fd,data)
def killed_before_updater(argv,*args,**kwargs):
    if argv[0].endswith('/usr/bin/update-ca-trust'):raise SystemExit('fixture: killed')
    return real_run(argv,*args,**kwargs)
faults={'before-anchor':(ca.os,'open',no_space_for_anchor),'partial-anchor':(ca.os,'write',half_written),
        'after-anchor':(ca.subprocess,'run',killed_before_updater)}
def interrupted(label,branch):
    root=base/('crash-'+label+'-'+branch);(root/'usr/bin').mkdir(parents=True)
    for program in ('openssl','update-ca-trust'):shutil.copy2(base/'usr/bin'/program,root/'usr/bin'/program)
    with patch.object(*faults[label]):
        try:ca.mutate('trust',fp,der,root=str(root))
        except BaseException:pass
        else:raise AssertionError(label+': fault did not interrupt the trust')
    return root,root/ca.ANCHORS.lstrip('/')/ca.anchor_name(fp)
def pending(root,unchanged):
    status=ca.ca_status(str(root));anchor=status['anchor']
    assert status['state']=='unknown' and anchor['transaction']=='pending' and anchor['unchanged'] is unchanged,status
    assert status['reason']=='trust transaction pending; owned anchor '+('unchanged' if unchanged else 'missing or incomplete')+'; system trust update incomplete',status
    assert ca.trust_allowed(status,fp) and ca.remove_allowed(status,fp),status
for label in faults:
    root,anchor=interrupted(label,'trust')
    expected={'before-anchor':None,'partial-anchor':pem[:len(pem)//2],'after-anchor':pem}[label]
    assert (anchor.read_bytes() if anchor.exists() else None)==expected,label
    pending(root,label=='after-anchor')
    ca.mutate('trust',fp,der,root=str(root))
    status=ca.ca_status(str(root))
    assert status['state']=='owned' and status['anchor']['transaction']=='created' and anchor.read_bytes()==pem,(label,status)
    root,anchor=interrupted(label,'remove')
    ca.mutate('remove',fp,root=str(root))
    assert ca.ca_status(str(root))['state']=='none' and not anchor.exists(),label
    assert not (root/ca.STATE.lstrip('/')/ca.RECORD).exists(),label
# A crash can leave zero fill after the bytes already written.
root,anchor=interrupted('before-anchor','zero-fill');anchor.write_bytes(pem[:100]+b'\0'*60)
pending(root,False)
ca.mutate('remove',fp,root=str(root))
assert ca.ca_status(str(root))['state']=='none' and not anchor.exists()
# Bytes haseen never wrote are preserved and refused by both actions.
root,anchor=interrupted('before-anchor','foreign');anchor.write_bytes(b'administrator bytes\n')
assert ca.ca_status(str(root))['state']=='modified'
for action,payload in (('trust',der),('remove',None)):
    try:ca.mutate(action,fp,payload,root=str(root))
    except ValueError as error:assert 'preserved' in str(error),error
    else:raise AssertionError('foreign anchor bytes accepted by '+action)
assert anchor.read_bytes()==b'administrator bytes\n'
# A journal written before the certificate was recorded cannot prove a partial
# anchor is haseen's: removal refuses, a trust retry with the certificate completes.
root,anchor=interrupted('partial-anchor','unrecorded')
record=root/ca.STATE.lstrip('/')/ca.RECORD;row=json.loads(record.read_text());del row['pem'];record.write_text(json.dumps(row))
assert ca.ca_status(str(root))['state']=='modified'
try:ca.mutate('remove',fp,root=str(root))
except ValueError:pass
else:raise AssertionError('unverifiable partial anchor removed')
ca.mutate('trust',fp,der,root=str(root))
assert ca.ca_status(str(root))['state']=='owned' and anchor.read_bytes()==pem
print('interrupted trust recovered at every step')
PY
assert_status 'interrupted trust is completable and reversible' 0 "$STATUS"
# The CLI sees the same recoverable state: a trust interrupted before its anchor.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import errno,hashlib,os,pathlib,ssl,sys
from unittest.mock import patch
sys.path.insert(0,sys.argv[1]);import workflow_ca as ca
root=pathlib.Path(sys.argv[2]);der=ssl.PEM_cert_to_DER_cert((root/'certificates/ca.pem').read_text());fp=hashlib.sha256(der).hexdigest().upper()
real_open=os.open
def no_space_for_anchor(path,flags,*args,**kwargs):
    if path==ca.anchor_name(fp) and flags&os.O_CREAT:raise OSError(errno.ENOSPC,'fixture: no space')
    return real_open(path,flags,*args,**kwargs)
with patch.object(ca.os,'open',no_space_for_anchor):
    try:ca.mutate('trust',fp,der,root=str(root))
    except OSError:print('interrupted before the anchor')
PY
assert_contains 'trust interrupted before its anchor' "$OUTPUT" 'interrupted before the anchor'
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'interrupted trust reports a recoverable pending transaction' 'unknown pending false' "$(jq -r '"\(.state) \(.anchor.transaction) \(.anchor.unchanged)"' <<<"$OUTPUT")"
capture haseen-vapt-net-proxy-ca trust /certificates/ca.pem --dry-run
assert_status 'interrupted trust may be retried' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca remove "$fingerprint" --dry-run
assert_status 'interrupted trust may be removed' 0 "$STATUS"
capture haseen-vapt-doctor --json
assert_eq 'doctor offers recovery of an interrupted trust' true "$(jq '.workflow.capabilities[] | select(.id=="proxy-ca") | .available' <<<"$OUTPUT")"
VAPT_CA_MUTATE=true VAPT_CONFIRM=yes actions_api ca remove "$fingerprint"
assert_status 'CLI rolls back an interrupted trust' 0 "$STATUS"
capture haseen-vapt-net-proxy-ca status --json
assert_eq 'rolled-back trust leaves no owned state' none "$(jq -r '.state' <<<"$OUTPUT")"
rm -f "$CALLS/owned-update-ca-trust" "$CALLS/owned-openssl"
# The handed-over adapter sits in the sysroot, as production resolves it.
capture python3 -B - "$FIXTURES" "$CALLS" "$ROOT" <<'PY'
import json,os,pathlib,signal,socket,subprocess,sys,time
fixtures=pathlib.Path(sys.argv[1]);calls=pathlib.Path(sys.argv[2]);adapter=pathlib.Path(sys.argv[3])/'usr/bin/foreground-adapter'
adapter.write_text('#!/usr/bin/python3\nimport json,os,socket,time\ns=socket.socket();s.bind(("127.0.0.1",0));s.listen(1)\nwith open(os.environ["VAPT_FOREGROUND_READY"],"w") as f:json.dump({"pid":os.getpid(),"port":s.getsockname()[1]},f)\nwhile True:time.sleep(1)\n')
adapter.chmod(0o755)
for kind,args in [('listener',['8080']),('http-server',['/explicit-fixture','8080'])]:
    for stop in (signal.SIGTERM,signal.SIGHUP):
        ready=calls/('ready-'+kind+'-'+str(stop));env=dict(os.environ,VAPT_ENDPOINT_ADAPTER='/usr/bin/foreground-adapter',VAPT_FOREGROUND_READY=str(ready),VAPT_CONFIRM='yes')
        process=subprocess.Popen(['/usr/bin/bash',str(fixtures/'vapt-actions-runner.sh'),'endpoint',kind,*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            deadline=time.monotonic()+15
            while not ready.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            assert ready.exists(),'adapter readiness deadline exceeded'
            data=json.loads(ready.read_text());assert data['pid']==process.pid,'wrapper did not hand off its pid'
            process.send_signal(stop);assert process.wait(timeout=2)==-stop,'signal/exit code not propagated'
            with socket.socket() as probe:probe.bind(('127.0.0.1',data['port']))
        except BaseException:
            if process.poll() is None:process.kill()
            output,diagnostic=process.communicate(timeout=5)
            print('signal handoff failure:',kind,stop,'exit',process.returncode,'stdout:',output.decode(errors='replace'),'stderr:',diagnostic.decode(errors='replace'),file=sys.stderr)
            raise
        finally:
            if process.poll() is None:process.kill();process.wait(timeout=2)
adapter.unlink()
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
