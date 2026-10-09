# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-actions-lib.sh"
actions_fixture vapt-confinement-adversarial
# Execute the production HTTP request parser against in-memory transports.
# No sockets, DNS, subprocess parsers, installed programs or host trust changes.
capture python3 -B - "$VAPT_LAYER" "$ROOT" <<'PY'
import base64,contextlib,ctypes,hashlib,io,json,os,pathlib,ssl,subprocess,sys,types
from unittest.mock import patch
sys.path.insert(0,sys.argv[1])
import workflow_actions as actions,workflow_support as support,workflow_ca as ca
root=pathlib.Path(sys.argv[2]); failures=[]
def check(label,fn):
    try: fn()
    except Exception as e: failures.append(label); print('CASE-FAIL '+label+': '+repr(e))
    else: print('CASE-PASS '+label)
def eq(actual,expected):
    assert actual==expected, 'expected '+repr(expected)+' got '+repr(actual)
class Transport:
    def __init__(self,request): self.input=io.BytesIO(request);self.output=io.BytesIO()
    def recv_into(self,buffer): return self.input.readinto(buffer)
    def settimeout(self,value): self.timeout=value
    def sendall(self,data): self.output.write(data)
def request(path,rootfd=None,filefd=None,method='GET'):
    sock=Transport((method+' '+path+' HTTP/1.0\r\nHost: localhost\r\n\r\n').encode())
    actions.ConfinedHandler(sock,('127.0.0.1',1),types.SimpleNamespace(server_name='fixture',server_port=8080,request_idle_seconds=5.0,request_total_seconds=30.0),root_fd=rootfd,file_fd=filefd)
    raw=sock.output.getvalue();header,body=raw.split(b'\r\n\r\n',1);return int(header.split()[1]),body,header
selected=root/'selected'; selected.mkdir();(selected/'inside').write_bytes(b'SELECTED\n');(selected/'sub').mkdir();(selected/'sub/leaf').write_bytes(b'INNER\n')
secret=root/'outside-secret';secret.write_bytes(b'OUTSIDE-SECRET\n');(selected/'sym').symlink_to(secret);os.link(secret,selected/'hard')
os.mkfifo(selected/'fifo')
fd=actions.open_selected(selected,directory=True)
try:
    check('directory endpoint returns selected bytes',lambda:eq(request('/inside',fd)[:2],(200,b'SELECTED\n')))
    for path in ['/', '/sub', '/sub/', '/sym', '/hard', '/fifo', '/../outside-secret', '/%2e%2e/outside-secret', '/sub/%2e%2e/inside', '/%00', '/sub//leaf', '/sub/./leaf']:
        check('directory refusal '+path,lambda p=path:eq(request(p,fd)[0],404))
    check('HEAD emits no selected bytes',lambda:eq(request('/inside',fd,method='HEAD')[:2],(200,b'')))
    check('POST cannot mutate or expose',lambda:eq(request('/inside',fd,method='POST')[0],501))
    os.link(selected/'inside',root/'late-link')
    check('late hardlink refuses directory bytes',lambda:eq(request('/inside',fd)[0],404));(root/'late-link').unlink()
    check('unlink restores exclusive directory bytes',lambda:eq(request('/inside',fd)[:2],(200,b'SELECTED\n')))
    # Swap a traversed parent before opening its child, deterministically.
    saved_open=os.open;swapped=[False]
    def raced_open(path,*args,**kwargs):
        if path=='leaf' and not swapped[0]:
            swapped[0]=True;(selected/'sub').rename(selected/'retained-sub');(selected/'sub').symlink_to(root)
        return saved_open(path,*args,**kwargs)
    with patch.object(actions.os,'open',raced_open):
        check('parent replaced by symlink mid-request cannot redirect descriptor',lambda:eq(request('/sub/leaf',fd)[:2],(200,b'INNER\n')))
    check('subsequent request refuses replaced parent symlink',lambda:eq(request('/sub/outside-secret',fd)[0],404))
    selected.rename(root/'held-selected');selected.symlink_to(root)
    check('selected root name replaced retains original descriptor',lambda:eq(request('/inside',fd)[:2],(200,b'SELECTED\n')))
    check('selected root replacement cannot expose replacement secret',lambda:eq(request('/outside-secret',fd)[0],404))
