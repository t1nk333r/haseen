import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// A TextInput with a field background and a placeholder.
TextInput {
    id: root

    property string placeholderText: ""
    property color foreground: Theme.foreground

    height: implicitHeight
    leftPadding: Math.round(Theme.gap * 0.75)
    rightPadding: leftPadding
    topPadding: Math.round(Theme.gap / 2)
    bottomPadding: topPadding
    color: foreground
    selectionColor: Theme.selection
    selectedTextColor: Theme.foreground
    clip: true
    selectByMouse: true
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    Rectangle {
        z: -1
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.width: Theme.borderWidth
        border.color: root.activeFocus ? Theme.accent : Theme.border
    }

    Text {
        anchors.fill: parent
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        verticalAlignment: Text.AlignVCenter
        visible: root.text === ""
        textFormat: Text.PlainText
        text: root.placeholderText
        color: Theme.muted
        elide: Text.ElideRight
        font: root.font
    }
}
