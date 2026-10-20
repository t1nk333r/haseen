import QtQuick
import qs.Haseen

// A labelled switch row; the whole row is the click target. `clicked` asks
// for the change, the owner flips `checked`, as upstream's Toggle.
//
// Adapted from SettingsView.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: theme tokens instead of the Ui Toggle.
Item {
    id: root

    property string label: ""
    property string description: ""
    property bool checked: false

    signal clicked

    width: parent ? parent.width : implicitWidth
    implicitWidth: texts.implicitWidth + track.width + Theme.gap
    implicitHeight: Math.max(texts.implicitHeight, track.height) + Math.round(Theme.gap / 2)

    Column {
        id: texts

        anchors.left: parent.left
        anchors.right: track.left
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.description !== ""
            textFormat: Text.PlainText
            text: root.description
            color: Theme.subtle(Theme.surface)
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: height * 2
        height: Math.round(Theme.fontSize * 1.4)
        radius: height / 2
        color: root.checked ? Theme.accent : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.13)
        border.width: Theme.borderWidth
        border.color: root.checked ? Theme.accent : Theme.border

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.accentFg : Theme.foreground

            Behavior on x {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
