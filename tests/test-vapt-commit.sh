# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 007 review F2/F3: a per-package commit installs exactly the audited
# artifacts, and BlackArch repository activation waits for the reviewed full
# upgrade. Managers, keys and network are deterministic fixture fakes that act
# only on this test's sysroot; no package, hook, key or tool executes.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; commit regressions were skipped)"
    return 0
fi

WHOIS_URL=https://github.com/rfc1036/whois
CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
commit_case() {
    vapt_sandbox "$1"
    vapt_root
    printf '%s\n' "$CONF" >"$ROOT/etc/pacman.conf"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_LIVE_PLAN="$SANDBOX/live.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
}
row() { printf 'extra\t%s\t%s\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/%s-%s-x86_64.pkg.tar.gz\n' "$1" "$2" "$1" "$2"; }
installed_field() { # NAME FIELD — FIELD of the installed record, or "absent"
    python3 - "$ROOT/var/lib/haseen/vapt/installed.json" "$1" "$2" <<'EOF'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
records = [p for p in (json.loads(path.read_text()) if path.is_file() else []) if p['name'] == sys.argv[2]]
print(records[0].get(sys.argv[3], '') if records else 'absent')
EOF
}

# --- F2: sync DB drift and provider choice after the audit -------------------
for yes in '' --yes; do
    label="drift${yes:+ $yes}"
    commit_case "vapt-commit-drift${yes:+-yes}"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL||libdep" 'extra|libdep|1-1|https://example.org/libdep' \
        'extra|libdep|2-1|https://example.org/libdep'
    vapt_package whois 5.6.4-1
    vapt_package libdep 1-1
    { row whois 5.6.4-1; row libdep 1-1; } >"$VAPT_PLAN"
    # Another pacman -Sy between audit and commit: live resolution is newer.
    { row whois 5.6.4-1; row libdep 2-1; } >"$VAPT_LIVE_PLAN"
    vapt_api pacman ${yes:+"$yes"} extra/whois
    assert_status "F2 $label: audited transaction commits" 0 "$STATUS"
    assert_eq "F2 $label: audited dependency version installed, not the drifted one" 1-1 "$(installed_field libdep version)"
    assert_eq "F2 $label: requested target is explicit" explicit "$(installed_field whois reason)"
    assert_eq "F2 $label: new dependency is a dependency" depend "$(installed_field libdep reason)"
    vapt_tools_untouched "F2 $label"

    label="provider${yes:+ $yes}"
    commit_case "vapt-commit-provider${yes:+-yes}"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL||virt" 'extra|prova|1-1|https://example.org/prova|virt' \
        'extra|provb|1-1|https://example.org/provb|virt'
    vapt_package whois 5.6.4-1
    vapt_package prova 1-1
    { row whois 5.6.4-1; row prova 1-1; } >"$VAPT_PLAN"
    # Interactive provider selection at commit picks a different provider.
    { row whois 5.6.4-1; row provb 1-1; } >"$VAPT_LIVE_PLAN"
    vapt_api pacman ${yes:+"$yes"} extra/whois
    assert_status "F2 $label: audited provider commits" 0 "$STATUS"
    assert_eq "F2 $label: audited provider installed" 1-1 "$(installed_field prova version)"
    assert_eq "F2 $label: unaudited provider never installed" absent "$(installed_field provb version)"
    vapt_tools_untouched "F2 $label"
done

# Existing install reasons are preserved; the requested target is explicit.
commit_case vapt-commit-reasons
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL||libdep,newdep" 'extra|libdep|1-1|https://example.org/libdep' \
    'extra|newdep|1-1|https://example.org/newdep'
vapt_installed "whois|5.6.3-1|$WHOIS_URL||libdep||usr/bin/whois|depend" \
    'libdep|0-1|https://example.org/libdep||||usr/bin/libdep|explicit'
vapt_package whois 5.6.4-1
vapt_package libdep 1-1
vapt_package newdep 1-1
{ row whois 5.6.4-1; row libdep 1-1; row newdep 1-1; } >"$VAPT_PLAN"
cp "$VAPT_PLAN" "$VAPT_LIVE_PLAN"
vapt_api pacman --yes extra/whois
assert_status 'F2 reasons: reviewed upgrade transaction commits' 0 "$STATUS"
assert_eq 'F2 reasons: requested target becomes explicit' explicit "$(installed_field whois reason)"
assert_eq 'F2 reasons: upgraded explicit dependency stays explicit' explicit "$(installed_field libdep reason)"
assert_eq 'F2 reasons: newly installed dependency is a dependency' depend "$(installed_field newdep reason)"
assert_eq 'F2 reasons: all audited versions installed' '5.6.4-1 1-1 1-1' \
    "$(installed_field whois version) $(installed_field libdep version) $(installed_field newdep version)"

