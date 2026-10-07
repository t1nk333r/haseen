import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// haseen.logo: the selected mark (Branding, `haseen branding mark`) as a bar
// cell; a left click toggles the menu, as Omarchy's bar logo does. Off by
// default and in no default bar section (plan 059, no visual clutter): the
// menu is already on a key, so this is for people who want a click target.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string menuPath: typeof settings.menu === "string" ? settings.menu : ""

    implicitWidth: mark.width + padding * 2
    implicitHeight: vertical ? mark.height + padding * 2 : (parent ? parent.height : Theme.fontSize * 2)

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "menu", "toggle", menuPath]);
    }

    BrandImage {
        id: mark

        anchors.centerIn: parent
        // The 16 px grid drawing stays crisp at whole multiples of 16.
        height: 16 * Math.max(1, Math.round((Theme.fontSize + 2) / 16))
        path: Branding.symbolicPath
        // barForeground: readable on a transparent bar too.
        color: root.color
    }
}
