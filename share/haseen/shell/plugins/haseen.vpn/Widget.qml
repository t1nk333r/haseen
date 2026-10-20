// Adapted from Panel.qml (the bar button) of the owner's fork t1nk33r.vpn
// 1.4.1-t1nk33r.1 of jkoestinger/omarchy-vpn (MIT, Copyright (c) 2026 Justin
// Köstinger); see LICENSE and UPSTREAM.md beside this file.
// haseen: BarButton reading the haseen.vpn service (role `vpn`).
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "model/Shared.js" as Shared

// The shield is bright while a tunnel is up and muted otherwise. Left click
// opens the panel, right click connects or disconnects the shown tool, middle
// click reads every tool and the exit address again.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.vpn;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }

    glyph: Shared.GLYPH_VPN
    color: service && service.anyConnected ? Theme.barForeground : Theme.muted

    onClicked: button => {
        if (button === Qt.RightButton && service)
            service.toggleActive();
        else if (button === Qt.MiddleButton && service) {
            service.refreshAll(true);
            service.refreshPublicIp();
        } else if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
