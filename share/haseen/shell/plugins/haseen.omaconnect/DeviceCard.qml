import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The device part of the haseen.omaconnect panel: a switcher when there is
// more than one device, the selected one's glyph, name, state, battery and
// signal, and its pairing: a request from it (with the verification key to
// compare), Pair, or Unpair. Adapted from OmaConnect's
// components/DeviceSection.qml (MIT, Copyright (c) 2026 OmaConnect
// contributors).
Column {
    id: card

    required property var service
    property var settings: ({})

    readonly property var device: service.selected
    readonly property string pending: device ? service.pairing[device.id] || "" : ""
    readonly property color subtle: Theme.subtle(Theme.surface)

    spacing: Theme.gap

    Flow {
        width: card.width
        visible: card.service.devices.length > 1
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: card.service.devices

            delegate: Pill {
                required property var modelData

                text: modelData.name
                active: modelData.id === card.service.selectedId
                onClicked: card.service.select(modelData.id)
            }
        }
    }

    Item {
        width: card.width
        height: Math.round(Theme.fontSize * 2.6)
        visible: card.device !== null

        Glyph {
            id: glyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2.2
            glyph: card.device ? (card.settings.showDeviceTypeIcons !== false ? Model.deviceGlyph(card.device.type) : Model.deviceGlyph("phone")) : ""
            color: Model.canAct(card.device) ? Theme.accent : Theme.foreground
            font.pixelSize: Theme.fontSize + 6
        }

        Column {
            anchors.left: glyph.right
            anchors.leftMargin: Theme.gap
            anchors.right: battery.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: card.device ? card.device.name : ""
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: {
                    const extra = Model.details(card.device, card.settings.showBatteryStats, card.settings.showNetworkStats);
                    return Model.status(card.device) + (extra ? " · " + extra : "");
                }
                color: card.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }

        Glyph {
            id: battery

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: card.settings.showBatteryStats !== false && Model.canAct(card.device) && card.device.battery >= 0
            glyph: Model.batteryGlyph(card.device)
        }
    }

    // A request from the device: compare the key on both screens first.
    Column {
        width: card.width
        visible: card.device !== null && card.device.pairRequestedByPeer
        spacing: Math.round(Theme.gap / 2)

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: card.device ? card.device.name + " wants to pair. Accept only if the device shows the same key: " + Model.formatKey(card.device.verificationKey) : ""
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Row {
            spacing: Math.round(Theme.gap / 2)

            Pill {
                text: "Accept"
                active: true
                busy: card.service.busy
                onClicked: card.service.answer(card.device.id, true)
            }

            Pill {
                text: "Reject"
                busy: card.service.busy
                onClicked: card.service.answer(card.device.id, false)
            }
        }
    }

    Row {
        visible: card.device !== null && !card.device.pairRequestedByPeer
        spacing: Math.round(Theme.gap / 2)

        Pill {
            visible: card.device !== null && !card.device.paired
            text: card.pending === "requesting" ? "Waiting for the device…" : "Pair"
            pending: card.pending === "requesting"
            busy: card.service.busy || card.pending !== "" || (card.device !== null && !card.device.reachable)
            onClicked: card.service.pair()
        }

        Text {
            visible: card.device !== null && !card.device.paired && card.device.pairRequested && card.device.verificationKey !== ""
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: card.device ? "Key " + Model.formatKey(card.device.verificationKey) : ""
            color: card.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
