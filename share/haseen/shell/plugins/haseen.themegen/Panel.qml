import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Themegen.js" as Model
import "Wallhaven.js" as Wh
// The image list and its thumbnail card are haseen.imagepicker's, shared
// rather than copied: both panels scan the same directories the same way.
import "../haseen.imagepicker" as Picker
import "../haseen.imagepicker/Images.js" as Images

// haseen.themegen: build a theme from an image with matugen. Pick an image in
// the strip, a scheme and dark or light; the preview shows the palette as
// swatches and on a small mock desktop. Save writes the theme
// (`haseen theme generate … --no-apply`), Apply writes it and switches to it.
// The source switch picks between the user's own images and Wallhaven
// (plan 072, WallhavenGrid.qml): a search, sort chips and a paged grid whose
// pick is downloaded with `haseen wallhaven get` and then previewed the same.
// Keys: type to filter (Enter searches on Wallhaven), Left/Right move through
// the images, Up/Down change the scheme, Tab flips dark/light, Enter applies,
// Ctrl+S saves; Escape closes (the panel host handles it). Open with
// `haseen shell ipc panel toggle haseen.themegen` or menu Style › Theme
// Generator.
//
// Every colour comes from the CLI's --json preview: the mapping and the
// readability clamp live in bin/haseen-theme-generate only. Nothing runs
// until the panel opens: one `find`, then one matugen run per change of
// image, scheme or mode. A change while a run is busy waits for it and then
// runs once with the latest choice.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen (checkout, /usr/local, /usr, Nix).
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property var dirs: Images.directories(Array.isArray(settings.directories) && settings.directories.length > 0 ? settings.directories : ["~/Pictures", "~/Pictures/Wallpapers", Paths.userConfig + "/backgrounds"], Paths.home)
    readonly property int depth: typeof settings.depth === "number" && settings.depth >= 1 ? Math.round(settings.depth) : 3
    readonly property int limit: typeof settings.limit === "number" && settings.limit >= 1 ? Math.round(settings.limit) : 400
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 5
    readonly property int cardWidth: Theme.fontSize * 10
    readonly property int cellWidth: cardWidth + Theme.gap
    readonly property real pixelRatio: screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1

    property var images: []
    property string query: ""
    readonly property var results: Images.filter(images, query)

    property string image: ""
    property string scheme: Model.SCHEMES.indexOf(settings.scheme) >= 0 ? settings.scheme : Model.SCHEMES[0]
    property string mode: Theme.mode === "light" ? "light" : "dark"
    property string name: ""
    // The name follows the image until the user types one.
    property bool nameEdited: false

    property var preview: Model.parsePreview("")
    property bool previewQueued: false
    property string notice: ""
    property bool noticeIsError: false
    property bool writing: false
    // "local" (the strip of the user's images) or "wallhaven" (plan 072).
    property string source: settings.source === "wallhaven" ? "wallhaven" : "local"
    property bool wallhavenUsed: source === "wallhaven"

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    // The header note: an error in the urgent colour, anything else muted.
    function say(text: string, error: bool): void {
        notice = text;
        noticeIsError = error && text !== "";
    }

    function refresh(): void {
        if (image === "")
            return;
        if (previewProc.running) {
            previewQueued = true;
            return;
        }
        say("", false);
        previewProc.command = Model.previewArgv(cli, image, scheme, mode, name);
        previewProc.running = true;
    }

    function pick(index: int): void {
        const entry = results[index];
        const path = entry ? entry.path : "";
        // The results change and the strip's index moves in one step: one run.
        if (path === image)
            return;
        image = path;
        if (!nameEdited)
            name = image !== "" ? Model.defaultName(image) : "";
        refresh();
    }

    function step(delta: int): void {
        if (results.length === 0)
            return;
        strip.currentIndex = Math.max(0, Math.min(results.length - 1, strip.currentIndex + delta));
    }

    function setScheme(value: string): void {
        if (Model.SCHEMES.indexOf(value) < 0 || value === scheme)
            return;
        scheme = value;
        refresh();
    }

    function setMode(value: string): void {
        if (Model.MODES.indexOf(value) < 0 || value === mode)
            return;
        mode = value;
        refresh();
    }

    function setName(value: string): void {
        nameEdited = value !== "";
        name = nameEdited ? value : Model.defaultName(image);
        nameInput.text = name;
        refresh();
    }

    function write(apply: bool): void {
        if (writing || image === "" || !preview.ok || !Model.validName(name) || !Model.canWrite(preview.target))
            return;
        writing = true;
        say(apply ? "applying " + name + "…" : "saving " + name + "…", false);
        writeProc.apply = apply;
        writeProc.command = Model.writeArgv(cli, image, scheme, mode, name, apply);
        writeProc.running = true;
    }

    // My wallpapers or Wallhaven. Back on the user's own images, the strip's
    // picture is previewed again.
    function setSource(value: string): void {
        if ((value !== "local" && value !== "wallhaven") || value === source)
            return;
        source = value;
        input.text = "";
        if (value === "wallhaven") {
            wallhavenUsed = true;
            return;
        }
        image = "";
        pick(strip.currentIndex);
    }

    // Left/Right: the strip's images, or the Wallhaven grid's.
    function move(delta: int): void {
        if (source === "wallhaven") {
            if (wallhaven.item)
                wallhaven.item.step(delta);
        } else {
            step(delta);
        }
    }

    // A picture `haseen wallhaven get` saved: previewed like the user's own,
    // named after its wallhaven id until the user types a name.
    function useDownload(path: string, id: string): void {
        image = path;
        if (!nameEdited)
            name = Wh.themeName(id);
        refresh();
    }

    onResultsChanged: {
        strip.currentIndex = 0;
        if (source === "local")
            pick(0);
    }

    width: columns * cellWidth + Theme.gap
    spacing: Theme.gap
    focus: true

    Component.onCompleted: {
        if (dirs.length === 0)
            say("no directories configured", true);
        else
            scanProc.running = true;
        input.forceActiveFocus();
    }

    Shortcut {
        sequence: "Ctrl+S"
        context: Qt.WindowShortcut
        onActivated: root.write(false)
    }

    // Test hook (settings.debugIpc): drive the open panel over IPC, so a
    // smoke test or a screenshot never injects keys into the session.
    IpcHandler {
        target: "haseen.themegen"
        enabled: root.settings.debugIpc === true

        function setQuery(text: string): void {
            input.text = text;
        }

        function move(delta: int): void {
            root.step(delta);
        }

        function setScheme(value: string): void {
            root.setScheme(value);
        }

        function setMode(value: string): void {
            root.setMode(value);
        }

        function setName(value: string): void {
            root.setName(value);
        }

        function save(): void {
            root.write(false);
        }

        function apply(): void {
            root.write(true);
        }

        function setSource(value: string): void {
            root.setSource(value);
        }

        function search(text: string): void {
            input.text = text;
            if (wallhaven.item)
                wallhaven.item.search(text);
        }

        function setSort(value: string): void {
            if (wallhaven.item)
                wallhaven.item.setSort(value);
        }

        function more(): void {
            if (wallhaven.item)
                wallhaven.item.more();
        }

        function pickResult(index: int): void {
            if (wallhaven.item)
                wallhaven.item.select(index);
        }

        function state(): string {
            return JSON.stringify({
                count: root.images.length,
                shown: root.results.length,
                image: root.image,
                scheme: root.scheme,
                mode: root.mode,
                name: root.name,
                busy: previewProc.running || root.writing,
                preview: root.preview,
                notice: root.notice,
                source: root.source,
                wallhaven: wallhaven.item ? {
                    count: wallhaven.item.items.length,
                    page: wallhaven.item.page,
                    lastPage: wallhaven.item.lastPage,
                    sort: wallhaven.item.sort,
                    current: wallhaven.item.currentIndex,
                    downloading: wallhaven.item.downloading
                } : null
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
                root.say("no images in " + root.dirs.join(", "), true);
            else if (found.length > root.limit)
                root.say("showing " + root.limit + " of " + found.length, false);
        }
    }

    Process {
        id: previewProc

        stdout: StdioCollector {
            id: previewOut
        }
        stderr: StdioCollector {
            id: previewErr
        }
        onExited: code => {
            root.preview = code === 0 ? Model.parsePreview(previewOut.text) : Model.parsePreview("");
            if (code !== 0)
                root.say(Model.errorLine(previewErr.text, "haseen theme generate failed"), true);
            if (root.previewQueued) {
                root.previewQueued = false;
                root.refresh();
            }
        }
    }

    Process {
        id: writeProc

        property bool apply: false

        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: writeErr
        }
        onExited: code => {
            root.writing = false;
            if (code !== 0) {
                root.say(Model.errorLine(writeErr.text, "haseen theme generate failed"), true);
                return;
            }
            if (writeProc.apply) {
                root.close();
                return;
            }
            // The preview again, so the name now reads as ours; then the note.
            root.refresh();
            root.say("saved " + root.name + " (haseen theme set " + root.name + ")", false);
        }
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: "Theme generator"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: root.notice !== "" ? root.notice : previewProc.running ? "generating…" : root.source === "wallhaven" ? "Enter searches · Esc closes" : "Enter applies · Ctrl+S saves · Esc closes"
            color: root.noticeIsError ? Theme.urgent : Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Row {
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: [
                {
                    key: "local",
                    label: "My wallpapers"
                },
                {
                    key: "wallhaven",
                    label: "Wallhaven"
                }
            ]

            Choice {
                required property var modelData

                text: modelData.label
                active: root.source === modelData.key
                onClicked: root.setSource(modelData.key)
            }
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: input.activeFocus ? Theme.accent : Theme.border
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
            onTextChanged: if (root.source === "local")
                root.query = text
            onAccepted: {
                if (root.source === "wallhaven" && wallhaven.item)
                    wallhaven.item.search(text);
                else
                    root.write(true);
            }
            Keys.onUpPressed: root.setScheme(Model.cycle(Model.SCHEMES, root.scheme, -1))
            Keys.onDownPressed: root.setScheme(Model.cycle(Model.SCHEMES, root.scheme, 1))
            Keys.onTabPressed: root.setMode(Model.cycle(Model.MODES, root.mode, 1))
            Keys.onLeftPressed: event => {
                if (cursorPosition === 0 || text === "")
                    root.move(-1);
                else
                    event.accepted = false;
            }
            Keys.onRightPressed: event => {
                if (cursorPosition === text.length)
                    root.move(1);
                else
                    event.accepted = false;
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.source === "wallhaven" ? "search wallhaven · Enter searches · click a picture to use it" : "filter images"
                color: Theme.muted
                visible: input.text === ""
                font: input.font
            }
        }
    }

    ListView {
        id: strip

        width: parent.width
        height: Math.round(root.cardWidth * 9 / 16) + Theme.fontSize * 2
        orientation: ListView.Horizontal
        spacing: Theme.gap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        visible: root.source === "local"
        model: root.results
        onCurrentIndexChanged: {
            positionViewAtIndex(currentIndex, ListView.Contain);
            if (root.source === "local")
                root.pick(currentIndex);
        }

        delegate: Picker.ImageCard {
            required property var modelData
            required property int index

            width: root.cardWidth
            path: modelData.path
            label: modelData.label
            selected: ListView.isCurrentItem
            pixelRatio: root.pixelRatio
            onPicked: strip.currentIndex = index
        }
    }

    // Loaded on the first switch to Wallhaven and kept, so switching back
    // and forth keeps the results.
    Loader {
        id: wallhaven

        active: root.wallhavenUsed
        visible: root.source === "wallhaven"

        sourceComponent: WallhavenGrid {
            cli: root.cli
            columns: root.columns
            cardWidth: root.cardWidth
            pixelRatio: root.pixelRatio
            onSaid: (text, error) => root.say(text, error)
            onPicked: (path, id) => root.useDownload(path, id)
            Component.onCompleted: search("")
        }
    }

    Flow {
        width: parent.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: Model.SCHEMES

            Choice {
                required property string modelData

                text: Model.schemeLabel(modelData)
                active: root.scheme === modelData
                onClicked: root.setScheme(modelData)
            }
        }
    }

    Row {
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: Model.MODES

            Choice {
                required property string modelData

                text: Model.schemeLabel(modelData)
                active: root.mode === modelData
                onClicked: root.setMode(modelData)
            }
        }

        Item {
            width: Theme.gap
            height: 1
        }

        Rectangle {
            width: Theme.fontSize * 14
            height: Math.round(Theme.fontSize * 2.1)
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.color: nameInput.activeFocus ? Theme.accent : Model.validName(root.name) ? Theme.border : Theme.urgent
            border.width: Theme.borderWidth

            TextInput {
                id: nameInput

                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                text: root.name
                color: Theme.foreground
                selectionColor: Theme.selection
                clip: true
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 1
                onTextEdited: {
                    root.nameEdited = text !== "";
                    root.name = text;
                }
                onEditingFinished: root.refresh()
                onAccepted: root.write(false)
            }
        }

        Choice {
            text: "Save"
            enabled: root.preview.ok && !root.writing && Model.validName(root.name) && Model.canWrite(root.preview.target)
            onClicked: root.write(false)
        }

        Choice {
            text: "Apply"
            active: true
            enabled: root.preview.ok && !root.writing && Model.validName(root.name) && Model.canWrite(root.preview.target)
            onClicked: root.write(true)
        }
    }

    // Built from a complete preview only: the mock never draws half a palette.
    Loader {
        active: root.preview.ok
        visible: active

        sourceComponent: Row {
            spacing: Theme.gap

            PaletteMock {
                width: Theme.fontSize * 26
                height: Theme.fontSize * 13
                colors: root.preview.colors
                image: root.image
                pixelRatio: root.pixelRatio
            }

            Column {
                spacing: Theme.gap

                Swatches {
                    colors: root.preview.colors
                    // Seven swatches (the anchor row) across what the mock leaves.
                    swatch: Math.floor((root.width - Theme.fontSize * 26 - Theme.gap * 2 - Math.round(Theme.gap / 2) * 6) / 7)
                }

                Text {
                    width: root.width - Theme.fontSize * 26 - Theme.gap * 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: {
                        const parts = ["source " + root.preview.source];
                        const note = Model.targetNote(root.preview.target, root.preview.name);
                        if (note !== "")
                            parts.push(note);
                        if (root.preview.clamped.length > 0)
                            parts.push("clamped: " + root.preview.clamped.join(", "));
                        return parts.join(" · ");
                    }
                    color: Model.canWrite(root.preview.target) ? Theme.muted : Theme.urgent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }
}
