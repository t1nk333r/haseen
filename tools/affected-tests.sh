#!/usr/bin/env bash
# tools/affected-tests.sh — the tests/test-*.sh files a change affects (plan 100).
#
#   tools/affected-tests.sh [--committed] [--quiet] [BASE]
#       Prints the affected test files, one per line and sorted, or the word
#       `all`. The change is every path that differs between HEAD and its merge
#       base with BASE (default origin/main), deleted and renamed paths by their
#       old and their new name. Without --committed, staged, unstaged and
#       untracked (not ignored) files count too; CI passes --committed. Why each
#       path selects what it does goes to stderr unless --quiet.
#   tools/affected-tests.sh --check
#       Fails, listing them, on a file that is neither global, exempt nor
#       covered by a test, on a covers glob or a GLOBAL/EXEMPT entry that matches
#       no file, on a malformed glob and on a test without a covers line.
#
# Each tests/test-*.sh names what it exercises in its leading comment block
# (the lines before its first command), one or more lines of
#   # haseen:covers GLOB [GLOB...]
# A changed path selects, in this order:
#   1. every test, if it matches GLOBAL;
#   2. itself, if it is a tests/test-*.sh;
#   3. every test whose covers match it;
#   4. nothing, if it matches EXEMPT;
#   5. every test otherwise: a file no test claims is never skipped silently.
# The full suite still runs on every push to main (.github/workflows/ci.yml), so
# a declaration that misses something shows up red there.
#
# Globs are matched against repository-relative paths, whole path only:
#   *      any characters except /        ?      one character except /
#   [abc]  one of the characters ([!a] negates)
#   **     a whole path segment: zero or more directories (a/**/b, **/b);
#          trailing, everything below (a/**)
#   {a,b}  either alternative (not nested; may contain /, not **)
# Nothing else is special. A glob cannot contain a space, ^ or \ (use ?).
set -Eeuo pipefail
cd "$(dirname "$0")/.."
# sort, comm and the regexes all byte-wise, whatever the caller's locale.
export LC_ALL=C

# Paths every test depends on: a change here runs the whole suite.
GLOBAL=(
    tests/lib.sh                 # sourced into every test file's subshell
    tests/run.sh                 # the runner itself
    tools/affected-tests.sh      # this selector: a fault here can skip any test
    '.github/workflows/**'       # CI: what runs, where and as whom
    share/haseen/lib/common.sh   # the dry-run helpers nearly every command sources
    bin/haseen                   # the router behind every `haseen <group> <verb>`
)

# Paths no test reads: a change here alone runs no test. A covers glob wins
# over this list, so a document a test asserts on (NOTICE.md, docs/vapt.md)
# still selects that test.
EXEMPT=(
    'plans/**'                   # the engineering record; tools/check-docs.sh checks it
    'docs/**'                    # architecture, decisions and guides
    '*.md'                       # top-level docs: README, AGENTS (CLAUDE.md links to it), handoff, NOTICE
    LICENSE                      # the licence text
    .editorconfig                # editor settings
    .gitignore                   # git's ignore list
    .gitleaksignore              # read only by the secrets gate (tools/secrets.sh)
    .shellcheckrc                # read only by the lint gate (tools/lint.sh)
    tools/lint.sh                # the lint gate, run by CI's lint job
    tools/check-docs.sh          # the docs gate, run by CI's docs job
    tools/nest-launch.sh         # developer tool: nested Hyprland for UI proofs
    tools/sync-apply.sh          # developer tool: moves a WIP checkout onto a new main
    tools/plymouth-mock.sh       # developer tool: previews the boot splash
    tools/smoke-greeter.sh       # developer tool: the login screen under a headless Hyprland
    'tools/vptr/**'              # developer tool: a virtual pointer for nest proofs
)

usage() { sed -n '2,15s/^# \{0,1\}//p' "$0"; }

