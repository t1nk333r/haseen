import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The quick actions of the haseen.omaconnect panel, each shown only when the
// device has its KDE Connect plugin and the setting keeps it: ring, send the
// clipboard, a file, SMS, ping and text. Text and ping take the field below
// (an empty ping carries settings.defaultPingMessage). Adapted from
// OmaConnect's components/ActionToolbar.qml and ComposerSection.qml (MIT,
// Copyright (c) 2026 OmaConnect contributors).
Column {
    id: bar

    required property var service
    property var settings: ({})

    readonly property var device: service.selected
    readonly property var caps: device ? device.caps : ({})
    readonly property bool live: Model.canAct(device)

    spacing: Theme.gap

    Flow {
        width: bar.width
        spacing: Math.round(Theme.gap / 2)

        Pill {
            visible: bar.settings.showActionRing !== false && bar.caps.ring === true
            text: "Ring"
            busy: bar.service.busy
            enabled: bar.live
            onClicked: bar.service.ring()
        }

        Pill {
            visible: bar.settings.showActionClipboard !== false && bar.caps.clipboard === true
            text: "Send clipboard"
            busy: bar.service.busy
            enabled: bar.live
            onClicked: bar.service.sendClipboard()
        }

        Pill {
            visible: bar.settings.showActionFile !== false && bar.caps.file === true
            text: "Send file…"
            busy: bar.service.busy
            enabled: bar.live
            onClicked: bar.service.pickFile()
        }

        Pill {
            visible: bar.settings.showActionSms !== false && bar.caps.sms === true
            text: "SMS"
            enabled: bar.live
            onClicked: bar.service.openSms()
        }
    }

    Row {
        width: bar.width
        visible: (bar.settings.showActionText !== false && bar.caps.text === true) || (bar.settings.showActionPing === true && bar.caps.ping === true)
        spacing: Math.round(Theme.gap / 2)

        Field {
            id: draft

            width: bar.width - (sendText.visible ? sendText.width + parent.spacing : 0) - (sendPing.visible ? sendPing.width + parent.spacing : 0)
            enabled: bar.live
            placeholder: "Text or a link to send"
            onAccepted: {
                if (sendText.visible && bar.service.shareText(text))
                    text = "";
            }
        }

        Pill {
            id: sendText

            visible: bar.settings.showActionText !== false && bar.caps.text === true
            text: "Send"
            busy: bar.service.busy
            enabled: bar.live && draft.text.trim() !== ""
            onClicked: {
                if (bar.service.shareText(draft.text))
                    draft.text = "";
            }
        }

        Pill {
            id: sendPing

            visible: bar.settings.showActionPing === true && bar.caps.ping === true
            text: "Ping"
            busy: bar.service.busy
            enabled: bar.live
            onClicked: {
                if (bar.service.ping(draft.text))
                    draft.text = "";
            }
        }
    }
}
