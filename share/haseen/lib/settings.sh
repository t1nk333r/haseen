# shellcheck shell=bash
# settings.sh — the index of every haseen setting, where it is stored and
# which command changes it. Sourced, never executed.
#
# haseen keeps settings in six places on purpose, and this file is the map,
# not a seventh place. Nothing here owns state; every row points at the
# command that already does.
#
#   shell.json   ~/.config/haseen/shell.json, merged over the shipped default;
#                a plugin's settings fall back to its manifest's defaults.
#                User-authored, watched by the shell. Commands avoid rewriting
#                it so a hand-edited file keeps its shape.
#   config       other one-value files under ~/.config/haseen (the mono font),
#                each owned by one command and read by the theme render.
#   flag         ~/.local/state/haseen/flags/<name>: the file existing means on.
#                Session state (do-not-disturb, recording), not configuration:
#                it must not survive into a config file the user edits, and the
#                shell watches each file individually (qs.Haseen.Flags).
#   hypr-toggle  ~/.local/state/haseen/toggles/hypr/<name>.lua, included by
#                share/haseen/default/hypr/init.lua. Hyprland reads Lua, so a
#                JSON setting would have to be re-emitted as Lua on every
#                change; the Lua file is the setting.
#   state        other files under ~/.local/state/haseen (active shell, the
#                remembered power profile per source, the current theme).
#   env          ~/.config/uwsm/env.d/60-haseen-defaults, read by the next
#                login and pushed into the running systemd user manager.
#
# Row format, tab separated:
#   key \t store \t location \t value \t setter
# `value` is resolved when the row is produced; `setter` is the command line
# that changes it, with the new value appended.

[[ -n ${HASEEN_SETTINGS_SH:-} ]] && return 0
HASEEN_SETTINGS_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Where the sibling commands live: share/haseen/lib -> <prefix>/bin. Works for
# the checkout, /usr/local and /usr alike, and does not depend on the router
# having exported PATH.
HASEEN_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../bin" && pwd)"
# The defaults env file is uwsm's, not haseen's own config dir.
HASEEN_DEFAULTS_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/60-haseen-defaults"

# _settings_json PATH DEFAULT — a value from the merged shell.json. PATH is a
# jq path; false and 0 are values, only an absent key falls through. Objects
# and arrays print as compact JSON.
_settings_json() {
    local user="$HASEEN_USER_CONFIG/shell.json" def="$HASEEN_PATH/default/shell.json" v=""
    local pick="($1) | select(. != null) | if type == \"string\" then . else tojson end"
    have jq || {
        printf '%s' "$2"
        return 0
    }
    [[ -r $user ]] && v="$(jq -r "$pick" "$user" 2>/dev/null || true)"
    [[ -n $v ]] || { [[ -r $def ]] && v="$(jq -r "$pick" "$def" 2>/dev/null || true)"; }
    printf '%s' "${v:-$2}"
}

# _settings_plugin ID KEY — a plugin setting: the user's shell.json, else the
# shipped one, else the plugin manifest's default.
_settings_plugin() {
    local manifest="$HASEEN_PATH/shell/plugins/$1/manifest.json" v
    v="$(_settings_json ".plugins[\"$1\"].settings[\"$2\"]" "")"
    if [[ -z $v ]] && have jq && [[ -r $manifest ]]; then
        v="$(jq -r --arg k "$2" '.settings[$k].default | select(. != null) | if type == "string" then . else tojson end' "$manifest" 2>/dev/null || true)"
    fi
    printf '%s' "$v"
}

# _settings_flag NAME — on when the flag file exists.
_settings_flag() {
    [[ -e $HASEEN_USER_STATE/flags/$1 ]] && printf 'on' || printf 'off'
}

# _settings_toggle NAME — on when the Hyprland toggle file exists.
_settings_toggle() {
    [[ -e $HASEEN_USER_STATE/toggles/hypr/$1.lua ]] && printf 'on' || printf 'off'
}

# _settings_file PATH DEFAULT — the first line of PATH, or DEFAULT.
_settings_file() {
    local v=""
    [[ -r $1 ]] && IFS= read -r v <"$1"
    printf '%s' "${v:-$2}"
}

# _settings_row KEY STORE LOCATION VALUE SETTER
# No field may be empty: the readers split on tab, and bash collapses runs of
# whitespace delimiters, so an empty value would shift every later column.
_settings_row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-(unset)}" "${5:-(read-only)}"; }

