import QtQuick
import qs.Haseen

// A one-line text field with a placeholder. `password` masks it, for the API
// key and password fields; their text is never logged.
//
// Adapted from SettingsView.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: a TextInput on theme tokens instead of the Ui
// TextField.
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
    clip: true
    selectByMouse: true
    echoMode: password ? TextInput.Password : TextInput.Normal
    inputMethodHints: password ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase : Qt.ImhNoAutoUppercase
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
        visible: root.text === ""
        textFormat: Text.PlainText
        text: root.placeholderText
        color: Theme.subtle(Theme.surfaceAlt)
        elide: Text.ElideRight
        font: root.font
    }
}
