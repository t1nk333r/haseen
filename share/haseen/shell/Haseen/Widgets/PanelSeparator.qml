// Adapted from Omarchy shell/Ui/PanelSeparator.qml. MIT, Copyright (c) David
// Heinemeier Hansson.
import QtQuick
import qs.Haseen

// A 1 px divider between panel sections (plan 115): the foreground at 0.12.
Rectangle {
    property color foreground: Theme.foreground
    property real strength: 0.12

    width: parent ? parent.width : implicitWidth
    implicitWidth: 100
    implicitHeight: 1
    height: 1
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
