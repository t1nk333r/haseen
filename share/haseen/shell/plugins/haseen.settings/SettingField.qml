import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// One declared setting: its key, type and description, the effective value
// (marked when shell.json sets it), and an editor for its type. A boolean
// flips on click; anything else is typed and staged on Enter or when the
// field loses focus, and parsed for its type (arrays and objects as JSON).
// Reset drops the key from shell.json, back to the manifest default.
Item {
    id: root

    property var field: ({})
    property var pending: undefined
    property bool hasPending: false
    property bool resetting: false
    property string error: ""

    signal edited(string text)
    signal reset

    readonly property var shownValue: hasPending ? pending : resetting ? field.defaultValue : field.value

    height: column.implicitHeight + Theme.gap

    Column {
        id: column

        width: parent.width
        spacing: 2

        Item {
            width: parent.width
            height: Theme.fontSize * 1.8

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - resetButton.width
                text: root.field.key + "  (" + root.field.type + ")" + (root.field.set && !root.resetting ? "  · set" : "  · default") + (root.hasPending || root.resetting ? "  · unsaved" : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            BarButton {
                id: resetButton

                anchors.right: parent.right
                height: parent.height
                visible: root.field.set && !root.resetting
                text: "Reset"
                color: Theme.muted
                onClicked: root.reset()
            }
        }

        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            text: root.field.description || ""
            textFormat: Text.PlainText
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        BarButton {
            visible: root.field.type === "boolean"
            height: Theme.fontSize * 2
            text: root.shownValue === true ? "On" : "Off"
            highlighted: root.shownValue === true
            color: root.shownValue === true ? Theme.accent : Theme.muted
            onClicked: root.edited(root.shownValue === true ? "false" : "true")
        }

        Rectangle {
            width: parent.width
            height: Theme.fontSize * 2.2
            visible: root.field.type !== "boolean"
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.color: root.error !== "" ? Theme.urgent : input.activeFocus ? Theme.accent : Theme.border
            border.width: Theme.borderWidth

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                text: Model.formatValue(root.field.type, root.shownValue)
                color: Theme.foreground
                selectionColor: Theme.selection
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize
                clip: true
                onAccepted: root.edited(text)
                onActiveFocusChanged: if (!activeFocus && text !== Model.formatValue(root.field.type, root.shownValue))
                    root.edited(text)
            }
        }

        Text {
            width: parent.width
            visible: root.error !== ""
            text: root.error
            color: Theme.urgent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
