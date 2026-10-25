import QtQuick
import qs.Haseen

// A single icon glyph (Nerd Font codepoint) in the shell's font, which is
// the user's Nerd Font monospace as Omarchy draws icons in Style.font.family,
// at Omarchy's icon size (Style.font.icon, 14 px at base 12; plan 115).
Text {
    property string glyph: ""

    text: glyph
    color: Theme.foreground
    font.family: Theme.fontMono
    font.pixelSize: Theme.font.icon
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
