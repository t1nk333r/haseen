import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// SystemClock ticks on the minute boundary (or the second, only when the
// format shows seconds), and only while the bar is visible. A left click
// toggles the calendar panel (settings.calendar, default haseen.calendar).
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string format: {
        const key = vertical ? "verticalFormat" : "format";
        const fallback = vertical ? "HH\nmm" : "HH:mm";
        const source = typeof settings[key] === "string" && settings[key] !== "" ? settings[key] : fallback;
        return ClockDayName.effectiveFormat(source, ClockSettings.effectiveSetting(settings.showDayName), vertical);
    }
    readonly property string calendar: typeof settings.calendar === "string" ? settings.calendar : "haseen.calendar"

    text: Qt.formatDateTime(clock.date, format)

    onClicked: button => {
        if (button === Qt.LeftButton && calendar !== "")
            Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "panel", "toggle", calendar]);
    }

    SystemClock {
        id: clock
        enabled: root.visible
        precision: /s/.test(root.format.replace(/'[^']*'/g, "")) ? SystemClock.Seconds : SystemClock.Minutes
    }
}
