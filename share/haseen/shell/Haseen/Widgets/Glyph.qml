import QtQuick
import qs.Haseen

// A single icon glyph (Nerd Font codepoint) in the theme's mono font.
Text {
    property string glyph: ""

    text: glyph
    color: Theme.foreground
    font.family: Theme.fontMono
    font.pixelSize: Theme.fontSize + 2
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
