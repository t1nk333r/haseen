// Adapted from Omarchy shell/plugins/image-picker/ImagePicker.qml (one
// carousel item: its slanted outline and mask).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: no shader mask and no shade over an unselected slice (plan 152).
import QtQuick
import QtQuick.Shapes

// One slanted slice of SkewCarousel. Its outline is a parallelogram: the top
// edge starts `skew` px in and the bottom edge ends `skew` px short. The
// picture inside stays upright.
//
// Omarchy cuts the slant with a MultiEffect mask, which draws nothing on
// haseen's software renderer (architecture §6). This slice draws its content
// into a layer with the inverse shear, then shears the layer back. A layer
// is a texture, so both renderers draw it.
Item {
    id: slice

    property real skew: 28
    property color borderColor: "transparent"
    property real borderWidth: 1
    // The picture. It fills the slice's bounding box, and the slant cuts
    // `skew` px off its top-left and bottom-right corners. Put no mouse area
    // or handler in it. On the software renderer its coordinates are flipped
    // (see `flipped`), so a hit area in it would be mirrored, even though the
    // picture draws upright. The slice's own MouseArea below takes the
    // clicks.
    default property alias content: frame.data

    signal clicked

    readonly property real shear: skew / Math.max(1, height)
    // Qt 6.12's software renderer always draws a layer's texture upside
    // down (qsgsoftwareinternalimagenode.cpp:465), because it expects the
    // layer to have been rendered upside down. At a fractional scale that
    // upside-down render loses part of the picture, the bottom quarter at
    // 1.25 and all of it at 2 (qsgsoftwarelayer.cpp:204-208). On that
    // renderer this slice renders its layer unflipped and flips the content
    // itself (plan 156).
    readonly property bool flipped: GraphicsInfo.api === GraphicsInfo.Software

    Item {
        id: sheared

        width: Math.max(1, slice.width - slice.skew)
        height: slice.height
        layer.enabled: true
        layer.smooth: true
        layer.textureMirroring: slice.flipped ? ShaderEffectSource.NoMirroring : ShaderEffectSource.MirrorVertically
        // Shear the layer by x' = x - shear * y + skew. That puts its
        // rectangle on the slanted outline.
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -slice.shear, 0, slice.skew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        }

        // The inverse shear, so the content comes out upright. On the
        // software renderer the matrix also flips the content
        // (y' = height - y), and Qt's flip of the layer's texture undoes it.
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

    // Only the slanted shape takes clicks. A click in a cut corner goes to
    // the neighbouring slice, which overlaps that corner.
    MouseArea {
        anchors.fill: parent
        containmentMask: outline
        cursorShape: Qt.PointingHandCursor
        onClicked: slice.clicked()
    }
}
