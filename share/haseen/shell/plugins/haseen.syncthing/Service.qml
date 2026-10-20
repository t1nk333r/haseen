import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.syncthing service (role `syncthing`, plan 098), shared by the bar
// widget and the lazily loaded panel. It exists only while the plugin is
// listed in `services`.
//
// Ported from ilyaZar's omarchy-syncthing, hosts/omarchy/OmarchyService.qml
// and shared/CoreProcess.qml (MIT, Copyright (c) 2026 IlyaZar): one status
// read, then Syncthing's own event long poll (60 s per request, so nothing
// polls while Syncthing is up), a status read 500 ms after any event that is
// not a finished file, and the recent file activity. haseen changes:
// upstream's bundled Go core and its web UI themes are gone; `haseen
// syncthing` calls the REST API with curl. While Syncthing is down the status
// is asked for again after 5, 10, 20 and 40 s, then every refreshIntervalSec.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property string cli: binDir + "/haseen-syncthing"

    property var info: null
    property bool online: false
    property bool loaded: false
    // Why the last status read failed, as `haseen syncthing` said it ("" while
    // Syncthing answers).
    property string problem: ""
    readonly property var summary: Model.overall(info, online)
    property var activity: []
    property int lastEvent: 0
    property int failures: 0
    property string serviceState: ""

    property string message: ""
    property string error: ""
    property bool acting: false
    readonly property bool busy: acting

    function refresh(): void {
        if (statusProc.running)
            statusProc.again = true;
        else
            statusProc.running = true;
    }

    function say(text: string, failed: bool): void {
        root.message = failed ? "" : text;
        root.error = failed ? text : "";
        dismiss.restart();
    }

    // run(args, done): one `haseen syncthing ARGS`; refused while another runs.
    function run(args: var, done: string): bool {
        if (root.acting) {
            root.say("Wait for the last change to finish", true);
            return false;
        }
        root.acting = true;
        actProc.done = done;
        actProc.command = [root.cli].concat(args);
        actProc.running = true;
        return true;
    }

    function rescan(id: string): bool {
        return run(["rescan", id], "Scanning");
    }

    function setPaused(id: string, paused: bool): bool {
        return run([paused ? "pause" : "resume", id], paused ? "Paused" : "Resumed");
    }

    function setAllPaused(paused: bool): bool {
        return run([paused ? "pause-all" : "resume-all"], paused ? "Every device paused" : "Every device resumed");
    }

    function share(folder: string, device: string, on: bool): bool {
        return run(["share", folder, device, on ? "on" : "off"], on ? "Shared" : "No longer shared");
    }

    function addFolder(path: string): bool {
        const p = Model.expandHome(path, Paths.home);
        if (p.charAt(0) !== "/") {
            root.say("Enter a full path, such as ~/Documents", true);
            return false;
        }
        return run(["add-folder", p], "Folder added");
    }

    function acceptDevice(id: string, name: string): bool {
        return run(["accept-device", id, name], "Device added");
    }

    function dismissDevice(id: string): bool {
        return run(["dismiss-device", id], "Dismissed");
    }

    function acceptFolder(f: var, path: string): bool {
        const p = Model.expandHome(path, Paths.home);
        if (p.charAt(0) !== "/") {
            root.say("Enter a full path, such as ~/Sync", true);
            return false;
        }
        return run(["accept-folder", f.id, f.device, p, f.label], "Folder accepted");
    }

    function dismissFolder(f: var): bool {
        return run(["dismiss-folder", f.id, f.device], "Dismissed");
    }

    function controlService(verb: string): bool {
        return run(["service", verb], verb === "stop" ? "Syncthing stopped" : "Syncthing " + verb + "ed");
    }

    function openWebUi(): void {
        if (root.info && root.info.guiUrl)
            Apps.launch(["xdg-open", root.info.guiUrl]);
    }

    Component.onCompleted: {
        refresh();
        serviceProc.running = true;
    }

    Process {
        id: statusProc

        property bool again: false

        command: [root.cli, "status"]
        stdout: StdioCollector {
            id: statusOut

            waitForEnd: true
        }
        stderr: StdioCollector {
            id: statusErr

            waitForEnd: true
        }
        onExited: code => {
            root.loaded = true;
            const s = code === 0 ? Model.parseStatus(statusOut.text) : null;
            const why = statusErr.text.trim().split("\n").pop();
            root.problem = s ? "" : code === 127 ? "curl is not installed" : why || "Syncthing is not answering";
            if (s) {
                root.info = s;
                root.online = true;
                root.failures = 0;
                root.poll();
            } else {
                root.online = false;
                retry.interval = Model.backoff(root.failures, root.settings.refreshIntervalSec) * 1000;
                root.failures += 1;
                retry.restart();
            }
            if (again) {
                again = false;
                root.refresh();
            }
        }
    }

    // Syncthing's long poll: one request waits up to 60 s for an event.
    Process {
        id: events

        command: [root.cli, "events", "--since", String(root.lastEvent), "--timeout", "60"]
        stdout: StdioCollector {
            id: eventsOut

            waitForEnd: true
        }
        onExited: code => {
            if (code !== 0) {
                // Stopped or restarted: the status read finds out which.
                root.lastEvent = 0;
                root.refresh();
                return;
            }
            const r = Model.parseEvents(eventsOut.text, root.lastEvent, root.activity);
            const fresh = r.lastId !== root.lastEvent;
            root.activity = r.activity;
            if (r.changed)
                changed.restart();
            root.lastEvent = r.lastId;
            // Syncthing answers an empty poll only after its timeout; one
            // that came back empty at once must not turn into a busy loop.
            if (fresh)
                Qt.callLater(root.poll);
            else
                repoll.restart();
        }
    }

    function poll(): void {
        if (root.online && !events.running)
            events.running = true;
    }

    // haseen:ui-timeout
    Timer {
        id: repoll

        interval: 1000
        onTriggered: root.poll()
    }

    // haseen:ui-timeout
    Timer {
        id: changed

        interval: 500
        onTriggered: root.refresh()
    }

    // haseen:ui-timeout
    Timer {
        id: retry

        onTriggered: root.refresh()
    }

    // haseen:ui-timeout
    Timer {
        id: dismiss

        interval: 4000
        onTriggered: {
            root.message = "";
            root.error = "";
        }
    }

    Process {
        id: actProc

        property string done: ""

        stderr: StdioCollector {
            id: actErr

            waitForEnd: true
        }
        onExited: code => {
            root.acting = false;
            if (code === 0) {
                root.say(done, false);
            } else {
                const lines = actErr.text.trim().split("\n");
                root.say((lines[lines.length - 1] || "The change failed").replace(/^(Error|refusing): /, ""), true);
            }
            if (command.indexOf("service") === 1)
                serviceProc.running = true;
            root.refresh();
        }
    }

    Process {
        id: serviceProc

        command: [root.cli, "service", "status"]
        stdout: StdioCollector {
            id: serviceOut

            waitForEnd: true
        }
        onExited: root.serviceState = serviceOut.text.trim()
    }

    // Test hook (settings.debugIpc): the service's view.
    IpcHandler {
        target: "haseen.syncthing"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                online: root.online,
                summary: root.summary,
                folders: root.info ? root.info.folders.map(f => ({ id: f.id, text: Model.folderText(f) })) : [],
                activity: root.activity,
                lastEvent: root.lastEvent,
                message: root.message,
                error: root.error
            });
        }
    }
}
