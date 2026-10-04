pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// State flags (plan 019): a file in $HASEEN_USER_STATE/flags/<name> means
// "on". The CLI (`haseen toggle dnd`, `haseen capture screenrecord`, …)
// creates and removes the files; every QML reader uses this singleton, so
// there is one set of inotify watches and no polling.
//
// FileView watches the file and its parent directory; a directory that does
// not exist yet cannot be watched, so the watches start only after a one-off
// `mkdir -p`.
Singleton {
    id: root

    readonly property string dir: Paths.userState + "/flags"
    readonly property var names: ["dnd", "idle-off", "screensaver-off", "nightlight", "recording"]

    readonly property bool dnd: dndFile.on
    readonly property bool idleOff: idleOffFile.on
    readonly property bool screensaverOff: screensaverOffFile.on
    readonly property bool nightlight: nightlightFile.on
    readonly property bool recording: recordingFile.on

    property bool _dirReady: false

    function path(name: string): string {
        return dir + "/" + name;
    }

    // set("dnd", true) creates the flag file, set("dnd", false) removes it.
    // The bools follow through the watches, exactly as for a CLI change.
    function set(name: string, on: bool): void {
        if (names.indexOf(name) < 0) {
            console.warn("haseen: Flags.set: unknown flag '" + name + "'");
            return;
        }
        if (on)
            Quickshell.execDetached(["sh", "-c", "mkdir -p -- \"$1\" && : >\"$1/$2\"", "sh", dir, name]);
        else
            Quickshell.execDetached(["rm", "-f", "--", path(name)]);
    }

    Process {
        command: ["mkdir", "-p", "--", root.dir]
        running: true
        onExited: root._dirReady = true
    }

    component FlagFile: FileView {
        required property string name
        property bool on: false

        path: root._dirReady ? root.path(name) : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: on = true
        onLoadFailed: on = false
    }

    FlagFile {
        id: dndFile
        name: "dnd"
    }
    FlagFile {
        id: idleOffFile
        name: "idle-off"
    }
    FlagFile {
        id: screensaverOffFile
        name: "screensaver-off"
    }
    FlagFile {
        id: nightlightFile
        name: "nightlight"
    }
    FlagFile {
        id: recordingFile
        name: "recording"
    }
}
