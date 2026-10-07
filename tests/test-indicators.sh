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
        out("split-context", L.split(all, { context: "game" }));
        out("split-context-odd", L.split(all, { context: "party" }));
        out("context-cells", ["focus", "game", "present"].map(c => [L.cell("Context", true, c).glyph.codePointAt(0).toString(16), L.cell("Context", true, c).tooltip]));
        const pats = L.gamePatterns(["steam_app_[0-9]+", "bad(", "", 3]);
        out("game-patterns", [pats.length, L.gamePatterns(undefined).length]);
        out("is-game", [L.isGame(pats, "steam_app_570", 2), L.isGame(pats, "steam_app_570", 3), L.isGame(pats, "steam_app_570", 1),
            L.isGame(pats, "steam_app_570", 0), L.isGame(pats, "xsteam_app_570", 2), L.isGame([], "steam_app_570", 2)]);
        Qt.quit();
    }
}
EOF
js_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
r() { sed -n "s/^$1 //p" <<<"$js_out"; }

assert_eq "all of haseen's entries by default, in Omarchy's order, then the context" \
    '["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver","Context"]' "$(r default)"
assert_eq "items picks and orders; no source, unknown or repeated ids are dropped" '["Dnd","NightLight"]' "$(r items)"
assert_eq "Omarchy's older indicators key still works" '["StayAwake"]' "$(r legacy-key)"
assert_eq "an empty items list means all" "true" "$(r empty-items)"
assert_eq "entries another bar widget shows are left out" '["NightLight","Screensaver","Context"]' "$(r covered)"
assert_eq "nothing on: all wait for hover, but the context is in neither block" \
    '{"active":[],"inactive":["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver"]}' "$(r split-none)"
assert_eq "flags on: those are the always-shown block" \
    '{"active":["ScreenRecording","Dnd"],"inactive":["NightLight","StayAwake","Screensaver"]}' "$(r split-some)"
assert_eq "one glyph per entry, the same either way" "true" "$(r glyphs)"
assert_eq "the tooltip says what a click does" '["Allow notifications","Silence notifications"]' "$(r tips)"
assert_eq "an entry haseen has no source for has no cell" "null" "$(r unknown)"
assert_eq "a context other than normal is in the always-shown block" \
    '{"active":["Context"],"inactive":["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver"]}' "$(r split-context)"
assert_eq "a name that is no context shows nothing" \
    '{"active":[],"inactive":["ScreenRecording","NightLight","Dnd","StayAwake","Screensaver"]}' "$(r split-context-odd)"
assert_eq "each context has its glyph and names itself" \
    '[["f08c9","Focus context: back to normal"],["f0297","Game context: back to normal"],["f0428","Present context: back to normal"]]' "$(r context-cells)"
assert_eq "game classes: patterns that do not compile, empty or not strings are dropped" "[1,0]" "$(r game-patterns)"
assert_eq "a game is a matching class in real fullscreen, matched whole" "[true,true,false,false,false,false]" "$(r is-game)"

# A click must flip the flag the entry shows: run each command for real
# (screen recording only as a dry run; it would start the recorder).
cmds="$(r cmds)"
assert_eq "every entry has a command for both states" "6" "$(jq '[.[] | select((.[1] | length) > 0 and (.[2] | length) > 0)] | length' <<<"${cmds:-{\}}")"
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
# The context cell's click leaves the context; its flag holds the name.
mapfile -t ctx_off < <(jq -r '.Context[2][1:][]' <<<"$cmds")
haseen context focus >/dev/null
assert_eq "Context: its flag holds the context's name" "focus" "$(cat "$flags/$(jq -r '.Context[0]' <<<"$cmds")")"
capture haseen "${ctx_off[@]}"
assert_eq "Context: a click goes back to normal" "normal" "$(haseen context status)"
mapfile -t ctx_on < <(jq -r '.Context[1][1:][]' <<<"$cmds")
capture haseen "${ctx_on[@]}" --dry-run
assert_eq "Context: the inactive cell would open the context menu" "DRYRUN: haseen shell ipc menu toggle trigger.context" "$OUTPUT"

