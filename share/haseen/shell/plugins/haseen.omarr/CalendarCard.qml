import QtQuick
import QtQuick.Window
import qs.Haseen
import "Model.js" as Model

// A 16:9 media card: fanart (or the poster until fanart arrives), the title
// with its rating, a second line, a watched mark and a resume track. Used for
// calendar entries, on deck and recently added. Art comes from the service's
// local cache as file:// URLs and loads asynchronously.
//
// Adapted from CalendarCard.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: square image corners instead of a MultiEffect
// mask, a still glyph instead of the endless spinner, overlay and progress
// colours from theme tokens.
Item {
    id: root

    property var item: ({})
    property string posterUrl: ""
    property string fanartUrl: ""

    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property size artSize: Qt.size(Math.max(1, Math.round(width * dpr)), Math.max(1, Math.round(height * dpr)))
    readonly property string ratingLabel: Model.formatRating(item && item.rating, item && item.ratingSource)
    readonly property real progress: {
        const n = Number(root.item && root.item.progress);
        if (!(n > 0))
            return 0;
        return n >= 1 ? 1 : n;
    }
    readonly property bool showProgress: progress > 0 && progress < 1
    readonly property bool watched: !!(item && item.watched === true)
    readonly property bool hovered: hoverArea.containsMouse
    readonly property bool artPending: {
        if (fanart.status === Image.Ready)
            return false;
        if ((fanartUrl === "" || fanart.status === Image.Error) && poster.status === Image.Ready)
            return false;
        if (fanartUrl !== "" && fanart.status !== Image.Error)
            return true;
        if (posterUrl !== "" && poster.status !== Image.Error)
            return true;
        return false;
    }
    property bool showPlaceholder: false

    signal clicked

    // Art that is already cached arrives within a frame or two; the mark only
    // shows for art that is genuinely on its way.
    onArtPendingChanged: {
        if (artPending) {
            placeholderDelay.restart();
        } else {
            placeholderDelay.stop();
            showPlaceholder = false;
        }
    }

    width: parent ? parent.width : implicitWidth
    height: Math.round(width * 9 / 16)

    // haseen:ui-timeout
    Timer {
        id: placeholderDelay

        interval: 90
        onTriggered: root.showPlaceholder = true
    }

    MouseArea {
        id: hoverArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Rectangle {
        id: card

        anchors.fill: parent
        clip: true
        color: Theme.background
        opacity: root.hovered ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Image {
            id: fanart

            anchors.fill: parent
            visible: root.fanartUrl !== ""
            opacity: status === Image.Ready ? 1 : 0
            source: root.fanartUrl
            sourceSize: root.artSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        Image {
            id: poster

            anchors.fill: parent
            visible: root.posterUrl !== "" && fanart.status !== Image.Ready
            opacity: status === Image.Ready ? 1 : 0
            source: root.posterUrl
            sourceSize: root.artSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "\u{f048d}"
            color: Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize * 2
            opacity: root.showPlaceholder ? 0.5 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        // The text sits on the background colour faded in under it, so it
        // reads over any art in light and dark themes alike.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.5
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.88)
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.gap
            visible: root.watched
            width: watchedRow.implicitWidth + Theme.gap
            height: watchedRow.implicitHeight + Math.round(Theme.gap / 2)
            radius: Theme.radius
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)

            Row {
                id: watchedRow

                anchors.centerIn: parent
                spacing: Math.round(Theme.gap / 2)

                Text {
                    textFormat: Text.PlainText
                    text: "\u{f012c}"
                    color: Theme.foreground
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    textFormat: Text.PlainText
                    text: "Watched"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    font.bold: true
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.gap
            anchors.bottomMargin: Theme.gap + (root.showProgress ? progressTrack.height : 0)
            spacing: 1

            Item {
                width: parent.width
                height: titleText.implicitHeight

                Text {
                    id: titleText

                    anchors.left: parent.left
                    anchors.right: ratingBadge.left
                    anchors.rightMargin: root.ratingLabel !== "" ? Theme.gap : 0
                    textFormat: Text.PlainText
                    text: root.item && root.item.title ? String(root.item.title) : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    id: ratingBadge

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.ratingLabel !== ""
                    width: visible ? implicitWidth : 0
                    textFormat: Text.PlainText
                    text: root.ratingLabel
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    font.bold: true
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.item && root.item.subtitle ? String(root.item.subtitle) : ""
                color: Theme.subtle(Theme.background)
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
                elide: Text.ElideRight
            }
        }

        OmarrProgress {
            id: progressTrack

            visible: root.showProgress
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(3, Math.round(Theme.gap / 2))
            radius: 0
            value: root.progress
            fill: Theme.accent
        }
    }

    Rectangle {
        z: 2
        anchors.fill: parent
        color: "transparent"
        border.width: Math.max(1, Theme.borderWidth)
        border.color: Theme.accent
        opacity: root.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }
}
