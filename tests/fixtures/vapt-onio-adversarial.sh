# shellcheck shell=bash disable=SC2034  # read by tests/test-vapt-oniomarchy-*-adversarial.sh
# tests/fixtures/vapt-onio-adversarial.sh — shared builders for the adversarial
# private-source suites, sourced after tests/fixtures/vapt-lib.sh. Every
# fetch, key, package and tool command stays a vapt-lib logging stub; the
# custom signed database below is fixture protocol only (the gpg stub replays
# the status recorded for exactly those bytes). Nothing reaches a network,
# keyring, package manager or the live session.

ONIO_FX="$FIXTURES/vapt-oniomarchy"
PIN=0F5F9214F312B067ECBF1DF125E2C00AA6340BD0
ROT=B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0
ADV_CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
SOURCES=/var/lib/haseen/vapt/sources
HOST_STANZA=$'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch'

# adv_case NAME [extra repository rows...] — an x86_64 fixture host whose
# hermetic repository serves the signed private source (not yet approved).
adv_case() {
    vapt_sandbox "$1"
    shift
    vapt_root
    printf '%s\n' "$ADV_CONF" >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}" "$@"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve
}

# adv_approved NAME [rows...] — plus the approved, verified private state.
adv_approved() {
    adv_case "$@"
    vapt_onio_seed
}

# adv_publish JSON — republish the signed fixture database with exactly these
# records (and the served keyring), then seed the approved state from it.
# JSON: [{"name","version","arch","url",["depends"|"provides"|"conflicts"|
# "replaces"]...,["dir"]}]; dir overrides the desc directory (duplicates).
adv_publish() {
    FIXTURES="$FIXTURES" python3 - "$1" <<'EOF'
import hashlib, json, os, shutil, sys, tarfile
from pathlib import Path
sandbox = Path(os.environ['VAPT_SANDBOX'])
root = Path(os.environ['HASEEN_SYSROOT'])
if not root.resolve().is_relative_to(sandbox.resolve()):
    sys.exit('fixture sysroot must be inside the sandbox')
onio = sandbox / 'onio'
fx = Path(os.environ['FIXTURES']) / 'vapt-oniomarchy'
meta = json.loads((onio / 'serve.json').read_text())
records = [dict(name='oniomarchy-keyring', version=meta['version'], arch='any', url='https://pkgs.oniomarchy.com',
                filename=meta['keyring'], sha256sum=meta['sha256'])]
for r in json.loads(sys.argv[1]):
    filename = r['name'] + '-' + r['version'] + '-x86_64.pkg.tar.gz'
    archive = sandbox / 'archives' / filename
    digest = hashlib.sha256(archive.read_bytes() if archive.exists() else filename.encode()).hexdigest()
    records.append(dict(r, filename=filename, sha256sum=digest))
build = onio / 'build' / 'adversarial-db'
shutil.rmtree(build, ignore_errors=True)
build.mkdir(parents=True)
for r in records:
    lines = ['%FILENAME%', r['filename'], '', '%NAME%', r['name'], '', '%VERSION%', r['version'], '',
             '%ARCH%', r['arch'], '', '%URL%', r.get('url', ''), '', '%SHA256SUM%', r['sha256sum'], '']
    for key in ('depends', 'provides', 'conflicts', 'replaces'):
        if r.get(key):
            lines += ['%' + key.upper() + '%'] + r[key] + ['']
    entry = build / r.get('dir', r['name'] + '-' + r['version'])
    entry.mkdir(exist_ok=True)
    (entry / 'desc').write_text('\n'.join(lines) + '\n')
database = onio / 'serve' / 'oniomarchy.db'
with tarfile.open(database, 'w:gz') as out:
    for member in sorted(p.relative_to(build) for p in build.iterdir()):
        out.add(build / member, str(member))
digest = hashlib.sha256(database.read_bytes()).hexdigest()
Path(str(database) + '.sig').write_text('fixture-sig ' + digest + '\n')
(onio / 'status').mkdir(exist_ok=True)
(onio / 'status' / digest).write_text((fx / 'trust' / 'pinned.status').read_text())
path = root / 'var/lib/haseen/vapt/repositories.json'
repos = json.loads(path.read_text())
repos['oniomarchy'] = [{k: v for k, v in r.items() if k not in ('arch', 'dir')} for r in records]
path.write_text(json.dumps(repos))
EOF
    vapt_onio_seed
}

# adv_db_status TEXT — replace the replayed gpg status of the served database.
adv_db_status() {
    local sum
    sum="$(sha256sum "$SANDBOX/onio/serve/oniomarchy.db" | cut -d' ' -f1)"
    printf '%s\n' "$1" >"$SANDBOX/onio/status/$sum"
}

adv_annotation() { awk -F'\t' '$1 == "# oniomarchy" { print $2; exit }' <<<"$OUTPUT"; }
adv_state() { python3 "$VAPT_META" oniomarchy-status --root "$ROOT" | awk -F'\t' '$1 == "state" { print $2 }'; }
adv_field() { python3 "$VAPT_META" oniomarchy-status --root "$ROOT" | awk -F'\t' -v k="$1" '$1 == k { print $2 }'; }
adv_closure() { capture python3 "$VAPT_META" closure "$1" --root "$ROOT" --with-oniomarchy; }
# Fetches that reached the private source's host (BlackArch bootstrap
# fetches made by --yes are a separate, pre-existing source and not counted).
adv_onio_fetches() { vapt_calls curl | grep -c 'pkgs\.oniomarchy\.com' || true; }
adv_trust_ops() { vapt_calls sudo | grep -F pacman-key || true; }
adv_exists() { [[ -e $1 || -L $1 ]] && echo yes || echo no; }
adv_digest() { find "$1" -type f -printf '%P ' -exec sha256sum {} \; 2>/dev/null | LC_ALL=C sort; }

# adv_mutated_tree — a copy of share/haseen with the VAPT layer editable.
adv_mutated_tree() {
    ADV_TREE="$SANDBOX/share"
    rm -rf "$ADV_TREE"
    mkdir -p "$ADV_TREE/layers"
    cp -R "$HASEEN_PATH/lib" "$ADV_TREE/lib"
    cp -R "$HASEEN_PATH/default" "$ADV_TREE/default"
    cp -R "$VAPT_LAYER" "$ADV_TREE/layers/vapt"
    ADV_TREE_VAPT="$ADV_TREE/layers/vapt"
}
adv_tree_plan() {
    capture env HASEEN_PATH="$ADV_TREE" HASEEN_SYSROOT="$ROOT" PATH="$SANDBOX/cli-stubs:$PATH" haseen vapt install --dry-run "$@" </dev/null
}
