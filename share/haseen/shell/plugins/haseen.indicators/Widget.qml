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
//
// Only the indicators that are on take room in the bar. Omarchy reveals the
// others inline, which widens the widget, and in the centre section that
// shifted the clock and every other module on each hover. Here they open in a
// strip laid over the bar beside the widget, so the bar never moves.
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
    readonly property var activeCells: parts.active.map(id => ({ id: id, active: true }))
    readonly property var revealCells: reveal ? parts.inactive.map(id => ({ id: id, active: false })) : []
    // With nothing on, a sliver stays to hover over.
    readonly property int hoverZone: ids.length > 0 ? Theme.gap : 0
    readonly property bool hovered: hover.hovered || revealHovered
    property bool revealHovered: false

    property Item tipItem: null
    property string tipText: ""

    implicitWidth: activeCells.length > 0 ? grid.implicitWidth : hoverZone
    implicitHeight: vertical ? (activeCells.length > 0 ? grid.implicitHeight : hoverZone) : Config.barHeight

    function showTip(item: Item, on: bool): void {
        if (on) {
            tipItem = item;
            tipText = item.cell.tooltip;
        } else if (tipItem === item) {
            tipItem = null;
        }
    }

    onHoveredChanged: {
        if (hovered) {
            hideTimer.stop();
            revealHeld = true;
        } else {
            hideTimer.restart();
        }
    }

    HoverHandler {
        id: hover
    }

    // The pointer crosses from the bar into the strip, a separate surface;
    // a short grace keeps the strip from closing on the way.
    // haseen:ui-timeout
    Timer {
        id: hideTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!root.hovered)
                root.revealHeld = false;
        }
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.activeCells.length)

        Repeater {
            model: root.activeCells

            delegate: IndicatorCell {
                host: root
                vertical: root.vertical
            }
        }
    }

    // The dimmed indicators, beside the widget on the bar's own row (above
    // it on a side bar), toward the start of the bar so the active block
    // keeps its neighbour. At the start edge the compositor flips the strip
    // to the other side. A popup draws over the bar, so nothing reflows.
    LazyLoader {
        active: root.revealCells.length > 0

        PopupWindow {
            visible: true
            color: "transparent"
            anchor.item: root
            anchor.edges: root.vertical ? Edges.Top | Edges.Left : Edges.Left | Edges.Top
            anchor.gravity: root.vertical ? Edges.Top | Edges.Right : Edges.Left | Edges.Bottom
            anchor.adjustment: PopupAdjustment.Flip
            // Never 0: the strip empties a moment before the loader drops the
            // window, and a popup repositioned to size 0 is a protocol error
            // that kills the shell's Wayland connection.
            implicitWidth: Math.max(1, root.vertical ? root.width : strip.implicitWidth)
            implicitHeight: Math.max(1, root.vertical ? strip.implicitHeight : Config.barHeight)
            onVisibleChanged: if (!visible) root.revealHovered = false

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                radius: Theme.radius

                HoverHandler {
                    onHoveredChanged: root.revealHovered = hovered
                }

                Grid {
                    id: strip
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : Math.max(1, root.revealCells.length)

                    Repeater {
                        model: root.revealCells

                        delegate: IndicatorCell {
                            host: root
                            vertical: root.vertical
                            // The strip has the bar's colour even when the
                            // bar itself is see-through.
                            color: Theme.foreground
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