# --- F3: BlackArch activation waits for the reviewed full upgrade ------------
ba_case() {
    commit_case "$1"
    vapt_repos "${VAPT_BASE[@]}" "extra|whois|5.6.4-1|$WHOIS_URL" "$VAPT_BA_KEYRING"
    vapt_installed "whois|5.6.3-1|$WHOIS_URL"
    vapt_bootstrap_fixture
    unset VAPT_LIVE_PLAN
    row whois 5.6.4-1 >"$VAPT_PLAN"
    CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
}
pending() { [[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no; }

ba_case vapt-ba-rejected-upgrade
vapt_package whois 5.6.4-1 $'post_upgrade() {\n systemctl start whois.socket\n}'
vapt_api blackarch
assert_status 'F3 rejected review: not a failed apply' 0 "$STATUS"
assert_eq 'F3 rejected review leaves the global pacman config unchanged' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
assert_eq 'F3 rejected review writes no recovery marker' no "$(pending)"
# Retry after the blocking upgrade content changes: resumable, not foreign.
vapt_package whois 5.6.4-1
vapt_api blackarch
assert_status 'F3 retry after rejection succeeds' 0 "$STATUS"
assert_not_contains 'F3 retry is never classified as a broken foreign stanza' "$OUTPUT" 'unverified/broken'
assert_contains 'F3 retry completes the reviewed bootstrap' "$OUTPUT" 'full upgrade completed'
assert_eq 'F3 activation appends exactly one BlackArch stanza' 1 "$(grep -c '^\[blackarch\]$' "$ROOT/etc/pacman.conf")"
vapt_tools_untouched 'F3 rejected then retried'
# B2: the root sudoers-facts producer writes only inside the root stage.
assert_eq 'B2 bootstrap never writes sudoers facts at the filesystem root' no \
    "$([[ -e /sudo-plugins || -e /sudo-plugins.new || -e $ROOT/sudo-plugins || -e $ROOT/sudo-plugins.new ]] && echo yes || echo no)"
# M2: the keyring is installed like any exact archive: from a
# repository-free configuration, so nothing can be re-resolved from a repo.
assert_not_contains 'M2 keyring install configuration names no repository' "$(vapt_calls commit-config)" '[core]'
assert_not_contains 'M2 keyring install configuration names no BlackArch repository' "$(vapt_calls commit-config)" '[blackarch]'

ba_case vapt-ba-commit-failed
vapt_package whois 5.6.4-1
export VAPT_PACMAN_FAIL=commit
vapt_api blackarch
assert_contains 'F3 failed reviewed commit is a mutation failure' "$OUTPUT" 'MUTATION=1'
assert_eq 'F3 failed reviewed commit records upgrade-pending' yes "$(pending)"
assert_eq 'F3 failed reviewed commit does not activate BlackArch' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
unset VAPT_PACMAN_FAIL
trust_calls="$(vapt_calls curl)$(vapt_calls gpg)"
vapt_api install --groups osint
assert_status 'F3 declined recovery is unavailable, not failed' 0 "$STATUS"
assert_eq 'F3 pending upgrade still blocks package transactions' skipped "$(vapt_field whois 6)"
assert_eq 'F3 declined recovery keeps upgrade-pending' yes "$(pending)"
assert_eq 'F3 declined recovery never contacts upstream or touches signer keys' "$trust_calls" \
    "$(vapt_calls curl)$(vapt_calls gpg)"
assert_eq 'F3 declined recovery leaves BlackArch inactive' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
vapt_tools_untouched 'F3 failed commit'
# Accepted recovery remembers the staged repository: it reviews and commits
# with BlackArch again, then activates it before clearing the record.
vapt_api recover
assert_status 'F3 accepted recovery completes' 0 "$STATUS"
assert_eq 'F3 accepted recovery activates exactly one BlackArch stanza' 1 "$(grep -c '^\[blackarch\]$' "$ROOT/etc/pacman.conf")"
assert_eq 'F3 accepted recovery clears upgrade-pending' no "$(pending)"
assert_contains 'F3 recovered BlackArch is usable' "$OUTPUT" 'STATE=usable'
vapt_tools_untouched 'F3 accepted recovery'

ba_case vapt-ba-foreign-stanza
vapt_repos "${VAPT_BASE[@]}" "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_conf_add $'[blackarch]\nInclude = /etc/pacman.d/blackarch-mirrorlist'
mkdir -p "$ROOT/etc/pacman.d"
printf 'Server = https://blackarch.org/blackarch/$repo/os/$arch\n' >"$ROOT/etc/pacman.d/blackarch-mirrorlist"
CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
vapt_api blackarch
assert_contains 'F3 foreign unverified stanza preserved, not repaired' "$OUTPUT" 'preserved, not repaired'
assert_eq 'F3 foreign stanza never re-bootstrapped' '' "$(vapt_calls curl)"
assert_eq 'F3 foreign stanza config unchanged' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"

# --- SEC-ARTIFACT-2: the commit opens only sealed, digest-bound artifacts ----
# swap_package NAME VERSION SCRIPT — a validly signed (mock) but unaudited
# same-filename archive, built outside $SANDBOX/archives so it is never the
# repository's published artifact.
swap_package() {
    local dir="$SANDBOX/swap-build/$1"
    mkdir -p "$dir/usr/bin" "$SANDBOX/swap"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$1" "$2" >"$dir/.PKGINFO"
    printf 'unaudited replacement, never executed\n' >"$dir/usr/bin/$1"
    printf '%s\n' "$3" >"$dir/.INSTALL"
    tar -czf "$SANDBOX/swap/$1-$2-x86_64.pkg.tar.gz" -C "$dir" .PKGINFO .INSTALL usr
}
sha() { sha256sum "$1" | cut -d' ' -f1; }
assert_sealed_commit() { # LABEL ARCHIVE-NAME EXPECTED-SHA
    assert_eq "$1: commit opened the audited bytes" "$2 $3" "$(grep -F "$2 " "$CALLS/commit-digests" | sort -u)"
    assert_eq "$1: committed directory is not group/other-writable" '' \
        "$(awk '{ m = substr($2, length($2) - 1, 2); if (m !~ /^[0145][0145]$/) print }' "$CALLS/commit-dirs")"
    assert_eq "$1: committed artifact signature verified over opened bytes" "$2 valid" "$(grep -F "$2 " "$CALLS/commit-signatures" | sort -u)"
}
for yes in '' --yes; do
    commit_case "vapt-seal-commit-swap${yes:+-yes}"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
    vapt_package whois 5.6.4-1
    row whois 5.6.4-1 >"$VAPT_PLAN"
    cp "$VAPT_PLAN" "$VAPT_LIVE_PLAN"
    good="$(sha "$SANDBOX/archives/whois-5.6.4-1-x86_64.pkg.tar.gz")"
    swap_package whois 5.6.4-1 $'post_install() {\n systemctl enable --now whois.socket\n}'
    export VAPT_SWAP_COMMIT="$SANDBOX/swap"
    vapt_api pacman ${yes:+"$yes"} extra/whois
    assert_status "SEC-ARTIFACT-2 post-audit swap${yes:+ $yes}: audited artifact still commits" 0 "$STATUS"
    assert_sealed_commit "SEC-ARTIFACT-2 post-audit swap${yes:+ $yes}" whois-5.6.4-1-x86_64.pkg.tar.gz "$good"
    vapt_tools_untouched "SEC-ARTIFACT-2 post-audit swap${yes:+ $yes}"
done

commit_case vapt-seal-download-swap
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
row whois 5.6.4-1 >"$VAPT_PLAN"
swap_package whois 5.6.4-1 $'post_install() {\n echo replaced\n}'
export VAPT_SWAP_DOWNLOAD="$SANDBOX/swap"
vapt_api pacman --yes extra/whois
assert_status 'SEC-ARTIFACT-2 pre-seal swap: bytes differing from the reviewed DB digest refused' 2 "$STATUS"
assert_eq 'SEC-ARTIFACT-2 pre-seal swap: nothing committed' '' "$(vapt_calls commit-digests)"
assert_eq 'SEC-ARTIFACT-2 pre-seal swap: target not installed' absent "$(installed_field whois version)"

commit_case vapt-seal-missing-digest
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'PY'
import json, sys
repos = json.load(open(sys.argv[1]))
for record in repos['extra']:
    record.pop('sha256sum', None)
json.dump(repos, open(sys.argv[1], 'w'))
PY
row whois 5.6.4-1 >"$VAPT_PLAN"
vapt_api pacman --yes extra/whois
assert_status 'SEC-ARTIFACT-2 artifact without a reviewed DB digest refused' 2 "$STATUS"
assert_eq 'SEC-ARTIFACT-2 unbound artifact never committed' '' "$(vapt_calls commit-digests)"

commit_case vapt-seal-duplicate-plan
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
{ row whois 5.6.4-1; row whois 5.6.4-1; } >"$VAPT_PLAN"
vapt_api pacman --yes extra/whois
assert_status 'SEC-PROVENANCE-3 duplicate plan row refused' 2 "$STATUS"
assert_eq 'SEC-PROVENANCE-3 duplicate plan never commits' '' "$(vapt_calls commit-digests)"

commit_case vapt-seal-upgrade-swap
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_installed "whois|5.6.3-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
row whois 5.6.4-1 >"$VAPT_PLAN"
unset VAPT_LIVE_PLAN
good="$(sha "$SANDBOX/archives/whois-5.6.4-1-x86_64.pkg.tar.gz")"
swap_package whois 5.6.4-1 $'post_upgrade() {\n systemctl start whois.socket\n}'
export VAPT_SWAP_COMMIT="$SANDBOX/swap"
vapt_api upgrade
assert_status 'SEC-ARTIFACT-2 full upgrade with post-audit swap commits the audited set' 0 "$STATUS"
assert_sealed_commit 'SEC-ARTIFACT-2 full upgrade' whois-5.6.4-1-x86_64.pkg.tar.gz "$good"

# --- SEC-PATH-4: every privileged pacman call runs with PATH=/usr/bin --------
commit_case vapt-path-canonical
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
row whois 5.6.4-1 >"$VAPT_PLAN"
mkdir -p "$ROOT/usr/bin" "$ROOT/opt/vendor/bin"
printf 'fixture decoy, never executed\n' >"$ROOT/usr/bin/touch"
printf 'fixture decoy, never executed\n' >"$ROOT/opt/vendor/bin/touch"
# A host sudo policy whose PATH puts a vendor directory first.
export VAPT_SUDO_PATH=/opt/vendor/bin:/usr/local/bin:/usr/bin
vapt_api pacman --yes extra/whois
assert_status 'SEC-PATH-4 install commits' 0 "$STATUS"
assert_eq 'SEC-PATH-4 hook helper command resolves from /usr/bin only' 'touch /usr/bin/touch' \
    "$(sort -u "$CALLS/commit-resolutions")"
unset VAPT_SUDO_PATH

# --- F3: the recovery record is validated, never silently forgotten ----------
for variant in symlink unknown; do
    ba_case "vapt-ba-marker-$variant"
    vapt_package whois 5.6.4-1
    mkdir -p "$ROOT/var/lib/haseen/vapt"
    case "$variant" in
    symlink)
        printf 'reviewed-full-upgrade-commit-pending\tblackarch-staged\n' >"$SANDBOX/elsewhere"
        ln -s "$SANDBOX/elsewhere" "$ROOT/var/lib/haseen/vapt/upgrade-pending" ;;
    unknown) printf 'reviewed-full-upgrade-commit-pending\tblackarch-stage\n' >"$ROOT/var/lib/haseen/vapt/upgrade-pending" ;;
    esac
    vapt_api recover
    assert_status "F3 $variant recovery record fails closed" 2 "$STATUS"
    assert_eq "F3 $variant recovery record: no review or commit" '' "$(vapt_calls review-repos)$(vapt_calls commit-digests)"
    assert_eq "F3 $variant recovery record retained" yes \
        "$([[ -L $ROOT/var/lib/haseen/vapt/upgrade-pending || -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
    assert_eq "F3 $variant recovery record: BlackArch not activated" "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
