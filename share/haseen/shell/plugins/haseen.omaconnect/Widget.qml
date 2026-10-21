import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.omaconnect bar widget (plan 098): the selected device's glyph from
// the haseen.omaconnect service (role `kdeconnect`), dimmed while no paired
// device is reachable and accented while one asks to pair; with
// showBarBattery its battery percentage. Click opens the panel. Takes no room
// until the service runs (it must be listed in `services`). Adapted from
// OmaConnect's BarWidget.qml (MIT, Copyright (c) 2026 OmaConnect
// contributors).
BarButton {
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
    readonly property bool live: Model.canAct(device)

    glyph: settings.showDeviceTypeIcons !== false && device ? Model.deviceGlyph(device.type) : Model.deviceGlyph("phone")
    text: settings.showBarBattery === true && live && device.battery >= 0 ? device.battery + "%" : ""
    color: service && service.incoming ? Theme.accent : live ? Theme.barForeground : Theme.muted
    implicitWidth: service ? contentWidth : 0

    onClicked: Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId])
}
