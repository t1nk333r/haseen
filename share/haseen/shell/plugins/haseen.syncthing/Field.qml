import QtQuick
import qs.Haseen

// A one-line text field on theme tokens, as the weather panel's city field:
// Enter emits accepted(), Escape clears it instead of closing the panel.
TextInput {
    id: field

    property string placeholder

    leftPadding: Math.round(Theme.gap * 0.75)
    rightPadding: leftPadding
    topPadding: Math.round(Theme.gap / 2)
    bottomPadding: topPadding
    clip: true
    selectByMouse: true
    color: Theme.foreground
    selectionColor: Theme.selection
    selectedTextColor: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape && field.text !== ""
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && field.text !== "") {
            field.text = "";
            event.accepted = true;
        }
    }

    Rectangle {
        z: -1
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.width: Theme.borderWidth
        border.color: field.activeFocus ? Theme.accent : Theme.border
    }

    Text {
        anchors.fill: parent
        anchors.leftMargin: field.leftPadding
        verticalAlignment: Text.AlignVCenter
        visible: field.text === ""
        text: field.placeholder
        color: Theme.subtle(Theme.surfaceAlt)
        elide: Text.ElideRight
        font: field.font
    }
}
