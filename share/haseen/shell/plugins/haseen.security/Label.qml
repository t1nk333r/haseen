import QtQuick
import qs.Haseen
Text {
    property bool heading: false
    property bool mono: false
    color: Theme.foreground
    font.family: mono ? Theme.fontMono : Theme.fontFamily
    font.pixelSize: Math.round((heading ? 14 : 12) * Math.max(1 / 11, Theme.fontSize / 11))
    font.bold: heading
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    Accessible.role: Accessible.StaticText
    Accessible.name: text
}
