import QtQuick
import qs.Haseen
import "Themegen.js" as Model

// The previewed palette as swatch rows: surfaces, text, accent and selection;
// the six hues; their bright variants. Each swatch is the preview's colour
// with its key and value under it; the frame and labels are Theme tokens.
// The rows are the palette's own order, data rather than reading order, so a
// right-to-left panel does not reverse them; the captions are colors.toml
// key names (bg, fg, red …) and stay as they are.
Column {
    id: root

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    required property var colors
    property int swatch: Theme.fontSize * 3

    spacing: Theme.gap

    Repeater {
        model: Model.swatchRows(root.colors)

        Row {
            required property var modelData

            spacing: Math.round(Theme.gap / 2)

            Repeater {
                model: parent.modelData

                Column {
                    required property var modelData

                    width: root.swatch
                    spacing: 1

                    Rectangle {
                        width: root.swatch
                        height: Math.round(root.swatch * 0.6)
                        radius: Theme.radius
                        color: parent.modelData.color
                        border.color: Theme.border
                        border.width: Theme.borderWidth
                    }

                    Text {
                        width: root.swatch
                        text: Model.swatchLabel(parent.modelData.key)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.subtle(Theme.surface)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }
                }
            }
        }
    }
}
