import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// The omARR bar cell: the server glyph and a badge from the haseen.omarr
// service (role `omarr`). The badge is the unread event count, else the
// services down or downloads running; it is hidden at zero. The glyph is
// muted while no service is configured and urgent while one is down. Left
// click toggles the panel, middle click polls every service now.
//
// Adapted from BarWidget.qml in omARR (MIT, Copyright (c) 2026 luccast), as
// the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: a BarButton; the panel is haseen's PanelPopup,
// opened over IPC, so no panel loader, host injection or relayout reopen.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.omarr;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property int badgeCount: service ? Number(service.badgeCount || 0) : 0
    readonly property int unreadCount: service ? Number(service.unreadCount || 0) : 0

    glyph: "\u{f048d}"
    text: unreadCount > 0 ? String(unreadCount) : badgeCount > 0 ? String(badgeCount) : ""
    color: !service || !service.configured ? Theme.muted : service.badgeUrgent ? Theme.urgent : Theme.barForeground
    visible: service !== null
    implicitWidth: visible ? contentWidth : 0

    onClicked: button => {
        if (button === Qt.MiddleButton)
            root.service.forcePoll();
        else if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
