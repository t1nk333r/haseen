# shellcheck shell=bash
# haseen:covers bin/haseen-bar-{arrange,move,position} share/haseen/shell/BarDrag.js
# haseen:covers share/haseen/shell/Overflow.js share/haseen/shell/PluginSlot.qml
# haseen:covers share/haseen/shell/{Bar,BarDragOverlay,BarOverflowCell,BarOverflowPanel}.qml
# haseen:covers share/haseen/shell/{BarSection,BarSlot,BarStrip}.qml
# haseen:covers share/haseen/shell/Compat/{DmsHost,OmarchyHost}.qml
# haseen:covers share/haseen/shell/Haseen/Widgets/BarButton.qml tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Dragging on the bar (plan 112): widgets anywhere, the bar to another edge,
# no arrange mode needed. The pure rules (BarDrag.js, Overflow.changes) under
# the Qt JS engine; then the bar's strip (BarStrip.qml, the very sections,
# pool and slots Bar.qml shows) in the real Quickshell engine, offscreen,
# with fixture widgets and real pointer events (QtTest's TestEvent): a press
# that stays under the threshold, the wheel and the other buttons reach every
# kind of widget, compat-hosted ones included; drags move widgets within and
# between sections, onto the chevron, into and out of the overflow drawer,
# without rebuilding them; widgets with drags of their own keep them; held or
# dragged empty space moves the bar. The drops are then replayed through
# `haseen bar move`. Bar.qml itself is a layer-shell window, which needs a
# compositor: its wiring is read from the source. What only a live Hyprland
# session shows (the compositor's pointer grab across windows and screens,
# the keyboard during a drag, the overlay window) is listed in the plan.

SHELL_DIR="$HASEEN_PATH/shell"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

# --- the rules, under the Qt JS engine --------------------------------------
sandbox bar-drag-units
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/BarDrag.js" as D
import "file://$SHELL_DIR/Overflow.js" as O

Item {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        // The threshold: past Qt's own drag distance, so a widget's own drag
        // starts first.
        eq("threshold: one and a half of Qt's distance", 15, D.threshold(10));
        eq("threshold: always above Qt's distance", true, D.threshold(4) > 4 && D.threshold(30) > 30);
        eq("threshold: no distance reported", 15, D.threshold(0));

        // The edge under the pointer, on a 1600x900 screen.
        const s = { width: 1600, height: 900 };
        eq("edge: near the top", "top", D.edgeAt({ x: 800, y: 50 }, s));
        eq("edge: near the bottom", "bottom", D.edgeAt({ x: 800, y: 850 }, s));
        eq("edge: near the left", "left", D.edgeAt({ x: 40, y: 450 }, s));
        eq("edge: near the right", "right", D.edgeAt({ x: 1560, y: 450 }, s));
        eq("edge: the diagonals in normalised space, not pixels", "left", D.edgeAt({ x: 200, y: 200 }, s));
        eq("edge: the centre counts as the top", "top", D.edgeAt({ x: 800, y: 450 }, s));
        eq("edge: a point off the screen counts on its border", "bottom", D.edgeAt({ x: 800, y: 5000 }, s));
        eq("edge: off the left", "left", D.edgeAt({ x: -300, y: 450 }, s));
        eq("edge: no size", "top", D.edgeAt({ x: 1, y: 1 }, null));

        // The bar window on its screen (Bar.qml's anchors and margins).
        const win = { width: 1602, height: 28 }, side = { width: 40, height: 902 };
        eq("origin: top bar", { x: -1, y: 0 }, D.windowOrigin("top", win, s, 1));
        eq("origin: bottom bar", { x: -1, y: 872 }, D.windowOrigin("bottom", win, s, 1));
        eq("origin: left bar", { x: 0, y: -1 }, D.windowOrigin("left", side, s, 1));
        eq("origin: right bar", { x: 1560, y: -1 }, D.windowOrigin("right", side, s, 1));
        eq("origin: no frame, no overlap", { x: 0, y: 0 }, D.windowOrigin("top", win, s, 0));

        // A section's rows while a widget is dragged.
        eq("rows: no drag", ["a", "b"], D.rows(["a", "b"], "left", null));
        eq("rows: a drop elsewhere", ["a", "b"], D.rows(["a", "b"], "left", { section: "right", before: "" }));
        eq("rows: the room in front of a widget", ["a", D.ROOM, "b"], D.rows(["a", "b"], "left", { section: "left", before: "b" }));
        eq("rows: the room at the end", ["a", "b", D.ROOM], D.rows(["a", "b"], "left", { section: "left", before: "" }));
        eq("rows: an empty section gets the room", [D.ROOM], D.rows([], "center", { section: "center", before: "" }));
        eq("rows: an unknown neighbour means the end", ["a", D.ROOM], D.rows(["a"], "left", { section: "left", before: "x" }));
        eq("rows: the panel opens no room in the bar", ["a"], D.rows(["a"], "left", { section: "overflow", before: "" }));
        eq("the room is no plugin id", false, /^[a-z0-9-]+(\\.[a-z0-9-]+)+$/.test(D.ROOM));

        // Whether a drop changes anything: a widget let go of where it was
        // needs no write.
        const L = { left: ["a", "b"], center: ["c"], right: ["haseen.tray", "x"], overflow: ["x"], pinned: [] };
        eq("changes: back where it was", false, O.changes(L, "a", "left", "b", false));
        eq("changes: at its own section's end, where it is", false, O.changes(L, "b", "left", "", false));
        eq("changes: in front of itself", false, O.changes(L, "a", "left", "a", false));
        eq("changes: a real move", true, O.changes(L, "b", "left", "a", false));
        eq("changes: to another section", true, O.changes(L, "a", "center", "", false));
        eq("changes: out of the panel, pinned", true, O.changes(L, "x", "right", "", true));
        eq("changes: into the panel", true, O.changes(L, "a", "overflow", "", false));
        eq("changes: the tray never moves", false, O.changes(L, "haseen.tray", "left", "", false));
        eq("changes: missing lists", true, O.changes({ left: ["a"] }, "a", "right", "", false));
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "drag unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "drag unit count" "34" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML_BIN"
fi

# --- Bar.qml's window: read from the source -----------------------------------
bar="$(cat "$SHELL_DIR/Bar.qml")"
assert_contains "the bar never takes the keyboard: a drag keeps its pointer grab" "$bar" \
    "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None"
assert_not_contains "no keyboard focus is asked for mid-drag" "$bar" "WlrKeyboardFocus.Exclusive"
assert_contains "the drag's window exists only while a drag lasts" "$bar" $'active: strip.dragging && !bar.hidden\n\n        BarDragOverlay {'
assert_contains "the bar's contents are the strip under test here" "$bar" "BarStrip {"
assert_contains "the bar's cross-axis size comes from the theme" "$(cat "$SHELL_DIR/Haseen/Config.qml")" "Theme.barMetrics.sizeHorizontal"
assert_not_contains "no hairline of its own" "$bar" "Hairline on the inner edge"
assert_contains "the drag's window is handed the strip" "$bar" $'BarDragOverlay {\n            screen: bar.screen\n            stripItem: strip'
overlay="$(cat "$SHELL_DIR/BarDragOverlay.qml")"
assert_contains "the drag's window takes no input" "$overlay" "mask: Region {}"
assert_contains "the drag's window is over everything" "$overlay" "WlrLayershell.layer: WlrLayer.Overlay"
assert_contains "the drag's window never takes the keyboard" "$overlay" "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None"
assert_contains "the drag's window reserves no room" "$overlay" "exclusionMode: ExclusionMode.Ignore"
# A property named `strip` here would shadow Bar.qml's id of that name and
# bind to itself: the overlay then reads every member of undefined (plan 118).
assert_contains "the overlay's strip is not shadowed by its own name" "$overlay" "required property var stripItem"
assert_contains "Escape in the overflow panel cancels a drag before it closes the panel" \
    "$(cat "$SHELL_DIR/BarOverflowPanel.qml")" $'if (panel.barWindow.dragging)\n                panel.barWindow.cancelDrag();'
strip="$(cat "$SHELL_DIR/BarStrip.qml")"
assert_contains "a silent drag ends on a marked single-shot timeout" "$strip" $'// haseen:ui-timeout\n    Timer {\n        id: watchdog'

# Plan 126: a press held still on a widget starts the coding agent on it.
slot="$(cat "$SHELL_DIR/BarSlot.qml")"
assert_contains "a held widget asks the bar to edit it" "$slot" "slot.host.editWidget(slot.modelData)"
assert_contains "after 700 ms" "$slot" "interval: 700"
assert_contains "only for the left button" "$slot" "centroid.pressedButtons & Qt.LeftButton"
assert_contains "and travel cancels the hold" "$slot" "p.position.x - p.pressPosition.x"
assert_contains "the strip runs haseen bar edit" "$strip" 'Quickshell.execDetached(["haseen", "bar", "edit", id])'
assert_eq "no colour literals in the drag's files" "" \
    "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$SHELL_DIR"/{Bar,BarStrip,BarSlot,BarSection,BarDragOverlay}.qml || true)"
