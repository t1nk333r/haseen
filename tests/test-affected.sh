# shellcheck shell=bash
# haseen:covers tests/fixtures/affected/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 100: tools/affected-tests.sh picks the tests a change affects, and
# tests/run.sh --affected runs them. Everything here happens in a scratch git
# repository built for the test, with copies of the runner, tests/lib.sh and
# the selector, three tiny tests with covers declarations and a few source
# files; never against this checkout's history.

sandbox affected
S="$SANDBOX/repo"
# The sandbox stubs git; the selector and this test need the real one.
GIT_PATH=/usr/bin:/bin
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
g() { env PATH="$GIT_PATH" git -C "$S" "$@" >/dev/null; }
put() { mkdir -p "$S/$(dirname "$1")" && printf '%s\n' "${2:-$1}" >"$S/$1"; }
# sel [ARGS] — the selector's answer in OUTPUT (stdout and its report).
sel() { capture env PATH="$GIT_PATH" "$S/tools/affected-tests.sh" "$@"; }
# picked [ARGS] — the selection alone, one line.
picked() { env PATH="$GIT_PATH" "$S/tools/affected-tests.sh" --quiet "$@" 2>/dev/null | paste -sd' '; }
# change CMD — start from a fresh topic branch off main, run CMD, commit.
change() {
    g checkout -q -f main
    g branch -q -D topic 2>/dev/null || true
    g checkout -q -b topic
    "$@"
    g add -A
    g commit -q --allow-empty -m change
}

mkdir -p "$S/tools" "$S/tests"
cp "$REPO/tools/affected-tests.sh" "$S/tools/"
cp "$REPO/tests/run.sh" "$REPO/tests/lib.sh" "$S/tests/"
cp -R "$FIXTURES/affected/." "$S/"
# Every GLOBAL and EXEMPT entry needs a file, or --check calls it stale: one
# per entry, read from the selector itself ("**" and "*" filled in).
while read -r entry; do
    f="${entry//\'/}"
    f="${f//\*\*/x}"
    f="${f//\*/x}"
    [[ -e $S/$f ]] || put "$f"
done < <(sed -n '/^\(GLOBAL\|EXEMPT\)=(/,/^)/{/^    /s/^    \([^ ]*\).*/\1/p}' "$REPO/tools/affected-tests.sh")
put docs/other.md
put plans/001-x.md
put README.md
printf '/tests/.out/\n' >"$S/.gitignore"
env PATH="$GIT_PATH" git init -q -b main "$S"
g add -A
g commit -q -m base

# --- the scratch tree is complete -------------------------------------------
sel --check
assert_status "--check passes on a covered tree" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "every file is covered, global or exempt"
assert_not_contains "a covers line after the first command is not a declaration" "$OUTPUT" "not/declared"

# --- nothing changed --------------------------------------------------------
sel main
assert_status "no change succeeds" 0 "$STATUS"
assert_eq "no change selects nothing" "" "$(picked main)"
assert_contains "the report names the merge base" "$OUTPUT" "0 changed path(s) since"

# --- globs ------------------------------------------------------------------
change put src/alpha/deep/b.txt "b2"
assert_eq "a/** reaches any depth" "tests/test-alpha.sh" "$(picked main)"
change put src/x/y/shared.txt "s2"
assert_eq "a/**/b crosses directories" "tests/test-beta.sh" "$(picked main)"
change put src/shared.txt "s2"
assert_eq "a/**/b matches zero directories" "tests/test-beta.sh" "$(picked main)"
change put src/delta/d.c "d2"
assert_eq "{a,b} picks either alternative" "tests/test-gamma.sh" "$(picked main)"
change put src/gamma/sub/g.c
assert_eq "* stays inside one directory: an unclaimed path runs everything" "all" "$(picked main)"
sel main
assert_contains "the report names the unclaimed path" "$OUTPUT" \
    "src/gamma/sub/g.c: no test covers it and it is neither global nor exempt, every test"
change put src/alpha/a.txt "a2"
put src/beta.sh "b2"
g commit -q -am two
assert_eq "two changes select both tests, sorted" "tests/test-alpha.sh tests/test-beta.sh" "$(picked main)"

# --- renames and deletions count by both paths ---------------------------------
change g mv src/alpha/a.txt src/gamma/a.c
assert_eq "a rename selects the old path's and the new path's tests" \
    "tests/test-alpha.sh tests/test-gamma.sh" "$(picked main)"
change g rm -q src/delta/d.c
assert_eq "a deletion selects the tests that covered the file" "tests/test-gamma.sh" "$(picked main)"

