import QtQuick
import Quickshell.Io
import qs.Haseen

// One theme in the picker's carousel, filling its slice: the preview image
// when one exists (the theme's own preview.png, else the one `haseen theme
// fetch` cached), else the theme's palette read from its colors.toml — the
// sample "Aa" over a row of swatches in the selected item, a column of
// swatches in a narrow slice. The colours drawn here are the theme's data,
// not styling; the fallback fill uses Theme tokens.
Item {
    id: preview

    property string name: ""
    // An existing preview image, or "" (the panel scanned for it).
    property string previewPath: ""
    // The colors.toml staging would use (user theme over stock).
    property string colorFile: ""
    // The size every slice decodes at: the selected item's, in pixels.
    property int decodeWidth: 0
    property int decodeHeight: 0

    property var colours: ({})
    readonly property bool hasPreview: image.status === Image.Ready
    readonly property bool wide: width > height
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

    Rectangle {
        anchors.fill: parent
        color: preview.swatch("background") || Theme.surfaceAlt
    }

    Image {
        id: image

        anchors.fill: parent
        source: preview.previewPath !== "" ? Paths.fileUrl(preview.previewPath) : ""
        sourceSize.width: preview.decodeWidth
        sourceSize.height: preview.decodeHeight
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.gap
        visible: preview.previewPath === "" || image.status === Image.Error

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: preview.wide
            text: "Aa" // i18n-ignore: a sample of the theme's foreground
            color: preview.swatch("foreground") || Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.display
            font.bold: true
        }

        // The palette in its own order (red … foreground): data, so a
        // right-to-left panel does not reverse it.
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            columns: preview.wide ? preview.stripKeys.length : 1
            spacing: 2

            Repeater {
                model: preview.stripKeys

                delegate: Rectangle {
                    required property string modelData

                    width: Math.round(preview.wide ? Math.min(preview.width / 12, preview.height / 6) : Math.min(preview.width * 0.4, preview.height / 12))
                    height: width
                    radius: Theme.radius / 2
                    color: preview.swatch(modelData) || "transparent"
                    visible: preview.swatch(modelData) !== ""
                }
            }
        }
    }

    FileView {
        path: preview.colorFile
        onLoaded: preview.parse(text())
    }
}
