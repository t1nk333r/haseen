import QtQuick
import qs.Haseen
import "Drift.js" as Drift

// One screen of the native screensaver: the branding (image, else text),
// a large clock and the date in a card that moves a few pixels per tick.
// Swallows keys and clicks and reports them as input().
Item {
    id: view

    property string clock: ""
    property string date: ""
    property string branding: ""
    property string image: ""
    property int tick: 0
    property int phase: 0

    signal input

    readonly property int margin: Theme.gap * 8
    readonly property var pos: Drift.position(tick, phase, width, height, card.width, card.height, margin, 4)

    focus: true
    Keys.onPressed: event => {
        event.accepted = true;
        view.input();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPressed: view.input()
        onWheel: view.input()
    }

    Column {
        id: card

        x: view.pos.x
        y: view.pos.y
        spacing: Theme.gap * 2

        Image {
            id: logo

            anchors.horizontalCenter: parent.horizontalCenter
            source: view.image
            visible: view.image !== "" && status === Image.Ready
            sourceSize.height: Math.round(view.height / 4)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !logo.visible && text !== ""
            text: view.branding.replace(/\s+$/, "")
            color: Theme.accent
            textFormat: Text.PlainText
            font.family: Theme.fontMono
            font.pixelSize: Math.max(10, Math.round(view.height / 48))
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.clock
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(32, Math.round(Math.min(view.width, view.height) / 5))
            font.weight: Font.Light
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.date
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(Theme.fontSize, Math.round(view.height / 40))
        }
    }
}
