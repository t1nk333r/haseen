# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 007 landed-security follow-up (SEC-L1..L7). Fixture data only: archives,
# ELF metadata and selectors are inert, nothing (hook, scriptlet, interpreter,
# library, manager or key operation) executes, and every privileged request is
# recorded by a fake.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; landed security regressions were skipped)"
    return 0
fi

landed_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    vapt_stock
    unset LANDED_PLAN
    landed_facts
}
# landed_facts [PLUGIN...] — the sudoers group_plugin facts file a root
# producer would write (0755 dir, 0644 file); fixture ownership is the caller.
landed_facts() {
    LANDED_FACTS="$SANDBOX/facts/sudo-plugins"
    install -d -m 0755 "$SANDBOX/facts"
    rm -f "$LANDED_FACTS"
    printf '%s\n' "$@" | sed '/^$/d' >"$LANDED_FACTS"
    chmod 0644 "$LANDED_FACTS"
}
# landed_archive NAME VERSION [PATH=TEXT|PATH=@ELF:needed,soname|PATH@>LINK|PATH<FILE|.INSTALL=TEXT]...
landed_archive() {
    local name="$1" version="$2" dir="$SANDBOX/landed/$1-$2" item path value
    local -A tops=([usr]=1)
    local members=(.PKGINFO)
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$dir/.PKGINFO"
    printf 'inert fixture item, never executed\n' >"$dir/usr/bin/$name"
    for item in "$@"; do
        if [[ $item =~ ^([A-Za-z0-9._/+-]+)\<(.*)$ ]]; then
            # PATH<FILE: a member with exactly FILE's bytes.
            path="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
            mkdir -p "$dir/$(dirname "$path")"
            cp -- "$value" "$dir/$path"
        elif [[ $item == *'@>'* ]]; then
            path="${item%%@>*}" value="${item#*@>}"
            mkdir -p "$dir/$(dirname "$path")"
            ln -sfn "$value" "$dir/$path"
        else
            path="${item%%=*}" value="${item#*=}"
            mkdir -p "$dir/$(dirname "$path")"
            if [[ $value == @ELF:* ]]; then
                value="${value#@ELF:}"
                vapt_elf "$dir/$path" "needed=${value%%,*}" "soname=${value#*,}"
            else
                printf '%s\n' "$value" >"$dir/$path"
            fi
        fi
        if [[ $path == .INSTALL ]]; then members+=(.INSTALL); else tops[${path%%/*}]=1; fi
    done
    LANDED_ARCHIVE="$SANDBOX/archives/$name-$version-x86_64.pkg.tar.gz"
    tar -czf "$LANDED_ARCHIVE" -C "$dir" "${members[@]}" "${!tops[@]}"
}
landed_plan() { # REPO NAME VERSION... — plan rows, each a reviewed sync record
    LANDED_PLAN="$SANDBOX/landed-plan.tsv"
    : >"$LANDED_PLAN"
    while (($# >= 3)); do
        printf '%s\t%s\t%s\t%s-%s-x86_64.pkg.tar.gz\n' "$1" "$2" "$3" "$2" "$3" >>"$LANDED_PLAN"
        python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" "$1" "$2" "$3" <<'EOF'
import json, sys
path, repo, name, version = sys.argv[1:]
repos = json.load(open(path))
records = repos.setdefault(repo, [])
if not any(p['name'] == name and p['version'] == version for p in records):
    records.append({'name': name, 'version': version, 'url': 'https://example.org/' + name,
                    'provides': [], 'depends': []})
json.dump(repos, open(path, 'w'))
EOF
        shift 3
    done
}
landed_review() { # LABEL EXPECTED ARCHIVE...
    local label="$1" expected="$2" plan=()
    shift 2
    [[ -z ${LANDED_PLAN:-} ]] || plan=(--plan "$LANDED_PLAN")
    capture python3 "$VAPT_META" audit "$@" "${plan[@]}" --sudo-plugins "$LANDED_FACTS" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
no_stock_hooks() { rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook; }

# --- SEC-L1: a scriptlet runs through libalpm's /bin/sh chain ---------------
# No stock hook binds bash here; only the scriptlet's own shell does.
landed_case vapt-landed-scriptlet-shell
no_stock_hooks
landed_archive nmap 7.99-1 $'.INSTALL=post_install() {\n echo installed\n}'
landed_review 'SEC-L1 builtin-only scriptlet with the retained shell (control)' 0 "$LANDED_ARCHIVE"
NMAP_ARCHIVE="$LANDED_ARCHIVE"
landed_archive bash 5.3.3-3 'usr/bin/bash=@ELF:libc.so.6,' $'.INSTALL=post_upgrade() {\n return 0\n}'
landed_plan blackarch bash 5.3.3-3
landed_review 'SEC-L1 non-base replacement shell for a builtin-only scriptlet is refused' 1 "$LANDED_ARCHIVE"
landed_archive bash 5.3.3-3 'usr/bin/bash=@ELF:libc.so.6,'
landed_plan blackarch bash 5.3.3-3 extra nmap 7.99-1
landed_review 'SEC-L1 non-base replacement shell beside another package scriptlet is refused' 1 \
    "$LANDED_ARCHIVE" "$NMAP_ARCHIVE"
unset LANDED_PLAN
printf '\nlocal edit\n' >>"$ROOT/usr/bin/bash"
landed_review 'SEC-L1 retained shell not equal to its base reference cannot run a scriptlet' 1 "$NMAP_ARCHIVE"

# --- SEC-L2: privileged Python startup imports are part of the guard --------
landed_case vapt-landed-python-imports
no_stock_hooks
vapt_stock_python
landed_archive nmap 7.99-1 'usr/lib/python3.14/site-packages/nmapmod/__init__.py=# inert'
landed_review 'SEC-L2 site-packages addition is outside the isolated import path (control)' 0 "$LANDED_ARCHIVE"
landed_archive nmap 7.99-1 'usr/lib/python3.14/ctypes/__init__.so=@ELF:libc.so.6,'
landed_review 'SEC-L2 non-base extension shadowing a stdlib package is refused' 1 "$LANDED_ARCHIVE"
landed_archive nmap 7.99-1 'usr/lib/python3.14/zz_vapt.py=# inert'
landed_review 'SEC-L2 non-base addition to the isolated stdlib path is refused' 1 "$LANDED_ARCHIVE"
landed_archive nmap 7.99-1 'usr/lib/libalt.so.1=@ELF:,libc.so.6'
landed_review 'SEC-L2 non-base library selected by a stdlib extension dependency is refused' 1 "$LANDED_ARCHIVE"

# --- SEC-L3: future ldconfig indexes retained libraries ---------------------
for soname in libzz.so.999 libreadline.so.8; do
    landed_case "vapt-landed-retained-soname-$soname"
    vapt_elf "$ROOT/usr/lib/libzz.so.999" "soname=$soname"
    landed_archive nmap 7.99-1
    expected=0
    [[ $soname != libreadline.so.8 ]] || expected=1
    landed_review "SEC-L3 retained unowned library with SONAME $soname" "$expected" "$LANDED_ARCHIVE"
done

# --- SEC-L4: symlinked selector directories are not empty --------------------
for selector in loader gconv; do
    landed_case "vapt-landed-symlinked-$selector-selectors"
    mkdir -p "$ROOT/opt/configs"
    if [[ $selector == loader ]]; then
        rm -rf "$ROOT/etc/ld.so.conf.d"
        ln -s ../opt/configs "$ROOT/etc/ld.so.conf.d"
        landed_archive nmap 7.99-1 'opt/configs/tool.conf=/opt/tool/lib' \
            'opt/tool/lib/libtool.so.1=@ELF:,libreadline.so.8'
    else
        mkdir -p "$ROOT/usr/lib/gconv"
        printf 'module FIXTURE// INTERNAL FIXTURE 1\n' >"$ROOT/usr/lib/gconv/gconv-modules"
        ln -s ../../../opt/configs "$ROOT/usr/lib/gconv/gconv-modules.d"
        landed_archive nmap 7.99-1 'opt/configs/tool.conf=module TOOL// INTERNAL /opt/tool/lib/tool 1' \
            'opt/tool/lib/tool.so=@ELF:libc.so.6,'
    fi
    landed_review "SEC-L4 symlinked $selector selector directory is never treated as empty" 1 "$LANDED_ARCHIVE"
done

# --- SEC-L5: sealed artifacts need non-replaceable ancestry ------------------
vapt_sandbox vapt-landed-seal-ancestry
mkdir -p "$SANDBOX/src" "$SANDBOX/safe/sealed" "$SANDBOX/open/sealed"
printf 'inert artifact bytes\n' >"$SANDBOX/src/a-1-1-x86_64.pkg.tar.gz"
digest="$(sha256sum "$SANDBOX/src/a-1-1-x86_64.pkg.tar.gz" | cut -d' ' -f1)"
chmod 0755 "$SANDBOX/safe" "$SANDBOX/safe/sealed" "$SANDBOX/open/sealed"
chmod 0777 "$SANDBOX/open"
capture python3 "$VAPT_META" seal "$SANDBOX/src/a-1-1-x86_64.pkg.tar.gz" "$SANDBOX/safe/sealed/a-1-1-x86_64.pkg.tar.gz" "$digest" --root "$SANDBOX"
assert_status 'SEC-L5 fixture seal into caller-owned non-replaceable ancestry (control)' 0 "$STATUS"
capture python3 "$VAPT_META" seal "$SANDBOX/src/a-1-1-x86_64.pkg.tar.gz" "$SANDBOX/open/sealed/a-1-1-x86_64.pkg.tar.gz" "$digest" --root "$SANDBOX"
assert_status 'SEC-L5 seal below a world-writable ancestor is refused' 1 "$STATUS"
assert_eq 'SEC-L5 refused seal leaves no artifact' no "$([[ -e $SANDBOX/open/sealed/a-1-1-x86_64.pkg.tar.gz ]] && echo yes || echo no)"
chmod 0755 "$SANDBOX/open"
if [[ $(id -u) != 0 ]]; then
    rm -f "$SANDBOX/safe/sealed/a-1-1-x86_64.pkg.tar.gz"
    capture python3 "$VAPT_META" seal "$SANDBOX/src/a-1-1-x86_64.pkg.tar.gz" "$SANDBOX/safe/sealed/a-1-1-x86_64.pkg.tar.gz" "$digest"
    assert_status 'SEC-L5 production seal requires root-owned ancestry (no caller ownership)' 1 "$STATUS"
fi

# --- SEC-L6: committed archives equal the complete reviewed plan -------------
WHOIS_URL=https://github.com/rfc1036/whois
l6_case() {
    vapt_sandbox "$1"
    vapt_root
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL||libdep" 'extra|libdep|1-1|https://example.org/libdep'
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    printf 'extra\twhois\t5.6.4-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/whois-5.6.4-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
    printf 'extra\tlibdep\t1-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/libdep-1-1-x86_64.pkg.tar.gz\n' >>"$VAPT_PLAN"
}
# l6_archive FILE-NAME PKGNAME PKGVER DEPENDS — published under FILE-NAME's DB record.
l6_archive() {
    local dir="$SANDBOX/l6/$1"
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$2" "$3" >"$dir/.PKGINFO"
    [[ -z $4 ]] || printf 'depend = %s\n' "$4" >>"$dir/.PKGINFO"
    printf 'inert fixture item, never executed\n' >"$dir/usr/bin/$2"
    tar -czf "$SANDBOX/archives/$1" -C "$dir" .PKGINFO usr
    python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" "$1" "$(sha256sum "$SANDBOX/archives/$1" | cut -d' ' -f1)" <<'EOF'
import json, sys
path, filename, digest = sys.argv[1:]
repos = json.load(open(path))
for record in repos['extra']:
    if filename.startswith(record['name'] + '-' + record['version'] + '-'):
        record['sha256sum'], record['filename'] = digest, filename
json.dump(repos, open(path, 'w'))
EOF
}
installed_version() {
    python3 - "$ROOT/var/lib/haseen/vapt/installed.json" "$1" <<'EOF'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
records = json.loads(path.read_text()) if path.is_file() else []
print(next((p['version'] for p in records if p['name'] == sys.argv[2]), 'absent'))
EOF
}
for variant in control identity depends; do
    l6_case "vapt-landed-plan-$variant"
    l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
    case "$variant" in
    control) l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep ;;
    identity) l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whoami 5.6.4-1 libdep ;;
    depends) l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 'unreviewed-runtime' ;;
    esac
    vapt_api pacman --yes extra/whois
    if [[ $variant == control ]]; then
        assert_status 'SEC-L6 archive identity and dependencies equal the reviewed plan (control)' 0 "$STATUS"
        assert_eq 'SEC-L6 control installs the reviewed target' 5.6.4-1 "$(installed_version whois)"
    else
        assert_status "SEC-L6 $variant mismatch between signed archive and reviewed plan is refused" 2 "$STATUS"
        assert_eq "SEC-L6 $variant mismatch never opens an archive for commit" '' "$(vapt_calls commit-digests)"
        assert_eq "SEC-L6 $variant mismatch installs nothing" 'absent absent' "$(installed_version whois) $(installed_version whoami)"
    fi
    vapt_tools_untouched "SEC-L6 $variant"
done

# --- SEC-L7: public mutating entrypoints never use fixture trust live --------
vapt_sandbox vapt-landed-sysroot-mutation
vapt_root
vapt_repos "${VAPT_BASE[@]}" "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_sudo_noop
for verb in install remove; do
    if [[ $verb == install ]]; then vapt_cli install --yes --groups osint; else vapt_cli remove --yes; fi
    assert_status "SEC-L7 public $verb with a sysroot refuses to mutate" 2 "$STATUS"
    assert_eq "SEC-L7 public $verb with a sysroot requests no privileged operation" '' "$(vapt_calls sudo)"
done
vapt_cli install --dry-run --groups osint
assert_status 'SEC-L7 sysroot dry-run planning stays available' 0 "$STATUS"
vapt_tools_untouched 'SEC-L7 sysroot mutation refusal'

# --- Integration H1/H2/M1/M2/G5: real-host state and commit consistency -----
# Uses the per-package/full-upgrade setup of the SEC-L6 cases above.
whois_upgrade_case() {
    l6_case "$1"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL" "extra|whois|5.6.5-1|$WHOIS_URL"
    vapt_installed "whois|5.6.3-1|$WHOIS_URL"
    vapt_package whois 5.6.4-1
    printf 'extra\twhois\t5.6.4-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/whois-5.6.4-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
    printf 'original live sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
}
pending_state() { [[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no; }

# H1: a fresh host has no shared lock (or root state directory beyond the
# fixture's own protocol files): the first transaction creates it.
l6_case vapt-landed-fresh-state-dir
l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
rm -f "$ROOT/var/lib/haseen/vapt/transaction.lock"
vapt_api pacman --yes extra/whois
assert_status 'H1 first transaction on a host without the shared lock' 0 "$STATUS"
assert_eq 'H1 first transaction installs the reviewed target' 5.6.4-1 "$(installed_version whois)"
assert_eq 'H1 first transaction creates the shared lock' yes \
    "$([[ -f $ROOT/var/lib/haseen/vapt/transaction.lock ]] && echo yes || echo no)"

# N2: root state lives only at /var/lib/haseen. An environment override is
# refused with a reason before any root state operation; nothing is created
# or chmodded at the other path.
l6_case vapt-landed-state-dir-override
l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
mkdir -p "$ROOT/opt/elsewhere"
chmod 0700 "$ROOT/opt/elsewhere"
export HASEEN_STATE_DIR=/opt/elsewhere
vapt_api pacman --yes extra/whois
unset HASEEN_STATE_DIR
assert_status 'N2 HASEEN_STATE_DIR override is refused' 2 "$STATUS"
assert_contains 'N2 override refusal is reported' "$OUTPUT" 'HASEEN_STATE_DIR'
assert_eq 'N2 override installs nothing' absent "$(installed_version whois)"
assert_eq 'N2 override path is never chmodded by root' 700 "$(stat -c %a "$ROOT/opt/elsewhere")"
assert_eq 'N2 override path gets no lock or state' '' "$(ls -A "$ROOT/opt/elsewhere")"
# The root metadata operations themselves accept only the canonical paths.
capture python3 "$VAPT_META" state-repair "$ROOT/opt/elsewhere" --root "$ROOT"
assert_status 'N2 state-repair refuses a non-canonical directory' 1 "$STATUS"
assert_eq 'N2 refused state-repair leaves the mode' 700 "$(stat -c %a "$ROOT/opt/elsewhere")"
capture python3 "$VAPT_META" shared-lock-prepare "$ROOT/opt/elsewhere/transaction.lock" --root "$ROOT"
assert_status 'N2 shared-lock-prepare refuses a non-canonical lock' 1 "$STATUS"
assert_eq 'N2 refused shared-lock-prepare creates no lock' '' "$(ls -A "$ROOT/opt/elsewhere")"
capture python3 "$VAPT_META" state-repair "$ROOT/var/lib/haseen" "$ROOT/var/lib/haseen/vapt" --root "$ROOT"
assert_status 'N2 state-repair of the canonical directories (control)' 0 "$STATUS"

# H2: a restrictive caller umask must not make root-written review/commit
# files unreadable to the reviewer or to DownloadUser.
l6_case vapt-landed-umask-download
l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
mask="$(umask)"
umask 077
vapt_api pacman --yes extra/whois
umask "$mask"
assert_status 'H2 per-package transaction under umask 077' 0 "$STATUS"
assert_eq 'H2 downloaded artifacts are world-readable like libalpm under umask 022' '' \
    "$(grep -v ' 0o644$' "$CALLS/download-modes" || true)"
whois_upgrade_case vapt-landed-umask-frozen
mask="$(umask)"
umask 077
vapt_api upgrade
umask "$mask"
assert_status 'H2 full upgrade under umask 077' 0 "$STATUS"
assert_eq 'H2 frozen reviewed DB, its repository and parent are DownloadUser-readable' 'extra 0o644 0o755 0o755' \
    "$(sort -u "$CALLS/frozen-modes")"

# M1: a live DB refreshed after the review must not resolve the commit.
whois_upgrade_case vapt-landed-newer-live-db
export VAPT_LIVE_PLAN="$SANDBOX/live.tsv"
printf 'extra\twhois\t5.6.5-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/whois-5.6.5-1-x86_64.pkg.tar.gz\n' >"$VAPT_LIVE_PLAN"
touch -d '+1 day' "$ROOT/var/lib/pacman/sync/extra.db"
vapt_api upgrade
assert_status 'M1 reviewed full upgrade commits' 0 "$STATUS"
assert_eq 'M1 commit installs the reviewed version, never the newer live DB resolution' 5.6.4-1 "$(installed_version whois)"
assert_eq 'M1 live DB becomes the reviewed DB' 'reviewed fixture DB extra' "$(cat "$ROOT/var/lib/pacman/sync/extra.db")"

# M2: another user's recorded full-upgrade commit appearing after this run's
# early check still blocks a per-package commit once the lock is held.
l6_case vapt-landed-marker-after-precheck
l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
printf 'reviewed-full-upgrade-commit-pending\n' >"$ROOT/var/lib/haseen/vapt/upgrade-pending"
vapt_api pacman --yes extra/whois
assert_status 'M2 per-package commit over a recorded incomplete upgrade is refused' 2 "$STATUS"
assert_eq 'M2 nothing is committed' '' "$(vapt_calls commit-digests)"
assert_eq 'M2 the recorded commit is preserved' yes "$(pending_state)"

# G5: BlackArch activation and record clearing are each all-or-nothing and
# resumable: a failure leaves either the old config or the full stanza, and
# the recovery record until both are done.
ba_landed_case() {
    whois_upgrade_case "$1"
    vapt_repos "${VAPT_BASE[@]}" "extra|whois|5.6.4-1|$WHOIS_URL" "$VAPT_BA_KEYRING"
    vapt_package whois 5.6.4-1
    vapt_bootstrap_fixture
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
    CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
}
stanzas() { grep -c '^\[blackarch\]$' "$ROOT/etc/pacman.conf" || true; }
for step in activate-blackarch state-clear; do
    ba_landed_case "vapt-landed-ba-$step-failure"
    export VAPT_FAIL_ROOT_OP="$step"
    vapt_api blackarch
    unset VAPT_FAIL_ROOT_OP
    assert_contains "G5 $step failure is a mutation failure" "$OUTPUT" 'MUTATION=1'
    assert_eq "G5 $step failure keeps the recovery record" yes "$(pending_state)"
    if [[ $step == activate-blackarch ]]; then
        assert_eq 'G5 failed activation leaves the previous config byte-identical' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
    else
        assert_eq 'G5 failed record clear leaves exactly one complete stanza' 1 "$(stanzas)"
        assert_contains 'G5 failed record clear leaves the stanza usable' "$(cat "$ROOT/etc/pacman.conf")" 'Server = https://blackarch.org/blackarch/$repo/os/$arch'
    fi
    vapt_api recover
    assert_status "G5 recovery after a $step failure completes" 0 "$STATUS"
    assert_eq "G5 recovery after a $step failure leaves exactly one stanza" 1 "$(stanzas)"
    assert_eq "G5 recovery after a $step failure clears the record" no "$(pending_state)"
    assert_contains "G5 recovery after a $step failure leaves BlackArch usable" "$OUTPUT" 'STATE=usable'
    vapt_tools_untouched "G5 $step"
done

# --- SEC-L1b: libalpm runs .INSTALL whenever its text names the phase ------
# libalpm decides by grepping the .INSTALL text for the phase name, not by a
# function-definition shape: any non-exempt scriptlet seeds the shell proof.
for body in $'echo post_install\n' $'printf "%s" pre_upgrade\n'; do
    landed_case vapt-landed-scriptlet-phase-text
    no_stock_hooks
    printf '\nlocal edit\n' >>"$ROOT/usr/bin/bash"
    landed_archive nmap 7.99-1 ".INSTALL=$body"
    landed_review "SEC-L1b scriptlet text naming a phase needs a base-proven shell: ${body%%$'\n'*}" 1 "$LANDED_ARCHIVE"
done
landed_case vapt-landed-scriptlet-phase-control
no_stock_hooks
landed_archive nmap 7.99-1 $'.INSTALL=echo post_install\n'
landed_review 'SEC-L1b phase text with the base-proven shell (control)' 0 "$LANDED_ARCHIVE"
# The static scriptlet grammar supports only `name() {` openers; a split
# definition is an unsupported shape and stays a manual-review refusal.
landed_archive nmap 7.99-1 $'.INSTALL=post_install ()\n{\n return 0\n}'
landed_review 'SEC-L1b split function definition remains an unsupported shape' 1 "$LANDED_ARCHIVE"

# --- SEC-L3b: ldconfig indexes library symlinks through their targets ------
for variant in colliding unrelated; do
    landed_case "vapt-landed-soname-symlink-$variant"
    soname=libnovelalias.so.1
    [[ $variant == unrelated ]] || soname=libreadline.so.8
    mkdir -p "$ROOT/opt/outside"
    vapt_elf "$ROOT/opt/outside/payload.bin" "soname=$soname"
    ln -s ../../opt/outside/payload.bin "$ROOT/usr/lib/libnovel-alias.so.1"
    landed_archive nmap 7.99-1
    expected=0
    [[ $variant == unrelated ]] || expected=1
    landed_review "SEC-L3b retained library symlink to a $variant-SONAME object outside the search dirs" "$expected" "$LANDED_ARCHIVE"
done
landed_case vapt-landed-soname-symlink-incoming
landed_archive nmap 7.99-1 'usr/lib/libnovel-alias.so.1@>../../opt/nmap/payload.bin' \
    'opt/nmap/payload.bin=@ELF:,libreadline.so.8'
landed_review 'SEC-L3b incoming library symlink to a colliding-SONAME object is refused' 1 "$LANDED_ARCHIVE"

# --- PAM1/SUDO1: post-commit sudo loads PAM and sudo.conf plugins -----------
# haseen's own privileged steps after the commit run sudo, which dlopens PAM
# modules named by /etc/pam.d/sudo (and its includes) and sudo.conf plugins.
pam_case() {
    landed_case "$1"
    no_stock_hooks
    mkdir -p "$ROOT/etc/pam.d" "$ROOT/usr/lib/security" "$ROOT/usr/lib/sudo"
    printf 'auth include system-auth\naccount include system-auth\nsession include system-auth\n' >"$ROOT/etc/pam.d/sudo"
    printf 'auth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so\n' >"$ROOT/etc/pam.d/system-auth"
    vapt_elf "$ROOT/usr/bin/sudo" needed=libc.so.6 interp=/usr/lib64/ld-linux-x86-64.so.2 type=2
}
pam_case vapt-landed-pam-control
landed_archive nmap 7.99-1
landed_review 'PAM1 unrelated package with retained PAM/sudo configuration (control)' 0 "$LANDED_ARCHIVE"
for change in pam-include pam-module sudo-conf sudo-plugin; do
    pam_case "vapt-landed-pam-$change"
    case "$change" in
    pam-include) landed_archive nmap 7.99-1 'etc/pam.d/system-auth=auth required /opt/nmap/pam_evil.so' 'opt/nmap/pam_evil.so=@ELF:libc.so.6,' ;;
    pam-module) landed_archive nmap 7.99-1 'usr/lib/security/pam_unix.so=@ELF:libc.so.6,' ;;
    sudo-conf) landed_archive nmap 7.99-1 'etc/sudo.conf=Plugin sudoers_policy /opt/nmap/policy.so' 'opt/nmap/policy.so=@ELF:libc.so.6,' ;;
    sudo-plugin) landed_archive nmap 7.99-1 'usr/lib/sudo/sudoers.so=@ELF:libc.so.6,' ;;
    esac
    landed_review "PAM1 unauthenticated change to the post-commit sudo $change graph is refused" 1 "$LANDED_ARCHIVE"
done

# --- SEC-FROZEN-1: production-parity sudoers facts --------------------------
# The unprivileged audit cannot read root-only sudoers: it consumes the root
# producer's facts file and refuses without it, fixture root or not.
pam_case vapt-landed-facts-required
landed_archive nmap 7.99-1
capture python3 "$VAPT_META" audit "$LANDED_ARCHIVE" --root "$ROOT"
assert_status 'FROZEN-1 audit without sudoers group_plugin facts is refused' 1 "$STATUS"
for selected in no yes; do
    pam_case "vapt-landed-group-plugin-$selected"
    mkdir -p "$ROOT/usr/lib/vapt"
    vapt_elf "$ROOT/usr/lib/vapt/group_vapt.so" needed=libc.so.6
    [[ $selected == no ]] || landed_facts /usr/lib/vapt/group_vapt.so
    landed_archive nmap 7.99-1 'usr/lib/vapt/group_vapt.so=@ELF:libc.so.6,'
    expected=0
    [[ $selected == no ]] || expected=1
    landed_review "FROZEN-1 unauthenticated replacement of a sudoers group_plugin (selected=$selected)" "$expected" "$LANDED_ARCHIVE"
done

# --- SEC-FROZEN-3/4/5: the root producer refuses unmodelled sudo selection ---
# The producer writes only <sysroot>/var/cache/haseen-vapt.<id>/sudo-plugins,
# into the existing root stage it never creates or chmods.
PRODUCED=var/cache/haseen-vapt.landed/sudo-plugins
producer_case() { # LABEL EXPECTED — run the producer on the fixture sysroot
    rm -rf "$ROOT/var/cache/haseen-vapt.landed"
    install -d -m 0755 "$ROOT/var/cache/haseen-vapt.landed"
    capture python3 "$VAPT_META" sudo-plugins --out "$ROOT/$PRODUCED" --root "$ROOT"
    assert_status "$1" "$2" "$STATUS"
    if [[ $2 != 0 ]]; then
        assert_eq "$1: no facts file is produced" no "$([[ -e $ROOT/$PRODUCED ]] && echo yes || echo no)"
    fi
}
pam_case vapt-landed-producer
printf 'root ALL=(ALL:ALL) ALL\nDefaults group_plugin="/usr/lib/vapt/group_vapt.so /etc/group"\n' >"$ROOT/etc/sudoers"
producer_case 'FROZEN producer literal group_plugin (control)' 0
assert_eq 'FROZEN producer names the selected module' /usr/lib/vapt/group_vapt.so "$(cat "$ROOT/$PRODUCED" 2>/dev/null)"
# B2: any other destination is refused before anything is created or chmodded.
install -d -m 0750 "$SANDBOX/elsewhere"
for out in "$SANDBOX/elsewhere/sudo-plugins" "$ROOT/sudo-plugins" \
    "$ROOT/var/cache/haseen-vapt.landed/nested/sudo-plugins" "$ROOT/var/cache/other/sudo-plugins"; do
    capture python3 "$VAPT_META" sudo-plugins --out "$out" --root "$ROOT"
    assert_status "B2 producer refuses an unconfined destination: ${out#"$SANDBOX"/}" 1 "$STATUS"
    assert_eq "B2 unconfined destination stays absent: ${out#"$SANDBOX"/}" no \
        "$([[ -e $out || -e $out.new ]] && echo yes || echo no)"
done
assert_eq 'B2 producer creates no unconfined directory' no \
    "$([[ -e $ROOT/var/cache/haseen-vapt.landed/nested || -e $ROOT/var/cache/other ]] && echo yes || echo no)"
assert_eq 'B2 producer never chmods an existing parent' 750 "$(stat -c %a "$SANDBOX/elsewhere")"
rm -rf "$ROOT/var/cache/haseen-vapt.landed"
capture python3 "$VAPT_META" sudo-plugins --out "$ROOT/$PRODUCED" --root "$ROOT"
assert_status 'B2 producer never creates the root stage itself' 1 "$STATUS"
mkdir -p "$ROOT/etc/sudoers.d"
for include in '@include "/etc/sudoers.d/vapt policy"' '@include /etc/sudoers.d/vapt\ policy' '#include "/etc/sudoers.d/vapt"' '@includedir "/etc/sudoers.d"'; do
    printf 'root ALL=(ALL:ALL) ALL\n%s\n' "$include" >"$ROOT/etc/sudoers"
    producer_case "FROZEN-3 unsupported sudoers include spelling is refused: $include" 1
done
for override in 'Defaults pam_service=vapt' 'Defaults:alice pam_login_service=vapt' 'Defaults pam_askpass_service=vapt'; do
    printf 'root ALL=(ALL:ALL) ALL\n%s\n' "$override" >"$ROOT/etc/sudoers"
    producer_case "FROZEN-5 sudoers PAM service override is refused: $override" 1
done
printf 'root ALL=(ALL:ALL) ALL\n' >"$ROOT/etc/sudoers"
for conf in 'Plugin sudoers_policy sudoers.so sudoers_file=/etc/vapt-sudoers' 'Plugin sudoers_policy sudoers.so ldap_conf=/etc/vapt-ldap.conf' 'Path plugin_dir /usr/lib/vapt'; do
    printf '%s\n' "$conf" >"$ROOT/etc/sudo.conf"
    producer_case "FROZEN-4 sudo.conf source/plugin_dir override is refused by the producer: $conf" 1
    landed_archive nmap 7.99-1
    landed_review "FROZEN-4 sudo.conf source/plugin_dir override is refused by the audit: $conf" 1 "$LANDED_ARCHIVE"
done
rm -f "$ROOT/etc/sudo.conf"
printf 'passwd: files\ngroup: files\nsudoers: files ldap\n' >"$ROOT/etc/nsswitch.conf"
producer_case 'FROZEN-4 nsswitch sudoers source other than files is refused' 1

# --- RPATH: inherited DT_RPATH search is not modelled ------------------------
for tag in runpath rpath rpath-origin; do
    pam_case "vapt-landed-$tag"
    case "$tag" in
    runpath) entry=runpath=/usr/lib/sudo ;;
    rpath) entry=rpath=/usr/lib/sudo ;;
    rpath-origin) entry='rpath=$ORIGIN' ;;
    esac
    vapt_elf "$ROOT/usr/bin/sudo" needed=libc.so.6 interp=/usr/lib64/ld-linux-x86-64.so.2 type=2 "$entry"
    landed_archive nmap 7.99-1
    expected=1
    [[ $tag != runpath ]] || expected=0
    landed_review "RPATH reached privileged object with $entry" "$expected" "$LANDED_ARCHIVE"
done

# --- SEC-L1 prerequisite: a scriptlet needs a shell in both snapshots --------
landed_case vapt-landed-scriptlet-no-shell
no_stock_hooks
rm -f "$ROOT/bin/sh" "$ROOT/usr/bin/sh" "$ROOT/usr/bin/bash"
landed_archive nmap 7.99-1 $'.INSTALL=echo post_install\n'
landed_review 'SEC-L1 scriptlet without a base-proven shell in a needed snapshot is refused' 1 "$LANDED_ARCHIVE"

# --- Audit H1: the scriptlet shell expands unquoted braces, globs and tildes -
# An audited literal member named like the unexpanded word is not what bash
# runs. Inert payloads only; nothing executes.
for word in '/usr/bin/{nmap-helper,nmap-alt}' '/usr/bin/nmap-hel?er' '/usr/bin/nmap-help*' \
    '/usr/bin/nmap-help[e]r' '~root/../usr/bin/nmap-helper'; do
    landed_case vapt-landed-scriptlet-expansion
    no_stock_hooks
    landed_archive nmap 7.99-1 "usr/bin/$(basename -- "$word")=#!/bin/sh" 'usr/bin/nmap-helper=#!/bin/sh' \
        ".INSTALL=post_install() {"$'\n'" $word"$'\n}'
    landed_review "H1 unquoted shell expansion in a scriptlet command word is refused: $word" 1 "$LANDED_ARCHIVE"
done
for word in "'{a,b}'" '"*"' "'~'"; do
    landed_case vapt-landed-scriptlet-quoted-literal
    no_stock_hooks
    landed_archive nmap 7.99-1 ".INSTALL=post_install() {"$'\n'" echo $word"$'\n}'
    landed_review "H1 quoted literal argument stays literal (control): $word" 0 "$LANDED_ARCHIVE"
done

# --- Audit L3: helper bytes come from the exact member, not a name pattern ---
# A quoted '/usr/bin/[ab]' runs the literal member usr/bin/[ab]; a pattern
# lookup would audit usr/bin/a instead. Inert text only; nothing executes.
landed_case vapt-landed-helper-exact-member
no_stock_hooks
landed_archive nmap 7.99-1 $'usr/bin/[ab]=#!/bin/sh\nsystemctl enable evil.socket' $'usr/bin/a=#!/bin/sh\necho ok' \
    $'.INSTALL=post_install() {\n \'/usr/bin/[ab]\'\n}'
landed_review 'L3 the literal helper member body is the one audited' 1 "$LANDED_ARCHIVE"

# --- INT-CACHE: an artifact already in the host package cache --------------
# pacman -p prints %l as file://<cachedir>/<file> for cached artifacts; the
# transaction must still plan, seal and commit the reviewed artifact.
for kind in per-package full-upgrade; do
    if [[ $kind == per-package ]]; then
        l6_case vapt-landed-cached-artifact-package
        l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
        l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
    else
        whois_upgrade_case vapt-landed-cached-artifact-upgrade
    fi
    mkdir -p "$ROOT/var/cache/pacman/pkg"
    cp "$SANDBOX/archives/whois-5.6.4-1-x86_64.pkg.tar.gz" "$ROOT/var/cache/pacman/pkg/"
    if [[ $kind == per-package ]]; then vapt_api pacman --yes extra/whois; else vapt_api upgrade; fi
    assert_status "INT-CACHE $kind transaction with a host-cached artifact" 0 "$STATUS"
    assert_eq "INT-CACHE $kind installs the reviewed version" 5.6.4-1 "$(installed_version whois)"
    assert_eq "INT-CACHE $kind leaves no recovery record" no "$(pending_state)"
done

# --- INT-ACTIVATE: an unusable pacman.conf is refused before any commit ----
# Activation needs a single regular /etc/pacman.conf. If it is a symlink, a
# reviewed commit could never be followed by activation (perpetual recovery):
# refuse before the marker or any package change.
ba_landed_case vapt-landed-activation-preflight
mv "$ROOT/etc/pacman.conf" "$ROOT/etc/pacman.conf.real"
ln -s pacman.conf.real "$ROOT/etc/pacman.conf"
vapt_api blackarch
assert_eq 'INT-ACTIVATE symlinked pacman.conf: nothing is committed' '' "$(vapt_calls commit-digests)"
assert_eq 'INT-ACTIVATE symlinked pacman.conf: no recovery record' no "$(pending_state)"
assert_eq 'INT-ACTIVATE symlinked pacman.conf: configuration untouched' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf.real")"
assert_eq 'INT-ACTIVATE symlinked pacman.conf: link preserved' yes "$([[ -L $ROOT/etc/pacman.conf ]] && echo yes || echo no)"

# --- N1: scriptlet and helper text is split and stripped exactly as bash ----
# bash lines end only at LF and only space/tab are blanks: a VT/FF/FS/NEL or
# Unicode separator must not turn a command word into an apparent comment.
# U+2028 and NEL are spelled as their UTF-8 bytes (locale-independent).
for hidden in $'\v# hidden' $'\f# hidden' $'\x1c# hidden' $'\xe2\x80\xa8# hidden' $'\xc2\x85# hidden' $'\xff# hidden'; do
    landed_case vapt-landed-scriptlet-whitespace
    no_stock_hooks
    landed_archive nmap 7.99-1 ".INSTALL=post_install() {"$'\n'" $hidden"$'\n}'
    landed_review "N1 control/non-shell whitespace in scriptlet text is refused: $(printf '%q' "$hidden")" 1 "$LANDED_ARCHIVE"
done
landed_case vapt-landed-scriptlet-tab-control
no_stock_hooks
landed_archive nmap 7.99-1 $'.INSTALL=post_install() {\n\t# note\n\techo\tpost_install\n}'
landed_review 'N1 tab-indented comment and tab-separated words (control)' 0 "$LANDED_ARCHIVE"
# A retained host helper is read as raw bytes: no universal-newline rewrite.
for body in $'#!/bin/sh\n\r# note\nexit 0\n' $'#!/bin/sh\n\v# note\nexit 0\n' $'#!/bin/sh\n# note\nexit 0\n'; do
    landed_case vapt-landed-host-helper-bytes
    no_stock_hooks
    mkdir -p "$ROOT/usr/local/lib"
    printf '%s' "$body" >"$ROOT/usr/local/lib/setup"
    printf '[Trigger]\nOperation = Install\nType = Package\nTarget = nmap\n[Action]\nWhen = PostTransaction\nExec = /bin/sh /usr/local/lib/setup\n' \
        >"$ROOT/usr/share/libalpm/hooks/zz-local.hook"
    landed_archive nmap 7.99-1
    expected=1
    [[ $body != *$'\r'* && $body != *$'\v'* ]] && expected=0
    landed_review "N1 retained helper bytes are audited exactly: $(printf '%q' "${body#*$'\n'}")" "$expected" "$LANDED_ARCHIVE"
done

# --- SEC-HELPER-SELF: the program haseen runs as root, and its policy -------
# A reviewed copy of this layer installed in the sysroot (owned by a package,
# reached through a retained symlink) audits a transaction. Its own module,
# its policy files, their link hops and physical targets may not be replaced,
# redirected or removed by unauthenticated bytes; byte-identical payloads and
# unrelated packages are unaffected. Incoming members are inert data.
self_case() { # NAME [logical|physical]
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    local layer=opt/haseen/layers/vapt
    vapt_installed "haseen-vapt|1-1|https://example.org/haseen||||usr/share/haseen,$layer/metadata.py,$layer/files/stock-hooks.tsv,$layer/files/blackarch-signers.txt"
    vapt_stock
    no_stock_hooks
    unset LANDED_PLAN
    landed_facts
    mkdir -p "$ROOT/opt/haseen/layers"
    cp -R "$VAPT_LAYER" "$ROOT/$layer"
    ln -s ../../opt/haseen "$ROOT/usr/share/haseen"
    SELF_META="$ROOT/usr/share/haseen/layers/vapt/metadata.py"
    SELF_LAYER="$ROOT/$layer"
}
self_review() { # LABEL EXPECTED ARCHIVE...
    local label="$1" expected="$2" stage="$ROOT/var/cache/haseen-vapt.self"
    shift 2
    # Root-only retained-attribute facts from the real producer, run with
    # the SAME copied module that audits (fixture: caller-owned stage).
    rm -rf "$stage"
    install -d -m 0755 "$stage"
    capture python3 "$SELF_META" authority-facts --out "$stage/authority-facts" --root "$ROOT"
    assert_status "$label: retained authority facts produced" 0 "$STATUS"
    capture python3 "$SELF_META" audit "$@" --sudo-plugins "$LANDED_FACTS" \
        --authority-facts "$stage/authority-facts" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
self_case vapt-landed-self-unrelated
landed_archive nmap 7.99-1
self_review 'SELF unrelated package beside the installed haseen program (control)' 0 "$LANDED_ARCHIVE"
self_case vapt-landed-self-identical
landed_archive haseen-vapt 2-1 "opt/haseen/layers/vapt/metadata.py<$SELF_LAYER/metadata.py" \
    "opt/haseen/layers/vapt/files/stock-hooks.tsv<$SELF_LAYER/files/stock-hooks.tsv" \
    "opt/haseen/layers/vapt/files/blackarch-signers.txt<$SELF_LAYER/files/blackarch-signers.txt" 'usr/share/haseen@>../../opt/haseen'
self_review 'SELF byte-identical program and policy upgrade (control)' 0 "$LANDED_ARCHIVE"
for change in module-bytes policy-bytes signers-bytes module-link module-removed logical-hop policy-dir-link; do
    self_case "vapt-landed-self-$change"
    keep=("opt/haseen/layers/vapt/metadata.py<$SELF_LAYER/metadata.py"
          "opt/haseen/layers/vapt/files/stock-hooks.tsv<$SELF_LAYER/files/stock-hooks.tsv"
          "opt/haseen/layers/vapt/files/blackarch-signers.txt<$SELF_LAYER/files/blackarch-signers.txt"
          'usr/share/haseen@>../../opt/haseen')
    case "$change" in
    module-bytes) keep[0]='opt/haseen/layers/vapt/metadata.py=# changed root program' ;;
    policy-bytes) keep[1]=$'opt/haseen/layers/vapt/files/stock-hooks.tsv=# changed stock hook policy' ;;
    signers-bytes) keep[2]='opt/haseen/layers/vapt/files/blackarch-signers.txt=0000000000000000000000000000000000000000' ;;
    module-link) keep[0]='opt/haseen/layers/vapt/metadata.py@>../../../vapt-other.py' ;;
    module-removed) unset 'keep[0]' ;;
    logical-hop) keep[3]='usr/share/haseen@>../../opt/haseen-other' ;;
    policy-dir-link) keep[1]='opt/haseen/layers/vapt/files@>../../../vapt-policy'; unset 'keep[2]' ;;
    esac
    landed_archive haseen-vapt 2-1 "${keep[@]}"
    self_review "SELF unauthenticated $change change to the program haseen runs as root is refused" 1 "$LANDED_ARCHIVE"
done

# --- Root gateway: the privilege entry itself is not resolved via caller PATH
# A caller PATH entry shadowing the gateway's interpreter (the fixture's
# run_root analogue of sudo) never runs a privileged step; it passes through.
l6_case vapt-landed-root-gateway-path
l6_archive libdep-1-1-x86_64.pkg.tar.gz libdep 1-1 ''
l6_archive whois-5.6.4-1-x86_64.pkg.tar.gz whois 5.6.4-1 libdep
mkdir -p "$SANDBOX/shadow"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>%q\nexec /usr/bin/python3 "$@"\n' "$SANDBOX/shadow.log" >"$SANDBOX/shadow/python3"
chmod +x "$SANDBOX/shadow/python3"
PATH="$SANDBOX/shadow:$PATH" vapt_api pacman --yes extra/whois
assert_status 'gateway: shadowed caller PATH still completes the transaction' 0 "$STATUS"
assert_eq 'gateway: no privileged step goes through the caller PATH shadow' '' \
    "$(grep -F "$VAPT_FIXTURE_DRIVER root" "$SANDBOX/shadow.log" 2>/dev/null || true)"

# --- SELF anchors: the base-vendor keyrings the audit trusts ---------------
# base_signers/artifact_signer read exactly archlinux/cachyos .gpg and
# -revoked. An unauthenticated package may not replace, add or redirect
# them; other keyrings stay ordinary data; a signed base update is accepted.
for anchor in changed revoked-added link keyrings-dir-link blackarch-control; do
    landed_case "vapt-landed-anchor-$anchor"
    no_stock_hooks
    mkdir -p "$ROOT/usr/share/pacman/keyrings"
    printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
    expected=1
    case "$anchor" in
    changed) landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/archlinux.gpg=attacker keyring' ;;
    revoked-added) landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/cachyos-revoked=0000000000000000000000000000000000000000' ;;
    link) landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/archlinux.gpg@>../../../../opt/nmap/decoy.gpg' 'opt/nmap/decoy.gpg=decoy' ;;
    keyrings-dir-link) landed_archive nmap 7.99-1 'usr/share/pacman/keyrings@>../../../opt/nmap/keyrings' 'opt/nmap/keyrings/archlinux.gpg=decoy' ;;
    blackarch-control) landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/blackarch.gpg=ordinary vendor keyring data'; expected=0 ;;
    esac
    landed_review "SELF anchor: unauthenticated $anchor of a base-vendor trust anchor" "$expected" "$LANDED_ARCHIVE"
done
landed_case vapt-landed-anchor-signed-update
no_stock_hooks
mkdir -p "$ROOT/usr/share/pacman/keyrings"
printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
landed_plan core archlinux-keyring 20260101-1
landed_archive archlinux-keyring 20260101-1 'usr/share/pacman/keyrings/archlinux.gpg=updated vendor keyring'
python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
printf 'fixture-sha256 %s\n' "$(sha256sum "$LANDED_ARCHIVE" | cut -d' ' -f1)" >"$LANDED_ARCHIVE.sig"
landed_review 'SELF anchor: a base-signed vendor keyring update (control)' 0 "$LANDED_ARCHIVE"

# --- SELF authority: the consumed policy path and extraction metadata ------
# SEC-SELF-POLICY-TARGET / SEC-SELF-ACCESS-METADATA consumer cases.
# Fixture data only: archives are rewritten with Python tarfile header fields
# (uid/gid/mode/PAX xattr) and never extracted; the audited module copy is the
# production metadata.py reading inert members. No payload, hook, key,
# package manager or native object executes.

AUTH_UMASK="$(umask)"
umask 022
AUTH_ALT_ID="$(python3 -c 'import os; print(65533 if os.getuid() == 65534 else 65534)')"

# auth_member ARCHIVE REL [mode=OCT] [uid=N] [gid=N] [xattr=NAME=VALUE] —
# rewrite one member's header in place, keeping its bytes/link target. Every
# other member is copied unchanged. Fails if REL is not a member.
auth_member() {
    python3 - "$@" <<'PY'
import io, sys, tarfile
from pathlib import Path
archive, rel, changes = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
with tarfile.open(archive, 'r:*') as old:
    members = [(m, old.extractfile(m).read() if m.isfile() else None) for m in old]
found, out = False, io.BytesIO()
with tarfile.open(fileobj=out, mode='w:gz', format=tarfile.PAX_FORMAT) as new:
    for member, data in members:
        if member.name.removeprefix('./').rstrip('/') == rel:
            found = True
            for change in changes:
                key, value = change.split('=', 1)
                if key == 'mode':
                    member.mode = int(value, 8)
                elif key == 'uid':
                    member.uid, member.uname = int(value), ''
                elif key == 'gid':
                    member.gid, member.gname = int(value), ''
                elif key == 'xattr':
                    name, text = value.split('=', 1)
                    member.pax_headers = dict(member.pax_headers, **{'SCHILY.xattr.' + name: text})
                else:
                    sys.exit('unknown member change ' + key)
        new.addfile(member, io.BytesIO(data) if data is not None else None)
if not found:
    sys.exit('fixture member missing: ' + rel)
archive.write_bytes(out.getvalue())
PY
}
# auth_publish ARCHIVE... — publish every built archive as its plan row's
# reviewed artifact (base signer for core) with a matching fixture signature.
auth_publish() {
    local archive
    python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
    for archive in "$@"; do
        printf 'fixture-sha256 %s\n' "$(sha256sum "$archive" | cut -d' ' -f1)" >"$archive.sig"
    done
}
# auth_facts META — the root-side authority-facts producer, run by the SAME
# module that audits, after all retained setup, into a caller-owned 0755
# stage the producer never creates. Sets AUTH_FACTS. Fixture visibility is
# noncryptographic caller-owned data; no default/hand-written facts exist.
auth_facts() {
    local stage="$ROOT/var/cache/haseen-vapt.authority"
    install -d -m 0755 "$stage"
    AUTH_FACTS="$stage/authority-facts"
    rm -f "$AUTH_FACTS"
    capture python3 "$1" authority-facts --out "$AUTH_FACTS" --root "$ROOT"
    assert_status 'authority facts producer completes over the fixture root' 0 "$STATUS"
}
# auth_audit LABEL EXPECTED META [--authority-facts FILE] ARCHIVE... — the
# real audit CLI of META with exactly the given facts argument.
auth_audit() {
    local label="$1" expected="$2" meta="$3" plan=()
    shift 3
    [[ -z ${LANDED_PLAN:-} ]] || plan=(--plan "$LANDED_PLAN")
    capture python3 "$meta" audit "$@" "${plan[@]}" --sudo-plugins "$LANDED_FACTS" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
# auth_review LABEL EXPECTED META ARCHIVE... — produce facts, then audit.
auth_review() {
    local label="$1" expected="$2" meta="$3"
    shift 3
    auth_facts "$meta"
    auth_audit "$label" "$expected" "$meta" --authority-facts "$AUTH_FACTS" "$@"
}

# --- SEC-SELF-POLICY-TARGET: a FILE-symlinked module consumes its PHYSICAL
# sibling policy. The logical layer is a real directory whose metadata.py is a
# file symlink to opt/haseen/layers/vapt/metadata.py; both directories carry
# files/*. Only the physical stock-hooks.tsv is what stock_policy reads.
AUTH_LOGICAL=usr/share/haseen/layers/vapt
AUTH_PHYSICAL=opt/haseen/layers/vapt
AUTH_NEXT=opt/haseen-next/layers/vapt
auth_policy_case() {
    local f
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    vapt_installed "haseen-vapt|1-1|https://example.org/haseen||||$AUTH_LOGICAL/metadata.py,$AUTH_LOGICAL/files/stock-hooks.tsv,$AUTH_LOGICAL/files/blackarch-signers.txt,$AUTH_PHYSICAL/metadata.py,$AUTH_PHYSICAL/files/stock-hooks.tsv,$AUTH_PHYSICAL/files/blackarch-signers.txt"
    vapt_stock
    no_stock_hooks
    # No stock hook remains, so the audit consumes the module's own physical
    # policy file rather than the fixture's restated-digest override.
    rm -f "$ROOT/var/lib/haseen/vapt/stock-hooks.tsv"
    unset LANDED_PLAN
    landed_facts
    mkdir -p "$ROOT/$AUTH_LOGICAL/files" "$ROOT/$AUTH_PHYSICAL/files"
    cp "$VAPT_LAYER/metadata.py" "$ROOT/$AUTH_PHYSICAL/metadata.py"
    for f in stock-hooks.tsv blackarch-signers.txt; do
        cp "$VAPT_LAYER/files/$f" "$ROOT/$AUTH_PHYSICAL/files/$f"
        cp "$VAPT_LAYER/files/$f" "$ROOT/$AUTH_LOGICAL/files/$f"
    done
    chmod 0644 "$ROOT/$AUTH_PHYSICAL/metadata.py" "$ROOT/$AUTH_PHYSICAL"/files/* "$ROOT/$AUTH_LOGICAL"/files/*
    ln -s ../../../../../$AUTH_PHYSICAL/metadata.py "$ROOT/$AUTH_LOGICAL/metadata.py"
    AUTH_META="$ROOT/$AUTH_LOGICAL/metadata.py"
    # Every member of the installed owner, byte-identical, link unchanged.
    AUTH_KEEP=("$AUTH_LOGICAL/metadata.py@>../../../../../$AUTH_PHYSICAL/metadata.py"
               "$AUTH_LOGICAL/files/stock-hooks.tsv<$ROOT/$AUTH_LOGICAL/files/stock-hooks.tsv"
               "$AUTH_LOGICAL/files/blackarch-signers.txt<$ROOT/$AUTH_LOGICAL/files/blackarch-signers.txt"
               "$AUTH_PHYSICAL/metadata.py<$ROOT/$AUTH_PHYSICAL/metadata.py"
               "$AUTH_PHYSICAL/files/stock-hooks.tsv<$ROOT/$AUTH_PHYSICAL/files/stock-hooks.tsv"
               "$AUTH_PHYSICAL/files/blackarch-signers.txt<$ROOT/$AUTH_PHYSICAL/files/blackarch-signers.txt")
}
AUTH_POLICY_CHANGE="$AUTH_PHYSICAL/files/stock-hooks.tsv=# changed physical stock hook policy"

auth_policy_case vapt-auth-policy-target-unrelated
landed_archive nmap 7.99-1
auth_review 'SELF-POLICY-TARGET unrelated package beside a file-symlinked module (control)' 0 "$AUTH_META" "$LANDED_ARCHIVE"

auth_policy_case vapt-auth-policy-target-identical
landed_archive haseen-vapt 2-1 "${AUTH_KEEP[@]}"
auth_review 'SELF-POLICY-TARGET identical upgrade of the file-symlinked layer (control)' 0 "$AUTH_META" "$LANDED_ARCHIVE"

# The logical sibling stays byte-identical; only the consumed physical
# sibling changes. A logical-only guard misses it.
auth_policy_case vapt-auth-policy-target-physical-changed
AUTH_KEEP[4]="$AUTH_POLICY_CHANGE"
landed_archive haseen-vapt 2-1 "${AUTH_KEEP[@]}"
auth_review 'SELF-POLICY-TARGET unauthenticated change to the consumed physical stock-hook policy is refused' 1 "$AUTH_META" "$LANDED_ARCHIVE"

auth_policy_case vapt-auth-policy-target-base-update
AUTH_KEEP[4]="$AUTH_POLICY_CHANGE"
landed_plan core haseen-vapt 2-1
landed_archive haseen-vapt 2-1 "${AUTH_KEEP[@]}"
auth_publish "$LANDED_ARCHIVE"
auth_review 'SELF-POLICY-TARGET base-authenticated physical policy update (control)' 0 "$AUTH_META" "$LANDED_ARCHIVE"

# Future view: an authenticated base upgrade retargets the module link to a
# new physical directory. That future module's sibling policy is the one the
# next audit consumes; a non-base companion in the same plan may not supply it.
for supplier in base companion; do
    auth_policy_case "vapt-auth-policy-target-redirect-$supplier"
    AUTH_KEEP[0]="$AUTH_LOGICAL/metadata.py@>../../../../../$AUTH_NEXT/metadata.py"
    AUTH_KEEP+=("$AUTH_NEXT/metadata.py<$ROOT/$AUTH_PHYSICAL/metadata.py")
    landed_plan core haseen-vapt 2-1 blackarch vapt-notes 1-1
    if [[ $supplier == base ]]; then
        AUTH_KEEP+=("$AUTH_NEXT/files/stock-hooks.tsv<$ROOT/$AUTH_PHYSICAL/files/stock-hooks.tsv")
        landed_archive haseen-vapt 2-1 "${AUTH_KEEP[@]}"
        AUTH_BASE="$LANDED_ARCHIVE"
        landed_archive vapt-notes 1-1 'usr/share/vapt-notes/readme=inert unrelated notes'
        AUTH_EXPECTED=0
    else
        landed_archive haseen-vapt 2-1 "${AUTH_KEEP[@]}"
        AUTH_BASE="$LANDED_ARCHIVE"
        landed_archive vapt-notes 1-1 "$AUTH_NEXT/files/stock-hooks.tsv=# companion-supplied future policy"
        AUTH_EXPECTED=1
    fi
    auth_publish "$AUTH_BASE" "$LANDED_ARCHIVE"
    auth_review "SELF-POLICY-TARGET base-redirected module with its future policy from the $supplier package" \
        "$AUTH_EXPECTED" "$AUTH_META" "$AUTH_BASE" "$LANDED_ARCHIVE"
done

# --- SEC-SELF-ACCESS-METADATA: identical bytes, changed write authority. ---
# Baseline: retained files are caller-owned 0644; landed_archive members carry
# the caller's uid/gid and the copied 0644 mode. Only the named header changes.
AUTH_SELF_REL=opt/haseen/layers/vapt
auth_self_case() {
    self_case "$1"
    chmod 0644 "$SELF_LAYER/metadata.py" "$SELF_LAYER/files/stock-hooks.tsv" "$SELF_LAYER/files/blackarch-signers.txt"
    landed_archive haseen-vapt 2-1 "$AUTH_SELF_REL/metadata.py<$SELF_LAYER/metadata.py" \
        "$AUTH_SELF_REL/files/stock-hooks.tsv<$SELF_LAYER/files/stock-hooks.tsv" \
        "$AUTH_SELF_REL/files/blackarch-signers.txt<$SELF_LAYER/files/blackarch-signers.txt" \
        'usr/share/haseen@>../../opt/haseen'
}

for authority in noop-rewrite parent-dir-0777 link-mode module-0666 module-0664 module-uid module-gid module-xattr policy-0666 signers-0666 link-uid; do
    auth_self_case "vapt-auth-self-$authority"
    AUTH_EXPECTED=1
    case "$authority" in
    noop-rewrite) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" mode=0644; AUTH_EXPECTED=0 ;;
    # libalpm does not reapply metadata to an already-existing directory.
    parent-dir-0777) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL" mode=0777; AUTH_EXPECTED=0 ;;
    # Linux applies no mode to a symlink; its target and owner are unchanged.
    link-mode) auth_member "$LANDED_ARCHIVE" usr/share/haseen mode=0700; AUTH_EXPECTED=0 ;;
    module-0666) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" mode=0666 ;;
    module-0664) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" mode=0664 ;;
    module-uid) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" "uid=$AUTH_ALT_ID" ;;
    module-gid) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" "gid=$AUTH_ALT_ID" ;;
    module-xattr) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" xattr=user.haseen-fixture=inert ;;
    policy-0666) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/files/stock-hooks.tsv" mode=0666 ;;
    signers-0666) auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/files/blackarch-signers.txt" mode=0666 ;;
    # Same target, but the guarded link hop is handed to another owner.
    link-uid) auth_member "$LANDED_ARCHIVE" usr/share/haseen "uid=$AUTH_ALT_ID" ;;
    esac
    auth_review "SELF-ACCESS byte-identical program upgrade with $authority authority" \
        "$AUTH_EXPECTED" "$SELF_META" "$LANDED_ARCHIVE"
done

# A base-authenticated vendor update keeps its deliberate trust exemption.
auth_self_case vapt-auth-self-base-update
landed_plan core haseen-vapt 2-1
auth_member "$LANDED_ARCHIVE" "$AUTH_SELF_REL/metadata.py" mode=0666
auth_publish "$LANDED_ARCHIVE"
auth_review 'SELF-ACCESS base-authenticated program update with changed authority (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

# Trust anchors: identical retained keyring bytes from an unauthenticated
# package may not change who can write the anchor.
for authority in noop-rewrite mode-0666 uid xattr; do
    landed_case "vapt-auth-anchor-$authority"
    no_stock_hooks
    mkdir -p "$ROOT/usr/share/pacman/keyrings"
    printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
    chmod 0644 "$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
    landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/archlinux.gpg=retained vendor keyring'
    AUTH_EXPECTED=1
    case "$authority" in
    noop-rewrite) auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg mode=0644; AUTH_EXPECTED=0 ;;
    mode-0666) auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg mode=0666 ;;
    uid) auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg "uid=$AUTH_ALT_ID" ;;
    xattr) auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg xattr=user.haseen-fixture=inert ;;
    esac
    auth_review "SELF-ACCESS byte-identical base-vendor anchor with $authority authority" \
        "$AUTH_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done
landed_case vapt-auth-anchor-base-update
no_stock_hooks
mkdir -p "$ROOT/usr/share/pacman/keyrings"
printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
chmod 0644 "$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
landed_plan core archlinux-keyring 20260101-1
landed_archive archlinux-keyring 20260101-1 'usr/share/pacman/keyrings/archlinux.gpg=retained vendor keyring'
auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg mode=0666
auth_publish "$LANDED_ARCHIVE"
auth_review 'SELF-ACCESS base-signed keyring update with changed authority (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"

# Unprotected ordinary data keeps whatever authority its package declares.
landed_case vapt-auth-ordinary-member
no_stock_hooks
landed_archive nmap 7.99-1 'usr/share/nmap/notes.txt=inert ordinary data'
auth_member "$LANDED_ARCHIVE" usr/share/nmap/notes.txt mode=0666 "uid=$AUTH_ALT_ID" "gid=$AUTH_ALT_ID" xattr=user.haseen-fixture=inert
auth_review 'SELF-ACCESS unprotected ordinary member with arbitrary authority (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"

# --- Root authority facts bridge. Facts are required only to grant the
# non-base identical exemption; unrelated packages and base-authenticated
# updates never need them. Each negative replaces the identical-upgrade
# control's facts with exactly one defect; nothing is hand-written as valid.
for facts in present omitted group-writable symlinked malformed; do
    auth_self_case "vapt-auth-facts-identical-$facts"
    auth_facts "$SELF_META"
    AUTH_EXPECTED=1
    AUTH_FACTS_ARG=(--authority-facts "$AUTH_FACTS")
    case "$facts" in
    present) AUTH_EXPECTED=0 ;;
    omitted) AUTH_FACTS_ARG=() ;;
    group-writable) chmod 0664 "$AUTH_FACTS" ;;
    symlinked)
        mv "$AUTH_FACTS" "$AUTH_FACTS.real"
        ln -s authority-facts.real "$AUTH_FACTS"
        ;;
    malformed) printf 'not\ta\tvalid row\n' >>"$AUTH_FACTS" ;;
    esac
    auth_audit "AUTHORITY-FACTS identical non-base program upgrade with $facts facts" \
        "$AUTH_EXPECTED" "$SELF_META" "${AUTH_FACTS_ARG[@]}" "$LANDED_ARCHIVE"
done

# The exemption is the only consumer: without any facts file these remain
# allowed, so a missing producer cannot be masked by blanket refusal either.
auth_self_case vapt-auth-facts-not-needed-unrelated
landed_archive nmap 7.99-1
auth_audit 'AUTHORITY-FACTS unrelated package needs no facts (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"
auth_self_case vapt-auth-facts-not-needed-base-update
landed_plan core haseen-vapt 2-1
auth_publish "$LANDED_ARCHIVE"
auth_audit 'AUTHORITY-FACTS base-authenticated update needs no facts (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

# A guarded element that did not exist when the facts were produced has no
# row; its later identical replacement is unverified. Producing after the
# anchor exists is the noop-rewrite anchor control above.
landed_case vapt-auth-facts-missing-row
no_stock_hooks
auth_facts "$VAPT_META"
mkdir -p "$ROOT/usr/share/pacman/keyrings"
printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
chmod 0644 "$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
landed_archive nmap 7.99-1 'usr/share/pacman/keyrings/archlinux.gpg=retained vendor keyring'
auth_audit 'AUTHORITY-FACTS identical anchor replacement without a facts row is refused' 1 \
    "$VAPT_META" --authority-facts "$AUTH_FACTS" "$LANDED_ARCHIVE"

umask "$AUTH_UMASK"
unset AUTH_UMASK AUTH_ALT_ID AUTH_META AUTH_KEEP AUTH_BASE AUTH_EXPECTED AUTH_POLICY_CHANGE AUTH_FACTS AUTH_FACTS_ARG

# --- SELF retained ACL/attributes: preserved authority on reinstall ------
# SEC-SELF-RETAINED-ACL consumer cases (reuse the auth_* helpers above).
# Fixture data only: POSIX ACLs are set with os.setxattr on scratch files
# inside $ROOT; archives are built, never extracted; no payload executes; no
# host user/group is created (the named group is a bare numeric gid).

ACL_UMASK="$(umask)"
umask 022

# acl_set PATH access|default — write a valid Linux POSIX ACL xattr.
#   access : user::rw- group::r-- group:NAMED:rw- mask::rw- other::---  (0660)
#   default: user::rwx group::r-x group:NAMED:rwx mask::rwx other::r-x
# Exit 3 when the filesystem has no ACL support; any other failure, or an
# access ACL whose resulting mode is not 0660, is a fixture error (exit 1).
acl_set() {
    python3 - "$1" "$2" <<'PY'
import errno, os, stat, struct, sys
path, kind = sys.argv[1], sys.argv[2]
# The named group differs from the caller's own (deterministic, no host user).
named = 65533 if os.getgid() == 65534 else 65534
undefined = 0xFFFFFFFF
if kind == 'access':
    entries = [(0x01, 6, undefined), (0x04, 4, undefined), (0x08, 6, named), (0x10, 6, undefined), (0x20, 0, undefined)]
    name = 'system.posix_acl_access'
else:
    entries = [(0x01, 7, undefined), (0x04, 5, undefined), (0x08, 7, named), (0x10, 7, undefined), (0x20, 5, undefined)]
    name = 'system.posix_acl_default'
value = struct.pack('<I', 2) + b''.join(struct.pack('<HHI', *entry) for entry in entries)
try:
    os.setxattr(path, name, value, follow_symlinks=False)
except OSError as error:
    if error.errno in (errno.EOPNOTSUPP, errno.ENOTSUP):
        sys.exit(3)
    raise
if os.getxattr(path, name, follow_symlinks=False) != value:
    sys.exit('ACL not retained on ' + path)
if kind == 'access' and stat.S_IMODE(os.lstat(path).st_mode) != 0o660:
    sys.exit('access ACL did not produce mode 0660 on ' + path)
PY
}
# acl_supported — probe on the sandbox filesystem the fixture root lives on.
acl_supported() {
    local probe status
    vapt_sandbox vapt-acl-probe
    probe="$SANDBOX/acl-probe"
    : >"$probe"
    acl_set "$probe" access
    status=$?
    rm -rf "$SANDBOX"
    case "$status" in
    0) return 0 ;;
    3) return 1 ;;
    *) _fail "SELF-RETAINED-ACL fixture ACL probe failed unexpectedly (status $status)"; return 1 ;;
    esac
}
# acl_apply PATH access|default — set it, failing the test (never skipping)
# once support was established.
acl_apply() {
    acl_set "$1" "$2" || _fail "SELF-RETAINED-ACL could not set $2 ACL on fixture ${1#"$ROOT"/}"
}

# The self layout with one more file the upgraded package owns but which is
# not a protected program/policy path: a retained ACL there is unmodeled data.
ACL_LAYER=opt/haseen/layers/vapt
acl_self_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    vapt_installed "haseen-vapt|1-1|https://example.org/haseen||||usr/share/haseen,$ACL_LAYER/metadata.py,$ACL_LAYER/files/stock-hooks.tsv,$ACL_LAYER/files/blackarch-signers.txt,$ACL_LAYER/notes.txt"
    vapt_stock
    no_stock_hooks
    unset LANDED_PLAN
    landed_facts
    mkdir -p "$ROOT/opt/haseen/layers"
    cp -R "$VAPT_LAYER" "$ROOT/$ACL_LAYER"
    printf 'inert package-owned notes\n' >"$ROOT/$ACL_LAYER/notes.txt"
    ln -s ../../opt/haseen "$ROOT/usr/share/haseen"
    SELF_META="$ROOT/usr/share/haseen/layers/vapt/metadata.py"
    SELF_LAYER="$ROOT/$ACL_LAYER"
    chmod 0660 "$SELF_LAYER/metadata.py" "$SELF_LAYER/files/stock-hooks.tsv" \
        "$SELF_LAYER/files/blackarch-signers.txt" "$SELF_LAYER/notes.txt"
}
# acl_self_archive — byte-identical haseen-vapt 2-1, every member mode 0660,
# caller uid/gid (as built), no xattrs.
acl_self_archive() {
    local rel
    landed_archive haseen-vapt 2-1 "$ACL_LAYER/metadata.py<$SELF_LAYER/metadata.py" \
        "$ACL_LAYER/files/stock-hooks.tsv<$SELF_LAYER/files/stock-hooks.tsv" \
        "$ACL_LAYER/files/blackarch-signers.txt<$SELF_LAYER/files/blackarch-signers.txt" \
        "$ACL_LAYER/notes.txt<$SELF_LAYER/notes.txt" 'usr/share/haseen@>../../opt/haseen'
    for rel in metadata.py files/stock-hooks.tsv files/blackarch-signers.txt notes.txt; do
        auth_member "$LANDED_ARCHIVE" "$ACL_LAYER/$rel" mode=0660
    done
}
acl_anchor_case() {
    landed_case "$1"
    no_stock_hooks
    mkdir -p "$ROOT/usr/share/pacman/keyrings"
    printf 'retained vendor keyring\n' >"$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
    chmod 0660 "$ROOT/usr/share/pacman/keyrings/archlinux.gpg"
}
acl_anchor_archive() { # NAME VERSION
    landed_archive "$1" "$2" 'usr/share/pacman/keyrings/archlinux.gpg=retained vendor keyring'
    auth_member "$LANDED_ARCHIVE" usr/share/pacman/keyrings/archlinux.gpg mode=0660
}

if ! acl_supported; then
    echo "  (note: the test filesystem rejects POSIX ACL xattrs; SELF-RETAINED-ACL cases were skipped)"
else
    # --- Retained access ACL on protected program/policy files. -------------
    # plain: same 0660 mode without an ACL (the ordinary identical control).
    for retained in plain module policy signers; do
        acl_self_case "vapt-acl-self-$retained"
        AUTH_EXPECTED=1
        case "$retained" in
        plain) AUTH_EXPECTED=0 ;;
        module) acl_apply "$SELF_LAYER/metadata.py" access ;;
        policy) acl_apply "$SELF_LAYER/files/stock-hooks.tsv" access ;;
        signers) acl_apply "$SELF_LAYER/files/blackarch-signers.txt" access ;;
        esac
        acl_self_archive
        auth_review "SELF-RETAINED-ACL identical non-base replacement of a $retained retained file" \
            "$AUTH_EXPECTED" "$SELF_META" "$LANDED_ARCHIVE"
    done

    # Facts produced before the ACL appeared are stale: the audit's own
    # no-follow attribute check on the replaced element still refuses.
    acl_self_case vapt-acl-self-stale-facts
    auth_facts "$SELF_META"
    acl_apply "$SELF_LAYER/metadata.py" access
    acl_self_archive
    auth_audit 'SELF-RETAINED-ACL ACL added after facts were produced is refused' 1 \
        "$SELF_META" --authority-facts "$AUTH_FACTS" "$LANDED_ARCHIVE"

    # Unmodeled ACL on an owned but unprotected file stays ordinary data.
    acl_self_case vapt-acl-self-ordinary-owned
    acl_apply "$SELF_LAYER/notes.txt" access
    acl_self_archive
    auth_review 'SELF-RETAINED-ACL ACL on an unprotected owned file (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

    # Nothing replaces the ACL-restricted program: an unrelated package passes.
    acl_self_case vapt-acl-self-unrelated
    acl_apply "$SELF_LAYER/metadata.py" access
    landed_archive nmap 7.99-1
    auth_review 'SELF-RETAINED-ACL retained ACL beside an unrelated package (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

    # A retained non-ACL user xattr can only be dropped by the replacement,
    # which never widens write authority (owner-declared boundary).
    acl_self_case vapt-acl-self-retained-user-xattr
    if python3 -c 'import os, sys; os.setxattr(sys.argv[1], "user.haseen-fixture", b"inert", follow_symlinks=False)' \
        "$SELF_LAYER/metadata.py" 2>/dev/null; then
        acl_self_archive
        auth_review 'SELF-RETAINED-ACL retained non-ACL user xattr under an identical replacement (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"
    else
        echo "  (note: the test filesystem rejects user xattrs; the retained user-xattr control was skipped)"
    fi

    # A base-authenticated vendor update keeps its deliberate exemption.
    acl_self_case vapt-acl-self-base-update
    acl_apply "$SELF_LAYER/metadata.py" access
    landed_plan core haseen-vapt 2-1
    acl_self_archive
    auth_publish "$LANDED_ARCHIVE"
    auth_review 'SELF-RETAINED-ACL base-authenticated update over a retained ACL (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

    # --- Inherited default ACL: the recreated inode gains a named writer. ---
    for change in identical unrelated base-update; do
        acl_self_case "vapt-acl-self-parent-default-$change"
        acl_apply "$SELF_LAYER" default
        AUTH_EXPECTED=0
        case "$change" in
        identical) acl_self_archive; AUTH_EXPECTED=1 ;;
        unrelated) landed_archive nmap 7.99-1 ;;
        base-update) landed_plan core haseen-vapt 2-1; acl_self_archive; auth_publish "$LANDED_ARCHIVE" ;;
        esac
        auth_review "SELF-RETAINED-ACL parent default ACL with $change transaction" \
            "$AUTH_EXPECTED" "$SELF_META" "$LANDED_ARCHIVE"
    done

    # A symlink inherits no default ACL (symlink(7), acl(5)): the identical
    # guarded usr/share/haseen link hop under a default-ACL parent is unchanged
    # authority. Its regular-file siblings live under an ACL-free directory.
    acl_self_case vapt-acl-self-link-parent-default
    acl_apply "$ROOT/usr/share" default
    acl_self_archive
    auth_review 'SELF-RETAINED-ACL identical symlink hop under a default-ACL parent (control)' 0 "$SELF_META" "$LANDED_ARCHIVE"

    # --- Retained access ACL on a base-vendor trust anchor. ------------------
    for retained in plain acl; do
        acl_anchor_case "vapt-acl-anchor-$retained"
        AUTH_EXPECTED=0
        [[ $retained == plain ]] || { acl_apply "$ROOT/usr/share/pacman/keyrings/archlinux.gpg" access; AUTH_EXPECTED=1; }
        acl_anchor_archive nmap 7.99-1
        auth_review "SELF-RETAINED-ACL identical non-base anchor over a $retained retained keyring" \
            "$AUTH_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
    done
    acl_anchor_case vapt-acl-anchor-base-update
    acl_apply "$ROOT/usr/share/pacman/keyrings/archlinux.gpg" access
    landed_plan core archlinux-keyring 20260101-1
    acl_anchor_archive archlinux-keyring 20260101-1
    auth_publish "$LANDED_ARCHIVE"
    auth_review 'SELF-RETAINED-ACL base-signed keyring update over a retained ACL (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"
fi

umask "$ACL_UMASK"
unset ACL_UMASK AUTH_EXPECTED

# --- Root runtime blockers: interpreter startup layout and hardlinks -----
# CPython -I -S startup layout selectors and PAX data-bearing hardlinks onto
# protected inodes (reuses the auth_* helpers above).
# Every member is inert text or a copied inert fixture ELF; archives are only
# read by the audit's libarchive decoder, never extracted. No interpreter,
# import, hook, payload, tool or key operation executes.
RB_UMASK="$(umask)"
umask 022

# rb_add ARCHIVE NAME KIND [ARG] [mode=OCT] — append one member, keeping all
# others. KIND: file TEXT | link TARGET | hardlink LINKNAME [DATA]. A hardlink
# with DATA is a PAX hardlink entry whose body libarchive's disk writer would
# write through the linked inode; a PAX header is forced so readers keep it.
rb_add() {
    python3 - "$@" <<'PY'
import io, sys, tarfile
from pathlib import Path
archive, name, kind = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
rest = sys.argv[4:]
mode = 0o644
if rest and rest[-1].startswith('mode='):
    mode = int(rest.pop()[5:], 8)
with tarfile.open(archive, 'r:*') as old:
    members = [(m, old.extractfile(m).read() if m.isfile() else None) for m in old]
out = io.BytesIO()
with tarfile.open(fileobj=out, mode='w:gz', format=tarfile.PAX_FORMAT) as new:
    for member, data in members:
        if member.name.removeprefix('./') != name:
            new.addfile(member, io.BytesIO(data) if data is not None else None)
    info = tarfile.TarInfo(name)
    info.mode = mode
    body = None
    if kind == 'file':
        body = (rest[0] + '\n').encode()
    elif kind == 'link':
        info.type, info.linkname = tarfile.SYMTYPE, rest[0]
    elif kind == 'hardlink':
        info.type, info.linkname = tarfile.LNKTYPE, rest[0]
        info.pax_headers = {'comment': 'inert fixture hardlink'}
        if len(rest) > 1 and rest[1]:
            body = (rest[1] + '\n').encode()
    else:
        sys.exit('unknown member kind ' + kind)
    info.size = len(body) if body is not None else 0
    new.addfile(info, io.BytesIO(body) if body is not None else None)
archive.write_bytes(out.getvalue())
PY
}

# --- CPython -I -S startup selectors beside the root interpreter. -----------
rb_python_case() {
    landed_case "$1"
    no_stock_hooks
    vapt_stock_python
}
# rb_python_member REL SOURCE|link:TARGET — add one member to the base-signed
# python reference archive and install exactly it (base-proven retained bytes).
rb_python_member() {
    python3 - "$ROOT" "$1" "$2" <<'PY'
import gzip, hashlib, io, sys, tarfile
from pathlib import Path
root, rel, source = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
archive = root / 'var/cache/pacman/pkg/python-3.14.0-1-x86_64.pkg.tar.gz'
link = source[5:] if source.startswith('link:') else None
data = None if link else Path(source).read_bytes()
out = io.BytesIO()
with tarfile.open(archive, 'r:*') as old, tarfile.open(fileobj=out, mode='w:gz') as new:
    for member in old:
        if member.name.removeprefix('./').rstrip('/') != rel:
            new.addfile(member, old.extractfile(member) if member.isfile() else None)
    info = tarfile.TarInfo(rel)
    info.mode = 0o644
    if link:
        info.type, info.linkname = tarfile.SYMTYPE, link
        new.addfile(info)
    else:
        info.size = len(data)
        new.addfile(info, io.BytesIO(data))
archive.write_bytes(out.getvalue())
target = root / rel
target.parent.mkdir(parents=True, exist_ok=True)
target.unlink(missing_ok=True)
entry = root / 'var/lib/pacman/local/python-3.14.0-1'
if link:
    target.symlink_to(link)
    row = './' + rel + ' type=link link=' + link
else:
    target.write_bytes(data)
    target.chmod(0o644)
    row = './' + rel + ' type=file mode=644 sha256digest=' + hashlib.sha256(data).hexdigest()
files = [r for r in (entry / 'files').read_text().splitlines() if r and r != '%FILES%' and r != rel]
(entry / 'files').write_text('%FILES%\n' + '\n'.join(files + [rel]) + '\n\n')
rows = [r for r in gzip.open(entry / 'mtree', 'rt').read().splitlines() if not r.startswith('./' + rel + ' ')]
with gzip.open(entry / 'mtree', 'wt') as stream:
    stream.write('\n'.join(rows + [row]) + '\n')
PY
    python3 "$VAPT_FIXTURE_DRIVER" digests "$ROOT/var/cache/pacman/pkg"
    auth_publish "$ROOT/var/cache/pacman/pkg/python-3.14.0-1-x86_64.pkg.tar.gz"
}
# rb_python_update [MEMBER-SPEC...] — base-signed python 3.14.0-2 (extra)
# with the retained stock members plus the given landed_archive specs.
rb_python_update() {
    landed_plan extra python 3.14.0-2 "${RB_EXTRA_PLAN[@]}"
    landed_archive python 3.14.0-2 "usr/bin/python3.14<$ROOT/usr/bin/python3.14" 'usr/bin/python3@>python3.14' \
        "usr/lib/python3.14/ctypes/__init__.py<$ROOT/usr/lib/python3.14/ctypes/__init__.py" \
        "usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so<$ROOT/usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so" "$@"
}
# rb_lower_owner NAME REL TEXT — installed non-base (chaotic-aur) owner of REL.
rb_lower_owner() {
    vapt_conf_add $'[chaotic-aur]\nServer = https://mirror.example/chaotic-aur/$arch'
    mkdir -p "$ROOT/$(dirname "$2")"
    printf '%s\n' "$3" >"$ROOT/$2"
    chmod 0644 "$ROOT/$2"
    python3 - "$ROOT" "$1" "$2" <<'PY'
import gzip, hashlib, sys
from pathlib import Path
root, name, rel = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
entry = root / 'var/lib/pacman/local' / (name + '-1-1')
entry.mkdir()
(entry / 'desc').write_text('%NAME%\n' + name + '\n\n%VERSION%\n1-1\n\n%URL%\nhttps://example.org/' + name + '\n\n')
(entry / 'files').write_text('%FILES%\n' + rel + '\n\n')
(entry / 'depends').write_text('%DEPENDS%\n\n%PROVIDES%\n\n%CONFLICTS%\n\n%REPLACES%\n\n')
with gzip.open(entry / 'mtree', 'wt') as stream:
    stream.write('#mtree\n./' + rel + ' type=file mode=644 sha256digest='
                 + hashlib.sha256((root / rel).read_bytes()).hexdigest() + '\n')
PY
}
RB_EXTRA_PLAN=()
# rb_libpython — the root interpreter NEEDs a base-proven libpython at
# usr/lib (the start directory for libpython-relative selectors/landmarks).
rb_libpython() {
    vapt_elf "$SANDBOX/python-exe" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 needed=libpython3.14.so.1.0,libc.so.6
    rb_python_member usr/bin/python3.14 "$SANDBOX/python-exe"
    vapt_elf "$SANDBOX/libpython" soname=libpython3.14.so.1.0 needed=libc.so.6
    rb_python_member usr/lib/libpython3.14.so.1.0 "$SANDBOX/libpython"
}
# Incoming non-base selectors (unplanned nmap) that CPython's path calculation
# consults even in isolated mode, including the landmarks searched from the
# shared-library and executable directories; unrelated locations are data.
for selector in pth-versioned pth-unversioned pth-libpython pyvenv-bindir pyvenv-prefix builddir builddir-alone \
    pyvenv-link zip-libdir stdlib-libdir stdlib-pyc-libdir dynload-libdir zip-bindir unrelated-pth unrelated-pyvenv \
    static-libpython-pth other-version-landmark root-lib-dir; do
    rb_python_case "vapt-rb-python-selector-$selector"
    case "$selector" in
    pth-libpython | zip-libdir | stdlib-libdir | stdlib-pyc-libdir | dynload-libdir | other-version-landmark) rb_libpython ;;
    esac
    landed_archive nmap 7.99-1
    RB_EXPECTED=1
    case "$selector" in
    pth-versioned) rb_add "$LANDED_ARCHIVE" usr/bin/python3.14._pth file 'usr/share/nmap' ;;
    pth-unversioned) rb_add "$LANDED_ARCHIVE" usr/bin/python3._pth file 'usr/share/nmap' ;;
    pyvenv-bindir) rb_add "$LANDED_ARCHIVE" usr/bin/pyvenv.cfg file 'home = /usr/share/nmap' ;;
    pyvenv-prefix) rb_add "$LANDED_ARCHIVE" usr/pyvenv.cfg file 'home = /usr/share/nmap' ;;
    pth-libpython) rb_add "$LANDED_ARCHIVE" usr/lib/libpython3.14.so.1.0._pth file 'usr/share/nmap' ;;
    builddir-alone) rb_add "$LANDED_ARCHIVE" usr/bin/pybuilddir.txt file 'nmap-build' ;;
    zip-libdir) rb_add "$LANDED_ARCHIVE" usr/lib/lib/python314.zip file 'inert fixture zip stand-in' ;;
    stdlib-libdir) rb_add "$LANDED_ARCHIVE" usr/lib/lib/python3.14/os.py file '# inert fixture landmark, never imported' ;;
    stdlib-pyc-libdir) rb_add "$LANDED_ARCHIVE" usr/lib/lib/python3.14/os.pyc file 'inert fixture bytecode stand-in' ;;
    dynload-libdir) rb_add "$LANDED_ARCHIVE" usr/lib/lib/python3.14/lib-dynload/README file 'inert fixture directory landmark' ;;
    # Static interpreter (stock ELF, no libpython NEEDED): an unrelated
    # library's selector is unused.
    static-libpython-pth)
        rb_add "$LANDED_ARCHIVE" usr/lib/libpython3.14.so.1.0 file 'inert unrelated library stand-in'
        rb_add "$LANDED_ARCHIVE" usr/lib/libpython3.14.so.1.0._pth file 'usr/share/nmap'
        RB_EXPECTED=0
        ;;
    # Landmarks are version-specific.
    other-version-landmark) rb_add "$LANDED_ARCHIVE" usr/lib/lib/python3.13/os.py file '# inert other-version file'; RB_EXPECTED=0 ;;
    # A real (non-usrmerge) /lib directory holding a stdlib landmark.
    root-lib-dir)
        rm -f "$ROOT/lib"
        mkdir -p "$ROOT/lib/python3.14"
        printf '# inert fixture landmark, never imported\n' >"$ROOT/lib/python3.14/os.py"
        ;;
    zip-bindir) rb_add "$LANDED_ARCHIVE" usr/bin/lib/python314.zip file 'inert fixture zip stand-in' ;;
    builddir)
        rb_add "$LANDED_ARCHIVE" usr/bin/Modules/Setup.local file '# inert fixture build landmark'
        rb_add "$LANDED_ARCHIVE" usr/bin/pybuilddir.txt file 'nmap-build'
        ;;
    pyvenv-link)
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/cfg file 'home = /usr/share/nmap'
        rb_add "$LANDED_ARCHIVE" usr/bin/pyvenv.cfg link ../share/nmap/cfg
        ;;
    unrelated-pth) rb_add "$LANDED_ARCHIVE" usr/share/nmap/python3.14._pth file 'usr/share/nmap'; RB_EXPECTED=0 ;;
    unrelated-pyvenv) rb_add "$LANDED_ARCHIVE" usr/share/nmap/pyvenv.cfg file 'home = /usr/share/nmap'; RB_EXPECTED=0 ;;
    esac
    auth_review "PY-STARTUP unauthenticated $selector selector for the root interpreter" \
        "$RB_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# Startup selectors make the import layout unmodeled: whether retained,
# base-shipped or removed, any current/future selector for the root
# interpreter is a manual refusal. Their absence is the supported layout.

# A retained stdlib landmark below the resolved libpython's directory, and a
# root interpreter with its own RUNPATH, are both unmodeled layouts.
for layout in libdir-zip-landmark runpath; do
    rb_python_case "vapt-rb-python-retained-$layout"
    if [[ $layout == libdir-zip-landmark ]]; then
        rb_libpython
        mkdir -p "$ROOT/usr/lib/lib"
        printf 'inert fixture zip stand-in\n' >"$ROOT/usr/lib/lib/python314.zip"
    else
        vapt_elf "$SANDBOX/python-exe" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 needed=libc.so.6 runpath=/usr/lib/vapt-python
        rb_python_member usr/bin/python3.14 "$SANDBOX/python-exe"
    fi
    landed_archive nmap 7.99-1
    auth_review "PY-STARTUP retained $layout layout of the root interpreter" 1 "$VAPT_META" "$LANDED_ARCHIVE"
done

# Retained selectors with an unrelated transaction.
for retained in pyvenv pth-empty-root; do
    rb_python_case "vapt-rb-python-retained-$retained"
    mkdir -p "$ROOT/usr/share/vaptlib"
    if [[ $retained == pyvenv ]]; then
        printf 'home = /usr/share/nmap\n' >"$ROOT/usr/bin/pyvenv.cfg"
        landed_archive nmap 7.99-1
    else
        # The retained ._pth selects an empty ordinary directory; the incoming
        # non-base module there would be imported first (never imported here).
        printf '/usr/share/vaptlib\n/usr/lib/python3.14\n/usr/lib/python3.14/lib-dynload\n' >"$ROOT/usr/bin/python3._pth"
        landed_archive nmap 7.99-1 'usr/share/vaptlib/argparse.py=# inert fixture module text, never imported'
    fi
    auth_review "PY-STARTUP retained $retained selector leaves the root import layout unmodeled" 1 "$VAPT_META" "$LANDED_ARCHIVE"
done

# Without any selector the same off-stdlib module is ordinary package data.
rb_python_case vapt-rb-python-offstdlib-control
landed_archive nmap 7.99-1 'usr/share/vaptlib/argparse.py=# inert fixture module text, never imported'
auth_review 'PY-STARTUP off-stdlib module without any selector (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"

# Base python update: selector-free is supported; a shipped selector is not,
# alone or selecting a directory a non-base package in the same plan fills.
for base in plain selector selector-with-companion; do
    rb_python_case "vapt-rb-python-base-$base"
    RB_EXTRA_PLAN=()
    case "$base" in
    plain) rb_python_update; RB_ARCHIVES=("$LANDED_ARCHIVE"); RB_EXPECTED=0 ;;
    selector) rb_python_update 'usr/bin/python3.14._pth=python314.zip'; RB_ARCHIVES=("$LANDED_ARCHIVE"); RB_EXPECTED=1 ;;
    selector-with-companion)
        RB_EXTRA_PLAN=(blackarch vapt-notes 1-1)
        rb_python_update $'usr/bin/python3.14._pth=/usr/share/vaptlib\n/usr/lib/python3.14\n/usr/lib/python3.14/lib-dynload'
        RB_ARCHIVES=("$LANDED_ARCHIVE")
        landed_archive vapt-notes 1-1 'usr/share/vaptlib/argparse.py=# inert fixture module text, never imported'
        RB_ARCHIVES+=("$LANDED_ARCHIVE")
        RB_EXPECTED=1
        ;;
    esac
    auth_publish "${RB_ARCHIVES[@]}"
    auth_review "PY-STARTUP base python update ($base)" "$RB_EXPECTED" "$VAPT_META" "${RB_ARCHIVES[@]}"
done
RB_EXTRA_PLAN=()

# Removing a retained selector still leaves the transaction's current view
# with an unmodeled layout.
rb_python_case vapt-rb-python-selector-removed
rb_lower_owner vapt-runtime usr/bin/python3._pth '/usr/share/vaptlib'
landed_plan chaotic-aur vapt-runtime 2-1
landed_archive vapt-runtime 2-1 'usr/share/vapt-runtime/readme=inert replacement data'
auth_publish "$LANDED_ARCHIVE"
auth_review 'PY-STARTUP non-base removal of a retained interpreter selector' 1 "$VAPT_META" "$LANDED_ARCHIVE"

# libpython: the root interpreter NEEDs libpython3.14.so.1.0, which a retained
# ld.so.cache resolves to a base-proven glibc-hwcaps object. A ._pth beside
# the physical selected library, or beside another loader candidate, is a
# startup selector. Without one the base-proven layout is supported.
for libsel in none selected-physical other-candidate; do
    rb_python_case "vapt-rb-python-libpython-$libsel"
    vapt_elf "$SANDBOX/python-exe" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 needed=libpython3.14.so.1.0,libc.so.6
    rb_python_member usr/bin/python3.14 "$SANDBOX/python-exe"
    vapt_elf "$SANDBOX/libpython" soname=libpython3.14.so.1.0 needed=libc.so.6
    rb_python_member usr/lib/glibc-hwcaps/x86-64-v3/libpython3.14.so.1.0 "$SANDBOX/libpython"
    rb_python_member usr/lib/libpython3.14.so.1.0 "$SANDBOX/libpython"
    vapt_ldcache "$ROOT/etc/ld.so.cache" libpython3.14.so.1.0=/usr/lib/glibc-hwcaps/x86-64-v3/libpython3.14.so.1.0
    RB_EXPECTED=1
    case "$libsel" in
    none) landed_archive nmap 7.99-1; RB_EXPECTED=0 ;;
    selected-physical) landed_archive nmap 7.99-1 'usr/lib/glibc-hwcaps/x86-64-v3/libpython3.14.so.1.0._pth=/usr/share/vaptlib' ;;
    other-candidate) landed_archive nmap 7.99-1 'usr/lib/libpython3.14.so.1.0._pth=/usr/share/vaptlib' ;;
    esac
    auth_review "PY-STARTUP libpython selector ($libsel)" "$RB_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# --- PAX hardlinks. Only a size-0 link to an EARLIER regular member of the
# same archive, with identical mode/uid/gid and no xattrs, is ordinary.
RB_ANCHOR=usr/share/pacman/keyrings/archlinux.gpg
rb_anchor_case() {
    landed_case "$1"
    no_stock_hooks
    mkdir -p "$ROOT/usr/share/pacman/keyrings" "$ROOT/usr/share/doc"
    printf 'retained vendor keyring\n' >"$ROOT/$RB_ANCHOR"
    printf 'retained unowned documentation\n' >"$ROOT/usr/share/doc/fixture.txt"
    chmod 0644 "$ROOT/$RB_ANCHOR" "$ROOT/usr/share/doc/fixture.txt"
}
for link in data-anchor zero-anchor-mode zero-anchor-same data-unprotected in-archive-pair \
    in-archive-reversed in-archive-mode in-archive-data; do
    rb_anchor_case "vapt-rb-hardlink-$link"
    landed_archive nmap 7.99-1
    RB_EXPECTED=1
    case "$link" in
    data-anchor) rb_add "$LANDED_ARCHIVE" usr/share/nmap/notes.txt hardlink "$RB_ANCHOR" 'attacker keyring bytes' ;;
    zero-anchor-mode) rb_add "$LANDED_ARCHIVE" usr/share/nmap/notes.txt hardlink "$RB_ANCHOR" '' mode=0666 ;;
    zero-anchor-same) rb_add "$LANDED_ARCHIVE" usr/share/nmap/notes.txt hardlink "$RB_ANCHOR" '' ;;
    data-unprotected) rb_add "$LANDED_ARCHIVE" usr/share/nmap/notes.txt hardlink usr/share/doc/fixture.txt 'replacement bytes' ;;
    in-archive-pair)
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/a.txt file 'inert ordinary data'
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/b.txt hardlink usr/share/nmap/a.txt ''
        RB_EXPECTED=0
        ;;
    in-archive-reversed)
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/b.txt hardlink usr/share/nmap/a.txt ''
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/a.txt file 'inert ordinary data'
        ;;
    in-archive-mode)
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/a.txt file 'inert ordinary data'
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/b.txt hardlink usr/share/nmap/a.txt '' mode=0666
        ;;
    in-archive-data)
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/a.txt file 'inert ordinary data'
        rb_add "$LANDED_ARCHIVE" usr/share/nmap/b.txt hardlink usr/share/nmap/a.txt 'rewritten bytes'
        ;;
    esac
    auth_review "HARDLINK $link member at an ordinary incoming path" "$RB_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# The privileged program's own inode, physically and through its logical
# symlinked ancestor (usr/share/haseen -> ../../opt/haseen).
for target in physical logical; do
    self_case "vapt-rb-hardlink-self-$target"
    RB_TARGET=opt/haseen/layers/vapt/metadata.py
    [[ $target == physical ]] || RB_TARGET=usr/share/haseen/layers/vapt/metadata.py
    landed_archive nmap 7.99-1
    rb_add "$LANDED_ARCHIVE" usr/share/nmap/notes.txt hardlink "$RB_TARGET" '# inert replacement program text'
    auth_review "HARDLINK data-bearing member onto the $target root program path" 1 "$SELF_META" "$LANDED_ARCHIVE"
done

# A same-archive hardlink is only modelled when both paths are really
# extracted under plain directories: a skipped (NoExtract/NoUpgrade), backup
# (.pacnew) or symlink-aliased path leaves the on-disk inode the retained one.
for skip in noextract-target noupgrade-link backup-target alias-ancestor; do
    rb_anchor_case "vapt-rb-hardlink-$skip"
    landed_archive nmap 7.99-1
    case "$skip" in
    noextract-target)
        sed -i '/^\[options\]$/a NoExtract = usr/share/nmap/a.txt' "$ROOT/etc/pacman.conf" ;;
    noupgrade-link)
        sed -i '/^\[options\]$/a NoUpgrade = usr/share/nmap/b.txt' "$ROOT/etc/pacman.conf" ;;
    backup-target)
        printf 'backup = usr/share/nmap/a.txt\n' >>"$SANDBOX/landed/nmap-7.99-1/.PKGINFO"
        tar -czf "$LANDED_ARCHIVE" -C "$SANDBOX/landed/nmap-7.99-1" .PKGINFO usr ;;
    alias-ancestor)
        mkdir -p "$ROOT/usr/share/nmap-real"
        ln -s nmap-real "$ROOT/usr/share/nmap" ;;
    esac
    rb_add "$LANDED_ARCHIVE" usr/share/nmap/a.txt file 'inert ordinary data'
    rb_add "$LANDED_ARCHIVE" usr/share/nmap/b.txt hardlink usr/share/nmap/a.txt ''
    auth_review "HARDLINK same-archive pair with a $skip path is not modelled" 1 "$VAPT_META" "$LANDED_ARCHIVE"
done

umask "$RB_UMASK"
unset RB_UMASK RB_EXPECTED RB_ANCHOR RB_TARGET RB_ARCHIVES RB_EXTRA_PLAN

# --- Hardlink targets: ordinary extracted payloads only ------------------
# A hardlink alias and its target must both be ordinary payloads of the same
# archive (never dot-metadata) without xattrs; reuses the auth_* helpers above.
# Archives are only decoded by the audit; nothing is extracted, imported or
# executed. Facts come from the real producer.

HP_UMASK="$(umask)"
umask 022

# hp_alias ARCHIVE ALIAS TARGET — append a zero-body PAX hardlink ALIAS ->
# TARGET whose mode/uid/gid/uname/gname/mtime are copied from TARGET's own
# header and which carries no xattrs, so only the target's nature can differ.
hp_alias() {
    python3 - "$@" <<'PY'
import io, sys, tarfile
from pathlib import Path
archive, alias, target = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
with tarfile.open(archive, 'r:*') as old:
    members = [(m, old.extractfile(m).read() if m.isfile() else None) for m in old]
source = next((m for m, _ in members if m.name.removeprefix('./') == target), None)
if source is None or not source.isfile():
    sys.exit('fixture hardlink target missing or not regular: ' + target)
out = io.BytesIO()
with tarfile.open(fileobj=out, mode='w:gz', format=tarfile.PAX_FORMAT) as new:
    for member, data in members:
        if member.name.removeprefix('./') != alias:
            new.addfile(member, io.BytesIO(data) if data is not None else None)
    info = tarfile.TarInfo(alias)
    info.type, info.linkname, info.size = tarfile.LNKTYPE, source.name, 0
    info.mode, info.uid, info.gid = source.mode, source.uid, source.gid
    info.uname, info.gname, info.mtime = source.uname, source.gname, source.mtime
    new.addfile(info)
archive.write_bytes(out.getvalue())
PY
}

# Expected: only an ordinary earlier payload target with no xattrs on either
# side is an ordinary internal link.
for alias in ordinary-control pkginfo-target install-target dot-metadata-alias target-user-xattr; do
    landed_case "vapt-hp-hardlink-$alias"
    no_stock_hooks
    if [[ $alias == install-target ]]; then
        landed_archive nmap 7.99-1 'usr/share/nmap/a.txt=inert ordinary data' '.INSTALL=# inert fixture scriptlet notes'
    else
        landed_archive nmap 7.99-1 'usr/share/nmap/a.txt=inert ordinary data'
    fi
    HP_EXPECTED=1
    case "$alias" in
    ordinary-control) hp_alias "$LANDED_ARCHIVE" usr/share/nmap/b.txt usr/share/nmap/a.txt; HP_EXPECTED=0 ;;
    # libalpm never extracts dot-metadata: the alias would have no payload source.
    pkginfo-target) hp_alias "$LANDED_ARCHIVE" usr/share/nmap/b.txt .PKGINFO ;;
    install-target) hp_alias "$LANDED_ARCHIVE" usr/share/nmap/b.txt .INSTALL ;;
    # A root dot-name is package metadata, not an installed payload path.
    dot-metadata-alias) hp_alias "$LANDED_ARCHIVE" .CHANGELOG usr/share/nmap/a.txt ;;
    # Target carries a user xattr; the alias header has none.
    target-user-xattr)
        auth_member "$LANDED_ARCHIVE" usr/share/nmap/a.txt xattr=user.haseen-fixture=inert
        hp_alias "$LANDED_ARCHIVE" usr/share/nmap/b.txt usr/share/nmap/a.txt
        ;;
    esac
    auth_review "HARDLINK-PAYLOAD zero-body alias case $alias" "$HP_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

umask "$HP_UMASK"
unset HP_UMASK HP_EXPECTED

# --- Root stdlib physical layout: no redirected import roots -----------
# The root interpreter imports its stdlib through usr/lib/python3.14 and
# usr/lib/python314.zip; a link there (or an outward/site-packages-bound
# link inside the imported stdlib) would make other physical bytes the
# import roots. Reuses the rb_*/auth_* helpers above. Fixture bytes are
# inert text/ELF metadata; nothing is imported, executed or extracted.

SR_UMASK="$(umask)"
umask 022

# sr_stdlib_link — relocate the stock stdlib to /opt/stdlib and make
# usr/lib/python3.14 a base-proven link to it (base reference, local DB and
# mtree all name the link; the physical files keep their base-proven bytes).
sr_stdlib_link() {
    mkdir -p "$ROOT/opt"
    mv "$ROOT/usr/lib/python3.14" "$ROOT/opt/stdlib"
    rb_python_member usr/lib/python3.14 link:/opt/stdlib
}
# sr_dynload_link — the same for the canonical lib-dynload directory alone.
sr_dynload_link() {
    mkdir -p "$ROOT/opt"
    mv "$ROOT/usr/lib/python3.14/lib-dynload" "$ROOT/opt/dynload"
    rb_python_member usr/lib/python3.14/lib-dynload link:/opt/dynload
}

# Retained base-proven directory alias: a non-base module in its physical
# target is an import-root change. Without the alias the same path is data.
for alias in none stdlib-dir dynload-dir; do
    rb_python_case "vapt-sr-stdlib-alias-$alias"
    SR_EXPECTED=1
    case "$alias" in
    none)
        landed_archive nmap 7.99-1 'opt/stdlib/argparse/__init__.py=# inert fixture module text, never imported'
        SR_EXPECTED=0
        ;;
    stdlib-dir)
        sr_stdlib_link
        landed_archive nmap 7.99-1 'opt/stdlib/argparse/__init__.py=# inert fixture module text, never imported'
        ;;
    dynload-dir)
        sr_dynload_link
        vapt_elf "$SANDBOX/sr-extension" soname=_vaptfix.cpython-314-x86_64-linux-gnu.so needed=libc.so.6
        landed_archive nmap 7.99-1 "opt/dynload/_vaptfix.cpython-314-x86_64-linux-gnu.so<$SANDBOX/sr-extension"
        ;;
    esac
    auth_review "STDLIB-REDIRECT non-base module behind retained alias ($alias)" "$SR_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# Retained base-proven zip alias whose physical target a non-base package
