# shellcheck shell=bash
# gestures.sh — touchpad gestures for haseen.gestures. Sourced, never executed.
#
# Adapted from omagesture's omagesture-apply (github.com/heroesofcode/omagesture,
# MIT, Copyright (c) 2026 Pedro Henrique). Upstream keeps its defaults in three
# places (manifest, Model.js, the script) and writes ~/.config/hypr/omagesture.lua,
# then appends a require block to the user's hyprland.lua. Here:
#   - the defaults live only in the plugin manifest, which the shell already
#     merges with shell.json (architecture 5.2), so the panel, this renderer
#     and a fresh install cannot disagree;
#   - the Lua goes to $HASEEN_USER_STATE/toggles/hypr/gestures.lua, which
#     default/hypr/init.lua already loads, so no user file is ever edited;
#   - Omarchy commands are replaced by haseen ones (menu, screenshot) and the
#     middle-click "paste" action is dropped: it ran `wl-paste --primary` from
#     a bind, which prints the selection to nowhere and pastes nothing.
#
# Every value that reaches the Lua is checked against a fixed list first, so a
# hand-edited shell.json cannot inject code into the compositor config.

[[ -n ${HASEEN_GESTURES_SH:-} ]] && return 0
HASEEN_GESTURES_SH=1

# shellcheck source=../shell/lib/plugin.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shell/lib/plugin.sh"

GESTURES_ID=haseen.gestures
GESTURES_MANIFEST="$HASEEN_PATH/shell/plugins/$GESTURES_ID/manifest.json"
GESTURES_TOGGLE="$HASEEN_USER_STATE/toggles/hypr/gestures.lua"
# The flag the bar widget shows itself for (qs.Haseen.Flags). The hardware
# quirk (share/haseen/hardware/gestures.sh) writes it when the machine has a
# touchpad.
# shellcheck disable=SC2034 # read by the quirk body that sources this file
GESTURES_FLAG="$HASEEN_USER_STATE/flags/gestures"
# The Omarchy original, which haseen's compat layer can still load from
# ~/.config/omarchy/plugins/ (read-only, never touched here).
GESTURES_UPSTREAM_ID=io.github.heroesofcode.omagesture

# What each key accepts. Keys absent here are booleans (enabled, naturalScroll,
# swipeForever); every g<fingers><direction> key takes an action.
# shellcheck disable=SC2016 # jq source, not shell
GESTURES_JQ_VALID='
    def choices: {
        clickMethod: ["clickfinger", "buttonareas"],
        drag: ["off", "threefinger", "fourfinger"],
        middleButton: ["none", "resize", "move", "screenshot"],
        swipeRange: ["numbered", "existing"],
        action: ["none", "workspace", "special", "fullscreen", "maximize", "float",
                 "move_window", "resize_window", "close_window", "zoom", "menu"]
    };
    def valid($k; $v):
        if ($k | test("^g[234]")) then ($v | type == "string") and (choices.action | index([$v]) != null)
        elif choices | has($k) then ($v | type == "string") and (choices[$k] | index([$v]) != null)
        else ($v | type == "boolean") end;
'

# gestures_defaults — the manifest's defaults as one object.
gestures_defaults() {
    [[ -r $GESTURES_MANIFEST ]] || die "missing $GESTURES_MANIFEST"
    jq -c '.settings | map_values(.default)' "$GESTURES_MANIFEST"
}

# gestures_check_patch JSON — dies unless JSON is an object of known keys with
# accepted values. The panel's --set path, so a typo fails loudly.
gestures_check_patch() {
    local patch="$1" defaults bad
    jq -e 'type == "object"' <<<"$patch" >/dev/null 2>&1 || die "gesture settings must be a JSON object"
    defaults="$(gestures_defaults)"
    bad="$(jq -r --argjson d "$defaults" "$GESTURES_JQ_VALID"'
        to_entries[] | .key as $k | select(($d | has($k) | not) or (valid($k; .value) | not))
        | "\($k)=\(.value | tojson)"' <<<"$patch")"
    [[ -z $bad ]] || die "invalid gesture setting: ${bad//$'\n'/, } (haseen gestures apply --help)"
}

