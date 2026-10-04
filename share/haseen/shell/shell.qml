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

ShellRoot {
    id: shell

    // Ids of the panels currently shown (one PanelWindow each). Opening a
    // panel closes the others: one popup at a time keeps the screen calm.
    property var openPanels: []
    // Screen the open panel appears on, captured at toggle time.
    property var panelScreen: null

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

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // service-kind plugins listed in shell.json `services`. ScriptModel
    // diffs the list, so editing shell.json never restarts unrelated services.
    Instantiator {
        model: ScriptModel {
            values: Config.services.filter(id => Config.isEnabled(id))
        }

        delegate: ServiceHost {}
    }

    // One LazyLoader per panel plugin: nothing is instantiated until the
    // panel first opens, and closing it frees the window again.
    Instantiator {
        model: ScriptModel {
            values: Plugins.panelIds
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
            shell.togglePanel(id);
        }

        function close(): void {
            shell.openPanels = [];
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            shell.routeRole("launcher", "toggle");
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