done

# --- G4: one privileged review/commit/recovery across haseen users -----------
# Another user's live transaction holds the root-owned shared mutex: neither a
# recovery nor a fresh review may run, and the recorded commit is preserved.
lock_case() {
    commit_case "$1"
    vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
    vapt_installed "whois|5.6.3-1|$WHOIS_URL"
    vapt_package whois 5.6.4-1
    unset VAPT_LIVE_PLAN
    row whois 5.6.4-1 >"$VAPT_PLAN"
    MARKER="$ROOT/var/lib/haseen/vapt/upgrade-pending"
    mkdir -p "${MARKER%/*}"
    printf 'reviewed-full-upgrade-commit-pending\tblackarch-staged\n' >"$MARKER"
    MARKER_SHA="$(sha "$MARKER")"
}
lock_case vapt-root-lock-busy
lock="$ROOT/var/lib/haseen/vapt/transaction.lock"
: >"$lock"
chmod 0644 "$lock"
exec {held}<"$lock"
python3 -c 'import fcntl, sys; fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)' "$held"
for operation in recover upgrade; do
    vapt_api "$operation"
    assert_status "G4 $operation while another haseen transaction holds the mutex" 2 "$STATUS"
    assert_eq "G4 $operation never commits concurrently" '' "$(vapt_calls commit-digests)"
    assert_eq "G4 $operation preserves the other user's recovery record" "$MARKER_SHA" "$(sha "$MARKER")"
