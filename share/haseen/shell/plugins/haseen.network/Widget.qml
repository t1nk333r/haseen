// Adapted from Omarchy shell/plugins/panels/network/Panel.qml (the bar
// button). MIT, Copyright (c) David Heinemeier Hansson.
// haseen: BarButton, optional name, limited-connectivity colour.
import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// NetworkManager over D-Bus via Quickshell.Networking: property change
// signals only, no polling and no scanning (the panel scans while open).
// Wired wins when both are up. Left click opens the haseen.network panel.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi && d.connected) || null
    readonly property var wifiNetwork: wifi ? wifi.networks.values.find(n => n.connected) || null : null
    readonly property string kind: Model.connectionKind(wired !== null, wifi !== null)
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Limited || Networking.connectivity === NetworkConnectivity.Portal

    glyph: Model.connectionIcon(kind, wifiNetwork ? Math.round(wifiNetwork.signalStrength * 100) : -1)
    text: settings.showName === true ? (wired ? wired.name : wifiNetwork ? wifiNetwork.name : "") : ""
    color: kind === "disconnected" ? Theme.muted : limited ? Theme.warning : Theme.barForeground

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
