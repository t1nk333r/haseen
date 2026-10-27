import QtQuick
import qs.Haseen

// Written for haseen's port (plan 096); no upstream code.
// One boolean setting: a label, a detail line and an on/off pill. Clicking
// anywhere on the row flips it.
Item {
    id: root

    property string label
    property string detail
    property bool checked: false

    signal toggled(bool on)

    width: parent ? parent.width : 0
    height: Math.round(Theme.fontSize * 3)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: mouse.containsMouse
    }

    Column {
        anchors.left: parent.left
        anchors.right: pill.left
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.label
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
        }

        Text {
            width: parent.width
            text: root.detail
            visible: text !== ""
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    Rectangle {
        id: pill

        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.fontSize * 2.6
        height: Theme.fontSize * 1.4
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.surface
        border.color: root.checked ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            // On is the end edge: the left one in a right-to-left panel.
            x: root.checked !== root.LayoutMirroring.enabled ? parent.width - width - 2 : 2
            color: root.checked ? Theme.accentFg : Theme.muted
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.toggled(!root.checked)
    }
}
