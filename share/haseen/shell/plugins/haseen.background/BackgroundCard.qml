import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One background of the current theme: a thumbnail-sized decode of the image
// file, its file name under it, a dot when it is the one on screen.
Item {
    id: card

    required property string path
    required property string label
    property bool selected: false
    property bool active: false
    property real pixelRatio: 1

    signal picked
    signal hovered

    readonly property real previewHeight: Math.round(width * 9 / 16)

    implicitWidth: width
    implicitHeight: frame.height + row.height + Theme.gap / 2

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
            // The grid decodes at card size: a 4K wallpaper costs a thumbnail.
            // Both sides, so the crop fills the frame from pixels decoded for
            // it (as ImageCard.qml, plan 083).
            sourceSize.width: Math.round(card.width * card.pixelRatio)
            sourceSize.height: Math.round(card.previewHeight * card.pixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: status === Image.Ready
        }

        Glyph {
            anchors.centerIn: parent
            glyph: "\uf03e"
            color: Theme.muted
            visible: preview.status !== Image.Ready
        }
    }

    Row {
        id: row

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
            width: row.width - (card.active ? Theme.fontSize : 0)
            text: card.label
            color: card.selected ? Theme.accent : Theme.foreground
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
            font.bold: card.selected
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: card.hovered()
        onClicked: card.picked()
    }
}
