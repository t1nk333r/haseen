import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen

// haseen.clipboard service: records clipboard history with cliphist, one
// `wl-paste --type <t> --watch cliphist store` watcher for text and one for
// images (the setup cliphist's README recommends). Event-driven: wl-paste
// blocks on the Wayland data device and runs `cliphist store` per copy.
//
// Sensitive copies: wl-paste >= 2.2 sets CLIPBOARD_STATE=sensitive when the
// source offers x-kde-passwordManagerHint (password managers), and
// `cliphist store` skips those (and handles CLIPBOARD_STATE=clear). Nothing
// here filters MIME types itself, so that handling stays cliphist's.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int maxItems: typeof settings.maxItems === "number" && settings.maxItems >= 1 ? Math.round(settings.maxItems) : 750
    // False once a watcher found wl-paste or cliphist missing.
    property bool available: true

    component Watcher: Process {
        id: watcher

        required property string type

        // exit 127: a tool is missing; checked first so wl-paste never spawns
        // a missing cliphist once per copy. setpriv --pdeathsig (util-linux)
        // ends the watcher with the shell: Quickshell stops it on reload, but
        // a killed or crashed shell would otherwise leave it recording.
        command: ["sh", "-c", "command -v wl-paste >/dev/null && command -v cliphist >/dev/null || exit 127; command -v setpriv >/dev/null && set -- \"$@\" setpriv --pdeathsig TERM; t=$1 n=$2; shift 2; exec \"$@\" wl-paste --type \"$t\" --watch cliphist -max-items \"$n\" store", "sh", type, String(root.maxItems)]
        running: true
        onExited: code => {
            if (code === 127) {
                root.available = false;
                Plugins.warnOnce("clipboard:missing", "haseen.clipboard: wl-paste or cliphist not installed, history is not recorded");
            } else {
                Plugins.warnOnce("clipboard:exit:" + watcher.type, "haseen.clipboard: " + watcher.type + " watcher exited (" + code + ")");
            }
        }
    }

    Watcher {
        type: "text"
    }

    Watcher {
        type: "image"
    }
}
