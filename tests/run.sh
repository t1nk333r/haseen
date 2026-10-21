#!/usr/bin/env bash
# tests/run.sh — hermetic test suite. Runs every tests/test-*.sh (or the ones
# named on the command line, or with --affected [--committed] [BASE] the ones
# a change affects) in its own subshell. Never touches the live system: see
# tests/lib.sh.
set -Eeuo pipefail

# The fakes are shell scripts, and a shell cannot trap a signal that was
# ignored when it started: bash keeps it ignored and says nothing. A suite
# started as a background job of a non-interactive shell (`tests/run.sh &`,
# an agent's or wrapper's job) inherits SIGINT and SIGQUIT ignored, so a fake
# recorder or notify-send never sees the SIGINT a test sends it (plan 094).
# Start from every signal at its default, as a terminal or CI's container
# exec does. The marker stops a loop should a signal stay ignored.
sig_ignored="$(sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$$/status" 2>/dev/null || true)"
if [[ -z ${HASEEN_TESTS_SIGDFL:-} && $sig_ignored == *[1-9a-f]* ]] &&
    env --default-signal true 2>/dev/null; then
    HASEEN_TESTS_SIGDFL=1 exec env --default-signal "$BASH" "$0" "$@"
fi
unset HASEEN_TESTS_SIGDFL sig_ignored

cd "$(dirname "$0")/.."

files=("$@")
# --affected [--committed] [BASE]: only the test files the change since BASE
# affects, as tools/affected-tests.sh chooses them (plan 100). Pull requests
# and pre-commit runs use it; main runs everything after each merge.
if [[ ${1:-} == --affected ]]; then
    shift
    selection="$(tools/affected-tests.sh "$@")" || exit
    if [[ -z $selection ]]; then
        echo "no test is affected by this change; nothing to run"
        exit 0
    fi
    files=(tests/test-*.sh)
    total_files=${#files[@]}
    [[ $selection == all ]] || mapfile -t files <<<"$selection"
    echo "affected: ${#files[@]} of $total_files test files"
fi
((${#files[@]} > 0)) || files=(tests/test-*.sh)

total=0
failed=0
# Each file's output goes to a file, not a command substitution: $(…) reads
# to EOF, so any process a test leaves behind with its stdout (an orphaned
# helper, a receiver it never killed) would hang the run instead of failing.
# Waiting for the subshell itself is bounded by the test. Every file gets a
# fresh capture, unlinked once read: a straggler of one file keeps writing
# into its own, never into the next file's results.
result_file=""
trap 'rm -f -- "$result_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for f in "${files[@]}"; do
    printf '%s\n' "${f##*/}"
    result_file="$(mktemp)"
    set +e
    (
        set -Eeuo pipefail
        # A test never reads the caller's terminal or pipe: a stub that
        # drains stdin (the scripted curl) would wait on it forever.
        exec </dev/null
        # shellcheck source=tests/lib.sh
        source tests/lib.sh
        # shellcheck disable=SC1090
        source "$f"
        printf 'RESULT %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
    ) >"$result_file"
    rc=$?
    result="$(<"$result_file")"
    rm -f -- "$result_file"
    result_file=""
    set -e
    printf '%s\n' "$result" | grep -v '^RESULT ' || true
    line="$(printf '%s\n' "$result" | grep '^RESULT ' || true)"
    if [[ $rc -ne 0 || -z $line ]]; then
        echo "  FAIL ${f##*/} aborted (exit $rc)" >&2
        failed=$((failed + 1))
        total=$((total + 1))
        continue
    fi
    read -r _ n nf <<<"$line"
    total=$((total + n))
    failed=$((failed + nf))
done

echo "----"
echo "$((total - failed))/$total passed"
((failed == 0))
