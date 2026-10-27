import QtQuick
import qs.Haseen

// A title, an optional second line and a progress track: one active download
// or one playback session.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: the repeated delegates are one file, theme tokens.
Column {
    id: root

    property string title: ""
    property string subtitle: ""
    property color subtitleColor: Theme.subtle(Theme.surface)
    property real progress: 0
    // A playback session: its track keeps time running left to right in a
    // right-to-left panel; a download's fills from the start edge.
    property bool playback: false

    width: parent ? parent.width : implicitWidth
    spacing: Math.max(1, Math.round(Theme.gap / 3))

    Text {
        width: parent.width
        textFormat: Text.PlainText
        // Set rather than implicit: a right-to-left panel then aligns
        // Latin text and numbers to the right too (plan 109).
        horizontalAlignment: Text.AlignLeft
        text: root.title
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
        elide: Text.ElideRight
    }

    Text {
        width: parent.width
        visible: root.subtitle !== ""
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: root.subtitle
        color: root.subtitleColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        elide: Text.ElideRight
    }

    OmarrProgress {
        value: root.progress
        LayoutMirroring.enabled: root.playback ? false : root.LayoutMirroring.enabled
        LayoutMirroring.childrenInherit: true
    }
}
