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

# A straggler of one file never reaches the next file's results. The first
# file leaves a writer that waits (bounded) until the second file has
# started, then prints a passing RESULT and a marker; the second waits
# (bounded) for that write, then fails. The failure must count, the run must
# fail, and neither the marker nor the forged RESULT may be read as the
# second file's. The first file pads its own output so the writer's offset
# lies past the second file's, where a shared, truncated capture shows it.
sandbox run-harness-late
first="$SANDBOX/inner-first.sh"
second="$SANDBOX/inner-second.sh"
LATE_STARTED="$SANDBOX/second-started" LATE_WRITTEN="$SANDBOX/late-written"
export LATE_STARTED LATE_WRITTEN
cat >"$first" <<'EOF'
# shellcheck shell=bash
(
    for _ in $(seq 100); do [ -e "$LATE_STARTED" ] && break; sleep 0.05; done
    printf 'LATE-WRITER-OUTPUT\nRESULT 7 0\n'
    : >"$LATE_WRITTEN"
) 2>/dev/null &
for _ in $(seq 20); do echo "first file padding line"; done
assert_eq "the first inner case ran" yes yes
EOF
cat >"$second" <<'EOF'
# shellcheck shell=bash
: >"$LATE_STARTED"
for _ in $(seq 100); do [ -e "$LATE_WRITTEN" ] && break; sleep 0.05; done
assert_eq "the second inner case fails on purpose" yes no 2>/dev/null
EOF
capture timeout 15 "$REPO/tests/run.sh" "$first" "$second"
assert_eq "the late writer did write while the second file ran" yes \
    "$([[ -e $LATE_WRITTEN ]] && echo yes)"
assert_status "the second file's failure fails the run" 1 "$STATUS"
assert_contains "and it is counted, with no forged passes" "$OUTPUT" "1/2 passed"
assert_not_contains "the late output never reaches the second file's capture" "$OUTPUT" "LATE-WRITER-OUTPUT"
