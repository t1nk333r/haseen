// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml (menu separator).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file, theme tokens.
import QtQuick
import qs.Haseen

// A thin rule between tray menu groups.
Item {
    implicitHeight: Theme.gap + 1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.border
    }
}
