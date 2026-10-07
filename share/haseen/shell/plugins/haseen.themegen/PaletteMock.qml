import QtQuick
import qs.Haseen

// A small desktop drawn in the previewed palette: the bar with its accent
// workspace and clock, a window framed in the accent, and a terminal in it
// with a prompt, a selected row, a comment and the six hues. Every colour
// here is the preview's own (`colors`, from `haseen theme generate --json`);
// only sizes and fonts come from Theme.
Rectangle {
    id: root

    required property var colors
    // The background image, behind a band of the theme's background.
    property string image: ""
    property real pixelRatio: 1

    readonly property int line: Math.round(Theme.fontSize * 1.5)

    radius: Theme.radius
    color: colors.background
    border.color: colors.muted
    border.width: Theme.borderWidth
    clip: true

    Image {
        anchors.fill: parent
        anchors.margins: root.border.width
        source: root.image !== "" ? Paths.fileUrl(root.image) : ""
        sourceSize.width: Math.round(root.width * root.pixelRatio)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: 0.85
    }

    // The bar.
    Rectangle {
        id: bar

        x: root.border.width
        y: root.border.width
        width: root.width - root.border.width * 2
        height: root.line + Theme.gap
        color: root.colors.background

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.gap / 2)

            Repeater {
                model: 3

                Rectangle {
                    required property int index

                    width: root.line
                    height: root.line - Theme.gap / 2
                    radius: Theme.radius
                    color: index === 0 ? root.colors.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: String(parent.index + 1)
                        color: parent.index === 0 ? root.colors.background : root.colors.dark_foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: parent.index === 0
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: "10:24"
            color: root.colors.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Repeater {
                model: ["green", "yellow", "red"]

                Rectangle {
                    required property string modelData

                    width: Math.round(Theme.fontSize * 0.6)
                    height: width
                    radius: width / 2
                    color: root.colors[modelData]
                }
            }
        }
    }

    // A window: lighter surface, accent border, a terminal inside.
    Rectangle {
        anchors.top: bar.bottom
        anchors.left: parent.left
        // Two thirds of the width: the wallpaper shows beside the window.
        width: Math.round(root.width * 0.66)
        anchors.bottom: parent.bottom
        anchors.margins: Theme.gap * 1.5
        radius: Theme.radius
        color: root.colors.background
        border.color: root.colors.accent
        border.width: Theme.borderWidth * 2
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: 0

            Text {
                height: root.line
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.StyledText
                text: "<font color='" + root.colors.green + "'>~/Pictures</font> <font color='" + root.colors.blue + "'>❯</font> ls"
                color: root.colors.foreground
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 1
            }

            Rectangle {
                width: parent.width
                height: root.line
                radius: Theme.radius
                color: root.colors.selection

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.gap / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "a selected row"
                    color: root.colors.foreground
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            Text {
                height: root.line
                verticalAlignment: Text.AlignVCenter
                text: "# muted comment"
                color: root.colors.dark_foreground
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 1
                font.italic: true
            }

            Row {
                height: root.line
                spacing: Theme.gap

                Repeater {
                    model: ["red", "yellow", "green", "cyan", "blue", "magenta"]

                    Text {
                        required property string modelData

                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        color: root.colors[modelData]
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }
        }
    }
}
