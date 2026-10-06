# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.indicators (Omarchy's indicators, ported): which entries show, how
# the flags split them into the active and the hover-revealed block, and the
# command a click runs, which must be a real haseen command that flips the
# flag. The pure JS runs in Qt's own engine (qml), as Quickshell does.

PLUGINS="$HASEEN_PATH/shell/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox indicators
capture haseen plugin validate haseen.indicators
assert_status "haseen.indicators validates" 0 "$STATUS"

if [[ ! -x $QML_BIN ]]; then
    echo "  skip: $QML_BIN not installed, Indicators.js not exercised" >&2
    return 0
fi

harness="$SANDBOX/harness"
mkdir -p "$harness"
cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.indicators/Indicators.js" as L
Item {
    function out(name, v) { console.warn("RESULT " + name + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const all = L.entries({}, []);
        out("default", all);
        out("items", L.entries({ items: ["Dnd", { id: "NightLight" }, "Dictation", "Dnd", "Reminder"] }, []));
        out("legacy-key", L.entries({ indicators: ["StayAwake"] }, []));
        out("empty-items", L.entries({ items: [] }, []).length === all.length);
        out("covered", L.entries({}, ["haseen.pager", "haseen.idle", "haseen.privacy"]));
        out("split-none", L.split(all, {}));
        out("split-some", L.split(all, { dnd: true, recording: true, nightlight: false }));
        const cmds = {};
        for (const id of all) cmds[id] = [L.flagOf(id), L.cell(id, false).command, L.cell(id, true).command];
        out("cmds", cmds);
        out("glyphs", all.every(id => L.cell(id, true).glyph !== "" && L.cell(id, true).glyph === L.cell(id, false).glyph));
        out("tips", [L.cell("Dnd", true).tooltip, L.cell("Dnd", false).tooltip]);
        out("unknown", L.cell("Dictation", true));
        Qt.quit();
    }
}
EOF
js_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
r() { sed -n "s/^$1 //p" <<<"$js_out"; }

assert_eq "all of haseen's entries by default, in Omarchy's order" \
    '["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver"]' "$(r default)"
assert_eq "items picks and orders; no source, unknown or repeated ids are dropped" '["Dnd","NightLight"]' "$(r items)"
assert_eq "Omarchy's older indicators key still works" '["StayAwake"]' "$(r legacy-key)"
assert_eq "an empty items list means all" "true" "$(r empty-items)"
assert_eq "entries another bar widget shows are left out" '["NightLight","Screensaver"]' "$(r covered)"
assert_eq "nothing on: all wait for hover" \
    '{"active":[],"inactive":["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver"]}' "$(r split-none)"
assert_eq "flags on: those are the always-shown block" \
    '{"active":["ScreenRecording","Dnd"],"inactive":["NightLight","StayAwake","Screensaver"]}' "$(r split-some)"
assert_eq "one glyph per entry, the same either way" "true" "$(r glyphs)"
assert_eq "the tooltip says what a click does" '["Allow notifications","Silence notifications"]' "$(r tips)"
assert_eq "an entry haseen has no source for has no cell" "null" "$(r unknown)"

# A click must flip the flag the entry shows: run each command for real
# (screen recording only as a dry run; it would start the recorder).
cmds="$(r cmds)"
assert_eq "every entry has a command for both states" "5" "$(jq '[.[] | select((.[1] | length) > 0 and (.[2] | length) > 0)] | length' <<<"${cmds:-{\}}")"
flags="$XDG_STATE_HOME/haseen/flags"
for id in NightLight Dnd StayAwake Screensaver; do
    flag="$(jq -r --arg id "$id" '.[$id][0]' <<<"$cmds")"
    mapfile -t on < <(jq -r --arg id "$id" '.[$id][1][1:][]' <<<"$cmds")
    mapfile -t off < <(jq -r --arg id "$id" '.[$id][2][1:][]' <<<"$cmds")
    rm -f "$flags/$flag"
    capture haseen "${on[@]}"
    assert_eq "$id: a click while off sets $flag" "set" "$([[ -e $flags/$flag ]] && echo set || echo clear)"
    capture haseen "${off[@]}"
    assert_eq "$id: a click while on clears $flag" "clear" "$([[ -e $flags/$flag ]] && echo set || echo clear)"
done
mapfile -t rec < <(jq -r '.ScreenRecording[1][1:][]' <<<"$cmds")
# The recorder itself is not in the CI image; the dry run only needs it on PATH.
stub gpu-screen-recorder "exit 0"
capture haseen "${rec[@]}" --fullscreen --dry-run
assert_status "ScreenRecording: the start command is haseen capture screenrecord" 0 "$STATUS"
assert_eq "ScreenRecording: stop is screenrecord --stop" '["haseen","capture","screenrecord","--stop"]' \
    "$(jq -c '.ScreenRecording[2]' <<<"$cmds")"

# --- the widget in the real engine: revealing never moves the bar ------------
# Omarchy reveals the dimmed indicators inline, which widened the widget and
# shifted every module beside it on each hover. Only the indicators that are
# on may take room; the revealed ones open over the bar. The sandbox bar has
# the pager, idle and privacy widgets, so the entries are NightLight (on here)
# and Screensaver.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ -x $QS_BIN ]]; then
    shell="$SANDBOX/widget"
    mkdir -p "$shell" "$SANDBOX/run" "$flags"
    chmod 700 "$SANDBOX/run"
    for module in Haseen Compat Ui Commons plugins; do
        ln -sfn "$HASEEN_PATH/shell/$module" "$shell/$module"
    done
    rm -f "$flags"/*
    : >"$flags/nightlight"
    cat >"$shell/shell.qml" <<QML
import QtQuick
import Quickshell
import qs.Haseen
ShellRoot {
    id: probe
    property int tick: 0
    property var hidden: null
    property var shown: null
    function make(settings) {
        const c = Qt.createComponent("file://$PLUGINS/haseen.indicators/Widget.qml");
        if (c.status !== Component.Ready) {
            console.log("RESULT " + JSON.stringify({ error: c.errorString() }));
            Qt.quit();
            return null;
        }
        return c.createObject(holder, { pluginId: "haseen.indicators", settings: settings });
    }
    // In a window: positioners lay out only there.
    FloatingWindow {
        visible: true
        implicitWidth: 400
        implicitHeight: 40
        Item {
            id: holder
            anchors.fill: parent
        }
    }
    Component.onCompleted: {
        hidden = make({});
        shown = make({ alwaysShow: true });
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.tick += 1;
            if (!probe.shown || ((!Flags.nightlight || probe.tick < 5) && probe.tick < 50))
                return;
            console.log("RESULT " + JSON.stringify({
                hiddenWidth: probe.hidden.implicitWidth,
                shownWidth: probe.shown.implicitWidth,
                sliver: Theme.gap
            }));
            Qt.quit();
        }
    }
}
QML
    capture env XDG_RUNTIME_DIR="$SANDBOX/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$shell"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n 1)"
    [[ -n $result ]] || result="$(jq -cn --arg o "$OUTPUT" '{error: ("no result: " + $o)}')"
    assert_eq "the widget loads" "" "$(jq -r '.error // empty' <<<"$result")"
    assert_eq "an indicator that is on takes room in the bar" "true" "$(jq -r '.hiddenWidth > .sliver' <<<"$result")"
    assert_eq "revealing does not widen the widget, so nothing beside it moves" \
        "$(jq -r .hiddenWidth <<<"$result")" "$(jq -r .shownWidth <<<"$result")"
    rm -f "$flags/nightlight"
fi
