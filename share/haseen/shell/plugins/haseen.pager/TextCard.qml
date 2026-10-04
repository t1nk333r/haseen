import QtQuick
import qs.Haseen

// A Recent or History row in the panel: source and time, summary, and the
// flattened body, clipped until opened. Left click opens or folds the body;
// right or middle click forgets it (Recent only). Text only: a recent row
// keeps text, never the notification or its actions. Adapted from omapager
// (https://github.com/njpatel/omapager, MIT, Copyright (c) 2026 Neil Jagdish
// Patel).
Rectangle {
    id: root

    property string meta: ""
    property string summary: ""
    property string bodyLine: ""
    property int closedLines: 2
    property int openLines: 12
    property bool forgettable: true
    property bool open: false

    signal forget

    height: text.implicitHeight + Theme.gap * 2
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.color: Theme.border
    border.width: 1

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (body.visible)
                    root.open = !root.open;
                return;
            }
            if (root.forgettable)
                root.forget();
        }
    }

    Column {
        id: text

        x: Theme.gap
        y: Theme.gap
        width: parent.width - Theme.gap * 2
        spacing: 2

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.meta
            color: Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Theme.fontSize - 2)
        }

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.summary
            color: Theme.foreground
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            id: body

            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.bodyLine
            color: Theme.foreground
            wrapMode: Text.WordWrap
            maximumLineCount: root.open ? root.openLines : root.closedLines
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }
}
