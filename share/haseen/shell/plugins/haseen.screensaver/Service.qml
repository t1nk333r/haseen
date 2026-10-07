import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Haseen

// haseen.screensaver: answers the `screensaver` role (haseen.idle calls
// start() after screensaverAfter, dismiss() on input) and the `screensaver`
// IPC target (`haseen screensaver`, start(style)).
//
// ttfx (default): Omarchy's screensaver, ported in bin/haseen-screensaver.
//   `--ttfx-launch` opens a fullscreen terminal running ttfx on every
//   monitor, each on a special workspace; a key press or a focus change in
//   one of them closes them all. The terminals are Hyprland clients, not
//   children of the shell, so they are followed through Hyprland's
//   openwindow/closewindow events, and `--stop` closes them. Without ttfx
//   or a supported terminal it falls back to native.
// native: one overlay per screen with a clock and the branding text (default
//   the selected mark's logo, Branding.logoPath; or the user's text or
//   image) on the theme background. The card moves a few pixels every 2 s
//   (Drift.js); there is no animation between steps, so the cost is one
//   small repaint per tick.
//
// Any input ends it: keys and clicks reach the overlay or the terminals
// directly, and pointer motion is caught by a 1 s ext-idle-notify monitor
// that arms once the user has been still for a second (so the key release
// of the keybind that started it does not end it at once). Nothing here
// locks the session; the windows, the monitor and the 2 s tick exist only
// while it is shown.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string appId: "org.haseen.screensaver"
    readonly property string defaultStyle: settings.style === "native" ? "native" : "ttfx"
    readonly property string clockFormat: typeof settings.clockFormat === "string" && settings.clockFormat !== "" ? settings.clockFormat : "HH:mm"
    readonly property string command: Paths.haseenPath + "/../../bin/haseen-screensaver"

    property bool active: false
    property string style: "native"
    property bool _armed: false
    property int tick: 0
    property int phase: 0
    property date now: new Date()
    // ttfx: addresses of the mapped screensaver terminals, and the monitor
    // that had focus before (the last terminal to close takes focus along).
    property var _windows: ({})
    property int _windowCount: 0
    property string _focusedMonitor: ""
    readonly property int windowCount: !active ? 0 : (style === "ttfx" ? _windowCount : Quickshell.screens.length)

    // The idle path: honours the screensaver-off flag.
    function start(): void {
        if (Flags.screensaverOff)
            return;
        show("default");
    }

    // The IPC path (`haseen screensaver` checks the flag itself, --force
    // skips it). requested: ttfx, native, or anything else for the setting.
    function show(requested: string): void {
        if (active || _locked())
            return;
        style = requested === "native" || requested === "ttfx" ? requested : defaultStyle;
        _armed = false;
        tick = 0;
        phase = Math.floor(Math.random() * 100000);
        now = new Date();
        _windows = {};
        _windowCount = 0;
        if (style === "ttfx") {
            const mon = Hyprland.focusedMonitor;
            _focusedMonitor = mon ? mon.name : "";
            launcher.running = true;
        }
        active = true;
    }

    function dismiss(): void {
        if (!active)
            return;
        active = false;
        if (style === "ttfx") {
            if (launcher.running)
                launcher.running = false;
            if (_windowCount > 0)
                Quickshell.execDetached([command, "--stop"]);
        }
    }

    function _fallBack(reason: string): void {
        Plugins.warnOnce(pluginId + ":ttfx:" + reason, "haseen.screensaver: ttfx style unavailable (" + reason + "), showing the native screensaver");
        style = "native";
    }

    function _locked(): bool {
        const entry = Plugins.roles.lock;
        return !!(entry && entry.instance && entry.instance.locked === true);
    }

    function _windowEvent(name: string, data: string): void {
        if (name === "openwindow") {
            // ADDRESS,WORKSPACE,CLASS,TITLE
            const parts = data.split(",");
            if (parts.length < 3 || parts[2] !== appId)
                return;
            const w = Object.assign({}, _windows);
            w[parts[0]] = true;
            _windows = w;
            _windowCount = Object.keys(w).length;
            // Mapped after a dismissal raced the launcher: close it too.
            if (!active)
                Quickshell.execDetached([command, "--stop"]);
        } else if (name === "closewindow") {
            if (!_windows[data])
                return;
            const w = Object.assign({}, _windows);
            delete w[data];
            _windows = w;
            _windowCount = Object.keys(w).length;
            if (_windowCount === 0)
                _allClosed();
        }
    }

    function _allClosed(): void {
        if (_focusedMonitor !== "")
            Hyprland.dispatch("hl.dsp.focus({ monitor = \"" + _focusedMonitor + "\" })");
        if (active && style === "ttfx")
            active = false;
    }

    function stateJson(): string {
        return JSON.stringify({
            active: active,
            style: style,
            terminals: _windowCount,
            launcherRunning: launcher.running,
            armed: _armed,
            tick: tick,
            screensaverOff: Flags.screensaverOff
        });
    }

    Connections {
        target: Hyprland
        enabled: root._windowCount > 0 || launcher.running || (root.active && root.style === "ttfx")

        function onRawEvent(event: var): void {
            root._windowEvent(event.name, event.data);
        }
    }

    Process {
        id: launcher

        command: [root.command, "--ttfx-launch"]
        stderr: StdioCollector {
            id: launcherErr
        }
        onExited: code => {
            if (!root.active || root.style !== "ttfx")
                return;
            if (code !== 0)
                root._fallBack(launcherErr.text.trim() || "exit " + code);
            else if (root._windowCount === 0)
                noWindow.restart();
        }
    }

    // The launcher waits for each terminal to map, so its windows are known
    // by the time it exits; none after this grace means none will come.
    // haseen:ui-timeout
    Timer {
        id: noWindow

        interval: 2000
        repeat: false
        onTriggered: {
            if (root.active && root.style === "ttfx" && root._windowCount === 0)
                root._fallBack("no terminal appeared");
        }
    }

    // A fresh monitor per show, never re-enabled in place (see the
    // IdleMonitor note in haseen.idle/Service.qml).
    LazyLoader {
        active: root.active

        IdleMonitor {
            timeout: 1
            respectInhibitors: false
            onIsIdleChanged: {
                if (isIdle)
                    root._armed = true;
                else if (root._armed)
                    root.dismiss();
            }
        }
    }

    // The native clock and drift step; runs only while it is shown.
    // haseen:sample
    Timer {
        interval: 2000
        repeat: true
        running: root.active && root.style === "native"
        onTriggered: {
            root.tick++;
            root.now = new Date();
        }
    }

    LazyLoader {
        active: root.active && root.style === "native"

        Scope {
            FileView {
                id: userText

                path: Paths.userConfig + "/branding/screensaver.txt"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
            }

            // The selected mark's terminal logo (`haseen branding mark`).
            FileView {
                id: defaultText

                path: Branding.logoPath
                printErrors: false
            }

            FileView {
                id: userImage

                path: Paths.userConfig + "/branding/screensaver.png"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
            }

            Variants {
                model: Quickshell.screens

                PanelWindow {
                    required property var modelData

                    screen: modelData
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    exclusionMode: ExclusionMode.Ignore
                    color: Theme.background
                    WlrLayershell.namespace: "haseen-screensaver"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                    View {
                        anchors.fill: parent
                        clock: Qt.formatTime(root.now, root.clockFormat)
                        date: Qt.formatDate(root.now, "dddd, d MMMM")
                        branding: {
                            const t = userText.loaded ? userText.text() : "";
                            return t.trim() !== "" ? t : (defaultText.loaded ? defaultText.text() : "");
                        }
                        image: userImage.loaded ? Paths.fileUrl(userImage.path) : ""
                        tick: root.tick
                        phase: root.phase
                        onInput: root.dismiss()
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "screensaver"

        // style: ttfx, native, or "default" for the style setting.
        function start(style: string): void {
            root.show(style);
        }
    }

    // Test hook (settings.debugIpc): end the screensaver and read its state
    // without input, and exercise the idle path (`startIdle` honours the
    // screensaver-off flag like haseen.idle does).
    IpcHandler {
        target: "haseen.screensaver"
        enabled: root.settings.debugIpc === true

        function dismiss(): void {
            root.dismiss();
        }

        function startIdle(): void {
            root.start();
        }

        function state(): string {
            return root.stateJson();
        }
    }
}
