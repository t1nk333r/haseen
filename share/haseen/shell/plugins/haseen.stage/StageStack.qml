import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets
import "Stage.js" as Stage

// One workspace on the stage (plan 163): a stack of its windows, the most
// recently focused in front, turned about the edge side towards the middle
// of the screen; the front window's app icon and the workspace's number
// face the viewer at the stack's lower corner on the edge side. A click
// switches to the workspace. Under the pointer the cards spread and the
// stack turns part of the way back.
//
// The turn is one 3D Rotation of the whole stack. On the GPU renderer the
// stack is drawn flat into a layer first and the layer is turned: turning
// each card on its own puts the cards in planes that cross, and the depth
// test then cuts them where they meet (seen in the rhi draws of plan 163).
// The software renderer paints the projection with QPainter's perspective
// transform, card by card in order, so it needs no layer, and a layer there
// is wrong at a fractional scale (plan 156).
Item {
    id: stack

    // Stage.stacks entry: { id, name, windows }.
    required property var modelData
    required property int index
    property string edge: "left"
    property int tilt: 50
    property var metrics: ({})
    property int inset: 0
    property int iconSize: 24
    property bool capture: true
    property bool software: GraphicsInfo.api === GraphicsInfo.Software

    signal chosen(int workspaceId)

    readonly property var windows: modelData.windows || []
    readonly property var front: windows.length > 0 ? windows[0] : null
    readonly property bool hovered: pointer.containsMouse
    readonly property int back: Math.max(0, windows.length - 1)
    readonly property int bandTop: (metrics.rise || 0) * back
    readonly property int planeHeight: metrics.planeHeight || 0
    // The front card's rectangle in the plane: the icon sits on its corner.
    readonly property var frontSize: front ? Stage.cardSize(front.width, front.height, front.width, front.height, metrics.planeWidth || 0, planeHeight) : ({
            width: 0,
            height: 0
        })

    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("Workspace %1", modelData.name)

    Item {
        id: plane

        x: stack.edge === "right" ? stack.width - stack.inset - width : stack.inset
        y: Math.round((stack.height - height - stack.iconSize / 2) / 2)
        width: stack.metrics.stackWidth || 0
        height: stack.bandTop + stack.planeHeight
        layer.enabled: !stack.software
        layer.smooth: true
        antialiasing: true

        transform: Rotation {
            origin.x: Stage.tiltOriginX(stack.edge, plane.width)
            origin.y: plane.height / 2
            axis {
                x: 0
                y: 1
                z: 0
            }
            angle: Stage.tilt(stack.edge, stack.tilt, stack.hovered)
            distanceToPlane: Math.max(500, Math.round(plane.width * 3.2))

            Behavior on angle {
                NumberAnimation {
                    duration: Theme.duration(180)
                    easing.type: Easing.OutCubic
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: stack.windows
                objectProp: "address"
            }

            StageCard {
                required property int index

                readonly property var size: Stage.cardSize(modelData.width, modelData.height, stack.front.width, stack.front.height, stack.metrics.planeWidth, stack.planeHeight)
                readonly property var place: Stage.fan(index, stack.windows.length, stack.metrics.step, stack.metrics.rise, stack.hovered)

                capture: stack.capture
                width: Math.round(size.width * place.scale)
                height: Math.round(size.height * place.scale)
                x: Stage.cardX(stack.edge, place.dx, width, plane.width)
                y: stack.bandTop + Math.round((stack.planeHeight - height) / 2) - place.dy
                z: place.z
                opacity: place.opacity

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.duration(180)
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Theme.duration(180)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // The icon and the number face the viewer: they are not turned.
    Item {
        id: label

        readonly property int frontBottom: plane.y + stack.bandTop + Math.round((stack.planeHeight + stack.frontSize.height) / 2)

        x: stack.edge === "right" ? plane.x + plane.width - width - Math.round(stack.iconSize * 0.25) : plane.x + Math.round(stack.iconSize * 0.25)
        y: frontBottom - Math.round(stack.iconSize / 2)
        width: stack.iconSize + badge.width - Math.round(stack.iconSize * 0.15)
        height: stack.iconSize
        z: 10
        LayoutMirroring.enabled: stack.edge === "right"
        LayoutMirroring.childrenInherit: true

        IconImage {
            id: appIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: stack.iconSize
            source: stack.front ? (stack.front.icon || "") : ""
            visible: source.toString() !== "" && status === Image.Ready
        }

        Rectangle {
            anchors.fill: appIcon
            visible: !appIcon.visible
            radius: Math.round(stack.iconSize / 4)
            color: Theme.surfaceAlt

            Glyph {
                anchors.centerIn: parent
                glyph: ""
                color: Theme.foreground
                font.pixelSize: Theme.font.icon
            }
        }

        Rectangle {
            id: badge

            anchors.left: appIcon.right
            anchors.leftMargin: -Math.round(stack.iconSize * 0.15)
            anchors.verticalCenter: appIcon.verticalCenter
            anchors.verticalCenterOffset: Math.round(stack.iconSize * 0.18)
            width: Math.max(height, number.implicitWidth + Theme.spacing.lg)
            height: Math.round(number.implicitHeight + Theme.spacing.xs)
            radius: height / 2
            color: Theme.popups.background
            border.width: Math.max(1, Theme.space(1))
            border.color: stack.hovered ? Theme.accent : Theme.alpha(Theme.foreground, 0.28)

            Text {
                id: number

                anchors.centerIn: parent
                text: stack.modelData.name
                color: stack.hovered ? Theme.accent : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
                font.bold: true
            }
        }
    }

    MouseArea {
        id: pointer

        x: plane.x
        y: plane.y
        width: plane.width
        height: label.y + label.height - plane.y
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: stack.chosen(stack.modelData.id)
    }
}
