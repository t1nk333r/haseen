// Adapted from Omarchy shell/plugins/panels/audio/Panel.qml (volume rows).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file, theme tokens.
import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// One volume row for a PwNodeAudio: glyph (click toggles mute), label,
// draggable bar, percentage. Writes go straight to the node; the bar follows
// the node's own volume, so external changes show up live.
Item {
    id: row

    required property var audio
    property string glyph
    property string label
    property string detail: ""

    readonly property bool muted: audio ? audio.muted : true
    readonly property real volume: audio ? audio.volume : 0

    function setVolume(v: real): void {
        if (!audio)
            return;
        audio.volume = Math.max(0, Math.min(1, v));
        if (audio.muted && v > 0)
            audio.muted = false;
    }

    implicitHeight: Math.round(Theme.fontSize * 3.4)

    BarButton {
        id: mute

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        glyph: row.glyph
        color: row.muted ? Theme.muted : Theme.accent
        highlighted: !row.muted
        onClicked: if (row.audio)
            row.audio.muted = !row.audio.muted
    }

    Column {
        anchors.left: mute.right
        anchors.leftMargin: Theme.gap
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(Theme.gap / 2)

        Item {
            width: parent.width
            height: name.implicitHeight

            Text {
                id: name

                anchors.left: parent.left
                anchors.right: pct.left
                anchors.rightMargin: Theme.gap
                text: row.detail !== "" ? row.label + " · " + row.detail : row.label
                elide: Text.ElideRight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                id: pct

                anchors.right: parent.right
                text: row.muted ? "Muted" : Math.round(row.volume * 100) + "%"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }

        Item {
            id: track

            width: parent.width
            height: Math.round(Theme.fontSize * 0.9)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Theme.surfaceAlt

                Rectangle {
                    width: parent.width * Math.min(1, row.volume)
                    height: parent.height
                    radius: 2
                    color: row.muted ? Theme.muted : Theme.accent
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: (track.width - width) * Math.min(1, row.volume)
                width: parent.height
                height: width
                radius: width / 2
                color: Theme.foreground
                border.width: Theme.borderWidth
                border.color: row.muted ? Theme.muted : Theme.accent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: event => row.setVolume(event.x / Math.max(1, width))
                onPositionChanged: event => {
                    if (pressed)
                        row.setVolume(event.x / Math.max(1, width));
                }
                onWheel: event => row.setVolume(row.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05))
            }
        }
    }
}
