import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// A labelled integer with - / + steppers; modified(value) on each committed
// change, clamped to from..to (poll interval, queue page size).
//
// Adapted from SettingsView.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: theme tokens and Pill steppers instead of the Ui
// NumberField.
Column {
    id: root

    property string label: ""
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property int value: 0
    readonly property alias field: input

    signal modified(int next)

    function commit(v: int): void {
        const n = Math.max(from, Math.min(to, v));
        if (n !== value)
            modified(n);
        input.text = String(n);
    }

    // commit() replaces the field's text binding, so a value saved elsewhere
    // is written back here.
    onValueChanged: input.text = String(value)
    spacing: Math.round(Theme.gap / 2)

    Text {
        width: parent.width
        textFormat: Text.PlainText
        // Set rather than implicit: a right-to-left panel then aligns
        // Latin text and numbers to the right too (plan 109).
        horizontalAlignment: Text.AlignLeft
        text: root.label
        color: Theme.subtle(Theme.surface)
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
        elide: Text.ElideRight
    }

    Row {
        spacing: Math.round(Theme.gap / 2)

        Pill {
            text: "−"
            enabled: root.value > root.from
            onClicked: root.commit(root.value - root.stepSize)
        }

        OmarrField {
            id: input

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 5
            horizontalAlignment: TextInput.AlignHCenter
            text: String(root.value)
            validator: IntValidator {
                bottom: 0
                top: root.to
            }
            onEditingFinished: root.commit(parseInt(text, 10) || root.from)
        }

        Pill {
            text: "+"
            enabled: root.value < root.to
            onClicked: root.commit(root.value + root.stepSize)
        }
    }
}
