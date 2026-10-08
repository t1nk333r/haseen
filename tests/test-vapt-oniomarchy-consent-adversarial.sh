# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 adversarial: consent to the private oniomarchy source is per
# operation (--with-oniomarchy) and never implied by --all, --yes, a repeated
# run, an existing host [oniomarchy] stanza or an existing descriptor. The
# repository commands' dry-runs are pure and claim nothing. Interrupted
# approvals leave nothing usable. All commands are hermetic stubs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"
# shellcheck source=tests/fixtures/vapt-onio-adversarial.sh
source "$FIXTURES/vapt-onio-adversarial.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; private-source consent regressions were skipped)"
    return 0
fi

# --- --all --yes without the flag never approves or contacts the source ------
adv_case vapt-adv-consent-all-yes
vapt_sudo_noop
vapt_api install --yes --all
assert_eq '--all --yes: the source stays not selected' not-selected "$(adv_annotation)"
assert_eq '--all --yes: nothing fetched from the private host' 0 "$(adv_onio_fetches)"
assert_eq '--all --yes: no key operation' '' "$(adv_trust_ops)"
assert_eq '--all --yes: no private state created' no "$(adv_exists "$ROOT$SOURCES")"
assert_contains '--all --yes: a candidate records the unselected tier' "$(vapt_field can-utils 8)" 'oniomarchy:not-selected'
assert_not_contains '--all --yes: no row targets the private source' "$OUTPUT" $'\toniomarchy/'

# --- an existing approved descriptor is not consent for this operation -------
adv_approved vapt-adv-consent-approved-noflag
vapt_sudo_noop
state_before="$(adv_digest "$ROOT$SOURCES")"
vapt_api install --yes --groups automotive,sdr
assert_eq 'approved, no flag: not selected' not-selected "$(adv_annotation)"
assert_eq 'approved, no flag: nothing fetched from the private host' 0 "$(adv_onio_fetches)"
assert_eq 'approved, no flag: can-utils not taken from the private source' none "$(vapt_field can-utils 3)"
assert_eq 'approved, no flag: chirp not taken from the private source' none "$(vapt_field chirp 3)"
assert_eq 'approved, no flag: private state untouched' "$state_before" "$(adv_digest "$ROOT$SOURCES")"
vapt_tools_untouched 'approved, no flag'

# --- repeated runs: opting in once does not persist --------------------------
adv_approved vapt-adv-consent-repeat
vapt_plan 'opted-in run' --with-oniomarchy --groups automotive
assert_eq 'first run resolves from the private source' oniomarchy/can-utils "$(vapt_field can-utils 4)"
vapt_plan 'next run without the flag' --groups automotive
assert_eq 'the next run is not selected again' not-selected "$(adv_annotation)"
assert_eq 'the next run does not resolve from the private source' none "$(vapt_field can-utils 3)"
vapt_sudo_noop
vapt_api install --yes --with-oniomarchy --groups automotive
fetches_after_opt_in="$(adv_onio_fetches)"
vapt_api install --yes --groups automotive
assert_eq 'a real run after an opted-in run fetches nothing from the private host' \
    "$fetches_after_opt_in" "$(adv_onio_fetches)"
assert_eq 'a real run after an opted-in run reports not-selected' not-selected "$(adv_annotation)"

# --- a host [oniomarchy] stanza is never adopted, with or without approval ---
adv_approved vapt-adv-consent-host-stanza
vapt_conf_add "$HOST_STANZA"
conf_before="$(cat "$ROOT/etc/pacman.conf")"
state_before="$(adv_digest "$ROOT$SOURCES")"
vapt_sudo_noop
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'host stanza + flag: the source is broken' broken "$(adv_annotation)"
assert_eq 'host stanza + flag: nothing fetched from the private host' 0 "$(adv_onio_fetches)"
assert_eq 'host stanza + flag: no key operation' '' "$(adv_trust_ops)"
assert_contains 'host stanza + flag: tier unavailable' "$(vapt_field can-utils 8)" 'oniomarchy:unavailable'
assert_eq 'host stanza + flag: pacman.conf byte-identical' "$conf_before" "$(cat "$ROOT/etc/pacman.conf")"
assert_eq 'host stanza + flag: private state untouched' "$state_before" "$(adv_digest "$ROOT$SOURCES")"
vapt_api repo-enable --yes
assert_status 'host stanza: repo-enable refuses' 1 "$STATUS"
assert_eq 'host stanza: repo-enable fetches nothing' 0 "$(adv_onio_fetches)"
assert_eq 'host stanza: repo-enable changes no trust' '' "$(adv_trust_ops)"

