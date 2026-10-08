import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Column {
    id: root
    property string label: ""
    property alias text: input.text
    property string error: ""
    signal committed()
    signal submitted()
    signal edited(string value)
    spacing: Theme.gap
    function focusInput(): void { input.forceActiveFocus(); }
    Label { width: parent.width; text: root.label }
    Controls.TextField {
        id: input
        width: parent.width
        height: Math.max(40, implicitHeight)
        color: Theme.foreground
        font.family: Theme.fontMono
        font.pixelSize: Math.round(12 * Theme.fontSize / 11)
        selectionColor: Theme.selection
        selectedTextColor: Theme.foreground
        activeFocusOnTab: true
        Accessible.name: root.label
        Accessible.description: root.error
        onEditingFinished: root.committed()
        onAccepted: root.submitted()
        Keys.priority: Keys.AfterItem
        onTextEdited: root.edited(text)
        background: Rectangle {
            color: Theme.surfaceAlt
            radius: Theme.radius
            border.width: input.activeFocus ? 2 : Theme.borderWidth
            border.color: input.activeFocus ? Theme.foreground : Theme.border
        }
    }
    Label { width: parent.width; visible: root.error !== ""; text: root.error }
}
