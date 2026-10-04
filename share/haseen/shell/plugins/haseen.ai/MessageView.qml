import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One chat message. Plain text on purpose: rich or Markdown text would let a
// model's reply make the shell fetch remote images. The text is selectable;
// the copy button (shown on hover) copies the whole message.
Item {
    id: root

    required property string role
    required property string content
    required property string modelName
    required property string phase

    signal copyRequested(string text)

    readonly property bool mine: role === "user"
    readonly property int pad: Theme.gap

    implicitHeight: column.implicitHeight + pad * 2

    HoverHandler {
        id: hover

        onHoveredChanged: copy.copied = false
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.mine ? Theme.surfaceAlt : "transparent"
        border.color: root.phase === "error" ? Theme.urgent : "transparent"
        border.width: Theme.borderWidth
    }

    Column {
        id: column

        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: Math.round(Theme.gap / 2)

        Item {
            width: parent.width
            height: copy.implicitHeight

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.mine ? "You" : (root.modelName || "assistant") + (root.phase === "stopped" ? "  · stopped" : root.phase === "streaming" ? "  ·  …" : "")
                color: root.mine ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: root.mine
            }

            BarButton {
                id: copy

                property bool copied: false

                anchors.right: parent.right
                implicitHeight: Theme.fontSize + Theme.gap * 2
                glyph: "\uf0c5"
                text: copied ? "copied" : ""
                color: Theme.muted
                visible: hover.hovered && root.content !== ""
                onClicked: {
                    root.copyRequested(root.content);
                    copied = true;
                }
            }
        }

        TextEdit {
            width: parent.width
            text: root.content !== "" ? root.content : root.phase === "streaming" ? "…" : ""
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
            color: root.phase === "error" ? Theme.urgent : Theme.foreground
            selectionColor: Theme.selection
            selectedTextColor: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }
}