adv_case vapt-adv-consent-host-include
mkdir -p "$ROOT/etc/pacman.d"
printf '%s\n' "$HOST_STANZA" >"$ROOT/etc/pacman.d/onio.conf"
printf '\nInclude = /etc/pacman.d/onio.conf\n' >>"$ROOT/etc/pacman.conf"
vapt_sudo_noop
vapt_api repo-enable --yes
assert_status 'an included host stanza also refuses approval' 1 "$STATUS"
assert_eq 'included host stanza: nothing fetched' 0 "$(adv_onio_fetches)"
assert_eq 'included host stanza: no private state' no "$(adv_exists "$ROOT$SOURCES")"
vapt_plan 'included host stanza' --with-oniomarchy --groups automotive
assert_eq 'included host stanza: opted-in plan reports broken' broken "$(adv_annotation)"

# --- an existing foreign descriptor is preserved and never consent -----------
adv_approved vapt-adv-consent-foreign
printf '%s\nUsage = All\n' "$HOST_STANZA" >"$ROOT$SOURCES/oniomarchy.conf"
foreign="$(sha256sum <"$ROOT$SOURCES/oniomarchy.conf")"
vapt_sudo_noop
vapt_api repo-enable --yes
assert_status 'foreign descriptor: approval refused' 1 "$STATUS"
assert_eq 'foreign descriptor: approval fetched nothing' 0 "$(adv_onio_fetches)"
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'foreign descriptor: opted-in run reports broken' broken "$(adv_annotation)"
assert_eq 'foreign descriptor: opted-in run fetched nothing' 0 "$(adv_onio_fetches)"
vapt_api repo-disable --yes
assert_status 'foreign descriptor: disable refuses' 1 "$STATUS"
assert_eq 'foreign descriptor: byte-identical after enable/install/disable' "$foreign" "$(sha256sum <"$ROOT$SOURCES/oniomarchy.conf")"

# --- repository command dry-runs on an APPROVED source: pure, no claims -----
adv_approved vapt-adv-consent-dry-approved
tree_before="$(vapt_tree)"
vapt_cli repo-disable --dry-run oniomarchy
assert_status 'disable dry-run exits 0' 0 "$STATUS"
assert_dry_pure 'disable dry-run' "$OUTPUT"
assert_eq 'disable dry-run invokes no stub' '' "$(ls -A "$CALLS")"
assert_eq 'disable dry-run writes nothing' "$tree_before" "$(vapt_tree)"
assert_eq 'disable dry-run leaves the descriptor' yes "$(adv_exists "$ROOT$SOURCES/oniomarchy.conf")"
# The dry-run did not remove anything; it must not say it did.
assert_not_contains 'disable dry-run claims no removal' "$OUTPUT" 'descriptor removed'
vapt_cli repo-enable --dry-run oniomarchy
assert_status 'enable dry-run (approved) exits 0' 0 "$STATUS"
assert_eq 'enable dry-run (approved) invokes no stub' '' "$(ls -A "$CALLS")"
assert_eq 'enable dry-run (approved) writes nothing' "$tree_before" "$(vapt_tree)"
assert_not_contains 'enable dry-run (approved) claims no approval' "$OUTPUT" 'approved for dedicated'
# An approved source re-approves from its recorded keyring authority: the real
# run never refetches the HTTPS key nor re-signs the pin, so the plan must not
# describe that it would.
assert_not_contains 'enable dry-run (approved) does not plan a key refetch' "$OUTPUT" 'would fetch https://pkgs.oniomarchy.com/oniomarchy.gpg'
vapt_cli repo-status --dry-run --json oniomarchy
assert_status 'status dry-run exits 0' 0 "$STATUS"
assert_eq 'status dry-run invokes no stub' '' "$(ls -A "$CALLS")"
assert_eq 'status dry-run writes nothing' "$tree_before" "$(vapt_tree)"
vapt_cli install --dry-run --yes --with-oniomarchy --groups automotive
assert_status 'opted-in install dry-run with --yes exits 0' 0 "$STATUS"
assert_eq 'opted-in install dry-run with --yes invokes no stub' '' "$(ls -A "$CALLS")"
assert_eq 'opted-in install dry-run with --yes writes nothing' "$tree_before" "$(vapt_tree)"

