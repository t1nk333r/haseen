# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
source "$FIXTURES/vapt-lib.sh"
boundary_case() {
    vapt_sandbox "vapt-abuse-boundary-$1"
    vapt_root
    printf '%s\n' $'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch' >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve
}

# Corrupt the recovery checkpoint at a precise layer boundary: after it was
# parsed under the shared lock but before refresh/review. This models an
# administrator/non-cooperating root writer, not an unprivileged attacker.
boundary_case inflight-checkpoint
vapt_onio_seed
marker="$ROOT/var/lib/haseen/vapt/upgrade-pending"
printf 'reviewed-full-upgrade-commit-pending\n' >"$marker"
: >"$SANDBOX/plan.tsv"
mkdir "$SANDBOX/archives"
export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
capture bash -c '
runner="$1"
set -- repo-status true
source "$runner"
run_root() {
    case "$*" in *" -Syuw "*) printf "hostile-changed-checkpoint\n" >"$HASEEN_SYSROOT/var/lib/haseen/vapt/upgrade-pending" ;; esac
    python3 "$VAPT_FIXTURE_DRIVER" root "$@"
}
vapt_pacman_recover
' _ "$FIXTURES/vapt-runner.sh"
assert_status 'checkpoint bytes changed during recovery: refuses before commit' 2 "$STATUS"
assert_eq 'checkpoint bytes changed during recovery: no commit' '' "$(vapt_calls commit-dirs)"
assert_eq 'checkpoint bytes changed during recovery: preserves new bytes' 'hostile-changed-checkpoint' "$(cat "$marker" 2>/dev/null || true)"

# Final approval write can fail after shared-keyring trust has changed. Its
# offline status must stay absent and retry must reuse recorded authority.
boundary_case final-write
export VAPT_FAIL_ROOT_OP=oniomarchy-approve
vapt_api repo-enable --yes
unset VAPT_FAIL_ROOT_OP
assert_status 'failed descriptor write: operation fails truthfully' 1 "$STATUS"
vapt_api repo-status true
assert_contains 'failed descriptor write: no usable source' "$OUTPUT" '"state": "absent"'
assert_contains 'failed descriptor write: retained authority accurately shown' "$OUTPUT" '"keyringAuthorityState": "ok"'
: >"$CALLS/sudo"
vapt_api repo-enable --yes
assert_status 'retry after descriptor failure: can approve' 0 "$STATUS"
assert_not_contains 'retry does not expand trust a second time' "$(vapt_calls sudo)" '--lsign-key'

# A forged user report is not installation proof. Invalid IDs and controls
# should not contaminate a consumer, nor run a package manager or tool.
boundary_case forged-report
mkdir -p "$ROOT$VAPT_STATE"
printf '# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\n%s\tautomotive\toniոմarchy\toniոմarchy/can-utils\tresolved\tinstalled\tforged\tforged\n' $'evil;id\x1b[2J' >"$ROOT$VAPT_STATE/report.tsv"
vapt_api status
assert_status 'forged report cannot attest installation' 2 "$STATUS"
assert_not_contains 'forged report ID is not emitted as terminal control' "$OUTPUT" $'\x1b'
assert_eq 'forged report consumer invokes no manager' '' "$(vapt_calls sudo)$(vapt_calls pacman)$(vapt_calls curl)$(vapt_calls gpg)$(vapt_calls pipx)"

# PATH shadows of every requested trust/package tool must never run on status
# or dry-run. Real mutators are blocked at the public sysroot gateway.
boundary_case path-shadow
for c in curl gpg pacman pacman-key pipx; do _vapt_stub_log "$SANDBOX/stubs/$c" "$c"; done
for command in repo-status repo-enable repo-disable; do
    args=(--dry-run oniomarchy)
    [[ $command != repo-status ]] || args=(--dry-run --json oniomarchy)
    vapt_cli "$command" "${args[@]}"
    assert_status "$command: PATH shadows not needed" 0 "$STATUS"
    assert_eq "$command: shadows not executed" '' "$(vapt_calls curl)$(vapt_calls gpg)$(vapt_calls pacman)$(vapt_calls pacman-key)$(vapt_calls pipx)"
done

# Unicode validation should not change with the caller locale. The previous
# abuse pass exercised the inherited UTF-8 locale; here force the C boundary.
boundary_case locale
cp -R "$VAPT_LAYER/packages" "$SANDBOX/packages"
printf 'cán-utils\n' >>"$SANDBOX/packages/security/automotive.txt"
capture env LC_ALL=C bash -c 'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/layers/vapt/provision.sh"; vapt_reset; VAPT_DIR="$1"; vapt_manifest_validate' _ "$SANDBOX"
assert_status 'C locale: Unicode package name rejected' 2 "$STATUS"
vapt_tools_untouched 'boundary probes'