# owns and upgrades. Without the alias the same file is unrelated data.
for alias in none zip; do
    rb_python_case "vapt-sr-stdlib-zip-$alias"
    rb_lower_owner vapt-runtime opt/stdlib.zip 'inert original zip stand-in'
    [[ $alias == none ]] || rb_python_member usr/lib/python314.zip link:/opt/stdlib.zip
    landed_plan chaotic-aur vapt-runtime 2-1
    landed_archive vapt-runtime 2-1 'opt/stdlib.zip=inert replacement zip stand-in'
    auth_publish "$LANDED_ARCHIVE"
    SR_EXPECTED=1
    [[ $alias != none ]] || SR_EXPECTED=0
    auth_review "STDLIB-REDIRECT non-base physical zip replacement (alias: $alias)" "$SR_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# Future redirect: a base python update makes usr/lib/python3.14 a link to a
# new physical tree it supplies. The future layout is non-canonical, so it is
# a manual refusal alone or with a non-base companion module there.
for companion in none module; do
    rb_python_case "vapt-sr-stdlib-future-$companion"
    SR_ARCHIVES=()
    if [[ $companion == module ]]; then
        landed_plan extra python 3.14.0-2 blackarch vapt-notes 1-1
    else
        landed_plan extra python 3.14.0-2
    fi
    landed_archive python 3.14.0-2 "usr/bin/python3.14<$ROOT/usr/bin/python3.14" 'usr/bin/python3@>python3.14' \
        'usr/lib/python3.14@>/opt/stdlib-next' \
        "opt/stdlib-next/ctypes/__init__.py<$ROOT/usr/lib/python3.14/ctypes/__init__.py" \
        "opt/stdlib-next/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so<$ROOT/usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so"
    SR_ARCHIVES+=("$LANDED_ARCHIVE")
    SR_EXPECTED=1
    if [[ $companion == module ]]; then
        landed_archive vapt-notes 1-1 'opt/stdlib-next/argparse/__init__.py=# inert fixture module text, never imported'
        SR_ARCHIVES+=("$LANDED_ARCHIVE")
        SR_EXPECTED=1
    fi
    auth_publish "${SR_ARCHIVES[@]}"
    auth_review "STDLIB-REDIRECT base future redirect (companion: $companion)" "$SR_EXPECTED" "$VAPT_META" "${SR_ARCHIVES[@]}"
