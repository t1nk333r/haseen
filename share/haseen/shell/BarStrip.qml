import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Overflow.js" as Overflow
import "BarDrag.js" as BarDrag

// Everything in one bar but its window (plan 112): the three sections of
// bar-widget plugins (left/center/right, top to bottom when the bar is
// vertical), the pool of widgets they show, the overflow chevron, and every
// pointer gesture on the bar. Bar.qml puts it in a layer-shell window; tests
// load it in an ordinary one.
//
// Widgets are kept in a pool, one BarSlot per shown id, in an order that
// does not depend on the sections, and each moves into the cell its section
// keeps for it (BarSection.qml): moving a widget never rebuilds it.
//
// Dragging, after Omarchy's bar (shell/plugins/bar/Bar.qml, v4.5.0-rc1,
// MIT, Copyright (c) David Heinemeier Hansson). There the bar takes every
// press on a widget and hands clicks on; here the widget keeps its press, and
// only a press that travels BarDrag.threshold becomes a drag (BarSlot.qml).
// The bar is never mirrored (plan 109), so a drag reads the same in every
// language.
// - A widget, dragged, follows the pointer as a ghost (BarDragOverlay.qml)
//   and leaves a room where it would land: within its section, in another
//   one, on the chevron (which shows during every drag; the overflow panel's
//   end) or, while the panel is open, in front of the panel cell under the
//   pointer; out of the panel into the bar it is pinned, so the fit does not
//   send it straight back. Where it lands is worked out against the bar as
//   the drag found it (`frozen`), so the room moving does not move the
//   target. Letting go saves it through `haseen bar move` (moveRequested,
//   shell.qml); letting go anywhere else, Escape (Bar.qml) or a cancelled
//   grab puts it back with nothing saved. The tray never moves and nothing
//   lands in front of it (Overflow.dropTarget, Overflow.move).
// - Empty bar space, held for 200 ms or dragged past the threshold, moves
//   the bar: the edge nearest the pointer is previewed (BarDragOverlay.qml)
//   and letting go there saves it like `haseen bar position`
//   (positionRequested). The position is one for every screen; the pointer's
//   place on the screen it is dragged on picks the edge. A short press never
//   moves the bar; a double click (transparency) and a right click (arrange
//   mode) on empty space work as before.
//
// Overflow (architecture 5.3): when the sections do not fit the bar's length,
// widgets move into a panel behind a chevron at the end of the bar
// (Overflow.js decides which, BarOverflowPanel.qml shows them). The fit is
// recomputed when a widget's size, the bar's length or the overflow settings
// change: a binding collects them and a deferred call computes it, no timer.
// It waits while a widget is dragged, so nothing moves under the pointer.
//
// haseen.nook (plan 095), when it sits in a section, is that panel's opener
// instead of the chevron: the panel opens under it, the chevron shows only
// in arrange mode or during a drag (as a drop target), and the nook never
// moves into the panel it opens (Overflow.fit's `never`).
Item {
    id: strip

    // The bar's screen: name, width, height.
    required property var screen
    property string position: "top"
    readonly property bool vertical: position === "left" || position === "right"
    // How far the bar window reaches past each end of its edge (Bar.qml).
    property int overlap: 0
    property bool hidden: false
    // The open overflow panel (BarOverflowPanel.qml): toBar, fromBar,
    // cardContains. Null while it is closed.
    property var panel: null
    // The nook's widget while it is in this bar (it registers on the window).
    property Item nookItem: null

    // The bar's length along its edge, as the popups measure it.
    readonly property real extent: (vertical ? height : width) - 2 * overlap
    // Each id once, the tray first in the right section (Overflow.sections).
    readonly property var layoutIds: Overflow.sections(Config.section("left"), Config.section("center"), Config.section("right"))
    // Every shown widget once, sorted, so a move between sections leaves it
    // as it is.
    readonly property var shownIds: layoutIds.left.concat(layoutIds.center, layoutIds.right).filter(id => Config.isEnabled(id)).sort()
    // The pool: shownIds, an id leaving it a moment later (prunePool). A
    // move written one list at a time (shell.qml's moveWidget sets
    // bar.left, then bar.right) takes the widget out of every section in
    // between, and would otherwise rebuild it.
    property var poolIds: []
    readonly property string nookId: "haseen.nook"
    readonly property bool nookHosted: Config.isEnabled(nookId) && Plugins.componentUrl(nookId, "bar-widget") !== "" && shownIds.indexOf(nookId) >= 0
    readonly property int spacing: Math.round(Theme.gap / 2)
    // Across the bar: the size every slot takes that way.
    readonly property real cross: vertical ? track.width : track.height
    // Ids that never move.
    readonly property var fixedIds: ["haseen.tray"]
    readonly property int dragThreshold: BarDrag.threshold(Qt.styleHints.startDragDistance)

    readonly property var fitSpec: ({
            length: vertical ? track.height : track.width,
            spacing: spacing,
            gap: Theme.gap,
            button: nookHosted && !arranging ? 0 : vertical ? overflowButton.implicitHeight : overflowButton.implicitWidth,
            never: [nookId],
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
    // A fit asked for while a widget was dragged, made once it lands.
    property bool refitPending: false
    // What the overflow panel shows, in order: for `bar status` too.
    readonly property var overflowShown: fit.shown
    property bool overflowOpen: false
    // Where along the bar the open panel is centred when an opener other
    // than the chevron (the nook) opened it; -1 means the chevron.
    property real overflowCentre: -1
    // The chevron: it points where the panel opens, and turns round while
    // it is open. The nook shows the same one.
    readonly property var overflowGlyphs: ({
            top: ["", ""],
            bottom: ["", ""],
            left: ["", ""],
            right: ["", ""]
        })
    readonly property string overflowGlyph: overflowGlyphs[position][overflowOpen ? 1 : 0]
    // Arrange mode: a click on a widget, in the bar or in the panel, moves it
    // to the other one, and the panel shows the bar's four edges. The panel
    // is open while arranging, even with nothing in it. Drags work with or
    // without it.
    property bool arranging: false
    // The overflow panel's cell for each id while it is open
    // (BarOverflowCell.qml), each section's cell for each id
    // (BarSection.qml), each id's slot (BarSlot.qml).
    property var cells: ({})
    property var sectionCells: ({})
    property var slots: ({})
    // id -> natural length along the bar.
    property var lengths: ({})
    // When a widget inside the overflow panel was last pressed (Date.now()).
    property real overflowPressTime: 0
    // The button's centre along the bar, measured like an opener's centre.
    readonly property real buttonCentre: (vertical ? track.y + overflowButton.y + overflowButton.height / 2 : track.x + overflowButton.x + overflowButton.width / 2) - overlap

    // The widget being dragged, where it would land (Overflow.dropTarget's
    // answer, or { section: "overflow", before }) or null, and the bar as the
    // drag found it.
    property string dragId: ""
    property Item dragSlot: null
    property var drop: null
    property var frozen: null
    property real dragLength: 0
    // The pointer, in this item's (the bar window's) coordinates, and where
    // in the widget it took hold of it.
    property point dragAt: Qt.point(0, 0)
    property point dragGrip: Qt.point(0, 0)
    // Shows the chevron for a drag before the bar is measured for it.
    property bool dragArmed: false
    // The dragged widget's picture, once taken.
    property url ghostUrl: ""
    // The bar being moved, and the edge it would go to.
    property bool barMoving: false
    property string barEdge: ""
    readonly property bool dragging: dragId !== "" || barMoving
    // The pointer on its screen, for the ghost.
    readonly property point dragScreenAt: {
        const o = BarDrag.windowOrigin(position, {
            width: width,
            height: height
        }, screenSize(), overlap);
        return Qt.point(o.x + dragAt.x, o.y + dragAt.y);
    }

    signal transparencyToggleRequested
    // A press on a bar widget, as PanelPlacement.js's opener.
    signal widgetPressed(var opener)
    // A click while arranging: `haseen bar overflow <verb> <id>` (add or pin).
    signal overflowEditRequested(string verb, string id)
    // A drop: `haseen bar move <id> <to> --before <before> [--pin]`.
    signal moveRequested(string id, string to, string before, bool pin)
    // A bar let go of over another edge, or the panel's edge buttons:
    // `haseen bar position <pos>`.
    signal positionRequested(string pos)

    function screenSize(): var {
        return {
            width: screen && screen.width > 0 ? screen.width : width,
            height: screen && screen.height > 0 ? screen.height : height
        };
    }

    function entries(section: Item): var {
        return section.shownIds.map(id => ({
                    id: id,
                    size: lengths[id] || 0
                }));
    }

    function syncPool(): void {
        const add = shownIds.filter(id => poolIds.indexOf(id) < 0);
        if (add.length > 0)
            poolIds = poolIds.concat(add).sort();
        if (poolIds.some(id => shownIds.indexOf(id) < 0))
            Qt.callLater(strip.prunePool);
    }

    function prunePool(): void {
        const keep = poolIds.filter(id => shownIds.indexOf(id) >= 0);
        if (keep.length !== poolIds.length)
            poolIds = keep;
    }

    function refit(): void {
        if (dragId !== "") {
            refitPending = true;
            return;
        }
        refitPending = false;
        fit = Overflow.fit(fitSpec, fit);
    }

    // Copy, change, assign: a binding reading the map sees every change.
    function setIn(map: var, id: string, value: var): var {
        const next = Object.assign({}, map);
        if (value === null)
            delete next[id];
        else
            next[id] = value;
        return next;
    }

    function registerCell(id: string, item: Item): void {
        cells = setIn(cells, id, item);
    }

    function unregisterCell(id: string, item: Item): void {
        if (cells[id] === item)
            cells = setIn(cells, id, null);
    }

    function registerSectionCell(id: string, item: Item): void {
        sectionCells = setIn(sectionCells, id, item);
    }

    function unregisterSectionCell(id: string, item: Item): void {
        if (sectionCells[id] === item)
            sectionCells = setIn(sectionCells, id, null);
    }

    function registerSlot(id: string, slot: Item): void {
        slots = setIn(slots, id, slot);
    }

    function unregisterSlot(id: string, slot: Item): void {
        if (dragSlot === slot)
            cancelDrag();
        if (slots[id] === slot)
            slots = setIn(slots, id, null);
    }

    function report(id: string, length: real): void {
        if (lengths[id] !== length)
            lengths = setIn(lengths, id, length);
    }

    function forget(id: string): void {
        if (id in lengths)
            lengths = setIn(lengths, id, null);
    }

    // Where a widget's slot sits: the open panel's cell while it is in
    // overflow, else its section's cell (folded there while in overflow),
    // else parked.
    function hostFor(id: string): Item {
        if (fit.ids.indexOf(id) >= 0 && cells[id])
            return cells[id];
        return sectionCells[id] || parking;
    }

    function inTrack(item: Item): bool {
        for (let n = item; n; n = n.parent)
            if (n === track)
                return true;
        return false;
    }

    function over(item: Item, x: real, y: real): bool {
        return item !== null && item.visible && item.contains(item.mapFromItem(strip, x, y));
    }

    // A point on empty bar space: no widget, chevron or nook under it.
    function onEmpty(x: real, y: real): bool {
        if (over(overflowButton, x, y))
            return false;
        const p = track.mapFromItem(strip, x, y);
        const along = vertical ? p.y : p.x;
        for (const section of [leftSection, centerSection, rightSection])
            for (const span of section.spans(track))
                if (along >= span.start && along < span.end)
                    return false;
        return true;
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
        widgetPressed({
            screen: screen,
            position: position,
            centre: (vertical ? c.y : c.x) - (inBar ? overlap : 0),
            extent: extent,
            time: Date.now()
        });
    }

    function arrangeClicked(id: string): void {
        overflowEditRequested(fit.ids.indexOf(id) >= 0 ? "pin" : "add", id);
    }

    // The nook's click: open (or close) the panel centred under `item`,
    // measured as reportPress measures a widget.
    function toggleOverflowFrom(item: Item): void {
        if (overflowOpen) {
            overflowOpen = false;
            return;
        }
        const c = item.mapToItem(null, item.width / 2, item.height / 2);
        overflowCentre = (vertical ? c.y : c.x) - overlap;
        overflowOpen = true;
    }

    function setArranging(on: bool): void {
        arranging = on;
        overflowOpen = on || (overflowOpen && overflowShown.length > 0);
    }

    // A point a slot reports, in its own window's coordinates, in this
    // item's: as it is in the bar, or mapped from the overflow panel.
    function toStrip(slot: Item, p: point): var {
        if (inTrack(slot))
            return strip.mapFromItem(null, p.x, p.y);
        if (!panel)
            return null;
        const b = panel.toBar(p.x, p.y);
        return strip.mapFromItem(null, b.x, b.y);
    }

    // Where a drag at (x, y) in this item's coordinates would land, or
    // null: on the chevron or the nook, the panel's end; in the bar, the gap
    // Overflow.dropTarget picks from the bar as the drag found it; over the
    // open panel's card, in front of the cell Overflow.panelTarget picks.
    // The nook never goes into the panel it opens.
    function dropAt(id: string, x: real, y: real): var {
        if (x >= 0 && y >= 0 && x < width && y < height) {
            if (over(overflowButton, x, y) || (nookItem && nookItem !== slots[id] && over(nookItem, x, y)))
                return id === nookId ? null : {
                    section: "overflow",
                    before: ""
                };
            if (!frozen)
                return null;
            const t = track.mapFromItem(strip, x, y);
            return Overflow.dropTarget(vertical ? t.y : t.x, frozen, id);
        }
        if (!panel || id === nookId)
            return null;
        const b = strip.mapToItem(null, x, y);
        const p = panel.fromBar(b.x, b.y);
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

    // A widget's drag passed the threshold (BarSlot.qml). `grip` is where in
    // the slot it was pressed, `at` the pointer in the slot's window.
    function beginDrag(id: string, slot: Item, grip: point, at: point): void {
        if (dragging)
            return;
        const p = toStrip(slot, at);
        if (!p)
            return;
        // The chevron shows first, so the right section is measured where it
        // stays for the drag.
        dragArmed = true;
        frozen = {
            length: vertical ? track.height : track.width,
            spacing: spacing,
            left: leftSection.spans(track),
            center: centerSection.spans(track),
            right: rightSection.spans(track)
        };
        dragSlot = slot;
        dragLength = slot.length;
        dragGrip = grip;
        dragAt = p;
        doubleTap.forget();
        dragId = id;
        drop = dropAt(id, p.x, p.y);
        watchdog.restart();
        const item = slot.item;
        if (item && typeof item.grabToImage === "function")
            item.grabToImage(result => {
                if (strip.dragSlot === slot && result)
                    strip.ghostUrl = result.url;
            });
    }

    function moveDrag(id: string, slot: Item, at: point): void {
        if (dragId !== id)
            return;
        const p = toStrip(slot, at);
        if (!p)
            return;
        dragAt = p;
        drop = dropAt(id, p.x, p.y);
        watchdog.restart();
    }

    // After the release has been handled: the move reparents the very slot
    // whose handler is delivering it. A cancel in between (the handler's
    // canceled() follows its deactivation) leaves nothing to land.
    function releaseDrag(id: string): void {
        Qt.callLater(strip.landDrag, id);
    }

    function landDrag(id: string): void {
        if (dragId !== id)
            return;
        const d = drop;
        const pin = d !== null && d.section !== "overflow" && fit.ids.indexOf(id) >= 0;
        endDrag();
        if (d === null)
            return;
        const b = Config.bar;
        if (Overflow.changes({
                left: b.left,
                center: b.center,
                right: b.right,
                overflow: b.overflow,
                pinned: b.pinned
            }, id, d.section, d.before, pin))
            moveRequested(id, d.section, d.before, pin);
    }

    function cancelDrag(): void {
        if (dragId !== "")
            endDrag();
    }

    function endDrag(): void {
        dragId = "";
        drop = null;
        frozen = null;
        dragSlot = null;
        dragArmed = false;
        ghostUrl = "";
        if (!barMoving)
            watchdog.stop();
        if (refitPending)
            Qt.callLater(strip.refit);
    }

    // Empty bar space held or dragged (the area below the sections).
    function beginBarMove(): void {
        if (dragging || hidden)
            return;
        doubleTap.forget();
        barEdge = position;
        barMoving = true;
        watchdog.restart();
    }

    function updateBarMove(x: real, y: real): void {
        if (!barMoving)
            return;
        const o = BarDrag.windowOrigin(position, {
            width: width,
            height: height
        }, screenSize(), overlap);
        barEdge = BarDrag.edgeAt({
            x: o.x + x,
            y: o.y + y
        }, screenSize());
        watchdog.restart();
    }

    function finishBarMove(): void {
        if (!barMoving)
            return;
        const edge = barEdge;
        cancelBarMove();
        // Later: the bar moves to the new edge under the handler that is
        // delivering this release.
        if (edge !== "" && edge !== position)
            Qt.callLater(() => strip.positionRequested(edge));
    }

    function cancelBarMove(): void {
        barMoving = false;
        barEdge = "";
        if (dragId === "")
            watchdog.stop();
    }

    onShownIdsChanged: syncPool()
    Component.onCompleted: syncPool()
    onFitSpecChanged: Qt.callLater(strip.refit)
    onOverflowShownChanged: {
        if (overflowShown.length === 0 && !arranging)
            overflowOpen = false;
    }
    onHiddenChanged: {
        overflowOpen = false;
        cancelDrag();
        cancelBarMove();
    }
    onOverflowOpenChanged: {
        if (!overflowOpen) {
            arranging = false;
            overflowCentre = -1;
        }
    }

    // A drag that hears nothing for this long is over: Bar.qml takes the
    // keyboard while one lasts (for Escape), and a release the compositor
    // never delivered must not keep it.
    // haseen:ui-timeout
    Timer {
        id: watchdog

        interval: 15000
        repeat: false
        onTriggered: {
            strip.cancelDrag();
            strip.cancelBarMove();
        }
    }

    // Below the sections: a right click on empty bar space arranges, as one
    // on the chevron does. A widget whose own MouseArea takes only the left
    // button lets a right click fall through to here, so one over a widget is
    // ignored (leaving arrange mode still works from anywhere).
    MouseArea {
        anchors.fill: parent
        enabled: !strip.hidden
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            if (!strip.arranging && !strip.onEmpty(mouse.x, mouse.y))
                return;
            strip.setArranging(!strip.arranging);
        }
    }

    // Below the sections too: empty bar space held, or dragged past the
    // threshold, moves the bar. A press that a widget does not take (one
    // without a MouseArea of its own) falls through to here and is let go.
    MouseArea {
        id: barMove

        property point pressAt: Qt.point(0, 0)

        anchors.fill: parent
        enabled: !strip.hidden
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 200
        cursorShape: strip.barMoving ? Qt.ClosedHandCursor : undefined
        onPressed: mouse => {
            if (!strip.onEmpty(mouse.x, mouse.y)) {
                mouse.accepted = false;
                return;
            }
            pressAt = Qt.point(mouse.x, mouse.y);
        }
        onPressAndHold: mouse => {
            if (pressed)
                strip.beginBarMove();
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (!strip.barMoving) {
                if (Math.abs(mouse.x - pressAt.x) + Math.abs(mouse.y - pressAt.y) < strip.dragThreshold)
                    return;
                strip.beginBarMove();
            }
            strip.updateBarMove(mouse.x, mouse.y);
        }
        onReleased: strip.finishBarMove()
        onCanceled: strip.cancelBarMove()
    }

    Item {
        id: track

        anchors.fill: parent
        anchors.leftMargin: strip.vertical ? 0 : Theme.gap + strip.overlap
        anchors.rightMargin: strip.vertical ? 0 : Theme.gap + strip.overlap
        anchors.topMargin: strip.vertical ? Theme.gap + strip.overlap : 0
        anchors.bottomMargin: strip.vertical ? Theme.gap + strip.overlap : 0
        visible: !strip.hidden

        // Where a slot waits while no cell is its (between one section's
        // cell going and another's coming): clipped, never invisible.
        Item {
            id: parking

            width: 0
            height: 0
            clip: true
        }

        // The pool: one slot per shown widget, which moves into its cell.
        Instantiator {
            model: ScriptModel {
                values: strip.poolIds
            }

            delegate: BarSlot {
                host: strip
            }
        }

        // Each section is anchored on both axes, the one across the bar
        // being a no-op (the section spans it). Anchoring only the axis along
        // the bar left a section at its old offset after a live switch
        // between a vertical and a horizontal bar: removing an anchor keeps
        // the position it set, so the right section sat outside a 28 px bar.
        BarSection {
            id: leftSection

            anchors.left: parent.left
            anchors.top: parent.top
            width: strip.vertical ? parent.width : implicitWidth
            height: strip.vertical ? implicitHeight : parent.height
            vertical: strip.vertical
            ids: strip.layoutIds.left
            name: "left"
            host: strip
        }

        BarSection {
            id: centerSection

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: strip.vertical ? parent.width : implicitWidth
            height: strip.vertical ? implicitHeight : parent.height
            vertical: strip.vertical
            ids: strip.layoutIds.center
            name: "center"
            host: strip
        }

        // Before the overflow button when it shows (left of it, or above it
        // in a vertical bar).
        BarSection {
            id: rightSection

            anchors.right: strip.vertical || !overflowButton.visible ? parent.right : overflowButton.left
            anchors.bottom: !strip.vertical || !overflowButton.visible ? parent.bottom : overflowButton.top
            anchors.rightMargin: !strip.vertical && overflowButton.visible ? strip.spacing : 0
            anchors.bottomMargin: strip.vertical && overflowButton.visible ? strip.spacing : 0
            width: strip.vertical ? parent.width : implicitWidth
            height: strip.vertical ? implicitHeight : parent.height
            vertical: strip.vertical
            ids: strip.layoutIds.right
            name: "right"
            host: strip
        }

        // The overflow button, at the very end of the bar, while something
        // is in overflow (with the nook in the bar, only in arrange mode),
        // and during every drag as a drop target. A right click opens it in
        // arrange mode.
        BarButton {
            id: overflowButton

            objectName: "barOverflowChevron"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: strip.vertical ? parent.width : implicitWidth
            height: strip.vertical ? implicitHeight : parent.height
            vertical: strip.vertical
            visible: strip.dragArmed || (strip.nookHosted ? strip.arranging : strip.fit.button || strip.overflowOpen)
            glyph: strip.overflowGlyph
            highlighted: strip.overflowOpen || (strip.drop !== null && strip.drop.section === "overflow")
            onClicked: button => {
                if (button === Qt.LeftButton) {
                    strip.overflowOpen = !strip.overflowOpen;
                } else if (button === Qt.RightButton) {
                    strip.setArranging(!strip.overflowOpen || !strip.arranging);
                }
            }
        }
    }

    // Over everything but the chevron (and the nook), and only passive: a
    // double click on a widget still reaches the widget, and both presses
    // still open or close whatever it opens, as in Omarchy's bar (plan 015,
    // after Omarchy's shell/plugins/bar/Bar.qml toggleTransparency, MIT,
    // Copyright (c) David Heinemeier Hansson). A PointHandler, as on the
    // slots (BarSlot.qml): it only ever takes a passive grab. A TapHandler
    // here kept every widget from seeing its clicks (nested Hyprland). Two
    // presses within the double-click interval and distance make a double
    // click, as Qt counts them; a drag or a bar move in between forgets the
    // first.
    Item {
        anchors.fill: parent

        PointHandler {
            id: doubleTap

            property real lastTime: 0
            property point lastAt: Qt.point(0, 0)

            function forget(): void {
                lastTime = 0;
            }

            enabled: !strip.hidden && !strip.arranging
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
                if (overflowButton.visible && overflowButton.contains(b))
                    return;
                // Opening and closing the panel from the nook is no double click either.
                const n = strip.nookItem;
                if (n && n.visible && n.contains(n.mapFromItem(null, p.x, p.y)))
                    return;
                strip.transparencyToggleRequested();
            }
        }
    }
}
