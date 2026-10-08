import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One image in the picker grid: a thumbnail-sized decode of the file, its
// label under it. The frame, the selection and the text are Theme tokens;
// only the picture itself is the file's own pixels.
Item {
    id: card

    required property string path
    required property string label
    property bool showLabel: true
    property bool selected: false
    property real pixelRatio: 1

    signal picked
    signal hovered

    readonly property real previewHeight: Math.round(width * 9 / 16)

    implicitWidth: width
    implicitHeight: frame.height + (showLabel ? text.height + Theme.gap / 2 : 0)

    Rectangle {
        id: frame

        width: card.width
        height: card.previewHeight
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: card.selected ? Theme.accent : Theme.border
        border.width: card.selected ? Theme.borderWidth * 2 : Theme.borderWidth
        clip: true

        Image {
            id: preview

            anchors.fill: parent
            anchors.margins: frame.border.width
            source: card.path !== "" ? Paths.fileUrl(card.path) : ""
            // Decoded at the card's size, never at the file's: a 4K wallpaper
            // costs the same as a thumbnail here. Both sides, so the crop
            // fills the frame from pixels decoded for it: a wide picture
            // decoded to the width alone came out short and was scaled up
            // (plan 083).
            sourceSize.width: Math.round(card.width * card.pixelRatio)
            sourceSize.height: Math.round(card.previewHeight * card.pixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: status === Image.Ready
        }

        // A file Qt cannot decode keeps its slot with a placeholder glyph.
        Glyph {
            anchors.centerIn: parent
            glyph: "\uf03e"
            color: Theme.muted
            visible: preview.status !== Image.Ready
        }
    }

    Text {
        id: text

        anchors.top: frame.bottom
        anchors.topMargin: Theme.gap / 2
        width: card.width
        text: card.label
        color: card.selected ? Theme.accent : Theme.foreground
        elide: Text.ElideRight
        textFormat: Text.PlainText
        visible: card.showLabel
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: card.selected
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: card.hovered()
        onClicked: card.picked()
    }
}
