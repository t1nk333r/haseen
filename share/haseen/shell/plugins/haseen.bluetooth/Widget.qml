import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Haseen
import qs.Haseen.Widgets

// Bluetooth state from BlueZ over D-Bus (Quickshell.Bluetooth): property
// change signals only, no polling. Takes no room without an adapter. Click
// opens the haseen.bluetooth panel.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []

    glyph: !on ? "\u{F00B2}" : connected.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
    text: settings.showName === true && connected.length > 0 ? (connected[0].name || connected[0].deviceName) : ""
    color: on ? Theme.barForeground : Theme.muted
    implicitWidth: adapter ? contentWidth : 0

    // Left click opens the panel; right click toggles power (the owner's
    // tailscale widget convention).
    onClicked: button => {
        if (button === Qt.RightButton) {
            if (adapter)
                adapter.enabled = !adapter.enabled;
            return;
        }
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