done
exec {held}<&-
assert_eq 'G4 busy mutex leaves BlackArch inactive' 0 "$(grep -c '^\[blackarch\]$' "$ROOT/etc/pacman.conf" || true)"

# Without contention, a fresh review never overwrites or clears a recorded
# commit; only recovery resumes it.
lock_case vapt-root-lock-fresh-review
vapt_api upgrade
assert_status 'G4 fresh review with a recorded commit is refused' 2 "$STATUS"
assert_eq 'G4 fresh review never commits' '' "$(vapt_calls commit-digests)"
assert_eq 'G4 fresh review preserves the recorded commit' "$MARKER_SHA" "$(sha "$MARKER")"

# --- B3: existing root haseen state created 0700 under a 077 umask ----------
# Root repairs its own non-replaceable state directories to 0755 before the
# user-side state, lock and marker checks need to traverse them.
commit_case vapt-state-dir-0700
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
row whois 5.6.4-1 >"$VAPT_PLAN"
cp "$VAPT_PLAN" "$VAPT_LIVE_PLAN"
mkdir -p "$ROOT/var/lib/haseen/vapt"
chmod 0700 "$ROOT/var/lib/haseen/vapt" "$ROOT/var/lib/haseen"
vapt_api pacman --yes extra/whois
assert_status 'B3 transaction with 0700 root state directories' 0 "$STATUS"
assert_eq 'B3 state directories are repaired to 0755' '755 755' \
    "$(stat -c %a "$ROOT/var/lib/haseen") $(stat -c %a "$ROOT/var/lib/haseen/vapt")"
