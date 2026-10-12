# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Real solver-plan/archive policy and public transaction APIs; managers are
# deterministic fakes which operate only on this test's fixture sysroot.
source "$FIXTURES/vapt-lib.sh"
WHOIS='extra|whois|5.6.4-1|https://github.com/rfc1036/whois'
WHOIS_ROW=$'extra\twhois\t5.6.4-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/whois-5.6.4-1-x86_64.pkg.tar.gz'
transaction_case() {
    vapt_sandbox "$1"
    vapt_root
    vapt_repos "$WHOIS"
    # Keep repository declarations and DBs consistent for full-upgrade commit.
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives"
    printf '%s\n' "$WHOIS_ROW" >"$VAPT_PLAN"
}
system_db() { cat "$ROOT/var/lib/pacman/sync/extra.db"; }
assert_no_commit() { # Consumer outcome: the manager fake opened no archive and nothing was installed.
    assert_eq "$1: no archive opened by a real install/upgrade commit" '' "$(vapt_calls commit-digests)"
    assert_eq "$1: reviewed target not installed" no \
        "$(grep -qs '"version": "5.6.4-1"' "$ROOT/var/lib/haseen/vapt/installed.json" && echo yes || echo no)"
}
assert_clean() {
    assert_eq "$1: root download stage removed" no "$([[ -d $ROOT/var/cache/haseen-vapt.fixture ]] && echo yes || echo no)"
    assert_eq "$1: private stage removed" '' "$(ls -A "$ROOT$XDG_CACHE_HOME/haseen/vapt" 2>/dev/null || true)"
    vapt_tools_untouched "$1"
}

# Installed exact is cheap and does not re-audit old activation scriptlets.
transaction_case vapt-transaction-exact
vapt_installed 'whois|5.6.4-1|https://github.com/rfc1036/whois|||post_install() { systemctl enable old.service; }'
vapt_api pacman extra/whois
assert_status 'exact target succeeds without staging' 0 "$STATUS"
assert_contains 'exact target state' "$OUTPUT" 'STATE=already-exact'
assert_eq 'exact target invokes neither solver nor root manager' '' "$(ls -A "$CALLS")"

# Even exact targets cannot retain AUR/custom dependencies implicitly.
transaction_case vapt-transaction-exact-provider
vapt_repos 'extra|whois|5.6.4-1|https://github.com/rfc1036/whois||libvirtual'
vapt_installed 'whois|5.6.4-1|https://github.com/rfc1036/whois||libvirtual' \
    'aur-provider|1-1|https://aur.archlinux.org/|libvirtual'
vapt_api pacman extra/whois
assert_status 'exact target with unproven provider skipped' 2 "$STATUS"
assert_eq 'unproven exact closure causes no download' '' "$(ls -A "$CALLS")"

# Positive control reaches install after signed download and audit. Every
# download uses a non-private root stage with alpm-writable package directory.
transaction_case vapt-transaction-clean
vapt_package whois 5.6.4-1
vapt_api pacman extra/whois
assert_status 'reviewed clean transaction commits' 0 "$STATUS"
assert_contains 'sandbox-safe download cache' "$(vapt_calls sudo)" '--cachedir /var/cache/haseen-vapt.fixture/packages'
assert_contains 'solver uses temporary DB' "$(vapt_calls pacman)" '--dbpath /var/cache/haseen-vapt.fixture/db -Sp'
assert_eq 'single-package transaction never refreshes system sync DB' 'original system sync DB' "$(system_db)"
assert_eq 'one final commit of exactly the audited archive' \
    "whois-5.6.4-1-x86_64.pkg.tar.gz $(sha256sum "$VAPT_ARCHIVES/whois-5.6.4-1-x86_64.pkg.tar.gz" | cut -d' ' -f1)" \
    "$(vapt_calls commit-digests)"
assert_not_contains 'ordinary package install never suppresses scriptlets' "$(vapt_calls sudo)" '--noscriptlet'
assert_clean clean

# Malformed plans, unavailable downloaded bytes, and hostile payloads stop
# before the commit. The positive control above prevents vacuous rejection.
for failure in version source missing-archive activation download; do
    transaction_case "vapt-transaction-$failure"
    vapt_package whois 5.6.4-1
    case "$failure" in
    version) printf '%s\n' "${WHOIS_ROW//5.6.4-1/5.6.5-1}" >"$VAPT_PLAN" ;;
    source) printf '%s\n' "${WHOIS_ROW/extra$'\t'/omarchy$'\t'}" >"$VAPT_PLAN" ;;
    missing-archive) rm "$VAPT_ARCHIVES/whois-5.6.4-1-x86_64.pkg.tar.gz" ;;
    activation) vapt_package whois 5.6.4-1 $'post_install() {\n systemctl enable --now whois.socket\n}' ;;
    download) export VAPT_PACMAN_FAIL=download ;;
    esac
    vapt_api pacman extra/whois
    expected=2
    [[ $failure != download ]] || expected=1
    assert_status "$failure refuses transaction" "$expected" "$STATUS"
    assert_no_commit "$failure"
    assert_eq "$failure preserves live system sync DB" 'original system sync DB' "$(system_db)"
    assert_clean "$failure"