# --- the global set, exempt documents, documents a test asserts on ---------------
change put tests/lib.sh "# changed"
assert_eq "tests/lib.sh is global" "all" "$(picked main)"
change put share/haseen/lib/common.sh "# changed"
assert_eq "common.sh is global" "all" "$(picked main)"
sel main
assert_contains "the report says why" "$OUTPUT" "share/haseen/lib/common.sh: global, every test"
change put .github/workflows/ci.yml "on: push"
assert_eq "the workflow is global" "all" "$(picked main)"
change put docs/other.md "more"
put plans/001-x.md "more"
put README.md "more"
g commit -q -am docs
assert_eq "plans, docs and top-level docs alone select nothing" "" "$(picked main)"
sel main
assert_contains "the report calls them exempt" "$OUTPUT" "docs/other.md: exempt, no test"
change put docs/alpha.md "asserted"
assert_eq "a document a test covers selects that test" "tests/test-alpha.sh" "$(picked main)"
change put NOTICE.md "a notice the gamma test asserts on"
assert_eq "a covered top-level document beats the exempt *.md" "tests/test-gamma.sh" "$(picked main)"

# --- a changed test selects itself; a deleted one runs nothing ---------------------
change sed -i 's/assert_eq "beta runs" yes yes/assert_eq "beta runs" yes "yes"/' "$S/tests/test-beta.sh"
assert_eq "a changed test selects itself" "tests/test-beta.sh" "$(picked main)"
change g rm -q tests/test-gamma.sh
assert_eq "a deleted test runs nothing" "" "$(picked main)"

# --- the working tree counts unless --committed ------------------------------------
change true
put src/beta.sh "unstaged"
assert_eq "an unstaged change counts" "tests/test-beta.sh" "$(picked main)"
assert_eq "--committed ignores it" "" "$(picked --committed main)"
g add src/beta.sh
assert_eq "a staged change counts" "tests/test-beta.sh" "$(picked main)"
g checkout -q -f topic
put src/alpha/new.txt "untracked"
assert_eq "an untracked file counts" "tests/test-alpha.sh" "$(picked main)"
assert_eq "--committed ignores it too" "" "$(picked --committed main)"
rm -f "$S/src/alpha/new.txt"

# --- the base -----------------------------------------------------------------
change put src/alpha/a.txt "a3"
g checkout -q main
put src/delta/d.c "main moved on"
g commit -q -am main-moves
g checkout -q topic
assert_eq "only the topic's own changes count, from the merge base" "tests/test-alpha.sh" "$(picked main)"
assert_eq "a commit works as the base" "tests/test-alpha.sh" \
    "$(picked "$(env PATH="$GIT_PATH" git -C "$S" rev-parse topic~1)")"
sel no-such-branch
assert_status "an unknown base fails" 2 "$STATUS"
assert_contains "and says so" "$OUTPUT" "unknown base 'no-such-branch'"

# --- --check failures ---------------------------------------------------------
change put src/unclaimed.txt
sel --check
assert_status "an uncovered file fails --check" 1 "$STATUS"
assert_contains "and is listed" "$OUTPUT" "  src/unclaimed.txt"
change sed -i 's#^\# haseen:covers src/beta.sh#& src/no-such/**#' "$S/tests/test-beta.sh"
sel --check
assert_status "a stale glob fails --check" 1 "$STATUS"
assert_contains "and is listed with its test" "$OUTPUT" "  tests/test-beta.sh: src/no-such/**"
change sed -i '/^# haseen:covers/d' "$S/tests/test-gamma.sh"
sel --check
assert_status "a test without covers fails --check" 1 "$STATUS"
assert_contains "and is listed" "$OUTPUT" $'test files without a \'# haseen:covers\' line:\n  tests/test-gamma.sh'
change sed -i 's#^\# haseen:covers src/beta.sh#& src/a**#' "$S/tests/test-beta.sh"
sel --check
assert_status "a malformed glob fails --check" 1 "$STATUS"
assert_contains "and is listed" "$OUTPUT" "tests/test-beta.sh: malformed glob: src/a**"
sel main
assert_status "and the selector refuses to guess" 2 "$STATUS"

