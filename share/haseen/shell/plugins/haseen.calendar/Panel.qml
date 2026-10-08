import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Calendar.js" as Cal
import "Moon.js" as Moon

// Month calendar. A click on the clock opens it (or `haseen shell ipc panel
// toggle haseen.calendar`). Arrows or the wheel change month, Page Up/Down
// too; a click on the title returns to today. Week start follows the locale
// unless settings.weekStart names a day; ISO week numbers on the left.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var locale: Qt.locale()
    readonly property date today: clock.date
    property int year: today.getFullYear()
    property int month: today.getMonth()
    readonly property int first: Cal.weekStart(settings.weekStart, locale.firstDayOfWeek)
    readonly property bool weekNumbers: settings.weekNumbers !== false
    readonly property var cells: Cal.monthGrid(year, month, first)
    readonly property var weeks: Cal.rowWeeks(cells)
    readonly property int cell: Math.round(Theme.fontSize * 2.2)
    readonly property var clockSettings: Plugins.settingsFor("haseen.clock")
    readonly property string clockFormat: {
        const key = Config.barVertical ? "verticalFormat" : "format";
        const fallback = Config.barVertical ? "HH\nmm" : "HH:mm";
        return typeof clockSettings[key] === "string" && clockSettings[key] !== "" ? clockSettings[key] : fallback;
    }
    readonly property bool dayNameShown: ClockDayName.isShown(clockFormat, clockSettings.showDayName)

    ClockSettings {
        id: clockSettingsWriter
    }

    function shift(delta: int): void {
        const m = Cal.shiftMonth(year, month, delta);
        year = m.year;
        month = m.month;
    }

    function goToday(): void {
        year = today.getFullYear();
        month = today.getMonth();
    }

    spacing: Theme.gap
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Left)
            root.shift(-1);
        else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Right)
            root.shift(1);
        else if (event.key === Qt.Key_Home)
            root.goToday();
        else
            return;
        event.accepted = true;
    }

    // The today marker moves at midnight; hourly ticks are enough.
    SystemClock {
        id: clock
        enabled: root.visible
        precision: SystemClock.Hours
    }

    component NavButton: Text {
        signal activated

        color: navMouse.containsMouse ? Theme.accent : Theme.foreground
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSize + 2
        width: root.cell
        horizontalAlignment: Text.AlignHCenter

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.activated()
        }
    }

    Item {
        width: body.width
        height: title.implicitHeight

        NavButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf053"
            onActivated: root.shift(-1)
        }

        Text {
            id: title
            anchors.centerIn: parent
            text: root.locale.standaloneMonthName(root.month, Locale.LongFormat) + " " + root.year
            color: titleMouse.containsMouse ? Theme.accent : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true

            MouseArea {
                id: titleMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.goToday()
            }
        }

        NavButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf054"
            onActivated: root.shift(1)
        }
    }

    // Tonight's moon, from the owner's old waybar clock tooltip. Follows the
    // hourly clock above, so it is current whenever the panel is open.
    Column {
        width: body.width
        visible: root.settings.moon !== false

        readonly property var moon: Moon.lines(root.today.getTime())

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: parent.moon.title
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: parent.moon.detail
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Row {
        id: body

        // ISO week numbers: blank corner, then one per row.
        Column {
            visible: root.weekNumbers

            Item {
                width: root.cell
                height: root.cell
            }

            Repeater {
                model: root.weeks

                delegate: Text {
                    required property int modelData

                    width: root.cell
                    height: root.cell
                    text: modelData
                    color: Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: Cal.weekdayOrder(root.first)

                delegate: Text {
                    required property int modelData

                    width: root.cell
                    height: root.cell
                    text: root.locale.dayName(modelData, Locale.ShortFormat).slice(0, 2)
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Repeater {
                model: root.cells

                delegate: Item {
                    id: slot

                    required property var modelData
                    readonly property bool isToday: Cal.sameDay(modelData, root.today)

                    width: root.cell
                    height: root.cell

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.cell - 4
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        visible: slot.isToday
                    }

                    Text {
                        anchors.fill: parent
                        text: slot.modelData.day
                        color: slot.isToday ? Theme.accentFg : slot.modelData.inMonth ? Theme.foreground : Theme.muted
                        opacity: slot.modelData.inMonth ? 1 : 0.6
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: slot.isToday
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    WheelHandler {
        onWheel: event => {
            const steps = Math.round(event.angleDelta.y / 120);
            if (steps !== 0)
                root.shift(-steps);
        }
    }

    Row {
        id: dayNameRow

        width: body.implicitWidth
        spacing: Theme.gap

        Text {
            width: Math.max(0, dayNameRow.width - dayNameToggle.implicitWidth - dayNameRow.spacing)
            text: "Day name"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            verticalAlignment: Text.AlignVCenter
        }

        Pill {
            id: dayNameToggle

            objectName: "clockDayNameToggle"
            text: root.dayNameShown ? "On" : "Off"
            activeFocusOnTab: true
            active: root.dayNameShown
            onClicked: clockSettingsWriter.setDayName(!root.dayNameShown)
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                    return;
                dayNameToggle.clicked();
                event.accepted = true;
            }
        }
    }

    // Test hook (settings.debugIpc): change and read the shown month without
    // a keyboard or pointer.
    IpcHandler {
        target: "haseen.calendar"
        enabled: root.settings.debugIpc === true

        function shift(delta: int): void {
            root.shift(delta);
        }

        function today(): void {
            root.goToday();
        }

        function shown(): string {
            const c = root.cells;
            return root.year + "-" + String(root.month + 1).padStart(2, "0") + " first=" + root.first + " cells=" + c[0].day + ".." + c[41].day + " weeks=" + root.weeks.join(",");
        }
    }
}
