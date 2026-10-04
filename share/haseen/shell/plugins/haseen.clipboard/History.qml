import QtQuick
import Quickshell
import Quickshell.Io
import "Cliphist.js" as Cliphist

// cliphist access shared by the panel and the launcher provider: list on
// demand, copy an entry back (`cliphist decode | wl-copy`), delete one.
// Lives only as long as its owner (an open panel or launcher).
Scope {
    id: root

    // Cliphist.parse rows, newest first.
    property var entries: []
    property bool loaded: false
    // False when `cliphist list` could not run (not installed).
    property bool available: true

    function refresh(): void {
        lister.running = false;
        lister.running = true;
    }

    // The line goes in on stdin: cliphist decode/delete take a list line.
    function copy(entry: var): void {
        if (entry)
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", entry.line]);
    }

    function remove(entry: var): void {
        if (!entry)
            return;
        entries = entries.filter(e => e.id !== entry.id);
        const cmd = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", entry.line];
        // A second delete while one runs goes detached; the local list is
        // already filtered, only the trailing refresh is skipped.
        if (deleter.running) {
            Quickshell.execDetached(cmd);
            return;
        }
        deleter.command = cmd;
        deleter.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: lister

        // Through sh so a missing cliphist is exit 127, not a start failure.
        command: ["sh", "-c", "exec cliphist list"]
        stdout: StdioCollector {
            id: listing
        }
        onExited: code => {
            root.available = code === 0;
            root.entries = code === 0 ? Cliphist.parse(listing.text) : [];
            root.loaded = true;
        }
    }

    Process {
        id: deleter

        onExited: root.refresh()
    }
}
