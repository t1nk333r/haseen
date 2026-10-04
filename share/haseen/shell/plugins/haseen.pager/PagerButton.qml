import QtQuick
import qs.Haseen

// A small bordered text button in theme colours. Adapted from omapager
// (https://github.com/njpatel/omapager, MIT, Copyright (c) 2026 Neil Jagdish
// Patel), which used Omarchy's Button; haseen has no shared kit control, so
// this is the one the cards and the panel share.
//
// Inside a notification card the deck's hover region sits above every card
// and takes hover first, so the card tells the button whether the pointer is
// on it (`hot`). Elsewhere `trackHover` lets the button see it itself.
Rectangle {
    id: button

    property string text: ""
    property color foreground: Theme.foreground
    property string fontFamily: Theme.fontFamily
    property real fontSize: Theme.fontSize
    property bool bordered: true
    property bool hot: false
    property bool trackHover: false
    property bool selected: false
    property bool leftAlign: false
    property bool wrap: false
    property int horizontalPadding: 8
    property int verticalPadding: 3

    signal clicked
    signal rightClicked

    readonly property bool lit: hot || (trackHover && area.containsMouse)

    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2
    radius: Theme.radius
    color: selected ? Theme.selection : lit ? Theme.surfaceAlt : "transparent"
    border.width: bordered ? Math.max(1, Theme.borderWidth) : 0
    border.color: lit ? Theme.accent : Theme.border

    Text {
        id: label

        x: button.leftAlign ? button.horizontalPadding : Math.max(button.horizontalPadding, (button.width - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: button.wrap ? Math.max(1, button.width - button.horizontalPadding * 2) : implicitWidth
        text: button.text
        textFormat: Text.PlainText
        wrapMode: button.wrap ? Text.Wrap : Text.NoWrap
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: button.selected
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: button.trackHover
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                button.rightClicked();
            else
                button.clicked();
        }
    }
}
