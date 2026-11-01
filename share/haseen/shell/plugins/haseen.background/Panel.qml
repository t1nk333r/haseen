import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// haseen.background: the current theme's backgrounds in Omarchy's carousel
// (SkewCarousel, plan 152): the one on screen selected in the middle, the
// others as slanted slices beside it, over the desktop with no dim.
// Left/Right (or Tab) move, Enter or a click on the selected one runs
// `haseen theme bg set`, a click on another slice selects it, `n` runs
// `haseen theme bg next`; Escape or a click away from the picker closes it.
// Open with `haseen shell ipc panel toggle haseen.background`.
//
// Adapted from Omarchy shell/plugins/background and image-picker
// (MIT, Copyright (c) David Heinemeier Hansson). Omarchy's background plugin
// both *draws* the wallpaper and opens a switcher for it. haseen keeps the
// drawing where it already is: swaybg under haseen-background.service
// (bin/haseen-theme-bg-run), fed by the current/background symlink that
// `haseen theme bg set|next` moves. This plugin is only the picker over that
// same state — it paints no wallpaper, it starts no daemon, and every change
// goes through the CLI, so the shell and a terminal always agree.
//
// Nothing runs until the panel opens: one `haseen theme bg list`, one
// `haseen theme bg current`, then one asynchronous decode, at the selected
// item's size, per slice on screen or next to it.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    property var backgrounds: []
    property string current: ""
    property string themeName: ""
    property string notice: ""
    // The list from `bg list`, shown once `bg current` says which is on
    // screen, so the carousel opens on it instead of moving there.
    property var listed: []
    property bool shown: false

    function nameOf(path: string): string {
        return String(path || "").split("/").pop();
    }

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function apply(index: int): void {
        const path = backgrounds[index];
        if (!path)
            return;
        Quickshell.execDetached([cli, "theme", "bg", "set", path]);
        close();
    }

    // The CLI picks the next background and restarts the unit; the panel only
    // asks what it landed on, so the selection follows without a watcher.
    function next(): void {
        if (!nextProc.running)
            nextProc.running = true;
    }

    function selectPath(path: string): void {
        const i = backgrounds.indexOf(path);
        if (i >= 0)
            carousel.currentIndex = i;
    }

    implicitWidth: carousel.implicitWidth
    implicitHeight: carousel.implicitHeight

    // The carousel passes on the keys it does not use.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_N && event.modifiers === Qt.NoModifier) {
            root.next();
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        listProc.running = true;
        carousel.forceActiveFocus();
    }

    // Test hook (settings.debugIpc): move, inspect and accept over IPC while
    // the panel is open, so a smoke test never injects keys into the session.
    IpcHandler {
        target: "haseen.background"
        enabled: root.settings.debugIpc === true

        function select(name: string): void {
            for (const path of root.backgrounds) {
                if (root.nameOf(path) === name) {
                    root.selectPath(path);
                    return;
                }
            }
        }

        function move(direction: string): void {
            if (direction === "left" || direction === "right")
                carousel.move(direction === "left" ? -1 : 1);
        }

        function accept(): void {
            root.apply(carousel.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                theme: root.themeName,
                count: root.backgrounds.length,
                current: root.current,
                selected: root.backgrounds[carousel.currentIndex] || "",
                notice: root.notice
            });
        }
    }

    // The theme's backgrounds, in the CLI's own order (user dir, the theme's
    // own, then the fetched cache), so `next` and this carousel agree.
    Process {
        id: listProc

        command: [root.cli, "theme", "bg", "list"]
        stdout: StdioCollector {
            id: listOut
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: code => {
            if (code !== 0) {
                root.notice = listErr.text.trim() || I18n.tr("haseen theme bg list failed");
                return;
            }
            root.listed = listOut.text.split("\n").filter(l => l.trim() !== "");
            if (root.listed.length === 0)
                root.notice = I18n.tr("no backgrounds yet · haseen theme fetch");
            currentProc.running = true;
        }
    }

    // `haseen theme bg current` reads the symlink swaybg was started on. It
    // exits 1 with no background set, which is a state, not a failure.
    Process {
        id: currentProc

        command: [root.cli, "theme", "bg", "current"]
        stdout: StdioCollector {
            id: currentOut
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.current = code === 0 ? currentOut.text.trim() : "";
            if (!root.shown) {
                root.shown = true;
                root.backgrounds = root.listed;
                carousel.currentIndex = root.backgrounds.length > 0 ? 0 : -1;
            }
            root.selectPath(root.current);
        }
    }

    Process {
        id: nextProc

        command: [root.cli, "theme", "bg", "next"]
        stderr: StdioCollector {
            id: nextErr
        }
        onExited: code => {
            if (code !== 0)
                root.notice = nextErr.text.trim() || I18n.tr("haseen theme bg next failed");
            else
                currentProc.running = true;
        }
    }

    // A fresh install has no theme yet; that is not worth a log line.
    FileView {
        path: Paths.userState + "/current/theme.name"
        printErrors: false
        onLoaded: root.themeName = text().trim()
    }

    // A click away from the picker closes it; the carousel's card takes its
    // own clicks.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    SkewCarousel {
        id: carousel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        screen: root.screen
        names: root.backgrounds
        notice: root.notice
        onActivated: index => root.apply(index)
        onDismissed: root.close()

        // One background, decoded at the selected item's size whichever
        // slice shows it, so selecting a slice never decodes it again: a 4K
        // wallpaper costs that size, not 4K. The theme's background colour
        // fills the slice until the decode lands.
        slice: Component {
            Item {
                id: picture

                // The Loader holding it carries the model index.
                readonly property string path: root.backgrounds[parent ? parent.modelIndex : -1] || ""

                Rectangle {
                    anchors.fill: parent
                    color: Theme.background
                }

                Image {
                    anchors.fill: parent
                    source: picture.path !== "" ? Paths.fileUrl(picture.path) : ""
                    sourceSize.width: Math.round(carousel.geometry.expandedWidth * carousel.pixelRatio)
                    sourceSize.height: Math.round(carousel.geometry.expandedHeight * carousel.pixelRatio)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }
        }
    }
}
