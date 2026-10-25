// Adapted from Omarchy shell/Ui/ToggleSwitch.qml. MIT, Copyright (c) David
// Heinemeier Hansson.
// haseen: theme tokens from qs.Haseen.
import QtQuick
import qs.Haseen

// A bare on/off switch (plan 115): the caller owns the value, binds
// `checked` to it and flips it on `toggled()`. `busy` swallows clicks while
// an operation runs. The track is the selected fill when on and the normal
// fill when off, with the matching state border; the knob is the selected
// colour when on and the foreground darkened when off. Pill-shaped when
// Hyprland rounds its corners, square when it does not. A ring outside the
// track shows hover and the keyboard cursor (`cursorRing`, on while the
// switch takes its own clicks).
Item {
    id: root

    property bool checked: false
    property bool busy: false
    property bool interactive: true
    property bool hasCursor: false
    property bool cursorRing: interactive
    property int cursorPad: Theme.space(6)
    property bool rounded: Theme.radius > 0
    property color foreground: Theme.foreground
    property color accent: Theme.accent
    // ToggleSwitch.qml:62-65.
    property int trackHeight: Math.max(22, Math.round(Theme.spacing.controlHeight * 0.55))
    property int trackWidth: Math.round(trackHeight * 1.9)
    property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
    property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property alias containsMouse: mouse.containsMouse
    readonly property bool hot: hasCursor || mouse.containsMouse
    readonly property int _pad: cursorRing ? cursorPad : 0

    signal toggled
    signal hovered(bool isHovered)

    implicitWidth: trackWidth + _pad * 2
    implicitHeight: trackHeight + _pad * 2

    Rectangle {
        anchors.fill: parent
        visible: root.cursorRing && root.hot
        color: "transparent"
        radius: Theme.radius
        border.color: Theme.hoverBorderFor(root.foreground, root.accent)
        border.width: Theme.hoverBorderWidth
    }

    Rectangle {
        id: track

        width: root.trackWidth
        height: root.trackHeight
        anchors.centerIn: parent
        radius: root.rounded ? height / 2 : 0
        color: root.checked ? Theme.selectedFillFor(root.foreground, root.accent) : Theme.normalFillFor(root.foreground, root.accent)
        border.color: root.checked ? Theme.selectedBorderFor(root.foreground, root.accent) : Theme.normalBorderFor(root.foreground, root.accent)
        border.width: root.checked ? Theme.selectedBorderWidth : Theme.normalBorderWidth

        Behavior on color {
            ColorAnimation {
                duration: Theme.duration(120)
            }
        }

        Rectangle {
            width: root.knobSize
            height: root.knobSize
            radius: root.rounded ? height / 2 : 0
            x: root.checked !== root.mirrored ? track.width - width - root.knobInset : root.knobInset
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)

            Behavior on x {
                NumberAnimation {
                    duration: Theme.duration(120)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration(120)
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hovered(containsMouse)
        onClicked: {
            if (!root.busy)
                root.toggled();
        }
    }
}