done

# Full-upgrade review cannot refresh the real DB or create an upgrade marker
# before archive/closure audit. Post-review commit is tested separately.
transaction_case vapt-upgrade-rejected
vapt_installed 'whois|5.6.3-1|https://github.com/rfc1036/whois'
vapt_package whois 5.6.4-1 $'post_upgrade() {\n systemctl start whois.socket\n}'
vapt_api upgrade
assert_status 'unsafe full upgrade is a policy rejection' 2 "$STATUS"
assert_contains 'upgrade download is isolated' "$(vapt_calls sudo)" '--dbpath /var/cache/haseen-vapt.fixture/db -Syuw'
assert_contains 'upgrade plan is isolated' "$(vapt_calls pacman)" '--dbpath /var/cache/haseen-vapt.fixture/db -Sup'
assert_no_commit 'rejected full upgrade'
assert_eq 'rejected upgrade preserves system DB' 'original system sync DB' "$(system_db)"
assert_eq 'rejected upgrade creates no recovery marker' no "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
assert_clean 'rejected upgrade'

transaction_case vapt-upgrade-clean
vapt_installed 'whois|5.6.3-1|https://github.com/rfc1036/whois'
vapt_package whois 5.6.4-1
vapt_api upgrade
assert_status 'reviewed full upgrade commits' 0 "$STATUS"
assert_eq 'exactly the reviewed archive opened by one full upgrade commit' 1 "$(vapt_calls commit-digests | grep -c '^whois-5.6.4-1-x86_64.pkg.tar.gz ' || true)"
assert_eq 'successful upgrade clears recovery record' no "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
assert_eq 'commit uses frozen reviewed DB bytes' 'reviewed fixture DB extra' "$(system_db)"
assert_clean 'successful upgrade'

transaction_case vapt-upgrade-commit-failed
vapt_installed 'whois|5.6.3-1|https://github.com/rfc1036/whois'
vapt_package whois 5.6.4-1
export VAPT_PACMAN_FAIL=commit
vapt_api upgrade
assert_status 'failed reviewed commit is mutation failure' 1 "$STATUS"
assert_eq 'failed reviewed commit retains recovery record' yes "$([[ -f $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
assert_clean 'failed commit'

# Actual CLI subprocess, not a conditional call into layer internals: download
# failure must propagate and must not write an applied marker.
transaction_case vapt-cli-download-failed
vapt_repos "$WHOIS" "$VAPT_BA_KEYRING"
vapt_conf_add $'[blackarch]\nServer = https://blackarch.org/blackarch/$repo/os/$arch'
vapt_package whois 5.6.4-1
export VAPT_PACMAN_FAIL=download
vapt_api install --groups osint
assert_status 'failed download propagates through provisioning' 1 "$STATUS"
assert_eq 'failed apply never requests an applied marker write' '' "$(vapt_calls sudo | grep -F '/var/lib/haseen/layers/vapt' || true)"
assert_no_commit 'failed CLI download'
vapt_tools_untouched 'failed CLI download'

# Successive applies retain old logical/group rows and status keeps checking
# them, rather than claiming that the most recent group is the whole state.
vapt_sandbox vapt-cumulative
vapt_root
vapt_home_in_root
vapt_repos 'extra|whois|5.6.4-1|https://github.com/rfc1036/whois' "$VAPT_BA_KEYRING"
vapt_installed 'whois|5.6.4-1|https://github.com/rfc1036/whois'
vapt_api install --groups osint
assert_status 'first group apply with unresolved tools' 0 "$STATUS"
vapt_api install --groups network
assert_status 'second group apply with unresolved tools' 0 "$STATUS"
report="$(cat "$ROOT$VAPT_STATE/report.tsv")"
assert_eq 'shared identity retains selected-group union in order' 'osint,network' "$(awk -F'\t' '$1 == "whois" {print $2}' <<<"$report")"
assert_eq 'earlier whois selection retained' 1 "$(awk -F'\t' '$1 == "whois" {print $2}' <<<"$report" | grep -cF osint || true)"
assert_eq 'one cumulative row per identity' '' "$(awk -F'\t' 'NF == 8 && $1 !~ /^#/ && $1 != "logical" {print $1}' <<<"$report" | sort | uniq -d)"
assert_contains 'new group report retained' "$report" $'masscan\tnetwork\t'
vapt_api status
assert_status 'cumulative unavailable rows remain degraded' 2 "$STATUS"
vapt_tools_untouched cumulative
