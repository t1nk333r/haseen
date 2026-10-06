import QtQuick
import qs.Haseen

// One labelled choice in the gestures panel. The list opens inline under the
// row (a second popup window would break the panel's focus grab), so the
// panel grows while it is open. Options are {value, label}; a value that is
// not among them (an axis set per direction in shell.json) reads as such.
Column {
    id: root

    property string label: ""
    property var options: []
    property string value: ""
    property bool open: false
    readonly property var current: {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === value)
                return options[i];
        return null;
    }

    signal picked(string value)

    spacing: 2

    Item {
        width: root.width
        height: Math.round(Theme.fontSize * 2)

        Text {
            anchors.left: parent.left
            anchors.right: box.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.foreground
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Rectangle {
            id: box

            anchors.right: parent.right
            width: Math.round(parent.width * 0.58)
            height: parent.height
            radius: Theme.radius
            color: boxMouse.containsMouse ? Theme.surfaceAlt : "transparent"
            border.width: Theme.borderWidth
            border.color: root.open ? Theme.accent : Theme.border

            Text {
                anchors.left: parent.left
                anchors.right: chevron.left
                anchors.leftMargin: Math.round(Theme.gap * 0.75)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.current ? root.current.label : "Different per direction"
                color: root.current ? Theme.foreground : Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
            }

            Text {
                id: chevron

                anchors.right: parent.right
                anchors.rightMargin: Math.round(Theme.gap * 0.75)
                anchors.verticalCenter: parent.verticalCenter
                text: root.open ? "\u25b4" : "\u25be"
                color: Theme.muted
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
            }

            MouseArea {
                id: boxMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = !root.open
            }
        }
    }

    Repeater {
        model: root.open ? root.options : []

        delegate: Rectangle {
            id: row

            required property var modelData

            x: root.width - width
            width: box.width
            height: Math.round(Theme.fontSize * 1.8)
            radius: Theme.radius
            color: rowMouse.containsMouse ? Theme.surfaceAlt : "transparent"

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Math.round(Theme.gap * 0.75)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.modelData.value === root.value ? Theme.accent : Theme.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.open = false;
                    if (row.modelData.value !== root.value)
                        root.picked(row.modelData.value);
                }
            }
        }
    }
}
