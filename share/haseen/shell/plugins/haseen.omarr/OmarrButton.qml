import QtQuick
import qs.Haseen

// A square glyph button with a tooltip, haseen.omarr's stand-in for
// upstream's PanelActionButton (header actions, queue pause/resume/remove,
// paging, reorder and remove in settings).
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: theme tokens, Nerd Font glyph in Theme.fontMono.
Rectangle {
    id: root

    property string glyph: ""
    property string tooltipText: ""
    property bool tooltipBelow: false
    property color foreground: Theme.foreground
    property color hoverColor: foreground
    readonly property alias containsMouse: mouse.containsMouse

    signal clicked

    implicitWidth: Math.round(Theme.fontSize * 2.2)
    implicitHeight: implicitWidth
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    opacity: enabled ? 1 : 0.4
    color: mouse.containsMouse && enabled ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12) : "transparent"

    Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.glyph
        color: mouse.containsMouse && root.enabled ? root.hoverColor : root.foreground
        font.family: Theme.fontMono
        font.pixelSize: Theme.font.icon
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    OmarrToolTip {
        visible: mouse.containsMouse && root.tooltipText !== ""
        text: root.tooltipText
        below: root.tooltipBelow
    }
}
