import QtQuick
import qs.Haseen

// One inner corner: a radius-sized square filled with the frame colour
// outside a quarter circle. Drawn as the border of a larger rounded
// Rectangle, clipped to the square, so it needs no Canvas buffer or shader.
//
// The Rectangle's inner edge has radius `radius` and its arc centre sits on
// the square's corner that faces into the window area; its border is
// `radius` wide, so it covers the rest of the square.
//
// `bleed` extends the square, in the frame colour, by that many px on its
// two outer sides, under the strip and the bar it meets (seams: Frame.qml).
Item {
    id: root

    property int radius: 12
    property int bleed: 0
    property color fill: Theme.background
    property bool atRight: false
    property bool atBottom: false

    width: radius + bleed
    height: radius + bleed

    // The outer column, then the outer row.
    Rectangle {
        x: root.atRight ? root.radius : 0
        width: root.bleed
        height: root.height
        color: root.fill
    }

    Rectangle {
        y: root.atBottom ? root.radius : 0
        width: root.width
        height: root.bleed
        color: root.fill
    }

    Item {
        x: root.atRight ? 0 : root.bleed
        y: root.atBottom ? 0 : root.bleed
        width: root.radius
        height: root.radius
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
        }
    }

    // One cross-fade for the whole corner, as the bar's (Bar.qml).
    Behavior on fill {
        ColorAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }
}
