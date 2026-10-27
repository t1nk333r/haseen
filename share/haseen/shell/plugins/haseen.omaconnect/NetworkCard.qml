import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Network discovery in the haseen.omaconnect panel, collapsed until asked
// for: Tailscale peers (one `tailscale status --json` when it opens) and any
// literal address to add to the list KDE Connect tries beyond its own
// discovery, and the saved ones to remove. Adapted from OmaConnect's
// components/NetworkSection.qml (MIT, Copyright (c) 2026 OmaConnect
// contributors).
Column {
    id: card

    required property var service
    property bool open: false

    readonly property var ts: service.tailscale
    readonly property var peers: Model.filterPeers(ts ? ts.peers : [], query.text)
    readonly property color subtle: Theme.subtle(Theme.surface)

    spacing: Math.round(Theme.gap / 2)

    Pill {
        text: card.open ? I18n.tr("Hide network discovery") : I18n.tr("Network discovery…")
        onClicked: {
            card.open = !card.open;
            if (card.open)
                card.service.fetchTailscale();
        }
    }

    Column {
        width: card.width
        visible: card.open
        spacing: Math.round(Theme.gap / 2)

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: card.service.tailscaleLoading ? I18n.tr("Asking Tailscale…") : card.service.tailscaleMissing ? I18n.tr("Tailscale is not installed (optional).") : !card.ts ? I18n.tr("Tailscale is not connected.") : card.ts.running ? I18n.tr("Tailscale: this machine is %1. Add a peer that runs KDE Connect:", card.ts.self) : I18n.tr("Tailscale: %1", card.ts.backend)
            color: card.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }

        Field {
            id: query

            width: parent.width
            visible: card.ts !== null && card.ts.peers.length > 6
            placeholder: I18n.tr("Filter peers")
        }

        Repeater {
            model: card.peers

            delegate: Item {
                id: peer

                required property var modelData
                readonly property bool saved: card.service.addresses.indexOf(modelData.address) >= 0

                width: card.width
                height: Math.round(Theme.fontSize * 2.2)

                Text {
                    anchors.left: parent.left
                    anchors.right: add.left
                    anchors.rightMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: [peer.modelData.name, peer.modelData.address].concat(peer.modelData.online ? [] : [I18n.tr("offline")]).join(" · ")
                    color: peer.modelData.online ? Theme.foreground : card.subtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }

                Pill {
                    id: add

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: peer.saved ? I18n.tr("Saved") : I18n.tr("Add")
                    active: peer.saved
                    enabled: !peer.saved && card.service.addressesReady
                    onClicked: card.service.saveAddress(peer.modelData.address, false)
                }
            }
        }

        Row {
            width: card.width
            spacing: Math.round(Theme.gap / 2)

            Field {
                id: manual

                width: card.width - addManual.width - parent.spacing
                placeholder: I18n.tr("Another IPv4 or IPv6 address")
                onAccepted: {
                    if (card.service.saveAddress(text, false))
                        text = "";
                }
            }

            Pill {
                id: addManual

                text: I18n.tr("Add")
                enabled: card.service.addressesReady && manual.text.trim() !== ""
                onClicked: {
                    if (card.service.saveAddress(manual.text, false))
                        manual.text = "";
                }
            }
        }

        Flow {
            width: card.width
            visible: card.service.addresses.length > 0
            spacing: Math.round(Theme.gap / 2)

            Text {
                height: Math.round(Theme.fontSize * 2.1)
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr("Saved:")
                color: card.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }

            Repeater {
                model: card.service.addresses

                delegate: Pill {
                    required property var modelData

                    // A click removes it.
                    text: modelData + "  ×"
                    onClicked: card.service.saveAddress(modelData, true)
                }
            }
        }
    }
}