# --- tests/run.sh --affected ----------------------------------------------------
change put docs/other.md "only docs"
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh" --affected main
assert_status "an empty selection exits 0" 0 "$STATUS"
assert_contains "and says nothing is affected" "$OUTPUT" "no test is affected by this change; nothing to run"
assert_not_contains "and runs nothing" "$OUTPUT" "test-alpha.sh"
change put src/delta/d.c "d3"
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh" --affected main
assert_status "a selection runs" 0 "$STATUS"
assert_contains "the selection is counted" "$OUTPUT" "affected: 1 of 3 test files"
assert_contains "the selected test ran" "$OUTPUT" "test-gamma.sh"
assert_not_contains "the others did not" "$OUTPUT" "test-alpha.sh"
assert_contains "its checks are counted" "$OUTPUT" "1/1 passed"
change put src/gamma/sub/g.c
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh" --affected --committed main
assert_status "all runs every file" 0 "$STATUS"
assert_contains "all is counted" "$OUTPUT" "affected: 3 of 3 test files"
assert_contains "every check ran" "$OUTPUT" "3/3 passed"
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh" --affected no-such-branch
assert_status "a selector failure fails the run" 2 "$STATUS"
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh" tests/test-alpha.sh
assert_contains "naming a file still runs just that file" "$OUTPUT" "1/1 passed"
capture env PATH="$GIT_PATH:$PATH" "$S/tests/run.sh"
assert_contains "no argument still runs every file" "$OUTPUT" "3/3 passed"


# --- names no glob can match: a tab or a newline selects every test --------------
# The selector reads paths NUL-separated and its own formats are lines of tab-
# separated fields; a name with a control character would split a field (a
# root "lib<TAB>E<TAB>x.c" once read as "lib", exempt, and selected nothing).
tab=$'\t'
change put "lib${tab}E${tab}x.c" "x"
assert_eq "a root name with tabs selects every test" "all" "$(picked main)"
sel main
assert_contains "and says why" "$OUTPUT" "\$'lib\\tE\\tx.c': a control character in the name"
change put "bin/a${tab}b" "x"
assert_eq "a tab-named command selects every test" "all" "$(picked main)"
change put "docs/a"$'\n'"README.md" "x"
assert_eq "a newline in a name selects every test, even between exempt halves" "all" "$(picked main)"
change put "lib${tab}E${tab}x.c" "x"
sel --check
assert_status "--check refuses a tab-named file" 1 "$STATUS"
assert_contains "and names it" "$OUTPUT" "  \$'lib\\tE\\tx.c'"

# --- when git cannot read the checkout, nothing passes ------------------------------
# Git refuses a checkout another user owns (CI's lint container, PR #56's run
# 39647712605); its own test knob stands in for the other owner here.
change put src/alpha/a.txt "a4"
capture env PATH="$GIT_PATH" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$S" status
assert_status "git itself refuses a checkout another user owns" 128 "$STATUS"
capture env PATH="$GIT_PATH" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$S/tools/affected-tests.sh" --check
assert_status "--check stops" 2 "$STATUS"
assert_contains "and says git cannot read the checkout" "$OUTPUT" "git cannot read this repository"
assert_not_contains "and never reports it covered" "$OUTPUT" "every file is covered"
capture env PATH="$GIT_PATH" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$S/tools/affected-tests.sh" main
assert_status "the selection stops too" 2 "$STATUS"
assert_eq "and selects nothing on stdout" "" "$(env PATH="$GIT_PATH" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$S/tools/affected-tests.sh" main 2>/dev/null)"
capture env PATH="$GIT_PATH:$PATH" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$S/tests/run.sh" --affected main
assert_status "tests/run.sh --affected fails with it" 2 "$STATUS"
assert_not_contains "without running a test" "$OUTPUT" "passed"
# A copy outside its own checkout would be read as whatever repository holds it.
mkdir -p "$SANDBOX/loose/tools" "$SANDBOX/loose/tests"
cp "$S/tools/affected-tests.sh" "$SANDBOX/loose/tools/"
cp "$S/tests/test-alpha.sh" "$SANDBOX/loose/tests/"
capture env PATH="$GIT_PATH" "$SANDBOX/loose/tools/affected-tests.sh" --check
assert_status "a copy outside a checkout stops" 2 "$STATUS"
assert_contains "and says why" "$OUTPUT" "affected-tests: git"
# A repository whose files git lists none of (all ignored) is not a covered one.
mkdir -p "$SANDBOX/empty"
cp -R "$SANDBOX/loose/." "$SANDBOX/empty/"
printf '*\n' >"$SANDBOX/empty/.gitignore"
env PATH="$GIT_PATH" git init -q "$SANDBOX/empty"
capture env PATH="$GIT_PATH" "$SANDBOX/empty/tools/affected-tests.sh" --check
assert_status "an empty file list stops --check" 2 "$STATUS"
assert_contains "and says so" "$OUTPUT" "git listed no files"
