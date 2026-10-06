import QtQuick
import Quickshell
import qs.Haseen

// A row (or, in a left/right bar, a column) of bar-widget plugins. Disabled
// ids are filtered out; unknown ones are skipped by PluginSlot with one log
// line. Positioners neither place nor space zero-size children, so a widget
// reporting implicitWidth 0 (its "hidden" signal in both orientations) adds
// no gap.
//
// Vertical: every slot is the bar's width. A widget that declares
// `property bool vertical` gets it set and sizes its own height; any other
// widget gets a square cell, clipped, so it stays inside the bar.
//
// Every shown widget gets a hover highlight from its slot. widgetPressed(slot)
// reports every press on a widget, for the panel host: a toggle that follows
// it opens the panel under that widget (shell.qml).
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
    // moves it between the bar and the panel instead of reaching it.
    property bool arranging: false
    readonly property var shownIds: ids.filter(id => Config.isEnabled(id))
    // id -> natural length along the bar.
    property var lengths: ({})

    signal widgetPressed(Item slot)
    // A click while arranging: `overflowed` says where the widget is now.
    signal moveRequested(string id, bool overflowed)

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
                readonly property bool shown: ready && item.implicitWidth > 0

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

                    // Arrange mode: this takes the click, so the widget never
                    // sees it, and moves the widget (outlined, so the mode
                    // shows). A modifier gesture could not do this: a bar has
                    // no keyboard focus, so Wayland never tells it about Shift.
                    MouseArea {
                        id: arrange

                        anchors.fill: parent
                        enabled: section.arranging && section.fixedIds.indexOf(cell.modelData) < 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: section.moveRequested(cell.modelData, cell.overflowed)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            visible: arrange.enabled
                            radius: Theme.radius
                            color: arrange.containsMouse ? Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.5) : "transparent"
                            border.color: Theme.accent
                            border.width: Theme.borderWidth
                        }
                    }
                }
            }
        }
    }
}
