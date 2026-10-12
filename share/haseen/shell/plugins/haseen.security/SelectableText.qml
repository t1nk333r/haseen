import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Controls.TextArea {
    readOnly: true
    selectByMouse: true
    activeFocusOnTab: true
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    color: Theme.foreground
    font.family: Theme.fontMono
    font.pixelSize: Math.round(12 * Theme.fontSize / 11)
    selectionColor: Theme.selection
    selectedTextColor: Theme.foreground
    Accessible.role: Accessible.EditableText
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        border.width: parent.activeFocus ? 2 : 0
        border.color: Theme.foreground
    }
}
