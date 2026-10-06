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
Grid {
    id: section

    required property var ids
    required property var screen
    property bool vertical: false

    signal widgetPressed(Item slot)

    // Column count only (no `rows`): flipping both at once briefly asks for
    // a 1x1 grid and Qt warns.
    columns: vertical ? 1 : Math.max(1, ids.length)
    spacing: Math.round(Theme.gap / 2)

    Repeater {
        model: ScriptModel {
            values: section.ids.filter(id => Config.isEnabled(id))
        }

        delegate: PluginSlot {
            id: slot

            required property string modelData
            readonly property bool ready: status === Loader.Ready && item !== null
            // Set once per loaded item, not bound: a binding that reads the
            // item's `vertical` while also writing it loops.
            property bool adapts: false
            readonly property bool shown: ready && item.implicitWidth > 0

            pluginId: modelData
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
                    onActiveChanged: {
                        if (active)
                            section.widgetPressed(slot);
                    }
                }
            }
        }
    }
}
