import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// haseen.kblayout's list (plan 080), opened by a right click on the bar code
// when the main keyboard has more than two layouts. Opening it reads
// `hyprctl -j devices` once, so the active row is the one Hyprland has now; a
// click runs `hyprctl switchxkblayout main N` and closes the panel.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    width: Theme.fontSize * 16
    spacing: Math.round(Theme.gap / 2)

    function choose(i: int): void {
        Keyboard.select(i);
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    Component.onCompleted: Keyboard.refresh()

    Text {
        width: parent.width
        text: "Keyboard layout"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: Keyboard.layouts

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool active: index === Keyboard.index

            width: root.width
            height: Math.round(Theme.fontSize * 2.1)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: row.active ? Theme.accent : rowMouse.containsMouse ? Theme.surfaceAlt : "transparent"
            }

            Text {
                id: codeText

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                text: row.modelData.code
                color: row.active ? Theme.accentFg : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.left: codeText.right
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: row.modelData.variant !== "" ? row.modelData.layout + " (" + row.modelData.variant + ")" : row.modelData.layout
                color: row.active ? Theme.accentFg : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.choose(row.index)
            }
        }
    }
}
