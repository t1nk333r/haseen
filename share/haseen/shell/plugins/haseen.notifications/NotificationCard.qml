import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets

// One notification: app, summary, body, image and action buttons. As a popup
// it times out on its own (paused while hovered); in the panel it stays.
Rectangle {
    id: card

    required property var notification
    property bool popup: false
    // ms until the popup hides itself; 0 = never.
    property int timeout: 0

    signal expired
    signal activated
    signal closeClicked

    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property string iconSource: {
        const icon = notification ? notification.appIcon : "";
        if (icon === "")
            return "";
        return icon.startsWith("/") || icon.indexOf("://") >= 0 ? icon : Quickshell.iconPath(icon, true);
    }

    implicitHeight: content.implicitHeight + Theme.gap * 3
    color: Theme.surface
    radius: Theme.radius
    border.color: critical ? Theme.urgent : Theme.border
    border.width: Theme.borderWidth

    // A replaced notification (same id, new text) gets its full time again.
    // restart() only when running: the panel copy has no timer to start.
    function _rearm(): void {
        if (hideTimer.running)
            hideTimer.restart();
    }

    Connections {
        target: card.notification
        function onSummaryChanged() {
            card._rearm();
        }
        function onBodyChanged() {
            card._rearm();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: hideTimer

        interval: Math.max(card.timeout, 1)
        repeat: false
        running: card.popup && card.timeout > 0 && !hover.hovered
        onTriggered: card.expired()
    }

    HoverHandler {
        id: hover
    }

    // Below the content, so the close and action buttons take their own clicks.
    MouseArea {
        anchors.fill: parent
        onClicked: card.activated()
    }

    Column {
        id: content

        x: Theme.gap * 1.5
        y: Theme.gap * 1.5
        width: card.width - Theme.gap * 3
        spacing: Math.round(Theme.gap / 2)

        Item {
            width: parent.width
            height: Math.max(appName.implicitHeight, closeGlyph.implicitHeight)

            IconImage {
                id: appIcon

                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Theme.fontSize + 2
                source: card.iconSource
                visible: card.iconSource !== ""
            }

            Text {
                id: appName

                anchors.left: appIcon.visible ? appIcon.right : parent.left
                anchors.leftMargin: appIcon.visible ? Theme.gap : 0
                anchors.right: closeGlyph.left
                anchors.verticalCenter: parent.verticalCenter
                text: card.notification ? card.notification.appName : ""
                color: Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Glyph {
                id: closeGlyph

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\uf00d"
                color: closeArea.containsMouse ? Theme.foreground : Theme.muted
                font.pixelSize: Theme.fontSize

                MouseArea {
                    id: closeArea

                    anchors.fill: parent
                    anchors.margins: -Theme.gap / 2
                    hoverEnabled: true
                    onClicked: card.closeClicked()
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.gap

            Image {
                id: image

                width: visible ? Theme.fontSize * 3 : 0
                height: width
                source: card.notification ? card.notification.image : ""
                visible: source.toString() !== "" && status === Image.Ready
                sourceSize.width: Theme.fontSize * 3
                sourceSize.height: Theme.fontSize * 3
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Column {
                width: parent.width - (image.visible ? image.width + Theme.gap : 0)
                spacing: 2

                Text {
                    width: parent.width
                    text: card.notification ? card.notification.summary : ""
                    color: Theme.foreground
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: card.notification ? card.notification.body : ""
                    visible: text !== ""
                    color: Theme.foreground
                    elide: Text.ElideRight
                    maximumLineCount: card.popup ? 4 : 8
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.gap
            visible: actionRepeater.count > 0

            Repeater {
                id: actionRepeater

                // The "default" action is the card click itself.
                model: card.notification ? Array.from(card.notification.actions).filter(a => a.identifier !== "default") : []

                delegate: Rectangle {
                    id: actionButton

                    required property var modelData

                    implicitWidth: actionLabel.implicitWidth + Theme.gap * 2
                    implicitHeight: actionLabel.implicitHeight + Theme.gap
                    radius: Theme.radius
                    color: actionArea.containsMouse ? Theme.selection : Theme.surfaceAlt

                    Text {
                        id: actionLabel

                        anchors.centerIn: parent
                        text: actionButton.modelData.text
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: actionArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: actionButton.modelData.invoke()
                    }
                }
            }
        }
    }
}
