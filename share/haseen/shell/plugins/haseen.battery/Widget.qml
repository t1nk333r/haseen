import QtQuick
import Quickshell.Services.UPower
import qs.Haseen
import qs.Haseen.Widgets

// UPower display device (D-Bus signals). implicitWidth 0 without a laptop
// battery, so the bar slot disappears entirely.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery && device.isPresent
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge)
    readonly property real low: typeof settings.low === "number" ? settings.low : 15

    visible: present
    implicitWidth: present ? contentWidth : 0

    glyph: charging ? "\u{F0084}" : ["\u{F008E}", "\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"][Math.max(0, Math.min(10, Math.round(percent / 10)))]
    text: percent + "%"
    color: !charging && percent <= low ? Theme.urgent : Theme.barForeground
}
