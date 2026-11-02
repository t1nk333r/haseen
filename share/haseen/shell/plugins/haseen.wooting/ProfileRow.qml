import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One stored profile in haseen.wooting's panel (plan 099): a check on the
// active one, the full name, a click to switch. Written for the port, with
// no upstream code: the original drew these rows with Omarchy's qs.Ui Button.
// Plan 153 added a second line with the profile's own settings and a dot in
// the colour the profile stores, each only when the keyboard reports it.
Item {
    id: root

    property string text
    // The settings line, already translated; empty draws a one-line row.
    property string detail: ""
    // The profile's stored colour, "#rrggbb", or empty for none.
    property string swatch: ""
    property bool active: false

    signal clicked

    implicitWidth: Math.max(label.implicitWidth, detailLabel.implicitWidth) + Theme.fontSize * 4
    implicitHeight: Math.round(Theme.fontSize * (root.detail !== "" ? 3.4 : 2.2))

    Rectangle {
        id: tint

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

    Column {
        anchors.left: check.right
        anchors.leftMargin: Theme.gap
        anchors.right: dot.visible ? dot.left : parent.right
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: label

            width: parent.width
            // A profile name comes off the keyboard; it never renders as markup.
            textFormat: Text.PlainText
            text: root.text
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
            font.bold: root.active
        }

        Text {
            id: detailLabel

            width: parent.width
            visible: root.detail !== ""
            textFormat: Text.PlainText
            text: root.detail
            elide: Text.ElideRight
            // Read on what is under it: the tint when shown, else the panel.
            color: Theme.subtle(tint.visible ? Theme.over(tint.color, tint.color.a, Theme.surface) : Theme.surface)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    Rectangle {
        id: dot

        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(Theme.fontSize * 0.75)
        height: width
        radius: width / 2
        visible: root.swatch !== ""
        // The keyboard's own colour for the profile, not a theme colour; the
        // ring keeps a dark or a surface-coloured one visible.
        color: root.swatch !== "" ? root.swatch : Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
