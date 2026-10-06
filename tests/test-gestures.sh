# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Touchpad gestures (haseen.gestures, ported from omagesture): the Lua the
# defaults and a changed mapping render to, what `haseen gestures apply`
# writes and reloads (once, and nothing on a dry run), the `gestures` hardware
# quirk on a touchpad laptop and a desktop, and the plugin itself — manifest,
# panel catalogue against the CLI, and the panel and widget in the real engine.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.gestures"
QS_BIN=${QS_BIN:-/usr/bin/qs}
# A live session's Hyprland must never be reloaded from a test.
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY

sandbox gestures
TOGGLE="$XDG_STATE_HOME/haseen/toggles/hypr/gestures.lua"
FLAG="$XDG_STATE_HOME/haseen/flags/gestures"
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
gesture_lines() { grep -c '^hl.gesture' <<<"$1" || true; }

# --- the defaults are the owner's Omarchy mapping -----------------------------
capture haseen gestures apply --print
assert_status "print renders" 0 "$STATUS"
default_lua="$OUTPUT"
assert_contains "three fingers sideways switch workspaces" "$OUTPUT" 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })'
assert_contains "four fingers sideways resize" "$OUTPUT" 'hl.gesture({ fingers = 4, direction = "horizontal", action = haseen_gesture_resize("x") })'
assert_contains "four fingers up and down resize" "$OUTPUT" 'hl.gesture({ fingers = 4, direction = "vertical", action = haseen_gesture_resize("y") })'
assert_eq "nothing else is mapped (three fingers up/down stay free)" 3 "$(gesture_lines "$OUTPUT")"
assert_contains "natural scroll and two-finger right click" "$OUTPUT" "touchpad = { natural_scroll = true, clickfinger_behavior = true, drag_3fg = 0 }"
assert_contains "the swipe reaches empty workspaces" "$OUTPUT" "workspace_swipe_use_r = true, workspace_swipe_forever = false"
assert_contains "three-finger click-drag moves the window" "$OUTPUT" 'hl.bind("mouse:274", hl.dsp.window.drag(), { mouse = true'
assert_not_contains "nothing calls Omarchy" "$OUTPUT" "omarchy"
assert_eq "print writes nothing" "" "$(compgen -G "$XDG_STATE_HOME/haseen/*" || true)"

# --- a changed mapping ------------------------------------------------------
mkdir -p "$(dirname "$CFG")"
cat >"$CFG" <<'JSON'
{"bar":{"right":["haseen.clock"]},"plugins":{"haseen.gestures":{"settings":{
  "g3Up":"menu","g3Down":"special","g4Left":"close_window","g2PinchIn":"zoom","g2PinchOut":"zoom",
  "middleButton":"screenshot","naturalScroll":false,"clickMethod":"buttonareas","swipeRange":"existing"}}}}
JSON
capture haseen gestures apply --print
# shellcheck disable=SC2034 # read through ${!lua_var} in the Hyprland check
changed_lua="$OUTPUT"
assert_contains "three fingers up opens haseen's menu, once per swipe" "$OUTPUT" 'direction = "up", action = haseen_gesture_once(40, function() hl.dispatch(hl.dsp.exec_cmd("haseen menu")) end)'
assert_contains "the once helper is defined" "$OUTPUT" "local function haseen_gesture_once(threshold, run)"
assert_contains "three fingers down toggles haseen's scratchpad" "$OUTPUT" 'direction = "down", action = "special", workspace_name = "scratchpad"'
assert_contains "different halves stay separate: left closes" "$OUTPUT" 'hl.gesture({ fingers = 4, direction = "left", action = "close" })'
assert_contains "and right still resizes" "$OUTPUT" 'hl.gesture({ fingers = 4, direction = "right", action = haseen_gesture_resize("x") })'
assert_contains "matching pinch halves collapse into one axis" "$OUTPUT" 'hl.gesture({ fingers = 2, direction = "pinch", action = "cursorZoom", zoom_level = 2 })'
assert_contains "middle click takes a haseen screenshot" "$OUTPUT" 'hl.dsp.exec_cmd("haseen capture screenshot region")'
assert_contains "scroll and click follow the settings" "$OUTPUT" "natural_scroll = false, clickfinger_behavior = false"
assert_contains "the swipe walks open workspaces only" "$OUTPUT" "workspace_swipe_use_r = false"
assert_not_contains "no drag bind without move" "$OUTPUT" "hl.dsp.window.drag()"

# An Omarchy value haseen does not carry (upstream's no-op "paste") or a
# hand-edited value falls back to the default instead of reaching the Lua.
cat >"$CFG" <<'JSON'
{"plugins":{"haseen.gestures":{"settings":{"middleButton":"paste","g3Up":"workspace\" }) os.execute(\"x"}}}}
JSON
capture haseen gestures apply --print
assert_contains "an unsupported value is named" "$OUTPUT" 'ignoring unsupported setting middleButton="paste"'
assert_contains "and falls back to the default" "$OUTPUT" "hl.dsp.window.drag()"
assert_not_contains "a hostile value never reaches the Lua" "$(haseen gestures apply --print 2>/dev/null)" "os.execute"

cat >"$CFG" <<'JSON'
{"plugins":{"haseen.gestures":{"settings":{"enabled":false}}}}
JSON
capture haseen gestures apply --print
assert_eq "gestures off: no gesture at all" 0 "$(gesture_lines "$OUTPUT")"
assert_contains "gestures off: the touchpad tuning still applies" "$OUTPUT" "touchpad = { natural_scroll = true"

cat >"$CFG" <<'JSON'
{"plugins":{"haseen.gestures":{"settings":{"drag":"threefinger"}}}}
JSON
capture haseen gestures apply --print
assert_contains "three-finger drag yields to mapped three-finger swipes" "$OUTPUT" "drag_3fg = 0"
assert_contains "and says why" "$OUTPUT" "three-finger drag dropped"
cat >"$CFG" <<'JSON'
{"plugins":{"haseen.gestures":{"settings":{"drag":"threefinger","g3Left":"none","g3Right":"none"}}}}
JSON
capture haseen gestures apply --print
assert_contains "with three fingers free the drag is on" "$OUTPUT" "drag_3fg = 1"
rm -f "$CFG"

# --- the generated Lua is valid Hyprland config ------------------------------
if command -v Hyprland >/dev/null; then
    mkdir -p "$SANDBOX/verify" "$SANDBOX/run"
    chmod 700 "$SANDBOX/run"
    for name in default changed; do
        lua_var="${name}_lua"
        printf '%s\n' "${!lua_var}" >"$SANDBOX/verify/$name.lua"
        printf 'dofile("%s")\n' "$SANDBOX/verify/$name.lua" >"$SANDBOX/verify/$name-main.lua"
        capture env XDG_RUNTIME_DIR="$SANDBOX/run" timeout 30 Hyprland --verify-config -c "$SANDBOX/verify/$name-main.lua"
        assert_contains "Hyprland accepts the $name mapping" "$OUTPUT" "config ok"
    done
else
    echo "  skip: Hyprland not installed; --verify-config not run" >&2
fi

# --- apply: dry-run pure, writes once, reloads once ---------------------------
stub hyprctl "echo \"hyprctl \$*\" >>\"$SANDBOX/hyprctl.log\""
capture haseen gestures apply --dry-run
assert_dry_pure "apply" "$OUTPUT"
assert_contains "the dry run shows the file" "$OUTPUT" "DRYRUN: write $TOGGLE"
assert_eq "the dry run writes nothing" "" "$(compgen -G "$XDG_STATE_HOME/haseen/*" || true)"

capture haseen gestures apply --set '{"g3Up":"menu"}' --dry-run
assert_dry_pure "apply --set" "$OUTPUT"
assert_contains "the dry run shows the settings it would save" "$OUTPUT" '"g3Up": "menu"'
assert_contains "and renders them" "$OUTPUT" 'haseen menu'
assert_eq "--set --dry-run writes no shell.json" "" "$(compgen -G "$XDG_CONFIG_HOME/haseen/*" || true)"

export HYPRLAND_INSTANCE_SIGNATURE=test
capture haseen gestures apply
assert_status "apply" 0 "$STATUS"
assert_eq "the file holds the default mapping" "$default_lua" "$(cat "$TOGGLE")"
assert_eq "Hyprland reloads once" "hyprctl reload" "$(cat "$SANDBOX/hyprctl.log")"
capture haseen gestures apply
assert_contains "a second apply is a no-op" "$OUTPUT" "already current"
assert_eq "and does not reload again" 1 "$(grep -c reload "$SANDBOX/hyprctl.log")"

mkdir -p "$(dirname "$CFG")"
echo '{"bar":{"position":"bottom"},"plugins":{"haseen.gestures":{"settings":{"g4Up":"none"}}}}' >"$CFG"
capture haseen gestures apply --set '{"g3Up":"menu","g3Down":"menu"}'
assert_status "apply --set" 0 "$STATUS"
assert_eq "the setting is saved" "menu" "$(jq -r '.plugins["haseen.gestures"].settings.g3Up' "$CFG")"
assert_eq "earlier settings survive" "none" "$(jq -r '.plugins["haseen.gestures"].settings.g4Up' "$CFG")"
assert_eq "unrelated config survives" "bottom" "$(jq -r .bar.position "$CFG")"
assert_contains "the file follows" "$(cat "$TOGGLE")" 'fingers = 3, direction = "vertical", action = haseen_gesture_once'
assert_contains "and so does the split axis" "$(cat "$TOGGLE")" 'fingers = 4, direction = "down", action = haseen_gesture_resize("y")'
assert_eq "a change reloads" 2 "$(grep -c reload "$SANDBOX/hyprctl.log")"
capture haseen gestures apply --set '{"g3Up":"menu","g3Down":"menu"}'
assert_contains "the same --set again changes nothing" "$OUTPUT" "already current"
assert_eq "and does not reload" 2 "$(grep -c reload "$SANDBOX/hyprctl.log")"

before="$(cat "$CFG")"
for bad in '{"g3Up":"bogus"}' '{"g9Left":"workspace"}' '{"enabled":"yes"}' '["g3Up"]' '{"middleButton":"paste"}'; do
    capture haseen gestures apply --set "$bad"
    assert_status "--set refuses $bad" 1 "$STATUS"
done
assert_eq "a refused --set leaves shell.json alone" "$before" "$(cat "$CFG")"
unset HYPRLAND_INSTANCE_SIGNATURE

# --- coexistence with the Omarchy original -----------------------------------
echo '{"bar":{"right":["io.github.heroesofcode.omagesture"]}}' >"$CFG"
capture haseen gestures apply --dry-run
assert_contains "the Omarchy copy in the bar is flagged" "$OUTPUT" "io.github.heroesofcode.omagesture is also in the bar"
rm -f "$CFG"
mkdir -p "$XDG_CONFIG_HOME/hypr"
printf -- '-- omagesture:begin (managed)\npcall(require, "hypr.omagesture")\n-- omagesture:end\n' >"$XDG_CONFIG_HOME/hypr/hyprland.lua"
capture haseen gestures apply --dry-run
assert_contains "an omagesture require block is flagged" "$OUTPUT" "omagesture:begin block"
rm -rf "$XDG_CONFIG_HOME/hypr"

# --- the hardware quirk ------------------------------------------------------
sandbox gestures-quirk
TOGGLE="$XDG_STATE_HOME/haseen/toggles/hypr/gestures.lua"
FLAG="$XDG_STATE_HOME/haseen/flags/gestures"
export HASEEN_SYSROOT="$FIXTURES/hw-touchpad-laptop"
assert_contains "a touchpad laptop matches gestures" "$(haseen hw match --json | jq -r '.matched | join(" ")')" "gestures"
export HASEEN_SYSROOT="$FIXTURES/hw-desktop"
# The desktop has a mouse, a TrackPoint keyboard, a pen tablet and a
# touchscreen: pointers, but none of them a touchpad.
assert_not_contains "a desktop without a touchpad does not" "$(haseen hw match --json | jq -r '.matched | join(" ")')" "gestures"
capture haseen hw apply gestures --yes
assert_contains "naming it on the desktop refuses it" "$OUTPUT" "does not match this machine"
assert_eq "and writes nothing" "" "$(compgen -G "$XDG_STATE_HOME/haseen/*" || true)"
export HASEEN_SYSROOT="$FIXTURES/hw-vm-guest"
assert_not_contains "a machine with no input list does not match" "$(haseen hw match --json | jq -r '.matched | join(" ")')" "gestures"

export HASEEN_SYSROOT="$FIXTURES/hw-touchpad-laptop"
capture haseen hw apply gestures --dry-run --yes
assert_dry_pure "gestures quirk" "$OUTPUT"
assert_contains "the quirk plans the mapping" "$OUTPUT" "DRYRUN: write $TOGGLE"
assert_contains "and the widget flag" "$OUTPUT" "DRYRUN: write $FLAG"
assert_eq "the dry run writes nothing" "" "$(compgen -G "$XDG_STATE_HOME/haseen/*" || true)"

capture haseen hw apply gestures --yes
assert_status "the quirk applies" 0 "$STATUS"
assert_eq "it writes the default mapping" "$default_lua" "$(cat "$TOGGLE")"
assert_eq "it switches the widget on" yes "$([[ -e $FLAG ]] && echo yes || echo no)"
assert_eq "the user's shell.json is never written" "" "$(compgen -G "$XDG_CONFIG_HOME/haseen/*" || true)"
assert_eq "it is recorded" applied "$(cut -d' ' -f1 "$XDG_STATE_HOME/haseen/hardware/gestures")"
capture haseen hw apply gestures --yes
assert_contains "a second run is a no-op" "$OUTPUT" "0 applied, 1 already recorded"
capture haseen hw apply gestures --force --yes
assert_contains "--force finds the mapping current" "$OUTPUT" "already current"
assert_contains "and the widget already on" "$OUTPUT" "already on"
unset HASEEN_SYSROOT

# --- the plugin ---------------------------------------------------------------
capture haseen plugin validate haseen.gestures
assert_status "plugin validates" 0 "$STATUS"
assert_contains "it validates as a built-in" "$OUTPUT" "ok: haseen.gestures (builtin:"
assert_eq "bar widget and lazy panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "it runs a command and writes files" "exec files:write" "$(jq -r '.permissions | sort | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "settings are typed and described" "" \
    "$(jq -r '.settings | to_entries[] | select((.value.type | not) or (.value.description | not)) | .key' "$PLUGIN/manifest.json")"
for key in $(grep -ohE 'settings\.[a-zA-Z0-9]+' "$PLUGIN"/*.qml | cut -d. -f2 | sort -u); do
    assert_eq "the setting $key the QML reads is declared" true "$(jq --arg k "$key" '.settings | has($k)' "$PLUGIN/manifest.json")"
done
assert_contains "the default bar lists the widget" "$(jq -c .bar.right "$HASEEN_PATH/default/shell.json")" '"haseen.gestures"'
assert_contains "the widget waits for the flag" "$(cat "$PLUGIN/Widget.qml")" "implicitWidth: Flags.gestures ? contentWidth : 0"

# Every value the panel offers is one the CLI accepts.
for list in ACTIONS CLICK_METHODS DRAG_MODES SWIPE_RANGES MIDDLE_BUTTONS; do
    values="$(awk -v l="var $list = [" 'index($0, l) == 1 { on = 1; next } on && /^\];/ { exit } on' "$PLUGIN/Model.js" |
        sed -n 's/.*value: "\([a-z_]*\)".*/\1/p')"
    assert_eq "Model.js $list is not empty" false "$([[ -z $values ]] && echo true || echo false)"
    case "$list" in
    ACTIONS) key=g3Up ;;
    CLICK_METHODS) key=clickMethod ;;
    DRAG_MODES) key=drag ;;
    SWIPE_RANGES) key=swipeRange ;;
    MIDDLE_BUTTONS) key=middleButton ;;
    esac
    for value in $values; do
        capture haseen gestures apply --set "{\"$key\":\"$value\"}" --dry-run
        assert_status "the panel's $key=$value is accepted" 0 "$STATUS"
    done
