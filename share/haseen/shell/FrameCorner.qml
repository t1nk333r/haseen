import QtQuick
import qs.Haseen

// One inner corner: a radius-sized square filled with the frame colour
// outside a quarter circle. Drawn as the border of a larger rounded
// Rectangle, clipped to the square, so it needs no Canvas buffer or shader.
//
// The Rectangle's inner edge has radius `radius` and its arc centre sits on
// the square's corner that faces into the window area; its border is
// `radius` wide, so it covers the rest of the square.
Item {
    id: root

    property int radius: 12
    property color fill: Theme.background
    property bool atRight: false
    property bool atBottom: false

    width: radius
    height: radius
    clip: true

    Rectangle {
        x: root.atRight ? -2 * root.radius : -root.radius
        y: root.atBottom ? -2 * root.radius : -root.radius
        width: root.radius * 4
        height: root.radius * 4
        radius: root.radius * 2
        color: "transparent"
        border.width: root.radius
        border.color: root.fill

        Behavior on border.color {
            ColorAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
            }
        }
    }
}
