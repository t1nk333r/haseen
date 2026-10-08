import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// The active keyboard layout as a short code (plan 080): EN, AR, … from the
// Keyboard singleton, which reads `hyprctl -j devices` once and then follows
// Hyprland's `activelayout` event. With one layout it takes no room, so it
// can sit in bar.right on any machine. A left click runs
// `hyprctl switchxkblayout main next`; with more than two layouts a right
// click opens the list (the panel). Off by default.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool multi: Keyboard.layouts.length > 1

    visible: multi
    implicitWidth: multi ? contentWidth : 0
    // The list's code for the active layout (Keyboard.code), so the bar and
    // the list never show two codes for one layout.
    text: Keyboard.code

    onClicked: button => {
        if (button === Qt.LeftButton)
            Keyboard.next();
        else if (button === Qt.RightButton && Keyboard.layouts.length > 2)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
