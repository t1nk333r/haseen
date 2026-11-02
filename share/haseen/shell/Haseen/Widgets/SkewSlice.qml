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
// is not sheared at all. A layer is a texture, not a shader, so the
// software renderer draws it too (plan 152), at any scale (plan 156).
Item {
    id: slice

    property real skew: 28
    property color borderColor: "transparent"
    property real borderWidth: 1
    // The picture, upright, filling the slice's bounding box; the slant cuts
    // `skew` px off its top-left and bottom-right corners. Keep it free of
    // mouse areas and handlers: on the software renderer its coordinates
    // are flipped (`flipped`), so a hit area in it would be mirrored, though
    // the picture still draws upright; the slice's own MouseArea below takes
    // the clicks.
    default property alias content: frame.data

    signal clicked

    readonly property real shear: skew / Math.max(1, height)
    // Qt 6.12's software renderer draws a layer's texture flipped upside
    // down (qsgsoftwareinternalimagenode.cpp:465) and expects the layer to
    // have been rendered flipped already, which it renders wrong at a
    // fractional scale: at 1.25 the bottom quarter of the picture is lost,
    // at 2 all of it (qsgsoftwarelayer.cpp:204-208). There the layer is
    // rendered unflipped and the content flips itself instead (plan 156).
    readonly property bool flipped: GraphicsInfo.api === GraphicsInfo.Software

    Item {
        id: sheared

        width: Math.max(1, slice.width - slice.skew)
        height: slice.height
        layer.enabled: true
        layer.smooth: true
        layer.textureMirroring: slice.flipped ? ShaderEffectSource.NoMirroring : ShaderEffectSource.MirrorVertically
        // x' = x - shear * y + skew: the layer's rectangle lands on the
        // slanted outline.
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -slice.shear, 0, slice.skew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        }

        // The inverse, so the content comes out upright; on the software
        // renderer also upside down (y' = height - y), which its layer
        // undoes.
        Item {
            id: frame

            width: slice.width
            height: slice.height
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, slice.shear, 0, -slice.skew, 0, slice.flipped ? -1 : 1, 0, slice.flipped ? slice.height : 0, 0, 0, 1, 0, 0, 0, 0, 1)
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