done

# Member links inside the canonical tree: a link staying in the tree (file
# or package directory) is the stock shape; one whose target leaves the tree
# is a non-canonical root. The base-proven link alone (unrelated nmap)
# already refuses. site-packages is outside the -I -S import path: an
# outward link there is not a root-consumed shape.
for member in in-tree in-tree-dir out-of-tree out-of-tree-dir retained-alias-only site-packages-link; do
    rb_python_case "vapt-sr-stdlib-member-$member"
    SR_EXPECTED=1
    case "$member" in
    in-tree)
        printf '# inert fixture module text, never imported\n' >"$SANDBOX/sr-y"
        rb_python_member usr/lib/python3.14/y.py "$SANDBOX/sr-y"
        rb_python_member usr/lib/python3.14/x.py link:y.py
        SR_EXPECTED=0
        ;;
    in-tree-dir)
        printf '# inert fixture module text, never imported\n' >"$SANDBOX/sr-pkg"
        rb_python_member usr/lib/python3.14/vaptpkg/__init__.py "$SANDBOX/sr-pkg"
        rb_python_member usr/lib/python3.14/vaptalias link:vaptpkg
        SR_EXPECTED=0
        ;;
    out-of-tree-dir)
        mkdir -p "$ROOT/opt/sharedargparse"
        printf '# inert fixture module text, never imported\n' >"$ROOT/opt/sharedargparse/__init__.py"
        rb_python_member usr/lib/python3.14/argparse link:/opt/sharedargparse
        ;;
    site-packages-link)
        mkdir -p "$ROOT/opt/x"
        printf '# inert fixture module text, never imported\n' >"$ROOT/opt/x/vaptsite.py"
        rb_python_member usr/lib/python3.14/site-packages/vaptsite.py link:/opt/x/vaptsite.py
        SR_EXPECTED=0
        ;;
    out-of-tree)
        mkdir -p "$ROOT/opt/x"
        printf '# inert fixture module text, never imported\n' >"$ROOT/opt/x/argparse.py"
        rb_python_member usr/lib/python3.14/argparse.py link:/opt/x/argparse.py
        ;;
    retained-alias-only) sr_stdlib_link ;;
    esac
    landed_archive nmap 7.99-1
    auth_review "STDLIB-REDIRECT retained stdlib member/alias shape ($member)" "$SR_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# A link FROM the imported stdlib INTO the excluded site-packages makes that
