import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// The Todoist mark in the bar, with the task count beside it when the bar
// count is on (the panel's Settings). Dimmed and without a count while no
// token is set or the API rejected it. Left click toggles the panel, middle
// click refreshes. State comes from the haseen.todoist service (role
// `todoist`); hidden until it runs.
//
// Adapted from BarWidget.qml and TodoistIcon.qml in omarchy-todoist (MIT,
// Copyright (c) 2026 aryan-techie), as the owner's fork t1nk33r.todoist
// 1.14.0; see LICENSE and UPSTREAM.md beside this file. haseen changes: a
// BarButton on Theme tokens, the state read from the service.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.todoist;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool connected: !!service && service.hasToken && !service.tokenInvalid

    // md-format_list_checks, as upstream's mark.
    glyph: service ? "\u{f0756}" : ""
    text: connected && service.barCountMode !== "hide" ? String(service.barCountValue) + (service.barCountTruncated ? "+" : "") : ""
    color: Theme.barForeground
    opacity: connected ? 1 : 0.6
    visible: service !== null
    implicitWidth: visible ? contentWidth : 0

    onClicked: button => {
        if (button === Qt.MiddleButton)
            root.service.refresh();
        else
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
