import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// haseen.themepicker: every theme `haseen theme list` knows, in Omarchy's
// theme switcher (its image-picker carousel with labels and a filter, MIT,
// Copyright (c) David Heinemeier Hansson; SkewCarousel, plan 152): the
// current theme selected in the middle, the others as slanted slices beside
// it, its name under it, over the desktop with no dim. Left/Right (or Tab)
// move, typing filters by name, Enter or a click on the selected one runs
// `haseen theme set` and closes, a click on another slice selects it;
// Escape clears the filter, then closes, as does a click away from the
// picker. A theme without a preview shows its palette; `haseen theme fetch
// --all` caches the Omarchy previews. Open with
// `haseen shell ipc panel toggle haseen.themepicker`.
//
// Nothing runs until the panel opens: one `find` for the user themes' files
// and the cached previews, one `haseen theme list`, then one colors.toml
// read and one asynchronous decode, at the selected item's size, per slice
// on screen or next to it.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property string userThemes: Paths.userConfig + "/themes"
    readonly property string cacheDir: (Quickshell.env("HASEEN_USER_CACHE") || (Quickshell.env("XDG_CACHE_HOME") || Paths.home + "/.cache") + "/haseen") + "/themes"

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
            carousel.currentIndex = i;
    }

    implicitWidth: carousel.implicitWidth
    implicitHeight: carousel.implicitHeight

    Component.onCompleted: {
        scanProc.running = true;
        carousel.forceActiveFocus();
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
            if (direction === "left" || direction === "right")
                carousel.move(direction === "left" ? -1 : 1);
        }

        function filter(text: string): void {
            carousel.setFilter(text);
        }

        function accept(): void {
            if (carousel.hasSelection)
                root.apply(carousel.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                current: carousel.hasSelection ? root.themes[carousel.currentIndex] : "",
                active: root.currentTheme,
                count: root.themes.length,
                shown: carousel.shown.length,
                filter: carousel.filterText,
                cards: root.themes.map(n => n + (root.previewOf[n] ? ":preview" : ":palette")),
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
                root.notice = listErr.text.trim() || I18n.tr("haseen theme list failed");
                return;
            }
            root.themes = listOut.text.split("\n").filter(l => l.trim() !== "");
            carousel.currentIndex = root.themes.length > 0 ? 0 : -1;
            root.selectName(root.currentTheme);
        }
    }

    // A fresh install has no theme yet; that is not worth a log line. Read
    // before the list arrives, as a rule; when it lands later, the picker
    // still opens on it.
    FileView {
        path: Paths.userState + "/current/theme.name"
        printErrors: false
        onLoaded: {
            root.currentTheme = text().trim();
            root.selectName(root.currentTheme);
        }
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
        names: root.themes
        showLabels: true
        filterable: true
        notice: root.notice
        onActivated: index => root.apply(index)
        onDismissed: root.close()

        slice: Component {
            ThemePreview {
                // The Loader holding it carries the model index.
                name: root.themes[parent ? parent.modelIndex : -1] || ""
                previewPath: root.previewOf[name] || ""
                colorFile: name !== "" ? root.colorFileFor(name) : ""
                decodeWidth: Math.round(carousel.geometry.expandedWidth * carousel.pixelRatio)
                decodeHeight: Math.round(carousel.geometry.expandedHeight * carousel.pixelRatio)
            }
        }
    }
}
