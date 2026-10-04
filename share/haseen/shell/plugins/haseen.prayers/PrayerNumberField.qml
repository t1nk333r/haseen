import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// An integer field with - / + steppers; modified(value) on every change.
Row {
    id: root

    property int from: 0
    property int to: 100
    property int stepSize: 1
    property int value: 0
    property color foreground: Theme.foreground
    property string fontFamily: Theme.fontFamily
    property int fieldWidth: Theme.fontSize * 7
    readonly property alias field: input

    signal modified(int next)

    spacing: 2

    function commit(v: int): void {
        const n = Math.max(from, Math.min(to, v));
        if (n !== value)
            modified(n);
        input.text = String(n);
    }

    PrayerButton {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u2212"
        bordered: true
        foreground: root.foreground
        fontSize: Math.max(1, Theme.fontSize - 1)
        onClicked: root.commit(root.value - root.stepSize)
    }

    PrayerTextField {
        id: input

        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Theme.fontSize * 3, root.fieldWidth - Theme.fontSize * 4)
        horizontalAlignment: TextInput.AlignHCenter
        foreground: root.foreground
        font.family: root.fontFamily
        text: String(root.value)
        validator: IntValidator {
            bottom: root.from
            top: root.to
        }
        onEditingFinished: root.commit(parseInt(text, 10) || 0)
    }

    PrayerButton {
        anchors.verticalCenter: parent.verticalCenter
        text: "+"
        bordered: true
        foreground: root.foreground
        fontSize: Math.max(1, Theme.fontSize - 1)
        onClicked: root.commit(root.value + root.stepSize)
    }
}
