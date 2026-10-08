# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 007 review F1: the read-only transaction audit against a host carrying
# the stock Arch maintenance hooks (systemd, glibc, fontconfig, desktop-file,
# mime, glib schemas, texinfo). Fixture data only: hook Trigger/Exec lines
# restate public package facts, helper scripts are original inert stand-ins,
# ELF programs are decoy bytes, and nothing (hook, helper, tool, manager) runs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; the stock hook audit was skipped)"
    return 0
fi

# stock_case NAME [INSTALLED-ROW...] — fresh sysroot with the stock hook set.
stock_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    shift
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    (($# == 0)) || vapt_installed "$@"
    vapt_stock
}
# tool NAME VERSION [PATH=CONTENT...] — an archive with usr/bin/NAME plus
# inert data payloads; PATH .INSTALL becomes the package scriptlet.
tool() {
    local name="$1" version="$2" dir="$SANDBOX/packages/$1" item members=(.PKGINFO usr)
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$dir/.PKGINFO"
    printf 'fixture decoy, never executed\n' >"$dir/usr/bin/$name"
    for item in "$@"; do
        mkdir -p "$dir/$(dirname "${item%%=*}")"
        printf '%s\n' "${item#*=}" >"$dir/${item%%=*}"
        [[ ${item%%=*} != .INSTALL ]] || members+=(.INSTALL)
        [[ ${item%%=*} != etc/* ]] || members+=(etc)
    done
    TOOL_ARCHIVE="$SANDBOX/archives/$name-$version-x86_64.pkg.tar.gz"
    tar -czf "$TOOL_ARCHIVE" -C "$dir" "${members[@]}"
    _vapt_digests
}
review() { # LABEL EXPECTED [ARCHIVE...] — $STOCK_PLAN rows name archive sources
    local label="$1" expected="$2" plan=()
    shift 2
    (($#)) || set -- "$TOOL_ARCHIVE"
    [[ -z ${STOCK_PLAN:-} ]] || plan=(--plan "$STOCK_PLAN")
    capture python3 "$VAPT_META" audit "$@" "${plan[@]}" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
# mtree_set OWNER-DIR PATH — re-record PATH's current digest in the owner's
# local mtree, modelling a package that really ships those bytes.
mtree_set() {
    python3 - "$ROOT" "$1" "$2" <<'EOF'
import gzip, hashlib, sys
from pathlib import Path
root, entry, path = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
mtree = root / 'var/lib/pacman/local' / entry / 'mtree'
digest = hashlib.sha256((root / path).read_bytes()).hexdigest()
lines = [line if not line.startswith('./' + path + ' ') else
         './' + path + ' type=file mode=644 sha256digest=' + digest
         for line in gzip.open(mtree, 'rt').read().splitlines()]
with gzip.open(mtree, 'wt') as output:
    output.write('\n'.join(lines) + '\n')
EOF
}

# --- benign transactions under the reviewed stock hook set ------------------
# Every package archive carries usr/, so 35-systemd-update is always relevant.
stock_case vapt-stock-plain
tool nmap 7.99-1
review 'F1 ordinary tool passes with the stock systemd update hook relevant' 0

stock_case vapt-stock-maintenance
tool nmap 7.99-1 'usr/share/applications/nmap.desktop=[Desktop Entry]' \
    'usr/share/mime/packages/nmap.xml=<mime-info/>' 'usr/share/fonts/nmap.otf=font' \
    'usr/share/glib-2.0/schemas/org.nmap.gschema.xml=<schemalist/>' 'usr/share/info/nmap.info=info' \
    'usr/lib/sysusers.d/nmap.conf=u nmap - "fixture account"' 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap' \
    'usr/share/fontconfig/conf.default/10-nmap.conf=<fontconfig/>'
review 'F1 reviewed cache/database maintenance hooks allow a benign transaction' 0

# --- incoming activation, Omarchy and opaque commands stay rejected ----------
stock_case vapt-stock-incoming-activation
tool nmap 7.99-1 $'.INSTALL=post_install() {\n systemctl enable --now nmap.socket\n}'
review 'incoming scriptlet activation still rejected under stock hooks' 1
tool nmap 7.99-1 $'usr/share/libalpm/hooks/nmap.hook=[Trigger]\nOperation = Install\nType = Package\nTarget = nmap\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/omarchy-refresh-config'
review 'incoming Omarchy hook still rejected under stock hooks' 1
tool nmap 7.99-1 $'usr/share/libalpm/hooks/nmap.hook=[Trigger]\nOperation = Install\nType = Package\nTarget = nmap\n[Action]\nWhen = PostTransaction\nExec = /bin/sh -c \'touch "$HOME/x"\''
review 'incoming opaque dynamic hook command still rejected' 1

# --- maintenance that interprets incoming data or loads code is not trusted -
stock_case vapt-stock-unreviewed-operations
tool nmap 7.99-1 'usr/lib/tmpfiles.d/nmap.conf=L+ /etc/systemd/system/multi-user.target.wants/nmap.service - - - - /usr/lib/systemd/system/nmap.service'
review 'tmpfiles operation (L lines can create .wants links) is refused' 1
tool nmap 7.99-1 $'usr/lib/systemd/system/nmap.service=[Service]\nExecStart=/usr/bin/nmap'
review 'unit payload triggers unreviewed daemon-reload and is refused' 1
tool nmap 7.99-1 'usr/lib/gio/modules/libnmap.so=module'
review 'module-loading gio-querymodules maintenance is refused' 1
tool nmap 7.99-1 'usr/lib/udev/rules.d/90-nmap.rules=ACTION=="add"'
review 'udev reload/trigger operation is refused' 1
tool nmap 7.99-1 'usr/lib/sysusers.d/nmap.conf=X /tmp/nmap'
review 'sysusers data outside account types is refused' 1
tool nmap 7.99-1 'usr/lib/sysusers.d/nmap.conf=u nmap - "fixture account"'
review 'sysusers account data control' 0

# --- changed or misattributed otherwise-trusted helpers ----------------------
stock_case vapt-stock-tampered-helper
printf '\nsystemctl enable --now evil.service\n' >>"$ROOT/usr/share/libalpm/scripts/systemd-hook"
tool nmap 7.99-1
review 'locally changed stock helper bytes (mtree mismatch) rejected' 1

stock_case vapt-stock-tampered-hook
sed -i 's|systemd-hook update|systemd-hook restart sshd.service|' "$ROOT/usr/share/libalpm/hooks/35-systemd-update.hook"
tool nmap 7.99-1
review 'stock hook rewritten to a restart operation rejected' 1

stock_case vapt-stock-admin-copy
mkdir -p "$ROOT/etc/pacman.d/hooks"
printf '[Trigger]\nOperation = Install\nType = Path\nTarget = usr/\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/ldconfig -r .\n' \
    >"$ROOT/etc/pacman.d/hooks/zz-copy.hook"
tool nmap 7.99-1
review 'reviewed Exec outside the stock hook path is not trusted by basename' 1
printf '[Trigger]\nOperation = Install\nType = Path\nTarget = usr/\n[Action]\nWhen = PreTransaction\nExec = /usr/share/libalpm/scripts/systemd-hook enqueue-marked\n' \
    >"$ROOT/etc/pacman.d/hooks/zz-copy.hook"
review 'stock helper with a restart argument from an admin hook rejected' 1

# Root commits run with PATH=/usr/bin only; a /usr/local shadow is not on the
# consumer's PATH (consumer resolution is asserted in test-vapt-commit.sh).
stock_case vapt-stock-path-shadow
mkdir -p "$ROOT/usr/local/bin"
printf '#!/bin/sh\nsystemctl enable --now evil.service\n' >"$ROOT/usr/local/bin/touch"
tool nmap 7.99-1
review 'out-of-PATH shadow is irrelevant to the canonical /usr/bin helper' 0

# Provenance is the installed bytes equal to an authenticated base reference;
# local version/URL labels neither grant nor deny it.
stock_case vapt-stock-unproven-owner
tool nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
review 'ldconfig maintenance with allowed glibc owner (control)' 0
sed -i 's/^2\.44-1$/2.44-9/' "$ROOT"/var/lib/pacman/local/glibc-2.44-1/desc
review 'relabelled local version with reference-equal bytes stays proven' 0
printf '\nlocal edit\n' >>"$ROOT/usr/bin/ldconfig"
review 'bytes differing from every authenticated reference are refused' 1

stock_case vapt-stock-not-native
printf '#!/bin/sh\nsystemctl enable --now evil.service\n' >"$ROOT/usr/bin/ldconfig"
mtree_set glibc-2.44-1 usr/bin/ldconfig
tool nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
review 'owner-attested script in place of the reviewed native program rejected' 1

# Owner upgrades: incoming stock bytes are audited in the future view. Changed
# native bytes are trusted only as the audited archive of the reviewed owner
# from a base-vendor repository (core/extra/multilib/cachyos*) named by the
# solver plan; reviewed helper scripts must additionally be a reviewed digest.
# .PKGINFO identity alone or a BlackArch/Chaotic homonym never vouches.
plan_rows() { # REPO NAME VERSION... (the fixture tool nmap is always its extra row)
    local repo="$1" source
    shift
    STOCK_PLAN="$SANDBOX/stock-plan.tsv"
    : >"$STOCK_PLAN"
    while (($#)); do
        source="$repo"
        [[ $1 != nmap ]] || source=extra
        printf '%s\t%s\t%s\thttps://mirror.example/%s-%s.pkg.tar.zst\n' "$source" "$1" "$2" "$1" "$2" >>"$STOCK_PLAN"
        shift 2
    done
}
stock_case vapt-stock-owner-upgrade
plan_rows core systemd 261.3-1
review 'systemd upgrade with unchanged reviewed helper' 0 "$(vapt_stock_archive systemd 261.3-1)"
review 'systemd upgrade with changed helper payload rejected' 1 \
    "$(vapt_stock_archive systemd 261.3-1 usr/share/libalpm/scripts/systemd-hook)"
plan_rows blackarch systemd 261.3-1
review 'BlackArch homonym of a stock owner never vouches for stock bytes' 1 "$(vapt_stock_archive systemd 261.3-1)"
unset STOCK_PLAN
review 'unplanned archive identity alone never vouches for stock bytes' 1 "$(vapt_stock_archive systemd 261.3-1)"
plan_rows core glibc 2.44-2
review 'glibc upgrade runs reviewed locale-gen' 0 "$(vapt_stock_archive glibc 2.44-2)"
review 'glibc upgrade with changed locale-gen rejected' 1 "$(vapt_stock_archive glibc 2.44-2 usr/bin/locale-gen)"
tool nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
plan_rows core glibc 2.44-2 nmap 7.99-1
review 'glibc base-vendor upgrade with changed native ldconfig bytes keeps owner provenance' 0 \
    "$(vapt_stock_archive glibc 2.44-2 usr/bin/ldconfig)" "$TOOL_ARCHIVE"
plan_rows chaotic-aur glibc 2.44-2 nmap 7.99-1
review 'Chaotic homonym with changed native ldconfig bytes rejected' 1 \
    "$(vapt_stock_archive glibc 2.44-2 usr/bin/ldconfig)" "$TOOL_ARCHIVE"
unset STOCK_PLAN
# A bash upgrade re-ships /usr/bin/sh -> bash and new interpreter bytes; the
# reviewed chain survives when both come from the base-vendor bash archive.
tool nmap 7.99-1
plan_rows core bash 5.3.3-3 nmap 7.99-1
review 'base-vendor bash upgrade keeps the reviewed interpreter chain' 0 \
    "$(vapt_stock_archive bash 5.3.3-3 usr/bin/bash)" "$TOOL_ARCHIVE"
plan_rows blackarch bash 5.3.3-3 nmap 7.99-1
review 'interpreter replaced by a non-base homonym rejected' 1 \
    "$(vapt_stock_archive bash 5.3.3-3 usr/bin/bash)" "$TOOL_ARCHIVE"
unset STOCK_PLAN

# Normal old-installed/new-repository state: the reviewed DB only carries the
# newer systemd. A transaction that leaves the old owner in place cannot prove
# its origin and is refused (remedy: full upgrade); the full upgrade itself
# replaces the owner with an audited base-vendor archive and passes.
stock_case vapt-stock-outdated-owner
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'EOF'
import json, sys
repos = json.load(open(sys.argv[1]))
for record in repos['core']:
    if record['name'] == 'systemd':
        record['version'] = '261.3-1'
json.dump(repos, open(sys.argv[1], 'w'))
EOF
tool nmap 7.99-1
review 'outdated stock owner absent from the reviewed DB is not trusted' 1
plan_rows core systemd 261.3-1 nmap 7.99-1
review 'full upgrade replacing the outdated owner with base-vendor bytes passes' 0 \
    "$(vapt_stock_archive systemd 261.3-1)" "$TOOL_ARCHIVE"
unset STOCK_PLAN

# Same name and version, different upstream label: bytes still decide.
stock_case vapt-stock-foreign-owner
sed -i 's|^https://www.github.com/systemd/systemd$|https://example.org/not-systemd|' \
    "$ROOT"/var/lib/pacman/local/systemd-261.2-1/desc
tool nmap 7.99-1
review 'local upstream label alone neither grants nor denies proven bytes' 0
# Same identity offered only by a non-base allowed repository (BlackArch).
stock_case vapt-stock-security-repo-owner
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'EOF'
import json, sys
repos = json.load(open(sys.argv[1]))
repos['blackarch'] = [r for r in repos['core'] if r['name'] == 'systemd']
repos['core'] = [r for r in repos['core'] if r['name'] != 'systemd']
json.dump(repos, open(sys.argv[1], 'w'))
EOF
tool nmap 7.99-1
review 'stock owner provable only through BlackArch is not base-vendor trusted' 1

# --- BlackArch keyring: stock hooks present, population exception unchanged --
stock_case vapt-stock-keyring
KEYRING_SCRIPT="$(cat "$FIXTURES/vapt-keyring.INSTALL")"
vapt_package blackarch-keyring 20251001-1 "$KEYRING_SCRIPT"
capture python3 "$VAPT_META" keyring "$SANDBOX/archives/blackarch-keyring-20251001-1-x86_64.pkg.tar.gz" --root "$ROOT"
assert_status 'keyring check passes with the stock hook set' 0 "$STATUS"
vapt_package blackarch-keyring 20251001-1 "${KEYRING_SCRIPT/--populate blackarch/--populate other}"
capture python3 "$VAPT_META" keyring "$SANDBOX/archives/blackarch-keyring-20251001-1-x86_64.pkg.tar.gz" --root "$ROOT"
assert_status 'changed keyring population scriptlet still rejected' 1 "$STATUS"

# --- representative ordinary upgrade scriptlets: documented outcome ----------
# Static notices are modelled; conditional/dynamic bodies need manual review
# (the owner's ordinary pacman -Syu outside VAPT), never assumed safe.
stock_case vapt-stock-upgrade-scriptlets 'subject|1-1|https://example.org/'
tool subject 2-1 $'.INSTALL=post_upgrade() {\n  echo "subject: restart your session"\n}'
review 'static upgrade notice scriptlet allowed' 0
tool subject 2-1 $'.INSTALL=post_upgrade() {\n  if [ "$(vercmp "$2" 1.0-1)" -lt 0 ]; then\n    echo "subject: format changed"\n  fi\n}'
review 'conditional upgrade scriptlet refused for manual review' 1
assert_contains 'conditional upgrade scriptlet names manual review' "$OUTPUT" 'requires manual review'

# --- consumer: the public per-package transaction under stock hooks ---------
stock_case vapt-stock-consumer
vapt_transactions
tool nmap 7.99-1
export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives"
printf 'extra\tnmap\t7.99-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/nmap-7.99-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
vapt_api pacman extra/nmap
assert_status 'F1 consumer: ordinary repository item installs under stock hooks' 0 "$STATUS"
assert_contains 'F1 consumer: item reaches the reviewed commit' "$OUTPUT" 'STATE=installed'
vapt_tools_untouched 'stock consumer'
