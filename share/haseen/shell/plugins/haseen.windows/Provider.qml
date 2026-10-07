import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Windows.js" as Windows

// Launcher provider (plan 081): `@text` lists open windows from
// Hyprland.toplevels (class icon, title, workspace); Enter focuses one with
// `hyprctl dispatch`. Created when the launcher opens and destroyed with it;
// the window list is refreshed on the first `@` query of an open (not on
// every open) and then follows Hyprland's events through the bindings. A
// class's icon is looked up once per open; a window glyph stands in when
// the icon theme has none.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: "@"
    property bool refreshed: false
    // wmClass -> icon name, for this open: one desktop-entry lookup a class.
    readonly property var icons: ({})

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

    // A desktop entry's icon is installed data; the class itself is client
    // input and only ever becomes an icon-theme name (Windows.themeIcon).
    function icon(wmClass: string): string {
        if (wmClass === "")
            return "";
        if (icons[wmClass] === undefined) {
            const entry = DesktopEntries.heuristicLookup(wmClass);
            icons[wmClass] = entry && entry.icon ? entry.icon : Windows.themeIcon(wmClass);
        }
        return icons[wmClass];
    }

    // lastIpcObject (class, focus order) is filled by a refresh.
    function refresh(): void {
        if (refreshed)
            return;
        refreshed = true;
        Hyprland.refreshToplevels();
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
                    glyph: "\uf2d0",
                    exec: () => root.focus(w.address)
                }));
    }

    function query(text: string): var {
        if (!refreshed)
            Qt.callLater(refresh);
        const rows = rowsFor(openWindows(), text);
        if (rows.length === 0)
            return [
                {
                    title: text.trim() === "" ? "No open windows" : "No matching window",
                    subtitle: "Windows: type part of a title or class",
                    icon: "preferences-system-windows",
                    glyph: "\uf2d0",
                    exec: () => {}
                }
            ];
        return rows;
    }
}
