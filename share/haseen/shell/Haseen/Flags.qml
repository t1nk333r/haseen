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
    // Omarchy's toggle store, read for the screensaver (plan 128).
    readonly property string omarchyToggles: Paths.omarchyState + "/toggles"
    readonly property var names: ["dnd", "idle-off", "screensaver-off", "nightlight", "recording", "gestures"]

    readonly property bool dnd: dndFile.on
    readonly property bool idleOff: idleOffFile.on
    // Either store: haseen's own flag, or Omarchy's, which a third-party
    // screensaver plugin touches while it holds the screensaver slot. Reading
    // only haseen's would start haseen's screensaver underneath the plugin's,
    // and haseen's ttfx quits on the focus change that follows — a flash and
    // nothing (plan 128).
    readonly property bool screensaverOff: screensaverOffFile.on || omarchyScreensaverOff.on
    readonly property bool nightlight: nightlightFile.on
    readonly property bool recording: recordingFile.on
    // Set by the `gestures` hardware quirk on a machine with a touchpad: the
    // haseen.gestures bar widget shows only then.
    readonly property bool gestures: gesturesFile.on
    // The runtime context (plan 062): `haseen context` writes its name into
    // flags/context while one other than normal is active. "" = normal.
    // Not in `names`: only the CLI switches it, since leaving restores the
    // switches it recorded.
    readonly property string context: contextFile.on ? contextFile.value : ""

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
        command: ["mkdir", "-p", "--", root.dir, root.omarchyToggles]
        running: true
        onExited: root._dirReady = true
    }

    component FlagFile: FileView {
        required property string name
        // haseen's own flags live in one directory; Omarchy's toggles live in
        // theirs and are read, never written, from here (plan 128).
        property string dir: root.dir
        property bool on: false
        // The file's first line, for a flag that names something.
        property string value: ""

        path: root._dirReady ? dir + "/" + name : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            value = text().split("\n")[0].trim();
            on = true;
        }
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
    FlagFile {
        id: gesturesFile
        name: "gestures"
    }
    FlagFile {
        id: contextFile
        name: "context"
    }

    // Omarchy's screensaver toggle: a third-party screensaver plugin (the
    // koi) creates it while it is the screensaver, and removes it when it
    // steps aside (plan 128).
    FlagFile {
        id: omarchyScreensaverOff
        name: "screensaver-off"
        dir: root.omarchyToggles
    }
}