# --- the widget in the real engine: revealing never moves the bar ------------
# Omarchy reveals the dimmed indicators inline, which widened the widget and
# shifted every module beside it on each hover. Only the indicators that are
# on may take room; the revealed ones open over the bar. The sandbox bar has
# the pager, idle and privacy widgets, so the entries are NightLight (on here)
# and Screensaver.
#
# Switching one off (or on) under the pointer used to resize the widget under
# it: the bar re-centred, the strip closed under the resting pointer and came
# back at the next repaint, and the strip, a popup, stayed where the widget had
# been. Now the cells keep their place while the pointer is on the widget, the
# bar takes the one-cell change once it has left, and the strip follows the
# widget wherever the bar lays it out. Qt's offscreen platform has a pointer
# resting near the window's corner: a widget moved under it has the pointer on
# it, and moved away, the pointer has left (real hover events, no faked state).
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
    property int stage: 0
    property int since: 0
    property var out: ({})
    property var hidden: null
    property var shown: null
    property var edge: null
    property var side: null
    property var rest: null
    function make(parentItem, settings, props) {
        const c = Qt.createComponent("file://$PLUGINS/haseen.indicators/Widget.qml");
        if (c.status !== Component.Ready) {
            out.error = c.errorString();
            finish();
            return null;
        }
        return c.createObject(parentItem, Object.assign({ pluginId: "haseen.indicators", settings: settings }, props || {}));
    }
    function at(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }
    function near(a, b) {
        return Math.abs(a - b) < 0.5;
    }
    // The strip's end toward the widget meets the widget's start.
    function beside(w) {
        if (!w.strip)
            return false;
        const a = at(w), s = at(w.strip);
        return near(s.x + s.w, a.x) && near(s.y, a.y) && near(s.h, a.h);
    }
    function finish() {
        console.log("RESULT " + JSON.stringify(out));
        Qt.quit();
    }
    function next() {
        stage += 1;
        since = tick;
    }
    function waited(n) {
        return tick - since >= n;
    }
    // Puts the widget under the pointer, its corner 2 px from it, so the
    // pointer is on it however narrow it is.
    function arrive(w) {
        const p = pointer.point.scenePosition;
        w.x = p.x - 2;
        w.y = p.y - 2;
    }
    // In a window: positioners lay out only there.
    FloatingWindow {
        visible: true
        implicitWidth: 600
        implicitHeight: 200
        Item {
            id: holder
            anchors.fill: parent
            HoverHandler {
                id: pointer
            }
            // A bar section: it moves when a neighbour's width changes.
            Item {
                id: section
                x: 300
                y: 100
                width: 100
                height: 28
            }
        }
    }
    Component.onCompleted: {
        hidden = make(holder, {}, { x: 100, y: 100 });
        shown = make(section, { alwaysShow: true });
        edge = make(holder, { alwaysShow: true }, { x: 0, y: 150 });
        side = make(holder, { alwaysShow: true }, { x: 550, y: 100, vertical: true });
        rest = make(holder, {}, { x: 200, y: 100 });
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.tick += 1;
            if (probe.tick > 250) {
                probe.out.error = "stuck at stage " + probe.stage;
                probe.finish();
            } else if (probe.out.error === undefined) {
                probe.step();
            }
        }
    }
    function step() {
        switch (stage) {
        case 0:
            if (!Flags.nightlight || tick < 5)
                return;
            out.hiddenWidth = hidden.implicitWidth;
            out.shownWidth = shown.implicitWidth;
            out.sliver = Theme.gap;
            out.beside = beside(shown);
            if (edge.strip) {
                const e = at(edge), s = at(edge.strip);
                out.flipped = near(s.x, e.x + e.w) && near(s.y, e.y);
            }
            if (side.strip) {
                const v = at(side), s = at(side.strip);
                out.above = near(s.y + s.h, v.y) && near(s.x, v.x) && near(s.w, v.w);
            }
            section.x = 337;
            next();
            return;
        case 1:
            if (!waited(1))
                return;
            out.follows = beside(shown) && near(at(shown).x, 337);
            if (!pointer.hovered) {
                out.error = "no pointer in the offscreen window";
                finish();
                return;
            }
            // The pointer arrives on a widget with NightLight on.
            arrive(rest);
            next();
            return;
        case 2:
            if (!waited(3))
                return;
            out.restOpen = rest.strip !== null;
            out.restWidth = rest.implicitWidth;
            Flags.set("nightlight", false);
            next();
            return;
        case 3:
            if (Flags.nightlight || !waited(3))
                return;
            out.restWidthOffHeld = rest.implicitWidth;
            // The pointer leaves.
            rest.y = 100;
            next();
            return;
        case 4:
            if (!waited(8))
                return;
            out.restWidthOffLeft = rest.implicitWidth;
            out.restClosed = rest.strip === null;
            arrive(rest);
            next();
            return;
        case 5:
            if (!waited(3))
                return;
            out.restWidthBeforeOn = rest.implicitWidth;
            Flags.set("screensaver-off", true);
            next();
            return;
        case 6:
            if (!Flags.screensaverOff || !waited(3))
                return;
            out.restWidthOnHeld = rest.implicitWidth;
            rest.y = 100;
            next();
            return;
        case 7:
            if (!waited(8))
                return;
            out.restWidthOnLeft = rest.implicitWidth;
            Flags.set("nightlight", true);
            next();
            return;
        case 8:
            if (!Flags.nightlight || !waited(3))
                return;
            out.allOnStrip = shown.strip !== null || edge.strip !== null;
            // A runtime context begins (haseen context game writes the name).
            out.widthNoContext = hidden.implicitWidth;
            Quickshell.execDetached(["sh", "-c", "echo game >\"\$1\"", "sh", Flags.path("context")]);
            next();
            return;
        case 9:
            if (Flags.context !== "game" || !waited(3))
                return;
            out.contextActive = hidden.parts.active.indexOf("Context") >= 0;
            out.contextGrows = hidden.implicitWidth > out.widthNoContext;
            Quickshell.execDetached(["rm", "-f", "--", Flags.path("context")]);
            next();
            return;
        case 10:
            if (Flags.context !== "" || !waited(3))
                return;
            out.contextGone = hidden.parts.active.indexOf("Context") < 0 && hidden.parts.inactive.indexOf("Context") < 0;
            out.widthAfterContext = hidden.implicitWidth;
            finish();
        }
    }
}
QML
    capture env XDG_RUNTIME_DIR="$SANDBOX/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$shell"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n 1)"
    [[ -n $result ]] || result="$(jq -cn --arg o "$OUTPUT" '{error: ("no result: " + $o)}')"
    w() { jq -r "$1" <<<"$result"; }
    assert_eq "the widget loads" "" "$(w '.error // empty')"
    assert_eq "an indicator that is on takes room in the bar" "true" "$(w '.hiddenWidth > .sliver')"
    assert_eq "revealing does not widen the widget, so nothing beside it moves" "$(w .hiddenWidth)" "$(w .shownWidth)"
    assert_eq "the strip opens on the bar's row, toward its start, against the widget" "true" "$(w .beside)"
    assert_eq "at the bar's start edge the strip opens on the other side" "true" "$(w .flipped)"
    assert_eq "in a side bar the strip opens above the widget, as wide as the bar" "true" "$(w .above)"
    assert_eq "the strip follows the widget when the bar lays it out again" "true" "$(w .follows)"
    assert_eq "the pointer on the widget opens the strip" "true" "$(w .restOpen)"
    assert_eq "switching an indicator off under the pointer moves nothing" "$(w .restWidth)" "$(w .restWidthOffHeld)"
    assert_eq "once the pointer has left, the cell leaves the bar" "$(w .sliver)" "$(w .restWidthOffLeft)"
    assert_eq "and the strip closes" "true" "$(w .restClosed)"
    assert_eq "switching one on under the pointer moves nothing either" "$(w .restWidthBeforeOn)" "$(w .restWidthOnHeld)"
    assert_eq "once the pointer has left, the cell takes room in the bar" "true" "$(w '.restWidthOnLeft > .sliver')"
    assert_eq "with every entry on there is nothing to reveal, so no strip" "false" "$(w .allOnStrip)"
    assert_eq "a context other than normal shows its indicator" "true" "$(w .contextActive)"
    assert_eq "the context indicator takes room in the bar" "true" "$(w .contextGrows)"
    assert_eq "back to normal, the context indicator is in neither block" "true" "$(w .contextGone)"
    assert_eq "and the bar gives its room back" "$(w .widthNoContext)" "$(w .widthAfterContext)"
    assert_not_contains "the widget logs no QML warning" "$OUTPUT" "haseen.indicators/"
    rm -f "$flags"/*
fi
