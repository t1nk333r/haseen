pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// qs.Services.DMSNetworkService for DankMaterialShell plugins (architecture
// 5.4): the read-only connection state DMS widgets show, from Quickshell's
// NetworkManager binding (the same source as haseen.network), driven by its
// D-Bus signals. Names follow DankMaterialShell's
// quickshell/Services/DMSNetworkService.qml (MIT, Copyright (c) 2025 Avenge
// Media LLC). Nothing here connects, disconnects or changes a setting: DMS's
// control functions are not provided.
Singleton {
    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wiredDevice: devices.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi && d.connected) || null
    readonly property var wifiNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiAvailable: Networking.wifiHardwareEnabled
    readonly property string networkStatus: wiredDevice ? "ethernet" : (wifiNetwork ? "wifi" : "disconnected")
    readonly property string currentWifiSSID: wifiNetwork ? wifiNetwork.name : ""
    readonly property int wifiSignalStrength: wifiNetwork ? Math.round(wifiNetwork.signalStrength * 100) : 0
    readonly property bool ethernetConnected: wiredDevice !== null
}
