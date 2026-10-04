import QtQuick
import Quickshell.Networking
import qs.Haseen
import qs.Haseen.Widgets

// NetworkManager over D-Bus via Quickshell.Networking: property change
// signals only, no polling and no scanning (scannerEnabled stays off).
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
    readonly property real strength: wifiNetwork ? wifiNetwork.signalStrength : 0
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Limited || Networking.connectivity === NetworkConnectivity.Portal

    glyph: wired ? "\u{F0200}" : wifi ? ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"][Math.min(4, Math.ceil(strength * 4))] : "\u{F092E}"
    text: settings.showName === true ? (wired ? wired.name : wifiNetwork ? wifiNetwork.name : "") : ""
    color: !wired && !wifi ? Theme.muted : limited ? Theme.warning : Theme.foreground
}
