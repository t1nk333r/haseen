# shellcheck shell=bash
# omarchy/themed/lib.sh — shared by haseen's answers to Omarchy's theme
# helpers (omarchy-theme-color, -osc, -set-<app>; plan 093). Sourced after
# ../lib.sh, never executed.
#
# Omarchy renders one file per app into current/theme at every theme set
# (claude.json, pi.json, keyboard.rgb, …) and each omarchy-theme-set-<app>
# publishes its file to the app. haseen's theme set renders only
# share/haseen/themed, so the files these commands need come from here:
#   1. current/theme/<file>, when the theme ships it or the user's template
#      ~/.config/haseen/themed/<file>.tpl rendered it at theme set;
#   2. else the user's template, else the template in this directory,
#      rendered from current/theme/colors.toml by haseen's own renderer
#      (theme_render_templates) into a private scratch directory.
# The templates here are Omarchy's default/themed ones (MIT, Copyright (c)
# David Heinemeier Hansson); the themes they publish are named haseen.

[[ -n ${HASEEN_OMARCHY_THEMED_LIB:-} ]] && return 0
HASEEN_OMARCHY_THEMED_LIB=1

# shellcheck source=../../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

OMARCHY_THEMED_DIR="$HASEEN_OMARCHY_DIR/themed"
OMARCHY_THEMED_SCRATCH=""

omarchy_themed_cleanup() {
    if [[ -n $OMARCHY_THEMED_SCRATCH ]]; then rm -rf -- "$OMARCHY_THEMED_SCRATCH"; fi
}

# omarchy_themed_scratch — REPLY = a private scratch directory, removed when
# the command exits. A renderer's output is never left in a shared place.
omarchy_themed_scratch() {
    if [[ -z $OMARCHY_THEMED_SCRATCH ]]; then
        OMARCHY_THEMED_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/haseen-omarchy-theme.XXXXXX")"
        trap omarchy_themed_cleanup EXIT
    fi
    REPLY=$OMARCHY_THEMED_SCRATCH
}

# omarchy_theme_file NAME — REPLY = the current theme's NAME (claude.json,
# keyboard.rgb, …): the copy in current/theme, else NAME rendered from the
# current colors.toml. Returns 1 when there is no current theme to render
# from or no template for NAME.
omarchy_theme_file() {
    local name="$1" colors="$THEME_CURRENT_PATH/colors.toml" tpl dir
    REPLY=""
    if [[ -f $THEME_CURRENT_PATH/$name ]]; then
        REPLY="$THEME_CURRENT_PATH/$name"
        return 0
    fi
    [[ -f $colors ]] || return 1
    tpl="$THEME_USER_TEMPLATES_DIR/$name.tpl"
    [[ -f $tpl ]] || tpl="$OMARCHY_THEMED_DIR/$name.tpl"
    [[ -f $tpl ]] || return 1
    omarchy_themed_scratch
    dir="$REPLY/render-$name"
    rm -rf -- "$dir"
    mkdir -p "$dir/theme" "$dir/templates" "$dir/none"
    cp -- "$colors" "$dir/theme/colors.toml"
    # The mode falls back to a light.mode marker beside colors.toml.
    if [[ -e $THEME_CURRENT_PATH/light.mode ]]; then : >"$dir/theme/light.mode"; fi
    cp -- "$tpl" "$dir/templates/$name.tpl"
    # A subshell: the renderer reads its template dirs from these globals.
    (
        THEME_TEMPLATES_DIR="$dir/templates"
        THEME_USER_TEMPLATES_DIR="$dir/none"
        theme_render_templates "$dir/theme"
    ) || return 1
    [[ -f $dir/theme/$name ]] || return 1
    REPLY="$dir/theme/$name"
}

# omarchy_unresolved FILE — FILE still holds a {{ placeholder }}: the theme
# lacks a key the template uses. Publishing it would hand the app a file it
# rejects, so callers keep the previous one instead (omarchy-theme-set-t3code).
omarchy_unresolved() { grep -q '{{' -- "$1"; }

# omarchy_publish SRC DEST — copy SRC over DEST atomically (a temporary file
# beside DEST, then a rename): the apps watch these files and would read a
# half-written one as invalid. Under --dry-run prints the content instead.
omarchy_publish() {
    local src="$1" dest="$2" tmp lines
    if $DRY_RUN; then
        lines="$(wc -l <"$src")"
        if ((lines <= 200)); then
            echo "DRYRUN: write $dest:"
            sed 's/^/    | /' -- "$src"
        else
            echo "DRYRUN: write $dest ($lines lines rendered from the current theme)"
        fi
        return 0
    fi
    mkdir -p -- "$(dirname -- "$dest")" || return 1
    tmp="$(mktemp "$dest.XXXXXX")" || return 1
    if ! cp -- "$src" "$tmp" || ! mv -fT -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}

# omarchy_json_set FILE JQ_FILTER [JQ_ARGS...] — rewrite the JSON FILE through
# jq, atomically; a file jq cannot parse is left untouched and fails. Only
# commands acting on an explicit flag (--activate) call this on an app's own
# settings: haseen never edits them by default.
omarchy_json_set() {
    local file="$1" filter="$2" out
    shift 2
    out="$(jq "$@" "$filter" "$file")" || return 1
    printf '%s\n' "$out" | replace_user_file "$file"
}

# omarchy_theme_osc FILE — print the OSC 10/11/12/17/19 and 4;0-15 sequences
# for a colors.toml (Omarchy bin/omarchy-theme-osc), resolved by haseen's
# parser; nothing when FILE is missing.
omarchy_theme_osc() {
    local key i
    theme_colors_load "$1" || return 0
    for key in 10:foreground 11:background 12:cursor 17:selection_background 19:selection_foreground; do
        if [[ -n ${THEME_COLORS[${key#*:}]:-} ]]; then
            printf '\033]%s;%s\007' "${key%%:*}" "${THEME_COLORS[${key#*:}]}"
        fi
    done
    for i in {0..15}; do
        if [[ -n ${THEME_COLORS[color$i]:-} ]]; then
            printf '\033]4;%d;%s\007' "$i" "${THEME_COLORS[color$i]}"
        fi
    done
    return 0
}

# omarchy_tty_write TTY DATA — send escape sequences to a terminal another
# process owns. A dry run names the terminal instead.
omarchy_tty_write() {
    if $DRY_RUN; then
        echo "DRYRUN: write the theme palette (OSC sequences) to $1"
        return 0
    fi
    printf '%s' "$2" >"$1" 2>/dev/null || true
}

# omarchy_run_quiet CMD... — run CMD with its output discarded (an app's own
# chatter); a dry run still prints the command.
omarchy_run_quiet() {
    if $DRY_RUN; then
        echo "DRYRUN: $*"
        return 0
    fi
    "$@" &>/dev/null
}
