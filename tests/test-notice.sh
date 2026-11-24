# shellcheck shell=bash
# haseen:covers NOTICE.md
# haseen:scans bin/** share/** install.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The licence rule (AGENTS.md): code adapted from Omarchy or DankMaterialShell
# keeps the upstream notice in its file header and has a row in NOTICE.md.
# Every file whose leading comments say it was adapted, ported, copied, taken
# or derived from either one must be named in NOTICE.md's Where column (plan
# 201: haseen.imagepicker, init.lua, input.lua, greeter.sh and two seeds had
# their header notice and no row).

sandbox notice

# notice_regexes NOTICE — one anchored ERE per path in the Where column (the
# last cell of every table row): {a,b} is either, * stays inside a segment and
# a trailing / takes everything below. Backticked words without a / (function
# names, commit ids) are not paths.
notice_regexes() {
    awk -F'|' '/^\| / && NF > 3 { print $(NF - 1) }' "$1" | grep -oE '`[^`]+`' | tr -d '`' |
        grep -E '^[A-Za-z0-9_./{},*+-]*/[A-Za-z0-9_./{},*+-]*$' |
        awk '{
            re = $0
            gsub(/\./, "[.]", re); gsub(/\+/, "[+]", re); gsub(/\*/, "[^/]*", re)
            gsub(/\{/, "(", re); gsub(/\}/, ")", re); gsub(/,/, "|", re)
            print "^" re (re ~ /\/$/ ? ".*" : "") "$"
        }' | sort -u
}

# adapted_files ROOT PATH... — the files under ROOT/PATH... (relative to ROOT)
# whose first 60 lines, comment markers stripped, say they were adapted from
# Omarchy or DankMaterialShell. Symbolic links are the dispatcher's names, not
# code of their own.
adapted_files() {
    local root=$1
    shift
    (cd "$root" && find "$@" -type f -print0 2>/dev/null) | (cd "$root" && LC_ALL=C xargs -0 -r awk '
        function judge() {
            if (text ~ /(adapted|ported|copied|taken|derived)[[:space:]]+from[[:space:]]+(the[[:space:]]+)?(omarchy|dms|dankmaterialshell)/)
                print prev
        }
        FNR == 1 { if (prev != "") judge(); prev = FILENAME; text = "" }
        FNR > 60 { nextfile }
        {
            line = $0
            sub(/^[[:space:]]*(#+|\/\/+|--+|\/?\*+|;+)[[:space:]]?/, "", line)
            text = text " " tolower(line)
        }
        END { if (prev != "") judge() }
    ') | sort -u
}

# unlisted REGEXES FILES — the files no regex matches.
unlisted() {
    awk 'FILENAME == ARGV[1] { re[++n] = $0; next }
        { for (i = 1; i <= n; i++) if ($0 ~ re[i]) next; print }' "$1" "$2"
}

# --- the checker itself, on a small tree ------------------------------------------
T="$SANDBOX/tree"
mkdir -p "$T/share/x/plugins/haseen.listed" "$T/share/x/lib" "$T/bin"
printf '// Adapted from Omarchy shell/plugins/thing (MIT)\n' >"$T/share/x/plugins/haseen.listed/A.qml"
printf '#!/usr/bin/env bash\n# The shape is adapted\n# from DankMaterialShell (MIT).\n' >"$T/share/x/lib/split.sh"
printf -- '-- The rule is ported\n-- from Omarchy default/hypr/input.lua.\n' >"$T/share/x/lib/rule.lua"
printf '#!/usr/bin/env bash\n# Adapted from Omarchy bin/thing.\n' >"$T/bin/haseen-thing-a"
printf '#!/usr/bin/env bash\n# Adapted from Omarchy bin/thing.\n' >"$T/bin/haseen-thing-b"
printf '#!/usr/bin/env bash\n# Our own code; Omarchy does this differently.\n' >"$T/bin/haseen-own"
ln -s haseen-thing-a "$T/bin/omarchy-thing"
cat >"$T/NOTICE.md" <<'MD'
| Upstream | License | Copyright | What | Where |
|---|---|---|---|---|
| omarchy | MIT | x | thing | `share/x/plugins/haseen.listed/`, `bin/haseen-thing-{a,c}` (`run_it`) |
| dms | MIT | x | shape | `share/x/lib/*.sh` |
MD
notice_regexes "$T/NOTICE.md" >"$SANDBOX/re-small"
adapted_files "$T" bin share >"$SANDBOX/adapted-small"
assert_eq "the scan reads comment markers across lines and skips links and own code" \
    "bin/haseen-thing-a bin/haseen-thing-b share/x/lib/rule.lua share/x/lib/split.sh share/x/plugins/haseen.listed/A.qml" \
    "$(paste -sd' ' "$SANDBOX/adapted-small")"
assert_eq "a file in no Where cell is reported; braces, globs and directories match" \
    "bin/haseen-thing-b share/x/lib/rule.lua" \
    "$(unlisted "$SANDBOX/re-small" "$SANDBOX/adapted-small" | paste -sd' ')"

# --- this repository ---------------------------------------------------------------
notice_regexes "$REPO/NOTICE.md" >"$SANDBOX/re"
adapted_files "$REPO" bin share install.sh >"$SANDBOX/adapted"
n="$(wc -l <"$SANDBOX/adapted")"
assert_eq "the scan finds the adapted files (themes, ports, the compat host)" yes "$( ((n > 100)) && echo yes || echo "no: $n")"
assert_eq "every file adapted from Omarchy or DankMaterialShell has a NOTICE.md row" "" \
    "$(unlisted "$SANDBOX/re" "$SANDBOX/adapted")"
