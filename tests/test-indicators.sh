# shellcheck shell=bash
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
capture haseen "${rec[@]}" --fullscreen --dry-run
assert_status "ScreenRecording: the start command is haseen capture screenrecord" 0 "$STATUS"
assert_eq "ScreenRecording: stop is screenrecord --stop" '["haseen","capture","screenrecord","--stop"]' \
    "$(jq -c '.ScreenRecording[2]' <<<"$cmds")"
