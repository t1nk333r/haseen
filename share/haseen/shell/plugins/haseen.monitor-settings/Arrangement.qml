import QtQuick
import qs.Haseen
import "Model.js" as Model

// The arrangement diagram of the haseen.monitor-settings panel: the enabled
// monitors to scale (logical size, a 90° or 270° rotation swaps the sides),
// framed around their bounding box. Drag one: on release its edges snap to a
// neighbour's within 8 px on screen, it is pushed clear of any overlap
// (Model.place) and dropped(name, x, y) asks for the new position. A drag may
// pass over another monitor; only the drop is resolved, as in GNOME's and
// Windows' display settings. Adapted from the ArrangementDiagram of
// juliusmork-sys's Monitor Settings Extender (MIT, Copyright (c) 2026 Julius
// Getz Mørk); haseen keeps the snapping and push-out in Model.js.
Item {
    id: diagram

    // The monitors where they stand, left to right: a map of the desk, not
    // reading order, and the drag math works in Hyprland's coordinates. A
    // right-to-left panel does not mirror it.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property var monitors: []
    property bool busy: false

    signal dropped(string name, int x, int y)

    readonly property var boxes: Model.rects(monitors, "")
    readonly property var frame: Model.bounds(boxes)
    // A little headroom so a box at the frame's edge is not drawn flush on it.
    readonly property real unit: Math.min(width / frame.w, height / frame.h) * 0.96

    height: Math.round(Theme.fontSize * 13)

    Item {
        id: canvas

        width: diagram.frame.w * diagram.unit
        height: diagram.frame.h * diagram.unit
        anchors.centerIn: parent

        Repeater {
            model: diagram.boxes

            delegate: Rectangle {
                id: box

                required property var modelData
                readonly property var info: modelData
                readonly property var monitor: diagram.monitors.find(m => m.name === info.name) || null
                property real dragX: 0
                property real dragY: 0

                x: (info.x - diagram.frame.x) * diagram.unit + dragX
                y: (info.y - diagram.frame.y) * diagram.unit + dragY
                width: Math.max(2, info.w * diagram.unit - 2)
                height: Math.max(2, info.h * diagram.unit - 2)
                radius: Theme.radius
                color: monitor && monitor.focused ? Theme.selection : Theme.surfaceAlt
                border.width: drag.pressed ? 2 : Theme.borderWidth
                border.color: drag.pressed ? Theme.accent : Theme.border
                z: drag.pressed ? 10 : 1

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.gap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: box.monitor ? I18n.tr(box.monitor.label) : box.info.name
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }

                MouseArea {
                    id: drag

                    property point start

                    anchors.fill: parent
                    enabled: !diagram.busy
                    cursorShape: Qt.SizeAllCursor
                    onPressed: mouse => start = mapToItem(canvas, mouse.x, mouse.y)
                    onPositionChanged: mouse => {
                        const p = mapToItem(canvas, mouse.x, mouse.y);
                        box.dragX = p.x - start.x;
                        box.dragY = p.y - start.y;
                    }
                    onReleased: {
                        const x = box.info.x + box.dragX / diagram.unit;
                        const y = box.info.y + box.dragY / diagram.unit;
                        const at = Model.place(diagram.monitors, box.info.name, x, y, 8 / diagram.unit);
                        // The box stays where it landed until the list is
                        // read again after the change, which rebuilds it.
                        box.dragX = at ? (at.x - box.info.x) * diagram.unit : 0;
                        box.dragY = at ? (at.y - box.info.y) * diagram.unit : 0;
                        if (at && (at.x !== box.info.x || at.y !== box.info.y))
                            diagram.dropped(box.info.name, at.x, at.y);
                    }
                }
            }
        }
    }
}
