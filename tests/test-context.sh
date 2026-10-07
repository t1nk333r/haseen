# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen context (plan 062): each context sets the switches it names, and
# leaving it puts every switch back exactly as it was, whatever the switches
# were before; a second context replaces the first against the same record;
# the game context's Hyprland options come back to their recorded live values;
# the watcher's --auto never replaces a context picked by hand.

FLAG_NAMES=(dnd idle-off screensaver-off nightlight)

sandbox context
FLAGS_DIR="$XDG_STATE_HOME/haseen/flags"
GAME_LUA="$XDG_STATE_HOME/haseen/toggles/hypr/context-game.lua"
SAVED="$XDG_STATE_HOME/haseen/context/saved"
HLOG="$SANDBOX/hyprctl.log"
# A Hyprland that answers getoption with the values in $SANDBOX/hypr/<option>
# and logs every other call.
mkdir -p "$SANDBOX/hypr"
stub hyprctl "
if [ \"\$1\" = getoption ]; then
    v=\$(cat \"$SANDBOX/hypr/\$(echo \"\$2\" | tr : _)\" 2>/dev/null || echo true)
    printf '{\"option\": \"%s\", \"bool\": %s, \"set\": true }\n' \"\$2\" \"\$v\"
    exit 0
fi
echo \"\$*\" >>\"$HLOG\""
stub notify-send 'echo "notify-send $*" >>"'"$SANDBOX"'/notify.log"'
hypr_live() { # animations blur shadow
    echo "$1" >"$SANDBOX/hypr/animations_enabled"
    echo "$2" >"$SANDBOX/hypr/decoration_blur_enabled"
    echo "$3" >"$SANDBOX/hypr/decoration_shadow_enabled"
}
hypr_live true true true

# flags — the four switches as "dnd=1 idle-off=0 …".
flags() {
    local f out=()
    for f in "${FLAG_NAMES[@]}"; do
        out+=("$f=$([[ -e $FLAGS_DIR/$f ]] && echo 1 || echo 0)")
    done
    echo "${out[*]}"
}
# set_flags "dnd=1 idle-off=0 …" — the starting point, written directly.
set_flags() {
    local kv
    mkdir -p "$FLAGS_DIR"
    for kv in $1; do
        if [[ ${kv#*=} == 1 ]]; then : >"$FLAGS_DIR/${kv%%=*}"; else rm -f "$FLAGS_DIR/${kv%%=*}"; fi
    done
}

capture haseen context --help
assert_status "context --help" 0 "$STATUS"
assert_contains "context --help usage" "$OUTPUT" "Usage: haseen context"
assert_eq "no context is normal" "normal" "$(haseen context)"
assert_eq "status says normal" "normal" "$(haseen context status)"
capture haseen context party
assert_status "an unknown context is refused" 2 "$STATUS"
capture haseen context focus extra
assert_status "one context at a time" 2 "$STATUS"
capture haseen context present --auto
assert_status "--auto is for game and normal only" 2 "$STATUS"

# --- what each context sets ---------------------------------------------------
set_flags "dnd=0 idle-off=0 screensaver-off=0 nightlight=1"
haseen context focus >/dev/null
assert_eq "focus: notifications held, nothing else" "dnd=1 idle-off=0 screensaver-off=0 nightlight=1" "$(flags)"
assert_eq "focus: the status names it" "focus" "$(haseen context status)"
assert_eq "focus: the shell's flag holds the name" "focus" "$(cat "$FLAGS_DIR/context")"
haseen context normal >/dev/null
assert_eq "focus → normal: the flags are back" "dnd=0 idle-off=0 screensaver-off=0 nightlight=1" "$(flags)"
assert_eq "normal: the context flag is gone" "absent" "$([[ -e $FLAGS_DIR/context ]] && echo present || echo absent)"
assert_eq "normal: the record is gone" "absent" "$([[ -e $SAVED ]] && echo present || echo absent)"

haseen context present >/dev/null
assert_eq "present: notifications, idle and screensaver held; night light paused" \
    "dnd=1 idle-off=1 screensaver-off=1 nightlight=0" "$(flags)"
haseen context normal >/dev/null
assert_eq "present → normal: the night light is back on" "dnd=0 idle-off=0 screensaver-off=0 nightlight=1" "$(flags)"
assert_eq "present: the screensaver toggle sent no notification" "" "$(cat "$SANDBOX/notify.log" 2>/dev/null)"

: >"$HLOG"
haseen context game >/dev/null
assert_eq "game: notifications and the idle lock held" "dnd=1 idle-off=1 screensaver-off=0 nightlight=1" "$(flags)"
assert_contains "game: animations, blur and shadows off live" "$(cat "$HLOG")" \
    "eval hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false } } })"
assert_contains "game: the override survives a Hyprland reload" "$(cat "$GAME_LUA" 2>/dev/null)" "animations = { enabled = false }"
haseen context normal >/dev/null
assert_eq "game → normal: the flags are back" "dnd=0 idle-off=0 screensaver-off=0 nightlight=1" "$(flags)"
assert_eq "game → normal: the override file is gone" "absent" "$([[ -e $GAME_LUA ]] && echo present || echo absent)"
assert_contains "game → normal: the recorded live values come back" "$(tail -1 "$HLOG")" \
    "eval hl.config({ animations = { enabled = true }, decoration = { blur = { enabled = true }, shadow = { enabled = true } } })"

# --- every context restores every starting point exactly ----------------------
starts=(
    "dnd=0 idle-off=0 screensaver-off=0 nightlight=0"
    "dnd=1 idle-off=1 screensaver-off=1 nightlight=1"
    "dnd=1 idle-off=0 screensaver-off=1 nightlight=0"
    "dnd=0 idle-off=1 screensaver-off=0 nightlight=1"
)
for ctx in focus game present; do
    for start in "${starts[@]}"; do
        set_flags "$start"
        haseen context "$ctx" >/dev/null
        haseen context normal >/dev/null
        assert_eq "$ctx from [$start]: left exactly as found" "$start" "$(flags)"
    done
done

# Mixed live Hyprland values (blur set live by the user, not in any file).
hypr_live false true false
: >"$HLOG"
haseen context game >/dev/null
haseen context normal >/dev/null
assert_contains "game: mixed live values are restored as they were" "$(tail -1 "$HLOG")" \
    "eval hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = true }, shadow = { enabled = false } } })"
hypr_live true true true

# --- nested contexts replace against the first record --------------------------
start="dnd=0 idle-off=0 screensaver-off=1 nightlight=1"
set_flags "$start"
haseen context present >/dev/null
capture haseen context focus
assert_status "a second context replaces the first" 0 "$STATUS"
assert_eq "present → focus: the context is focus" "focus" "$(haseen context status)"
assert_eq "present → focus: present's idle and night light changes are undone" \
    "dnd=1 idle-off=0 screensaver-off=1 nightlight=1" "$(flags)"
: >"$HLOG"
haseen context game >/dev/null
assert_eq "focus → game: game's switches over the first record" "dnd=1 idle-off=1 screensaver-off=1 nightlight=1" "$(flags)"
haseen context present >/dev/null
assert_contains "game → present: Hyprland's options are restored on the way" "$(cat "$HLOG")" \
    "eval hl.config({ animations = { enabled = true }"
assert_eq "game → present: the override file is gone" "absent" "$([[ -e $GAME_LUA ]] && echo present || echo absent)"
haseen context normal >/dev/null
assert_eq "present → focus → game → present → normal: back to the very first state" "$start" "$(flags)"

set_flags "dnd=0 idle-off=0 screensaver-off=0 nightlight=0"
haseen context focus >/dev/null
capture haseen context focus
assert_contains "the same context again changes nothing" "$OUTPUT" "Already in the focus context"
haseen context normal >/dev/null
assert_eq "focus twice → normal: exact" "dnd=0 idle-off=0 screensaver-off=0 nightlight=0" "$(flags)"
capture haseen context normal
assert_contains "normal while normal changes nothing" "$OUTPUT" "Already in the normal context"

# A change made by hand during a context is undone on leaving: the record wins.
haseen context focus >/dev/null
haseen toggle nightlight on >/dev/null
haseen context normal >/dev/null
assert_eq "a switch flipped during a context goes back to the record" "dnd=0 idle-off=0 screensaver-off=0 nightlight=0" "$(flags)"

# --- the watcher's --auto -------------------------------------------------------
haseen context focus >/dev/null
capture haseen context game --auto
assert_contains "game --auto does not replace a context picked by hand" "$OUTPUT" "Not replacing the focus context"
assert_eq "the hand-picked context stays" "focus" "$(haseen context status)"
capture haseen context normal --auto
assert_contains "normal --auto does not leave a context picked by hand" "$OUTPUT" "Not leaving the focus context"
assert_eq "still focus" "focus" "$(haseen context status)"
haseen context normal >/dev/null

haseen context game --auto >/dev/null
assert_eq "game --auto from normal enters game" "game" "$(haseen context status)"
haseen context normal --auto >/dev/null
assert_eq "normal --auto leaves the game it entered" "normal" "$(haseen context status)"
assert_eq "auto game → normal: exact" "dnd=0 idle-off=0 screensaver-off=0 nightlight=0" "$(flags)"

haseen context game --auto >/dev/null
haseen context game >/dev/null
capture haseen context normal --auto
assert_eq "a game picked by hand after the watcher's stays" "game" "$(haseen context status)"
haseen context normal >/dev/null
assert_eq "and normal by hand leaves it exactly" "dnd=0 idle-off=0 screensaver-off=0 nightlight=0" "$(flags)"

# --- dry runs change nothing ----------------------------------------------------
set_flags "dnd=0 idle-off=1 screensaver-off=0 nightlight=1"
rm -f "$HLOG"
for ctx in focus game present; do
    capture haseen context "$ctx" --dry-run
    assert_status "$ctx --dry-run" 0 "$STATUS"
    assert_dry_pure "context $ctx" "$OUTPUT"
    assert_eq "$ctx --dry-run: still normal" "normal" "$(haseen context status)"
    assert_eq "$ctx --dry-run: flags untouched" "dnd=0 idle-off=1 screensaver-off=0 nightlight=1" "$(flags)"
done
capture haseen context game --dry-run
assert_contains "game --dry-run shows the live override" "$OUTPUT" "DRYRUN: write $GAME_LUA"
assert_contains "game --dry-run shows the do-not-disturb toggle" "$OUTPUT" "DRYRUN: write $FLAGS_DIR/dnd"
assert_eq "dry runs never called Hyprland" "absent" "$([[ -e $HLOG ]] && echo present || echo absent)"
haseen context present >/dev/null
capture haseen context normal --dry-run
assert_dry_pure "context normal" "$OUTPUT"
assert_contains "normal --dry-run shows the night light coming back" "$OUTPUT" "DRYRUN: write $FLAGS_DIR/nightlight"
assert_eq "normal --dry-run: still present" "present" "$(haseen context status)"
haseen context normal >/dev/null

# --- auto-game: the setting and the service --------------------------------------
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
assert_eq "auto-game is off by default" "off" "$(haseen context auto-game)"
capture haseen context auto-game on --dry-run
assert_dry_pure "auto-game on" "$OUTPUT"
assert_eq "auto-game on --dry-run writes nothing" "absent" "$([[ -e $CFG ]] && echo present || echo absent)"
haseen context auto-game on >/dev/null 2>&1
assert_eq "auto-game on watches Steam games" 'steam_app_\d+' "$(haseen context auto-game)"
assert_eq "auto-game on lists the watcher service" "true" "$(jq '.services | index("haseen.indicators") != null' "$CFG")"
assert_eq "the default services stay listed" "true" "$(jq '.services | index("haseen.pager") != null' "$CFG")"
haseen context auto-game set 'steam_app_\d+' gamescope >/dev/null 2>&1
assert_eq "auto-game set takes the user's patterns" $'steam_app_\\d+\ngamescope' "$(haseen context auto-game)"
haseen context game --auto >/dev/null
haseen context auto-game toggle >/dev/null 2>&1
assert_eq "toggle turns it off" "off" "$(haseen context auto-game)"
assert_eq "off drops the watcher service" "false" "$(jq '.services | index("haseen.indicators") != null' "$CFG")"
assert_eq "off leaves the game the watcher entered" "normal" "$(haseen context status)"
haseen context auto-game toggle >/dev/null 2>&1
assert_eq "toggle turns it back on" 'steam_app_\d+' "$(haseen context auto-game)"
capture haseen context auto-game set ''
assert_status "an empty pattern is refused" 1 "$STATUS"
