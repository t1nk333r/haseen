import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Images.js" as Images

// haseen.imagepicker: the images in a few directories as a grid of thumbnails.
// Type to filter, arrows (or Tab) move, Enter or a click runs the configured
// command with the image's path appended and closes; Escape closes (the panel
// host handles it). Open with
// `haseen shell ipc panel toggle haseen.imagepicker`.
//
// Adapted from Omarchy shell/plugins/image-picker (MIT, Copyright (c) David
// Heinemeier Hansson): a directory of images, picked by name, handed to
// whoever asked for one. haseen drops the overlay, the carousel and the
// thumbnail cache: this is a panel, Qt decodes each visible image once at
// thumbnail size, and the default action is `haseen theme bg set`, so the
// picked image goes through the same background state as the CLI.
//
// Nothing runs until the panel opens: one `find` over the configured
// directories, then one asynchronous decode per visible card.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property var dirs: Images.directories(Array.isArray(settings.directories) && settings.directories.length > 0 ? settings.directories : ["~/Pictures", "~/Pictures/Wallpapers", Paths.userConfig + "/backgrounds"], Paths.home)
    readonly property int depth: typeof settings.depth === "number" && settings.depth >= 1 ? Math.round(settings.depth) : 3
    readonly property int limit: typeof settings.limit === "number" && settings.limit >= 1 ? Math.round(settings.limit) : 400
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 4
    readonly property int rows: typeof settings.rows === "number" && settings.rows >= 1 ? Math.round(settings.rows) : 3
    readonly property bool showLabels: settings.labels !== false
    readonly property int cardWidth: Theme.fontSize * 14
    readonly property int cellWidth: cardWidth + Theme.gap * 2
    readonly property int cellHeight: Math.round(cardWidth * 9 / 16) + (showLabels ? Theme.fontSize * 2 : 0) + Theme.gap * 2

    property var images: []
    property string query: ""
    property string notice: ""
    readonly property var results: Images.filter(images, query)

    // The argv a pick runs, with the image appended. Empty settings.command
    // means the background the CLI and swaybg already agree on.
    function applyCommand(path: string): var {
        const argv = Array.isArray(settings.command) && settings.command.length > 0 ? settings.command.map(a => String(a)) : [cli, "theme", "bg", "set"];
        argv.push(path);
        return argv;
    }

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function apply(index: int): void {
        const image = results[index];
        if (!image)
            return;
        Quickshell.execDetached(applyCommand(image.path));
        close();
    }

    // `step`, not `move`: Column already has a `move` transition property.
    function step(delta: int): void {
        if (results.length === 0)
            return;
        grid.currentIndex = Math.max(0, Math.min(results.length - 1, grid.currentIndex + delta));
    }

    onResultsChanged: grid.currentIndex = 0

    width: columns * cellWidth
    spacing: Theme.gap
    focus: true

    Component.onCompleted: {
        if (dirs.length === 0)
            notice = "no directories configured";
        else
            scanProc.running = true;
        input.forceActiveFocus();
    }

    // Test hook (settings.debugIpc): filter, move and accept over IPC while
    // the panel is open, so a smoke test never injects keys into the session.
    IpcHandler {
        target: "haseen.imagepicker"
        enabled: root.settings.debugIpc === true

        function setQuery(text: string): void {
            input.text = text;
        }

        function move(delta: int): void {
            root.step(delta);
        }

        function accept(): void {
            root.apply(grid.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                dirs: root.dirs,
                count: root.images.length,
                shown: root.results.length,
                current: root.results[grid.currentIndex] ? root.results[grid.currentIndex].path : "",
                command: root.results[grid.currentIndex] ? root.applyCommand(root.results[grid.currentIndex].path) : [],
                notice: root.notice
            });
        }
    }

    // Existing files only, so no card asks for an image that is not there. A
    // missing directory makes find exit 1; its output still counts.
    Process {
        id: scanProc

        command: {
            const argv = ["find", "-L"].concat(root.dirs);
            argv.push("-maxdepth", String(root.depth), "-type", "f", "(");
            for (let i = 0; i < Images.EXTENSIONS.length; i++) {
                if (i > 0)
                    argv.push("-o");
                argv.push("-iname", "*." + Images.EXTENSIONS[i]);
            }
            argv.push(")", "-print");
            return argv;
        }
        stdout: StdioCollector {
            id: scanOut
        }
        // "No such file or directory" for an absent dir: expected, not news.
        stderr: StdioCollector {}
        onExited: {
            const found = Images.parseList(scanOut.text);
            root.images = found.slice(0, root.limit);
            if (found.length === 0)
                root.notice = "no images in " + root.dirs.join(", ");
            else if (found.length > root.limit)
                root.notice = "showing " + root.limit + " of " + found.length;
        }
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: "Images"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: root.notice !== "" ? root.notice : "Enter applies · Esc closes"
            color: root.notice !== "" ? Theme.urgent : Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: Theme.accent
        border.width: Theme.borderWidth

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Theme.gap * 1.5
            anchors.rightMargin: Theme.gap * 1.5
            verticalAlignment: TextInput.AlignVCenter
            focus: true
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            onTextChanged: root.query = text
            onAccepted: root.apply(grid.currentIndex)
            Keys.onUpPressed: root.step(-root.columns)
            Keys.onDownPressed: root.step(root.columns)
            Keys.onTabPressed: root.step(1)
            Keys.onBacktabPressed: root.step(-1)
            Keys.onLeftPressed: event => {
                if (cursorPosition === 0 || text === "")
                    root.step(-1);
                else
                    event.accepted = false;
            }
            Keys.onRightPressed: event => {
                if (cursorPosition === text.length)
                    root.step(1);
                else
                    event.accepted = false;
            }
        }
    }

    GridView {
        id: grid

        width: root.columns * root.cellWidth
        height: Math.max(1, Math.min(Math.ceil(root.results.length / root.columns), root.rows)) * root.cellHeight
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        clip: true
        keyNavigationWraps: false
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        model: root.results
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

        delegate: Item {
            id: cell

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            ImageCard {
                x: Theme.gap
                y: Theme.gap
                width: root.cardWidth
                path: cell.modelData.path
                label: cell.modelData.label
                showLabel: root.showLabels
                selected: cell.GridView.isCurrentItem
                pixelRatio: root.screen && root.screen.devicePixelRatio ? root.screen.devicePixelRatio : 1
                onHovered: grid.currentIndex = cell.index
                onPicked: root.apply(cell.index)
            }
        }
    }
}
