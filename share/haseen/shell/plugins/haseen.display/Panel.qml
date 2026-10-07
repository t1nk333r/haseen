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
// waiting one replacing older ones. Off by default; open it with
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
    property var sent: []

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
        sent = sent.concat([command.slice(1).join(" ")]);
        setProc.command = command;
        setProc.running = true;
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

        onExited: {
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
                sent: root.sent
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
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Repeater {
        model: root.devices

        delegate: Column {
            id: row

            required property var modelData
            readonly property var device: modelData
            readonly property int value: root.valueOf(device)
            property bool dragging: false
            property int dragPercent: 0
            readonly property int shownPercent: dragging ? dragPercent : Model.percent(value, device.max)

            width: root.width
            spacing: Math.round(Theme.gap / 2)

            // A press sends at once; a move sends only when the percent
            // changes, so the release does not repeat the last one.
            function slideTo(x: real, pressed: bool): void {
                const pct = Model.fromFraction(x / track.width, device.max);
                const moved = pressed || pct !== dragPercent;
                dragPercent = pct;
                if (moved && Model.live(device.kind))
                    root.send(device, pct);
            }

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
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Item {
                id: track

                width: parent.width
                height: Math.round(Theme.fontSize * 1.4)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Math.max(Theme.gap, 4)
                    radius: height / 2
                    color: Theme.surfaceAlt

                    Rectangle {
                        width: parent.width * row.shownPercent / 100
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                    }
                }

                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, parent.width * row.shownPercent / 100 - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Theme.fontSize * 1.1)
                    height: width
                    radius: width / 2
                    color: Theme.accent
                    border.color: Theme.surface
                    border.width: Theme.borderWidth
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: mouse => {
                        row.dragging = true;
                        row.slideTo(mouse.x, true);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            row.slideTo(mouse.x, false);
                    }
                    onReleased: mouse => {
                        row.slideTo(mouse.x, false);
                        if (!Model.live(row.device.kind))
                            root.send(row.device, row.dragPercent);
                        row.dragging = false;
                    }
                    onWheel: wheel => {
                        const pct = Math.max(0, Math.min(100, row.shownPercent + (wheel.angleDelta.y > 0 ? 5 : -5)));
                        root.send(row.device, pct);
                    }
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: Model.emptyText(root.devices.length, root.sysfsDone && root.ddcDone)
        color: Theme.muted
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

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: stateText.implicitWidth + Theme.gap * 3
            height: Math.round(Theme.fontSize * 1.8)
            radius: Theme.radius
            color: Flags.nightlight ? Theme.accent : "transparent"
            border.color: Flags.nightlight ? Theme.accent : Theme.border
            border.width: Theme.borderWidth

            Text {
                id: stateText

                anchors.centerIn: parent
                text: Flags.nightlight ? "On" : "Off"
                color: Flags.nightlight ? Theme.accentFg : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
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
