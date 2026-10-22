# shellcheck shell=bash
# haseen's interface language for the desktop notifications bash commands
# send (plan 109). Source after common.sh.
#
#   notify-send -a haseen "$(i18n "Screensaver enabled")"
#   notify-send -a haseen "$(i18n "Reminder set for %1" "$at")" "$message"
#   notify-send -a haseen "$(i18n_n "%1 reminder" "%1 reminders" "$n")"
#
# Only what a notification shows goes through here. A command's terminal
# output, errors and --help stay English: terminals rarely shape Arabic or
# lay it out right to left, and English errors are what a search finds.
#
# The language is the one `haseen language` wrote to
# $HASEEN_USER_CONFIG/language, as the shell reads it (Haseen/I18n.qml).
# Strings are keyed by their English in $HASEEN_PATH/i18n/<code>/notify.json;
# a missing catalog, string or jq leaves the English. tools/i18n.py collects
# every literal `i18n "…"` and `i18n_n "…" "…"` into the English catalog, so
# the text must be one literal with no expansion: pass values as %1..%9.

# i18n_requested FILE — the code a language file asks for: its first line
# without one leading UTF-8 BOM, one trailing CR (a file saved with CRLF) and
# surrounding spaces and tabs, in that order; nothing else. Haseen/I18n.qml
# (requestedCode) does exactly the same, so a hand-edited file means the same
# language to the shell, to notifications and to `haseen language`.
i18n_requested() {
    local line=""
    [[ -r $1 ]] && IFS= read -r line <"$1" || true
    line=${line#$'\xef\xbb\xbf'}
    line=${line%$'\r'}
    line=${line#"${line%%[!$' \t']*}"}
    line=${line%"${line##*[!$' \t']}"}
    printf '%s\n' "$line"
}

# The interface language code ("en" when none is set or it is unknown).
i18n_language() {
    local code
    code="$(i18n_requested "$HASEEN_USER_CONFIG/language")"
    if [[ $code =~ ^[a-z]{2,3}$ && $code != en && -r $HASEEN_PATH/i18n/$code/notify.json ]]; then
        printf '%s\n' "$code"
    else
        printf 'en\n'
    fi
}

# _i18n_fill TEXT ARGS… — %1..%9 replaced in one pass, without jq.
_i18n_fill() {
    local text=$1 out="" head digit
    shift
    while [[ $text == *%[1-9]* ]]; do
        head=${text%%%[1-9]*}
        digit=${text:${#head}+1:1}
        text=${text:${#head}+2}
        out+=$head
        if ((digit <= $#)); then
            out+=${!digit}
        else
            out+=%$digit
        fi
    done
    printf '%s\n' "$out$text"
}

# _i18n_lookup KEY COUNT ARGS… — the catalog's form for KEY (COUNT empty for
# a plain string), filled; prints nothing when there is none. `--` ends jq's
# options, so an argument such as "-n" or "--help" stays a value.
_i18n_lookup() {
    local key=$1 count=$2 lang
    shift 2
    lang="$(i18n_language)"
    [[ $lang != en ]] && command -v jq >/dev/null 2>&1 || return 0
    jq -r --arg key "$key" --arg count "$count" --arg lang "$lang" '
        def category($n):
            if $n != ($n | floor) then "other"
            elif $lang == "ar" then
                if $n <= 2 then ["zero", "one", "two"][$n]
                elif ($n % 100) >= 3 and ($n % 100) <= 10 then "few"
                elif ($n % 100) >= 11 then "many"
                else "other" end
            elif $n == 1 then "one" else "other" end;
        .[$key] as $value
        | (if ($value | type) == "object" then
              ($count | tonumber? // 0 | fabs) as $n | ($value[category($n)] // $value.other)
           else $value end) as $text
        | if ($text | type) == "string" and $text != "" then
              $text | gsub("%(?<d>[1-9])"; (.d | tonumber) as $i | ($ARGS.positional[$i - 1] // ("%" + .d)))
          else empty end
    ' "$HASEEN_PATH/i18n/$lang/notify.json" --args -- "$@" 2>/dev/null || true
}

# i18n TEXT [ARG…] — TEXT in the interface language, %1..%9 filled.
i18n() {
    local text=$1 out
    shift
    out="$(_i18n_lookup "$text" "" "$@")"
    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    else
        _i18n_fill "$text" "$@"
    fi
}

# i18n_n SINGULAR PLURAL COUNT [ARG…] — the counted form; %1 is COUNT, %2..
# the further arguments. PLURAL is the catalog key.
i18n_n() {
    local one=$1 other=$2 count=$3 out
    shift 3
    out="$(_i18n_lookup "$other" "$count" "$count" "$@")"
    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    elif [[ $count == 1 ]]; then
        _i18n_fill "$one" "$count" "$@"
    else
        _i18n_fill "$other" "$count" "$@"
    fi
}
