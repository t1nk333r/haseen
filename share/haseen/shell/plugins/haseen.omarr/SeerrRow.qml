import QtQuick
import qs.Haseen

// One row of the Seerr detail (SeerrPane): a request, or a title from a
// discover list or a search. Its poster (from the service's cache; a quiet
// mark until it is there), the title, a second line and the row's buttons:
// approve and decline on a request waiting for approval, request on a title
// Seerr does not have yet. A decline or a request asks first: while
// `confirming`, the line is `question` and the button sends.
//
// Written for haseen (plan 097, follow-up 2026-10-31), on the Omarr*
// controls adapted from omARR (MIT, Copyright (c) 2026 luccast).
OmarrRow {
    id: root

    property var item: ({})
    property string posterUrl: ""
    property string line: ""
    property color lineColor: Theme.subtle(Theme.surface)
    property string question: ""
    property bool confirming: false
    property bool canApprove: false
    property bool canDecline: false
    property bool canRequest: false
    property string requestTip: ""

    signal opened
    signal approved
    signal declined
    signal requested
    signal cancelled

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(poster.height, texts.implicitHeight) + Theme.gap * 1.5
    hasCursor: mouse.containsMouse

    // The row opens the title's page in Seerr.
    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }

    Row {
        anchors.fill: parent
        anchors.margins: Math.round(Theme.gap * 0.75)
        spacing: Theme.gap

        Rectangle {
            id: poster

            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Theme.fontSize * 2.4)
            height: Math.round(width * 1.5)
            color: Theme.surfaceAlt
            clip: true

            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                textFormat: Text.PlainText
                text: root.item && root.item.mediaType === "tv" ? "\u{f0502}" : "\u{f0381}"
                color: Theme.subtle(Theme.surfaceAlt)
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.body
            }

            Image {
                id: art

                anchors.fill: parent
                visible: status === Image.Ready
                source: root.posterUrl
                sourceSize: Qt.size(Math.max(1, poster.width * 2), Math.max(1, poster.height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }
        }

        Column {
            id: texts

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - poster.width - parent.spacing - (actions.visible ? actions.width + parent.spacing : 0)
            spacing: Math.max(1, Math.round(Theme.gap / 3))

            Text {
                width: parent.width
                textFormat: Text.PlainText
                // Set rather than implicit: a right-to-left panel then aligns
                // Latin text and numbers to the right too (plan 109).
                horizontalAlignment: Text.AlignLeft
                text: root.item && root.item.title ? String(root.item.title) : ""
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                text: root.confirming ? root.question : root.line
                color: root.confirming ? Theme.urgent : root.lineColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Row {
            id: actions

            anchors.verticalCenter: parent.verticalCenter
            visible: root.canApprove || root.canDecline || root.canRequest
            spacing: 2

            OmarrButton {
                visible: root.canApprove && !root.confirming
                glyph: "\u{f012c}"
                tooltipText: I18n.tr("Approve")
                onClicked: root.approved()
            }

            // Asked once: Seerr approves only a request still waiting.
            OmarrButton {
                visible: root.canDecline
                glyph: "\u{f073a}"
                tooltipText: I18n.tr("Decline")
                foreground: root.confirming ? Theme.urgent : Theme.foreground
                hoverColor: Theme.urgent
                onClicked: root.declined()
            }

            // Asked once: a request may start a download at once.
            OmarrButton {
                visible: root.canRequest
                glyph: "\u{f0415}"
                tooltipText: root.requestTip
                foreground: root.confirming ? Theme.accent : Theme.foreground
                hoverColor: Theme.accent
                onClicked: root.requested()
            }

            OmarrButton {
                visible: root.confirming
                glyph: "\u{f0156}"
                tooltipText: I18n.tr("Cancel")
                onClicked: root.cancelled()
            }
        }
    }
}