# site-packages file root-imported. The base-proven link refuses even with an
# unrelated transaction, and certainly when a non-base owner upgrades its
# physical target. Without the link the same upgrade is ordinary.
for into in no-link retained-link lower-upgrade; do
    rb_python_case "vapt-sr-stdlib-into-site-packages-$into"
    rb_lower_owner vapt-runtime usr/lib/python3.14/site-packages/vaptsite/argparse.py '# inert original module text, never imported'
    [[ $into == no-link ]] || rb_python_member usr/lib/python3.14/argparse.py link:site-packages/vaptsite/argparse.py
    if [[ $into == retained-link ]]; then
        landed_archive nmap 7.99-1
    else
        landed_plan chaotic-aur vapt-runtime 2-1
        landed_archive vapt-runtime 2-1 'usr/lib/python3.14/site-packages/vaptsite/argparse.py=# inert replacement module text, never imported'
        auth_publish "$LANDED_ARCHIVE"
    fi
    SR_EXPECTED=1
    [[ $into != no-link ]] || SR_EXPECTED=0
    auth_review "STDLIB-REDIRECT stdlib link into site-packages ($into)" "$SR_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# The stock physical layout with a link-free base python update.
rb_python_case vapt-sr-stdlib-base-canonical
rb_python_update
auth_publish "$LANDED_ARCHIVE"
auth_review 'STDLIB-REDIRECT link-free base python update over the stock layout (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"

