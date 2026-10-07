import QtQuick
import Quickshell.Services.Mpris
import qs.Haseen
import qs.Haseen.Widgets
import "Media.js" as Media

// haseen.media panel (plan 078): cover art, title, artist and album, a seek
// bar, previous / play-pause / next, shuffle and repeat, the player's own
// volume, and a switcher when several players are on the bus. Everything is
// a Quickshell.Services.Mpris property binding (D-Bus signals); a control the
// player does not offer is hidden (Media.controls). Cover art follows plan
// 010's remote-image rule (Media.artSource): local art always, https art
// only with the remoteArt setting (off by default), else a themed
// placeholder. The host loads the panel only while it is open. Open it with
// a right or middle click on the bar's media label or
// `haseen shell ipc panel toggle haseen.media`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var players: Mpris.players.values
    // D-Bus name of the player picked in the switcher, for as long as the
    // panel is open; "" follows the bar's pick (playing, else paused).
    property string chosen: ""
    readonly property int index: Media.selectIndex(players.map(p => ({
                dbusName: p.dbusName,
                isPlaying: p.isPlaying,
                stopped: p.playbackState === MprisPlaybackState.Stopped
            })), chosen)
    readonly property MprisPlayer player: index >= 0 ? players[index] : null
    readonly property var labels: Media.playerLabels(players.map(p => ({
                identity: p.identity,
                dbusName: p.dbusName
            })))
    readonly property var controls: Media.controls(player ? {
        canControl: player.canControl,
        canGoPrevious: player.canGoPrevious,
        canGoNext: player.canGoNext,
        canTogglePlaying: player.canTogglePlaying,
        canSeek: player.canSeek,
        lengthSupported: player.lengthSupported,
        positionSupported: player.positionSupported,
        length: player.length,
        shuffleSupported: player.shuffleSupported,
        loopSupported: player.loopSupported,
        volumeSupported: player.volumeSupported
    } : null)
    readonly property string art: player ? Media.artSource(player.trackArtUrl, settings.remoteArt === true) : ""
    readonly property string title: player ? (String(player.trackTitle || "").trim() || player.identity) : ""
    // Quickshell reports `position` extrapolated from the last D-Bus value
    // but only re-reads it when positionChanged() is emitted; the tick below
    // does that, so a tick costs no D-Bus call.
    readonly property real position: player && controls.time ? player.position : 0
    readonly property bool ticking: player !== null && player.isPlaying && controls.time

    width: Theme.fontSize * 24
    spacing: Theme.gap

    function choose(i: int): void {
        if (i >= 0 && i < players.length)
            chosen = players[i].dbusName;
    }

    function seek(fraction: real): void {
        if (player && controls.seek)
            player.position = fraction * player.length;
    }

    function setVolume(v: real): void {
        if (player && controls.volume)
            player.volume = Math.max(0, Math.min(1, v));
    }

    function toggleShuffle(): void {
        if (player && controls.shuffle)
            player.shuffle = !player.shuffle;
    }

    function cycleLoop(): void {
        if (player && controls.loop)
            player.loopState = Media.nextLoop(player.loopState);
    }

    // The seek bar's clock: one positionChanged() a second while the panel
    // is open and the player plays a track with a length (plan 078). The
    // panel exists only while open, so nothing ticks behind a closed one;
    // single-shot, re-armed from onTriggered while `ticking` holds.
    // haseen:ui-timeout
    Timer {
        id: tick

        interval: 1000
        repeat: false
        running: root.ticking
        onTriggered: {
            if (!root.ticking)
                return;
            root.player.positionChanged();
            tick.restart();
        }
    }

    // A bordered choice, as in the battery panel: `active` is filled.
    component Choice: Item {
        id: choice

        property string label
        property bool active: false

        signal clicked

        implicitWidth: choiceText.implicitWidth + Theme.gap * 3
        implicitHeight: Math.round(Theme.fontSize * 2.1)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: choice.active ? Theme.accent : choiceMouse.containsMouse ? Theme.surfaceAlt : "transparent"
            border.color: choice.active || choiceMouse.containsMouse ? Theme.accent : Theme.border
            border.width: Theme.borderWidth
        }

        Text {
            id: choiceText

            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: choice.label
            color: choice.active ? Theme.accentFg : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: choice.active
        }

        MouseArea {
            id: choiceMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.clicked()
        }
    }

    // A transport button: a glyph cell sized for the panel, not the bar.
    component Control: BarButton {
        implicitHeight: Math.round(Theme.fontSize * 2.4)
        padding: Theme.gap
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Media"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 2)
            visible: root.players.length === 1
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.labels.length > 0 ? root.labels[0] : ""
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: parent.width
        visible: root.player === null
        wrapMode: Text.WordWrap
        text: "Nothing is playing (no MPRIS player on the bus)."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // The switcher: one pill per player, the shown one filled.
    Flow {
        width: parent.width
        visible: root.players.length > 1
        spacing: Theme.gap

        Repeater {
            model: root.labels

            delegate: Choice {
                required property int index
                required property string modelData

                label: modelData
                active: index === root.index
                onClicked: root.choose(index)
            }
        }
    }

    Row {
        visible: root.player !== null
        spacing: Theme.gap * 2

        Item {
            id: cover

            width: Theme.fontSize * 7
            height: width

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: Theme.borderWidth
                visible: artImage.status !== Image.Ready
            }

            Glyph {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                glyph: "\uf001"
                color: Theme.muted
                font.pixelSize: Theme.fontSize * 3
            }

            Image {
                id: artImage

                anchors.fill: parent
                visible: status === Image.Ready
                source: root.art
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                // Decode at most twice the cell: a player's art can be huge.
                sourceSize.width: cover.width * 2
                sourceSize.height: cover.height * 2
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - cover.width - Theme.gap * 2
            spacing: Math.round(Theme.gap / 2)

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.title
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }

            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.player ? String(root.player.trackArtist || "").trim() : ""
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.player ? String(root.player.trackAlbum || "").trim() : ""
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Column {
        width: parent.width
        visible: root.controls.time
        spacing: Math.round(Theme.gap / 2)

        TrackBar {
            width: parent.width
            enabled: root.controls.seek
            live: false
            value: root.player ? Media.fraction(root.position, root.player.length) : 0
            onMoved: v => root.seek(v)
        }

        Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
                id: elapsed

                anchors.left: parent.left
                text: Media.formatTime(root.position)
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Text {
                anchors.right: parent.right
                text: root.player ? Media.formatTime(root.player.length) : ""
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Item {
        width: parent.width
        height: transport.implicitHeight
        visible: root.player !== null

        Row {
            id: transport

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.gap

            Control {
                visible: root.controls.shuffle
                glyph: "\uf074"
                color: root.player && root.player.shuffle ? Theme.accent : Theme.muted
                onClicked: root.toggleShuffle()
            }

            Control {
                visible: root.controls.previous
                glyph: "\uf048"
                color: Theme.foreground
                onClicked: root.player.previous()
            }

            Control {
                visible: root.controls.playPause
                glyph: root.player && root.player.isPlaying ? "\uf04c" : "\uf04b"
                color: Theme.accent
                highlighted: true
                onClicked: root.player.togglePlaying()
            }

            Control {
                visible: root.controls.next
                glyph: "\uf051"
                color: Theme.foreground
                onClicked: root.player.next()
            }

            Control {
                visible: root.controls.loop
                glyph: root.player ? Media.loopGlyph(root.player.loopState) : ""
                color: root.player && root.player.loopState !== MprisLoopState.None ? Theme.accent : Theme.muted
                onClicked: root.cycleLoop()
            }
        }
    }

    Item {
        width: parent.width
        height: Math.round(Theme.fontSize * 2)
        visible: root.controls.volume

        Glyph {
            id: volumeIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: Media.volumeGlyph(root.player ? root.player.volume : 0)
            color: Theme.muted
        }

        TrackBar {
            anchors.left: volumeIcon.right
            anchors.right: volumePct.left
            anchors.leftMargin: Theme.gap
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            value: root.player ? root.player.volume : 0
            onMoved: v => root.setVolume(v)
        }

        Text {
            id: volumePct

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2.6
            horizontalAlignment: Text.AlignRight
            text: Math.round((root.player ? root.player.volume : 0) * 100) + "%"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
