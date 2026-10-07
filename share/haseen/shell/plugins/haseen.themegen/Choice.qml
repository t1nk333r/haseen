import QtQuick
import qs.Haseen

// One bordered choice in a row: a scheme, a mode, Save or Apply. `active`
// fills it with the accent; `enabled: false` dims it and ignores clicks.
Item {
    id: root

    property string text
    property bool active: false

    signal clicked

    implicitWidth: label.implicitWidth + Theme.gap * 3
    implicitHeight: Math.round(Theme.fontSize * 2.1)
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.active ? Theme.accent : mouse.containsMouse ? Theme.surfaceAlt : "transparent"
        border.color: root.active || mouse.containsMouse ? Theme.accent : Theme.border
        border.width: Theme.borderWidth
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        color: root.active ? Theme.accentFg : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: root.active
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
