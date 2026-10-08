pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.Haseen

// The calendar is a transient panel, so accepted writes belong to the shell.
// Keep the latest requested value live while queued CLI writes reload Config.
Singleton {
    id: root

    property var writes: []
    property var writing: null
    property var pendingDayName: null

    function effectiveSetting(savedValue: var): var {
        return pendingDayName !== null ? pendingDayName : savedValue;
    }
    function releaseFailedOverride(): void {
        if (writes.length === 0)
            pendingDayName = null;
    }

    function setDayName(enabled: bool): void {
        pendingDayName = enabled;
        Config.setRuntime(["plugins", "haseen.clock", "settings", "showDayName"], enabled);
        writes = writes.concat([enabled]);
        startWrite();
    }

    function startWrite(): void {
        if (writing !== null || writes.length === 0)
            return;
        writing = writes[0];
        writes = writes.slice(1);
        writer.command = [Paths.haseenPath + "/../../bin/haseen-plugin-settings", "haseen.clock", "--yes"];
        writer.running = true;
    }

    property Process writer: Process {
        id: writer

        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector { id: errors }

        onStarted: {
            write(JSON.stringify({ settings: { showDayName: root.writing } }) + "\n");
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (running)
                return;
            Qt.callLater(() => {
                if (root.writing === null || writer.running)
                    return;
                console.warn("haseen.clock: cannot start clock settings persistence");
                root.writing = null;
                writer.stdinEnabled = true;
                root.releaseFailedOverride();
                root.startWrite();
            });
        }
        onExited: function(code) {
            if (root.writing === null)
                return;
            if (code !== 0) {
                console.warn("haseen.clock: clock settings persistence failed:", errors.text);
                root.releaseFailedOverride();
            } else if (root.writes.length === 0 && root.pendingDayName !== null) {
                // A user-file reload may have cleared Config.runtime before the
                // newest write completed. Reassert the confirmed value before
                // releasing the live override.
                Config.setRuntime(["plugins", "haseen.clock", "settings", "showDayName"], root.pendingDayName);
                root.pendingDayName = null;
            }
            root.writing = null;
            stdinEnabled = true;
            Qt.callLater(() => root.startWrite());
        }
    }
}