assert_eq "no blur or shader in the drag's files" "" \
    "$(grep -nE 'MultiEffect|ShaderEffect|FastBlur|GaussianBlur|layer\.effect' "$SHELL_DIR"/{Bar,BarStrip,BarSlot,BarSection,BarDragOverlay}.qml || true)"

# --- the strip in the real engine ------------------------------------------------
if [[ ! -x $QS_BIN ]]; then
    _fail "qs missing: $QS_BIN"
else
    sandbox bar-drag-engine
    P="$XDG_CONFIG_HOME/haseen/plugins"
    mkdir -p "$P" "$XDG_CONFIG_HOME/omarchy/plugins"
    # fixture ID — a native bar widget; its body comes on stdin. Every widget
    # notes what reaches it and says when it is built and destroyed.
    fixture() {
        mkdir -p "$P/$1"
        printf '{"schemaVersion":1,"id":"%s","name":"%s","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"Widget.qml"}}\n' "$1" "$1" >"$P/$1/manifest.json"
        cat >"$P/$1/Widget.qml"
    }
    common='    property string pluginId
    property var settings: ({})
    property var screen: null
    property var log: []
    function note(s) { log = log.concat([s]); }
    Component.onCompleted: console.warn("BORN " + pluginId)
    Component.onDestruction: console.warn("DIED " + pluginId)'
    # A MouseArea taking every button and the wheel, as most widgets have.
    for id in me.a me.b me.c me.d; do
        fixture "$id" <<EOF
import QtQuick
Item {
    id: root
$common
    implicitWidth: 40
    implicitHeight: 20
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => root.note("click" + e.button)
        onDoubleClicked: e => root.note("dbl" + e.button)
        onCanceled: root.note("cancel")
        onWheel: e => root.note("wheel" + e.angleDelta.y)
    }
}
EOF
    done
    # BarButton, which nearly every built-in widget is.
    fixture me.button <<EOF
import QtQuick
import qs.Haseen.Widgets
BarButton {
    id: root
$common
    text: "btn"
    onClicked: b => root.note("click" + b)
    onScrolled: s => root.note("scroll" + s)
}
EOF
    # Pointer handlers instead of a MouseArea.
    fixture me.tap <<EOF
import QtQuick
Item {
    id: root
$common
    implicitWidth: 40
    implicitHeight: 20
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: (p, b) => root.note("tap" + b)
    }
    WheelHandler { onWheel: e => root.note("wheel" + e.angleDelta.y) }
}
EOF
    # Drags of their own: a MouseArea moving a knob, one that keeps the
    # mouse (a slider's way), and a widget that opts out.
    fixture me.own <<EOF
import QtQuick
Item {
    id: root
$common
    implicitWidth: 60
    implicitHeight: 20
    Item { id: knob; width: 10; height: 10 }
    MouseArea {
        anchors.fill: parent
        drag.target: knob
        onPressed: root.note("press")
        onReleased: root.note("knob" + Math.round(knob.x))
        onCanceled: root.note("cancel")
    }
}
EOF
    fixture me.slide <<EOF
import QtQuick
Item {
    id: root
$common
    implicitWidth: 60
    implicitHeight: 20
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        onReleased: e => root.note("release" + Math.round(e.x))
        onCanceled: root.note("cancel")
    }
}
EOF
    fixture me.slider <<EOF
