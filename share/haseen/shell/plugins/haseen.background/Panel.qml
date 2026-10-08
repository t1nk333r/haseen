import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen

// haseen.background: the current theme's backgrounds as a grid, the one on
// screen marked. Arrows (or Tab) move, Enter or a click runs
// `haseen theme bg set`, `n` runs `haseen theme bg next`; Escape closes (the
// panel host handles it). Open with
// `haseen shell ipc panel toggle haseen.background`.
//
// Adapted from Omarchy shell/plugins/background (MIT, Copyright (c) David
// Heinemeier Hansson), which both *draws* the wallpaper and opens a switcher
// for it. haseen keeps the drawing where it already is: swaybg under
// haseen-background.service (bin/haseen-theme-bg-run), fed by the
// current/background symlink that `haseen theme bg set|next` moves. This
// plugin is only the picker over that same state — it paints no wallpaper, it
// starts no daemon, and every change goes through the CLI, so the shell and a
// terminal always agree.
//
// Nothing runs until the panel opens: one `haseen theme bg list`, one
// `haseen theme bg current`, then one asynchronous, thumbnail-sized decode
// per visible card.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 3
    readonly property int rows: typeof settings.rows === "number" && settings.rows >= 1 ? Math.round(settings.rows) : 2
    readonly property int cardWidth: Theme.fontSize * 15
    readonly property int cellWidth: cardWidth + Theme.gap * 2
    readonly property int cellHeight: Math.round(cardWidth * 9 / 16) + Theme.fontSize * 2 + Theme.gap * 2

    property var backgrounds: []
    property string current: ""
    property string themeName: ""
    property string notice: ""

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
    // asks what it landed on, so the mark follows without a watcher.
    function next(): void {
        if (!nextProc.running)
            nextProc.running = true;
    }

    function selectPath(path: string): void {
        const i = backgrounds.indexOf(path);
        if (i >= 0)
            grid.currentIndex = i;
    }

    width: columns * cellWidth
    spacing: Theme.gap
    focus: true

    // Enter applies the highlighted cell. A window shortcut, not a key handler
    // on this item: the grid cell that holds focus took the press before it
    // could propagate here, so Enter did nothing (io, plan 050).
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.WindowShortcut
        onActivated: root.apply(grid.currentIndex)
    }
    Keys.onTabPressed: grid.moveCurrentIndexRight()
    Keys.onBacktabPressed: grid.moveCurrentIndexLeft()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_N) {
            root.next();
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        listProc.running = true;
        grid.forceActiveFocus();
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
            switch (direction) {
            case "left":
                grid.moveCurrentIndexLeft();
                break;
            case "right":
                grid.moveCurrentIndexRight();
                break;
            case "up":
                grid.moveCurrentIndexUp();
                break;
            case "down":
                grid.moveCurrentIndexDown();
                break;
            }
        }

        function accept(): void {
            root.apply(grid.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                theme: root.themeName,
                count: root.backgrounds.length,
                current: root.current,
                selected: root.backgrounds[grid.currentIndex] || "",
                notice: root.notice
            });
        }
    }

    // The theme's backgrounds, in the CLI's own order (user dir, the theme's
    // own, then the fetched cache), so `next` and this grid agree.
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
                root.notice = listErr.text.trim() || "haseen theme bg list failed";
                return;
            }
            root.backgrounds = listOut.text.split("\n").filter(l => l.trim() !== "");
            if (root.backgrounds.length === 0)
                root.notice = "no backgrounds yet · haseen theme fetch";
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
            Qt.callLater(() => {
                root.selectPath(root.current);
                grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
            });
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
                root.notice = nextErr.text.trim() || "haseen theme bg next failed";
            else
                currentProc.running = true;
        }
    }

    FileView {
        path: Paths.userState + "/current/theme.name"
        onLoaded: root.themeName = text().trim()
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: root.themeName !== "" ? "Background · " + root.themeName : "Background"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: root.notice !== "" ? root.notice : "Enter applies · n next · Esc closes"
            color: root.notice !== "" ? Theme.urgent : Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    GridView {
        id: grid

        width: root.columns * root.cellWidth
        height: Math.max(1, Math.min(Math.ceil(root.backgrounds.length / root.columns), root.rows)) * root.cellHeight
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        clip: true
        focus: true
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        model: root.backgrounds

        delegate: Item {
            id: cell

            required property string modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            BackgroundCard {
                x: Theme.gap
                y: Theme.gap
                width: root.cardWidth
                path: cell.modelData
                label: root.nameOf(cell.modelData)
                selected: cell.GridView.isCurrentItem
                active: root.current === cell.modelData
                pixelRatio: root.screen && root.screen.devicePixelRatio ? root.screen.devicePixelRatio : 1
                onHovered: grid.currentIndex = cell.index
                onPicked: root.apply(cell.index)
            }
        }
    }
}