umask "$SR_UMASK"
unset SR_UMASK SR_EXPECTED SR_ARCHIVES

# --- Root stdlib: site-packages is an exact path component -------------
# Only the exact site-packages directory is outside the -I -S import path; a
# sibling such as site-packages-compat is ordinary stdlib. Reuses the rb_*/
# auth_* helpers above; fixture text is inert, nothing is imported, executed
# or extracted.

SP_UMASK="$(umask)"
umask 022

for compat in exact-site-packages compat-member compat-alias base-compat; do
    rb_python_case "vapt-sp-prefix-$compat"
    SP_DIR=site-packages-compat
    [[ $compat != exact-site-packages ]] || SP_DIR=site-packages
    SP_REL="usr/lib/python3.14/$SP_DIR/argparse.py"
    SP_EXPECTED=1
    if [[ $compat == base-compat ]]; then
        # Base-authenticated update of a base-owned compat member.
        printf '# inert original module text, never imported\n' >"$SANDBOX/sp-old"
        rb_python_member "$SP_REL" "$SANDBOX/sp-old"
        rb_python_update "$SP_REL=# inert updated module text, never imported"
        SP_EXPECTED=0
    else
        rb_lower_owner vapt-runtime "$SP_REL" '# inert original module text, never imported'
        [[ $compat != compat-alias ]] || rb_python_member usr/lib/python3.14/argparse.py "link:$SP_DIR/argparse.py"
        landed_plan chaotic-aur vapt-runtime 2-1
        landed_archive vapt-runtime 2-1 "$SP_REL=# inert replacement module text, never imported"
        [[ $compat != exact-site-packages ]] || SP_EXPECTED=0
    fi
    auth_publish "$LANDED_ARCHIVE"
    auth_review "SITE-PACKAGES prefix boundary ($compat)" "$SP_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