finally: os.close(fd)
file=root/'single';file.write_bytes(b'ONE-OWNED-FILE\n');fd=actions.open_selected(file)
try:
    check('fixed single-file endpoint returns only one file',lambda:eq(request('/file',filefd=fd)[:2],(200,b'ONE-OWNED-FILE\n')))
    for path in ['/', '/single', '/file/', '/../single', '/%2e%2e/file', '/outside-secret']:
        check('single-file refuses '+path,lambda p=path:eq(request(p,filefd=fd)[0],404))
    os.link(file,root/'single-extra')
    check('late hardlink refuses held single-file bytes',lambda:eq(request('/file',filefd=fd)[0],404));(root/'single-extra').unlink()
    file.rename(root/'single-held');file.symlink_to(secret)
    check('single-file path replacement cannot change held bytes',lambda:eq(request('/file',filefd=fd)[:2],(200,b'ONE-OWNED-FILE\n')))
finally:os.close(fd)
# Build genuinely signed X509 certificates via the native library, never the
# openssl executable. Only its textual metadata subprocess is replaced below;
# admission still executes the production native X509_check_ca classifier.
lib=ctypes.CDLL('/usr/lib/libcrypto.so.3')
def bind(name,restype,args):
    fn=getattr(lib,name);fn.restype=restype;fn.argtypes=args;return fn
P=ctypes.c_void_p;I=ctypes.c_int;S=ctypes.c_char_p
ctx_new=bind('EVP_PKEY_CTX_new_id',P,[I,P]);ctx=ctx_new(6,None)
bind('EVP_PKEY_keygen_init',I,[P])(ctx);bind('EVP_PKEY_CTX_set_rsa_keygen_bits',I,[P,I])(ctx,2048)
key=P();assert bind('EVP_PKEY_keygen',I,[P,ctypes.POINTER(P)])(ctx,ctypes.byref(key))>0
bind('EVP_PKEY_CTX_free',None,[P])(ctx)
new=bind('X509_new',P,[]);free=bind('X509_free',None,[P]);set_version=bind('X509_set_version',I,[P,ctypes.c_long]);serial=bind('X509_get_serialNumber',P,[P]);asnint=bind('ASN1_INTEGER_set',I,[P,ctypes.c_long]);pubkey=bind('X509_set_pubkey',I,[P,P]);get_name=bind('X509_get_subject_name',P,[P]);name_add=bind('X509_NAME_add_entry_by_txt',I,[P,S,I,S,I,I,I]);issuer=bind('X509_set_issuer_name',I,[P,P]);get_before=bind('X509_getm_notBefore',P,[P]);get_after=bind('X509_getm_notAfter',P,[P]);set_time=bind('ASN1_TIME_set_string',I,[P,S]);oct_new=bind('ASN1_OCTET_STRING_new',P,[]);oct_set=bind('ASN1_OCTET_STRING_set',I,[P,S,I]);oct_free=bind('ASN1_OCTET_STRING_free',None,[P]);ext_new=bind('X509_EXTENSION_create_by_NID',P,[P,I,I,P]);ext_add=bind('X509_add_ext',I,[P,P,I]);ext_free=bind('X509_EXTENSION_free',None,[P]);sha256=bind('EVP_sha256',P,[]);sign=bind('X509_sign',I,[P,P,P]);encode=bind('i2d_X509',I,[P,ctypes.POINTER(P)])
def certificate(extension,critical=1):
    x=new()
    try:
        assert set_version(x,2)==1;asnint(serial(x),1);pubkey(x,key)
        n=get_name(x);assert name_add(n,b'CN',0x1001,b'CA:TRUE',-1,-1,0)==1;issuer(x,n)
        set_time(get_before(x),b'20200101000000Z');set_time(get_after(x),b'20400101000000Z')
        if extension is not None:
            octet=oct_new();oct_set(octet,extension,len(extension));e=ext_new(None,87,critical,octet);assert e;ext_add(x,e,-1);ext_free(e);oct_free(octet)
        assert sign(x,key,sha256())>0
        size=encode(x,None);buffer=ctypes.create_string_buffer(size);cursor=P(ctypes.addressof(buffer));assert encode(x,ctypes.byref(cursor))==size
        return buffer.raw
    finally:free(x)
