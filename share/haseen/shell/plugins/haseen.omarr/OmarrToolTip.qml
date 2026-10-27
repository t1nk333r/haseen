import QtQuick
import qs.Haseen

// A tooltip for haseen.omarr's panel buttons, drawn inside the panel beside
// its owner: a second popup window would break the panel's focus grab.
// Stands in for the Ui tooltip of upstream's PanelActionButton.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: theme tokens, no separate window.
Rectangle {
    id: root

    property string text: ""
    // Below the owner for buttons on the panel's top edge, where a tooltip
    // above would fall outside the popup surface.
    property bool below: false

    z: 100
    anchors.bottom: parent && !below ? parent.top : undefined
    anchors.top: parent && below ? parent.bottom : undefined
    anchors.bottomMargin: Math.round(Theme.gap / 2)
    anchors.topMargin: Math.round(Theme.gap / 2)
    anchors.right: parent ? parent.right : undefined
    width: label.implicitWidth + Theme.gap * 2
    height: label.implicitHeight + Theme.gap
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: Theme.borderWidth
    border.color: Theme.border

    Text {
        id: label

        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.text
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }
}