umask "$SP_UMASK"
unset SP_UMASK SP_DIR SP_REL SP_EXPECTED

# --- Root stdlib: free-threaded interpreter (python3.14t) --------------
# The root model derives the ABI thread suffix from the real executable
# name; its stdlib is usr/lib/python3.14t and its zip usr/lib/python314t.zip.
# Every byte is inert text or a copy of the stock inert fixture ELF; nothing
# is imported, executed or extracted.

TP_UMASK="$(umask)"
umask 022

# tp_sources — inert source bytes for the thread layout: the stock fixture
# interpreter ELF and lib-dynload extension (base-proven bytes), plus text.
tp_sources() {
    cp "$ROOT/usr/bin/python3.14" "$SANDBOX/tp-python3.14t"
    cp "$ROOT/usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so" "$SANDBOX/tp-ctypes"
    printf '# inert fixture stdlib landmark, never imported\n' >"$SANDBOX/tp-os"
}
# tp_thread_root — retained base-proven thread root: usr/bin/python3 ->
# python3.14t, a real usr/lib/python3.14t with os.py and lib-dynload, all in
# the base-signed python reference, local DB, mtree and signature.
tp_thread_root() {
    tp_sources
    rb_python_member usr/bin/python3.14t "$SANDBOX/tp-python3.14t"
    rb_python_member usr/lib/python3.14t/os.py "$SANDBOX/tp-os"
    rb_python_member usr/lib/python3.14t/lib-dynload/_ctypes.cpython-314t-x86_64-linux-gnu.so "$SANDBOX/tp-ctypes"
    rb_python_member usr/bin/python3 link:python3.14t
}
# tp_base_thread_update — base-signed python 3.14.0-2 whose future
# root is the thread layout, keeping the stock non-thread members too.
tp_base_thread_update() {
    landed_archive python 3.14.0-2 "usr/bin/python3.14<$ROOT/usr/bin/python3.14" \
        "usr/lib/python3.14/ctypes/__init__.py<$ROOT/usr/lib/python3.14/ctypes/__init__.py" \
        "usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so<$ROOT/usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so" \
        "usr/bin/python3.14t<$SANDBOX/tp-python3.14t" 'usr/bin/python3@>python3.14t' \
        "usr/lib/python3.14t/os.py<$SANDBOX/tp-os" \
        "usr/lib/python3.14t/lib-dynload/_ctypes.cpython-314t-x86_64-linux-gnu.so<$SANDBOX/tp-ctypes"
}

