import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Commands.js" as Commands
import "../haseen.menu/MenuModel.js" as Model

// Launcher provider (plan 081): `/text` searches the menu's commands (the
// leaves of default/menu.jsonc plus ~/.config/haseen/menu.jsonc, merged as
// the menu does), with the submenu path as the subtitle. Enter runs the
// action as the menu would, through Apps.launch.
//
// `when` and `disabled` guards: a guarded row shows only once its guard has
// answered in this open of the launcher. The provider runs one guard batch
// the first time `/` is typed and uses only those answers; until they land,
// guarded rows are left out, never run on a guess or on an answer the menu
// cached earlier (a package removed, the battery gone). The answers are
// merged into MenuModel.memory.guards for the menu as before.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: "/"
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    property string defaultText: ""
    property string userText: ""
    property var guards: null
    property bool asked: false
    readonly property var tree: {
        const defaults = Model.parseMenuJsonc(defaultText) || [];
        const user = Model.parseMenuJsonc(userText) || [];
        return Model.mergeMenuSources(defaults, user);
    }
    readonly property var rows: Commands.leaves(tree.items, tree.itemOrder, guards)

    function run(action: string): void {
        const c = Commands.command(action, binDir);
        if (c.panel !== "") {
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", c.panel]);
            return;
        }
        Apps.launch(c.argv, {
            desktopId: "haseen-menu"
        });
    }

    function askGuards(): void {
        if (asked || guardProc.running)
            return;
        const script = Model.guardScript(tree.items);
        if (script === "")
            return;
        asked = true;
        guardProc.command = ["bash", "-c", "PATH=\"$1:$PATH\"; eval \"$2\"", "bash", binDir, script];
        guardProc.running = true;
    }

    function query(text: string): var {
        if (!asked)
            Qt.callLater(askGuards);
        const ranked = Commands.rank(tree.items, rows, text).slice(0, 50);
        if (ranked.length === 0)
            return [
                {
                    title: defaultText === "" ? "Reading the menu…" : "No matching command",
                    subtitle: "Commands: the menu's actions, e.g. /theme, /screenshot, /update",
                    icon: "system-run",
                    exec: () => {}
                }
            ];
        return ranked.map(r => ({
                    title: r.label,
                    subtitle: r.path || "Menu",
                    icon: "system-run",
                    exec: () => root.run(r.action)
                }));
    }

    FileView {
        path: Paths.haseenPath + "/default/menu.jsonc"
        onLoaded: root.defaultText = text()
    }

    FileView {
        path: Paths.userConfig + "/menu.jsonc"
        printErrors: false
        onLoaded: root.userText = text()
    }

    Process {
        id: guardProc

        stdout: StdioCollector {
            onStreamFinished: {
                const fresh = Commands.mergeGuards(null, Model.parseGuardOutput(text));
                Model.memory.guards = Commands.mergeGuards(Model.memory.guards, fresh);
                root.guards = fresh;
            }
        }
    }
}