certificates={name:certificate(ext,critical) for name,ext,critical in [('real-ca',b'\x30\x03\x01\x01\xff',1),('noncritical-ca',b'\x30\x03\x01\x01\xff',0),('no-extension',None,0),('false-ca',b'\x30\x03\x01\x01\x00',1),('malformed',b'CA:TRUE',0),('malformed-critical',b'CA:TRUE',1)]}
bind('EVP_PKEY_free',None,[P])(key)
(root/'certificates').mkdir();(root/'certificates/ca.der').write_bytes(certificates['real-ca'])
def parser(argv,input,**kwargs):
    assert argv[0]=='/usr/bin/openssl' and argv[1]=='x509',argv
    der=ssl.PEM_cert_to_DER_cert(input.decode()) if b'BEGIN CERTIFICATE' in input else input
    text='subject=CN=CA:TRUE\nissuer=CN=CA:TRUE\nnotBefore=Jan  1 00:00:00 2020 GMT\nnotAfter=Jan  1 00:00:00 2040 GMT\nsha256 Fingerprint='+hashlib.sha256(der).hexdigest().upper()+'\n'
    return types.SimpleNamespace(returncode=0,stdout=text.encode(),stderr=b'')
with patch.object(support.subprocess,'run',parser):
    for name,der in certificates.items():
        expected='valid' if name.endswith('ca') and name not in ('false-ca',) else 'refused'
        check('native signed certificate classification '+name,lambda d=der,e=expected:eq(support.inspect_certificate_data(d)['state'],e))
        if expected=='refused':
            target=root/('refused-'+name);fp=hashlib.sha256(der).hexdigest().upper()
            def rejected(d=der,t=target,f=fp):
                try:ca.mutate('trust',f,d,root=str(t),updater=lambda:(_ for _ in ()).throw(AssertionError('updater must not run')))
                except ValueError:pass
                else:raise AssertionError('non-CA trust admitted')
                assert not t.exists(),'refused classification wrote files'
            check('privileged admission refuses '+name,rejected)
    der=certificates['real-ca'];fp=hashlib.sha256(der).hexdigest().upper()
    check('bundle rejected before trust',lambda:eq(support.inspect_certificate_data((ssl.DER_cert_to_PEM_cert(der)*2).encode())['state'],'invalid'))
    check('private key rejected before parser',lambda:eq(support.inspect_certificate_data(b'-----BEGIN ' b'PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----')['state'],'refused'))
    def expired_parser(argv,input,**kwargs):
        r=parser(argv,input,**kwargs);r.stdout=r.stdout.replace(b'2040 GMT',b'2021 GMT');return r
    with patch.object(support.subprocess,'run',expired_parser):
        check('expired genuine CA refused',lambda:eq(support.inspect_certificate_data(der)['state'],'refused'))
    def updater_failure():raise subprocess.CalledProcessError(7,['inert-updater'])
    target=root/'failed-updater'
    def failed_trust():
        try:ca.mutate('trust',fp,der,root=str(target),updater=updater_failure)
        except ValueError as e:assert 'no complete success' in str(e)
        else:raise AssertionError('updater failure returned success')
        eq(ca.ca_status(str(target))['state'],'unknown')
    check('failed trust updater cannot claim owned-complete state',failed_trust)
    check('successful updater recovers pending transaction',lambda:ca.mutate('trust',fp,der,root=str(target),updater=lambda:None))
    check('completed trust observable ownership',lambda:eq(ca.ca_status(str(target))['state'],'owned'))
    def failed_remove():
        try:ca.mutate('remove',fp,root=str(target),updater=updater_failure)
        except ValueError as e:assert 'no complete success' in str(e)
        else:raise AssertionError('remove updater failure returned success')
        assert ca.ca_status(str(target))['state']!='none','failed updater falsely reported trust removed'
    check('failed removal updater cannot claim absent trust',failed_remove)
    check('removal retry resolves retained transaction',lambda:ca.mutate('remove',fp,root=str(target),updater=lambda:None))
    check('completed removal observable none',lambda:eq(ca.ca_status(str(target))['state'],'none'))
    # Invoke the real command handler, asserting separated JSON/stdout and exit.
    for file,expected in [('ca.der',0),('missing.der',1)]:
        stdout=io.StringIO();stderr=io.StringIO()
        with patch.object(sys,'argv',['workflow_actions.py','inspect','/certificates/'+file,'--json','--dry-run']),contextlib.redirect_stdout(stdout),contextlib.redirect_stderr(stderr):rc=actions.main()
        check('inspection JSON exit '+file,lambda r=rc,e=expected:eq(r,e))
        check('inspection one versioned object '+file,lambda s=stdout.getvalue():eq(json.loads(s)['schemaVersion'],1))
    # Retain an owned fixture anchor to exercise the successful remove preview.
    ca.mutate('trust',fp,der,root=str(root),updater=lambda:None)
    (root/'certificates/fingerprint').write_text(fp)
