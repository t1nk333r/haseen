import QtQuick
import qs.Haseen

// A section label in haseen.omarr's panel (FLEET, DOWNLOADING, HISTORY…),
// upstream's PanelSectionHeader. Set `color` for the warnings header.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: theme tokens.
Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Math.max(1, Theme.fontSize - 1)
    font.bold: true
    font.letterSpacing: 1.1
    elide: Text.ElideRight
}
