import QtQuick
import Quickshell
import qs.Haseen

// A row (or, in a left/right bar, a column) of bar-widget plugins. Disabled
// ids are filtered out; unknown ones are skipped by PluginSlot with one log
// line. A widget that is invisible or reports implicitWidth 0 (its "hidden"
// signal in both orientations) gets a zero-size slot: positioners neither
// place nor space zero-size children, so it adds no gap, and it gets no
// hover highlight and no press or arrange area.
//
// Vertical: every slot is the bar's width. A widget that declares
// `property bool vertical` gets it set and sizes its own height; any other
// widget gets a square cell, clipped, so it stays inside the bar.
//
// Every shown widget gets a hover highlight from its slot. widgetPressed(slot)
// reports every press on a widget, for the panel host: a toggle that follows
// it opens the panel under that widget (shell.qml).
//
// Arrange mode: a click moves a widget between the bar and the overflow
// panel (moveRequested); a drag reports where the pointer is, in the window
// the widget sits in (dragMoved), and its end (dragEnded), and the bar
// (Bar.qml) decides where it lands.
//
// Overflow (Bar.qml, Overflow.js): each widget sits in a placeholder cell of
// this grid. An overflowed widget's cell shrinks to nothing (the grid skips
// it) and its slot moves into the overflow panel's cell for that id while the
// panel is open (`cells`), back here when it closes. The slot is never
// rebuilt and never made invisible: the widget keeps running, keeps its state
// and its IPC targets stay single, and a widget whose width follows its own
// visibility (`implicitWidth: visible ? w : 0`) keeps reporting its size.
// `lengths` reports each widget's natural size along the bar wherever it is,
// which is what the fit is computed from.
Grid {
    id: section

    required property var ids
    required property var screen
    property bool vertical: false
    // Ids now in overflow, and the overflow panel's cells by id (empty
    // while it is closed).
    property var overflowIds: []
    property var cells: ({})
    // Ids that never overflow; arranging leaves them alone.
    property var fixedIds: []
    // Arrange mode (the overflow panel's "Arrange"): a click on a widget
    // moves it between the bar and the panel instead of reaching it, and a
    // drag moves it anywhere.
    property bool arranging: false
    // The id being dragged, drawn dimmed where it is until it is dropped.
    property string dragId: ""
    readonly property var shownIds: ids.filter(id => Config.isEnabled(id))
    // id -> natural length along the bar.
    property var lengths: ({})

    signal widgetPressed(Item slot)
    // A click while arranging: `overflowed` says where the widget is now.
    signal moveRequested(string id, bool overflowed)
    // A drag while arranging: the pointer in the slot's window coordinates.
    signal dragMoved(string id, Item slot, real x, real y)
    signal dragEnded(string id, bool dropped)

    // The shown widgets still in the bar, in order, as [{ id, start, end }]
    // along the bar in `target`'s coordinates (Overflow.dropTarget).
    function spans(target: Item): var {
        const out = [];
        for (let i = 0; i < repeater.count; i++) {
            const c = repeater.itemAt(i);
            if (!c || c.overflowed || c.length <= 0)
                continue;
            const p = c.mapToItem(target, 0, 0);
            const start = vertical ? p.y : p.x;
            out.push({
                id: c.modelData,
                start: start,
                end: start + c.length
            });
        }
        return out;
    }

    function report(id: string, length: real): void {
        if (lengths[id] === length)
            return;
        const next = Object.assign({}, lengths);
        next[id] = length;
        lengths = next;
    }

    function forget(id: string): void {
        if (!(id in lengths))
            return;
        const next = Object.assign({}, lengths);
        delete next[id];
        lengths = next;
    }

    // Column count only (no `rows`): flipping both at once briefly asks for
    // a 1x1 grid and Qt warns.
    columns: vertical ? 1 : Math.max(1, ids.length)
    spacing: Math.round(Theme.gap / 2)

    Repeater {
        id: repeater

        model: ScriptModel {
            values: section.shownIds
        }

        delegate: Item {
            id: cell

            required property string modelData
            readonly property bool overflowed: section.overflowIds.indexOf(modelData) >= 0
            readonly property Item host: overflowed ? (section.cells[modelData] || null) : null
            readonly property real length: section.vertical ? slot.height : slot.width

            width: overflowed ? 0 : slot.width
            height: overflowed ? 0 : slot.height
            // Hides a parked widget without making it invisible (see above).
            clip: overflowed
            onLengthChanged: section.report(modelData, length)
            Component.onCompleted: section.report(modelData, length)
            Component.onDestruction: section.forget(modelData)

            PluginSlot {
                id: slot

                readonly property bool ready: status === Loader.Ready && item !== null
                // Set once per loaded item, not bound: a binding that reads the
                // item's `vertical` while also writing it loops.
                property bool adapts: false
                // `visible` too: an invisible widget with a size (an Omarchy
                // widget hidden by `visible: false`) must not leave an empty,
                // hoverable gap. Compat hosts report their widget's visibility
                // through their implicitWidth (OmarchyHost, DmsHost).
                readonly property bool shown: ready && item.visible && item.implicitWidth > 0

                parent: cell.host || cell
                pluginId: cell.modelData
                kind: "bar-widget"
                screen: section.screen
                width: !shown ? 0 : section.vertical ? section.width : item.implicitWidth
                // Read the item's own `vertical`, not the section's: while it is
                // still false the widget sizes itself horizontally (height from
                // its parent) and must get a fixed cell.
                height: !shown ? 0 : !section.vertical ? section.height : adapts && item.vertical ? item.implicitHeight : section.width
                clip: section.vertical && !adapts
                opacity: section.dragId === cell.modelData ? 0.35 : 1
                // After the load settles: assigning while the Loader is still
                // parenting and sizing the new item trips a binding-loop warning.
                onItemChanged: Qt.callLater(() => {
                    adapts = item !== null && ("vertical" in item);
                    if (adapts)
                        item.vertical = Qt.binding(() => section.vertical);
                })

                // Hover highlight for every widget, native or compat, drawn
                // behind it with BarButton's tint and insets, so a BarButton
                // widget looks as it always did. On the slot itself, not on the
                // item above the widget: a HoverHandler there takes the hover
                // from the widget's own MouseArea.
                HoverHandler {
                    id: hover
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: section.vertical ? 0 : 3
                    anchors.bottomMargin: section.vertical ? 0 : 3
                    anchors.leftMargin: section.vertical ? 3 : 0
                    anchors.rightMargin: section.vertical ? 3 : 0
                    z: -1
                    radius: Theme.radius
                    color: Theme.surfaceAlt
                    visible: hover.hovered
                }

                // Above the widget, so it sees the press first; a PointHandler
                // takes only a passive grab, so the press still reaches the
                // widget's own MouseArea or TapHandler. One in the slot itself
                // would never see a press the widget accepts.
                Item {
                    anchors.fill: parent
                    z: 1

                    PointHandler {
                        acceptedButtons: Qt.AllButtons
                        enabled: !section.arranging
                        onActiveChanged: {
                            if (active)
                                section.widgetPressed(slot);
                        }
                    }

                    // Arrange mode: this takes the press, so the widget never
                    // sees it (outlined, so the mode shows). A click moves the
                    // widget between the bar and the panel; a drag moves it
                    // where it is dropped (Bar.qml). A modifier gesture could
                    // not do this: a bar has no keyboard focus, so Wayland
                    // never tells it about Shift. While the button is held the
                    // compositor keeps sending the pointer here (an implicit
                    // grab), even over the other window (bar or panel).
                    MouseArea {
                        id: arrange

                        property point pressAt: Qt.point(0, 0)
                        property bool dragging: false

                        function finish(dropped: bool): void {
                            if (!dragging)
                                return;
                            dragging = false;
                            section.dragEnded(cell.modelData, dropped);
                        }

                        anchors.fill: parent
                        enabled: section.arranging && section.fixedIds.indexOf(cell.modelData) < 0
                        hoverEnabled: true
                        preventStealing: true
                        // Unset outside arrange mode (undefined resets it):
                        // a disabled MouseArea's cursor still wins over the
                        // widget's own under it.
                        cursorShape: !enabled ? undefined : dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => {
                            pressAt = Qt.point(mouse.x, mouse.y);
                            dragging = false;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed)
                                return;
                            if (!dragging && Math.abs(mouse.x - pressAt.x) + Math.abs(mouse.y - pressAt.y) < Qt.styleHints.startDragDistance)
                                return;
                            dragging = true;
                            const p = mapToItem(null, mouse.x, mouse.y);
                            section.dragMoved(cell.modelData, slot, p.x, p.y);
                        }
                        onReleased: mouse => {
                            if (dragging)
                                finish(true);
                            else if (containsMouse)
                                section.moveRequested(cell.modelData, cell.overflowed);
                        }
                        onCanceled: finish(false)
                        onEnabledChanged: {
                            if (!enabled)
                                finish(false);
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            visible: arrange.enabled
                            radius: Theme.radius
                            color: arrange.containsMouse || arrange.dragging ? Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.5) : "transparent"
                            border.color: Theme.accent
                            border.width: Theme.borderWidth
                        }
                    }
                }
            }
        }
    }
}
