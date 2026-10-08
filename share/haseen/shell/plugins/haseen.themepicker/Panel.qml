import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen

// haseen.themepicker: every theme `haseen theme list` knows, as a grid of
// previews. Arrows (or Tab) move, Enter or a click runs `haseen theme set`
// and closes; Escape closes (the panel host handles it). A theme without a
// preview shows its palette; `haseen theme fetch --all` caches the Omarchy
// previews. Open with `haseen shell ipc panel toggle haseen.themepicker`.
//
// Nothing runs until the panel opens: one `find` for the user themes' files
// and the cached previews, one `haseen theme list`, then one colors.toml
// read and one asynchronous, thumbnail-sized decode per card.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property string userThemes: Paths.userConfig + "/themes"
    readonly property string cacheDir: (Quickshell.env("HASEEN_USER_CACHE") || (Quickshell.env("XDG_CACHE_HOME") || Paths.home + "/.cache") + "/haseen") + "/themes"
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 4
    readonly property int rows: typeof settings.rows === "number" && settings.rows >= 1 ? Math.round(settings.rows) : 3
    readonly property int cardWidth: Theme.fontSize * 16
    readonly property int cellWidth: cardWidth + Theme.gap * 2
    readonly property int cellHeight: Math.round(cardWidth * 9 / 16) + Theme.fontSize * 2 + Theme.gap * 2

    property var themes: []
    property string currentTheme: ""
    property string notice: ""
    // name -> preview path: a user theme's own preview.png, else the fetched
    // preview-thumb.png, else the fetched preview.png (rank: lower wins).
    // And the user themes that ship their own colors.toml.
    property var previewOf: ({})
    property var userColours: ({})

    function colorFileFor(name: string): string {
        return (userColours[name] ? userThemes : Paths.haseenPath + "/themes") + "/" + name + "/colors.toml";
    }

    // One path per line from scanProc.
    function indexFiles(text: string): void {
        const previews = {};
        const rank = {};
        const colours = {};
        for (const path of text.split("\n")) {
            const parts = path.split("/");
            if (parts.length < 3)
                continue;
            const name = parts[parts.length - 2];
            const file = parts[parts.length - 1];
            const fromUser = path.startsWith(userThemes + "/");
            if (file === "colors.toml") {
                if (fromUser)
                    colours[name] = true;
                continue;
            }
            const r = fromUser ? (file === "preview.png" ? 0 : 3) : (file === "preview-thumb.png" ? 1 : 2);
            if (rank[name] === undefined || r < rank[name]) {
                rank[name] = r;
                previews[name] = path;
            }
        }
        previewOf = previews;
        userColours = colours;
    }

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function apply(index: int): void {
        const name = themes[index];
        if (!name)
            return;
        Quickshell.execDetached([cli, "theme", "set", name]);
        close();
    }

    function selectName(name: string): void {
        const i = themes.indexOf(name);
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

    Component.onCompleted: {
        scanProc.running = true;
        grid.forceActiveFocus();
    }

    // Test hook (settings.debugIpc): move, inspect and accept over IPC while
    // the panel is open, so a smoke test never injects keys into the session.
    IpcHandler {
        target: "haseen.themepicker"
        enabled: root.settings.debugIpc === true

        function select(name: string): void {
            root.selectName(name);
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
            const cards = [];
            for (let i = 0; i < grid.count; i++) {
                const item = grid.itemAtIndex(i);
                if (item)
                    cards.push(item.name + (item.hasPreview ? ":preview" : ":palette"));
            }
            return JSON.stringify({
                current: root.themes[grid.currentIndex] || "",
                active: root.currentTheme,
                count: root.themes.length,
                loaded: cards,
                notice: root.notice
            });
        }
    }

    // Existing files only, so no card asks for an image or colors.toml that
    // is not there. A missing directory makes find exit 1; its output still
    // counts. The list starts after it, so every card is created once with
    // its final paths.
    Process {
        id: scanProc

        command: ["find", "-L", root.userThemes, root.cacheDir, "-mindepth", "2", "-maxdepth", "2", "(", "-name", "preview.png", "-o", "-name", "preview-thumb.png", "-o", "-name", "colors.toml", ")", "-type", "f", "-print"]
        stdout: StdioCollector {
            id: scanOut
        }
        // "No such file or directory" for an absent dir: expected, not news.
        stderr: StdioCollector {}
        onExited: {
            root.indexFiles(scanOut.text);
            listProc.running = true;
        }
    }

    Process {
        id: listProc

        command: [root.cli, "theme", "list"]
        stdout: StdioCollector {
            id: listOut
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: code => {
            if (code !== 0) {
                root.notice = listErr.text.trim() || "haseen theme list failed";
                return;
            }
            root.themes = listOut.text.split("\n").filter(l => l.trim() !== "");
            Qt.callLater(() => {
                root.selectName(root.currentTheme);
                grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
            });
        }
    }

    FileView {
        path: Paths.userState + "/current/theme.name"
        onLoaded: root.currentTheme = text().trim()
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: "Themes"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            text: root.notice !== "" ? root.notice : "Enter applies · Esc closes"
            color: root.notice !== "" ? Theme.urgent : Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    GridView {
        id: grid

        width: root.columns * root.cellWidth
        height: Math.max(1, Math.min(Math.ceil(root.themes.length / root.columns), root.rows)) * root.cellHeight
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        clip: true
        focus: true
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        model: root.themes

        delegate: Item {
            id: cell

            required property string modelData
            required property int index

            readonly property string name: modelData
            readonly property bool hasPreview: card.hasPreview

            width: root.cellWidth
            height: root.cellHeight

            ThemeCard {
                id: card

                x: Theme.gap
                y: Theme.gap
                width: root.cardWidth
                name: cell.modelData
                previewPath: root.previewOf[cell.modelData] || ""
                colorFile: root.colorFileFor(cell.modelData)
                selected: cell.GridView.isCurrentItem
                active: root.currentTheme === cell.modelData
                pixelRatio: root.screen && root.screen.devicePixelRatio ? root.screen.devicePixelRatio : 1
                onHovered: grid.currentIndex = cell.index
                onPicked: root.apply(cell.index)
            }
        }
    }
}
