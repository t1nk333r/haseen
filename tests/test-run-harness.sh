# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tests/run.sh itself: a test file that leaves a process behind holding its
# stdout (util-linux unshare's orphaned --map-auto helper did, in CI), or a
# stub that drains stdin while the caller's stdin is an open pipe, must not
# hang the suite. Before the fix both waited forever.

sandbox run-harness
inner="$SANDBOX/inner-test.sh"
STRAY_PID_FILE="$SANDBOX/stray.pid"
export STRAY_PID_FILE
cat >"$inner" <<'EOF'
# shellcheck shell=bash
sleep 30 2>/dev/null &
echo "$!" >"$STRAY_PID_FILE"
cat >/dev/null
assert_eq "the inner case ran" yes yes
EOF
# Its stdin is a pipe whose writer stays open longer than the time limit.
capture timeout 15 "$REPO/tests/run.sh" "$inner" < <(sleep 20)
kill "$!" 2>/dev/null || true
[[ -s $STRAY_PID_FILE ]] && { kill "$(cat "$STRAY_PID_FILE")" 2>/dev/null || true; }
assert_status "a stray stdout holder and an open stdin do not hang the run" 0 "$STATUS"
assert_contains "the inner file's result is still counted" "$OUTPUT" "1/1 passed"
