import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.omaconnect panel (plan 098), ported from jitendradara12's
// OmaConnect, Panel.qml (MIT, Copyright (c) 2026 OmaConnect contributors):
// the selected device and its pairing, quick actions, the phone's media
// player, remote commands and network discovery, and the setup helpers while
// nothing is reachable. Everything it shows and does belongs to the
// haseen.omaconnect service (role `kdeconnect`); opening the panel asks it for
// a fresh scan and the phone's player. haseen changes: native haseen widgets
// instead of Omarchy's Ui module; no keyboard cursor (haseen panels take the pointer);
// the dependency installer is `haseen setup kdeconnect`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    property var service: {
        const entry = Plugins.roles.kdeconnect;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var device: service ? service.selected : null
    readonly property color subtle: Theme.subtle(Theme.surface)

    width: Theme.fontSize * 28
    spacing: Theme.gap

    Component.onCompleted: {
        if (service) {
            service.panelsOpen += 1;
            service.refresh(false);
            service.fetchMedia();
        }
    }
    Component.onDestruction: {
        if (service)
            service.panelsOpen = Math.max(0, service.panelsOpen - 1);
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "KDE Connect"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Pill {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.service !== null
            text: root.service && root.service.scanning ? "Looking…" : "Refresh"
            // Not busy while a scan runs: the daemon's signals rescan often,
            // and a button that dims every time reads as broken.
            onClicked: root.service.refresh(true)
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: {
            if (!root.service)
                return "The haseen.omaconnect service is not running: list it in the shell's services.";
            switch (root.service.discovery) {
            case "starting":
                return "Asking KDE Connect…";
            case "missing":
                return "KDE Connect is not installed: haseen setup kdeconnect on";
            case "unavailable":
                return "The KDE Connect daemon is not answering.";
            }
            return root.service.devices.length === 0 ? "No devices yet. Open KDE Connect on the phone, on the same network or Tailscale." : "";
        }
        color: root.subtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    DeviceCard {
        width: parent.width
        visible: root.service !== null && root.device !== null
        service: root.service
        settings: root.settings
    }

    ActionBar {
        width: parent.width
        visible: root.service !== null && Model.canAct(root.device)
        service: root.service
        settings: root.settings
    }

    MediaCard {
        width: parent.width
        visible: root.service !== null && root.settings.showMediaPlayer !== false && Model.canAct(root.device) && root.device.caps.media && Model.hasMedia(root.service.media)
        service: root.service
    }

    CommandsCard {
        width: parent.width
        visible: root.service !== null && root.settings.showRemoteCommands !== false && Model.canAct(root.device) && root.device.caps.commands
        service: root.service
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.service ? (root.service.error || root.service.message) : ""
        color: root.service && root.service.error ? Theme.urgent : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    NetworkCard {
        width: parent.width
        visible: root.service !== null && root.settings.showTailscale !== false && root.service.discovery === "ready"
        service: root.service
    }

    // While nothing is reachable: the two things that usually stand in the
    // way, the firewall (ports 1714-1764) and the phone-side app.
    Flow {
        width: parent.width
        visible: root.service !== null && root.settings.showTroubleshooting !== false && root.service.discovery === "ready" && root.service.reachable.length === 0
        spacing: Math.round(Theme.gap / 2)

        Pill {
            text: "Open the firewall…"
            onClicked: root.service.setupFirewall()
        }

        Pill {
            text: "KDE Connect app"
            onClicked: root.service.openApp()
        }
    }
}
