import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// haseen.monitor-settings bar widget (plan 098): a monitor glyph and nothing
// else, so it costs no polling. Left click opens the monitor panel, right
// click the brightness panel (haseen.display), and the wheel steps the
// backlight through `haseen brightness` (haseen.osd shows the level).
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"

    glyph: "\u{F0379}"
    color: Theme.barForeground

    function toggle(id: string): void {
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", id]);
    }

    onClicked: button => root.toggle(button === Qt.RightButton ? "haseen.display" : root.pluginId)
    onScrolled: steps => Quickshell.execDetached([root.binDir + "/haseen-brightness", steps > 0 ? "up" : "down"])
}
