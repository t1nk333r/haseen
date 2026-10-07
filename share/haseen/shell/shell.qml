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
import "PanelPlacement.js" as Placement
import "Overflow.js" as Overflow

ShellRoot {
    id: shell

    // Ids of the panels currently shown (one PanelWindow each). Opening a
    // panel closes the others: one popup at a time keeps the screen calm.
    property var openPanels: []
    // Screen the open panel appears on, captured at toggle time.
    property var panelScreen: null
    // The last press on a bar widget (Bar.widgetPressed), and the one the
    // open panel was toggled from: the panel opens under that widget
    // (PanelPlacement.js). Null when a key or the CLI opened it.
    property var barPress: null
    property var panelOpener: null
    // `bar toggle` hides the bars for this session only.
    property bool barHidden: false
    // Screen name -> { ids, open, arranging }: what each bar's overflow
    // panel holds, and whether that bar is in arrange mode.
    property var overflowState: ({})
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    // `bar arrange`: arrange mode on or off on the bar of this screen.
    signal arrangeRequested(string name, bool on)

    // Legacy plugin facades route native panels through this root, not through
    // detached CLI round trips. The binding is restored when the shell dies.
    Binding {
        target: Compat.Runtime
        property: "nativeShell"
        value: shell
        restoreMode: Binding.RestoreBindingOrValue
    }

    // The border wipe (plan 069): reading it creates the singleton, which
    // subscribes to haseen-sidecar while the theme asks for a wipe.
    readonly property bool borderWipe: BorderWipe.wanted

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    function togglePanel(id: string): void {
        // Every toggle takes the press, so a later key never reuses an old click.
        const press = Placement.opener(barPress, Date.now());
        barPress = null;
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
        panelOpener = press;
        panelScreen = press ? press.screen : focusedScreen();
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

    // `bar.overflow` / `bar.pinned` after one edit (Overflow.edit), applied
    // at once; `persist` saves it through `haseen bar overflow`, which a
    // click in arrange mode needs and the CLI's own IPC call does not.
    function editOverflow(verb: string, id: string, persist: bool): string {
        const r = Overflow.edit(Config.barOverflow, Config.barPinned, verb, id);
        if (r === null || id === "")
            return "usage: overflow add|remove|pin|unpin <id>";
        Config.setRuntime(["bar", "overflow"], r.overflow);
        Config.setRuntime(["bar", "pinned"], r.pinned);
        if (persist)
            Quickshell.execDetached([cli, "bar", "overflow", verb, id, "--no-apply"]);
        return JSON.stringify(r);
    }

    function setPosition(pos: string): string {
        if (["top", "bottom", "left", "right"].indexOf(pos) < 0)
            return "usage: position top|bottom|left|right";
        applySetting(["bar", "position"], pos, ["bar", "position", pos]);
        return pos;
    }

    // One drag-and-drop in arrange mode (Overflow.move), applied at once;
    // `persist` saves it through `haseen bar move`, which a drop needs and
    // the CLI's own IPC call does not.
    function moveWidget(id: string, to: string, before: string, pin: bool, persist: bool): string {
        const b = Config.bar;
        const r = Overflow.move({
            left: b.left,
            center: b.center,
            right: b.right,
            overflow: b.overflow,
            pinned: b.pinned
        }, id, to, before, pin);
        if (r === null)
            return "usage: move <id in the bar, not the tray> left|center|right|overflow [before-id] [pin]";
        for (const k of ["left", "center", "right", "overflow", "pinned"])
            if (JSON.stringify(r[k]) !== JSON.stringify(Config._ids(b[k])))
                Config.setRuntime(["bar", k], r[k]);
        if (persist)
            Quickshell.execDetached([cli, "bar", "move", id, to].concat(before !== "" ? ["--before", before] : [], pin ? ["--pin"] : [], ["--no-apply"]));
        return JSON.stringify(r);
    }

    function noteOverflow(name: string, state: var): void {
        const next = Object.assign({}, overflowState);
        if (state === null)
            delete next[name];
        else
            next[name] = state;
        overflowState = next;
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
                id: screenBar

                function report(): void {
                    shell.noteOverflow(screenScope.modelData.name, {
                        ids: screenBar.overflowShown,
                        open: screenBar.overflowOpen,
                        arranging: screenBar.arranging
                    });
                }

                screen: screenScope.modelData
                hidden: shell.barHidden
                transparent: barText.active
                onTransparencyToggleRequested: shell.setTransparent("toggle")
                onWidgetPressed: opener => shell.barPress = opener
                onOverflowEditRequested: (verb, id) => shell.editOverflow(verb, id, true)
                onMoveRequested: (id, to, before, pin) => shell.moveWidget(id, to, before, pin, true)
                onPositionRequested: pos => shell.setPosition(pos)
                onOverflowShownChanged: report()
                onOverflowOpenChanged: report()
                onArrangingChanged: report()
                Component.onCompleted: report()
                Component.onDestruction: shell.noteOverflow(screenScope.modelData.name, null)

                Connections {
                    target: shell

                    function onArrangeRequested(name: string, on: bool): void {
                        if (name === screenScope.modelData.name)
                            screenBar.setArranging(on);
                    }
                }
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
                opener: shell.panelOpener
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

        // `haseen menu select`: open the menu as a pick list on REQUEST (a
        // JSON file). Answers this shell's PID, so the waiting caller can
        // tell a shell that died from a user still choosing.
        function select(request: string): string {
            if (!Plugins.callRole("menu", "pick", [request])) {
                shell.routeRole("menu", "toggle");
                Qt.callLater(() => Plugins.callRole("menu", "pick", [request]));
            }
            return String(Quickshell.processId);
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
            return shell.setPosition(pos);
        }

        function tray(mode: string): string {
            const want = shell.onOff(mode, Plugins.settingsFor("haseen.tray").pinned === true);
            if (want === null)
                return "usage: tray pin|unpin|toggle";
            shell.applySetting(["plugins", "haseen.tray", "settings", "pinned"], want, ["bar", "tray", want ? "pin" : "unpin"]);
            return want ? "pinned" : "unpinned";
        }

        // add|remove|pin|unpin <id>; `haseen bar overflow` calls it after
        // saving, so it never saves again.
        function overflow(verb: string, id: string): string {
            return shell.editOverflow(verb, id, false);
        }

        // `haseen bar move` calls it after saving, so it never saves again.
        function move(id: string, to: string, before: string, pin: bool): string {
            return shell.moveWidget(id, to, before, pin, false);
        }

        // Arrange mode on the focused screen's bar: on|off|toggle. Session
        // only, like toggle().
        function arrange(mode: string): string {
            const s = shell.focusedScreen();
            const name = s ? s.name : "";
            const state = shell.overflowState[name];
            const want = shell.onOff(mode, !!(state && state.arranging));
            if (want === null || name === "")
                return "usage: arrange on|off|toggle";
            shell.arrangeRequested(name, want);
            return want ? "arranging" : "done";
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
                trayPinned: Plugins.settingsFor("haseen.tray").pinned === true,
                overflow: shell.overflowState
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
