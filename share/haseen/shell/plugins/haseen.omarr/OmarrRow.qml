import QtQuick
import qs.Haseen

// A selectable row surface: `hasCursor` is the keyboard or hover cursor,
// `current` the row whose detail is open. One highlight per state, as
// upstream's CursorSurface.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: theme tokens instead of the Ui CursorSurface.
Rectangle {
    property bool hasCursor: false
    property bool current: false

    radius: Theme.radius
    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : hasCursor ? Theme.surfaceAlt : "transparent"
    border.width: hasCursor ? Theme.borderWidth : 0
    border.color: Theme.accent

    Behavior on color {
        ColorAnimation {
            duration: 60
        }
    }
}
