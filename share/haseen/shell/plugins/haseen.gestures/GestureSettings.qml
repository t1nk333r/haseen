import QtQuick
import Quickshell
import qs.Haseen
import "Model.js" as Model

// Saves a change from the widget or the panel. The runtime layer repaints at
// once (the tray's pattern, plan 015); `haseen gestures apply --set` then
// persists it to shell.json under the shared lock, renders the Lua and reloads
// Hyprland. The command is the only writer of gestures.lua, so the panel and a
// terminal cannot disagree about what a gesture means.
QtObject {
    id: root

    property string pluginId
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    function save(patch: var): void {
        for (const k in patch)
            Config.setRuntime(["plugins", root.pluginId, "settings", k], patch[k]);
        Quickshell.execDetached(Model.applyCommand(root.cli, patch));
    }
}