# Retained thread root: the plain base update is supported; a non-base
# stdlib member or the selected thread zip is an import-root change; names
# that only look like thread stdlib paths outside usr/lib are ordinary.
for change in base-update member zip off-root; do
    rb_python_case "vapt-tp-thread-root-$change"
    tp_thread_root
    TP_EXPECTED=1
    case "$change" in
    base-update)
        landed_plan extra python 3.14.0-2
        tp_base_thread_update
        auth_publish "$LANDED_ARCHIVE"
        TP_EXPECTED=0
        ;;
    member) landed_archive nmap 7.99-1 'usr/lib/python3.14t/argparse.py=# inert fixture module text, never imported' ;;
    zip) landed_archive nmap 7.99-1 'usr/lib/python314t.zip=inert fixture zip stand-in' ;;
    off-root)
        landed_archive nmap 7.99-1 'usr/share/nmap/python314t.zip=inert fixture zip stand-in' \
            'usr/share/nmap/python3.14t/argparse.py=# inert fixture module text, never imported'
        TP_EXPECTED=0
        ;;
    esac
    auth_review "THREAD-ROOT retained python3.14t root ($change)" "$TP_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# Future transition: a base update introduces the previously absent thread
# root. Alone it is supported; a non-base companion module in the new thread
# stdlib in the same plan is an import-root change.
for companion in none module; do
    rb_python_case "vapt-tp-thread-transition-$companion"
    tp_sources
    TP_ARCHIVES=()
    if [[ $companion == module ]]; then
        landed_plan extra python 3.14.0-2 blackarch vapt-notes 1-1
    else
        landed_plan extra python 3.14.0-2
    fi
    tp_base_thread_update
    TP_ARCHIVES+=("$LANDED_ARCHIVE")
    TP_EXPECTED=0
    if [[ $companion == module ]]; then
        landed_archive vapt-notes 1-1 'usr/lib/python3.14t/argparse.py=# inert fixture module text, never imported'
        TP_ARCHIVES+=("$LANDED_ARCHIVE")
        TP_EXPECTED=1
    fi
    auth_publish "${TP_ARCHIVES[@]}"
    auth_review "THREAD-ROOT base transition to python3.14t (companion: $companion)" "$TP_EXPECTED" "$VAPT_META" "${TP_ARCHIVES[@]}"
done

umask "$TP_UMASK"
unset TP_UMASK TP_EXPECTED TP_ARCHIVES

# --- New root-consumed directories: creation authority ------------------
# A directory the transaction CREATES inside the root stdlib carries the
# archive's mode/uid/gid/xattrs (libalpm extracts with OWNER|PERM|XATTR); an
# existing directory is never re-permissioned. Archives are only decoded by
# the audit; nothing is extracted, imported or executed.
RD_UMASK="$(umask)"
umask 022
RD_ALT_ID="$(python3 -c 'import os; print(65533 if os.getuid() == 65534 else 65534)')"

# rb_dir ARCHIVE NAME [mode=OCT] [uid=N] [gid=N] [xattr=NAME=VALUE] — append
# a DIRTYPE member (default 0755, caller uid/gid, no xattrs), keeping others.
rb_dir() {
    python3 - "$@" <<'PY'
import io, os, sys, tarfile
from pathlib import Path
archive, name, changes = Path(sys.argv[1]), sys.argv[2].rstrip('/'), sys.argv[3:]
with tarfile.open(archive, 'r:*') as old:
    members = [(m, old.extractfile(m).read() if m.isfile() else None) for m in old]
info = tarfile.TarInfo(name)
info.type, info.mode, info.uid, info.gid = tarfile.DIRTYPE, 0o755, os.getuid(), os.getgid()
for change in changes:
    key, value = change.split('=', 1)
    if key == 'mode':
        info.mode = int(value, 8)
    elif key in ('uid', 'gid'):
        setattr(info, key, int(value))
    elif key == 'xattr':
        attr, text = value.split('=', 1)
        info.pax_headers = {'SCHILY.xattr.' + attr: text}
    else:
        sys.exit('unknown directory change ' + key)
out = io.BytesIO()
with tarfile.open(fileobj=out, mode='w:gz', format=tarfile.PAX_FORMAT) as new:
    for member, data in members:
        if member.name.removeprefix('./').rstrip('/') != name:
            new.addfile(member, io.BytesIO(data) if data is not None else None)
    new.addfile(info)
archive.write_bytes(out.getvalue())
PY
}

# Non-base nmap carries ONLY a directory entry. New in the root stdlib, its
# write authority decides whether another account can plant argparse/__init__.py
# there later; existing or unrelated directories keep ordinary semantics.
RD_NEW=usr/lib/python3.14/argparse
for dir in new-safe new-0777 new-group-writable new-uid new-gid new-xattr existing-0777 unrelated-0777; do
    rb_python_case "vapt-rd-stdlib-dir-$dir"
    landed_archive nmap 7.99-1
    RD_EXPECTED=1
    case "$dir" in
    new-safe) rb_dir "$LANDED_ARCHIVE" "$RD_NEW"; RD_EXPECTED=0 ;;
    new-0777) rb_dir "$LANDED_ARCHIVE" "$RD_NEW" mode=0777 ;;
    new-group-writable) rb_dir "$LANDED_ARCHIVE" "$RD_NEW" mode=0775 ;;
    new-uid) rb_dir "$LANDED_ARCHIVE" "$RD_NEW" "uid=$RD_ALT_ID" ;;
    new-gid) rb_dir "$LANDED_ARCHIVE" "$RD_NEW" "gid=$RD_ALT_ID" ;;
    new-xattr) rb_dir "$LANDED_ARCHIVE" "$RD_NEW" xattr=user.haseen-fixture=inert ;;
    # libalpm never re-permissions an existing directory.
    existing-0777) rb_dir "$LANDED_ARCHIVE" usr/lib/python3.14/ctypes mode=0777; RD_EXPECTED=0 ;;
    # Not an import root of the root interpreter.
    unrelated-0777) rb_dir "$LANDED_ARCHIVE" usr/share/nmap/user-data mode=0777; RD_EXPECTED=0 ;;
    esac
    auth_review "ROOT-DIR-AUTHORITY directory-only entry ($dir)" "$RD_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

# Two creators of the same new stdlib directory in one plan: the base python
# update's safe header does not excuse the non-base companion's unsafe one
# (which header wins at extraction is unmodelled). The base creator alone is
# the authenticated control.
for creators in base-only base-and-unsafe-companion; do
    rb_python_case "vapt-rd-stdlib-dir-creators-$creators"
    RD_ARCHIVES=()
    # rb_python_update writes the plan itself; the companion row must be in it.
    RB_EXTRA_PLAN=()
    [[ $creators == base-only ]] || RB_EXTRA_PLAN=(blackarch vapt-notes 1-1)
    rb_python_update
    RB_EXTRA_PLAN=()
    rb_dir "$LANDED_ARCHIVE" "$RD_NEW"
    RD_ARCHIVES+=("$LANDED_ARCHIVE")
    RD_EXPECTED=0
    if [[ $creators != base-only ]]; then
        landed_archive vapt-notes 1-1
        rb_dir "$LANDED_ARCHIVE" "$RD_NEW" mode=0777
        RD_ARCHIVES+=("$LANDED_ARCHIVE")
        RD_EXPECTED=1
    fi
    auth_publish "${RD_ARCHIVES[@]}"
    auth_review "ROOT-DIR-AUTHORITY new stdlib directory creators ($creators)" "$RD_EXPECTED" "$VAPT_META" "${RD_ARCHIVES[@]}"
done

# The rule is attribute-only: an authenticated base creator with an unsafe
# new-directory header is refused too. A new directory inside the exact
# site-packages subtree is outside the -I -S import tree.
rb_python_case vapt-rd-stdlib-dir-base-0777
rb_python_update
rb_dir "$LANDED_ARCHIVE" "$RD_NEW" mode=0777
auth_publish "$LANDED_ARCHIVE"
auth_review 'ROOT-DIR-AUTHORITY base-created new stdlib directory at 0777' 1 "$VAPT_META" "$LANDED_ARCHIVE"

rb_python_case vapt-rd-site-packages-dir-0777
landed_archive nmap 7.99-1
rb_dir "$LANDED_ARCHIVE" usr/lib/python3.14/site-packages/vaptsite mode=0777
auth_review 'ROOT-DIR-AUTHORITY new site-packages directory at 0777 (control)' 0 "$VAPT_META" "$LANDED_ARCHIVE"

# A new stdlib directory with a safe header still inherits the nearest
# existing parent's default ACL (named-group writer); skipped with a note
# where the filesystem rejects POSIX ACL xattrs.
if ! acl_supported; then
    echo "  (note: the test filesystem rejects POSIX ACL xattrs; the inherited default-ACL directory case was skipped)"
else
    for parent in plain default-acl; do
        rb_python_case "vapt-rd-stdlib-dir-parent-$parent"
        [[ $parent == plain ]] || acl_apply "$ROOT/usr/lib/python3.14" default
        landed_archive nmap 7.99-1
        rb_dir "$LANDED_ARCHIVE" "$RD_NEW"
        RD_EXPECTED=0
        [[ $parent == plain ]] || RD_EXPECTED=1
        auth_review "ROOT-DIR-AUTHORITY new stdlib directory under a $parent parent" "$RD_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
    done
fi

umask "$RD_UMASK"
unset RD_UMASK RD_ALT_ID RD_NEW RD_EXPECTED RD_ARCHIVES