print('CASE-TOTAL '+str(len(failures))+' failures')
PY
assert_status 'socketless serving and native certificate runner completes' 0 "$STATUS"
while IFS= read -r line; do
    case "$line" in CASE-PASS*) _pass ;; CASE-FAIL*) _fail "${line#CASE-FAIL }" ;; esac
done <<<"$OUTPUT"
assert_contains 'socketless and native certificate cases ran' "$OUTPUT" 'CASE-TOTAL'
# --yes is not authority for the actual typed gate (read from inert stdin).
for typed in '' yes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; do
    capture bash -c 'set -Eeuo pipefail; source "$HASEEN_PATH/lib/common.sh"; ASSUME_YES=true; confirm_typed "Test trust gate" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' <<<"$typed"
    expected=1; [[ $typed != AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ]] || expected=0
    assert_status "typed gate under --yes requires exact full fingerprint: $typed" "$expected" "$STATUS"
done
# Full production trust orchestration with only certificate-parser responses and
# root/terminal gateways substituted. The genuine classifier is exercised above;
# here a --yes launch must still read and compare the typed fingerprint.
trust_gate_script='
set -Eeuo pipefail
source "$HASEEN_PATH/lib/common.sh"
source "$HASEEN_PATH/layers/vapt/workflow_actions.sh"
[[ $HASEEN_SYSROOT == "$VAPT_SANDBOX"/* ]] || exit 97
ASSUME_YES=true
DRY_RUN=${2:-false}
CA_FLAGS=()
export HASEEN_TERMINAL_SH=1
vapt_action_refuse_fixture() { :; }
in_floating_terminal() { echo TERMINAL-REQUESTED; }
vapt_root_exec() { cat >/dev/null; echo ROOT-TRUST-REQUESTED; }
vapt_actions() {
    case "$1" in
    inspect) echo "{\"schemaVersion\":1,\"state\":\"valid\",\"certificate\":{\"sha256\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}}" ;;
    adapter|ca-trust-check) return 0 ;;
    ca-payload) echo INERT-ENCODED-PAYLOAD ;;
    *) exit 97 ;;
    esac
}
vapt_ca_action trust /certificates/ca.der <<< "$1"
'
for typed in '' yes AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; do
    capture bash -c "$trust_gate_script" bash "$typed"
    if [[ $typed == AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ]]; then
        assert_status 'trust orchestration with exact typed fingerprint' 0 "$STATUS"
        assert_contains 'accepted typed trust reaches inert privileged gateway' "$OUTPUT" ROOT-TRUST-REQUESTED
    else
        assert_status '--yes trust orchestration still refuses untyped/wrong fingerprint' 1 "$STATUS"
        assert_not_contains 'untyped trust never reaches privileged gateway' "$OUTPUT" ROOT-TRUST-REQUESTED
    fi
done
before="$(net_manifest)"
capture bash -c "$trust_gate_script" bash '' true
assert_status 'valid CA trust preview requires no typed input' 0 "$STATUS"
assert_contains 'valid CA trust preview states typed requirement' "$OUTPUT" 'require typed SHA-256'
assert_not_contains 'valid CA trust preview never requests terminal' "$OUTPUT" TERMINAL-REQUESTED
assert_not_contains 'valid CA trust preview never requests privilege' "$OUTPUT" ROOT-TRUST-REQUESTED
assert_eq 'valid CA trust preview preserves all sysroot bytes' "$before" "$(net_manifest)"
before="$(net_manifest)"
capture haseen-vapt-net-proxy-ca remove "$(<"$ROOT/certificates/fingerprint")" --yes --dry-run
assert_status 'unchanged owned CA removal preview' 0 "$STATUS"
assert_contains 'owned CA removal previews only this anchor' "$OUTPUT" 'remove only this anchor'
assert_dry_pure 'owned CA removal preview' "$OUTPUT"
assert_eq 'owned CA removal preview preserves all sysroot bytes' "$before" "$(net_manifest)"
actions_untouched adversarial-confinement
