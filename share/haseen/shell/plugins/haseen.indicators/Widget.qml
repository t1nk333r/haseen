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
//
// While the pointer is on the widget or its strip, every cell stays where it
// is: a click turns it on or off in place (it dims or lights up), and the bar
// takes the new layout, one cell wider or narrower, only once the pointer has
// left. A block that resized under the pointer moved the cells away from it,
// re-centred the modules beside it, and Qt re-checks the hover before it lays
// the bar out again, so the strip closed under a resting pointer and opened
// again at the next unrelated repaint.
//
// The strip is an item drawn over the widget's own window, not a popup: it
// moves with the widget in the same frame and goes away with it. A popup's
// anchor stays where the widget was until the popup is resized, and a popup
// shrunk before it closes is redrawn by the compositor, fading, at the new
// spot over the clock.
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
    // The pointer is on the widget or its strip, or left them less than the
    // grace ago.
    property bool held: false
    // The split as it was when the pointer arrived, kept while it is held.
    property var heldParts: null
    // Which cells sit in the bar (active) and which in the strip (inactive).
    readonly property var placed: heldParts !== null ? heldParts : parts
    readonly property bool reveal: settings.alwaysShow === true || held
    // With nothing on, a sliver stays to hover over.
    readonly property int hoverZone: ids.length > 0 ? Theme.gap : 0
    readonly property bool hovered: hover.hovered || (strip !== null && strip.hovered)
    // The open strip, or null.
    readonly property Item strip: stripLoader.item

    // The widget's corner in its window. Every ancestor's position is read,
    // so this follows the widget when the bar lays it out again (a
    // neighbour's width changes, the section re-centres, the slot moves into
    // the overflow panel); mapToItem alone is not re-evaluated then.
    // inView is false while a clipping ancestor has no room for it (a widget
    // parked for the overflow panel).
    readonly property var corner: {
        let x = 0;
        let y = 0;
        let inView = true;
        for (let item = root; item !== null; item = item.parent) {
            x += item.x;
            y += item.y;
            if (item.clip && (item.width <= 0 || item.height <= 0))
                inView = false;
        }
        return {
            x: x,
            y: y,
            inView: inView
        };
    }

    property IndicatorCell tipItem: null
    // Kept after the pointer leaves the cell: a tooltip window emptied before
    // it closes is shrunk first, and the compositor fades the old picture
    // out at the shrunk window's place.
    property string tipText: ""

    implicitWidth: placed.active.length > 0 ? grid.implicitWidth : hoverZone
    implicitHeight: vertical ? (placed.active.length > 0 ? grid.implicitHeight : hoverZone) : Config.barHeight

    function isOn(id: string): bool {
        return parts.active.indexOf(id) >= 0;
    }

    // A cell calls this when the pointer enters or leaves it, and again when
    // its state flips under the pointer (the tooltip says what a click does).
    function showTip(item: IndicatorCell, on: bool): void {
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
            held = true;
        } else {
            hideTimer.restart();
        }
    }
    onHeldChanged: heldParts = held ? parts : null

    HoverHandler {
        id: hover
    }

    // A short grace keeps the strip open while the pointer crosses between
    // the widget and the strip, or skims off the edge.
    // haseen:ui-timeout
    Timer {
        id: hideTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!root.hovered)
                root.held = false;
        }
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.placed.active.length)

        Repeater {
            // Keeps the cells that stay when the list changes.
            model: ScriptModel {
                values: root.placed.active
            }

            delegate: IndicatorCell {
                id: barCell
                host: root
                vertical: root.vertical
                active: root.isOn(barCell.modelData)
            }
        }
    }

    // The dimmed indicators, beside the widget on the bar's own row (above
    // it in a side bar), toward the start of the bar so the active block
    // keeps its neighbour; at the start edge, on the other side. Over every
    // other item of the window, so nothing reflows and nothing covers it.
    Loader {
        id: stripLoader

        readonly property real before: root.vertical ? root.corner.y - height : root.corner.x - width
        readonly property bool flipped: before < 0

        parent: root.Window.contentItem
        z: 1
        active: root.reveal && parent !== null && root.corner.inView && root.placed.inactive.length > 0
        x: root.vertical ? root.corner.x : flipped ? root.corner.x + root.width : before
        y: !root.vertical ? root.corner.y : flipped ? root.corner.y + root.height : before

        sourceComponent: Rectangle {
            readonly property bool hovered: stripHover.hovered

            implicitWidth: root.vertical ? root.width : cells.implicitWidth
            implicitHeight: root.vertical ? cells.implicitHeight : Config.barHeight
            color: Theme.background
            radius: Theme.radius

            HoverHandler {
                id: stripHover
            }

            Grid {
                id: cells
                anchors.centerIn: parent
                columns: root.vertical ? 1 : Math.max(1, root.placed.inactive.length)

                Repeater {
                    model: ScriptModel {
                        values: root.placed.inactive
                    }

                    delegate: IndicatorCell {
                        id: stripCell
                        host: root
                        vertical: root.vertical
                        active: root.isOn(stripCell.modelData)
                        // The strip has the bar's colour even when the
                        // bar itself is see-through.
                        color: Theme.foreground
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
