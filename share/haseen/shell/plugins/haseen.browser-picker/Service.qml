// Adapted from Picker.qml (the request, rule and ranking logic) of
// K53N0/omarchy-browser-picker (MIT, Copyright (c) 2026 K53N0), via the
// owner's fork t1nk33r.browser-picker 1.0.0-t1nk33r.1; see LICENSE and
// UPSTREAM.md beside this file.
// haseen: a service (role `browser-picker`) that answers IPC `pick` from
// bin/haseen-browser-picker through the caller's FIFO, as the menu's pick list
// does; the card is a lazily loaded Overlay.qml; settings from shell.json;
// rules in ~/.config/haseen/browser-picker.json, rankings in
// ~/.local/state/haseen/browser-picker.json.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Haseen
import "Model.js" as Model

// Every link the picker is the default browser for arrives here as one
// request: {urls, flags, selectionFile, doneFile}. A rule for the link's host
// answers at once (autoOpenRules); otherwise the card asks. The answer is a
// ready-to-run argv written NUL-separated to selectionFile, then one line to
// the caller's FIFO doneFile, also when nothing was chosen. The window exists
// only while a request is open.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string scanCommand: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen-browser-scan"
    readonly property string configPath: Paths.userConfig + "/browser-picker.json"
    readonly property string statePath: Paths.userState + "/browser-picker.json"
    readonly property string legacyRulesPath: Paths.home + "/.config/browser-chooser/rules"

    property var entries: []
    property bool scanned: false
    // The rules file; its `settings` are not read: the plugin settings are.
    property var rules: []
    readonly property var pickerSettings: Model.parseSettings(settings)
    readonly property var config: ({
            version: Model.CONFIG_VERSION,
            settings: pickerSettings,
            rules: rules
        })
    property var pickerState: Model.parseState("")
    property bool stateLoaded: false
    property bool legacyChecked: false
    property bool adoptChecked: false

    // The live request. An empty doneFile means nobody is waiting.
    property string selectionFile: ""
    property string doneFile: ""
    property var urls: []
    property var flags: []
    property string host: ""
    property bool opened: false
    property var targetScreen: null
    // The last argv answered, for the test hook.
    property var lastAnswer: null

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    function pick(request: string): void {
        // A second request while one is open answers the first "nothing
        // chosen", or its caller would wait on a FIFO nobody writes.
        if (doneFile !== "")
            deliver([]);
        requestReader.command = ["cat", "--", request];
        requestReader.running = true;
    }

    function startRequest(text: string): void {
        let req = {};
        try {
            req = JSON.parse(text) || {};
        } catch (e) {
            console.warn(root.pluginId + ": unreadable pick request -", e);
            return;
        }
        selectionFile = String(req.selectionFile || "");
        doneFile = String(req.doneFile || "");
        urls = Array.isArray(req.urls) ? req.urls.map(String) : [];
        flags = Array.isArray(req.flags) ? req.flags.map(String) : [];
        host = urls.length > 0 ? Model.hostOf(urls[0]) : "";
        // Profiles come and go while the shell runs, so every request scans;
        // with a list in hand the card shows it now and the rescan replaces it.
        scan();
        if (scanned)
            resolve();
    }

    function scan(): void {
        if (!scanner.running)
            scanner.running = true;
    }

    // Does this request need a person at all?
    function resolve(): void {
        if (doneFile === "")
            return;
        const rule = host ? Model.matchRule(rules, host) : null;
        if (rule && pickerSettings.autoOpenRules) {
            const target = Model.entryById(entries, rule.entryId);
            // A rule whose profile is gone is stale, not fatal: ask instead.
            if (target) {
                finish(target, false);
                return;
            }
        }
        targetScreen = focusedScreen();
        opened = true;
    }

    function finish(entry: var, alsoMakeRule: bool): void {
        // Only a choice somebody waits on is counted, so a stray second click
        // cannot inflate the ranking.
        if (entry && doneFile !== "") {
            const now = Date.now() / 1000;
            pickerState = Model.recordChoice(pickerState, entry.id, host, now);
            stateFile.setText(Model.serializeState(pickerState));
            if (alsoMakeRule && host)
                writeRules(Model.upsertRule(rules, host, entry.id, true));
        }
        deliver(entry ? Model.launchArgv(entry, urls, flags) : []);
    }

    function cancel(): void {
        deliver([]);
    }

    // The argv first, then the release, in one sh, so the caller can never
    // read a half-written selection. The FIFO is opened read-write, so the
    // write never blocks even when the caller has gone.
    function deliver(argv: var): void {
        const sel = selectionFile;
        const done = doneFile;
        selectionFile = "";
        doneFile = "";
        opened = false;
        lastAnswer = argv;
        if (done === "")
            return;
        const script = "sel=$1 done=$2; shift 2; if [ $# -gt 0 ] && [ -n \"$sel\" ]; then printf '%s\\0' \"$@\" > \"$sel\"; fi; printf 'x\\n' 1<>\"$done\"";
        Quickshell.execDetached(["sh", "-c", script, "sh", sel, done].concat(argv.map(String)));
    }

    function writeRules(next: var): void {
        rules = next;
        configFile.setText(Model.serializeConfig({
            rules: next
        }));
    }

    // A hand-written rule is not a learned one any more.
    function applyRule(oldPattern: string, newPattern: string, entryId: string): void {
        let next = rules;
        if (oldPattern && oldPattern !== newPattern)
            next = Model.removeRule(next, oldPattern);
        writeRules(Model.upsertRule(next, newPattern, entryId, false));
    }

    function removeRule(pattern: string): void {
        writeRules(Model.removeRule(rules, pattern));
    }

    // One import of the old bash chooser's rules, once there are labels to
    // match its targets against and no rules of our own yet.
    function importLegacyRules(): void {
        if (legacyChecked || entries.length === 0)
            return;
        legacyChecked = true;
        if (rules.length === 0)
            legacyFile.reload();
    }

    // Entry ids follow how a profile is identified; when that changes the
    // stored rankings move to the new ids once, after both sides are read.
    function adoptRenamedIds(): void {
        if (adoptChecked || entries.length === 0 || !stateLoaded)
            return;
        adoptChecked = true;
        const result = Model.adoptRenamedEntries(pickerState, entries);
        if (result.moves.length === 0)
            return;
        pickerState = result.state;
        stateFile.setText(Model.serializeState(pickerState));
    }

    Component.onCompleted: scan()

    Process {
        id: requestReader

        stdout: StdioCollector {
            id: requestText
        }
        onExited: code => {
            if (code === 0)
                root.startRequest(requestText.text);
        }
    }

    Process {
        id: scanner

        command: [root.scanCommand]
        stdout: StdioCollector {
            id: scanOut
        }
        onExited: code => {
            let parsed = null;
            try {
                parsed = JSON.parse(scanOut.text);
            } catch (e) {
                parsed = null;
            }
            root.entries = parsed && Array.isArray(parsed.entries) ? parsed.entries : [];
            root.scanned = true;
            root.importLegacyRules();
            root.adoptRenamedIds();
            // A request that came before the first scan waits on this.
            if (root.doneFile !== "" && !root.opened)
                root.resolve();
        }
    }

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.rules = Model.parseConfig(text()).rules
        onLoadFailed: root.rules = []
    }

    FileView {
        id: stateFile

        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.pickerState = Model.parseState(text());
            root.stateLoaded = true;
            root.adoptRenamedIds();
        }
        onLoadFailed: {
            root.pickerState = Model.parseState("");
            root.stateLoaded = true;
        }
    }

    FileView {
        id: legacyFile

        path: root.legacyRulesPath
        printErrors: false
        onLoaded: {
            const imported = Model.migrateLegacyRules(text(), root.entries);
            if (imported.length > 0)
                root.writeRules(imported);
        }
    }

    // bin/haseen-browser-picker: one request per link. Answers this shell's
    // PID, so the caller can tell a shell that died from a user still choosing.
    IpcHandler {
        target: "haseen.browser-picker"

        function pick(request: string): string {
            root.pick(request);
            return String(Quickshell.processId);
        }
    }

    // Test hook (settings.debugIpc): drive an open card without a keyboard.
    IpcHandler {
        target: "haseen.browser-picker.debug"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                opened: root.opened,
                host: root.host,
                entries: root.entries.map(e => e.id),
                rows: overlay.item ? overlay.item.rows.map(e => e.id) : [],
                cursor: overlay.item ? overlay.item.cursor : -1,
                offersRule: overlay.item ? overlay.item.offersRule : false,
                rules: root.rules,
                lastAnswer: root.lastAnswer
            });
        }

        function filter(text: string): void {
            if (overlay.item)
                overlay.item.setFilter(text);
        }

        function choose(makeRule: bool): void {
            if (overlay.item)
                overlay.item.choose(makeRule);
        }

        function cancel(): void {
            root.cancel();
        }
    }

    // From a URL, so the card (a layer-shell window) is compiled only when a
    // link waits for it.
    LazyLoader {
        id: overlay

        active: root.opened
        source: Qt.resolvedUrl("Overlay.qml")
        onItemChanged: if (item)
            item.service = root
    }
}