done

# --- the panel and widget in the real engine ---------------------------------
if [[ -x $QS_BIN ]]; then
    sandbox gestures-qml
    harness="$SANDBOX/shell"
    mkdir -p "$harness" "$SANDBOX/run"
    chmod 700 "$SANDBOX/run"
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
ShellRoot {
    id: probe
    property var panel: null
    property var widget: null
    property int phase: 0
    property var result: ({})
    function make(kind: string): var {
        const c = Qt.createComponent(Plugins.entryUrl("haseen.gestures", kind));
        if (c.status !== Component.Ready) {
            console.log("RESULT " + JSON.stringify({ error: c.errorString() }));
            Qt.quit();
            return null;
        }
        const o = c.createObject(null, { pluginId: "haseen.gestures", settings: Plugins.settingsFor("haseen.gestures") });
        o.settings = Qt.binding(() => Plugins.settingsFor("haseen.gestures"));
        return o;
    }
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (probe.phase === 0 && Plugins.ready) {
                probe.panel = probe.make("panel");
                probe.widget = probe.make("bar-widget");
                probe.result.widgetWidthBefore = probe.widget.implicitWidth;
                Flags.set("gestures", true);
                probe.phase = 1;
            } else if (probe.phase === 1 && Flags.gestures) {
                probe.result.widgetWidthAfter = probe.widget.implicitWidth;
                probe.result.panelHeight = probe.panel.implicitHeight;
                probe.panel.save({ g3Up: "menu", g3Down: "menu" });
                probe.result.immediate = probe.panel.settings.g3Up;
                probe.phase = 2;
            } else if (probe.phase === 2 && !checker.running) {
                // The CLI runs detached: wait for its file. (A FileView
                // cannot watch a file that did not exist when it started.)
                checker.running = true;
            }
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.log("RESULT " + JSON.stringify(probe.result));
            Qt.quit();
        }
    }
    Process {
        id: checker
        command: ["grep", "-q", "haseen menu", Paths.userState + "/toggles/hypr/gestures.lua"]
        onExited: code => {
            if (code === 0) {
                probe.result.rendered = true;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env XDG_RUNTIME_DIR="$SANDBOX/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 40 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n 1)"
    [[ -n $result ]] || result='{"error":"no result"}'
    assert_eq "the panel and widget load" "" "$(jq -r '.error // empty' <<<"$result")"
    assert_eq "the widget takes no room without the flag" 0 "$(jq -r .widgetWidthBefore <<<"$result")"
    assert_eq "and shows once the flag is set" true "$(jq -r '.widgetWidthAfter > 0' <<<"$result")"
    assert_eq "the panel has content" true "$(jq -r '.panelHeight > 0' <<<"$result")"
    assert_eq "a pick shows at once" menu "$(jq -r .immediate <<<"$result")"
    assert_eq "and reaches gestures.lua through the CLI" true "$(jq -r .rendered <<<"$result")"
    assert_eq "the pick is saved in shell.json" menu "$(jq -r '.plugins["haseen.gestures"].settings.g3Up' "$XDG_CONFIG_HOME/haseen/shell.json" 2>/dev/null)"
else
    echo "  skip: quickshell not installed; the panel is not loaded" >&2
fi
