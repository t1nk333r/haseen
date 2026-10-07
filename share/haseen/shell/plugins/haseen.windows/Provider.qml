import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Windows.js" as Windows

// Launcher provider (plan 081): `@text` lists open windows from
// Hyprland.toplevels (class icon, title, workspace); Enter focuses one with
// `hyprctl dispatch`. Created when the launcher opens and destroyed with it;
// the window list is refreshed once per open and then follows Hyprland's
// events through the bindings.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: "@"

    // Plain copies of Hyprland.toplevels for Windows.js.
    function openWindows(): var {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        const out = [];
        for (const t of list) {
            const ipc = t.lastIpcObject || {};
            let wmClass = String(ipc["class"] || "");
            if (wmClass === "" && t.wayland)
                wmClass = String(t.wayland.appId || "");
            out.push({
                address: Windows.normalAddress(ipc.address || t.address),
                title: String(t.title || ipc.title || ""),
                wmClass: wmClass,
                workspace: t.workspace ? String(t.workspace.name) : String((ipc.workspace && ipc.workspace.name) || ""),
                focus: ipc.focusHistoryID !== undefined ? Number(ipc.focusHistoryID) : 9999
            });
        }
        return out;
    }

    function icon(wmClass: string): string {
        if (wmClass === "")
            return "";
        const entry = DesktopEntries.heuristicLookup(wmClass);
        return entry && entry.icon ? entry.icon : wmClass.toLowerCase();
    }

    function focus(address: string): void {
        const argv = Windows.focusArgv(address, Hyprland.usingLua);
        if (argv.length > 0)
            Quickshell.execDetached(argv);
    }

    function rowsFor(windows: var, text: string): var {
        return Windows.rank(windows, text).slice(0, 50).map(w => ({
                    title: w.title || w.wmClass || w.address,
                    subtitle: Windows.subtitle(w),
                    icon: root.icon(w.wmClass),
                    exec: () => root.focus(w.address)
                }));
    }

    function query(text: string): var {
        const rows = rowsFor(openWindows(), text);
        if (rows.length === 0)
            return [
                {
                    title: text.trim() === "" ? "No open windows" : "No matching window",
                    subtitle: "Windows: type part of a title or class",
                    icon: "preferences-system-windows",
                    exec: () => {}
                }
            ];
        return rows;
    }

    // lastIpcObject (class, focus order) is filled by a refresh.
    Component.onCompleted: Hyprland.refreshToplevels()
}
