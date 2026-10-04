import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// SystemClock ticks on the minute boundary (or the second, only when the
// format shows seconds), and only while the bar is visible.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string format: typeof settings.format === "string" && settings.format !== "" ? settings.format : "HH:mm"

    text: Qt.formatDateTime(clock.date, format)

    SystemClock {
        id: clock
        enabled: root.visible
        precision: /s/.test(root.format.replace(/'[^']*'/g, "")) ? SystemClock.Seconds : SystemClock.Minutes
    }
}
