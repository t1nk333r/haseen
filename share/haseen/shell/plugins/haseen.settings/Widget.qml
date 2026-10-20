// The bar entry of the owner's fork t1nk33r.settings 1.1.0 of
// AyushKr2003/shell-settings (MIT, Copyright (c) AyushKr2003); see LICENSE and
// UPSTREAM.md beside this file. haseen: BarButton opening the panel.
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    glyph: "\u{f0493}"
    color: Theme.barForeground

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