assert_eq 'B3 reviewed version installed' 5.6.4-1 "$(installed_field whois version)"

# --- L1: pacman print-mode diagnostics never become plan rows ---------------
commit_case vapt-plan-stderr
vapt_repos "extra|whois|5.6.4-1|$WHOIS_URL"
vapt_package whois 5.6.4-1
row whois 5.6.4-1 >"$VAPT_PLAN"
cp "$VAPT_PLAN" "$VAPT_LIVE_PLAN"
export VAPT_PLAN_STDERR='warning: whois-5.6.4-1 is up to date -- reinstalling'
vapt_api pacman --yes extra/whois
unset VAPT_PLAN_STDERR
assert_status 'L1 stderr warning beside a valid plan' 0 "$STATUS"
assert_eq 'L1 reviewed version installed' 5.6.4-1 "$(installed_field whois version)"

# --- Audit M1: BlackArch preparation rechecks pending state under the lock --
# A recovery record that appears before this run holds the shared lock blocks
# keyring trust changes and the keyring package transaction.
ba_case vapt-ba-pending-at-lock
vapt_package whois 5.6.4-1
export VAPT_PENDING_AT_LOCK=1
vapt_api blackarch
unset VAPT_PENDING_AT_LOCK
assert_eq 'M1 pending at lock: no keyring trust change' '' "$(vapt_calls sudo | grep -F pacman-key || true)"
assert_eq 'M1 pending at lock: no package transaction' '' "$(vapt_calls commit-config)$(vapt_calls commit-digests)"
assert_eq 'M1 pending at lock: the other recovery record is preserved' \
    'reviewed-full-upgrade-commit-pending' "$(cat "$ROOT/var/lib/haseen/vapt/upgrade-pending" 2>/dev/null)"
assert_eq 'M1 pending at lock: BlackArch stays inactive' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
