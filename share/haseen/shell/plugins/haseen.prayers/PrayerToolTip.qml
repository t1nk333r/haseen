import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// Drawn inside the panel above its owner (a second popup window would
// break the panel's focus grab).
Rectangle {
    id: root

    property string text: ""
    property string fontFamily: Theme.fontFamily

    z: 100
    anchors.bottom: parent ? parent.top : undefined
    anchors.bottomMargin: Math.round(Theme.gap / 2)
    anchors.right: parent ? parent.right : undefined
    width: label.implicitWidth + Theme.gap * 2
    height: label.implicitHeight + Theme.gap
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: Theme.borderWidth
    border.color: Theme.border

    Text {
        id: label

        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.text
        color: Theme.foreground
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
    }
}
