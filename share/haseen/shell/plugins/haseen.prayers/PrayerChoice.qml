import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// A row of chips, one per option ({value, label}); the current one is filled.
Row {
    id: root

    property var options: []
    property string value: ""
    property color foreground: Theme.foreground
    property string fontFamily: Theme.fontFamily
    property int fontSize: Theme.fontSize

    signal changed(string next)

    spacing: Math.round(Theme.gap / 2)

    Repeater {
        model: root.options

        Rectangle {
            id: chip

            required property var modelData
            readonly property bool selected: String(modelData.value) === root.value

            width: chipLabel.implicitWidth + Theme.fontSize
            height: chipLabel.implicitHeight + Math.round(Theme.fontSize * 0.5)
            radius: Theme.radius
            color: selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : chipMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
            border.width: Theme.borderWidth
            border.color: selected ? Theme.accent : Theme.border

            Text {
                id: chipLabel

                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: chip.modelData.label
                color: chip.selected ? Theme.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
            }

            MouseArea {
                id: chipMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!chip.selected)
                        root.changed(String(chip.modelData.value));
                }
            }
        }
    }
}
