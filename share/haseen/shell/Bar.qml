import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "Overflow.js" as Overflow

// One bar per screen, on the edge shell.json `bar.position` names. Three
// sections of bar-widget plugins (left/center/right, top to bottom when the
// bar is vertical). With the screen frame on, the bar is the frame's thick
// edge (Frame.qml draws the rest); without it, a hairline marks the inner edge.
//
// Double-clicking the bar asks for transparency (plan 015, after Omarchy's
// shell/plugins/bar/Bar.qml toggleTransparency, MIT, Copyright (c) David
// Heinemeier Hansson): on empty space and, as in Omarchy, on a widget too,
// since a full bar has little empty space left (the chevron and arrange mode
// excepted). `transparent` comes from FrameTextColor: it turns true only once
// a legible text colour for the wallpaper is known.
//
// Overflow (architecture 5.3): when the sections do not fit the bar's length,
// widgets move into a panel behind a chevron at the end of the bar
// (Overflow.js decides which, BarOverflowPanel.qml shows them). Each bar
// computes its own, from its own length, so every screen gets its own answer.
// The fit is recomputed when a widget's size, the bar's length or the
// overflow settings change: a binding collects them and a deferred call
// computes it, no timer.
PanelWindow {
    id: bar

    property bool hidden: false
    property bool transparent: false
    readonly property string position: Config.barPosition
    readonly property bool vertical: Config.barVertical
    // A hidden bar leaves a frame-thick strip so the frame stays closed.
    readonly property int thickness: !hidden ? Config.barThickness : Config.frameEnabled ? Config.frameThickness : 0
    // With the frame on, the bar reaches 1 px under the frame strips at both
    // of its ends (the seam note in Frame.qml).
    readonly property int overlap: Config.frameEnabled ? 1 : 0
    // The bar's length along its edge, as the popups measure it.
    readonly property real extent: (vertical ? height : width) - 2 * overlap

    // Each id once, the tray first in the right section (Overflow.sections).
    readonly property var layoutIds: Overflow.sections(Config.section("left"), Config.section("center"), Config.section("right"))
    readonly property int spacing: Math.round(Theme.gap / 2)
    readonly property var fitSpec: ({
            length: vertical ? track.height : track.width,
            spacing: spacing,
            gap: Theme.gap,
            button: vertical ? overflowButton.implicitHeight : overflowButton.implicitWidth,
            hysteresis: Theme.gap * 2,
            left: entries(leftSection),
            center: entries(centerSection),
            right: entries(rightSection),
            overflow: Config.barOverflow,
            pinned: Config.barPinned
        })
    property var fit: ({
            ids: [],
            shown: [],
            autoRight: 0,
            autoLeft: 0,
            button: false,
            fits: true
        })
    // What the overflow panel shows, in order: for `bar status` too.
    readonly property var overflowShown: fit.shown
    property bool overflowOpen: false
    // Arrange mode: a click on a widget, in the bar or in the panel, moves it
    // to the other one, and a drag moves it where it is dropped (within a
    // section, to another one, into or out of the panel). The panel is open
    // while arranging, even with nothing in it, to drop widgets into.
    property bool arranging: false
    // The widget being dragged while arranging, and where it would land
    // (Overflow.dropTarget's answer, or { section: "overflow", before }),
    // or null.
    property string dragId: ""
    property var drop: null
    // The overflow panel's cell for each id while it is open.
    property var cells: ({})
    // When a widget inside the overflow panel was last pressed (Date.now()).
    property real overflowPressTime: 0
    // The button's centre along the bar, measured like an opener's centre.
    readonly property real buttonCentre: (vertical ? track.y + overflowButton.y + overflowButton.height / 2 : track.x + overflowButton.x + overflowButton.width / 2) - overlap

    signal transparencyToggleRequested
    // A press on a bar widget, as PanelPlacement.js's opener.
    signal widgetPressed(var opener)
    // A click while arranging: `haseen bar overflow <verb> <id>` (add or pin).
    signal overflowEditRequested(string verb, string id)
    // A drop while arranging: `haseen bar move <id> <to> --before <before>`.
    signal moveRequested(string id, string to, string before, bool pin)
    // The panel's edge buttons while arranging: `haseen bar position <pos>`.
    signal positionRequested(string pos)

    function entries(section: Item): var {
        return section.shownIds.map(id => ({
                    id: id,
                    size: section.lengths[id] || 0
                }));
    }

    function refit(): void {
        fit = Overflow.fit(fitSpec, fit);
    }

    function registerCell(id: string, item: Item): void {
        const next = Object.assign({}, cells);
        next[id] = item;
        cells = next;
    }

    function unregisterCell(id: string, item: Item): void {
        if (cells[id] !== item)
            return;
        const next = Object.assign({}, cells);
        delete next[id];
        cells = next;
    }

    function inTrack(item: Item): bool {
        for (let n = item; n; n = n.parent)
            if (n === track)
                return true;
        return false;
    }

    // Where a drag at (x, y) in this window's coordinates would land, or
    // null: in the bar, the gap Overflow.dropTarget picks (the chevron
    // means the panel's end); over the open panel's card, in front of the
    // cell Overflow.panelTarget picks.
    function dropAt(id: string, x: real, y: real): var {
        if (x >= 0 && y >= 0 && x < width && y < height) {
            const b = overflowButton.mapFromItem(null, x, y);
            if (overflowButton.visible && overflowButton.contains(b))
                return {
                    section: "overflow",
                    before: ""
                };
            const t = track.mapFromItem(null, x, y);
            return Overflow.dropTarget(vertical ? t.y : t.x, {
                length: vertical ? track.height : track.width,
                spacing: spacing,
                left: leftSection.spans(track),
                center: centerSection.spans(track),
                right: rightSection.spans(track)
            }, id);
        }
        const panel = overflowLoader.item;
        if (!panel)
            return null;
        const p = panel.fromBar(x, y);
        if (!panel.cardContains(p.x, p.y))
            return null;
        const rects = [];
        for (const cid of overflowShown) {
            const holder = cells[cid];
            if (!holder)
                continue;
            const o = holder.mapToItem(null, 0, 0);
            rects.push({
                id: cid,
                x: o.x,
                y: o.y,
                w: holder.width,
                h: holder.height
            });
        }
        return {
            section: "overflow",
            before: Overflow.panelTarget(p, rects, id)
        };
    }

    // A drag from a slot, in that slot's window: this bar or the panel.
    function dragUpdate(id: string, slot: Item, x: real, y: real): void {
        let p = Qt.point(x, y);
        if (!inTrack(slot)) {
            const panel = overflowLoader.item;
            if (!panel) {
                drop = null;
                return;
            }
            p = panel.toBar(x, y);
        }
        dragId = id;
        drop = dropAt(id, p.x, p.y);
    }

    // After the release has been handled: the move reparents (or rebuilds)
    // the very slot whose MouseArea is delivering it.
    function dragFinish(id: string, dropped: bool): void {
        const d = drop;
        dragId = "";
        drop = null;
        if (!dropped || !d)
            return;
        // Out of the panel means "here, for good": pinned, so the fit does
        // not send it straight back.
        const pin = d.section !== "overflow" && fit.ids.indexOf(id) >= 0;
        Qt.callLater(() => bar.moveRequested(id, d.section, d.before, pin));
    }

    function setArranging(on: bool): void {
        arranging = on;
        overflowOpen = on || (overflowOpen && overflowShown.length > 0);
    }

    // The bar spans its edge and the popups share its origin
    // (PanelPlacement.place), so the slot's centre in this window's
    // coordinates, less the overlap, is where along the edge a panel it
    // opens belongs. The overflow panel's window spans the same edge from
    // that origin (without the overlap), so a widget in it is measured the
    // same way and its own panel opens under it.
    function reportPress(slot: Item): void {
        const inBar = inTrack(slot);
        if (!inBar)
            overflowPressTime = Date.now();
        const c = slot.mapToItem(null, slot.width / 2, slot.height / 2);
        bar.widgetPressed({
            screen: bar.screen,
            position: bar.position,
            centre: (bar.vertical ? c.y : c.x) - (inBar ? overlap : 0),
            extent: bar.extent,
            time: Date.now()
        });
    }

    onFitSpecChanged: Qt.callLater(bar.refit)
    onOverflowShownChanged: {
        if (overflowShown.length === 0 && !arranging)
            overflowOpen = false;
    }
    onHiddenChanged: overflowOpen = false
    onOverflowOpenChanged: {
        if (!overflowOpen)
            arranging = false;
    }

    visible: thickness > 0
    anchors {
        top: bar.position !== "bottom"
        bottom: bar.position !== "top"
        left: bar.position !== "right"
        right: bar.position !== "left"
    }
    margins {
        top: bar.vertical ? -bar.overlap : 0
        bottom: bar.vertical ? -bar.overlap : 0
        left: bar.vertical ? 0 : -bar.overlap
        right: bar.vertical ? 0 : -bar.overlap
    }
    implicitWidth: thickness
    implicitHeight: thickness
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: thickness
    color: transparent ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) : Theme.background
    WlrLayershell.namespace: "haseen-bar"
    // Quickshell picks an opaque buffer when the first colour is opaque, and
    // transparency would then render black. Ask for alpha up front.
    surfaceFormat.opaque: false
    WlrLayershell.layer: WlrLayer.Top

    // The owner's frame cross-fades with the bar over 420 ms (t1nk33r.screen-frame).
    Behavior on color {
        ColorAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }

    // Below the sections: a right click on empty bar space arranges, as one
    // on the chevron does.
    MouseArea {
        anchors.fill: parent
        enabled: !bar.hidden
        acceptedButtons: Qt.RightButton
        onClicked: bar.setArranging(!bar.arranging)
    }

    Item {
        id: track

        anchors.fill: parent
        anchors.leftMargin: bar.vertical ? 0 : Theme.gap + bar.overlap
        anchors.rightMargin: bar.vertical ? 0 : Theme.gap + bar.overlap
        anchors.topMargin: bar.vertical ? Theme.gap + bar.overlap : 0
        anchors.bottomMargin: bar.vertical ? Theme.gap + bar.overlap : 0
        visible: !bar.hidden

        // Each section is anchored on both axes, the one across the bar
        // being a no-op (the section spans it). Anchoring only the axis along
        // the bar left a section at its old offset after a live switch
        // between a vertical and a horizontal bar: removing an anchor keeps
        // the position it set, so the right section sat outside a 28 px bar.
        BarSection {
            id: leftSection

            anchors.left: parent.left
            anchors.top: parent.top
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: bar.layoutIds.left
            screen: bar.screen
            overflowIds: bar.fit.ids
            cells: bar.cells
            fixedIds: ["haseen.tray"]
            arranging: bar.arranging
            onWidgetPressed: slot => bar.reportPress(slot)
            onMoveRequested: (id, overflowed) => bar.overflowEditRequested(overflowed ? "pin" : "add", id)
            dragId: bar.dragId
            onDragMoved: (id, slot, x, y) => bar.dragUpdate(id, slot, x, y)
            onDragEnded: (id, dropped) => bar.dragFinish(id, dropped)
        }

        BarSection {
            id: centerSection

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: bar.layoutIds.center
            screen: bar.screen
            overflowIds: bar.fit.ids
            cells: bar.cells
            fixedIds: ["haseen.tray"]
            arranging: bar.arranging
            onWidgetPressed: slot => bar.reportPress(slot)
            onMoveRequested: (id, overflowed) => bar.overflowEditRequested(overflowed ? "pin" : "add", id)
            dragId: bar.dragId
            onDragMoved: (id, slot, x, y) => bar.dragUpdate(id, slot, x, y)
            onDragEnded: (id, dropped) => bar.dragFinish(id, dropped)
        }

        // Before the overflow button when it shows (left of it, or above it
        // in a vertical bar).
        BarSection {
            id: rightSection

            anchors.right: bar.vertical || !overflowButton.visible ? parent.right : overflowButton.left
            anchors.bottom: !bar.vertical || !overflowButton.visible ? parent.bottom : overflowButton.top
            anchors.rightMargin: !bar.vertical && overflowButton.visible ? bar.spacing : 0
            anchors.bottomMargin: bar.vertical && overflowButton.visible ? bar.spacing : 0
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: bar.layoutIds.right
            screen: bar.screen
            overflowIds: bar.fit.ids
            cells: bar.cells
            fixedIds: ["haseen.tray"]
            arranging: bar.arranging
            onWidgetPressed: slot => bar.reportPress(slot)
            onMoveRequested: (id, overflowed) => bar.overflowEditRequested(overflowed ? "pin" : "add", id)
            dragId: bar.dragId
            onDragMoved: (id, slot, x, y) => bar.dragUpdate(id, slot, x, y)
            onDragEnded: (id, dropped) => bar.dragFinish(id, dropped)
        }

        // Where a dragged widget would land in the bar.
        Rectangle {
            readonly property bool shown: bar.drop !== null && bar.drop.section !== "overflow"

            visible: shown
            x: !shown ? 0 : bar.vertical ? 2 : Math.round(bar.drop.at - width / 2)
            y: !shown ? 0 : bar.vertical ? Math.round(bar.drop.at - height / 2) : 2
            width: bar.vertical ? track.width - 4 : 2
            height: bar.vertical ? 2 : track.height - 4
            radius: 1
            color: Theme.accent
        }

        // The overflow button, at the very end of the bar, only while
        // something is in overflow. The chevron points where the panel
        // opens, and turns round while it is open. A right click opens it
        // in arrange mode.
        BarButton {
            id: overflowButton

            readonly property var glyphs: ({
                    top: ["\uf078", "\uf077"],
                    bottom: ["\uf077", "\uf078"],
                    left: ["\uf054", "\uf053"],
                    right: ["\uf053", "\uf054"]
                })

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            visible: bar.fit.button || bar.overflowOpen
            glyph: glyphs[bar.position][bar.overflowOpen ? 1 : 0]
            highlighted: bar.overflowOpen || (bar.drop !== null && bar.drop.section === "overflow")
            onClicked: button => {
                if (button === Qt.LeftButton) {
                    bar.overflowOpen = !bar.overflowOpen;
                } else if (button === Qt.RightButton) {
                    bar.setArranging(!bar.overflowOpen || !bar.arranging);
                }
            }
        }
    }

    // Over everything but the chevron, and only passive: a double click on a
    // widget still reaches the widget, and both presses still open or close
    // whatever it opens, as in Omarchy's bar. A PointHandler, as on the
    // slots (BarSection.qml): it only ever takes a passive grab. A TapHandler
    // here kept every widget from seeing its clicks (nested Hyprland). Two
    // presses within the double-click interval and distance make a double
    // click, as Qt counts them.
    Item {
        anchors.fill: parent

        PointHandler {
            property real lastTime: 0
            property point lastAt: Qt.point(0, 0)

            enabled: !bar.hidden && !bar.arranging
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (!active)
                    return;
                const p = point.scenePosition;
                const now = Date.now();
                const near = Math.abs(p.x - lastAt.x) + Math.abs(p.y - lastAt.y) <= Qt.styleHints.startDragDistance;
                if (now - lastTime > Qt.styleHints.mouseDoubleClickInterval || !near) {
                    lastTime = now;
                    lastAt = p;
                    return;
                }
                lastTime = 0;
                const b = overflowButton.mapFromItem(null, p.x, p.y);
                if (!overflowButton.visible || !overflowButton.contains(b))
                    bar.transparencyToggleRequested();
            }
        }
    }

    // Lazy, like every panel: nothing exists until the button is clicked,
    // and closing it frees the window again (the widgets go back to their
    // parked cells in the bar first, BarSection.qml).
    LazyLoader {
        id: overflowLoader

        active: bar.overflowOpen && (bar.overflowShown.length > 0 || bar.arranging) && !bar.hidden

        BarOverflowPanel {
            barWindow: bar
            screen: bar.screen
            ids: bar.overflowShown
            centre: bar.buttonCentre
            arranging: bar.arranging
            dropBefore: bar.drop !== null && bar.drop.section === "overflow" ? bar.drop.before : null
            onArrangeToggled: bar.setArranging(!bar.arranging)
            onCloseRequested: bar.overflowOpen = false
            onPositionRequested: pos => bar.positionRequested(pos)
        }
    }

    // Hairline on the inner edge, only when no frame continues the bar.
    Rectangle {
        visible: !Config.frameEnabled && !bar.transparent && !bar.hidden
        x: bar.position === "left" ? parent.width - width : 0
        y: bar.position === "top" ? parent.height - height : 0
        width: bar.vertical ? Theme.borderWidth : parent.width
        height: bar.vertical ? parent.height : Theme.borderWidth
        color: Theme.border
    }
}
