// Adapted from BarWidget.qml (the bar entry) of K53N0/omarchy-browser-picker
// (MIT, Copyright (c) 2026 K53N0), via the owner's fork
// t1nk33r.browser-picker; see LICENSE and UPSTREAM.md beside this file.
// haseen: BarButton; the popup is the haseen.browser-picker panel.
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// Left click opens the panel (default-browser switch, settings, rules);
// middle click asks for a browser to open, with no link.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    glyph: "\u{f059f}"
    color: Theme.barForeground

    onClicked: button => {
        if (button === Qt.MiddleButton)
            Apps.launch([Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen-browser-picker"]);
        else if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
