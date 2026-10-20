import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.monitor-settings panel (plan 098), ported from juliusmork-sys's
// Omarchy Monitor Settings Extender (MIT, Copyright (c) 2026 Julius Getz
// Mørk): every monitor with its refresh rate, scale, rotation and on/off,
// mirror/extend for a laptop with an external monitor, a draggable
// arrangement for two or more, and the cursor size. haseen changes:
//   - Reads `haseen hardware monitor list` once on open, again after each
//     change and on Hyprland's monitor and reload events; the 5 s rescan
//     timer of the original is gone.
//   - Every change is one `haseen hardware monitor …` (built-in panel:
//     `haseen hardware laptop-display`, mirroring: `haseen hardware
//     mirror-display`), so it survives a reload instead of living only in
//     the running Hyprland. One runs at a time; the pills dim meanwhile.
//   - Brightness stays with haseen.display, which this opens; text size,
//     the screensaver timeout and the shell restart button are not ported
//     (haseen font, haseen setup idle and haseen shell restart own them).
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"

    property var info: Model.parseList("")
    property bool loaded: false
    property string error: ""
    // The commands run, for the debugIpc test hook only.
    property var sent: []

    readonly property var monitors: info.monitors
    readonly property var active: monitors.filter(m => !m.disabled)
    readonly property var internal: monitors.find(m => m.internal) || null
    readonly property var focused: monitors.find(m => m.focused) || active[0] || null
    readonly property bool canMirror: internal !== null && monitors.some(m => !m.internal)
    readonly property bool busy: act.running
    readonly property var cursorOptions: Model.CURSOR_SIZES.map(s => ({ value: s, label: s + " px" }))
    readonly property int cursorCurrent: Model.cursorPhysical(info.cursorSize, focused ? focused.scale : 1, Model.CURSOR_SIZES)
    readonly property color subtle: Theme.subtle(Theme.surface)

    width: Theme.fontSize * 30
    spacing: Theme.gap

    function refresh(): void {
        if (list.running)
            list.again = true;
        else
            list.running = true;
    }

    // run(argv): one haseen command after `haseen`, e.g. ["hardware",
    // "monitor", "set", "DP-1", "--scale", "1.25"]. Refused while one runs.
    function run(argv: var): bool {
        if (act.running)
            return false;
        root.error = "";
        const command = [root.binDir + "/haseen-" + argv[0] + "-" + argv[1]].concat(argv.slice(2));
        if (settings.debugIpc === true)
            root.sent = root.sent.concat([argv.join(" ")]);
        act.command = command;
        act.running = true;
        return true;
    }

    Process {
        id: list

        property bool again: false

        running: true
        command: [root.binDir + "/haseen-hardware-monitor", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.info = Model.parseList(text);
                root.loaded = true;
            }
        }
        onExited: code => {
            if (code !== 0 && !root.loaded)
                root.error = "Hyprland did not list the monitors.";
            if (again) {
                again = false;
                running = true;
            }
        }
    }

    Process {
        id: act

        stderr: StdioCollector {
            id: actErr

            waitForEnd: true
        }
        onExited: code => {
            if (code !== 0) {
                const lines = actErr.text.trim().split("\n");
                root.error = (lines[lines.length - 1] || "The change did not apply.").replace(/^Error: /, "");
            }
            // hyprctl answers before the monitor has settled; read it a
            // moment later, as the original did.
            settle.restart();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: settle

        interval: 200
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].indexOf(event.name) >= 0)
                root.refresh();
        }
    }

    // Test hook (settings.debugIpc): read the panel's view and act as a
    // click or a drop would.
    IpcHandler {
        target: "haseen.monitor-settings"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                loaded: root.loaded,
                monitors: root.monitors.map(m => ({ name: m.name, label: m.label, disabled: m.disabled, rates: Model.ratesFor(m.modes, m.width, m.height), scales: Model.scalesFor(m.width, m.height) })),
                mirror: root.info.mirror,
                canMirror: root.canMirror,
                cursor: root.cursorCurrent,
                sent: root.sent,
                busy: root.busy,
                error: root.error
            });
        }

        function act(argv: string): string {
            return root.run(JSON.parse(argv)) ? "ok" : "busy";
        }

        function drop(name: string, x: int, y: int): string {
            const at = Model.place(root.monitors, name, x, y, 0);
            if (!at)
                return "no monitor " + name;
            root.run(["hardware", "monitor", "set", name, "--position", at.x + "x" + at.y]);
            return at.x + "x" + at.y;
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Monitors"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Pill {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Brightness"
            onClicked: Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", "haseen.display"])
        }
    }

    Text {
        width: parent.width
        visible: !root.loaded && root.error === ""
        text: "Reading the monitors…"
        color: root.subtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Arrangement {
        width: parent.width
        visible: root.active.length > 1 && !root.info.mirror
        monitors: root.monitors
        busy: root.busy
        onDropped: (name, x, y) => root.run(["hardware", "monitor", "set", name, "--position", x + "x" + y])
    }

    PillRow {
        width: parent.width
        visible: root.canMirror
        title: "Laptop display"
        options: [
            { value: "extend", label: "Extend" },
            { value: "mirror", label: "Mirror" }
        ]
        current: root.info.mirror ? "mirror" : "extend"
        busy: root.busy
        onPicked: value => root.run(["hardware", "mirror-display", value === "mirror" ? "on" : "off"])
    }

    Repeater {
        // Keyed by connector: a re-read rebuilds only a monitor that is new.
        model: ScriptModel {
            values: root.monitors
            objectProp: "name"
        }

        delegate: MonitorCard {
            required property var modelData

            width: root.width
            monitor: modelData
            monitors: root.monitors
            busy: root.busy
            mirroring: root.info.mirror
            canTurnOff: root.active.length > 1
            onRequest: argv => root.run(argv)
        }
    }

    PillRow {
        width: parent.width
        visible: root.loaded
        title: "Cursor size"
        options: root.cursorOptions
        current: root.cursorCurrent
        busy: root.busy
        onPicked: value => root.run(["hardware", "monitor", "cursor", String(Model.cursorLogical(value, root.focused ? root.focused.scale : 1))])
    }

    Text {
        width: parent.width
        visible: root.error !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.error
        color: Theme.urgent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