# glob_regex GLOB — sets REGEX to the anchored POSIX ERE for GLOB; fails on
# bad syntax. (A variable, not output: no subshell per glob.)
glob_regex() {
    local g=$1 re='' c j body i=0 n=${#1} brace=0
    REGEX=
    [[ -n $g ]] || return 1
    while ((i < n)); do
        c=${g:i:1}
        case $c in
        '*')
            if [[ ${g:i:2} == '**' ]]; then
                ((brace == 0)) || return 1
                ((i == 0)) || [[ ${g:i-1:1} == / ]] || return 1
                if ((i + 2 == n)); then
                    re+='.+'
                    i=$((i + 2))
                    continue
                fi
                [[ ${g:i+2:1} == / ]] || return 1
                re+='([^/]+/)*'
                i=$((i + 3))
                continue
            fi
            re+='[^/]*'
            ;;
        '?') re+='[^/]' ;;
        '[')
            j=$((i + 1))
            [[ ${g:j:1} == '!' || ${g:j:1} == '^' ]] && j=$((j + 1))
            [[ ${g:j:1} == ']' ]] && j=$((j + 1))
            while ((j < n)) && [[ ${g:j:1} != ']' ]]; do j=$((j + 1)); done
            ((j < n)) || return 1
            body=${g:i+1:j-i-1}
            [[ $body == '!'* ]] && body="^${body:1}"
            [[ $body == *\\* || $body == *'['* ]] && return 1
            re+="[$body]"
            i=$j
            ;;
        '{')
            ((brace == 0)) || return 1
            brace=1
            re+='('
            ;;
        ',') if ((brace)); then re+='|'; else re+=','; fi ;;
        '}')
            ((brace)) || return 1
            brace=0
            re+=')'
            ;;
        '.' | '+' | '(' | ')' | '|' | '$') re+="[$c]" ;;
        '^' | \\ | ' ' | $'\t') return 1 ;;
        *) re+=$c ;;
        esac
        i=$((i + 1))
    done
    ((brace == 0)) || return 1
    REGEX="^$re\$"
}

