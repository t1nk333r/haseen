//@ pragma UseQApplication
//@ pragma DefaultEnv QT_QUICK_BACKEND = software
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP = 1

// haseen shell root (docs/architecture.md 5). Run with `haseen shell run`.
//
// UseQApplication: tray menus are platform menus, which Quickshell only
// renders in QApplication mode (measured cost: ~5 MB RSS).
// QT_QUICK_BACKEND=software: no blur or shaders are allowed (architecture 6),
// so the GPU scene graph buys nothing and costs ~85 MB RSS on the reference
// laptop (plan 005). Set QT_QUICK_BACKEND in the environment to override.
// QS_NO_RELOAD_POPUP: package updates touch the shell dir and trigger a hot
// reload; the reload toast would be clutter.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Haseen
import qs.Compat as Compat

ShellRoot {
    id: shell

    // Ids of the panels currently shown (one PanelWindow each). Opening a
    // panel closes the others: one popup at a time keeps the screen calm.
    property var openPanels: []
    // Screen the open panel appears on, captured at toggle time.
    property var panelScreen: null
    // `bar toggle` hides the bars for this session only.
    property bool barHidden: false
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    // Legacy plugin facades route native panels through this root, not through
    // detached CLI round trips. The binding is restored when the shell dies.
    Binding {
        target: Compat.Runtime
        property: "nativeShell"
        value: shell
        restoreMode: Binding.RestoreBindingOrValue
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    function togglePanel(id: string): void {
        if (openPanels.indexOf(id) >= 0) {
            closePanel(id);
            return;
        }
        if (Plugins.componentUrl(id, "panel") === "") {
            console.info("haseen: panel toggle: no valid panel plugin '" + id + "'");
            return;
        }
        if (!Config.isEnabled(id)) {
            console.info("haseen: panel toggle: plugin '" + id + "' is disabled");
            return;
        }
        panelScreen = focusedScreen();
        openPanels = [id];
    }

    function closePanel(id: string): void {
        openPanels = openPanels.filter(p => p !== id);
    }

    // launcher/lock/notifications go to the plugin that provides the role: a
    // loaded instance answering fn, else a panel provider for toggle().
    function routeRole(role: string, fn: string): void {
        if (Plugins.callRole(role, fn, []))
            return;
        const pid = Plugins.provider(role);
        if (pid !== "" && fn === "toggle" && Plugins.componentUrl(pid, "panel") !== "") {
            togglePanel(pid);
            return;
        }
        console.info("haseen: no plugin provides '" + role + "', " + role + "." + fn + "() ignored");
    }

    // Apply a setting at once (Config runtime layer) and persist it through
    // the CLI when the files disagree. The CLI calls back into `bar` IPC to
    // apply its own changes, with values the files then already hold, so
    // the two never loop (--no-apply on this side stops the echo).
    function applySetting(path: var, value: var, cliArgs: var): void {
        Config.setRuntime(path, value);
        if (Config.fileValue(path) !== value)
            Quickshell.execDetached([cli].concat(cliArgs, ["--no-apply"]));
    }

    function onOff(mode: string, current: bool): var {
        if (mode === "on" || mode === "pin")
            return true;
        if (mode === "off" || mode === "unpin")
            return false;
        if (mode === "toggle" || mode === "")
            return !current;
        return null;
    }

    function setTransparent(mode: string): string {
        const want = onOff(mode, Config.barTransparent);
        if (want === null)
            return "usage: transparent on|off|toggle";
        applySetting(["bar", "transparent"], want, ["bar", "transparent", want ? "on" : "off"]);
        return want ? "on" : "off";
    }

    // Picks the transparent bar's text colour; one for all screens.
    FrameTextColor {
        id: barText

        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    // Per screen: the bar first, then the frame strips around it.
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope

            required property var modelData

            Bar {
                screen: screenScope.modelData
                hidden: shell.barHidden
                transparent: barText.active
                onTransparencyToggleRequested: shell.setTransparent("toggle")
            }

            Frame {
                screen: screenScope.modelData
                transparent: barText.active
            }
        }
    }

    // Explicit services plus companions needed by listed Omarchy widgets.
    // ScriptModel diffs the ids so an unrelated edit never restarts a service.
    Instantiator {
        model: ScriptModel {
            values: Plugins.serviceKeys
        }

        delegate: ServiceHost {}
    }

    // One LazyLoader per panel plugin: nothing is instantiated until the
    // panel first opens, and closing it frees the window again.
    Instantiator {
        model: ScriptModel {
            values: Plugins.panelIds.filter(id => !Compat.Runtime.panelSelfWindowed(id))
        }

        delegate: LazyLoader {
            id: panelLoader

            required property string modelData

            active: shell.openPanels.indexOf(modelData) >= 0

            PanelPopup {
                pluginId: panelLoader.modelData
                screen: shell.panelScreen
                onCloseRequested: shell.closePanel(panelLoader.modelData)
            }
        }
    }

    // A legacy panel that builds its own window gets no popup from the shell,
    // exactly as upstream's panel loader gives it none: the popup's focus grab
    // covers only the popup's window, so the plugin's first click on its own
    // window would read as an outside click and destroy the panel. Loading
    // stays lazy; the entry exists while the panel is open.
    Instantiator {
        model: ScriptModel {
            values: Plugins.panelIds.filter(id => Compat.Runtime.panelSelfWindowed(id))
        }

        delegate: LazyLoader {
            id: windowedPanelLoader

            required property string modelData

            active: shell.openPanels.indexOf(modelData) >= 0

            PluginSlot {
                pluginId: windowedPanelLoader.modelData
                kind: "panel"
                screen: shell.panelScreen
            }
        }
    }

    IpcHandler {
        target: "shell"

        function reload(): void {
            Quickshell.reload(false);
        }

        function plugins(): string {
            return Plugins.describe();
        }
    }

    IpcHandler {
        target: "panel"

        function toggle(id: string): void {
            const key = Plugins.resolveId(id);
            const rec = Plugins.registry[key];
            // Legacy entries start closed and show themselves on open(payload),
            // so every one of them opens through the compat lifecycle, not by
            // being instantiated.
            if (rec && rec.compat === "omarchy") {
                Compat.Runtime.toggle(key, "");
                return;
            }
            shell.togglePanel(key);
        }

        function close(): void {
            shell.openPanels = [];
            Compat.Runtime.closePopout();
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            shell.routeRole("launcher", "toggle");
        }
    }

    IpcHandler {
        target: "menu"

        function toggle(path: string): void {
            if (Plugins.callRole("menu", "toggle", [path]))
                return;
            shell.routeRole("menu", "toggle");
            if (path !== "")
                Qt.callLater(() => Plugins.callRole("menu", "open", [path]));
        }
    }

    // `haseen bar …` (plan 015). Changes apply at once and persist through
    // the CLI; toggle() is session-only.
    IpcHandler {
        target: "bar"

        function toggle(): string {
            shell.barHidden = !shell.barHidden;
            return shell.barHidden ? "hidden" : "shown";
        }

        function transparent(mode: string): string {
            return shell.setTransparent(mode);
        }

        function position(pos: string): string {
            if (["top", "bottom", "left", "right"].indexOf(pos) < 0)
                return "usage: position top|bottom|left|right";
            shell.applySetting(["bar", "position"], pos, ["bar", "position", pos]);
            return pos;
        }

        function tray(mode: string): string {
            const want = shell.onOff(mode, Plugins.settingsFor("haseen.tray").pinned === true);
            if (want === null)
                return "usage: tray pin|unpin|toggle";
            shell.applySetting(["plugins", "haseen.tray", "settings", "pinned"], want, ["bar", "tray", want ? "pin" : "unpin"]);
            return want ? "pinned" : "unpinned";
        }

        // Test hook: what the bar shows right now.
        function status(): string {
            return JSON.stringify({
                position: Config.barPosition,
                hidden: shell.barHidden,
                transparent: Config.barTransparent,
                transparentActive: barText.active,
                barForeground: barText.hex(Theme.barForeground),
                frame: Config.frameEnabled,
                frameThickness: Config.frameThickness,
                frameRadius: Config.frameRadius,
                trayPinned: Plugins.settingsFor("haseen.tray").pinned === true
            });
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            shell.routeRole("lock", "lock");
        }
    }

    IpcHandler {
        target: "notifications"

        function clear(): void {
            shell.routeRole("notifications", "clear");
        }

        function toggleDnd(): void {
            shell.routeRole("notifications", "toggleDnd");
        }
    }
}
