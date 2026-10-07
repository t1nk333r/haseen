import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// haseen.logo: the selected mark (Branding, `haseen branding mark`) as a bar
// cell; a left click toggles the menu (top level unless settings.menu names a
// path), as Omarchy's bar logo does. On by default, first in bar.left (plan
// 070, owner-approved).
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
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "menu", "toggle", menuPath]);
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
