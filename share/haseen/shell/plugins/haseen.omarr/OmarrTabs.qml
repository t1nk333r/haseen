import QtQuick
import qs.Haseen

// Underlined text tabs: the overview's ON DECK / RECENTLY ADDED / CALENDAR
// and the settings' SETTINGS / FLEET. `model` is [{id, label}], each label
// English marked with I18n.mark and shown in the interface language.
//
// Adapted from Panel.qml and SettingsView.qml in omARR (MIT, Copyright (c)
// 2026 luccast), as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and
// UPSTREAM.md beside this file. haseen changes: one file for both tab rows,
// theme tokens.
Flow {
    id: root

    property var model: []
    property string current: ""

    signal picked(string id)

    spacing: Theme.gap * 2

    Repeater {
        model: root.model

        Item {
            id: chip

            required property var modelData
            readonly property bool selected: root.current === modelData.id

            width: label.implicitWidth
            height: label.implicitHeight + Math.round(Theme.gap * 0.75)

            Text {
                id: label

                textFormat: Text.PlainText
                text: I18n.tr(chip.modelData.label)
                color: chip.selected || mouse.containsMouse ? Theme.foreground : Theme.subtle(Theme.surface)
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
                font.bold: true
                font.letterSpacing: 1.1
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(1, Theme.borderWidth)
                visible: chip.selected
                color: Theme.accent
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(chip.modelData.id)
            }
        }
    }
}
