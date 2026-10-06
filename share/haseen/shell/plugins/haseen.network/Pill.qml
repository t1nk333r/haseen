// Adapted from Omarchy shell/plugins/panels/network/Panel.qml (BandPill,
// DnsProviderPill). MIT, Copyright (c) David Heinemeier Hansson.
// haseen: one bordered pill on theme tokens instead of qs.Ui Button.
import QtQuick
import qs.Haseen

// A bordered choice in a row of equal pills. `active` (fill) is the value in
// force, `selected` (bold) the one asked for; they differ while a change is
// in flight or, for the Wi-Fi band, while Automatic picks the band.
Item {
    id: root

    property string text
    property bool active: false
    property bool selected: active
    property bool busy: false
    readonly property alias containsMouse: mouse.containsMouse

    signal clicked
    signal hovered(bool isHovered)

    implicitWidth: label.implicitWidth + Theme.gap * 3
    implicitHeight: Math.round(Theme.fontSize * 2.1)
    opacity: busy ? 0.6 : 1

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.active ? Theme.accent : root.containsMouse ? Theme.surfaceAlt : "transparent"
        border.color: root.active || root.containsMouse ? Theme.accent : Theme.border
        border.width: Theme.borderWidth
    }

    Text {
        id: label

        anchors.fill: parent
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: root.text
        elide: Text.ElideRight
        color: root.active ? Theme.accentFg : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: root.selected
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hovered(containsMouse)
        onClicked: {
            if (!root.busy)
                root.clicked();
        }
    }
}
