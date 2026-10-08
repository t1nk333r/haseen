import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen

// Apply immediately in the shell, then persist through the plugin settings CLI.
// Queue writes so quick successive clicks cannot overwrite one another.
QtObject {
    id: root

    property var writes: []
    property var writing: null

    function setDayName(enabled: bool): void {
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
                console.warn("haseen.calendar: cannot start clock settings persistence");
                root.writing = null;
                writer.stdinEnabled = true;
                root.startWrite();
            });
        }
        onExited: function(code) {
            if (root.writing === null)
                return;
            if (code !== 0)
                console.warn("haseen.calendar: clock settings persistence failed:", errors.text);
            root.writing = null;
            stdinEnabled = true;
            Qt.callLater(() => root.startWrite());
        }
    }
}
