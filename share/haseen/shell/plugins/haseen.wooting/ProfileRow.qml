import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One stored profile in haseen.wooting's panel (plan 099): a check on the
// active one, the full name, a click to switch. Written for the port, with
// no upstream code: the original drew these rows with Omarchy's qs.Ui Button.
Item {
    id: root

    property string text
    property bool active: false

    signal clicked

    implicitWidth: label.implicitWidth + Theme.fontSize * 3
    implicitHeight: Math.round(Theme.fontSize * 2.2)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.active ? Theme.selection : Theme.surfaceAlt
        visible: root.active || mouse.containsMouse
    }

    Glyph {
        id: check

        anchors.left: parent.left
        anchors.leftMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{F012C}"
        color: Theme.accent
        opacity: root.active ? 1 : 0
    }

    Text {
        id: label

        anchors.left: check.right
        anchors.leftMargin: Theme.gap
        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        // A profile name comes off the keyboard; it never renders as markup.
        textFormat: Text.PlainText
        text: root.text
        elide: Text.ElideRight
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
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