import QtQuick
import QtQuick.Controls
Item {
    id: root
$common
    implicitWidth: 100
    implicitHeight: 20
    Slider {
        anchors.fill: parent
        from: 0
        to: 100
        onMoved: root.note("moved")
        onPressedChanged: root.note(pressed ? "press" : "release" + Math.round(value))
    }
}
EOF
    fixture me.optout <<EOF
import QtQuick
Item {
    id: root
$common
    readonly property bool barDraggable: false
    implicitWidth: 40
    implicitHeight: 20
    DragHandler { target: null; onActiveChanged: root.note(active ? "own-drag" : "own-drop") }
}
EOF
    # An Omarchy widget (OmarchyHost) and a DMS one (DmsHost).
    O="$XDG_CONFIG_HOME/omarchy/plugins/me.oma"
    mkdir -p "$O"
    printf '{"schemaVersion":1,"id":"me.oma","name":"Oma","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}\n' >"$O/manifest.json"
    cat >"$O/Widget.qml" <<'QML'
import QtQuick
Item {
    id: root
    property var bar
    property var settings
    property string moduleName
    property var log: []
    implicitWidth: 40
    implicitHeight: 20
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => root.log = root.log.concat(["click" + e.button])
        onWheel: e => root.log = root.log.concat(["wheel" + e.angleDelta.y])
    }
}
QML
    mkdir -p "$P/ClickFixture"
    printf '{"id":"clickFixture","name":"Click","version":"1.0.0","type":"widget","component":"./Widget.qml"}\n' >"$P/ClickFixture/plugin.json"
    cat >"$P/ClickFixture/Widget.qml" <<'QML'
import QtQuick
import qs.Widgets
import qs.Modules.Plugins
PluginComponent {
    id: root
    property int clicks: 0
    horizontalBarPill: Component { StyledText { text: "click" } }
    pillClickAction: (x, y, width, section, screen) => { root.clicks++; }
}
QML
    ids='"me.a","me.b","me.c","me.d","me.tap","me.button","me.own","me.slide","me.slider","me.optout","dms.click-fixture","me.oma"'
    layout='{"left":["me.a","me.b","me.tap"],"center":["me.button"],"right":["haseen.tray","me.c","me.d","me.own","me.slide","me.slider","me.optout","dms.click-fixture","me.oma"]}'
    jq -n --argjson bar "$layout" "[$ids]"' as $ids | {bar: $bar, plugins: ([$ids[] | {(.): {enabled: true}}] | add), services: []}' \
        >"$XDG_CONFIG_HOME/haseen/shell.json"
    cp "$XDG_CONFIG_HOME/haseen/shell.json" "$SANDBOX/shell.json.start"

    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for entry in "$SHELL_DIR"/*; do
        [[ ${entry##*/} == shell.qml ]] || ln -s "$entry" "$harness/${entry##*/}"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import QtTest
import qs.Haseen
import qs.Compat as Compat
import "Overflow.js" as Overflow

