import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Indicators.js" as Logic

// State indicators. Adapted from Omarchy shell/plugins/bar/widgets/Indicators.qml
// (MIT, Copyright (c) David Heinemeier Hansson).
//
// An indicator is on while its flag (qs.Haseen Flags) is set and then always
// shows; the rest stay hidden until the pointer rests on the widget, when they
// appear dimmed so they can be switched on. A click runs the `haseen toggle …`
// / `haseen capture screenrecord` command that flips the state; the flag
// watch brings the change back here, so nothing is polled.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false

    readonly property var barIds: Config.section("left").concat(Config.section("center"), Config.section("right"))
    readonly property var ids: Logic.entries(settings, barIds)
    readonly property var parts: Logic.split(ids, {
        "recording": Flags.recording,
        "nightlight": Flags.nightlight,
        "dnd": Flags.dnd,
        "idle-off": Flags.idleOff,
        "screensaver-off": Flags.screensaverOff
    })
    property bool revealHeld: false
    readonly property bool reveal: settings.alwaysShow === true || revealHeld
    // Inactive first: the active block keeps its place next to whatever sits
    // after the widget (the clock, in Omarchy's layout) as the others appear.
    readonly property var cells: (reveal ? parts.inactive.map(id => ({ id: id, active: false })) : []).concat(parts.active.map(id => ({ id: id, active: true })))
    // With nothing on, a sliver stays to hover over.
    readonly property int hoverZone: ids.length > 0 ? Theme.gap : 0

    property Item tipItem: null
    property string tipText: ""

    implicitWidth: cells.length > 0 ? grid.implicitWidth : hoverZone
    implicitHeight: vertical ? (cells.length > 0 ? grid.implicitHeight : hoverZone) : Config.barHeight

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop();
                root.revealHeld = true;
            } else {
                hideTimer.restart();
            }
        }
    }

    // Revealing widens the widget and can slide it out from under the
    // pointer for a moment; a short grace keeps it from flickering shut.
    // haseen:ui-timeout
    Timer {
        id: hideTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!hover.hovered)
                root.revealHeld = false;
        }
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.cells.length)

        Repeater {
            model: root.cells

            delegate: BarButton {
                id: button

                required property var modelData
                readonly property var cell: Logic.cell(modelData.id, modelData.active)

                vertical: root.vertical
                // Not root.height: the slot is 0 high until the widget has
                // width, and Grid skips zero-sized children.
                height: root.vertical ? implicitHeight : Config.barHeight
                padding: Math.round(Theme.gap * 0.75)
                glyph: cell.glyph
                opacity: modelData.active ? 1 : 0.45
                onClicked: Quickshell.execDetached(cell.command)

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            root.tipItem = button;
                            root.tipText = button.cell.tooltip;
                        } else if (root.tipItem === button) {
                            root.tipItem = null;
                        }
                    }
                }
            }
        }
    }

    // The hovered cell's tooltip; the window exists only while one is hovered.
    LazyLoader {
        active: root.tipItem !== null && root.tipText !== ""

        PopupWindow {
            // Opens away from the bar edge, whichever edge that is.
            readonly property string pos: Config.barPosition
            readonly property int away: pos === "bottom" ? Edges.Top : pos === "left" ? Edges.Right : pos === "right" ? Edges.Left : Edges.Bottom

            visible: true
            color: "transparent"
            anchor.item: root.tipItem
            anchor.edges: away
            anchor.gravity: away
            anchor.margins.top: pos === "top" ? Theme.gap : 0
            anchor.margins.bottom: pos === "bottom" ? Theme.gap : 0
            anchor.margins.left: pos === "left" ? Theme.gap : 0
            anchor.margins.right: pos === "right" ? Theme.gap : 0
            implicitWidth: Math.ceil(label.implicitWidth) + Theme.gap * 2
            implicitHeight: Math.ceil(label.implicitHeight) + Theme.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                radius: Theme.radius
                border.width: Theme.borderWidth
                border.color: Theme.border

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: root.tipText
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
