import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// haseen.kblayout's list (plan 080), opened by a right click on the bar code
// when the main keyboard has more than two layouts. Opening it reads
// `hyprctl -j devices` once, so the active row is the one Hyprland has now; a
// click, or Enter on the row under the cursor, runs `hyprctl switchxkblayout
// main N` and closes the panel. Up/Down, j/k and Tab move the cursor, as in
// haseen.session. Each row is the code the bar shows, the layout's xkb
// description ("Arabic") and its xkb name and variant.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // The row under the keyboard cursor; it starts on the active layout.
    property int current: Math.max(0, Keyboard.index)

    width: Theme.fontSize * 16
    spacing: Math.round(Theme.gap / 2)
    focus: true

    function choose(i: int): void {
        Keyboard.select(i);
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    function shift(delta: int): void {
        const n = Keyboard.layouts.length;
        if (n > 0)
            current = (current + delta + n) % n;
    }

    Keys.onUpPressed: shift(-1)
    Keys.onDownPressed: shift(1)
    Keys.onTabPressed: shift(1)
    Keys.onBacktabPressed: shift(-1)
    Keys.onReturnPressed: choose(current)
    Keys.onEnterPressed: choose(current)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_J || event.key === Qt.Key_K) {
            shift(event.key === Qt.Key_J ? 1 : -1);
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        Keyboard.refresh();
        forceActiveFocus();
    }

    Text {
        width: parent.width
        text: "Keyboard layout"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
    }

    Repeater {
        model: Keyboard.layouts

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool active: index === Keyboard.index
            readonly property bool cursor: index === root.current
            readonly property color fill: cursor ? Theme.selection : rowMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

            width: root.width
            height: Math.round(Theme.fontSize * 2.1)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: row.fill
            }

            Text {
                id: codeText

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                text: row.modelData.code
                color: row.active ? Theme.accent : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                id: nameText

                anchors.left: codeText.right
                anchors.right: idText.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: Keyboard.layoutName(row.modelData.layout)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                id: idText

                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.modelData.variant !== "" ? row.modelData.layout + " " + row.modelData.variant : row.modelData.layout
                color: Theme.subtle(row.fill)
                font.family: Theme.fontMono
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
