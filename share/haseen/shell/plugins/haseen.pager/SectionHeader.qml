import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// A panel section heading: the title (click folds), a Clear button while
// there is something to clear, and the fold chevron. Adapted from omapager
// (https://github.com/njpatel/omapager, MIT, Copyright (c) 2026 Neil Jagdish
// Patel), whose Clear is there whether or not the section is folded.
Item {
    id: root

    property string title: ""
    property bool folded: false
    property bool foldable: true
    property bool canClear: false

    signal toggled
    signal cleared

    width: parent ? parent.width : 0
    height: Theme.fontSize * 2

    Text {
        anchors.left: parent.left
        anchors.right: buttons.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.title
        color: Theme.muted
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(8, Theme.fontSize - 2)
        font.bold: true
        font.letterSpacing: 1
    }

    MouseArea {
        anchors.left: parent.left
        anchors.right: buttons.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        enabled: root.foldable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    Row {
        id: buttons

        anchors.right: parent.right
        height: parent.height

        BarButton {
            visible: root.canClear
            height: parent.height
            glyph: "\u{f0a79}"
            color: Theme.foreground
            onClicked: root.cleared()
        }

        BarButton {
            visible: root.foldable
            height: parent.height
            glyph: root.folded ? "\u{f0140}" : "\u{f0143}"
            color: Theme.foreground
            onClicked: root.toggled()
        }
    }
}
