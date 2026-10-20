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

    width: parent ? parent.width : implicitWidth
    spacing: Math.max(1, Math.round(Theme.gap / 3))

    Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.title
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
    }

    Text {
        width: parent.width
        visible: root.subtitle !== ""
        textFormat: Text.PlainText
        text: root.subtitle
        color: root.subtitleColor
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
        elide: Text.ElideRight
    }

    OmarrProgress {
        value: root.progress
    }
}
