import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// The weather pill, as Omarchy's weather bar widget (shell/plugins/panels/
// weather/BarWidget.qml; MIT, Copyright (c) David Heinemeier Hansson): the
// condition icon from the haseen.weather service (role `weather`) and the
// temperature beside it (settings.temperature, on by default since plan
// 180), hidden until there is an icon. Left click opens the forecast panel, right click sends
// the status line as a notification, middle click refreshes.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // A test may hand the pill a service of its own.
    property var service: {
        const entry = Plugins.roles.weather;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }

    glyph: service ? service.label : ""
    text: settings.temperature !== false && service && service.reportTempNum !== "" ? service.reportTempNum + "°" : ""
    color: Theme.barForeground
    visible: glyph !== ""
    implicitWidth: visible ? contentWidth : 0

    onClicked: button => {
        if (button === Qt.RightButton)
            root.service.notifyStatus();
        else if (button === Qt.MiddleButton)
            root.service.refresh();
        else
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
