# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 007 review F1, adversarial: attempts to borrow the reviewed stock
# maintenance-hook trust with the wrong hook origin, owner, phase argv,
# interpreter link, PATH entry, data class or installed-owner state. Every
# archive is assembled here from original inert fixture bytes (decoy ELF
# headers, stand-in scripts, never upstream source); the audit only reads them
# and nothing (hook, helper, tool, package manager) runs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; the adversarial stock hook audit was skipped)"
    return 0
fi

HOOKS_DIR=usr/share/libalpm/hooks

# adv_case NAME [INSTALLED-ROW...] — fresh sysroot with the stock hook set.
adv_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    shift
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    (($# == 0)) || vapt_installed "$@"
    vapt_stock
    unset ADV_PLAN
}

# adv_archive NAME VERSION [ITEM...] — archive with .PKGINFO, usr/bin/NAME and
# ITEMs: PATH=TEXT (text file), PATH=@ELF (inert decoy ELF header),
# PATH@>TARGET (symlink), PATH<FILE (copy of FILE's bytes). Sets ADV_ARCHIVE.
adv_archive() {
    local name="$1" version="$2" dir="$SANDBOX/adv-packages/$1-$2" item path kind value
    local spec='^([A-Za-z0-9._/+-]+)(=|<|@>)(.*)$'
    local -A tops=([usr]=1)
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$dir/.PKGINFO"
    printf 'fixture decoy, never executed\n' >"$dir/usr/bin/$name"
    for item in "$@"; do
        [[ $item =~ $spec ]] || return 1
        path="${BASH_REMATCH[1]}" kind="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
        mkdir -p "$dir/$(dirname "$path")"
        rm -f "$dir/$path"
        case "$kind" in
            '@>') ln -s "$value" "$dir/$path" ;;
            '<') cp -- "$value" "$dir/$path" ;;
            *)
                if [[ $value == @ELF ]]; then
                    printf '\177ELF\002\001\001adversarial-decoy %s\n' "$path" >"$dir/$path"
                else
                    printf '%s\n' "$value" >"$dir/$path"
                fi
                ;;
        esac
        tops[${path%%/*}]=1
    done
    ADV_ARCHIVE="$SANDBOX/archives/$name-$version-x86_64.pkg.tar.gz"
    tar -czf "$ADV_ARCHIVE" -C "$dir" .PKGINFO "${!tops[@]}"
}

# adv_unpack ARCHIVE — extract an archive for modification; sets ADV_DIR.
# adv_repack ARCHIVE — rebuild ARCHIVE from ADV_DIR (.PKGINFO + top entries).
adv_unpack() {
    ADV_DIR="$SANDBOX/adv-unpacked/${1##*/}"
    rm -rf "$ADV_DIR"
    mkdir -p "$ADV_DIR"
    tar -xzf "$1" -C "$ADV_DIR"
}
adv_repack() {
    local entries=(.PKGINFO) entry
    for entry in "$ADV_DIR"/*; do entries+=("${entry##*/}"); done
    tar -czf "$1" -C "$ADV_DIR" "${entries[@]}"
}

