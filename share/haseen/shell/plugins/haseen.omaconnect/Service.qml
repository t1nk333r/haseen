import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.omaconnect service (role `kdeconnect`, plan 098), shared by the bar
// widget and the lazily loaded panel. It exists only while the plugin is
// listed in `services`.
//
// Ported from jitendradara12's OmaConnect, KdeConnectController.qml (MIT,
// Copyright (c) 2026 OmaConnect contributors): a device scan through D-Bus,
// one `dbus-monitor` on the KDE Connect daemon's signals that asks for a new
// scan (and, while the panel shows a phone's player, a new media read) 300 ms
// after the last one, a 15 s rescan only while that monitor is down, one
// action at a time with its message for 4 s, a 30 s pairing watchdog, and
// Tailscale peers and saved addresses for devices KDE Connect cannot find on
// its own. haseen changes: the scripts are `haseen kdeconnect`; SMS, the
// KDE Connect app and the firewall step (`haseen setup kdeconnect`) start
// through Apps.launch; files are picked with `haseen menu select`; a pairing
// request while the panel is closed is one notification.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property string cli: binDir + "/haseen-kdeconnect"

    // "starting", "ready", "unavailable" (daemon not answering) or
    // "missing" (KDE Connect not installed).
    property string discovery: "starting"
    property bool scanning: false
    property var devices: []
    property string selectedId: ""
    readonly property var selected: devices.find(d => d.id === selectedId) || null
    readonly property var reachable: devices.filter(d => d.paired && d.reachable)
    readonly property var incoming: devices.find(d => d.pairRequestedByPeer) || null
    property var addresses: []
    property bool addressesReady: false

    // The last action's outcome, shown under the action bar for 4 s.
    property string message: ""
    property string error: ""
    // id -> "requesting" | "removing" while a pairing change is in flight.
    property var pairing: ({})

    property var commands: []
    property bool commandsLoading: false
    property var media: Model.parseMedia("")
    // Open panels count themselves here: the phone's player is read only
    // while one shows it, and a pairing request is a notification only
    // while none is open.
    property int panelsOpen: 0

    property var tailscale: null
    property bool tailscaleLoading: false
    property bool tailscaleMissing: false

    // Set when a call starts, cleared when it ends: Process.running only
    // reads true once the process has started.
    property bool acting: false
    readonly property bool busy: acting || pairProc.running || pickProc.running
    // Device ids a notification was sent for, so a request is announced once.
    property var announced: ({})
    property int monitorRestarts: 0

    function refresh(force: bool): void {
        if (scanProc.running) {
            if (force)
                scanProc.again = "force";
            else if (!scanProc.again)
                scanProc.again = "plain";
            return;
        }
        root.scanning = true;
        scanProc.command = force ? [root.cli, "devices", "--refresh"] : [root.cli, "devices"];
        scanProc.running = true;
    }

    function select(id: string): void {
        if (root.selectedId === id)
            return;
        root.selectedId = id;
        root.commands = [];
        root.media = Model.parseMedia("");
        if (root.panelsOpen > 0)
            root.fetchMedia();
    }

    function say(text: string, failed: bool): void {
        root.message = failed ? "" : text;
        root.error = failed ? text : "";
        dismiss.restart();
    }

    function applyScan(text: string, code: int): void {
        root.scanning = false;
        if (code === 127) {
            root.discovery = "missing";
            return;
        }
        if (code !== 0) {
            root.discovery = "unavailable";
            return;
        }
        const scan = Model.parseScan(text);
        root.devices = scan.devices;
        root.addressesReady = scan.addressesReady;
        if (scan.addressesReady)
            root.addresses = scan.addresses;
        root.discovery = "ready";
        // A pairing that went through (or an unpair) ends its wait.
        const next = Object.assign({}, root.pairing);
        let changed = false;
        for (const d of scan.devices) {
            if ((next[d.id] === "requesting" && d.paired) || (next[d.id] === "removing" && !d.paired)) {
                if (next[d.id] === "requesting")
                    root.say(d.name + " paired", false);
                delete next[d.id];
                changed = true;
            }
            if (d.pairRequestedByPeer && !root.announced[d.id] && root.panelsOpen === 0) {
                const a = Object.assign({}, root.announced);
                a[d.id] = true;
                root.announced = a;
                Quickshell.execDetached([root.binDir + "/haseen-notification-send", "-a", "KDE Connect", "-i", "kdeconnect", d.name + " wants to pair", "Check the key " + Model.formatKey(d.verificationKey) + " in the KDE Connect panel"]);
            }
        }
        if (changed)
            root.pairing = next;
        root.select(Model.pickDevice(scan.devices, root.selectedId));
    }

    // act(argv, done, what): one kdeconnect-cli (or haseen) call for the
    // selected device; refused while another runs or the device is offline.
    function act(argv: var, done: string, what: string): bool {
        if (root.busy) {
            root.say("Wait for the last action to finish", true);
            return false;
        }
        if (!Model.canAct(root.selected)) {
            root.say("The device must be paired and reachable", true);
            return false;
        }
        actionProc.done = done;
        actionProc.what = what;
        actionProc.command = argv;
        root.acting = true;
        actionProc.running = true;
        root.message = "";
        root.error = "";
        return true;
    }

    function cliFor(flag: var): var {
        return ["kdeconnect-cli", "-d", root.selectedId].concat(flag);
    }

    function ring(): bool {
        return root.act(root.cliFor(["--ring"]), "Ringing", "ring");
    }

    function sendClipboard(): bool {
        return root.act(root.cliFor(["--send-clipboard"]), "Clipboard sent", "clipboard");
    }

    function ping(text: string): bool {
        const t = String(text || "").trim() || String(root.settings.defaultPingMessage || "").trim();
        return root.act(root.cliFor(t ? ["--ping-msg", t] : ["--ping"]), "Ping sent", "ping");
    }

    function shareText(text: string): bool {
        const t = String(text || "").trim();
        if (!t) {
            root.say("Nothing to send", true);
            return false;
        }
        return root.act(root.cliFor(["--share-text", t]), "Text sent", "text");
    }

    function pickFile(): bool {
        if (root.busy) {
            root.say("Wait for the last action to finish", true);
            return false;
        }
        if (!Model.canAct(root.selected)) {
            root.say("The device must be paired and reachable", true);
            return false;
        }
        pickProc.deviceId = root.selectedId;
        pickProc.running = true;
        return true;
    }

    function openSms(): void {
        if (Model.canAct(root.selected))
            Apps.launch(["kdeconnect-sms", "--device", root.selectedId]);
    }

    function openApp(): void {
        Apps.launch(["kdeconnect-app"]);
    }

    function setupFirewall(): void {
        Apps.launch([root.binDir + "/haseen-setup-kdeconnect", "on"]);
    }

    function fetchCommands(): void {
        if (commandsProc.running || !root.selected || !root.selected.caps.commands || !Model.canAct(root.selected))
            return;
        root.commandsLoading = true;
        commandsProc.deviceId = root.selectedId;
        commandsProc.command = ["kdeconnect-cli", "-d", root.selectedId, "--list-commands"];
        commandsProc.running = true;
    }

    function runCommand(key: string): bool {
        return root.act(root.cliFor(["--execute-command", key]), "Command sent", "command");
    }

    function pair(): void {
        if (!root.selected || pairProc.running || actionProc.running)
            return;
        root.setPairing(root.selectedId, "requesting");
        pairProc.command = ["kdeconnect-cli", "-d", root.selectedId, "--pair"];
        pairProc.running = true;
        watchdog.restart();
        root.say("Pair request sent; accept it on " + root.selected.name, false);
    }

    function unpair(): void {
        if (!root.selected || pairProc.running || actionProc.running)
            return;
        root.setPairing(root.selectedId, "removing");
        pairProc.command = ["kdeconnect-cli", "-d", root.selectedId, "--unpair"];
        pairProc.running = true;
    }

    function answer(id: string, accept: bool): void {
        if (pairProc.running)
            return;
        pairProc.command = [root.cli, "pair", accept ? "accept" : "reject", id];
        pairProc.running = true;
    }

    function setPairing(id: string, value: string): void {
        const next = Object.assign({}, root.pairing);
        if (value)
            next[id] = value;
        else
            delete next[id];
        root.pairing = next;
    }

    function fetchMedia(): void {
        if (!root.selected || !root.selected.caps.media || !Model.canAct(root.selected))
            return;
        if (mediaProc.running) {
            mediaProc.again = true;
            return;
        }
        mediaProc.deviceId = root.selectedId;
        mediaProc.command = [root.cli, "media", "status", root.selectedId];
        mediaProc.running = true;
    }

    function mediaAction(action: string): void {
        if (Model.canAct(root.selected) && !mediaActProc.running) {
            mediaActProc.command = [root.cli, "media", "action", root.selectedId, action];
            mediaActProc.running = true;
        }
    }

    function mediaPlayer(name: string): void {
        if (Model.canAct(root.selected) && !mediaActProc.running) {
            mediaActProc.command = [root.cli, "media", "player", root.selectedId, name];
            mediaActProc.running = true;
        }
    }

    function fetchTailscale(): void {
        if (tailscaleProc.running)
            return;
        root.tailscaleLoading = true;
        tailscaleProc.running = true;
    }

    function saveAddress(address: string, remove: bool): bool {
        const a = String(address || "").trim();
        const why = Model.addressError(a);
        if (why) {
            root.say(why, true);
            return false;
        }
        if (!root.addressesReady || addressProc.running) {
            root.say("KDE Connect's address list is not ready", true);
            return false;
        }
        if (!remove && root.addresses.indexOf(a) >= 0) {
            root.refresh(true);
            return true;
        }
        addressProc.address = a;
        addressProc.remove = remove;
        addressProc.command = [root.cli, "address", remove ? "remove" : "add", a];
        addressProc.running = true;
        return true;
    }

    Component.onCompleted: refresh(false)

    Process {
        id: scanProc

        // A scan asked for while one runs: "plain", "force" or "".
        property string again: ""

        stdout: StdioCollector {
            id: scanOut

            waitForEnd: true
        }
        onExited: code => {
            root.applyScan(scanOut.text, code);
            if (again) {
                const force = again === "force";
                again = "";
                root.refresh(force);
            }
        }
    }

    // The daemon's signals: a device came or went, a battery or pairing
    // changed. Events only; the sampler below covers a monitor that died.
    Process {
        id: monitor

        running: root.discovery !== "missing"
        command: ["dbus-monitor", "--session", "type='signal',sender='org.kde.kdeconnect'"]
        stdout: SplitParser {
            onRead: line => {
                if (/device|charge|state|refresh|pair|reachable/i.test(line))
                    scanDebounce.restart();
                if (/mpris|PropertiesChanged/.test(line) && root.panelsOpen > 0)
                    mediaDebounce.restart();
            }
        }
        onExited: {
            restartMonitor.interval = Math.min(30000, 1000 * Math.pow(2, root.monitorRestarts));
            root.monitorRestarts += 1;
            restartMonitor.restart();
        }
        onStarted: root.monitorRestarts = 0
    }

    // haseen:ui-timeout
    Timer {
        id: restartMonitor

        onTriggered: {
            if (root.discovery !== "missing")
                monitor.running = true;
        }
    }

    // haseen:ui-timeout
    Timer {
        id: scanDebounce

        interval: 300
        onTriggered: root.refresh(false)
    }

    // haseen:ui-timeout
    Timer {
        id: mediaDebounce

        interval: 300
        onTriggered: root.fetchMedia()
    }

    // haseen:sample
    Timer {
        interval: 15000
        repeat: true
        running: !monitor.running && root.discovery !== "missing"
        onTriggered: root.refresh(false)
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

    // haseen:ui-timeout
    Timer {
        id: watchdog

        interval: 30000
        onTriggered: {
            let waited = false;
            for (const id in root.pairing)
                if (root.pairing[id] === "requesting") {
                    root.setPairing(id, "");
                    waited = true;
                }
            if (waited)
                root.say("Pairing timed out or was rejected", true);
        }
    }

    Process {
        id: actionProc

        property string done: ""
        property string what: ""

        stderr: StdioCollector {
            waitForEnd: true
        }
        onExited: code => {
            root.acting = false;
            root.say(code === 0 ? done : Model.failure(code, what), code !== 0);
        }
    }

    Process {
        id: pickProc

        property string deviceId: ""

        command: [root.cli, "pick-file"]
        stdout: StdioCollector {
            id: picked

            waitForEnd: true
        }
        onExited: code => {
            const path = picked.text.trim();
            if (code !== 0 || !path || deviceId !== root.selectedId) {
                root.say("No file sent", false);
                return;
            }
            Qt.callLater(() => root.act(root.cliFor(["--share", path]), "File sent", "file transfer"));
        }
    }

    Process {
        id: commandsProc

        property string deviceId: ""

        stdout: StdioCollector {
            id: commandsOut

            waitForEnd: true
        }
        onExited: code => {
            root.commandsLoading = false;
            if (deviceId === root.selectedId)
                root.commands = code === 0 ? Model.parseCommands(commandsOut.text) : [];
        }
    }

    Process {
        id: pairProc

        onExited: code => {
            if (code !== 0) {
                root.pairing = ({});
                root.say(Model.failure(code, "pairing"), true);
            }
            root.refresh(false);
        }
    }

    Process {
        id: mediaProc

        property string deviceId: ""
        property bool again: false

        stdout: StdioCollector {
            id: mediaOut

            waitForEnd: true
        }
        onExited: code => {
            if (deviceId === root.selectedId)
                root.media = code === 0 ? Model.parseMedia(mediaOut.text) : Model.parseMedia("");
            if (again) {
                again = false;
                root.fetchMedia();
            }
        }
    }

    Process {
        id: mediaActProc

        onExited: code => {
            if (code !== 0)
                root.say(Model.failure(code, "media control"), true);
            mediaDebounce.restart();
        }
    }

    Process {
        id: tailscaleProc

        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: tailscaleOut

            waitForEnd: true
        }
        onExited: code => {
            root.tailscaleLoading = false;
            root.tailscaleMissing = code === 127 || code === -1;
            root.tailscale = code === 0 ? Model.parseTailscale(tailscaleOut.text) : null;
        }
    }

    Process {
        id: addressProc

        property string address: ""
        property bool remove: false

        onExited: code => {
            root.say(code === 0 ? (remove ? "Removed " : "Saved ") + address : Model.failure(code, "address"), code !== 0);
            root.refresh(code === 0 && !remove);
        }
    }

    // Test hook (settings.debugIpc): the service's view.
    IpcHandler {
        target: "haseen.omaconnect"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                discovery: root.discovery,
                devices: root.devices.map(d => ({ id: d.id, name: d.name, status: Model.status(d), details: Model.details(d, true, true) })),
                selected: root.selectedId,
                addresses: root.addresses,
                message: root.message,
                error: root.error,
                pairing: root.pairing,
                media: root.media,
                commands: root.commands
            });
        }

        function refresh(): string {
            root.refresh(false);
            return "ok";
        }

        function call(name: string, arg: string): string {
            switch (name) {
            case "ring":
                return String(root.ring());
            case "clipboard":
                return String(root.sendClipboard());
            case "ping":
                return String(root.ping(arg));
            case "text":
                return String(root.shareText(arg));
            case "commands":
                root.fetchCommands();
                return "ok";
            case "run":
                return String(root.runCommand(arg));
            case "media":
                root.panelsOpen += 1;
                root.fetchMedia();
                return "ok";
            case "mediaAction":
                root.mediaAction(arg);
                return "ok";
            case "address":
                return String(root.saveAddress(arg, false));
            case "unaddress":
                return String(root.saveAddress(arg, true));
            case "accept":
                root.answer(arg, true);
                return "ok";
            }
            return "unknown " + name;
        }
    }
}
