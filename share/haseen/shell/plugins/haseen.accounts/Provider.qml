import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Accounts.js" as Accounts

// Launcher provider (plan 132): the agent account workflow as rows, with no
// prefix — haseen.launcher asks every empty-prefix provider beside the apps,
// so typing `account` (or `claude`, or the account's name) in SUPER + D finds
// them. What exists comes from `haseen agent account list --json`, read once
// on the first query and never while the launcher is closed; nothing polls.
//
// Every row runs the CLI's own verb in haseen's floating terminal
// (`haseen config terminal -- …`): `add` needs a TTY for its name prompt and
// the CLI's own browser hand-off, and `use` and `list` print the sentence
// that says what changed. Credentials stay where the CLI put them, and the
// list prints display fields only (plan 108).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // Empty: searched beside the apps on every non-empty query, and never at
    // rest — the empty launcher keeps the menu's ten app rows (plan 122).
    readonly property string prefix: ""
    // The CLI, found the way haseen.commands finds it: $HASEEN_PATH's parent
    // plus bin/, which is /usr/bin/haseen on an installed tree.
    readonly property string cli: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen"
    // What `list --json` printed, and whether that run is over: a row is
    // never shown on a guess.
    property string json: ""
    property bool listed: false
    property bool asked: false
    // I18n's translator for Accounts.js, which stays English on its own.
    readonly property var tx: ({
            tr: (text, ...args) => I18n.tr(text, ...args)
        })

    // rowsFor(jsonText, text) — a query's rows from a given list. The test
    // hook takes the JSON as an argument, as haseen.windows' rowsFor does.
    function rowsFor(jsonText: string, text: string): var {
        return Accounts.rows(Accounts.parse(jsonText), text, root.tx).map(r => ({
                    title: r.title,
                    subtitle: r.subtitle,
                    // No icon-theme name: most themes lack these agents', so a
                    // glyph is drawn in the icon column.
                    icon: "",
                    glyph: r.glyph,
                    exec: () => root.run(r)
                }));
    }

    function query(text: string): var {
        if (!asked) {
            asked = true;
            Qt.callLater(() => {
                if (!listProc.running)
                    listProc.running = true;
            });
        }
        if (!listed)
            return [];
        return rowsFor(json, text);
    }

    // Enter: the CLI's verb in a floating terminal, which stays open until
    // Enter so its output can be read.
    function run(row: var): void {
        const cmd = Accounts.command(row);
        if (cmd.length === 0)
            return;
        Apps.launch([cli, "config", "terminal", "--", cli].concat(cmd));
    }

    // One read-only list per open of the launcher. A run that fails leaves
    // the add rows standing rather than showing an older list.
    Process {
        id: listProc

        command: [root.cli, "agent", "account", "list", "--json"]
        stdout: StdioCollector {
            id: listOut
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.json = code === 0 ? listOut.text : "";
            root.listed = true;
        }
        // A process that cannot start never exits: it must not leave the
        // provider silent forever.
        onRunningChanged: {
            if (!running)
                root.listed = true;
        }
    }
}
