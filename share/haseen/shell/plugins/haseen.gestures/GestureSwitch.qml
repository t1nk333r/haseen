import QtQuick
import qs.Haseen

// A labelled on/off row in the gestures panel, with an optional one-line
// explanation under the label. Theme tokens only.
Item {
    id: root

    property string label: ""
    property string description: ""
    property bool checked: false

    signal toggled

    implicitHeight: Math.max(labels.implicitHeight, track.height)

    Column {
        id: labels

        anchors.left: parent.left
        anchors.right: track.left
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.label
            color: Theme.foreground
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            width: parent.width
            visible: root.description !== ""
            text: root.description
            color: Theme.muted
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 2)
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round(Theme.fontSize * 1.5)
        width: height * 2
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.surfaceAlt
        border.width: Theme.borderWidth
        border.color: root.checked ? Theme.accent : Theme.border

        Rectangle {
            width: track.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? track.width - width - 3 : 3
            color: root.checked ? Theme.accentFg : Theme.foreground
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }
}
