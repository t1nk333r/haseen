# shellcheck shell=bash
# haseen:covers bin/haseen-hardware-mirror-display bin/haseen-hardware-monitor
# haseen:covers bin/haseen-plugin-validate share/haseen/VERSION share/haseen/default/shell.json
# haseen:covers share/haseen/shell/Compat/** share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.monitor-settings/** tools/smoke-session.conf
# haseen:covers NOTICE.md share/haseen/shell/plugins/*/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 098: haseen.monitor-settings, ported from juliusmork-sys's Monitor
# Settings Extender. The manifest validates and the plugin is off by default;
# `haseen hardware monitor` applies live and records each change in a toggle
# that survives a reload (against a fake hyprctl); Model.js runs under the Qt
# JS engine; the panel runs in the real Quickshell engine.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGIN="$SHELL_DIR/plugins/haseen.monitor-settings"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

# --- manifest, contract and house rules ---------------------------------------
sandbox monitor-settings
capture haseen plugin validate haseen.monitor-settings
assert_status "monitor-settings validates" 0 "$STATUS"
assert_contains "monitor-settings is a built-in" "$OUTPUT" "ok: haseen.monitor-settings (builtin:"
assert_not_contains "it asks for no network" "$OUTPUT" "warning:"
assert_eq "bar widget and panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "off by default: not in the default bar or services" "" \
    "$(jq -r '[.bar.left, .bar.center, .bar.right, .services] | add | map(select(. == "haseen.monitor-settings")) | .[]' "$HASEEN_PATH/default/shell.json")"
for f in Widget.qml Panel.qml; do
    entry="$(cat "$PLUGIN/$f")"
    assert_contains "$f declares pluginId" "$entry" "property string pluginId"
    assert_contains "$f declares settings" "$entry" "property var settings: ({})"
    assert_contains "$f declares screen" "$entry" "property var screen: null"
done
for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGIN"/*.qml | cut -d. -f2 | sort -u); do
    assert_eq "declares the setting $key it reads" true "$(jq --arg k "$key" '.settings | has($k)' "$PLUGIN/manifest.json")"
done
assert_eq "no hex colour literals" "" "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "$PLUGIN" --include='*.qml' --include='*.js' || true)"
assert_eq "no Omarchy dependency" "" "$(grep -rnE 'omarchy-|OMARCHY_PATH|qs\.Commons|qs\.Ui' "$PLUGIN" || true)"
assert_eq "no sudo" "" "$(grep -rnE '\b(sudo|pkexec)\b' "$PLUGIN" "$REPO/bin/haseen-hardware-monitor" || true)"
assert_eq "no polling: only the post-change settle timeout" "1" "$(grep -c 'Timer {' "$PLUGIN/Panel.qml")"
assert_contains "the panel follows Hyprland's monitor events" "$(cat "$PLUGIN/Panel.qml")" '"monitoradded"'
assert_contains "the MIT notice is kept" "$(cat "$PLUGIN/Model.js")" "MIT, Copyright (c) 2026 Julius Getz Mørk"
assert_contains "NOTICE.md lists the port" "$(cat "$REPO/NOTICE.md")" "haseen.monitor-settings"

# --- haseen hardware monitor against a fake hyprctl ---------------------------
cat >"$SANDBOX/monitors.json" <<'EOF'
[{"name":"eDP-1","description":"BOE 0x07DB","make":"BOE","model":"0x07DB","width":1920,"height":1200,"refreshRate":60.001,"x":0,"y":0,"scale":1.25,"transform":0,"disabled":false,"focused":true,"availableModes":["1920x1200@60.00Hz","1920x1200@48.00Hz"]},
 {"name":"DP-1","description":"Samsung Electric Company LC34G55T H4ZR","make":"Samsung Electric Company","model":"LC34G55T","width":3440,"height":1440,"refreshRate":164.999,"x":1536,"y":0,"scale":1,"transform":0,"disabled":false,"focused":false,"availableModes":["3440x1440@165.00Hz","3440x1440@99.98Hz","2560x1440@59.95Hz"]}]