# settings_rows — every setting, in display order.
settings_rows() {
    local state="$HASEEN_USER_STATE"

    _settings_row theme state "$state/current/theme.name" \
        "$(_settings_file "$state/current/theme.name" "(none)")" "haseen theme set"
    _settings_row font.mono config "$HASEEN_USER_CONFIG/font" \
        "$(_settings_file "$HASEEN_USER_CONFIG/font" "(theme default)")" "haseen font set"
    _settings_row shell state "$state/active-shell" \
        "$(_settings_file "$state/active-shell" haseen)" "haseen shell use"

    _settings_row bar.position shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .bar.position top)" "haseen shell ipc bar position"
    _settings_row bar.height shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .bar.height 28)" "haseen config edit $HASEEN_USER_CONFIG/shell.json"
    _settings_row bar.transparent shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .bar.transparent false)" "haseen shell ipc bar transparent"
    _settings_row frame.enabled shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .frame.enabled true)" "haseen config edit $HASEEN_USER_CONFIG/shell.json"
    _settings_row frame.thickness shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .frame.thickness 6)" "haseen config edit $HASEEN_USER_CONFIG/shell.json"
    # Unset means twice the theme's radius (qs.Haseen Config.frameRadius).
    # Windows and the menu share it from the next `haseen theme set` (plan 046).
    _settings_row frame.radius shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_json .frame.radius "(theme radius x2)")" "haseen config edit $HASEEN_USER_CONFIG/shell.json"

    # Plugin settings a user is likely to look for: the battery warnings
    # (plan 075), the lock-key OSD (079), idle suspend (082), the clock's day
    # name (085), the clipboard preview (042) and the screensaver style,
    # the one with a command of its own. The rest are in each manifest
    # (`haseen plugin info <id>`).
    local plugin_key
    for plugin_key in haseen.battery:warnAt haseen.battery:criticalAt haseen.battery:criticalAction \
        haseen.osd:lockKeys haseen.idle:suspendAfter haseen.idle:onBattery \
        haseen.clock:showDayName haseen.clipboard:preview; do
        _settings_row "${plugin_key%%:*}.${plugin_key#*:}" shell.json "$HASEEN_USER_CONFIG/shell.json" \
            "$(_settings_plugin "${plugin_key%%:*}" "${plugin_key#*:}")" "haseen config edit $HASEEN_USER_CONFIG/shell.json"
    done
    _settings_row haseen.screensaver.style shell.json "$HASEEN_USER_CONFIG/shell.json" \
        "$(_settings_plugin haseen.screensaver style)" "haseen screensaver style"

    _settings_row dnd flag "$state/flags/dnd" "$(_settings_flag dnd)" "haseen toggle dnd"
    _settings_row idle flag "$state/flags/idle-off" \
        "$([[ $(_settings_flag idle-off) == on ]] && echo off || echo on)" "haseen toggle idle"
    _settings_row screensaver flag "$state/flags/screensaver-off" \
        "$([[ $(_settings_flag screensaver-off) == on ]] && echo off || echo on)" "haseen toggle screensaver"
    _settings_row nightlight flag "$state/flags/nightlight" \
        "$(_settings_flag nightlight)" "haseen toggle nightlight"
    _settings_row recording flag "$state/flags/recording" \
        "$(_settings_flag recording)" "haseen capture screenrecord"

    # The Hyprland toggles are stored inverted (the file turns the default
    # off), so the reported value is the user-facing one.
    _settings_row gaps hypr-toggle "$state/toggles/hypr/no-gaps.lua" \
        "$([[ $(_settings_toggle no-gaps) == on ]] && echo off || echo on)" "haseen toggle gaps"
    _settings_row animations hypr-toggle "$state/toggles/hypr/no-animations.lua" \
        "$([[ $(_settings_toggle no-animations) == on ]] && echo off || echo on)" "haseen toggle animations"
    _settings_row one-window-ratio hypr-toggle "$state/toggles/hypr/single-window-aspect-ratio.lua" \
        "$(_settings_toggle single-window-aspect-ratio)" "haseen toggle one-window-ratio"

    local kind
    for kind in browser terminal editor agent; do
        _settings_row "default.$kind" env "$HASEEN_DEFAULTS_ENV" \
            "$("$HASEEN_BIN_DIR/haseen-setup-default" "$kind" 2>/dev/null || echo '(unset)')" \
            "haseen setup default $kind"
    done
}

# settings_setter KEY — the command line that changes KEY, or failure.
settings_setter() {
    local key setter
    while IFS=$'\t' read -r key _ _ _ setter; do
        [[ $key == "$1" ]] || continue
        printf '%s\n' "$setter"
        return 0
    done < <(settings_rows)
    return 1
}
