import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "NightlightLogic.js" as Logic

// haseen.nightlight: follows the `nightlight` flag (`haseen toggle
// nightlight`, IPC `nightlight on|off|toggle`) with hyprsunset.
//
// On: if a hyprsunset already answers `hyprctl hyprsunset` (started by the
// user or another desktop), it is set to the temperature and set back to
// identity when the light goes off; otherwise this service runs its own
// `hyprsunset -t <K>` child and stops it again, which restores the colours.
// The flag is the single state, so the bar, the menu and the CLI agree.
//
// Schedule (settings.sunset/sunrise, fixed times, no geolocation): at start
// and at each crossing the flag is set to what the schedule says; a manual
// toggle holds until the next crossing. A crossing is noticed by a 60 s
// check that runs only while a schedule is configured. A single timer for
// the next crossing would oversleep a suspend (Qt timers are monotonic).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool active: Flags.nightlight
    readonly property int temperature: Logic.temperature(settings.temperature)
    readonly property bool hasSchedule: Logic.scheduled(0, settings.sunset, settings.sunrise) !== null

    // "own": our hyprsunset child; "external": someone else's; "": none.
    property string mode: ""
    property var _lastScheduled: null
    property bool _restart: false

    function apply(): void {
        if (active) {
            if (mode === "")
                probe.running = true;
            else
                Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(temperature)]);
            return;
        }
        if (mode === "own")
            sunset.running = false;
        else if (mode === "external")
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        mode = "";
    }

    // Restart our hyprsunset from the current settings (`haseen refresh
    // nightlight`); re-applies the temperature to an external one.
    function refresh(): void {
        if (!active)
            return;
        if (mode === "own" && sunset.running) {
            _restart = true;
            sunset.running = false;
            return;
        }
        apply();
    }

    function checkSchedule(initial: bool): void {
        const d = new Date();
        const s = Logic.scheduled(d.getHours() * 60 + d.getMinutes(), settings.sunset, settings.sunrise);
        if (s === null) {
            _lastScheduled = null;
            return;
        }
        // The present context pauses the night light (plan 062): a crossing
        // during it waits, and lands at the first check after it ends.
        if (Flags.context === "present")
            return;
        if (initial || s !== _lastScheduled) {
            _lastScheduled = s;
            Flags.set("nightlight", s);
        }
    }

    function statusJson(): string {
        return JSON.stringify({
            enabled: active,
            temperature: temperature,
            mode: mode,
            schedule: hasSchedule ? {
                sunset: settings.sunset,
                sunrise: settings.sunrise
            } : null
        });
    }

    onActiveChanged: apply()
    onTemperatureChanged: {
        if (active && mode !== "")
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(temperature)]);
    }
    onHasScheduleChanged: checkSchedule(true)
    Component.onCompleted: {
        checkSchedule(true);
        if (active)
            apply();
    }

    // Is a hyprsunset already listening? Exit 0 means it took the value.
    Process {
        id: probe

        command: ["hyprctl", "hyprsunset", "temperature", String(root.temperature)]
        onExited: code => {
            if (!root.active)
                return;
            if (code === 0) {
                root.mode = "external";
            } else {
                root.mode = "own";
                sunset.running = true;
            }
        }
    }

    Process {
        id: sunset

        command: ["hyprsunset", "-t", String(root.temperature)]
        onExited: code => {
            if (root._restart && root.active) {
                root._restart = false;
                running = true;
                return;
            }
            root._restart = false;
            if (root.active && root.mode === "own") {
                Plugins.warnOnce(root.pluginId + ":exit", "haseen.nightlight: hyprsunset exited (" + code + "); the night light is off until toggled again");
                root.mode = "";
            }
        }
    }

    // Schedule check; runs only while a schedule is configured.
    // haseen:sample
    Timer {
        interval: 60000
        repeat: true
        running: root.hasSchedule
        onTriggered: root.checkSchedule(false)
    }

    IpcHandler {
        target: "nightlight"

        function on(): void {
            Flags.set("nightlight", true);
        }

        function off(): void {
            Flags.set("nightlight", false);
        }

        function toggle(): void {
            Flags.set("nightlight", !root.active);
        }

        function refresh(): void {
            root.refresh();
        }

        function status(): string {
            return root.statusJson();
        }
    }
}