EOF
LOG="$SANDBOX/log"
stub hyprctl "case \"\$1\" in monitors) cat '$SANDBOX/monitors.json' ;; *) echo \"hyprctl \$*\" >>'$LOG' ;; esac"
stub gsettings "echo \"gsettings \$*\" >>'$LOG'; [ \"\$1\" != get ] || { [ \"\$3\" = cursor-theme ] && echo \"'Bibata'\" || echo 32; }"
STATE="$XDG_STATE_HOME/haseen"
TOGGLE="$STATE/toggles/hypr/display-layout.lua"

capture haseen hardware monitor list
assert_status "list succeeds" 0 "$STATUS"
assert_eq "list: rule keys by unique EDID description" '["desc:BOE 0x07DB","desc:Samsung Electric Company LC34G55T H4ZR"]' "$(jq -c '[.monitors[].ruleKey]' <<<"$OUTPUT")"
assert_eq "list: mirror, laptopOff and cursor size" '[false,false,32]' "$(jq -c '[.mirror, .laptopOff, .cursorSize]' <<<"$OUTPUT")"

mkdir -p "$XDG_CONFIG_HOME/hypr"
printf 'hl.monitor({ output = "DP-1", mode = "preferred" })\n' >"$XDG_CONFIG_HOME/hypr/monitors.lua"
capture haseen hardware monitor list
assert_eq "list: the user's monitors.lua rule is reported" '[false,true]' "$(jq -c '[.monitors[].userRule]' <<<"$OUTPUT")"
user_before="$(cat "$XDG_CONFIG_HOME/hypr/monitors.lua")"

capture haseen hardware monitor set DP-1 --transform 1 --position 1536x0 --dry-run
assert_status "set --dry-run succeeds" 0 "$STATUS"
assert_contains "dry run prints the live eval" "$OUTPUT" 'DRYRUN: hyprctl eval hl.monitor({ output = "DP-1", mode = "3440x1440@165", position = "1536x0", scale = 1, transform = 1 })'
assert_eq "dry run writes nothing" "no" "$([[ -e $TOGGLE || -e $STATE/monitor-settings.json ]] && echo yes || echo no)"
assert_eq "dry run runs no eval" "" "$(grep eval "$LOG" 2>/dev/null || true)"

capture haseen hardware monitor set DP-1 --transform 1 --position 1536x0
assert_status "set applies" 0 "$STATUS"
assert_eq "set: one live eval with the current mode" 'hyprctl eval hl.monitor({ output = "DP-1", mode = "3440x1440@165", position = "1536x0", scale = 1, transform = 1 })' "$(grep eval "$LOG")"
assert_contains "set: the toggle keeps it by description" "$(cat "$TOGGLE")" 'hl.monitor({ output = "desc:Samsung Electric Company LC34G55T H4ZR", mode = "3440x1440@165", position = "1536x0", scale = 1, transform = 1 })'
assert_eq "set: the toggle is valid Lua" 0 "$(luac -p "$TOGGLE" >/dev/null 2>&1; echo $?)"
assert_eq "the user's monitors.lua is untouched" "$user_before" "$(cat "$XDG_CONFIG_HOME/hypr/monitors.lua")"

capture haseen hardware monitor set eDP-1 --scale 1.6
assert_eq "a second monitor joins the same toggle" 2 "$(grep -c '^hl.monitor' "$TOGGLE")"
capture haseen hardware monitor set DP-1 --off
assert_contains "--off records the monitor as off" "$(cat "$TOGGLE")" 'output = "desc:Samsung Electric Company LC34G55T H4ZR", disabled = true'
jq '(.[] | select(.name == "DP-1")).disabled = true' "$SANDBOX/monitors.json" >"$SANDBOX/m2" && mv "$SANDBOX/m2" "$SANDBOX/monitors.json"
capture haseen hardware monitor set eDP-1 --off
assert_status "the last active display cannot be turned off" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "only active display"
capture haseen hardware monitor set DP-1 --on
assert_contains "--on brings it back at its preferred mode" "$(tail -1 "$LOG")" 'mode = "preferred", position = "auto", scale = 1, transform = 0, disabled = false'

