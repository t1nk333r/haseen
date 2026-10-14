# shellcheck shell=bash
source "$FIXTURES/vapt-workflow-lib.sh"
actions_fixture() {
    workflow_fixture "$1"
    python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); base=root/'var/lib/haseen/vapt'
repos=json.loads((base/'repositories.json').read_text()); records=json.loads((base/'installed.json').read_text())
rows=[('openssh','https://www.openssh.com/',['usr/lib/systemd/system/sshd.service','usr/lib/systemd/system/sshd@.service','usr/lib/systemd/system/sshdgenkeys.service']),
      ('postgresql','https://www.postgresql.org/',['usr/lib/systemd/system/postgresql.service']),
      ('apache','https://httpd.apache.org/',['usr/lib/systemd/system/httpd.service']),
      ('nginx','https://nginx.org/',['usr/lib/systemd/system/nginx.service']),
      ('openbsd-netcat','https://www.openbsd.org/',['usr/bin/nc']),
      ('python','https://www.python.org/',['usr/bin/python','usr/bin/python3.14','usr/include/python3.14/Python.h']),
      ('openssl','https://www.openssl.org/',['usr/bin/openssl']),
      ('ca-certificates-utils','https://gitlab.archlinux.org/',['usr/bin/update-ca-trust']),
      ('remmina','https://remmina.org/',['usr/bin/remmina'])]
services={}
for name,url,files in rows:
    record={'name':name,'version':'3.14.0-1' if name=='python' else '1-1','url':url,'files':files}
    records=[r for r in records if r['name']!=name]+[record]
    repos['extra']=[r for r in repos.get('extra',[]) if r['name']!=name]+[record]
    for file in files:
        path=root/file; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text('inert file\n')
        if file.endswith('.service'):
            path.write_text('[Unit]\nDescription=Owned fixture\n[Service]\nExecStart=/never-execute\n')
            services[path.name]={'FragmentPath':'/'+file,'ActiveState':'inactive','SubState':'dead','LoadState':'loaded'}
(base/'repositories.json').write_text(json.dumps(repos)); (base/'installed.json').write_text(json.dumps(records))
(base/'services.json').write_text(json.dumps(services))
(base/'addresses.json').write_text(json.dumps([{'interface':'lo','address':'127.0.0.1','prefixLength':8}]))
PY
    # Production executes host programs at sysroot paths (vapt_program,
    # host_program), so these recording stand-ins are exactly what an action
    # would run: each logs its argv to $CALLS/owned-NAME.
    local name
    for name in nc python python3.14 remmina systemctl update-ca-trust; do
        actions_stub "$ROOT/usr/bin/$name" "owned-$name"
    done
    printf '[ "${VAPT_CA_UPDATER_FAIL:-}" != true ] || exit 7\n' >>"$ROOT/usr/bin/update-ca-trust"
    workflow_openssl
    export HASEEN_INLINE=1
}
# actions_stub FILE NAME — log argv to $CALLS/NAME, announce it like every
# fixture stub, and succeed.
actions_stub() {
    cat >"$1" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/$2'
echo "STUB-CALLED: $2 \$*" >&2
EOF
    chmod +x "$1"
}
actions_api() {
    capture bash "$FIXTURES/vapt-actions-runner.sh" "$@"
}
# actions_untouched LABEL — no host program an action could run was executed.
# Tests that run one on purpose assert its log and then remove it.
actions_untouched() {
    local name
    for name in nc python python3.14 remmina systemctl update-ca-trust openssl; do
        assert_eq "$1: owned $name never executed" '' "$(vapt_calls "owned-$name")"
    done
    workflow_no_calls "$1"
}
net_manifest() {
    python3 -B - "$ROOT" <<'PY'
import hashlib,os,pathlib,sys
root=pathlib.Path(sys.argv[1]);digest=hashlib.sha256()
for path in sorted(root.rglob('*')):
    digest.update(str(path.relative_to(root)).encode())
    if path.is_symlink():digest.update(os.readlink(path).encode())
    elif path.is_file():digest.update(path.read_bytes())
print(digest.hexdigest())
PY
}
