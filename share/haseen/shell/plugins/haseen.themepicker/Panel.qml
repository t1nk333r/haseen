import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Previews.js" as Previews

// haseen.themepicker: every theme that `haseen theme list` knows, in
// Omarchy's theme switcher (SkewCarousel, plan 152), over the desktop with
// no dim. Omarchy's switcher is its image-picker carousel with labels and a
// filter (MIT, Copyright (c) David Heinemeier Hansson). The current theme
// is selected in the middle with its name under it, and the others are
// slanted slices beside it. Left and Right, or Tab, move the selection, and
// typing filters by name. Enter, or a click on the selected slice, runs
// `haseen theme set` and closes the picker. A click on another slice
// selects it. Escape clears the filter, and a second Escape closes the
// picker. A click away from the picker also closes it. Each theme shows the
// picture Omarchy's switcher shows (Previews.js, plan 158): its preview,
// else its first background, from the user's theme, then the previews
// `haseen theme fetch` cached, then the installed Omarchy's own themes. A
// theme with no picture anywhere shows its palette.
// Open it with `haseen shell ipc panel toggle haseen.themepicker`.
//
// Nothing runs until the panel opens. Then one `find` lists the theme files
// in the three places, and `haseen theme list` runs once.
// Each slice on screen or next to it reads one colors.toml and decodes one
// picture at the selected item's size.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // The haseen command next to share/haseen, in a checkout, /usr/local or
    // /usr.
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property string userThemes: Paths.userConfig + "/themes"
    readonly property string cacheDir: (Quickshell.env("HASEEN_USER_CACHE") || (Quickshell.env("XDG_CACHE_HOME") || Paths.home + "/.cache") + "/haseen") + "/themes"
    // The installed Omarchy's stock themes, each with its preview.png and
    // backgrounds. haseen reads them and never ships or copies them.
    readonly property string omarchyThemes: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/themes"

    property var themes: []
    property string currentTheme: ""
    property string notice: ""
    // previewOf maps a theme name to the picture it shows. userColours
    // lists the user themes that ship their own colors.toml.
    property var previewOf: ({})
    property var userColours: ({})

    function colorFileFor(name: string): string {
        return (userColours[name] ? userThemes : Paths.haseenPath + "/themes") + "/" + name + "/colors.toml";
    }

    // Reads scanProc's output, one path per line.
    function indexFiles(text: string): void {
        const found = Previews.index(text, {
            user: userThemes,
            cache: cacheDir,
            omarchy: omarchyThemes
        });
        previewOf = found.previews;
        userColours = found.colours;
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

    // A test hook, on with settings.debugIpc. A smoke test moves, inspects
    // and accepts over IPC while the panel is open, so it never sends keys
    // into the session.
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

    // Lists existing files only, so no slice asks for an image or a
    // colors.toml that is not there. A missing directory makes find exit 1,
    // and its output still counts. Previews.js drops what is not a theme's
    // preview, background or colors.toml. The theme list runs after the
    // scan, so every slice is created once, with its final paths.
    Process {
        id: scanProc

        command: ["find", "-L", root.userThemes, root.cacheDir, root.omarchyThemes, "-mindepth", "2", "-maxdepth", "3", "-type", "f", "(", "-iname", "preview.*", "-o", "-name", "colors.toml", "-o", "-path", "*/backgrounds/*", ")", "-print"]
        stdout: StdioCollector {
            id: scanOut
        }
        // find reports "No such file or directory" for an absent directory.
        // That is expected, so the panel drops it.
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

    // A fresh install has no theme yet, so a missing file prints nothing.
    // The file usually loads before the list arrives. If it loads later,
    // the picker still selects the current theme.
    FileView {
        path: Paths.userState + "/current/theme.name"
        printErrors: false
        onLoaded: {
            root.currentTheme = text().trim();
            root.selectName(root.currentTheme);
        }
    }

    // A click away from the picker closes it. The carousel's card takes the
    // clicks that land on it.
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
        // A narrower carousel in a panel card, for the `center` and `bar`
        // placements.
        compact: (root.settings.placement || "overlay") !== "overlay"
        names: root.themes
        showLabels: true
        filterable: true
        notice: root.notice
        onActivated: index => root.apply(index)
        onDismissed: root.close()

        slice: Component {
            ThemePreview {
                // The Loader that holds this item has the model index.
                name: root.themes[parent ? parent.modelIndex : -1] || ""
                previewPath: root.previewOf[name] || ""
                colorFile: name !== "" ? root.colorFileFor(name) : ""
                decodeWidth: Math.round(carousel.geometry.expandedWidth * carousel.pixelRatio)
                decodeHeight: Math.round(carousel.geometry.expandedHeight * carousel.pixelRatio)
            }
        }
    }
}