for bad in "DP-1 --mode 3440x1440" "DP-1 --position 10,20" "DP-1 --scale 9" "DP-1 --scale 01" "DP-1 --transform 8" 'DP;1 --scale 1' "nosuch --scale 1" "DP-1"; do
    # shellcheck disable=SC2086 # the words are the arguments under test
    capture haseen hardware monitor set $bad
    assert_status "set refuses: $bad" 1 "$STATUS"
done
: >"$STATE/toggles/hypr/mirror-display.lua"
capture haseen hardware monitor set DP-1 --scale 1.25
assert_status "set refuses while mirroring" 1 "$STATUS"
assert_contains "and names the way out" "$OUTPUT" "haseen hardware mirror-display off"
rm -f "$STATE/toggles/hypr/mirror-display.lua"

capture haseen hardware monitor cursor 40
assert_status "cursor applies" 0 "$STATUS"
assert_contains "cursor: Hyprland now" "$(cat "$LOG")" "hyprctl setcursor Bibata 40"
assert_contains "cursor: GTK now" "$(cat "$LOG")" "gsettings set org.gnome.desktop.interface cursor-size 40"
assert_eq "cursor: the next login" "export XCURSOR_SIZE=40" "$(tail -1 "$XDG_CONFIG_HOME/uwsm/env.d/61-haseen-cursor")"
capture haseen hardware monitor cursor 4
assert_status "cursor refuses a tiny size" 1 "$STATUS"

capture haseen hardware monitor reset DP-1
assert_eq "reset OUTPUT keeps the others" "1" "$(grep -c '^hl.monitor' "$TOGGLE")"
capture haseen hardware monitor reset
assert_eq "reset removes the toggle and the record" "no" "$([[ -e $TOGGLE || -e $STATE/monitor-settings.json ]] && echo yes || echo no)"
assert_eq "reset reloads Hyprland" "hyprctl reload" "$(tail -1 "$LOG")"
capture haseen hardware monitor --help
assert_status "--help" 0 "$STATUS"