# Dry-run on an absent source with --yes: still only a plan.
adv_case vapt-adv-consent-dry-absent-yes
tree_before="$(vapt_tree)"
vapt_cli repo-enable --dry-run --yes oniomarchy
assert_status 'enable dry-run --yes exits 0' 0 "$STATUS"
assert_eq 'enable dry-run --yes invokes no stub' '' "$(ls -A "$CALLS")"
assert_eq 'enable dry-run --yes writes nothing' "$tree_before" "$(vapt_tree)"
vapt_cli repo-disable --dry-run --yes oniomarchy
assert_eq 'disable dry-run of an absent source invokes no stub' '' "$(ls -A "$CALLS")"
assert_not_contains 'disable dry-run of an absent source claims no removal' "$OUTPUT" 'descriptor removed'

# --- operands ----------------------------------------------------------------
vapt_cli repo-status oniomarchy oniomarchy
assert_status 'repo-status refuses a repeated operand' 2 "$STATUS"
vapt_cli repo-enable --dry-run oniomarchy oniomarchy
assert_status 'repo-enable refuses a repeated operand' 2 "$STATUS"
vapt_cli repo-status blackarch
assert_status 'repo-status refuses another repository name' 2 "$STATUS"
vapt_cli install --dry-run --with-oniomarchy=yes --groups automotive
assert_status 'a valued flag is not the opt-in' 2 "$STATUS"
vapt_cli install --dry-run --groups automotive --with-oniomarchy --with-oniomarchy
assert_status 'a repeated trailing flag is refused' 2 "$STATUS"

# --- interrupted approval leaves nothing usable or approved ------------------
adv_case vapt-adv-consent-interrupt-approve
export VAPT_FAIL_ROOT_OP=oniomarchy-approve
vapt_api repo-enable --yes
unset VAPT_FAIL_ROOT_OP
assert_status 'interrupted approval fails' 1 "$STATUS"
assert_not_contains 'interrupted approval claims no approval' "$OUTPUT" 'approved for dedicated'
assert_eq 'interrupted approval: no descriptor' no "$(adv_exists "$ROOT$SOURCES/oniomarchy.conf")"
assert_eq 'interrupted approval: status is not usable' absent "$(adv_state)"
find "$CALLS" -mindepth 1 -delete
vapt_plan 'after an interrupted approval' --with-oniomarchy --groups automotive
assert_eq 'interrupted approval: nothing resolves from the source' none "$(vapt_field can-utils 3)"
: >"$CALLS/curl"
vapt_api install --with-oniomarchy --groups automotive
assert_eq 'interrupted approval: a run without --yes declines' declined "$(adv_annotation)"
assert_eq 'interrupted approval: the declined run fetches nothing' 0 "$(adv_onio_fetches)"

adv_case vapt-adv-consent-interrupt-write
export VAPT_FAIL_ROOT_OP=state-write
vapt_api repo-enable --yes
unset VAPT_FAIL_ROOT_OP
assert_status 'failed first root write fails approval' 1 "$STATUS"
assert_eq 'failed first root write: no private state' no "$(adv_exists "$ROOT$SOURCES")"
assert_eq 'failed first root write: no trust change' '' "$(adv_trust_ops)"

# --- disable, then inspect ---------------------------------------------------
adv_approved vapt-adv-consent-disable-status
vapt_sudo_noop
vapt_api repo-disable --yes
assert_status 'disable completes' 0 "$STATUS"
vapt_cli repo-status --json
assert_contains 'after disable the source is absent' "$OUTPUT" '"state": "absent"'
assert_contains 'after disable the source is not selected' "$OUTPUT" '"selected": false'
find "$CALLS" -mindepth 1 -delete
vapt_plan 'after disable' --with-oniomarchy --groups automotive
assert_eq 'after disable an opted-in plan is absent' absent "$(adv_annotation)"
assert_eq 'after disable nothing resolves from the source' none "$(vapt_field can-utils 3)"
vapt_api repo-disable --yes
assert_status 'a second disable is a no-op' 0 "$STATUS"
assert_contains 'a second disable says nothing to disable' "$OUTPUT" 'nothing to disable'
vapt_tools_untouched 'consent adversarial'