ShellRoot {
    id: probe
    property var r: ({})
    property var moves: []
    property var positions: []
    property int transparency: 0
    property var edits: []
    property int presses: 0
    property int step: 0
    property double mark: 0
    property var held: null
    property bool verticalPhase: false
    readonly property var ids: ["me.a", "me.b", "me.tap", "me.button", "me.c", "me.d", "me.own", "me.slide", "me.slider", "me.optout", "dms.click-fixture", "me.oma", "haseen.tray"]

    function since() { return Date.now() - mark; }
    function next() { step++; mark = Date.now(); }
    function slot(id) { return strip.slots[id] || null; }
    // The widget itself: a compat host's widget, else the slot's item.
    function w(id) {
        const s = slot(id);
        if (!s || !s.item) return null;
        return s.item.widget ? s.item.widget : s.item;
    }
    function logOf(id) { const x = w(id); return x && x.log ? x.log.join(",") : (x && x.clicks !== undefined ? "clicks" + x.clicks : "?"); }
    function clearLog(id) { const x = w(id); if (x && x.log) x.log = []; }
    function pos(id) { const s = slot(id); return s.mapToItem(strip, s.width / 2, s.height / 2); }
    function edge(id, f) { const s = slot(id); return s.mapToItem(strip, s.width * f, s.height / 2); }
    function click(id, b) { const p = pos(id); ev.mouseClick(strip, p.x, p.y, b, 0, -1); }
    function down(x, y) { ev.mousePress(strip, x, y, Qt.LeftButton, 0, -1); }
    function to(x, y) { ev.mouseMove(strip, x, y, -1, Qt.LeftButton, 0); }
    function up(x, y) { ev.mouseRelease(strip, x, y, Qt.LeftButton, 0, -1); }
    // Press at a, then move to b in steps of 5 px.
    function drag(a, b) {
        down(a.x, a.y);
        const n = Math.max(1, Math.ceil(Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y)) / 5));
        for (let i = 1; i <= n; i++) to(a.x + (b.x - a.x) * i / n, a.y + (b.y - a.y) * i / n);
    }
    function find(item, pred) {
        if (pred(item)) return item;
        for (const c of item.children) { const hit = find(c, pred); if (hit) return hit; }
        return null;
    }
    function section(name) { return find(win.contentItem, o => o.objectName === "barSection-" + name); }
    function chevron() { return find(win.contentItem, o => o.objectName === "barOverflowChevron"); }
    function rows(name) { return section(name).rows.map(id => id === "\u0000room" ? "ROOM" : id); }
    // What shell.qml's moveWidget does with a drop: one list at a time.
    function apply(m) {
        const b = Config.bar;
        const res = Overflow.move({ left: b.left, center: b.center, right: b.right, overflow: b.overflow, pinned: b.pinned }, m[0], m[1], m[2], m[3]);
        for (const k of ["left", "center", "right", "overflow", "pinned"])
            if (JSON.stringify(res[k]) !== JSON.stringify(Config._ids(b[k])))
                Config.setRuntime(["bar", k], res[k]);
    }
    // Empty bar space between the left and the centre sections.
    function emptyPoint() {
        const l = slot("me.tap").mapToItem(strip, slot("me.tap").width, 0).x;
        const c = slot("me.button").mapToItem(strip, 0, 0).x;
        return Qt.point(Math.round((l + c) / 2), 14);
    }
    function finish() { console.warn("RESULT " + JSON.stringify(r)); Qt.quit(); }

    QtObject {
        id: fakeShell
        property var openPanels: []
        function togglePanel(id) {}
        function closePanel(id) {}
        function focusedScreen() { return null; }
    }
    Binding { target: Compat.Runtime; property: "nativeShell"; value: fakeShell }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1400
        implicitHeight: 28
        BarStrip {
            id: strip
            anchors.fill: parent
            screen: ({ name: "T-1", width: 1400, height: 800 })
            position: "top"
            onMoveRequested: (id, to, before, pin) => probe.moves = probe.moves.concat([[id, to, before, pin]])
            onPositionRequested: pos => probe.positions = probe.positions.concat([pos])
            onTransparencyToggleRequested: probe.transparency++
            onOverflowEditRequested: (verb, id) => probe.edits = probe.edits.concat([[verb, id]])
            onWidgetPressed: probe.presses++
        }
        TestEvent { id: ev }
    }

    // A left bar, built only for the last steps.
    LazyLoader {
        id: vLoader
        active: probe.verticalPhase
        FloatingWindow {
            property alias strip: vs
            visible: true
            implicitWidth: 48
            implicitHeight: 700
            BarStrip {
                id: vs
                anchors.fill: parent
                screen: ({ name: "T-2", width: 1400, height: 800 })
                position: "left"
                onMoveRequested: (id, to, before, pin) => probe.moves = probe.moves.concat([[id, to, before, pin]])
                onPositionRequested: pos => probe.positions = probe.positions.concat([pos])
            }
        }
    }

    // A stand-in for the overflow panel's window (BarOverflowPanel.qml is a
    // layer-shell window): the real cells, placed as if under the bar.
    QtObject {
        id: fakePanel
        readonly property real ox: 600
        readonly property real oy: 28
        function toBar(x, y) { return Qt.point(x + ox, y + oy); }
        function fromBar(x, y) { return Qt.point(x - ox, y - oy); }
        function cardContains(x, y) { return x >= 0 && y >= 0 && x < panelWin.width && y < panelWin.height; }
    }
    FloatingWindow {
        id: panelWin
        visible: strip.overflowOpen
        implicitWidth: 300
        implicitHeight: 80
        Flow {
            id: panelFlow
            x: 10; y: 10
            width: 280
            spacing: 6
            Repeater {
                model: ScriptModel { values: strip.overflowOpen ? strip.overflowShown : [] }
                delegate: BarOverflowCell { bar: strip }
            }
        }
    }
    Binding { target: strip; property: "panel"; value: strip.overflowOpen ? fakePanel : null }

    Timer {
        interval: 30
        repeat: true
        running: true
        onTriggered: {
            const r = probe.r;
            const S = probe;
            switch (probe.step) {
            case 0:
                if (S.ids.some(id => !S.slot(id) || (!S.slot(id).shown && id !== "haseen.tray")) || S.since() < 500) {
                    if (S.since() > 20000) { r.notReady = S.ids.filter(id => !S.slot(id) || !S.slot(id).shown); S.finish(); }
                    break;
                }
                r.rightToLeft = I18n.rightToLeft;
                r.pool = strip.poolIds;
                r.threshold = strip.dragThreshold;
                r.tray = [S.slot("haseen.tray").fixed, S.slot("haseen.tray").draggable];
                r.chevronIdle = S.chevron().visible;
                for (const id of ["me.a", "me.button", "me.tap", "me.oma", "dms.click-fixture"]) {
                    S.click(id, Qt.LeftButton);
                    S.click(id, Qt.RightButton);
                    S.click(id, Qt.MiddleButton);
                    const p = S.pos(id);
                    ev.mouseWheel(strip, p.x, p.y, 0, 0, 0, 120, -1);
                }
                r.dragAfterClicks = strip.dragId;
                S.next(); break;
            case 1:
                r.clicks = {};
                for (const id of ["me.a", "me.button", "me.tap", "me.oma", "dms.click-fixture"]) { r.clicks[id] = S.logOf(id); S.clearLog(id); }
                r.presses = S.presses;
                // A press that moves less than the threshold stays a click.
                { const p = S.pos("me.b"); S.down(p.x, p.y); S.to(p.x + 6, p.y + 2); r.smallDragId = strip.dragId; S.up(p.x + 6, p.y + 2); }
                S.next(); break;
            case 2:
                r.smallMove = S.logOf("me.b"); S.clearLog("me.b");
                r.movesAfterSmall = S.moves.length;
                // A double click on a widget: the widget's, and the bar's
                // transparency too (plan 051).
                { const p = S.pos("me.b"); ev.mouseDoubleClickSequence(strip, p.x, p.y, Qt.LeftButton, 0, -1); }
                S.next(); break;
            case 3:
                r.widgetDouble = S.logOf("me.b"); S.clearLog("me.b");
                r.transparencyAfterWidgetDouble = S.transparency;
                // me.a into me.b's second half: it lands in front of me.tap.
                S.drag(S.pos("me.a"), S.edge("me.b", 0.75));
                r.dragId = strip.dragId;
                r.drop = strip.drop;
                r.leftRows = S.rows("left");
                r.chevronDuringDrag = S.chevron().visible;
                r.aDuringDrag = S.logOf("me.a");
                r.liftedWidth = S.slot("me.a").parent.width;
                S.next(); break;
            case 4:
                if (S.since() < 200) break; // the room opens, the picture is taken
                r.ghost = String(strip.ghostUrl) !== "";
                r.dragLength = strip.dragLength;
                { const room = S.section("left").children.find(c => c.room === true); r.roomWidth = room ? room.width : -1; }
                S.clearLog("me.a");
                { const p = S.edge("me.b", 0.75); S.up(p.x, p.y); }
                r.dragIdAtRelease = strip.dragId;
                S.next(); break;
            case 5:
                r.moveWithin = S.moves.slice();
                r.dragIdAfter = strip.dragId;
                r.chevronAfter = S.chevron().visible;
                r.aAfterDrop = S.logOf("me.a"); S.clearLog("me.a");
                S.apply(S.moves[S.moves.length - 1]);
                S.next(); break;
            case 6:
                if (S.since() < 100) break;
                r.leftAfterWithin = strip.layoutIds.left;
                // Across sections: me.b in front of me.d, measured once the
                // drag has begun (the chevron shows and the right section
                // makes way for it).
                S.held = S.w("me.b");
                S.drag(S.pos("me.b"), Qt.point(S.pos("me.b").x + 20, S.pos("me.b").y));
                { const p = S.edge("me.d", 0.25); S.to(p.x, p.y); }
                r.crossDrop = strip.drop;
                r.rightRows = S.rows("right");
                { const p = S.edge("me.d", 0.25); S.up(p.x, p.y); }
                S.next(); break;
            case 7:
                r.moveAcross = S.moves[S.moves.length - 1];
                S.apply(S.moves[S.moves.length - 1]);
                S.next(); break;
            case 8:
                if (S.since() < 150) break;
                r.rightAfterAcross = strip.layoutIds.right;
                r.sameInstance = S.w("me.b") === S.held;
                r.bInRightSection = S.slot("me.b").parent === strip.sectionCells["me.b"] && S.section("right").children.indexOf(S.slot("me.b").parent) >= 0;
                S.clearLog("me.b");
                S.click("me.b", Qt.LeftButton);
                r.bClickAfterMove = S.logOf("me.b");
                // Onto the chevron: the overflow panel's end.
                S.drag(S.pos("me.c"), Qt.point(S.pos("me.c").x + 20, S.pos("me.c").y));
                { const ch = S.chevron(); const c = ch.mapToItem(strip, ch.width / 2, ch.height / 2); S.to(c.x, c.y); r.chevronDrop = strip.drop; r.chevronHighlighted = ch.highlighted; S.up(c.x, c.y); }
                S.next(); break;
            case 9:
                r.moveOverflow = S.moves[S.moves.length - 1];
                // Let go of off the bar: nothing.
                S.held = S.moves.length;
                S.drag(S.pos("me.d"), Qt.point(S.pos("me.d").x, 300));
                r.offBarDrop = strip.drop;
                S.up(S.pos("me.d").x, 300);
                S.next(); break;
            case 10:
                r.offBarMoves = S.moves.length - S.held;
                r.offBarDragId = strip.dragId;
                // Escape (Bar.cancelDrag): nothing, even let go of on a target.
                S.held = S.moves.length;
                S.drag(S.pos("me.d"), S.edge("me.a", 0.25));
                r.cancelArmed = strip.dragId;
                strip.cancelDrag();
                r.cancelDragId = strip.dragId;
                r.cancelRows = S.rows("left");
                { const p = S.edge("me.a", 0.25); S.up(p.x, p.y); }
                S.next(); break;
            case 11:
                r.cancelMoves = S.moves.length - S.held;
                r.dAfterCancel = S.logOf("me.d");
                // Widgets with drags of their own keep them.
                S.held = S.moves.length;
                { const p = S.pos("me.own"); S.drag(p, Qt.point(p.x + 40, p.y + 3)); r.ownDragId = strip.dragId; S.up(p.x + 40, p.y + 3); }
                { const p = S.pos("me.slide"); S.drag(p, Qt.point(p.x + 40, p.y)); r.slideDragId = strip.dragId; S.up(p.x + 40, p.y); }
                { const p = S.edge("me.slider", 0.1); S.drag(p, Qt.point(p.x + 60, p.y)); r.sliderDragId = strip.dragId; S.up(p.x + 60, p.y); }
                { const p = S.pos("me.optout"); S.drag(p, Qt.point(p.x + 40, p.y)); r.optoutDragId = strip.dragId; S.up(p.x + 40, p.y); }
                S.next(); break;
            case 12:
                r.own = S.logOf("me.own"); r.slide = S.logOf("me.slide"); r.optout = S.logOf("me.optout");
                r.slider = S.logOf("me.slider");
                r.movesAfterOwn = S.moves.length - S.held;
                // Empty bar space, held: the bar moves.
                { const e = S.emptyPoint(); r.empty = strip.onEmpty(e.x, e.y); S.down(e.x, e.y); r.movingAtPress = strip.barMoving; }
                S.next(); break;
            case 13:
                if (S.since() < 350) break;
                r.heldMoving = strip.barMoving;
                r.heldEdge = strip.barEdge;
                r.keyboardWhileMoving = strip.dragging;
                { const e = S.emptyPoint(); S.to(e.x, 700); r.dragEdge = strip.barEdge; S.up(e.x, 700); }
                S.next(); break;
            case 14:
                r.positions = S.positions.slice();
                r.movingAfter = strip.barMoving;
                // A short press moves nothing; two make a double click.
                { const e = S.emptyPoint(); ev.mouseClick(strip, e.x, e.y, Qt.LeftButton, 0, -1); r.shortMoving = strip.barMoving; S.held = S.transparency; ev.mouseClick(strip, e.x, e.y, Qt.LeftButton, 0, -1); }
                S.next(); break;
            case 15:
                r.emptyDoubleToggles = S.transparency - S.held;
                r.positionsAfterShort = S.positions.length;
                // Dragged past the threshold without a hold; Escape cancels it.
                { const e = S.emptyPoint(); S.drag(e, Qt.point(e.x - 40, e.y)); r.dragMoving = strip.barMoving; S.to(5, 400); r.leftEdge = strip.barEdge; strip.cancelBarMove(); S.up(5, 400); }
                S.next(); break;
            case 16:
                if (S.since() < 100) break;
                r.positionsAfterCancel = S.positions.length;
                // Right click on empty space: arrange mode. A click there
                // moves a widget to the panel, a drag still drags.
                { const e = S.emptyPoint(); ev.mouseClick(strip, e.x + 3, e.y, Qt.RightButton, 0, -1); r.arranging = strip.arranging; }
                S.click("me.a", Qt.LeftButton);
                r.arrangeEdits = S.edits.slice();
                r.aLogArrange = S.logOf("me.a");
                S.drag(S.pos("me.a"), S.edge("me.b", 0.25));
                r.arrangeDragId = strip.dragId;
                { const p = S.edge("me.b", 0.25); S.up(p.x, p.y); }
                S.next(); break;
            case 17:
                r.arrangeMove = S.moves[S.moves.length - 1];
                strip.setArranging(false);
                S.apply(S.moves[2]); // me.c into bar.overflow
                S.next(); break;
            case 18:
                if (S.since() < 150) break;
                r.fitIds = strip.fit.ids;
                r.chevronWithOverflow = S.chevron().visible;
                strip.overflowOpen = true;
                S.next(); break;
            case 19:
                if (S.since() < 150) break;
                r.cInPanel = S.slot("me.c").parent === strip.cells["me.c"] && !strip.inTrack(S.slot("me.c"));
                S.clearLog("me.c");
                { const sl = S.slot("me.c"); ev.mouseClick(sl, sl.width / 2, sl.height / 2, Qt.LeftButton, 0, -1); ev.mouseClick(sl, sl.width / 2, sl.height / 2, Qt.RightButton, 0, -1); }
                r.cClickInPanel = S.logOf("me.c");
                // Out of the panel into the bar, in front of me.a: pinned.
                { const sl = S.slot("me.c"); const a = S.edge("me.a", 0.25); const target = Qt.point(a.x - fakePanel.ox, a.y - fakePanel.oy);
                  ev.mousePress(sl, sl.width / 2, sl.height / 2, Qt.LeftButton, 0, -1);
                  const start = sl.mapToItem(null, sl.width / 2, sl.height / 2);
                  for (let i = 1; i <= 20; i++) ev.mouseMove(panelFlow, start.x + (target.x - start.x) * i / 20 - panelFlow.x, start.y + (target.y - start.y) * i / 20 - panelFlow.y, -1, Qt.LeftButton, 0);
                  r.outOfPanelDrop = strip.drop; r.outDragId = strip.dragId;
                  ev.mouseRelease(panelFlow, target.x - panelFlow.x, target.y - panelFlow.y, Qt.LeftButton, 0, -1); }
                S.next(); break;
            case 20:
                r.outOfPanelMove = S.moves[S.moves.length - 1];
                // From the bar into the open panel, onto me.c's cell's first half.
                { const p = S.pos("me.d"); S.down(p.x, p.y); S.to(p.x + 20, p.y); const c = S.slot("me.c"); const q = c.mapToItem(null, 2, c.height / 2); S.to(q.x + fakePanel.ox, q.y + fakePanel.oy); r.intoPanelDrop = strip.drop; S.up(q.x + fakePanel.ox, q.y + fakePanel.oy); }
                S.next(); break;
            case 21:
                r.intoPanelMove = S.moves[S.moves.length - 1];
                strip.overflowOpen = false;
                r.cBackInBar = S.slot("me.c").parent === strip.sectionCells["me.c"];
                // The left bar builds widgets of its own from here.
                console.warn("VERTICAL-PHASE");
                probe.verticalPhase = true;
                S.next(); break;
            case 22:
                if (!vLoader.item || S.since() < 600) break;
                { const vs = vLoader.item.strip; const sl = n => vs.slots[n];
                  const at = (n, f) => sl(n).mapToItem(vs, sl(n).width / 2, sl(n).height * f);
                  r.vertical = [vs.vertical, sl("me.a").width, sl("me.a").height];
                  const a = at("me.a", 0.5);
                  ev.mousePress(vs, a.x, a.y, Qt.LeftButton, 0, -1);
                  for (let i = 1; i <= 6; i++) ev.mouseMove(vs, a.x, a.y + i * 5, -1, Qt.LeftButton, 0);
                  const t = at("me.tap", 0.75);
                  ev.mouseMove(vs, t.x, t.y, -1, Qt.LeftButton, 0);
                  r.verticalDrop = vs.drop;
                  ev.mouseRelease(vs, t.x, t.y, Qt.LeftButton, 0, -1); }
                S.next(); break;
            case 23:
                r.verticalMove = S.moves[S.moves.length - 1];
                // A left bar moved: the pointer near its screen's right edge.
                { const vs = vLoader.item.strip;
                  const lo = vs.slots["me.tap"].mapToItem(vs, 0, vs.slots["me.tap"].height).y, hi = vs.slots["me.button"].mapToItem(vs, 0, 0).y;
                  const e = Qt.point(24, Math.round((lo + hi) / 2)); r.vEmpty = vs.onEmpty(e.x, e.y);
                  ev.mousePress(vs, e.x, e.y, Qt.LeftButton, 0, -1);
                  for (let i = 1; i <= 6; i++) ev.mouseMove(vs, e.x + i * 5, e.y, -1, Qt.LeftButton, 0);
                  ev.mouseMove(vs, 1300, 400, -1, Qt.LeftButton, 0);
                  r.vEdge = vs.barEdge;
                  ev.mouseRelease(vs, 1300, 400, Qt.LeftButton, 0, -1); }
                S.next(); break;
            case 24:
                r.vPositions = S.positions.slice();
                r.moves = S.moves;
                // The same drops from the starting bar, by the shell's rule.
                {
                    const st = JSON.parse(Quickshell.env("BAR_DRAG_START"));
                    let l = { left: st.bar.left, center: st.bar.center, right: st.bar.right, overflow: [], pinned: [] };
                    for (const m of S.moves)
                        l = Overflow.move(l, m[0], m[1], m[2], m[3]) || l;
                    r.replay = [l.left, l.center, l.right, l.overflow, l.pinned];
                }
                S.finish();
            }
        }
    }
}
QML
    # scenario LANGUAGE — the scenario from the starting bar, in a display
    # language (plan 109); its RESULT line ends up in R.
    scenario() {
        cp "$SANDBOX/shell.json.start" "$XDG_CONFIG_HOME/haseen/shell.json"
        printf '%s\n' "$1" >"$XDG_CONFIG_HOME/haseen/language"
        capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            QT_FORCE_STDERR_LOGGING=1 BAR_DRAG_START="$(cat "$SANDBOX/shell.json.start")" timeout 90 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
        assert_status "the drag scenario completes in the real engine ($1)" 0 "$STATUS"
        R="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    }
    # Arabic first: the bar is never mirrored (plan 109), so every drag, drop
    # and edge must come out exactly as in English.
    scenario ar
    RTL="$R"
    scenario en
    assert_eq "the Arabic run is right to left" true "$(jq '.rightToLeft' <<<"$RTL")"
    assert_eq "in Arabic every drag, drop and bar move is the same as in English" \
        "$(jq -cS 'del(.rightToLeft)' <<<"$R")" "$(jq -cS 'del(.rightToLeft)' <<<"$RTL")"
    if [[ -z $R ]]; then
        _fail "the drag scenario produced no result" "$OUTPUT"
    else
        g() { jq -c "$1" <<<"$R"; }
        assert_eq "every fixture loaded" "null" "$(g .notReady)"
        assert_eq "one pool entry per shown widget, in a fixed order" \
            '["dms.click-fixture","haseen.tray","me.a","me.b","me.button","me.c","me.d","me.oma","me.optout","me.own","me.slide","me.slider","me.tap"]' "$(g .pool)"
        assert_eq "the threshold is past Qt's drag distance" true "$(jq '.threshold > 10' <<<"$R")"
        assert_eq "the tray is fixed and never dragged" '[true,false]' "$(g .tray)"
        assert_eq "no chevron while nothing overflows and nothing is dragged" false "$(g .chevronIdle)"

        # A plain click, the other buttons and the wheel, exactly as before.
        assert_eq "a native widget gets left, right, middle and the wheel" '"click1,click2,click4,wheel120"' "$(g '.clicks["me.a"]')"
        assert_eq "a BarButton widget gets its clicks and steps" '"click1,click2,click4,scroll1"' "$(g '.clicks["me.button"]')"
        assert_eq "a TapHandler widget gets its taps and the wheel" '"tap1,tap2,tap4,wheel120"' "$(g '.clicks["me.tap"]')"
        assert_eq "an Omarchy widget (OmarchyHost) gets its presses" '"click1,click2,click4,wheel120"' "$(g '.clicks["me.oma"]')"
        assert_eq "a DMS widget (DmsHost) runs its click action" '"clicks1"' "$(g '.clicks["dms.click-fixture"]')"
        assert_eq "no click started a drag" '""' "$(g .dragAfterClicks)"
        assert_eq "every press is still reported for panel placement" 15 "$(g .presses)"
        assert_eq "a press that moves under the threshold is no drag" '""' "$(g .smallDragId)"
        assert_eq "… and stays the widget's click" '"click1"' "$(g .smallMove)"
        assert_eq "… with nothing saved" 0 "$(g .movesAfterSmall)"
        assert_eq "a double click on a widget is the widget's" '"click1,dbl1"' "$(g .widgetDouble)"
        assert_eq "… and still asks for transparency, as before" 1 "$(g .transparencyAfterWidgetDouble)"

        # A drag within a section.
        assert_eq "past the threshold the widget is dragged" '"me.a"' "$(g .dragId)"
        assert_eq "the drop is computed as the pointer moves" '{"section":"left","before":"me.tap"}' "$(jq -c '.drop | {section, before}' <<<"$R")"
        assert_eq "the section opens a room where it would land" '["me.a","me.b","ROOM","me.tap"]' "$(g .leftRows)"
        assert_eq "the room is the widget's length" '[40,40]' "$(jq -c '[.dragLength, .roomWidth]' <<<"$R")"
        assert_eq "the lifted widget's cell folds away" 0 "$(g .liftedWidth)"
        assert_eq "the widget's own press is cancelled: no click" '"cancel"' "$(g .aDuringDrag)"
        assert_eq "nor a click when it lands" '""' "$(g .aAfterDrop)"
        assert_eq "the chevron shows during the drag" true "$(g .chevronDuringDrag)"
        assert_eq "a ghost picture is taken" true "$(g .ghost)"
        assert_eq "it lands after the release has been handled" '"me.a"' "$(g .dragIdAtRelease)"
        assert_eq "one move, in front of me.tap" '[["me.a","left","me.tap",false]]' "$(g .moveWithin)"
        assert_eq "the drag is over" '""' "$(g .dragIdAfter)"
        assert_eq "the chevron goes again" false "$(g .chevronAfter)"
        assert_eq "the section in its new order" '["me.b","me.a","me.tap"]' "$(g .leftAfterWithin)"

        # Between sections, never rebuilt.
        assert_eq "across sections: in front of me.d" '{"section":"right","before":"me.d"}' "$(jq -c '.crossDrop | {section, before}' <<<"$R")"
        assert_eq "the right section opens the room" '["haseen.tray","me.c","ROOM","me.d","me.own","me.slide","me.slider","me.optout","dms.click-fixture","me.oma"]' "$(g .rightRows)"
        assert_eq "the move asked for" '["me.b","right","me.d",false]' "$(g .moveAcross)"
        assert_eq "the right section after it" '["haseen.tray","me.c","me.b","me.d","me.own","me.slide","me.slider","me.optout","dms.click-fixture","me.oma"]' "$(g .rightAfterAcross)"
        assert_eq "the widget is the same instance after the move" true "$(g .sameInstance)"
        assert_eq "… in its new section's cell" true "$(g .bInRightSection)"
        assert_eq "… and still gets its clicks" '"click1"' "$(g .bClickAfterMove)"
        assert_eq "me.b was built once, however it moved" 1 "$(sed -n '/VERTICAL-PHASE/q;p' <<<"$OUTPUT" | grep -cE 'BORN me\.b$')"
        assert_eq "no fixture was destroyed by a move" "" "$(sed -n '/VERTICAL-PHASE/q;s/^.*DIED //p' <<<"$OUTPUT")"

        # Into the overflow panel: the chevron and the open drawer.
        assert_eq "the chevron takes a drop for the panel's end" '{"section":"overflow","before":""}' "$(g .chevronDrop)"
        assert_eq "… and lights up under it" true "$(g .chevronHighlighted)"
        assert_eq "the move into the panel" '["me.c","overflow","",false]' "$(g .moveOverflow)"
        assert_eq "the panel then holds it" '["me.c"]' "$(g .fitIds)"
        assert_eq "the chevron shows for it" true "$(g .chevronWithOverflow)"
        assert_eq "open, the widget sits in the panel's cell" true "$(g .cInPanel)"
        assert_eq "… and gets its clicks there" '"click1,click2"' "$(g .cClickInPanel)"
        assert_eq "dragged out of the panel, it lands in the bar" '{"section":"left","before":"me.a"}' "$(jq -c '.outOfPanelDrop | {section, before}' <<<"$R")"
        assert_eq "… pinned, so the fit does not send it back" '["me.c","left","me.a",true]' "$(g .outOfPanelMove)"
        assert_eq "dragged from the bar over the open panel: in front of the cell under it" '{"section":"overflow","before":"me.c"}' "$(g .intoPanelDrop)"
        assert_eq "the move into the panel, in front of me.c" '["me.d","overflow","me.c",false]' "$(g .intoPanelMove)"
        assert_eq "closed, the widget is back in its bar cell" true "$(g .cBackInBar)"

        # Cancelling.
        assert_eq "let go of off the bar: no target" null "$(g .offBarDrop)"
        assert_eq "… nothing saved" 0 "$(g .offBarMoves)"
        assert_eq "… and the drag is over" '""' "$(g .offBarDragId)"
        assert_eq "Escape's cancel ends the drag" '["me.d",""]' "$(jq -c '[.cancelArmed, .cancelDragId]' <<<"$R")"
        assert_eq "… closes the room" '["me.a","me.tap"]' "$(g .cancelRows)"
        assert_eq "… and nothing lands on release" 0 "$(g .cancelMoves)"
        assert_eq "neither drag clicked the widget" '"cancel,cancel"' "$(g .dAfterCancel)"

        # Widgets that drag themselves.
        assert_eq "a MouseArea with drag.target keeps its drag" '["","press,knob25"]' "$(jq -c '[.ownDragId, .own]' <<<"$R")"
        assert_eq "a MouseArea that keeps the mouse keeps it" '["","release70"]' "$(jq -c '[.slideDragId, .slide]' <<<"$R")"
        assert_eq "a Slider keeps its drag" '""' "$(g .sliderDragId)"
        assert_contains "… and moves its value" "$(g .slider)" "moved"
        assert_eq "barDraggable: false leaves the widget's own drag alone" '["","own-drag,own-drop"]' "$(jq -c '[.optoutDragId, .optout]' <<<"$R")"
        assert_eq "none of them moved" 0 "$(g .movesAfterOwn)"

        # The bar itself.
        assert_eq "the test point is empty bar space" true "$(g .empty)"
        assert_eq "a press alone does not move the bar" false "$(g .movingAtPress)"
        assert_eq "held 200 ms, the bar is lifted at its own edge" '[true,"top"]' "$(jq -c '[.heldMoving, .heldEdge]' <<<"$R")"
        assert_eq "the bar keeps the keyboard while it moves (Escape)" true "$(g .keyboardWhileMoving)"
        assert_eq "dragged down, the bottom edge" '"bottom"' "$(g .dragEdge)"
        assert_eq "let go of, it moves there" '["bottom"]' "$(g .positions)"
        assert_eq "… and the move is over" false "$(g .movingAfter)"
        assert_eq "a short press never moves the bar" '[false,1]' "$(jq -c '[.shortMoving, .positionsAfterShort]' <<<"$R")"
        assert_eq "a double click on empty space still asks for transparency" 1 "$(g .emptyDoubleToggles)"
        assert_eq "dragged past the threshold, no hold needed" '[true,"left"]' "$(jq -c '[.dragMoving, .leftEdge]' <<<"$R")"
        assert_eq "Escape's cancel leaves the bar where it is" 1 "$(g .positionsAfterCancel)"

        # Arrange mode stays.
        assert_eq "a right click on empty space still arranges" true "$(g .arranging)"
        assert_eq "arrange mode's click still moves a widget to the panel" '[["add","me.a"]]' "$(g .arrangeEdits)"
        assert_eq "… and the widget does not get it" '""' "$(g .aLogArrange)"
        assert_eq "a drag works in arrange mode too" '["me.a",["me.a","right","me.b",false]]' "$(jq -c '[.arrangeDragId, .arrangeMove]' <<<"$R")"

        # A vertical bar.
        assert_eq "a left bar: square cells the bar's width" '[true,48,48]' "$(g .vertical)"
        assert_eq "… dragged down past me.tap: the section's end" '{"section":"left","before":""}' "$(jq -c '.verticalDrop | {section, before}' <<<"$R")"
        assert_eq "… saved" '["me.a","left","",false]' "$(g .verticalMove)"
        assert_eq "a left bar moved toward the right edge of its screen" '[true,"right"]' "$(jq -c '[.vEmpty, .vEdge]' <<<"$R")"
        assert_eq "… moves there" '["bottom","right"]' "$(g .vPositions)"
        assert_not_contains "no binding loop" "$OUTPUT" "Binding loop"
        assert_not_contains "no QML type error" "$OUTPUT" "TypeError"

        # The drops, saved through `haseen bar move`: the shell.json the CLI
        # writes holds what the shell's rule gives.
        cp "$SANDBOX/shell.json.start" "$XDG_CONFIG_HOME/haseen/shell.json"
        stub qs 'exit 0'
        while read -r move; do
            id="$(jq -r '.[0]' <<<"$move")" to="$(jq -r '.[1]' <<<"$move")" before="$(jq -r '.[2]' <<<"$move")"
            args=("$id" "$to")
            [[ -n $before ]] && args+=(--before "$before")
            [[ $(jq -r '.[3]' <<<"$move") == true ]] && args+=(--pin)
            capture haseen bar move "${args[@]}" --no-apply
            assert_status "haseen bar move ${args[*]}" 0 "$STATUS"
        done < <(jq -c '.moves[]' <<<"$R")
        assert_eq "the CLI and the drops end with the same bar" "$(g .replay)" \
            "$(jq -c '[.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned] | map(. // [])' "$XDG_CONFIG_HOME/haseen/shell.json")"
    fi
fi

# --- haseen bar arrange: no longer needed, still answering ------------------------
sandbox bar-drag-cli
capture haseen bar arrange --help
assert_status "arrange --help exits 0" 0 "$STATUS"
assert_contains "arrange says drags need no arrange mode" "$OUTPUT" "Dragging needs no arrange mode"
capture haseen bar move --help
assert_contains "move points at dragging on the bar" "$OUTPUT" "drag a widget on the bar"
capture haseen bar position --help
assert_contains "position points at dragging the bar" "$OUTPUT" "empty bar space"