# --- Model.js under the Qt JS engine -------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as M
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        out("labels", [M.label({name: "eDP-1", make: "BOE", model: "0x07DB"}), M.label({name: "DP-1", make: "Samsung Electric Company", model: "LC34G55T"}), M.label({name: "DP-2", model: "0x1234", description: "Some Desc"}), M.label({name: "HDMI-A-1"})]);
        out("scales", M.scalesFor(1920, 1200));
        out("clean", [M.cleanScale(1.3, 3440, 1440), M.cleanScale(0, 1, 1)]);
        out("rates", M.ratesFor(["3440x1440@165.00Hz", "3440x1440@99.98Hz", "2560x1440@59.95Hz", "3440x1440@165.00Hz", "junk"], 3440, 1440));
        out("hz", [M.formatHz(164.999), M.formatHz(99.98), M.nearest([165, 99.98], 164.999)]);
        out("mode", M.modeArg({width: 3440, height: 1440}, 99.98));
        const mons = [{name: "A", x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0}, {name: "B", x: 1920, y: 0, width: 2560, height: 1440, scale: 1, transform: 0}];
        out("footprint", [M.footprint({width: 3840, height: 2160, scale: 2, transform: 1})]);
        out("snap", M.snap(1925, 5, 100, 100, [{x: 0, y: 0, w: 1920, h: 1080}], 8));
        out("place", [M.place(mons, "B", 1000, 300, 8), M.place(mons, "B", 1930, 3, 16), M.place(mons, "nosuch", 0, 0, 8)]);
        out("rotated", M.rotated([{name: "A", x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0}, {name: "B", x: 1000, y: 0, width: 1920, height: 1080, scale: 1, transform: 0}], "A", 1));
        out("cursor", [M.cursorLogical(48, 1.25), M.cursorPhysical(38, 1.25, M.CURSOR_SIZES), M.cursorLogical(20, 4)]);
        const parsed = M.parseList('{"monitors":[{"name":"DP-1","width":1,"height":2,"transform":5,"userRule":true},{"name":"bad name"}],"mirror":true,"cursorSize":"x"}');
        out("parse", [parsed.monitors.length, parsed.monitors[0].transform, parsed.monitors[0].userRule, parsed.mirror, parsed.cursorSize, M.parseList("nope").monitors.length]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "Model: friendly names" '["Built-in display","Samsung LC34G55T","Some Desc","HDMI-A-1"]' "$(r labels)"
    assert_eq "Model: scales snapped to whole logical pixels" '[1,1.25,1.5,1.6,1.88,2,2.5,3]' "$(r scales)"
    assert_eq "Model: clean scale rounds up; nonsense is 0" '[1.33,0]' "$(r clean)"
    assert_eq "Model: refresh rates at the resolution, highest first, once" '[165,99.98]' "$(r rates)"
    assert_eq "Model: Hz labels and the nearest advertised rate" '["165 Hz","99.98 Hz",165]' "$(r hz)"
    assert_eq "Model: the --mode argument" '"3440x1440@99.98"' "$(r mode)"
    assert_eq "Model: a rotated, scaled footprint" '[{"w":1080,"h":1920}]' "$(r footprint)"
    assert_eq "Model: an edge within the threshold snaps flush" '{"x":1920,"y":0}' "$(r snap)"
    assert_eq "Model: a drop onto a neighbour is pushed clear; a near drop snaps" '[{"x":1000,"y":1080},{"x":1920,"y":0},null]' "$(r place)"
    assert_eq "Model: a rotation that would overlap moves clear" '{"x":-80,"y":0}' "$(r rotated)"
    assert_eq "Model: cursor sizes through the scale" '[38,48,8]' "$(r cursor)"
    assert_eq "Model: the list is validated" '[1,5,true,true,24,0]' "$(r parse)"
else
    echo "  skip: $QML_BIN not installed, Model.js not exercised" >&2
fi

# --- the panel in the real engine ----------------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; panel scenario not run" >&2
else
    : >"$LOG"
    jq '(.[] | select(.name == "DP-1")).disabled = false' "$SANDBOX/monitors.json" >"$SANDBOX/m2" && mv "$SANDBOX/m2" "$SANDBOX/monitors.json"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$SHELL_DIR/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.monitor-settings" as M
ShellRoot {
    id: shell

    property var first: null

    M.Panel {
        id: panel

        pluginId: "haseen.monitor-settings"
        settings: ({ debugIpc: true })
    }

    M.Widget {
        id: widget

        pluginId: "haseen.monitor-settings"
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            shell.first = { loaded: panel.loaded, names: panel.monitors.map(m => m.label), canMirror: panel.canMirror, active: panel.active.length, glyph: widget.glyph };
            panel.run(["hardware", "monitor", "set", "DP-1", "--scale", "1.25"]);
            shell.first.second = panel.run(["hardware", "monitor", "set", "DP-1", "--scale", "2"]);
            later.running = true;
        }
    }

    Timer {
        id: later

        interval: 2000
        onTriggered: {
            console.warn("RESULT " + JSON.stringify({ first: shell.first, sent: panel.sent, busy: panel.busy, error: panel.error }));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "panel: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    assert_eq "panel: lists both monitors by friendly name" '["Built-in display","Samsung LC34G55T"]' "$(jq -c .first.names <<<"$RESULT")"
    assert_eq "panel: offers mirroring with a laptop and an external" true "$(jq .first.canMirror <<<"$RESULT")"
    assert_eq "panel: loaded" true "$(jq .first.loaded <<<"$RESULT")"
    assert_eq "panel: one change at a time" false "$(jq .first.second <<<"$RESULT")"
    assert_eq "panel: the change goes through haseen hardware monitor" '["hardware monitor set DP-1 --scale 1.25"]' "$(jq -c .sent <<<"$RESULT")"
    assert_eq "panel: it applied" 'hyprctl eval hl.monitor({ output = "DP-1", mode = "3440x1440@165", position = "1536x0", scale = 1.25, transform = 0 })' "$(grep eval "$LOG" | tail -1)"
    assert_eq "panel: no error" '""' "$(jq -c .error <<<"$RESULT")"
    assert_eq "widget: the monitor glyph" "$(printf '\U000F0379')" "$(jq -r .first.glyph <<<"$RESULT")"
fi
