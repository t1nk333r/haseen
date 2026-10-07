pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// qs.Common.Proc for DankMaterialShell plugins (architecture 5.4): run a
// command once and hand its stdout and exit code to a callback. The
// runCommand(id, command, callback, debounceMs, timeoutMs, owner) contract
// follows dank-qml-common DCommon/Common/Proc.qml, which DMS's Proc wraps
// (MIT, Copyright (c) 2025-2026 Avenge Media LLC):
//   - calls with the same id inside debounceMs (default 50) collapse into one
//     run, with the last command and callback;
//   - a run still going after timeoutMs (default 10000; noTimeout = -1 never)
//     is stopped and reported with exit code 124;
//   - a command that cannot start reports a non-zero exit code;
//   - a callback whose owner was destroyed is not called.
// The command runs as given: haseen neither rewrites nor blocks it, so a
// plugin's state-changing command (tlp, powerprofilesctl, …) does what the
// plugin asked.
Singleton {
    id: root

    readonly property int noTimeout: -1
    readonly property string dmsBin: Quickshell.env("DMS_EXECUTABLE") || "dms"
    property int defaultDebounceMs: 50
    property int defaultTimeoutMs: 10000
    property var _procDebouncers: ({})

    function runCommand(id, command, callback, debounceMs, timeoutMs, owner) {
        const wait = (typeof debounceMs === "number" && debounceMs >= 0) ? debounceMs : defaultDebounceMs;
        const timeout = (typeof timeoutMs === "number") ? timeoutMs : defaultTimeoutMs;
        const procId = id ? id : Math.random();
        const isRandomId = !id;

        if (!_procDebouncers[procId]) {
            const t = debounceTimerComp.createObject(root);
            t.triggered.connect(function () {
                root._launchProc(procId, isRandomId);
            });
            _procDebouncers[procId] = {
                timer: t,
                command: command,
                callback: callback,
                waitMs: wait,
                timeoutMs: timeout,
                isRandomId: isRandomId,
                owner: owner
            };
        } else {
            const e = _procDebouncers[procId];
            e.command = command;
            e.callback = callback;
            e.waitMs = wait;
            e.timeoutMs = timeout;
            e.owner = owner;
        }

        const entry = _procDebouncers[procId];
        entry.timer.interval = entry.waitMs;
        entry.timer.restart();
    }

    function release(id) {
        if (!id)
            return;
        const entry = _procDebouncers[id];
        if (!entry)
            return;
        entry.callback = null;
        entry.timer.stop();
        entry.timer.destroy();
        delete _procDebouncers[id];
    }

    // A destroyed QObject's wrapper stays truthy; Qt.isQtObject tells.
    function _ownerDead(entry) {
        return entry.owner && !Qt.isQtObject(entry.owner);
    }

    function _launchProc(id, isRandomId) {
        const entry = _procDebouncers[id];
        if (!entry || !entry.command)
            return;
        if (_ownerDead(entry)) {
            release(id);
            return;
        }
        const proc = procComp.createObject(root, {
            command: entry.command
        });
        const timeoutTimer = debounceTimerComp.createObject(root);
        let capturedOut = "";
        let exitSeen = false;
        let exitCode = -1;
        let outSeen = false;
        let errSeen = false;
        let done = false;

        function finish() {
            if (done || !exitSeen || !outSeen || !errSeen)
                return;
            done = true;
            timeoutTimer.stop();
            if (entry.callback && typeof entry.callback === "function" && !root._ownerDead(entry)) {
                try {
                    entry.callback(capturedOut, exitCode);
                } catch (e) {
                    console.warn("haseen: Proc.runCommand callback failed for", JSON.stringify(entry.command) + ":", e);
                }
            }
            proc.destroy();
            timeoutTimer.destroy();
            // A poller re-sets these on every call; dropping them frees a
            // dead caller's closure between polls.
            if (!entry.timer.running) {
                entry.command = null;
                entry.callback = null;
                entry.owner = undefined;
            }
            if (isRandomId || entry.isRandomId)
                Qt.callLater(function () {
                    if (root._procDebouncers[id]) {
                        root._procDebouncers[id].timer.destroy();
                        delete root._procDebouncers[id];
                    }
                });
        }

        // A run that cannot start (no such command) never exits or closes
        // its streams: report it the way a shell would.
        function failedStart() {
            exitSeen = outSeen = errSeen = true;
            exitCode = 127;
            finish();
        }

        timeoutTimer.interval = entry.timeoutMs;
        timeoutTimer.triggered.connect(function () {
            if (exitSeen)
                return;
            proc.running = false;
            exitSeen = outSeen = errSeen = true;
            exitCode = 124;
            finish();
        });
        proc.stdout.streamFinished.connect(function () {
            capturedOut = proc.stdout.text || "";
            outSeen = true;
            finish();
        });
        proc.stderr.streamFinished.connect(function () {
            errSeen = true;
            finish();
        });
        proc.exited.connect(function (code) {
            exitSeen = true;
            exitCode = code;
            finish();
        });
        // A run that never started stops without exiting; after the event
        // that stopped it, an exit has been seen or never will be.
        proc.runningChanged.connect(function () {
            if (!proc.running)
                Qt.callLater(function () {
                    if (!exitSeen)
                        failedStart();
                });
        });
        proc.running = true;
        if (entry.timeoutMs !== noTimeout)
            timeoutTimer.start();
    }

    Component {
        id: debounceTimerComp

        // haseen:ui-timeout
        Timer {
            repeat: false
        }
    }

    Component {
        id: procComp

        Process {
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
}
