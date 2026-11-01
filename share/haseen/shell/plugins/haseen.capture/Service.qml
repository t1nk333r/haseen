import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.capture's service (plan 150): what the toolbar captures, and what
// must outlive it. The toolbar (Panel.qml) is freed when it closes, so the
// capture's delay, the recording pill and the controller listener live here.
// It starts nothing of its own: the commands are `haseen capture screenshot`,
// `screenrecord` and `audiorecord`, started in their own scope (Apps.launch)
// so a shell restart never cuts a recording, and the flags those commands
// write (Flags: `recording`, `audio-recording`) say what runs, however it
// was started. The pill and the listener exist only while they are needed.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // The toolbar's choices, kept while the shell runs (Model.initialState).
    property var state: Model.initialState(settings)
    // Set by the open toolbar; the controller is read for it.
    property bool panelOpen: false
    // A capture waiting out its delay, and the state it was asked with.
    property bool pending: false
    property var pendingCommand: []

    readonly property string recordingKind: Model.recordingKind(Flags.recording, Flags.audioRecording)
    readonly property bool recording: recordingKind !== ""
    // The recording's start in epoch seconds; 0 until a flag says it, then
    // the moment the shell first saw the recording.
    property real seenAt: 0
    readonly property real recordingSince: {
        const flagged = Model.sinceSeconds(recordingKind === "audio" ? Flags.audioRecordingStart : Flags.recordingStart);
        return flagged > 0 ? flagged : seenAt;
    }
    onRecordingChanged: seenAt = recording ? Date.now() / 1000 : 0
    // The recording's clock, for the pill and the toolbar: `now` moves once
    // a second, and only while one of them shows a running recording.
    property bool pillShown: false
    readonly property bool ticking: recording && (panelOpen || pillShown)
    property real now: Date.now() / 1000
    readonly property string elapsed: Model.elapsedText(recordingSince > 0 ? now - recordingSince : 0)
    onTickingChanged: {
        now = Date.now() / 1000;
        if (ticking)
            tick.restart();
    }

    // What gamepad.py reports.
    readonly property bool controllerWanted: settings.controller === true && (panelOpen || recording)
    property int controllers: 0
    property string controllerError: ""

    // A controller press while the toolbar is open, for the toolbar.
    signal padPressed(string button)

    function change(key: string, value: var): void {
        state = Model.withChange(state, key, value);
    }

    // The toolbar's capture: it closes first, then this waits out the
    // delay (at least long enough for the toolbar to leave the screen).
    function capture(edit: bool): bool {
        if (recording) {
            stop();
            return true;
        }
        if (pending || !Model.canCapture(state))
            return false;
        pendingCommand = Model.startCommand(state, edit);
        pending = true;
        waitTimer.interval = Model.waitMs(state, 300);
        waitTimer.restart();
        return true;
    }

    function cancel(): void {
        waitTimer.stop();
        pending = false;
        pendingCommand = [];
    }

    function stop(): void {
        if (recording)
            Quickshell.execDetached(Model.stopCommand(recordingKind));
    }

    // One line from gamepad.py: the open toolbar gets the presses; with it
    // closed, only the Guide button means something, and only while a
    // recording runs.
    function padLine(line: string): void {
        const event = Model.padLine(line);
        if (!event)
            return;
        if (event.kind === "connected") {
            controllers = event.value;
        } else if (event.kind === "error") {
            controllerError = event.value;
        } else if (panelOpen) {
            padPressed(event.value);
        } else if (event.value === "guide" && recording) {
            stop();
        }
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // The delay before a capture: one shot, armed by capture().
    // haseen:ui-timeout
    Timer {
        id: waitTimer

        repeat: false
        onTriggered: {
            root.pending = false;
            const argv = root.pendingCommand;
            root.pendingCommand = [];
            if (argv.length > 0)
                Apps.launch(argv, {});
        }
    }

    // The clock's second: single-shot, re-armed from onTriggered while
    // `ticking` holds, as the media panel's seek bar (architecture 6).
    // haseen:ui-timeout
    Timer {
        id: tick

        interval: 1000
        repeat: false
        onTriggered: {
            root.now = Date.now() / 1000;
            if (root.ticking)
                tick.restart();
        }
    }

    // The controller listener: only while the setting is on and the toolbar
    // is open or a recording runs, so the Guide button can stop it.
    Process {
        id: pad

        command: ["python3", Qt.resolvedUrl("gamepad.py").toString().replace(/^file:\/\//, "")]
        running: root.controllerWanted
        stdout: SplitParser {
            onRead: line => root.padLine(line)
        }
        onExited: root.controllers = 0
    }

    LazyLoader {
        active: root.recording && root.settings.pill !== false
        source: Qt.resolvedUrl("PillWindow.qml")
        onItemChanged: if (item)
            item.service = root
        onActiveChanged: root.pillShown = active
    }

    // Test hook (settings.debugIpc): what the service would run, without
    // running it, and a controller press as gamepad.py prints it.
    IpcHandler {
        target: "haseen.capture.service"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                state: root.state,
                pending: root.pending,
                command: root.pendingCommand,
                recording: root.recordingKind,
                since: root.recordingSince,
                listening: pad.running,
                panelOpen: root.panelOpen
            });
        }

        function cancel(): void {
            root.cancel();
        }

        function line(text: string): void {
            root.padLine(text);
        }
    }
}