# gestures_settings [MERGED_SHELL_JSON] — every key resolved: manifest
# defaults, then plugins."haseen.gestures".settings from the merged shell.json
# (default file merged with the user's, the same rule as the shell; read from
# disk unless given). A value the renderer does not accept falls back to the
# default with a warning, so one bad edit never loses the whole mapping.
gestures_settings() {
    local defaults merged resolved
    defaults="$(gestures_defaults)"
    merged="${1:-$(shell_merged_json)}"
    merged="$(jq -c --arg id "$GESTURES_ID" '.plugins[$id].settings // {} | if type == "object" then . else {} end' <<<"$merged")"
    resolved="$(jq -c --argjson d "$defaults" --argjson s "$merged" -n "$GESTURES_JQ_VALID"'
        $d | with_entries(.key as $k
            | if ($s | has($k)) and valid($k; $s[$k]) then .value = $s[$k] else . end)')"
    jq -r --argjson s "$merged" -n "$GESTURES_JQ_VALID"'
        $s | to_entries[] | select(valid(.key; .value) | not)
        | "\(.key)=\(.value | tojson)"' 2>/dev/null |
        while IFS= read -r bad; do
            warn "gestures: ignoring unsupported setting $bad; using the default"
        done
    printf '%s\n' "$resolved"
}

