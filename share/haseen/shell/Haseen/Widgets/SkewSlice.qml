// Adapted from Omarchy shell/plugins/image-picker/ImagePicker.qml (one
// carousel item: its slanted outline and mask).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: no shader mask, no shade over an unselected slice (plan 152).
import QtQuick
import QtQuick.Shapes

// One slanted slice of SkewCarousel: a parallelogram whose top edge starts
// `skew` px in and whose bottom edge ends `skew` px short, with the picture
// upright inside it. Omarchy cuts the shape with a MultiEffect mask, which
// draws nothing on haseen's software renderer (architecture §6). Here the
// content is drawn slanted the other way into a layer and the layer is
// slanted back: the slice's edge is a parallelogram and the picture inside
// is not sheared at all. A layer is a texture, not a shader, so both
// renderers draw it the same (plan 152).
Item {
    id: slice

    property real skew: 28
    property color borderColor: "transparent"
    property real borderWidth: 1
    // The picture, upright, filling the slice's bounding box; the slant cuts
    // `skew` px off its top-left and bottom-right corners.
    default property alias content: frame.data

    signal clicked

    readonly property real shear: skew / Math.max(1, height)

    Item {
        id: sheared

        width: Math.max(1, slice.width - slice.skew)
        height: slice.height
        layer.enabled: true
        layer.smooth: true
        // x' = x - shear * y + skew: the layer's rectangle lands on the
        // slanted outline.
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -slice.shear, 0, slice.skew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        }

        // The inverse, so the content comes out upright.
        Item {
            id: frame

            width: slice.width
            height: slice.height
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, slice.shear, 0, -slice.skew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
            }
        }
    }

    Shape {
        id: outline

        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        containsMode: Shape.FillContains

        ShapePath {
            fillColor: "transparent"
            strokeColor: slice.borderColor
            strokeWidth: slice.borderWidth
            startX: slice.skew
            startY: 0

            PathLine {
                x: slice.width
                y: 0
            }
            PathLine {
                x: slice.width - slice.skew
                y: slice.height
            }
            PathLine {
                x: 0
                y: slice.height
            }
            PathLine {
                x: slice.skew
                y: 0
            }
        }
    }

    // Only the slanted shape takes the click: the corners it leaves belong
    // to the neighbouring slice, which they overlap.
    MouseArea {
        anchors.fill: parent
        containmentMask: outline
        cursorShape: Qt.PointingHandCursor
        onClicked: slice.clicked()
    }
}
