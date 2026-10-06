import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// Touchpad gestures in the bar. Listed in the default bar.right, but takes no
// room until the `gestures` flag exists: the hardware quirk sets it on a
// machine with a touchpad, so a desktop never shows it and the user's
// shell.json is never rewritten to switch it on. Left click opens the panel;
// right click turns every gesture off and on, as in omagesture's bar button
// (github.com/heroesofcode/omagesture, MIT, Copyright (c) 2026 Pedro Henrique).
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool on: settings.enabled !== false

    visible: Flags.gestures
    implicitWidth: Flags.gestures ? contentWidth : 0
    glyph: "\u{F0821}"
    color: on ? Theme.barForeground : Theme.muted

    GestureSettings {
        id: store
        pluginId: root.pluginId
    }

    onClicked: button => {
        if (button === Qt.RightButton) {
            store.save({
                enabled: !root.on
            });
            return;
        }
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