# gestures_render SETTINGS_JSON — the Hyprland Lua for those settings.
gestures_render() {
    local settings="$1" key value
    declare -A S=()
    while IFS=$'\t' read -r key value; do
        S[$key]="$value"
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value | tostring)"' <<<"$settings")

    local -a out=()
    emit() { out+=("$1"); }
    action() { printf '%s\n' "${S[g$1$2]:-none}"; }

    emit "-- Written by \`haseen gestures apply\` (plugin $GESTURES_ID). Every apply rewrites"
    emit "-- it from plugins.\"$GESTURES_ID\".settings in shell.json and the plugin's"
    emit "-- defaults: change the mapping from the gestures panel in the bar, or run"
    emit "--   haseen gestures apply --set '{\"g3Up\":\"menu\"}'"
    emit ""
    [[ ${S[enabled]} == true ]] || emit "-- Gestures are off. The touchpad tuning below still applies."

    # --- touchpad tuning (loads after default/hypr/input.lua, so it wins) ---
    local click=false drag=0
    [[ ${S[clickMethod]} == clickfinger ]] && click=true
    case "${S[drag]}" in
    threefinger) drag=1 ;;
    fourfinger) drag=2 ;;
    esac

    mapped() { # FINGERS — any swipe or pinch of that finger count is mapped
        local d
        for d in Left Right Up Down PinchIn PinchOut; do
            [[ $(action "$1" "$d") != none ]] && return 0
        done
        return 1
    }
    # libinput gives a multi-finger contact to the drag or to the swipe, never
    # both: asking for both would be config that silently does nothing.
    if [[ ${S[enabled]} == true ]]; then
        if ((drag == 1)) && mapped 3; then
            emit "-- NOTE: three-finger drag dropped: three-finger swipes are mapped, and"
            emit "-- libinput can only give those fingers to one of the two."
            drag=0
        elif ((drag == 2)) && mapped 4; then
            emit "-- NOTE: four-finger drag dropped: four-finger swipes are mapped."
            drag=0
        fi
    fi
    emit "hl.config({ input = { touchpad = { natural_scroll = ${S[naturalScroll]}, clickfinger_behavior = $click, drag_3fg = $drag } } })"
    # The touchpad block is what libinput touchpads read; the global one covers
    # an external mouse, so the scroll direction is the same on both.
    emit "hl.config({ input = { natural_scroll = ${S[naturalScroll]} } })"
    # `r` targets workspaces by number, so a swipe keeps going to 4, 5, 6 even
    # while they are empty; Hyprland's default `m` stops one past the last
    # open workspace.
    local use_r=true
    [[ ${S[swipeRange]} == existing ]] && use_r=false
    emit "hl.config({ gestures = { workspace_swipe_use_r = $use_r, workspace_swipe_forever = ${S[swipeForever]} } })"
    emit ""

    local fingers dir needs_once=false needs_resize=false
    if [[ ${S[enabled]} == true ]]; then
        for fingers in 2 3 4; do
            for dir in Left Right Up Down PinchIn PinchOut; do
                case "$(action "$fingers" "$dir")" in
                menu) needs_once=true ;;
                resize_window) needs_resize=true ;;
                esac
            done
        done
    fi

    # Native gesture actions animate under the fingers. A command has to fire
    # once per swipe instead of once per motion event, so it accumulates
    # travel and latches until the fingers lift.
    if $needs_once; then
        emit 'local function haseen_gesture_once(threshold, run)'
        emit '  local travel, fired = 0, false'
        emit '  local function step(event)'
        emit '    if fired then return end'
        emit '    local d = event and event.delta'
        emit '    travel = travel + math.abs((d and d.x) or 0) + math.abs((d and d.y) or 0)'
        emit '    if travel >= threshold then'
        emit '      fired = true'
        emit '      run()'
        emit '    end'
        emit '  end'
        emit '  return {'
        emit '    start = function(e) travel, fired = 0, false; step(e) end,'
        emit '    update = step,'
        emit '    finish = function() travel, fired = 0, false end,'
        emit '  }'
        emit 'end'
        emit ''
    fi
    # Hyprland's native `resize` gesture action registers but leaves tiled
    # windows untouched (measured upstream); the relative resize dispatcher
    # behind SUPER + right-drag moves the split, fed one motion delta at a
    # time so the edge follows the fingers.
    if $needs_resize; then
        emit 'local function haseen_gesture_resize(axis)'
        emit '  return {'
        emit '    start = function() end,'
        emit '    update = function(event)'
        emit '      local d = event and event.delta'
        emit '      if not d then return end'
        emit '      local dx = (axis == "x") and (d.x or 0) or 0'
        emit '      local dy = (axis == "y") and (d.y or 0) or 0'
        emit '      if dx == 0 and dy == 0 then return end'
        emit '      hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))'
        emit '    end,'
        emit '    finish = function() end,'
        emit '  }'
        emit 'end'
        emit ''
    fi

    action_lua() { # TOKEN DIRECTION — the Lua after `direction = …,`
        case "$1" in
        workspace) printf 'action = "workspace"' ;;
        move_window) printf 'action = "move"' ;;
        resize_window)
            case "$2" in
            vertical | up | down) printf 'action = haseen_gesture_resize("y")' ;;
            *) printf 'action = haseen_gesture_resize("x")' ;;
            esac
            ;;
        close_window) printf 'action = "close"' ;;
        fullscreen) printf 'action = "fullscreen"' ;;
        maximize) printf 'action = "fullscreen", mode = "maximize"' ;;
        float) printf 'action = "float"' ;;
        # haseen's scratchpad (SUPER + S in default/hypr/binds.lua), not
        # upstream's "magic", so the gesture and the key open the same one.
        special) printf 'action = "special", workspace_name = "scratchpad"' ;;
        zoom) printf 'action = "cursorZoom", zoom_level = 2' ;;
        # Upstream opened omarchy-menu; haseen's menu is the same role.
        menu) printf 'action = haseen_gesture_once(40, function() hl.dispatch(hl.dsp.exec_cmd("haseen menu")) end)' ;;
        esac
    }
    gesture() { # FINGERS DIRECTION TOKEN
        local body
        body="$(action_lua "$3" "$2")"
        [[ -n $body ]] || return 0
        emit "hl.gesture({ fingers = $1, direction = \"$2\", $body })"
    }

    local axis combined lo hi a b
    if [[ ${S[enabled]} == true ]]; then
        for fingers in 2 3 4; do
            # Hyprland refuses a gesture another one already shadows, so an
            # axis is claimed either as the combined direction or as its two
            # halves, never both. Matching halves collapse into the combined
            # form, the only one that follows the fingers continuously.
            for axis in horizontal:Left:Right vertical:Up:Down pinch:PinchIn:PinchOut; do
                IFS=: read -r combined lo hi <<<"$axis"
                a="$(action "$fingers" "$lo")"
                b="$(action "$fingers" "$hi")"
                if [[ $a == "$b" && $a != none ]]; then
                    gesture "$fingers" "$combined" "$a"
                else
                    gesture "$fingers" "${lo,,}" "$a"
                    gesture "$fingers" "${hi,,}" "$b"
                fi
            done
        done
    fi

    # Under clickfinger the middle button is a three-finger click. move and
    # resize are drag binds: the button is held, so libinput reports pointer
    # motion, never a gesture, and they do not collide with the swipes.
    case "${S[middleButton]}" in
    move)
        emit ""
        emit 'hl.bind("mouse:274", hl.dsp.window.drag(), { mouse = true, description = "Three-finger click and drag moves the window" })'
        ;;
    resize)
        emit ""
        emit 'hl.bind("mouse:274", hl.dsp.window.resize(), { mouse = true, description = "Three-finger click and drag resizes the window" })'
        ;;
    screenshot)
        emit ""
        emit 'hl.bind("mouse:274", hl.dsp.exec_cmd("haseen capture screenshot region"), { description = "Three-finger click takes a region screenshot" })'
        ;;
    esac

    printf '%s\n' "${out[@]}"
    unset -f emit action mapped action_lua gesture
}

