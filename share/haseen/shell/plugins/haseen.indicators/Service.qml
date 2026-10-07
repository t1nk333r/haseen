import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Indicators.js" as Logic

// The game context's watcher (plan 062), off by default: it runs only while
// settings.gameClasses lists a pattern (`haseen context auto-game on|set`,
// which also lists this service). While a fullscreen window whose class
// matches has focus, it enters the game context; when that window loses
// focus or fullscreen, it leaves. Both go through `haseen context … --auto`,
// which never replaces a context picked by hand and leaves only a game it
// entered itself. Hyprland events drive it; nothing is polled.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var patterns: Logic.gamePatterns(settings.gameClasses)
    readonly property bool watching: patterns.length > 0
    // A matching fullscreen window has focus.
    property bool gameFocused: false
    property bool _decided: false

    function evaluate(): void {
        if (!watching) {
            gameFocused = false;
            return;
        }
        const w = Hyprland.activeToplevel;
        const ipc = w && w.lastIpcObject ? w.lastIpcObject : {};
        let appClass = String(ipc["class"] || "");
        if (appClass === "" && w && w.wayland)
            appClass = String(w.wayland.appId || "");
        const game = Logic.isGame(patterns, appClass, ipc.fullscreen);
        // The first answer after a shell restart: a game this watcher entered
        // before may have closed meanwhile (normal --auto leaves only that).
        if (!_decided && !game)
            Quickshell.execDetached(["haseen", "context", "normal", "--auto"]);
        _decided = true;
        gameFocused = game;
    }

    onGameFocusedChanged: Quickshell.execDetached(["haseen", "context", gameFocused ? "game" : "normal", "--auto"])
    onWatchingChanged: refresh.restart()
    Component.onCompleted: {
        if (watching)
            refresh.restart();
    }

    Connections {
        target: Hyprland
        enabled: root.watching

        function onRawEvent(event: var): void {
            switch (event.name) {
            case "fullscreen":
            case "activewindowv2":
            case "closewindow":
            case "workspacev2":
            case "focusedmonv2":
                refresh.restart();
            }
        }
    }

    // A game going fullscreen sends a burst of events: refresh the windows
    // once, then decide when the IPC answer has landed (as haseen.pager does).
    // haseen:ui-timeout
    Timer {
        id: refresh

        interval: 100
        repeat: false
        onTriggered: {
            Hyprland.refreshToplevels();
            settle.restart();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: settle

        interval: 250
        repeat: false
        onTriggered: root.evaluate()
    }
}
