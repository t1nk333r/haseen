import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// haseen.session: Lock, Log out, Suspend, Reboot, Shut down. Arrows move,
// Enter or a click runs; with settings.confirm the destructive ones need a
// second press. Open with `haseen shell ipc panel toggle haseen.session`.
//
// Lock goes to the `lock` role (haseen.lock), falling back to
// `loginctl lock-session` for a lock daemon listening to logind. Log out,
// Suspend, Reboot and Shut down run `haseen system`, as the menu's System
// rows and SUPER + SHIFT + ESCAPE do: it asks every window to close first so
// a browser saves its session (plan 104), and brings a pending boot splash up
// to date before a reboot or shutdown (plan 177). The panel called systemctl
// and Hyprland's exit dispatcher itself until plan 197, and skipped both.
//
// Another installed OS (Windows) is one more row: `haseen boot list` reads the
// firmware's entries, and the row sets BootNext through pkexec and reboots
// through `haseen system`, so it starts once without touching the boot order
// or Secure Boot.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool confirm: settings.confirm !== false
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    // Firmware menus and removable slots are entries too, and they are noise in
    // a power menu. settings.bootEntries decides what shows: "auto" (the
    // default) drops them by label, a list of ids or labels shows exactly those.
    readonly property var bootNoise: /^(USB|PXE|IDER|ATA\b|ATAPI|CD\/DVD|Setup|Boot Menu|Diagnostic|Network|Startup|Rescue|MEBx)/i
    // settings.bootEntries as the panel reads it: null for "auto", [] for
    // none, else the lowercased ids and labels to show. The manifest types it
    // a string, so the Settings panel saves `false` and `0000, Windows` as
    // text; a hand-edited shell.json may hold the boolean or a JSON list
    // (plan 197). A list in settings can arrive as a Qt sequence, for which
    // Array.isArray is false, so any object with a length counts.
    readonly property var bootWanted: {
        const v = settings.bootEntries;
        if (v !== null && typeof v === "object" && typeof v.length === "number") {
            const out = [];
            for (let i = 0; i < v.length; i++) {
                const w = String(v[i]).trim().toLowerCase();
                if (w !== "")
                    out.push(w);
            }
            return out;
        }
        if (v === false)
            return [];
        const text = typeof v === "string" ? v.trim().toLowerCase() : "auto";
        if (text === "auto" || text === "")
            return null;
        if (text === "false" || text === "none" || text === "off")
            return [];
        return text.split(",").map(w => w.trim()).filter(w => w !== "");
    }
    property var bootActions: []
    readonly property var actions: baseActions.concat(bootActions)
    // label and confirm (the armed row's line) are English, translated where
    // the row shows them; %1 is a boot entry's own label (plan 109).
    readonly property var baseActions: [
        {
            id: "lock",
            label: I18n.mark("Lock"),
            glyph: "\uf023",
            destructive: false
        },
        {
            id: "logout",
            label: I18n.mark("Log out"),
            confirm: I18n.mark("Log out? Press again"),
            glyph: "\uf2f5",
            destructive: true
        },
        {
            id: "suspend",
            label: I18n.mark("Suspend"),
            glyph: "\uf186",
            destructive: false
        },
        {
            id: "reboot",
            label: I18n.mark("Reboot"),
            confirm: I18n.mark("Reboot? Press again"),
            glyph: "\uf2f9",
            destructive: true
        },
        {
            id: "poweroff",
            label: I18n.mark("Shut down"),
            confirm: I18n.mark("Shut down? Press again"),
            glyph: "\uf011",
            destructive: true
        }
    ]

    // Entries the firmware can start, read once while the panel is open.
    Process {
        id: bootList
        running: root.bootWanted === null || root.bootWanted.length > 0
        command: [root.cli + "-boot-list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let listing = {};
                try {
                    listing = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (listing.status !== "ready")
                    return;
                const wanted = root.bootWanted;
                root.bootActions = (listing.entries || []).filter(entry => {
                    if (entry.id === listing.currentId)
                        return false;
                    if (wanted)
                        return wanted.indexOf(entry.id.toLowerCase()) >= 0 || wanted.indexOf(entry.label.toLowerCase()) >= 0;
                    return !root.bootNoise.test(entry.label);
                }).map(entry => ({
                    id: "boot:" + entry.id,
                    label: I18n.mark("Reboot into %1"),
                    confirm: I18n.mark("Reboot into %1? Press again"),
                    bootLabel: entry.label,
                    glyph: "\uf2f9",
                    destructive: true
                }));
            }
        }
    }

    property int current: 0
    // Id of the action waiting for its confirming press.
    property string armed: ""

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function run(id: string): void {
        if (confirm && armed !== id && actions.find(a => a.id === id).destructive) {
            armed = id;
            return;
        }
        armed = "";
        close();
        if (id.startsWith("boot:")) {
            const entry = actions.find(a => a.id === id);
            // pkexec authenticates the BootNext write; the reboot that follows
            // is the user's own, `haseen system reboot` through logind, and
            // only once the firmware took it. Detached in its own scope, as
            // the menu runs `haseen system`: close() frees this panel, and a
            // Process it owned would die with it before the reboot. The id
            // and label stay argv ("$1", "${@:2}"), never part of the script.
            Apps.launch(["bash", "-c", 'pkexec "${@:2}" && exec "$1" system reboot', "haseen-session", root.cli, root.cli + "-boot-next", id.slice(5), "--label", entry.bootLabel, "--yes"]);
            return;
        }
        if (id === "lock") {
            if (!Plugins.callRole("lock", "lock", []))
                Quickshell.execDetached(["loginctl", "lock-session"]);
            return;
        }
        const verb = ({
                logout: "logout",
                suspend: "suspend",
                reboot: "reboot",
                poweroff: "shutdown"
            })[id];
        if (verb)
            Apps.launch([root.cli, "system", verb]);
    }

    function shift(delta: int): void {
        current = (current + delta + actions.length) % actions.length;
        armed = "";
    }

    width: Theme.fontSize * 16
    spacing: 2
    focus: true

    Keys.onUpPressed: shift(-1)
    Keys.onDownPressed: shift(1)
    Keys.onTabPressed: shift(1)
    Keys.onBacktabPressed: shift(-1)
    Keys.onReturnPressed: run(actions[current].id)
    Keys.onEnterPressed: run(actions[current].id)

    Component.onCompleted: forceActiveFocus()

    // Test hook (settings.debugIpc): select and press rows over IPC while the
    // panel is open, so a smoke test never injects keys into the session.
    IpcHandler {
        target: "haseen.session"
        enabled: root.settings.debugIpc === true

        function select(index: int): void {
            root.current = Math.max(0, Math.min(index, root.actions.length - 1));
            root.armed = "";
        }

        function press(): void {
            root.run(root.actions[root.current].id);
        }

        function state(): string {
            return JSON.stringify({
                current: root.actions[root.current].id,
                armed: root.armed
            });
        }
    }

    Repeater {
        model: root.actions

        delegate: BarButton {
            required property var modelData
            required property int index

            readonly property bool isArmed: root.armed === modelData.id

            width: root.width
            height: Theme.fontSize * 2.4
            glyph: modelData.glyph
            text: I18n.tr(isArmed ? modelData.confirm : modelData.label, modelData.bootLabel || "")
            color: isArmed ? Theme.urgent : Theme.foreground
            highlighted: root.current === index
            onClicked: {
                root.current = index;
                root.run(modelData.id);
            }
        }
    }
}