# adv_plan REPO NAME VERSION... — solver plan rows naming archive sources.
adv_plan() {
    ADV_PLAN="$SANDBOX/adv-plan.tsv"
    : >"$ADV_PLAN"
    while (($# >= 3)); do
        printf '%s\t%s\t%s\thttps://mirror.example/%s-%s.pkg.tar.zst\n' "$1" "$2" "$3" "$2" "$3" >>"$ADV_PLAN"
        shift 3
    done
}

# adv_review LABEL EXPECTED ARCHIVE... — the read-only audit verdict.
adv_review() {
    local label="$1" expected="$2" plan=()
    shift 2
    [[ -z ${ADV_PLAN:-} ]] || plan=(--plan "$ADV_PLAN")
    capture python3 "$VAPT_META" audit "$@" "${plan[@]}" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}

LDCONF='etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
LDCONFIG_HOOK=$'[Trigger]\nOperation = Install\nType = Path\nTarget = usr/*\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/ldconfig -r .'

# --- the shipped policy itself, not the fixture restatement -----------------
# Without the fixture digest override the production stock-hooks.tsv must load
# and still trust a reviewed ELF-only hook, while the inert stand-in helper is
# never a reviewed upstream revision.
adv_case vapt-adv-shipped-policy
rm -f "$ROOT/var/lib/haseen/vapt/stock-hooks.tsv" "$ROOT/$HOOKS_DIR/35-systemd-update.hook"
adv_archive nmap 7.99-1 "$LDCONF"
adv_review 'shipped stock policy trusts the reviewed canonical ldconfig hook' 0 "$ADV_ARCHIVE"
adv_case vapt-adv-shipped-digests
rm -f "$ROOT/var/lib/haseen/vapt/stock-hooks.tsv"
adv_archive nmap 7.99-1
adv_review 'shipped helper digests never vouch for fixture stand-in bytes' 1 "$ADV_ARCHIVE"
assert_not_contains 'shipped stock policy parses' "$OUTPUT" 'malformed stock hook policy'

# --- origin: reviewed basename + Exec outside the owner's stock file --------
adv_case vapt-adv-admin-same-basename
mkdir -p "$ROOT/etc/pacman.d/hooks"
ln -s /dev/null "$ROOT/etc/pacman.d/hooks/11-glibc-ldconfig.hook"
adv_archive nmap 7.99-1 "$LDCONF"
adv_review 'admin /dev/null mask of the stock ldconfig hook is honoured (control)' 0 "$ADV_ARCHIVE"
rm "$ROOT/etc/pacman.d/hooks/11-glibc-ldconfig.hook"
printf '%s\n' "$LDCONFIG_HOOK" >"$ROOT/etc/pacman.d/hooks/11-glibc-ldconfig.hook"
adv_review 'admin hook overriding a stock basename with the reviewed Exec is not stock-trusted' 1 "$ADV_ARCHIVE"

adv_case vapt-adv-foreign-stock-hook
rm "$ROOT/$HOOKS_DIR/11-glibc-ldconfig.hook"
adv_plan extra nmap 7.99-1
adv_archive nmap 7.99-1 "$HOOKS_DIR/11-glibc-ldconfig.hook=$LDCONFIG_HOOK"
adv_review 'base-vendor non-owner shipping a stock-named hook with the reviewed Exec is refused' 1 "$ADV_ARCHIVE"

# --- ownership: base-vendor provenance is per reviewed owner, not per repo --
adv_case vapt-adv-nonowner-elf
adv_plan core ldtool 1-1 extra nmap 7.99-1
# Every planned archive is a reviewed repository record (no extra metadata).
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'EOF'
import json, sys
repos = json.load(open(sys.argv[1]))
repos.setdefault('core', []).append({'name': 'ldtool', 'version': '1-1', 'url': 'https://example.org/ldtool',
                                     'provides': [], 'depends': []})
json.dump(repos, open(sys.argv[1], 'w'))
EOF
adv_archive nmap 7.99-1 "$LDCONF"
NMAP_ARCHIVE="$ADV_ARCHIVE"
adv_archive ldtool 1-1
adv_review 'unrelated base-vendor package beside ldconfig maintenance (control)' 0 "$ADV_ARCHIVE" "$NMAP_ARCHIVE"
adv_archive ldtool 1-1 'usr/bin/ldconfig=@ELF'
adv_review 'base-vendor non-owner replacing the reviewed native ldconfig is refused' 1 "$ADV_ARCHIVE" "$NMAP_ARCHIVE"

adv_case vapt-adv-nonowner-identical-helper
adv_plan extra nmap 7.99-1
adv_archive nmap 7.99-1 "usr/share/libalpm/scripts/systemd-hook<$ROOT/usr/share/libalpm/scripts/systemd-hook"
adv_review 'byte-identical reviewed helper shipped by a non-owner is refused' 1 "$ADV_ARCHIVE"

adv_case vapt-adv-dual-owner 'shadowowner|1-1|https://example.org/shadowowner||||usr/bin/ldconfig'
adv_archive nmap 7.99-1
adv_review 'extra local owner row is inert while ldconfig is irrelevant (control)' 0 "$ADV_ARCHIVE"
adv_archive nmap 7.99-1 "$LDCONF"
adv_review 'reviewed program claimed by two installed packages is refused' 1 "$ADV_ARCHIVE"

# --- old installed source: the interpreter owner, not only the hook owner ---
adv_case vapt-adv-outdated-bash
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'EOF'
import json, sys
repos = json.load(open(sys.argv[1]))
for record in repos['core']:
    if record['name'] == 'bash':
        record['version'] = '5.3.3-3'
json.dump(repos, open(sys.argv[1], 'w'))
EOF
adv_archive nmap 7.99-1
NMAP_ARCHIVE="$ADV_ARCHIVE"
adv_review 'helper interpreter owner absent from the reviewed DB is refused' 1 "$NMAP_ARCHIVE"
assert_contains 'outdated interpreter refusal names the interpreter' "$OUTPUT" '/usr/bin/bash'
adv_plan core bash 5.3.3-3 extra nmap 7.99-1
adv_review 'full upgrade replacing the outdated interpreter owner passes' 0 \
    "$(vapt_stock_archive bash 5.3.3-3)" "$NMAP_ARCHIVE"

# --- changed interpreter chain in the future (PostTransaction) view --------
adv_case vapt-adv-sh-link
adv_archive nmap 7.99-1
NMAP_ARCHIVE="$ADV_ARCHIVE"
adv_plan extra dashlink 1-1 extra nmap 7.99-1
adv_archive dashlink 1-1 'usr/bin/sh@>dash' 'usr/bin/dash=@ELF'
adv_review 'non-owner retargeting /usr/bin/sh away from bash is refused' 1 "$ADV_ARCHIVE" "$NMAP_ARCHIVE"
BASH_ARCHIVE="$(vapt_stock_archive bash 5.3.3-3)"
adv_unpack "$BASH_ARCHIVE"
adv_repack "$BASH_ARCHIVE"
# The repacked bytes are the published, base-signed artifact for this control.
python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
adv_plan core bash 5.3.3-3 extra nmap 7.99-1
adv_review 'repacked unchanged base-vendor bash upgrade (control)' 0 "$BASH_ARCHIVE" "$NMAP_ARCHIVE"
rm "$ADV_DIR/usr/bin/sh"
ln -s dash "$ADV_DIR/usr/bin/sh"
printf '\177ELF\002\001\001adversarial-decoy usr/bin/dash\n' >"$ADV_DIR/usr/bin/dash"
adv_repack "$BASH_ARCHIVE"
adv_review 'base-vendor bash owner retargeting the /usr/bin/sh link is refused' 1 "$BASH_ARCHIVE" "$NMAP_ARCHIVE"

# --- owner upgrades that change argv, drop a helper or de-canonicalize ------
adv_case vapt-adv-owner-upgrade
adv_archive nmap 7.99-1 "$LDCONF"
NMAP_ARCHIVE="$ADV_ARCHIVE"
GLIBC_ARCHIVE="$(vapt_stock_archive glibc 2.44-2)"
adv_unpack "$GLIBC_ARCHIVE"
adv_plan core glibc 2.44-2 extra nmap 7.99-1
sed -i 's|^Exec = /usr/bin/ldconfig -r \.$|Exec = /usr/bin/ldconfig -r /usr/lib/nmap|' "$ADV_DIR/$HOOKS_DIR/11-glibc-ldconfig.hook"
adv_repack "$GLIBC_ARCHIVE"
adv_review 'owner upgrade changing the reviewed hook argv is not stock-trusted' 1 "$GLIBC_ARCHIVE" "$NMAP_ARCHIVE"
GLIBC_ARCHIVE="$(vapt_stock_archive glibc 2.44-2)"
adv_unpack "$GLIBC_ARCHIVE"
mv "$ADV_DIR/usr/bin/ldconfig" "$ADV_DIR/usr/bin/ldconfig.real"
ln -s ldconfig.real "$ADV_DIR/usr/bin/ldconfig"
adv_repack "$GLIBC_ARCHIVE"
adv_review 'owner upgrade turning the canonical native program into a symlink is refused' 1 \
    "$GLIBC_ARCHIVE" "$NMAP_ARCHIVE"
SYSTEMD_ARCHIVE="$(vapt_stock_archive systemd 261.3-1)"
adv_unpack "$SYSTEMD_ARCHIVE"
adv_repack "$SYSTEMD_ARCHIVE"
python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
adv_plan core systemd 261.3-1
adv_review 'repacked unchanged base-vendor systemd upgrade (control)' 0 "$SYSTEMD_ARCHIVE"
rm "$ADV_DIR/usr/share/libalpm/scripts/systemd-hook"
adv_repack "$SYSTEMD_ARCHIVE"
adv_review 'owner upgrade dropping the reviewed helper its hook still runs is refused' 1 "$SYSTEMD_ARCHIVE"

# --- PATH shadowing of a reviewed helper command in the future view ---------
# Root commits run with PATH=/usr/bin only: /usr/local entries are not on the
# consumer's PATH (its actual resolution is asserted by the commit tests).
adv_case vapt-adv-path-shadow
adv_archive nmap 7.99-1 $'usr/local/sbin/touch=#!/bin/sh\n# inert stand-in, never executed\nexit 97'
adv_review 'incoming /usr/local shadow is off the canonical root PATH' 0 "$ADV_ARCHIVE"
adv_archive nmap 7.99-1 'usr/local/bin@>../../opt/nmap/bin' \
    $'opt/nmap/bin/touch=#!/bin/sh\n# inert stand-in, never executed\nexit 97'
adv_review 'incoming symlinked /usr/local directory is off the canonical root PATH' 0 "$ADV_ARCHIVE"

# --- data the trusted maintenance would turn into loaded code --------------
# gconv-modules.d entries name shared objects glibc loads in-process; the
# iconvconfig cache rebuild is module-loader registration, which the reviewed
# policy excludes (cf. gio-querymodules).
adv_case vapt-adv-gconv
adv_archive nmap 7.99-1 'usr/lib/gconv/gconv-modules.d/nmap.conf=module NMAP// INTERNAL /usr/lib/nmap/gconv 1'
adv_review 'incoming gconv module registration via trusted iconvconfig is refused' 1 "$ADV_ARCHIVE"
vapt_tools_untouched 'adversarial stock audit'

# --- H2: retained bytes are proven against the installed version's record ---
# Fixture DB protocol: $ROOT/var/lib/pacman/sync/repositories.json is the
# system (pre-refresh) sync DB; var/lib/haseen/vapt/repositories.json is what
# the mirrors publish now and what a private refresh (-Syuw) fetches. The
# reviewed full upgrade replaces bash and glibc (new ELF bytes) and carries a
# builtin-only .INSTALL, so the PreTransaction shell and libc must be proven
# against the INSTALLED 5.3.3-2 / 2.44-1 records and their genuine cached
# references. Inert bytes only; nothing executes.
H2_MIRROR=var/lib/haseen/vapt/repositories.json
H2_SYSTEM=var/lib/pacman/sync/repositories.json
h2_member() { # ARCHIVE REL TEXT — add/replace one regular member
    python3 - "$1" "$2" "$3" <<'PY'
import io, sys, tarfile
from pathlib import Path
archive, rel, text = Path(sys.argv[1]), sys.argv[2], sys.argv[3].encode()
result = io.BytesIO()
with tarfile.open(archive, 'r:*') as old, tarfile.open(fileobj=result, mode='w:gz') as new:
    for member in old:
        if member.name.removeprefix('./').rstrip('/') != rel:
            new.addfile(member, old.extractfile(member) if member.isfile() else None)
    member = tarfile.TarInfo(rel)
    member.mode, member.size = 0o644, len(text)
    new.addfile(member, io.BytesIO(text))
archive.write_bytes(result.getvalue())
PY
}
h2_only_version() { # FILE REPO NAME VERSION — the DB lists one version of NAME
    python3 - "$ROOT/$1" "$2" "$3" "$4" <<'PY'
import json, sys
from pathlib import Path
path, repo, name, version = Path(sys.argv[1]), *sys.argv[2:]
records = json.loads(path.read_text())
records[repo] = [r for r in records[repo] if r['name'] != name or r.get('version') == version]
path.write_text(json.dumps(records))
PY
}
h2_version() { # NAME — installed version: installed.json once a commit wrote
    # it, otherwise the libalpm-shaped local DB vapt_stock seeds.
    python3 - "$ROOT" "$1" <<'PY'
import json, sys
from pathlib import Path
root, name = Path(sys.argv[1]), sys.argv[2]
path = root / 'var/lib/haseen/vapt/installed.json'
if path.is_file():
    records = json.loads(path.read_text())
else:
    records = []
    for desc in (root / 'var/lib/pacman/local').glob('*/desc'):
        fields, key = {}, None
        for row in desc.read_text().splitlines():
            if row.startswith('%') and row.endswith('%'):
                key = row.strip('%').lower()
            elif row and key:
                fields.setdefault(key, row)
        records.append(fields)
print(next((p.get('version') for p in records if p.get('name') == name), 'absent'))
PY
}
h2_case() { # NAME [snapshot-after-sync]
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    vapt_stock
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    [[ ${2:-} == snapshot-after-sync ]] || cp "$ROOT/$H2_MIRROR" "$ROOT/$H2_SYSTEM"
    H2_BASH="$(vapt_stock_archive bash 5.3.3-3 usr/bin/bash)"
    h2_member "$H2_BASH" .INSTALL $'post_upgrade() {\n return 0\n}\n'
    vapt_stock_archive glibc 2.44-2 usr/lib/libc.so.6 >/dev/null
    python3 "$VAPT_FIXTURE_DRIVER" digests "$VAPT_ARCHIVES"
    h2_only_version "$H2_MIRROR" core bash 5.3.3-3
    h2_only_version "$H2_MIRROR" core glibc 2.44-2
    [[ ${2:-} != snapshot-after-sync ]] || cp "$ROOT/$H2_MIRROR" "$ROOT/$H2_SYSTEM"
    printf 'core\tbash\t5.3.3-3\thttps://geo.mirror.pkgbuild.com/core/os/x86_64/bash-5.3.3-3-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
    printf 'core\tglibc\t2.44-2\thttps://geo.mirror.pkgbuild.com/core/os/x86_64/glibc-2.44-2-x86_64.pkg.tar.gz\n' >>"$VAPT_PLAN"
    H2_OLD="$ROOT/var/cache/pacman/pkg/bash-5.3.3-2-x86_64.pkg.tar.gz"
}
h2_refused() { # LABEL REASON-FRAGMENT
    local system_before="$1"
    shift
    vapt_api upgrade
    assert_status "H2 $1" 2 "$STATUS"
    [[ -z ${2:-} ]] || assert_contains "H2 $1: reason" "$OUTPUT" "$2"
    assert_eq "H2 $1: installed bash unchanged" 5.3.3-2 "$(h2_version bash)"
    assert_eq "H2 $1: installed glibc unchanged" 2.44-1 "$(h2_version glibc)"
    assert_eq "H2 $1: no recovery record" no "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
    assert_eq "H2 $1: system sync DB unchanged" "$system_before" "$(sha256sum <"$ROOT/$H2_SYSTEM")"
}

h2_case vapt-h2-both-refs
vapt_api upgrade
assert_status 'H2 bash+glibc upgrade with a scriptlet proves old bytes by installed-version references' 0 "$STATUS"
assert_eq 'H2 reviewed bash installed' 5.3.3-3 "$(h2_version bash)"
assert_eq 'H2 reviewed glibc installed' 2.44-2 "$(h2_version glibc)"
assert_eq 'H2 completed upgrade leaves no recovery record' no \
    "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"

h2_case vapt-h2-no-old-record snapshot-after-sync
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'pre-refresh DB already lists only the new version' \
    'has no pre-refresh or reviewed repository record'

h2_case vapt-h2-old-ref-uncached
rm -f "$H2_OLD" "$H2_OLD.sig"
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'installed-version reference neither cached nor downloadable' \
    'installed-version reference unavailable: core/bash 5.3.3-2'

h2_case vapt-h2-forged-old-ref
# Same filename and identity, other bytes; its own detached "signature" is
# valid for those bytes, but the pre-refresh record binds another digest.
h2_member "$H2_OLD" usr/bin/bash 'forged old shell bytes'
printf 'fixture-sha256 %s\n' "$(sha256sum "$H2_OLD" | cut -d' ' -f1)" >"$H2_OLD.sig"
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'forged installed-version reference'

h2_case vapt-h2-nonbase-old-ref
python3 - "$ROOT/var/lib/haseen/vapt/fixture-signatures.tsv" "$(sha256sum "$H2_OLD" | cut -d' ' -f1)" <<'PY'
import sys
from pathlib import Path
path, digest = Path(sys.argv[1]), sys.argv[2]
rows = [line for line in path.read_text().splitlines() if not line.startswith(digest + '\t')]
path.write_text('\n'.join(rows + [digest + '\tF1C7B4A5E00000000000000000000000000071ED']) + '\n')
PY
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'installed-version reference signed by a non-base key'

h2_case vapt-h2-forged-retained-shell
printf '\nlocal edit\n' >>"$ROOT/usr/bin/bash"
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'installed shell differs from its authenticated old reference' \
    'installed bytes not proven'

h2_case vapt-h2-digest-conflict
python3 - "$ROOT/$H2_MIRROR" "$ROOT/$H2_SYSTEM" <<'PY'
import json, sys
from pathlib import Path
mirror, system = Path(sys.argv[1]), Path(sys.argv[2])
# The refreshed DB still lists bash 5.3.3-2, under a digest other than the
# pre-refresh snapshot's: the same (repo, name, version) changed bytes.
old = next(r for r in json.loads(system.read_text())['core'] if r['name'] == 'bash')
repos = json.loads(mirror.read_text())
repos['core'].append(dict(old, sha256sum='0' * 64))
mirror.write_text(json.dumps(repos))
PY
h2_refused "$(sha256sum <"$ROOT/$H2_SYSTEM")" 'repository record digest changed during refresh' \
    'changed digest during refresh'
vapt_tools_untouched 'H2 installed-version references'
