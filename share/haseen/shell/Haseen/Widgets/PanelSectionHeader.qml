// Adapted from Omarchy shell/Ui/PanelSectionHeader.qml. MIT, Copyright (c)
// David Heinemeier Hansson.
import QtQuick
import qs.Haseen

// The bold caption that opens a panel section ("Output", "Wi-Fi networks"),
// after a PanelSeparator (plan 115): caption size (10 px at base 12), the
// foreground darkened 1.4 times, with room above for glyphs that overshoot
// their ascent so a clipping list never beheads it.
Text {
    property color foreground: Theme.foreground

    textFormat: Text.PlainText
    color: Qt.darker(foreground, 1.4)
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.bold: true
    topPadding: Math.ceil(font.pixelSize * 0.15)
}
