import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Haseen
import "Stage.js" as Stage

// haseen.stage, a Stage Manager (plan 163): push the pointer against the
// left edge of a screen and that monitor's other workspaces slide in as
// small stacks of their windows, turned towards the middle of the screen,
// each with its app's icon and its number; click one to go there; move away
// or press Escape and they slide out. Behaviour taken from pocket-dots'
// Stage Manager (GPL-3.0, reference only, nothing copied).
//
// At rest only the hot strips exist, one per screen (EdgeStrip.qml): a
// transparent strip two pixels wide that draws nothing. The stage itself
// (StageWindow.qml) is created when it opens and destroyed when it has slid
// out; its window pictures are taken once per open and dropped with it.
// Everything comes from Hyprland's event socket and one toplevel refresh per
// open (for each window's focus order and size); nothing polls.
//
// The edge stays quiet while the screen is locked, while the game context
// is on, while that monitor's workspace has a fullscreen window and while a
// mouse button is held (Stage.suppressed). `haseen shell ipc stage toggle`
// opens it on the focused screen; no key is bound by default.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var cfg: Stage.config(settings)
    readonly property bool locked: {
        const entry = Plugins.roles.lock;
        return !!(entry && entry.instance && entry.instance.locked === true);
    }
    readonly property bool game: Flags.context === "game"

    // The screen the stage is out on, or null; who opened it: edge or ipc.
    property var stageScreen: null
    property string openedBy: ""
    // Why the last open was refused, for `stage status`.
    property string refused: ""

    function monitorOf(s: var): var {
        return s ? Hyprland.monitorFor(s) : null;
    }

    function fullscreenOn(s: var): bool {
        const m = monitorOf(s);
        return !!(m && m.activeWorkspace && m.activeWorkspace.hasFullscreen);
    }

    // Why the strip of screen `s` must stay quiet now, or "".
    function quietReason(s: var, buttons: int): string {
        return Stage.suppressed({
            locked: root.locked,
            context: Flags.context,
            fullscreen: fullscreenOn(s),
            buttons: buttons
        });
    }

    // A window's app icon: its desktop entry's, else its class as an icon
    // name (never a path a client chose); "" when the theme has neither.
    function iconFor(cls: string): string {
        if (cls === "")
            return "";
        const entry = DesktopEntries.heuristicLookup(cls);
        const name = entry && entry.icon ? entry.icon : Stage.themeIcon(cls);
        return name.startsWith("/") ? name : Quickshell.iconPath(name, true);
    }

    // Stage.stacks for screen `s`, from Quickshell's Hyprland objects. Read
    // inside a binding it follows them; only the open stage binds it. The
    // title is left out on purpose: a terminal's title changes all the time.
    function stacksFor(s: var): var {
        const m = monitorOf(s);
        if (!m)
            return [];
        const workspaces = Hyprland.workspaces.values.map(ws => ({
                    id: ws.id,
                    name: ws.name,
                    monitor: ws.monitor ? ws.monitor.name : ""
                }));
        const clients = Hyprland.toplevels.values.map(t => {
            const ipc = t.lastIpcObject || {};
            const size = Array.isArray(ipc.size) ? ipc.size : [0, 0];
            let cls = String(ipc["class"] || ipc.initialClass || "");
            if (cls === "" && t.wayland)
                cls = String(t.wayland.appId || "");
            return {
                address: String(ipc.address || t.address || ""),
                workspace: t.workspace ? t.workspace.id : -1,
                focus: ipc.focusHistoryID,
                cls: cls,
                width: Number(size[0]) || 0,
                height: Number(size[1]) || 0,
                hidden: ipc.hidden === true,
                toplevel: t,
                icon: root.iconFor(cls)
            };
        });
        const activeId = m.activeWorkspace ? m.activeWorkspace.id : -1;
        return Stage.stacks(workspaces, clients, m.name, activeId, cfg.maxWindows);
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // Opens the stage on screen `s` unless something keeps it quiet. A
    // second screen's push moves it there.
    function open(s: var, by: string, buttons: int): bool {
        if (!s)
            return false;
        const why = Stage.suppressed({
            locked: root.locked,
            context: Flags.context,
            fullscreen: fullscreenOn(s),
            buttons: buttons,
            count: stacksFor(s).length
        });
        refused = why;
        if (why !== "")
            return false;
        // Each window's focus order and size live in lastIpcObject, which
        // only a refresh brings up to date.
        Hyprland.refreshToplevels();
        openedBy = by;
        stageScreen = s;
        return true;
    }

    function edgeOpen(s: var, buttons: int): void {
        if (stageScreen === null)
            open(s, "edge", buttons);
    }

    // Slide out; `closed` follows when the column is gone.
    function close(): void {
        if (stageLoader.item)
            stageLoader.item.hide();
        else
            stageScreen = null;
    }

    function closed(): void {
        stageScreen = null;
        openedBy = "";
    }

    function choose(id: int): void {
        const cmd = Stage.focusCommand(id, Hyprland.usingLua);
        close();
        if (cmd !== "")
            Hyprland.dispatch(cmd);
    }

    function toggle(): string {
        if (stageScreen !== null) {
            close();
            return "closed";
        }
        return open(focusedScreen(), "ipc", 0) ? "opened" : "refused: " + refused;
    }

    onLockedChanged: if (locked)
        close()
    onGameChanged: if (game)
        close()

    // One strip per screen, loaded by URL (EdgeStrip.qml's header).
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen

            required property var modelData

            LazyLoader {
                active: true
                source: Qt.resolvedUrl("EdgeStrip.qml")
                onItemChanged: if (item) {
                    item.edgeScreen = perScreen.modelData;
                    item.service = root;
                }
            }
        }
    }

    // A window going fullscreen on the stage's monitor sends the stage
    // away (another workspace does too: StageWindow.qml).
    Connections {
        target: root.stageScreen && root.monitorOf(root.stageScreen) ? root.monitorOf(root.stageScreen).activeWorkspace : null

        function onHasFullscreenChanged(): void {
            if (root.fullscreenOn(root.stageScreen))
                root.close();
        }
    }

    LazyLoader {
        id: stageLoader

        active: root.stageScreen !== null
        source: Qt.resolvedUrl("StageWindow.qml")
        onItemChanged: if (item)
            item.service = root
    }

    // Architecture 5.5. No default bind: `haseen shell ipc stage toggle`
    // is there for a user's own bind and for tests.
    IpcHandler {
        target: "stage"

        function toggle(): string {
            return root.toggle();
        }

        function close(): void {
            root.close();
        }

        function status(): string {
            const s = root.stageScreen || root.focusedScreen();
            return JSON.stringify({
                open: root.stageScreen !== null,
                screen: root.stageScreen ? root.stageScreen.name : "",
                openedBy: root.openedBy,
                edge: root.cfg.edge,
                quiet: root.quietReason(s, 0),
                refused: root.refused,
                workspaces: root.stacksFor(s).map(st => st.id)
            });
        }
    }
}
