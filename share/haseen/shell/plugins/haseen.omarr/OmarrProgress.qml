import QtQuick
import qs.Haseen

// A thin progress track (downloads, sessions, queue rows). `value` is 0..1.
// It fills from the start edge, the right in a right-to-left panel; a
// playback position opts out (LayoutMirroring.enabled: false), as time runs
// left to right.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: theme tokens.
Rectangle {
    id: root

    property real value: 0
    property color fill: Theme.foreground

    width: parent ? parent.width : 0
    height: Math.max(2, Math.round(Theme.gap / 3))
    radius: 1
    color: Qt.rgba(fill.r, fill.g, fill.b, 0.2)

    Rectangle {
        anchors.left: parent.left
        width: parent.width * Math.max(0, Math.min(1, Number(root.value) || 0))
        height: parent.height
        radius: 1
        color: root.fill
    }
}
