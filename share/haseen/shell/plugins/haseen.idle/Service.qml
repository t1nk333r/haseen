import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Haseen
import "IdleLogic.js" as Logic

// haseen.idle: up to four ext-idle-notify monitors, so the compositor does
// the counting and the shell holds no timer.
//   screensaverAfter: start the `screensaver` role (haseen.screensaver);
//                     input dismisses it again.
//   lockAfter:        call the `lock` role (haseen.lock or any provider).
//   dpmsAfter:        turn the displays off, back on at the next input.
//   suspendAfter:     `haseen system suspend`, the menu's System > Suspend
//                     (0 = never, the default; plan 082).
// With respectInhibitors, an idle inhibitor (mpv, a browser playing video)
// keeps the monitors from firing; the suspend monitor honours inhibitors
// even when respectInhibitors is false. The `idle-off` flag (`haseen toggle
// idle`, Stay Awake, the game and present contexts) removes every monitor;
// `screensaver-off` removes only the screensaver one. settings.onBattery
// ({ screensaverAfter, lockAfter, dpmsAfter, suspendAfter }) replaces those
// values while UPower reports onBattery, an event-driven D-Bus property:
// plugging in or out recreates only the monitors whose timeout changed.
// The decisions live in IdleLogic.js (unit-tested).
//
// Each monitor is its own object, created with its final timeout and
// destroyed when that changes, never reconfigured in place. Quickshell
// 0.3.1's IdleMonitor deletes and recreates its notification on every
// parameter change; the allocator hands the new one the same address, the
// isIdle binding sees an unchanged pointer, and the monitor never reports
// idle again (observed in plan 019's smoke).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool respectInhibitors: settings.respectInhibitors !== false
    readonly property bool haveScreensaver: Plugins.roles.screensaver !== undefined
    readonly property var timeouts: Logic.timeouts(settings, {
        idleOff: Flags.idleOff,
        screensaverOff: Flags.screensaverOff,
        onBattery: UPower.onBattery
    }, haveScreensaver)
    // DPMS bookkeeping: true only from the moment the dpms monitor turned the
    // displays off until it turned them back on. Input after idle sends
    // dpms.on only when this is set, so displays someone else turned off
    // are left alone; a monitor removed while idle (Stay Awake, a timeout
    // change, a plug event) turns them on through its destruction hook.
    property bool _dpmsOff: false
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    // Suspends requested this session, for the debug hook.
    property int _suspends: 0
    // name -> isIdle of the live monitors, for the debug hook.
    property var _idle: ({})
    readonly property bool screensaverStartedThisCycle: _idle.screensaver === true

    function _dpms(on: bool): void {
        // Hyprland 0.56 in Lua mode takes Lua dispatcher expressions.
        const action = on ? "enable" : "disable";
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.dpms({ action = \"" + action + "\" })" : "dpms " + (on ? "on" : "off"));
    }

    function _run(monitor: string, isIdle: bool): void {
        const idle = Object.assign({}, _idle);
        idle[monitor] = isIdle;
        _idle = idle;
        for (const action of Logic.actions(monitor, isIdle, {
                dpmsOff: _dpmsOff,
                idleOff: Flags.idleOff
            })) {
            switch (action) {
            case "screensaver.start":
                Plugins.callRole("screensaver", "start", []);
                break;
            case "screensaver.dismiss":
                Plugins.callRole("screensaver", "dismiss", []);
                break;
            case "lock":
                if (!Plugins.callRole("lock", "lock", []))
                    Plugins.warnOnce(pluginId + ":nolock", "haseen.idle: no plugin provides 'lock'; idle lock skipped");
                break;
            case "dpms.off":
                _dpmsOff = true;
                _dpms(false);
                break;
            case "dpms.on":
                _dpmsOff = false;
                _dpms(true);
                break;
            case "suspend":
                // The menu's System > Suspend, by absolute path like the
                // battery plugin's critical action.
                _suspends++;
                Quickshell.execDetached([binDir + "/haseen-system", "suspend"]);
                break;
            }
        }
    }

    // Keys like "lock:300:1" (Logic.monitors); ScriptModel diffs strings by
    // value, so an unchanged monitor keeps its countdown.
    Instantiator {
        model: ScriptModel {
            values: Logic.monitors(root.timeouts, root.respectInhibitors)
        }

        delegate: IdleMonitor {
            required property string modelData
            readonly property var spec: Logic.parseMonitor(modelData)

            timeout: spec.timeout
            respectInhibitors: spec.respectInhibitors
            onIsIdleChanged: root._run(spec.name, isIdle)
            // Removed while idle (Stay Awake turned on during the
            // screensaver): undo what its idle state did.
            Component.onDestruction: {
                if (isIdle)
                    root._run(spec.name, false);
            }
        }
    }

    // Test hook (settings.debugIpc): read the monitors over IPC
    // (`qs ipc call haseen.idle state`) instead of waiting blind.
    IpcHandler {
        target: "haseen.idle"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                timeouts: root.timeouts,
                haveScreensaver: root.haveScreensaver,
                monitors: Logic.monitors(root.timeouts, root.respectInhibitors),
                idle: root._idle,
                dpmsOff: root._dpmsOff,
                onBattery: UPower.onBattery,
                suspends: root._suspends
            });
        }
    }
}
