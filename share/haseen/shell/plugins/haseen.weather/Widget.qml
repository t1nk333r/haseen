import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// Current temperature and a condition glyph from the haseen.weather service
// (role `weather`). Takes no room until the service has a good answer, so an
// offline machine or a disabled service shows nothing. Click opens the
// 3-day forecast panel.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.weather;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var current: service && service.forecast ? service.forecast.current : null

    glyph: current ? current.glyph : ""
    text: current ? current.temp + "°" : ""
    color: Theme.barForeground
    implicitWidth: current ? contentWidth : 0

    onClicked: Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId])
}
