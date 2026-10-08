import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.display panel (plan 077): a brightness slider per laptop backlight,
// keyboard backlight and DDC/CI monitor, and the night light when
// haseen.nightlight runs. `haseen brightness list` runs once when the panel
// opens, sysfs devices and DDC monitors apart, so the slow DDC probe never
// holds back the backlight. After that, backlight and keyboard values follow
// an inotify watch (FileView) on the file the list names, so keys and other
// tools move the sliders too; DDC values are read on open only. Every change
// goes through `haseen brightness set ID N%`, one at a time, the latest
// waiting one replacing older ones. A write the device refuses puts its
// slider back where it was and says so under the row. Rows are keyed by
// device id, so the DDC list landing late keeps the backlight row (and a
// drag on it). Off by default; open it with
// `haseen shell ipc panel toggle haseen.display` or Setup › Display.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"

    property var sysfsDevices: []
    property var ddcDevices: []
    property bool sysfsDone: false
    property bool ddcDone: false
    readonly property var devices: Model.merge(sysfsDevices, ddcDevices)
    // Raw values seen since the panel opened, by id: watches and DDC writes.
    property var live: ({})
    // Writes waiting for the running one, one per device (Model.enqueue).
    property var pending: []
    // True from a write's start until the queue is empty; the process alone
    // is not running for a moment between two writes.
    property bool busy: false
    // Values each device last took, by id, for a refused write to go back
    // to; the list's value until a write lands.
    property var confirmed: ({})
    // A refused write's message, by id, until the next write lands.
    property var errors: ({})
    // The writes run, for the debugIpc test hook only.
    property var sent: []
    readonly property color subtle: Theme.subtle(Theme.surface)

    readonly property bool nightlightShown: Plugins.componentUrl("haseen.nightlight", "service") !== "" && Config.isListed("haseen.nightlight") && Config.isEnabled("haseen.nightlight")

    width: Theme.fontSize * 24
    spacing: Theme.gap

    function noteValue(id: string, value: int): void {
        if (value < 0 || live[id] === value)
            return;
        const next = Object.assign({}, live);
        next[id] = value;
        live = next;
    }

    function valueOf(device: var): int {
        return live[device.id] !== undefined ? live[device.id] : device.value;
    }

    function send(device: var, pct: int): void {
        const command = [binDir + "/haseen-brightness"].concat(Model.setArgs(device.id, pct));
        // No watch tells a DDC monitor's value: show what was asked for.
        if (!device.watch)
            noteValue(device.id, Model.valueFor(device, pct));
        if (busy) {
            pending = Model.enqueue(pending, device.id, command);
            return;
        }
        run(command);
    }

    function run(command: var): void {
        busy = true;
        if (settings.debugIpc === true)
            sent = sent.concat([command.slice(1).join(" ")]);
        setProc.deviceId = command[2];
        setProc.percent = parseInt(command[3], 10);
        setProc.command = command;
        setProc.running = true;
    }

    function setEntry(map: var, id: string, value: var): var {
        const next = Object.assign({}, map);
        if (value === undefined)
            delete next[id];
        else
            next[id] = value;
        return next;
    }

    // The write for `id` ended. Refused: back to the value it last took
    // (a newer write waiting for it shows its own value instead), and say so.
    function landed(id: string, pct: int, ok: bool): void {
        const device = find(id);
        if (!device)
            return;
        if (ok) {
            confirmed = setEntry(confirmed, id, Model.valueFor(device, pct));
            errors = setEntry(errors, id, undefined);
            return;
        }
        errors = setEntry(errors, id, device.label + " did not accept the change");
        if (!device.watch && !pending.some(p => p.id === id))
            noteValue(id, confirmed[id] !== undefined ? confirmed[id] : device.value);
    }

    function find(id: string): var {
        for (const d of devices)
            if (d.id === id)
                return d;
        return null;
    }

    Process {
        running: true
        command: [root.binDir + "/haseen-brightness", "list", "--kind", "backlight,keyboard"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.sysfsDevices = Model.parseList(text)
        }
        onExited: root.sysfsDone = true
    }

    Process {
        running: true
        command: [root.binDir + "/haseen-brightness", "list", "--kind", "ddc"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.ddcDevices = Model.parseList(text)
        }
        onExited: root.ddcDone = true
    }

    Process {
        id: setProc

        property string deviceId: ""
        property int percent: 0

        onExited: code => {
            root.landed(setProc.deviceId, setProc.percent, code === 0);
            if (root.pending.length === 0) {
                root.busy = false;
                return;
            }
            const next = root.pending[0].command;
            root.pending = root.pending.slice(1);
            Qt.callLater(() => root.run(next));
        }
    }

    // Test hook (settings.debugIpc): read the panel's view and move a slider
    // as a release would (`qs ipc call haseen.display slide ID PERCENT`).
    IpcHandler {
        target: "haseen.display"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                devices: root.devices.map(d => ({ id: d.id, kind: d.kind, label: d.label, value: root.valueOf(d), max: d.max })),
                ddcDone: root.ddcDone,
                nightlight: root.nightlightShown,
                sent: root.sent,
                errors: root.errors
            });
        }

        function slide(id: string, percent: int): string {
            const d = root.find(id);
            if (!d)
                return "no device " + id;
            root.send(d, percent);
            return "ok";
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Display"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.ddcDone
            text: "Looking for monitors…"
            color: root.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Repeater {
        // Keyed by id: a row is rebuilt only for a device that is new.
        model: ScriptModel {
            values: root.devices
            objectProp: "id"
        }

        delegate: Column {
            id: row

            required property var modelData
            readonly property var device: modelData
            readonly property int value: root.valueOf(device)
            readonly property int shownPercent: slider.dragging ? Math.round(slider.dragValue * 100) : Model.percent(value, device.max)
            readonly property string error: root.errors[device.id] || ""

            width: root.width
            spacing: Math.round(Theme.gap / 2)

            FileView {
                path: row.device.watch
                watchChanges: row.device.watch !== ""
                printErrors: false
                onFileChanged: reload()
                onLoaded: root.noteValue(row.device.id, Model.toInt(text()))
            }

            Item {
                width: parent.width
                height: Math.round(Theme.fontSize * 1.8)

                Glyph {
                    id: glyph

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.fontSize * 2
                    glyph: Model.glyph(row.device.kind)
                }

                Text {
                    anchors.left: glyph.right
                    anchors.leftMargin: Theme.gap
                    anchors.right: percentText.left
                    anchors.rightMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: row.device.label
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    id: percentText

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.shownPercent + "%"
                    color: root.subtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            // Backlights send while dragged (each new level once), a DDC
            // monitor once on release; a 3-level keyboard snaps to its levels.
            TrackBar {
                id: slider

                width: parent.width
                live: Model.live(row.device.kind)
                steps: row.device.max < 100 ? row.device.max : 0
                value: Model.percent(row.value, row.device.max) / 100
                onMoved: v => root.send(row.device, Model.fromFraction(v, row.device.max))
            }

            Text {
                width: parent.width
                visible: row.error !== ""
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: row.error
                color: Theme.urgent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: Model.emptyText(root.devices.length, root.sysfsDone && root.ddcDone)
        color: root.subtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Item {
        width: parent.width
        height: Math.round(Theme.fontSize * 2.4)
        visible: root.nightlightShown

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surfaceAlt
            visible: nightMouse.containsMouse
        }

        Glyph {
            id: nightGlyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: "\uf186"
            color: Flags.nightlight ? Theme.accent : Theme.foreground
        }

        Text {
            anchors.left: nightGlyph.right
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: "Night light"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        // The state only: the row's MouseArea above it takes the click.
        Pill {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Flags.nightlight ? "On" : "Off"
            active: Flags.nightlight
        }

        MouseArea {
            id: nightMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Flags.set("nightlight", !Flags.nightlight)
        }
    }
}
