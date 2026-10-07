import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Haseen
import "BatteryLogic.js" as Logic

// haseen.battery service (plan 075): low and critical battery warnings from
// UPower's display device. Every reading is a property change on the D-Bus
// object (Quickshell.Services.UPower), so nothing polls; the decisions live
// in BatteryLogic.js (tests/test-battery.sh).
//   warnAt      one normal notification when the charge reaches it while
//               discharging;
//   criticalAt  one critical notification;
//   criticalAction (none by default) suspend, hibernate or poweroff: the
//               critical notification then carries a Cancel button, and
//               `haseen system <verb>` runs 60 s later unless Cancel was
//               pressed or a charger came. Closing the notification is not
//               a cancel.
// A charger resets both levels; nothing repeats while the charge stays below.
// Notifications go through `haseen notification send`, so the shell's own
// notification server shows them and keeps them in its history.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property var cfg: Logic.config(settings)
    readonly property var device: UPower.displayDevice
    // A new object on every change of a property it reads.
    readonly property var reading: Logic.reading(device ? {
        ready: device.ready,
        isLaptopBattery: device.isLaptopBattery,
        isPresent: device.isPresent,
        percentage: device.percentage,
        state: device.state
    } : null)
    property var logic: Logic.initial()
    // Every notification sent, for the debug hook.
    property var sent: []
    property string lastAction: ""

    function _info(): var {
        return {
            percent: reading.percent,
            timeToEmpty: device ? device.timeToEmpty : 0
        };
    }

    function _notify(event: string): void {
        const m = Logic.message(event, _info(), cfg);
        if (!m)
            return;
        sent = sent.concat([event + ": " + m.summary + " | " + m.body]);
        Quickshell.execDetached([binDir + "/haseen-notification-send", "-u", m.urgency, m.summary, m.body]);
    }

    // The countdown notification: the --exec of `haseen notification send`
    // is its Cancel button, and that command's output, "cancel", reaches
    // countdownNote's stdout only when the button is pressed.
    function _startCountdown(): void {
        const m = Logic.message("critical", _info(), cfg);
        sent = sent.concat(["critical: " + m.summary + " | " + m.body]);
        countdownNote.running = false;
        countdownNote.command = [binDir + "/haseen-notification-send", "-u", "critical", "--action-label", "Cancel", m.summary, m.body, "--exec", "echo", "cancel"];
        countdownNote.running = true;
        countdown.interval = Math.max(1000, logic.deadline - Date.now());
        countdown.restart();
    }

    function _stopCountdown(): void {
        countdown.stop();
        countdownNote.running = false;
    }

    function evaluate(): void {
        const r = Logic.step(logic, reading, cfg, Date.now());
        logic = r.state;
        for (const e of r.events) {
            switch (e) {
            case "warn":
                _notify("warn");
                break;
            case "critical":
                if (!logic.armed)
                    _notify("critical");
                break;
            case "arm":
                _startCountdown();
                break;
            case "disarm":
                _stopCountdown();
                _notify("disarm");
                break;
            }
        }
    }

    function cancel(): void {
        if (!logic.armed)
            return;
        logic = Logic.cancel(logic);
        _stopCountdown();
    }

    onReadingChanged: evaluate()
    onCfgChanged: evaluate()
    Component.onCompleted: evaluate()

    Process {
        id: countdownNote

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.trim() === "cancel")
                    root.cancel();
            }
        }
    }

    // haseen:ui-timeout
    Timer {
        id: countdown

        repeat: false
        onTriggered: {
            const r = Logic.fire(root.logic, root.reading, root.cfg, Date.now());
            root.logic = r.state;
            if (r.rearm) {
                root._startCountdown();
            } else if (r.run) {
                countdownNote.running = false;
                root.lastAction = r.verb;
                Quickshell.execDetached(Logic.actionCommand(root.binDir, r.verb));
            }
        }
    }

    // Test hook (settings.debugIpc): read the service's view over IPC
    // (`qs ipc call haseen.battery state`); cancel() is the notification's
    // Cancel button.
    IpcHandler {
        target: "haseen.battery"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                config: root.cfg,
                reading: root.reading,
                logic: root.logic,
                remaining: Logic.remaining(root.logic, Date.now()),
                sent: root.sent,
                lastAction: root.lastAction
            });
        }

        function cancel(): void {
            root.cancel();
        }
    }
}
