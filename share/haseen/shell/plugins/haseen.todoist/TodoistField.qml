import QtQuick
import qs.Haseen

// A one-line text field for the haseen.todoist panel, on Theme tokens:
// field background, accent border while focused, a placeholder, and
// password echo for the token. Stands in for the Omarchy Ui TextField the
// upstream panel used (omarchy-todoist, MIT, Copyright (c) 2026
// aryan-techie; see LICENSE beside this file).
TextInput {
    id: root

    property string placeholderText: ""
    property bool password: false

    height: implicitHeight
    leftPadding: Math.round(Theme.gap * 0.75)
    rightPadding: leftPadding
    topPadding: Math.round(Theme.gap / 2)
    bottomPadding: topPadding
    color: Theme.foreground
    selectionColor: Theme.selection
    selectedTextColor: Theme.foreground
    echoMode: password ? TextInput.Password : TextInput.Normal
    clip: true
    selectByMouse: true
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body

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
        visible: root.text === "" && !root.inputMethodComposing
        textFormat: Text.PlainText
        text: root.placeholderText
        color: Theme.muted
        elide: Text.ElideRight
        font: root.font
    }
}
