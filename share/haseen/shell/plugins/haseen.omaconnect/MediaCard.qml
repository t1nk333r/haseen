import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The phone's media player in the haseen.omaconnect panel: KDE Connect's
// downloaded cover (a local file only), title and artist, the players to
// switch between, and previous / play-pause / next. Read when the panel opens
// and after the daemon's mpris signals. Adapted from OmaConnect's
// components/MediaPlayerSection.qml (MIT, Copyright (c) 2026 OmaConnect
// contributors).
Column {
    id: card

    required property var service

    readonly property var media: service.media
    readonly property color subtle: Theme.subtle(Theme.surface)

    spacing: Math.round(Theme.gap / 2)

    Row {
        width: card.width
        spacing: Theme.gap

        Image {
            id: art

            width: Math.round(Theme.fontSize * 3.2)
            height: width
            visible: card.media.albumArt !== "" && status === Image.Ready
            source: card.media.albumArt === "" ? "" : card.media.albumArt.charAt(0) === "/" ? Paths.fileUrl(card.media.albumArt) : card.media.albumArt
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Column {
            width: card.width - (art.visible ? art.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: card.media.title || "Nothing playing"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                visible: text !== ""
                text: [card.media.artist, card.media.player].filter(s => s !== "").join(" · ")
                color: card.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Flow {
        width: card.width
        spacing: Math.round(Theme.gap / 2)

        Pill {
            text: "Previous"
            onClicked: card.service.mediaAction("Previous")
        }

        Pill {
            text: card.media.isPlaying ? "Pause" : "Play"
            active: card.media.isPlaying
            onClicked: card.service.mediaAction("PlayPause")
        }

        Pill {
            text: "Next"
            onClicked: card.service.mediaAction("Next")
        }

        Repeater {
            model: card.media.playerList.length > 1 ? card.media.playerList : []

            delegate: Pill {
                required property var modelData

                text: modelData
                active: modelData === card.media.player
                onClicked: card.service.mediaPlayer(modelData)
            }
        }
    }
}