# covers — "TEST<TAB>GLOB" for every glob in a test file's leading comments.
covers() {
    awk 'FNR == 1 { head = 1 }
        head && !/^#/ && !/^[[:space:]]*$/ { head = 0 }
        head && /^# haseen:covers[[:space:]]/ {
            sub(/^# haseen:covers[[:space:]]+/, "")
            n = split($0, g, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (g[i] != "") print FILENAME "\t" g[i]
        }' tests/test-*.sh
}

# rules FILE — writes "KIND<TAB>OWNER<TAB>GLOB<TAB>REGEX" lines for GLOBAL,
# EXEMPT and every covers glob to FILE; prints each malformed glob and fails.
rules() {
    local g bad=0 test REGEX
    {
        for g in "${GLOBAL[@]}"; do
            glob_regex "$g" || { echo "  GLOBAL: malformed glob: $g" >&3; bad=1; continue; }
            printf 'global\t-\t%s\t%s\n' "$g" "$REGEX"
        done
        for g in "${EXEMPT[@]}"; do
            glob_regex "$g" || { echo "  EXEMPT: malformed glob: $g" >&3; bad=1; continue; }
            printf 'exempt\t-\t%s\t%s\n' "$g" "$REGEX"
        done
        while IFS=$'\t' read -r test g; do
            glob_regex "$g" || { echo "  $test: malformed glob: $g" >&3; bad=1; continue; }
            printf 'covers\t%s\t%s\t%s\n' "$test" "$g" "$REGEX"
        done < <(covers)
    } 3>&1 >"$1"
    return "$bad"
}

# match PATHS RULES — "M<TAB>PATH<TAB>KIND<TAB>OWNER" for every match and
# "Z<TAB>KIND<TAB>OWNER<TAB>GLOB" for every rule that matches no path. The
# rules form the outer loop so each regex is compiled once.
match() {
    awk -F'\t' 'FILENAME == ARGV[1] { p[++n] = $0; next }
        {
            hit = 0
            for (i = 1; i <= n; i++)
                if (p[i] ~ $4) { print "M\t" p[i] "\t" $1 "\t" $2; hit = 1 }
            if (!hit) print "Z\t" $1 "\t" $2 "\t" $3
        }' "$1" "$2"
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

check() {
    local fail=0 f
    if ! rules "$tmp/rules" >"$tmp/bad"; then
        echo "affected-tests: malformed globs (see the syntax in tools/affected-tests.sh):" >&2
        cat "$tmp/bad" >&2
        fail=1
    fi
    # Every file a commit would carry: tracked and new, minus deleted ones.
    while IFS= read -r -d '' f; do
        [[ -e $f || -L $f ]] && printf '%s\n' "$f"
    done < <(git ls-files -z --cached --others --exclude-standard) | sort -u >"$tmp/paths"
    match "$tmp/paths" "$tmp/rules" >"$tmp/match"

    grep -E '^tests/test-[^/]*\.sh$' "$tmp/paths" | sort >"$tmp/tests"
    awk -F'\t' '$1 == "covers" { print $2 }' "$tmp/rules" | sort -u >"$tmp/declared"
    comm -23 "$tmp/tests" "$tmp/declared" >"$tmp/undeclared"
    if [[ -s $tmp/undeclared ]]; then
        echo "affected-tests: test files without a '# haseen:covers' line:" >&2
        sed 's/^/  /' "$tmp/undeclared" >&2
        fail=1
    fi

    awk -F'\t' '$1 == "Z" { print "  " ($2 == "covers" ? $3 : toupper($2)) ": " $4 }' "$tmp/match" >"$tmp/stale"
    if [[ -s $tmp/stale ]]; then
        echo "affected-tests: globs that match no file (stale declarations):" >&2
        cat "$tmp/stale" >&2
        fail=1
    fi

    # A test file always covers itself.
    { awk -F'\t' '$1 == "M" { print $2 }' "$tmp/match"; cat "$tmp/tests"; } | sort -u >"$tmp/claimed"
    comm -23 "$tmp/paths" "$tmp/claimed" >"$tmp/uncovered"
    if [[ -s $tmp/uncovered ]]; then
        echo "affected-tests: files no test covers and neither GLOBAL nor EXEMPT lists" >&2
        echo "  (add a '# haseen:covers' glob to the tests that exercise them):" >&2
        sed 's/^/  /' "$tmp/uncovered" >&2
        fail=1
    fi
    ((fail == 0)) || return 1
    echo "affected-tests: $(wc -l <"$tmp/paths") files, $(wc -l <"$tmp/tests") tests," \
        "$(grep -c '^covers' "$tmp/rules") covers globs: every file is covered, global or exempt"
}

select_tests() {
    local committed=$1 quiet=$2 base=$3 mb f
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null ||
        { echo "affected-tests: unknown base '$base' (fetch it, or name a commit)" >&2; return 2; }
    mb="$(git merge-base "$base" HEAD)" ||
        { echo "affected-tests: '$base' and HEAD share no history" >&2; return 2; }
    {
        git diff -z --name-only --no-renames "$mb" HEAD
        if ((committed == 0)); then
            git diff -z --name-only --no-renames HEAD
            git ls-files -z --others --exclude-standard
        fi
    } | tr '\0' '\n' | sed '/^$/d' | sort -u >"$tmp/changed"
    rules "$tmp/rules" >"$tmp/bad" || {
        echo "affected-tests: malformed globs; run tools/affected-tests.sh --check" >&2
        cat "$tmp/bad" >&2
        return 2
    }
    # One line per changed path: PATH, G if global, E if exempt, the covering
    # tests; "-" for none, as read collapses empty tab-separated fields.
    match "$tmp/changed" "$tmp/rules" | awk -F'\t' '
        FILENAME == ARGV[1] { ch[++n] = $0; next }
        $1 == "M" && $3 == "global" { g[$2] = "G" }
        $1 == "M" && $3 == "exempt" { e[$2] = "E" }
        $1 == "M" && $3 == "covers" { c[$2] = c[$2] " " $4 }
        END {
            for (i = 1; i <= n; i++) {
                p = ch[i]
                print p "\t" (p in g ? "G" : "-") "\t" (p in e ? "E" : "-") "\t" (p in c ? c[p] : "-")
            }
        }
    ' "$tmp/changed" - >"$tmp/classified"

    local -A selected=()
    local all=0 why=() t global exempt cov tests
    while IFS=$'\t' read -r f global exempt cov; do
        if [[ $global == G ]]; then
            all=1
            why+=("$f: global, every test")
            continue
        fi
        tests=()
        [[ $cov == - ]] || read -ra tests <<<"$cov"
        [[ $f =~ ^tests/test-[^/]*\.sh$ && -f $f ]] && tests+=("$f")
        if ((${#tests[@]} > 0)); then
            for t in "${tests[@]}"; do selected[$t]=1; done
            why+=("$f: $(printf '%s\n' "${tests[@]}" | sort -u | sed 's#^tests/##' | paste -sd' ')")
        elif [[ $exempt == E ]]; then
            why+=("$f: exempt, no test")
        elif [[ $f =~ ^tests/test-[^/]*\.sh$ ]]; then
            why+=("$f: a deleted test, nothing to run")
        else
            all=1
            why+=("$f: no test covers it and it is neither global nor exempt, every test")
        fi
    done <"$tmp/classified"

    if ((quiet == 0)); then
        {
            printf 'affected-tests: %s changed path(s) since %s (merge base of %s and HEAD)%s\n' \
                "$(wc -l <"$tmp/changed")" "$(git rev-parse --short "$mb")" "$base" \
                "$( ((committed)) && echo ', commits only' || echo ', commits and working tree')"
            ((${#why[@]} == 0)) || printf '  %s\n' "${why[@]}"
        } >&2
    fi
    if ((all)); then
        echo all
    elif ((${#selected[@]} > 0)); then
        printf '%s\n' "${!selected[@]}" | sort
    fi
}

committed=0 quiet=0 base=""
while (($# > 0)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    --check) check; exit ;;
    --committed) committed=1 ;;
    -q | --quiet) quiet=1 ;;
    -*) echo "affected-tests: unknown option $1 (see --help)" >&2; exit 2 ;;
    *)
        [[ -z $base ]] || { echo "affected-tests: one BASE only" >&2; exit 2; }
        base=$1
        ;;
    esac
    shift
done
select_tests "$committed" "$quiet" "${base:-origin/main}"