# --- New root-consumed directories: loader, hwcaps and hook namespaces --
# hwcaps, the hook directory, a configured loader directory and its physical
# alias; each pair differs only in the incoming directory header (0755
# root-equivalent vs 0777). Bytes are inert; nothing is extracted, loaded or
# executed.
RC_UMASK="$(umask)"
umask 022

# rc_base_member OWNER VERSION REL SOURCE|link:TARGET — add one member to the
# base-signed stock OWNER reference archive and install exactly it, recording
# it in the local DB files/mtree (base-proven retained configuration).
rc_base_member() {
    python3 - "$ROOT" "$@" <<'PY'
import gzip, hashlib, io, sys, tarfile
from pathlib import Path
root, owner, version, rel, source = Path(sys.argv[1]), *sys.argv[2:]
archive = root / 'var/cache/pacman/pkg' / (owner + '-' + version + '-x86_64.pkg.tar.gz')
link = source[5:] if source.startswith('link:') else None
data = None if link else Path(source).read_bytes()
out = io.BytesIO()
with tarfile.open(archive, 'r:*') as old, tarfile.open(fileobj=out, mode='w:gz') as new:
    for member in old:
        if member.name.removeprefix('./').rstrip('/') != rel:
            new.addfile(member, old.extractfile(member) if member.isfile() else None)
    info = tarfile.TarInfo(rel)
    info.mode = 0o644
    if link:
        info.type, info.linkname = tarfile.SYMTYPE, link
        new.addfile(info)
    else:
        info.size = len(data)
        new.addfile(info, io.BytesIO(data))
archive.write_bytes(out.getvalue())
target = root / rel
target.parent.mkdir(parents=True, exist_ok=True)
target.unlink(missing_ok=True)
entry = root / 'var/lib/pacman/local' / (owner + '-' + version)
if link:
    target.symlink_to(link)
    row = './' + rel + ' type=link link=' + link
else:
    target.write_bytes(data)
    target.chmod(0o644)
    row = './' + rel + ' type=file mode=644 sha256digest=' + hashlib.sha256(data).hexdigest()
files = [r for r in (entry / 'files').read_text().splitlines() if r and r != '%FILES%' and r != rel]
(entry / 'files').write_text('%FILES%\n' + '\n'.join(files + [rel]) + '\n\n')
rows = [r for r in gzip.open(entry / 'mtree', 'rt').read().splitlines() if not r.startswith('./' + rel + ' ')]
with gzip.open(entry / 'mtree', 'wt') as stream:
    stream.write('\n'.join(rows + [row]) + '\n')
PY
    python3 "$VAPT_FIXTURE_DRIVER" digests "$ROOT/var/cache/pacman/pkg"
    auth_publish "$ROOT/var/cache/pacman/pkg/$1-$2-x86_64.pkg.tar.gz"
}
rc_case() {
    landed_case "$1"
    no_stock_hooks
}
rc_absent() { # REL — the fixture must not already contain it
    [[ ! -e $ROOT/$1 && ! -L $ROOT/$1 ]] || _fail "ROOT-DIR-CONSUMERS fixture unexpectedly has /$1 before the transaction"
}
# rc_loader_fragment — base-proven glibc ld.so.conf.d fragment naming the
# configured loader directory /opt/vapt-libs.
rc_loader_fragment() {
    printf '/opt/vapt-libs\n' >"$SANDBOX/rc-fragment"
    rc_base_member glibc 2.44-1 etc/ld.so.conf.d/vapt.conf "$SANDBOX/rc-fragment"
}

for consumer in hwcaps hookdir loaderdir loaderdir-alias; do
    for mode in 0755 0777; do
        rc_case "vapt-rc-$consumer-$mode"
        landed_archive nmap 7.99-1
        case "$consumer" in
        hwcaps)
            rc_absent usr/lib/glibc-hwcaps
            rb_dir "$LANDED_ARCHIVE" usr/lib/glibc-hwcaps
            rb_dir "$LANDED_ARCHIVE" usr/lib/glibc-hwcaps/x86-64-v3 "mode=$mode"
            ;;
        hookdir)
            rc_absent etc/pacman.d
            rb_dir "$LANDED_ARCHIVE" etc/pacman.d
            rb_dir "$LANDED_ARCHIVE" etc/pacman.d/hooks "mode=$mode"
            ;;
        loaderdir)
            rc_loader_fragment
            rc_absent opt/vapt-libs
            mkdir -p "$ROOT/opt"
            rb_dir "$LANDED_ARCHIVE" opt/vapt-libs "mode=$mode"
            ;;
        # The configured directory is a retained base-proven link; the new
        # physical directory it resolves to is the loader-consumed one.
        loaderdir-alias)
            rc_loader_fragment
            mkdir -p "$ROOT/opt"
            rc_base_member glibc 2.44-1 opt/vapt-libs link:/srv/vapt-libs
            rc_absent srv/vapt-libs
            mkdir -p "$ROOT/srv"
            rb_dir "$LANDED_ARCHIVE" srv/vapt-libs "mode=$mode"
            ;;
        esac
        RC_EXPECTED=0
        [[ $mode == 0755 ]] || RC_EXPECTED=1
        auth_review "ROOT-DIR-CONSUMERS new $consumer directory at $mode" "$RC_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
    done
done

# Ordinary package data and a library's private subtree stay ordinary even
# when world-writable.
for ordinary in usr/share/nmap/cache usr/lib/nmap/plugins; do
    rc_case "vapt-rc-ordinary-${ordinary//\//-}"
    landed_archive nmap 7.99-1
    rb_dir "$LANDED_ARCHIVE" "$ordinary" mode=0777
    auth_review "ROOT-DIR-CONSUMERS ordinary $ordinary directory at 0777 (control)" 0 "$VAPT_META" "$LANDED_ARCHIVE"
done

umask "$RC_UMASK"
unset RC_UMASK RC_EXPECTED

# --- New root-consumed directories: future stdlib versions and hook alias
# A non-base nmap ships ONLY a directory entry (no file under it) for a stdlib
# root the current interpreter does not select, or for the physical target
# of a retained hook-directory link; a later base switch or libalpm's opendir
# would keep that directory's authority. Archives are only decoded; nothing
# is extracted.
for FS_DIR in usr/lib/python3.15 usr/lib/python3.14t; do
    for FS_MODE in 0755 0777; do
        rb_python_case "vapt-fs-${FS_DIR##*/}-$FS_MODE"
        [[ ! -e $ROOT/$FS_DIR && ! -L $ROOT/$FS_DIR ]] \
            || _fail "FUTURE-STDLIB-DIR fixture unexpectedly has /$FS_DIR before the transaction"
        landed_archive nmap 7.99-1
        rb_dir "$LANDED_ARCHIVE" "$FS_DIR" "mode=$FS_MODE"
        FS_EXPECTED=0
        [[ $FS_MODE == 0755 ]] || FS_EXPECTED=1
        auth_review "FUTURE-STDLIB-DIR directory-only new /$FS_DIR at $FS_MODE" "$FS_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
    done
done
unset FS_DIR FS_MODE FS_EXPECTED

# Physical hook-directory alias: a retained base-proven /etc/pacman.d/hooks
# link to an initially absent /opt/pacman-hooks. libalpm's opendir follows the
# link, so the new physical directory is the hook root (rc_base_member and
# rc_case from the loader/hook namespace section above).
for FS_MODE in 0755 0777; do
    rc_case "vapt-fs-hook-alias-$FS_MODE"
    rc_base_member filesystem 2025.10.12-1 etc/pacman.d/hooks link:/opt/pacman-hooks
    [[ ! -e $ROOT/opt/pacman-hooks && ! -L $ROOT/opt/pacman-hooks ]] \
        || _fail 'HOOK-ALIAS fixture unexpectedly has /opt/pacman-hooks before the transaction'
    mkdir -p "$ROOT/opt"
    landed_archive nmap 7.99-1
    rb_dir "$LANDED_ARCHIVE" opt/pacman-hooks "mode=$FS_MODE"
    FS_EXPECTED=0
    [[ $FS_MODE == 0755 ]] || FS_EXPECTED=1
    auth_review "HOOK-ALIAS new physical hook directory behind /etc/pacman.d/hooks at $FS_MODE" "$FS_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done
unset FS_MODE FS_EXPECTED

# --- New root-consumed directories: aliased PAM and gconv namespaces ----
# A retained base-proven link moves a root runtime namespace to an off-name
# physical directory; a new directory AT or BELOW that physical target
# carries the archive's authority. Archives are directory-only (.PKGINFO and
# directory headers, no file), so payloads and removals are empty. Reuses
# the rc_*/auth_* helpers above; nothing is extracted, loaded or executed.
# ra_dironly NAME VERSION DIR=MODE... — directory-only package archive;
# entries are caller-owned with no xattrs. Sets LANDED_ARCHIVE.
ra_dironly() {
    LANDED_ARCHIVE="$SANDBOX/archives/$1-$2-x86_64.pkg.tar.gz"
    mkdir -p "$SANDBOX/archives"
    python3 - "$LANDED_ARCHIVE" "$@" <<'PY'
import io, os, sys, tarfile
out, name, version, dirs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
pkginfo = ('pkgname = %s\npkgver = %s\narch = x86_64\n' % (name, version)).encode()
with tarfile.open(out, mode='w:gz', format=tarfile.PAX_FORMAT) as archive:
    info = tarfile.TarInfo('.PKGINFO')
    info.size, info.mode = len(pkginfo), 0o644
    archive.addfile(info, io.BytesIO(pkginfo))
    for spec in dirs:
        path, mode = spec.rsplit('=', 1)
        entry = tarfile.TarInfo(path)
        entry.type, entry.mode = tarfile.DIRTYPE, int(mode, 8)
        entry.uid, entry.gid = os.getuid(), os.getgid()
        archive.addfile(entry)
PY
}
ra_absent() {
    [[ ! -e $ROOT/$1 && ! -L $ROOT/$1 ]] || _fail "RUNTIME-ALIAS fixture unexpectedly has /$1 before the transaction"
}

# NAMESPACE OWNER VERSION LOGICAL PHYSICAL CHILD
RA_SPACES=(
    'pam filesystem 2025.10.12-1 etc/pam.d opt/pamconfig opt/pamconfig/sudo.d'
    'gconv glibc 2.44-1 usr/lib/gconv opt/gconv opt/gconv/gconv-modules.d'
)
for RA_SPACE in "${RA_SPACES[@]}"; do
    read -r RA_NAME RA_OWNER RA_VERSION RA_LOGICAL RA_PHYSICAL RA_CHILD <<<"$RA_SPACE"
    for RA_WHERE in target child; do
        for RA_MODE in 0755 0777; do
            rc_case "vapt-ra-$RA_NAME-$RA_WHERE-$RA_MODE"
            ra_absent "$RA_LOGICAL"
            ra_absent "$RA_PHYSICAL"
            mkdir -p "$ROOT/$(dirname "$RA_LOGICAL")" "$ROOT/$(dirname "$RA_PHYSICAL")"
            rc_base_member "$RA_OWNER" "$RA_VERSION" "$RA_LOGICAL" "link:/$RA_PHYSICAL"
            if [[ $RA_WHERE == target ]]; then
                ra_dironly nmap 7.99-1 "$RA_PHYSICAL=$RA_MODE"
            else
                # The physical root already exists, safely; only the child is new.
                install -d -m 0755 "$ROOT/$RA_PHYSICAL"
                ra_dironly nmap 7.99-1 "$RA_CHILD=$RA_MODE"
            fi
            RA_EXPECTED=0
            [[ $RA_MODE == 0755 ]] || RA_EXPECTED=1
            auth_review "RUNTIME-ALIAS new $RA_NAME $RA_WHERE directory behind /$RA_LOGICAL at $RA_MODE" \
                "$RA_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
        done
    done
done
unset RA_SPACES RA_SPACE RA_NAME RA_OWNER RA_VERSION RA_LOGICAL RA_PHYSICAL RA_CHILD RA_WHERE RA_MODE RA_EXPECTED

# --- Shared removals, directory hand-overs and the root interpreter ------
# A path several upgraded packages drop is removed under every owner's
# authority; an existing root-consumed directory one upgrade drops while
# another package ships its header may be recreated with that header; a
# transaction may not remove the /usr/bin/python3 post-commit steps run.
# Bytes are inert; nothing is extracted, loaded or executed.
FX_UMASK="$(umask)"
umask 022

# fx_dir_owner NAME DIR — installed non-base (chaotic-aur) NAME 1-1 owning
# exactly the existing 0755 directory DIR (local DB files/mtree).
fx_dir_owner() {
    vapt_conf_add $'[chaotic-aur]\nServer = https://mirror.example/chaotic-aur/$arch'
    [[ ! -e $ROOT/$2 && ! -L $ROOT/$2 ]] || _fail "HAND-OVER fixture unexpectedly has /$2 before setup"
    install -d -m 0755 "$ROOT/$2"
    python3 - "$ROOT" "$1" "$2" <<'PY'
import gzip, sys
from pathlib import Path
root, name, rel = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
entry = root / 'var/lib/pacman/local' / (name + '-1-1')
entry.mkdir()
(entry / 'desc').write_text('%NAME%\n' + name + '\n\n%VERSION%\n1-1\n\n%URL%\nhttps://example.org/' + name + '\n\n')
(entry / 'files').write_text('%FILES%\n' + rel + '/\n\n')
(entry / 'depends').write_text('%DEPENDS%\n\n%PROVIDES%\n\n%CONFLICTS%\n\n%REPLACES%\n\n')
with gzip.open(entry / 'mtree', 'wt') as stream:
    stream.write('#mtree\n./' + rel + ' type=dir mode=755\n')
PY
}

# Hand-over: vapt-runtime 1-1 owned etc/pam.d/vapt.d, its 2-1 drops it and
# nmap ships an explicit header for it in the same transaction.
for FX_MODE in 0755 0777; do
    rc_case "vapt-handover-pam-$FX_MODE"
    mkdir -p "$ROOT/etc/pam.d"
    fx_dir_owner vapt-runtime etc/pam.d/vapt.d
    landed_plan chaotic-aur vapt-runtime 2-1 extra nmap 7.99-1
    landed_archive vapt-runtime 2-1 'usr/share/vapt-runtime/readme=inert replacement data'
    FX_ARCHIVES=("$LANDED_ARCHIVE")
    ra_dironly nmap 7.99-1 "etc/pam.d/vapt.d=$FX_MODE"
    FX_ARCHIVES+=("$LANDED_ARCHIVE")
    auth_publish "${FX_ARCHIVES[@]}"
    FX_EXPECTED=0
    [[ $FX_MODE == 0755 ]] || FX_EXPECTED=1
    auth_review "HAND-OVER dropped /etc/pam.d/vapt.d recreated by a $FX_MODE header" \
        "$FX_EXPECTED" "$VAPT_META" "${FX_ARCHIVES[@]}"
done

# Shared removal: a stdlib file both the base python and a lower-trust owner
# drop. Every hash seed must refuse; only the base owner may remove alone.
for FX_OWNERS in base-only shared; do
    rb_python_case "vapt-shared-removal-$FX_OWNERS"
    FX_REL=usr/lib/python3.14/zz_vapt_shared.py
    printf '# inert fixture stdlib module text, never imported\n' >"$SANDBOX/fx-shared"
    RB_EXTRA_PLAN=()
    if [[ $FX_OWNERS == shared ]]; then
        rb_lower_owner vapt-runtime "$FX_REL" '# inert fixture stdlib module text, never imported'
        RB_EXTRA_PLAN=(chaotic-aur vapt-runtime 2-1)
    fi
    rb_python_member "$FX_REL" "$SANDBOX/fx-shared"
    rb_python_update
    RB_EXTRA_PLAN=()
    FX_ARCHIVES=("$LANDED_ARCHIVE")
    if [[ $FX_OWNERS == shared ]]; then
        landed_archive vapt-runtime 2-1 'usr/share/vapt-runtime/readme=inert replacement data'
        FX_ARCHIVES+=("$LANDED_ARCHIVE")
    fi
    auth_publish "${FX_ARCHIVES[@]}"
    FX_EXPECTED=0
    [[ $FX_OWNERS == base-only ]] || FX_EXPECTED=1
    auth_facts "$VAPT_META"
    for FX_SEED in 0 1 2 3 4 5 6 7; do
        PYTHONHASHSEED="$FX_SEED" auth_audit "SHARED-REMOVAL $FX_OWNERS removal of /$FX_REL (hash seed $FX_SEED)" \
            "$FX_EXPECTED" "$VAPT_META" --authority-facts "$AUTH_FACTS" "${FX_ARCHIVES[@]}"
    done
done

# Root interpreter: a base python update that keeps usr/bin/python3 passes;
# one that drops it is refused before the commit.
for FX_LINK in kept dropped; do
    rb_python_case "vapt-root-interpreter-$FX_LINK"
    if [[ $FX_LINK == kept ]]; then
        rb_python_update
        FX_EXPECTED=0
    else
        landed_plan extra python 3.14.0-2
        landed_archive python 3.14.0-2 "usr/bin/python3.14<$ROOT/usr/bin/python3.14" \
            "usr/lib/python3.14/ctypes/__init__.py<$ROOT/usr/lib/python3.14/ctypes/__init__.py" \
            "usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so<$ROOT/usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so"
        FX_EXPECTED=1
    fi
    auth_publish "$LANDED_ARCHIVE"
    auth_review "ROOT-INTERPRETER base python update with usr/bin/python3 $FX_LINK" \
        "$FX_EXPECTED" "$VAPT_META" "$LANDED_ARCHIVE"
done

umask "$FX_UMASK"
unset FX_UMASK FX_MODE FX_ARCHIVES FX_EXPECTED FX_OWNERS FX_REL FX_SEED FX_LINK