# gestures_write LUA — write the toggle when its content changes. Exit 0 when
# it was (or, with --dry-run, would be) written, 1 when it is already current.
gestures_write() {
    local lua="$1"
    if [[ -r $GESTURES_TOGGLE && "$(<"$GESTURES_TOGGLE")" == "$lua" ]]; then
        return 1
    fi
    printf '%s\n' "$lua" | write_user_file "$GESTURES_TOGGLE"
}

# gestures_reload — gestures cannot be unregistered, so a changed file needs a
# config reload. Outside a Hyprland session there is nothing to reload: the
# file loads at the next login.
gestures_reload() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
    if $DRY_RUN; then
        run hyprctl reload
    else
        hyprctl reload >/dev/null || warn "gestures: hyprctl reload failed; the change applies at the next reload"
    fi
}

# gestures_check_upstream MERGED_SHELL_JSON — warn when the Omarchy original
# would register the same gestures a second time. Hyprland keeps the first
# registration of an axis and reports the second as overshadowed, so the two
# must not both run. Read-only: the Omarchy plugin directory and the user's
# hyprland.lua are only looked at.
gestures_check_upstream() {
    local hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    if jq -e --arg id "$GESTURES_UPSTREAM_ID" \
        '([(.bar.left // []), (.bar.center // []), (.bar.right // [])] | add | index([$id]) != null)
         and .plugins[$id].enabled != false' <<<"$1" >/dev/null; then
        warn "gestures: the Omarchy plugin $GESTURES_UPSTREAM_ID is also in the bar; remove it from shell.json, $GESTURES_ID replaces it"
    fi
    if [[ -r $hypr ]] && grep -qF 'omagesture:begin' "$hypr"; then
        warn "gestures: $hypr still loads omagesture.lua (an omagesture:begin block); delete that block, $GESTURES_ID replaces it"
    fi
    return 0
}

# gestures_apply [RELOAD] [MERGED_SHELL_JSON] — render the current settings,
# write them if they changed, then reload Hyprland. The shared step of
# `haseen gestures apply` and the hardware quirk.
gestures_apply() {
    local reload="${1:-true}" merged="${2:-}" lua
    [[ -n $merged ]] || merged="$(shell_merged_json)"
    lua="$(gestures_render "$(gestures_settings "$merged")")"
    gestures_check_upstream "$merged"
    if gestures_write "$lua"; then
        $DRY_RUN || info "gestures: wrote ${GESTURES_TOGGLE/#$HOME/\~}"
        if $reload; then gestures_reload; fi
    else
        info "gestures: ${GESTURES_TOGGLE/#$HOME/\~} is already current"
    fi
}
