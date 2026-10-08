# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 slice 1B: transactions with the private oniomarchy source keep
# Required DatabaseRequired in rendered, private and frozen configurations;
# closure admits only the fixed roles by exact name or reviewed alias; a full
# upgrade never carries the private source and no recovery record names it.
# Package manager, keys and network are hermetic fixture stubs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; transaction regressions were skipped)"
    return 0
fi

ONIO_FX="$FIXTURES/vapt-oniomarchy"
CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
MARKER=var/lib/haseen/vapt/upgrade-pending

tx_case() { # NAME [extra repository rows...]
    vapt_sandbox "$1"
    shift
    vapt_root
    printf '%s\n' "$CONF" >"$ROOT/etc/pacman.conf"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_repos "$@"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve
    vapt_onio_seed
    : >"$SANDBOX/plan.tsv"
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    mkdir -p "$SANDBOX/archives"
    CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
}
meta() { python3 "$VAPT_META" "$@" --root "$ROOT"; }
pending() { [[ -e $ROOT/$MARKER ]] && echo yes || echo no; }

# --- rendered configurations keep the strict policy ----------------------------
tx_case vapt-onio-tx-config
rendered="$(meta config --with-oniomarchy)"
assert_contains 'the private stanza is rendered with its strict policy' "$rendered" \
    $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch\nUsage = Sync Search Install'
assert_eq 'the private source is the last section' '[oniomarchy]' "$(grep '^\[' <<<"$rendered" | tail -n1)"
assert_not_contains 'without the operation flag it is absent' "$(meta config)" 'oniomarchy'
frozen="$(meta config --with-oniomarchy --frozen /var/cache/haseen-vapt.x/reviewed)"
assert_contains 'the frozen configuration keeps DatabaseRequired' "$frozen" \
    $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = file:///var/cache/haseen-vapt.x/reviewed/oniomarchy'
vapt_conf_add $'[oniomarchy]\nSigLevel = Optional TrustAll\nServer = http://pkgs.oniomarchy.com/$arch'
assert_not_contains 'a host stanza is never rendered' "$(meta config --with-oniomarchy)" 'Optional TrustAll'
find "$VAPT_LAYER" -name __pycache__ -prune -exec rm -rf {} +

# --- closure admission (exact roles, no Provides, no shadowing) ----------------
while IFS=$'\t' read -r name target plan extra expect; do
    [[ $plan != - ]] || plan=''
    [[ $extra != - ]] || extra=''
    rows=()
    [[ -z $extra ]] || IFS=';' read -r -a rows <<<"$extra"
    tx_case vapt-onio-tx-closure "${rows[@]}"
    db="$ROOT/var/cache/haseen-vapt.review/db"
    mkdir -p "$db/sync"
    cp "$SANDBOX/onio/serve/oniomarchy.db" "$db/sync/"
    cp "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
    if [[ -n $plan ]]; then
        tr ';' '\n' <<<"$plan" | tr ',' '\t' >"$SANDBOX/closure.tsv"
        capture meta closure "$target" "$SANDBOX/closure.tsv" --dbpath "$db" --with-oniomarchy
    else
        capture meta closure "$target" --dbpath "$db" --with-oniomarchy
    fi
    if [[ $expect == safe ]]; then
        assert_status "$name: admitted" 0 "$STATUS"
    else
        assert_status "$name: refused" 1 "$STATUS"
        assert_contains "$name: reason" "$OUTPUT" "$expect"
    fi
done < <(python3 -c '
import json, sys
for c in json.load(open(sys.argv[1]))["cases"]:
    plan = ";".join(",".join(row) for row in c["plan"]) or "-"
    print(c["name"], c["target"], plan, ";".join(c["extra"]) or "-", c["expect"], sep="\t")
' "$ONIO_FX/transactions/closure.json")
find "$VAPT_LAYER" -name __pycache__ -prune -exec rm -rf {} +

# --- an opted-in install commits the exact audited private package ------------
tx_case vapt-onio-tx-install
vapt_package can-utils 2025.01-1
vapt_onio_serve
vapt_onio_seed
printf 'oniomarchy\tcan-utils\t2025.01-1\thttps://pkgs.oniomarchy.com/x86_64/can-utils-2025.01-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'the private package resolves' oniomarchy/can-utils "$(vapt_field can-utils 4)"
assert_eq 'the audited private package is installed' installed "$(vapt_field can-utils 6)"
assert_contains 'the source field names the private source (what the narrowed test-vapt.sh check rejects)' \
    "$(vapt_field can-utils 3) $(vapt_field can-utils 4)" omarchy
assert_contains 'the commit used a repository-free configuration' "$(vapt_calls commit-config)" 'LocalFileSigLevel = Required TrustedOnly'
assert_eq 'pacman.conf is never changed by a private install' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
vapt_tools_untouched 'private install'

# --- a full upgrade never carries the private source ---------------------------
# The source's Usage excludes Upgrade and its prelude runs after any full
# upgrade, so an approved source is never reviewed, frozen or recorded.
tx_case vapt-onio-tx-upgrade
vapt_api upgrade
assert_status 'a full upgrade with an approved private source commits' 0 "$STATUS"
assert_not_contains 'the review never syncs the private source' "$(vapt_calls review-repos)" 'oniomarchy'
assert_not_contains 'the commit configuration never names it' "$(vapt_calls commit-config)" '[oniomarchy]'
assert_eq 'the recovery record is cleared' no "$(pending)"
assert_eq 'pacman.conf untouched by the upgrade' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
# The invariant is enforced, not assumed: a scope set before a full upgrade
# refuses it before any review.
tx_case vapt-onio-tx-upgrade-scope
capture bash -c '
runner="$1"
set -- repo-status true
source "$runner"
ASSUME_YES=true
vapt_snapshot || exit $?
VAPT_ONIOMARCHY_SCOPE=1
vapt_pacman_upgrade; rc=$?
printf "REASON=%s\n" "${VAPT_APPLY_REASON:-}"
exit "$rc"
' _ "$FIXTURES/vapt-runner.sh"
assert_status 'a full upgrade under the private scope is refused' 2 "$STATUS"
assert_contains 'the refusal names the invariant' "$OUTPUT" 'never joins a full upgrade'
assert_eq 'the refused upgrade reviewed nothing' '' "$(vapt_calls review-repos)"

# A failed reviewed commit records only the generic record.
tx_case vapt-onio-tx-record
export VAPT_PACMAN_FAIL=commit
vapt_api upgrade
unset VAPT_PACMAN_FAIL
assert_eq 'the recovery record never names the private source' 'reviewed-full-upgrade-commit-pending' "$(cat "$ROOT/$MARKER")"

# --- recovery records ------------------------------------------------------------
while IFS=$'\t' read -r expect record; do
    [[ -n $expect && $expect != \#* ]] || continue
    tx_case vapt-onio-tx-recover
    printf '%b' "$record" >"$ROOT/$MARKER"
    vapt_api recover
    if [[ $expect == accept ]]; then
        assert_status "recovery $record: resumes" 0 "$STATUS"
        assert_eq "recovery $record: record cleared" no "$(pending)"
        assert_not_contains "recovery $record: no private scope" "$(vapt_calls review-repos)" 'oniomarchy'
    else
        assert_status "recovery $record: refused" 2 "$STATUS"
        assert_eq "recovery $record: record preserved" yes "$(pending)"
        assert_eq "recovery $record: nothing reviewed" '' "$(vapt_calls review-repos)"
    fi
done <"$ONIO_FX/transactions/recovery-records.txt"
vapt_tools_untouched 'recovery'
