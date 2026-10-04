import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
Text {
    property color foreground: Theme.foreground
    property string fontFamily: Theme.fontFamily

    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: Theme.accent
    font.family: fontFamily
    font.pixelSize: Math.max(1, Theme.fontSize - 1)
    font.bold: true
    font.letterSpacing: 1.1
    elide: Text.ElideRight
}
