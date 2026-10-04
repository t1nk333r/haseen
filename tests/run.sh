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
for f in "${files[@]}"; do
    printf '%s\n' "${f##*/}"
    set +e
    result="$(
        set -Eeuo pipefail
        # shellcheck source=tests/lib.sh
        source tests/lib.sh
        # shellcheck disable=SC1090
        source "$f"
        printf 'RESULT %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
    )"
    rc=$?
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
