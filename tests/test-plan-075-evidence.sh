# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }

plan="$(<"$REPO/plans/075-battery-warnings.md")"
assert_not_contains "Cancel is no longer described as hidden" "$plan" "shows the Cancel action behind its action affordance"
assert_contains "the final critical card says Cancel is directly visible" "$plan" "Cancel is directly visible"
assert_contains "the final critical-card screenshot is referenced" "$plan" "scratch-design/shots/1a-critical-card.png"
assert_contains "the final after-cancel screenshot is referenced" "$plan" "scratch-design/shots/1b-after-cancel.png"
assert_contains "the final after-cancel state is referenced" "$plan" "scratch-design/shots/1c-battery-state-after-cancel.json"
assert_contains "the final cancellation state is recorded" "$plan" "armed: false, cancelled: true, lastAction: \"\""
assert_contains "the earlier interaction is identified as pager IPC" "$plan" "pager IPC (act)"
assert_contains "screenshots do not establish pointer-click use" "$plan" "do not establish pointer-click use"
assert_contains "real hardware suspend remains unverified" "$plan" "Hardware suspend was not exercised"
