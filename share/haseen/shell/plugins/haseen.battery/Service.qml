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
//               `haseen system <verb>` runs 60 s after it is shown unless
//               Cancel was pressed or a charger came. Closing the
//               notification is not a cancel; a notification that could
//               not be shown is (fail closed: no action without a Cancel).
// A level resets once the charge climbs 3 points above it; nothing repeats
// while the charge stays below, also across a charger that comes and goes.
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
    // Countdown notifications that could not be shown, for the debug hook.
    property int undelivered: 0
    // The countdown notification's sender has started and has not yet said
    // it is shown. Its exit in that state means it never was.
    property bool _awaitingNote: false

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
    // is its Cancel button. With -p the sender prints the notification's id
    // once it is on screen, and later "cancel" (the --exec's output) only
    // when the button is pressed. The countdown starts on the id; a sender
    // that ends without one never showed a Cancel, so nothing will run.
    // Stopping the sender closes its notification (it traps TERM).
    function _startCountdown(): void {
        const m = Logic.message("critical", _info(), cfg);
        sent = sent.concat(["critical: " + m.summary + " | " + m.body]);
        countdown.stop();
        _awaitingNote = false;
        countdownNote.running = false;
        countdownNote.command = [binDir + "/haseen-notification-send", "-u", "critical", "-p", "--action-label", "Cancel", m.summary, m.body, "--exec", "echo", "cancel"];
        countdownNote.running = true;
    }

    function _noteShown(): void {
        if (!_awaitingNote)
            return;
        _awaitingNote = false;
        if (!logic.armed)
            return;
        logic = Logic.shown(logic, cfg, Date.now());
        countdown.interval = Math.max(1000, logic.deadline - Date.now());
        countdown.restart();
    }

    function _noteFailed(): void {
        _awaitingNote = false;
        if (!logic.armed)
            return;
        undelivered++;
        console.warn("haseen.battery: the critical notification could not be shown; " + cfg.criticalAction + " called off");
        logic = Logic.cancel(logic);
        countdown.stop();
    }

    function _stopCountdown(): void {
        _awaitingNote = false;
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

    // Deferred: UPower sends percentage and time-to-empty in one
    // PropertiesChanged, and the message should read both new values.
    onReadingChanged: Qt.callLater(evaluate)
    onCfgChanged: evaluate()
    Component.onCompleted: evaluate()

    Process {
        id: countdownNote

        // A restart (running = false; running = true) delivers the old
        // sender's exit before the new one starts, so only the current
        // sender can find _awaitingNote set.
        onStarted: root._awaitingNote = root.logic.armed
        onExited: {
            if (root._awaitingNote)
                root._noteFailed();
        }
        stdout: SplitParser {
            onRead: line => {
                if (/^[0-9]+$/.test(line))
                    root._noteShown();
                else if (line.trim() === "cancel")
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
            } else if (r.retry) {
                countdown.interval = r.delay;
                countdown.restart();
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
                lastAction: root.lastAction,
                undelivered: root.undelivered
            });
        }

        function cancel(): void {
            root.cancel();
        }
    }
}
