// Adapted from Omarchy shell/plugins/panels/network/Panel.qml (BandPill,
// DnsProviderPill) and shell/Ui/Button.qml. MIT, Copyright (c) David
// Heinemeier Hansson.
// haseen: one bordered pill on theme tokens instead of qs.Ui Button, shared
// by the network, battery, display, media and theme generator panels. Plan
// 115 draws it as Omarchy's bordered Button draws a band or DNS pill.
import QtQuick
import qs.Haseen

// A bordered choice in a row. `active` (the selected fill) is the value in
// force; `selected` (bold, also the selected fill) the one asked for, which
// differs from `active` while a change is in flight or, for the Wi-Fi band,
// while Automatic picks the band; `pending` draws the accent border and a
// bold label while that change runs (a haseen state Omarchy's Button lacks).
// Hover and keyboard focus take Omarchy's hover-cursor fill and border.
// `busy` and `enabled: false` dim the pill and drop its clicks. Its width is
// the bold label's, so turning bold never shifts the pills that follow.
Item {
    id: root

    property string text
    property bool active: false
    property bool selected: active
    property bool pending: false
    property bool busy: false
    readonly property alias containsMouse: mouse.containsMouse
    readonly property bool hot: mouse.containsMouse || activeFocus

    // Omarchy's BandPill: body-small text, control-padding-x across and
    // control-padding-y + space(2) down (network/Panel.qml:1718-1722), with
    // the widest border any state paints reserved (Button.qml:71-77).
    readonly property int horizontalPadding: Theme.spacing.controlPaddingX
    readonly property int verticalPadding: Theme.spacing.controlPaddingY + Theme.space(2)
    readonly property int reservedBorder: Math.max(Theme.normalBorderWidth, Theme.hoverBorderWidth, Theme.selectedBorderWidth)

    signal clicked
    signal hovered(bool isHovered)

    implicitWidth: Math.ceil(boldMetrics.advanceWidth) + (horizontalPadding + reservedBorder) * 2
    implicitHeight: Math.ceil(boldMetrics.height) + (verticalPadding + reservedBorder) * 2
    opacity: busy || !enabled ? 0.5 : 1

    TextMetrics {
        id: boldMetrics

        text: root.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.bold: true
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        // Button.qml:121-126: pressed > hot > selected/active > none.
        color: mouse.pressed ? Theme.pressedFill : root.hot ? Theme.hoverFill : (root.selected || root.active) ? Theme.selectedFill : "transparent"
        // Button.qml:115-119 with `bordered`: hover-cursor while hot, else
        // the normal border; pending uses the accent.
        border.color: root.pending ? Theme.accent : root.hot ? Theme.hoverBorderColor : Theme.normalBorderColor
        border.width: root.pending ? Math.max(1, Theme.normalBorderWidth) : root.hot ? Theme.hoverBorderWidth : Theme.normalBorderWidth

        Behavior on color {
            ColorAnimation {
                duration: Theme.duration(120)
            }
        }
    }

    Text {
        anchors.fill: parent
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: root.text
        elide: Text.ElideRight
        color: root.selected ? Theme.selectedStateColor(Theme.foreground, Theme.accent) : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.bold: root.selected || root.pending
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
