// Adapted from Omarchy shell/Ui/ToggleSwitch.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: theme tokens; no keyboard cursor ring (haseen panels have none).
import QtQuick
import qs.Haseen

// Bare on/off switch: a track with a sliding knob and no label. The caller
// owns the value: bind `checked` to real state and flip it in response to
// toggled(). `busy` swallows clicks while an operation is in flight but keeps
// hover, so a refresh does not make it flicker.
Item {
    id: root

    property bool checked: false
    property bool busy: false
    property bool rounded: Theme.radius > 0
    property int trackHeight: Math.max(16, Math.round(Theme.fontSize * 1.4))
    readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
    readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
    readonly property alias containsMouse: mouse.containsMouse

    signal toggled
    signal hovered(bool isHovered)

    implicitWidth: Math.round(trackHeight * 1.9)
    implicitHeight: trackHeight

    Rectangle {
        id: track

        anchors.fill: parent
        radius: root.rounded ? height / 2 : 0
        color: root.checked ? Theme.selection : Theme.surfaceAlt
        border.color: root.checked ? Theme.accent : root.containsMouse ? Theme.foreground : Theme.border
        border.width: Theme.borderWidth

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Rectangle {
            width: root.knobSize
            height: root.knobSize
            radius: root.rounded ? height / 2 : 0
            x: root.checked ? track.width - width - root.knobInset : root.knobInset
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.accent : Theme.muted

            Behavior on x {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hovered(containsMouse)
        onClicked: {
            if (!root.busy)
                root.toggled();
        }
    }
}
