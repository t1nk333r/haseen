#!/usr/bin/env bash
# tests/run.sh — hermetic test suite. Runs every tests/test-*.sh (or the ones
# named on the command line) in its own subshell. Never touches the live
# system: see tests/lib.sh.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

files=("$@")
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
