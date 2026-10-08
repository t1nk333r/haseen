import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// UPower display device (D-Bus signals). implicitWidth 0 without a laptop
// battery, so the bar slot disappears entirely. A left click opens the
// haseen.battery panel (plan 076).
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery && device.isPresent
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && Model.isCharging(device.state)
    readonly property real low: typeof settings.low === "number" ? settings.low : 15

    visible: present
    implicitWidth: present ? contentWidth : 0

    glyph: Model.glyph(percent, charging)
    text: percent + "%"
    color: !charging && percent <= low ? Theme.urgent : Theme.barForeground

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
