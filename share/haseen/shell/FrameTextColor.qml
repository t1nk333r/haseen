import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen

// Text colour for the transparent bar (plan 015). Port of Omarchy's
// refreshTransparentForeground (shell/plugins/bar/Bar.qml, MIT, Copyright (c)
// David Heinemeier Hansson): haseen-bar-text-color samples the wallpaper
// under the bar and answers whichever of the theme foreground and background
// reads better on it. The answer goes to Theme.barForeground, which every bar
// widget uses for its normal text.
//
// Omarchy samples ~/.local/state/omarchy/current/background, the symlink its
// background switcher points at the wallpaper; haseen's is
// $HASEEN_USER_STATE/current/background, kept the same way by
// `haseen theme bg`. Nothing polls: a run follows a change of transparency,
// bar position or size, theme colours, screen size, or the current/ directory
// (where the theme and background links are swapped). Like Omarchy, one
// sample serves every screen.
Scope {
    id: root

    // The screen whose size the sample assumes.
    property var screen: null
    readonly property bool requested: Config.barTransparent
    // True once a colour for the current request has landed. The bar turns
    // transparent only then, so its text never flashes unreadable.
    property bool active: false

    readonly property string script: Paths.haseenPath + "/../../bin/haseen-bar-text-color"
    readonly property string _inputs: [requested, Config.barPosition, Config.barThickness, hex(Theme.foreground), hex(Theme.background), screen ? screen.width : 0, screen ? screen.height : 0].join(" ")
    property bool _again: false
    property bool _answered: false

    function hex(c: color): string {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    function schedule(): void {
        if (!requested) {
            active = false;
            Theme.barForeground = Qt.binding(() => Theme.foreground);
            return;
        }
        Qt.callLater(run);
    }

    function run(): void {
        if (!requested)
            return;
        if (proc.running) {
            _again = true;
            return;
        }
        const args = [script, Config.barPosition, String(Config.barThickness), hex(Theme.foreground), hex(Theme.background)];
        if (screen)
            args.push("--screen", screen.width + "x" + screen.height);
        proc.command = args;
        _answered = false;
        proc.running = true;
    }

    on_InputsChanged: schedule()
    Component.onCompleted: schedule()

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => {
                const value = String(line || "").trim();
                if (!/^#[0-9A-Fa-f]{6}$/.test(value) || !root.requested)
                    return;
                root._answered = true;
                Theme.barForeground = value;
                root.active = true;
            }
        }
        onExited: {
            // A missing or failing helper still lets the bar go transparent,
            // with the theme's own foreground (the script's fallback answer).
            if (!root._answered && root.requested) {
                Theme.barForeground = Theme.foreground;
                root.active = true;
            }
            if (root._again) {
                root._again = false;
                root.run();
            }
        }
    }

    // A directory watch sees the symlink swaps; watching the image itself
    // would make FileView read the whole wallpaper into memory.
    FileView {
        path: root.requested ? Paths.userState + "/current" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: root.schedule()
    }
}
