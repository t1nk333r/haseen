import QtQuick
import Quickshell.Io
import qs.Haseen

// One theme in the picker grid: its preview image when one exists (the
// theme's own preview.png, else the one `haseen theme fetch` cached), else a
// strip of the theme's palette read from its colors.toml. The colours drawn
// here are the theme's data, not styling; the card itself uses Theme tokens.
Item {
    id: card

    required property string name
    // An existing preview image, or "" (the panel scanned for it).
    required property string previewPath
    // The colors.toml staging would use (user theme over stock).
    required property string colorFile
    property bool selected: false
    property bool active: false
    property real pixelRatio: 1

    signal picked
    signal hovered

    readonly property real previewHeight: Math.round(width * 9 / 16)
    property var colours: ({})
    readonly property bool hasPreview: preview.status === Image.Ready
    readonly property var stripKeys: ["red", "yellow", "green", "cyan", "blue", "magenta", "accent", "foreground"]
    readonly property var ansiKeys: ({
            background: "color0",
            red: "color1",
            green: "color2",
            yellow: "color3",
            blue: "color4",
            magenta: "color5",
            cyan: "color6",
            foreground: "color7",
            accent: "color4"
        })

    // The colour for key, through the colours colors.toml spells it with.
    function swatch(key: string): string {
        return colours[key] || colours[ansiKeys[key] || ""] || "";
    }

    function parse(text: string): void {
        const out = {};
        const re = /^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})\b/;
        for (const line of text.split("\n")) {
            const m = re.exec(line);
            if (m)
                out[m[1]] = m[2];
        }
        colours = out;
    }

    implicitHeight: frame.height + label.height + Theme.gap / 2

    Rectangle {
        id: frame

        width: card.width
        height: card.previewHeight
        radius: Theme.radius
        color: card.swatch("background") || Theme.surfaceAlt
        border.color: card.selected ? Theme.accent : Theme.border
        border.width: card.selected ? Theme.borderWidth * 2 : Theme.borderWidth
        clip: true

        Image {
            id: preview

            anchors.fill: parent
            anchors.margins: frame.border.width
            source: card.previewPath !== "" ? "file://" + card.previewPath : ""
            sourceSize.width: Math.round(card.width * card.pixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: status === Image.Ready
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.gap
            visible: !card.hasPreview

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Aa"
                color: card.swatch("foreground") || Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 2
                font.bold: true
            }

            Row {
                spacing: 2

                Repeater {
                    model: card.stripKeys

                    delegate: Rectangle {
                        required property string modelData

                        width: Math.round(card.width / 12)
                        height: width
                        radius: Theme.radius / 2
                        color: card.swatch(modelData) || "transparent"
                        visible: card.swatch(modelData) !== ""
                    }
                }
            }
        }
    }

    Row {
        id: label

        anchors.top: frame.bottom
        anchors.topMargin: Theme.gap / 2
        width: card.width
        spacing: Theme.gap / 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize / 2
            height: width
            radius: width / 2
            color: Theme.accent
            visible: card.active
        }

        Text {
            width: label.width - (card.active ? Theme.fontSize : 0)
            text: card.name
            color: card.selected ? Theme.accent : Theme.foreground
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: card.selected
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: card.hovered()
        onClicked: card.picked()
    }

    FileView {
        path: card.colorFile
        onLoaded: card.parse(text())
    }
}
