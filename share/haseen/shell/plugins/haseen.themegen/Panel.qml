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
// Keys (plan 083) go in three stages, the active one framed in the accent and
// named with its keys in the header. The search field: type to filter (to
// search, on Wallhaven); Enter (searching first on Wallhaven) or Down moves
// to the pictures. The pictures: h/j/k/l or the arrows move (by a row in the
// Wallhaven grid), Enter picks (downloads, on Wallhaven) and moves to the
// palette. The palette: h/j/k/l or the arrows change the scheme, Enter
// applies once the preview is of the picture picked. Tab flips dark/light,
// Ctrl+S saves, `/` goes back to the field and Backspace back one stage;
// Escape closes (the panel host handles it). The panel opens in the middle
// of the screen (`placement` "center"). Open with
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
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 4
    readonly property real pixelRatio: screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1
    readonly property real screenWidth: screen && screen.width > 0 ? screen.width : 1920
    readonly property real screenHeight: screen && screen.height > 0 ? screen.height : 1080
    // Thumbnails 18 em wide (10 before plan 083), smaller only where the panel
    // would pass 60% of the screen's width or about 85% of its height.
    readonly property int cardWidth: Math.max(Theme.fontSize * 10, Math.min(Theme.fontSize * 18, Math.floor((screenWidth * 0.6 - Theme.gap) / columns) - Theme.gap, Math.floor((screenHeight * 0.85 - Theme.fontSize * 28) / 2.2)))
    readonly property int cellWidth: cardWidth + Theme.gap
    // The palette mock spans two thumbnails, at the 2:1 it always had.
    readonly property int mockWidth: cardWidth * 2 + Theme.gap

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
    // The image the preview on show was made from: Save and Apply need it to
    // be the picture picked, not one shown before (plan 083).
    property string previewImage: ""
    property bool previewQueued: false
    property string notice: ""
    property bool noticeIsError: false
    property bool writing: false
    // "local" (the strip of the user's images) or "wallhaven" (plan 072).
    property string source: settings.source === "wallhaven" ? "wallhaven" : "local"
    property bool wallhavenUsed: source === "wallhaven"
    // The keyboard flow (plan 083): "search" (the text field has the focus),
    // "images" (the strip or the Wallhaven grid) or "palette" (the scheme
    // chips); in the last two the panel itself has the focus.
    property string stage: "search"
    readonly property bool downloading: wallhaven.item !== null && wallhaven.item.fetching
    // Save and Apply only for the picture on show: never while its download
    // or a preview run is still to land, so Enter cannot apply a half-loaded
    // pick (plan 083). A Wallhaven pick drops the picture before it lands,
    // and a failed download leaves none, so Enter never applies an older one.
    readonly property bool ready: image !== "" && previewImage === image && preview.ok && !previewProc.running && !previewQueued && !downloading && !writing && Model.validName(name) && Model.canWrite(preview.target)
    readonly property string hint: {
        if (stage === "images")
            return "h j k l or arrows move · Enter " + (source === "wallhaven" ? "downloads" : "picks") + " · / search · Esc closes";
        if (stage === "palette")
            return "h j k l or arrows: scheme · Tab dark/light · Enter applies · Ctrl+S saves · Backspace: pictures";
        return source === "wallhaven" ? "Enter searches · Down: pictures · Esc closes" : "Enter or Down: pictures · Esc closes";
    }

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
        previewProc.image = image;
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

    function setStage(value: string): void {
        if (value !== "search" && value !== "images" && value !== "palette")
            return;
        stage = value;
        if (value === "search")
            input.forceActiveFocus();
        else
            root.forceActiveFocus();
    }

    // Enter in the field: the filter is live already; on Wallhaven, search.
    // The pictures are next either way.
    function submit(): void {
        if (source === "wallhaven" && wallhaven.item)
            wallhaven.item.search(input.text);
        setStage("images");
    }

    // Enter on a picture: a local one is previewed already, a Wallhaven one
    // is downloaded now. The palette is next either way.
    function choose(): void {
        if (source === "wallhaven") {
            if (!wallhaven.item || wallhaven.item.currentIndex < 0)
                return;
            wallhaven.item.select(wallhaven.item.currentIndex);
        } else {
            if (results.length === 0)
                return;
            pick(strip.currentIndex);
        }
        setStage("palette");
    }

    // Enter on the palette: Apply, once the preview is of the picture picked.
    function confirm(): void {
        if (ready)
            write(true);
        else if (downloading)
            say("still downloading: Enter applies once the preview shows", false);
    }

    // The pictures and palette stages' keys; false leaves the key alone.
    // Ctrl, Alt and Super chords are the shortcuts'.
    function handleKey(key: int, modifiers: int): bool {
        if (stage === "search" || !root.activeFocus || (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            return false;
        let dx = 0;
        let dy = 0;
        switch (key) {
        case Qt.Key_Left:
        case Qt.Key_H:
            dx = -1;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            dx = 1;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            dy = -1;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            dy = 1;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (stage === "images")
                choose();
            else
                confirm();
            return true;
        case Qt.Key_Backspace:
            setStage(stage === "palette" ? "images" : "search");
            return true;
        case Qt.Key_Slash:
            setStage("search");
            return true;
        case Qt.Key_Tab:
            setMode(Model.cycle(Model.MODES, mode, 1));
            return true;
        default:
            return false;
        }
        if (stage === "images")
            move(dx, dy);
        else
            setScheme(Model.cycle(Model.SCHEMES, scheme, dx + dy));
        return true;
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
        if (!ready)
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

    // The pictures: the strip's (up and down step like left and right) or
    // the Wallhaven grid's, by a row there. Moving downloads nothing.
    function move(dx: int, dy: int): void {
        if (source === "wallhaven") {
            if (wallhaven.item)
                wallhaven.item.move(dx, dy);
        } else if (results.length > 0) {
            strip.currentIndex = Math.max(0, Math.min(results.length - 1, strip.currentIndex + dx + dy));
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

    // A Wallhaven pick: the picture on show is not the one picked any more.
    function awaitDownload(): void {
        image = "";
        previewImage = "";
        preview = Model.parsePreview("");
    }

    // The pick did not download: back to the pictures, with the error shown.
    function downloadFailed(): void {
        if (stage === "palette")
            setStage("images");
    }

    onResultsChanged: {
        strip.currentIndex = 0;
        if (source === "local")
            pick(0);
    }

    width: columns * cellWidth + Theme.gap
    spacing: Theme.gap
    focus: true
    Keys.onPressed: event => event.accepted = root.handleKey(event.key, event.modifiers)

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
            root.move(delta, 0);
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
                ready: root.ready,
                preview: root.preview,
                notice: root.notice,
                source: root.source,
                stage: root.stage,
                query: input.text,
                strip: strip.currentIndex,
                wallhaven: wallhaven.item ? {
                    count: wallhaven.item.count,
                    page: wallhaven.item.page,
                    lastPage: wallhaven.item.lastPage,
                    sort: wallhaven.item.sort,
                    current: wallhaven.item.currentIndex,
                    scrollY: wallhaven.item.scrollY,
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

        // The image this run is for.
        property string image: ""

        stdout: StdioCollector {
            id: previewOut
        }
        stderr: StdioCollector {
            id: previewErr
        }
        onExited: code => {
            // A Wallhaven pick dropped the picture meanwhile: nothing to show.
            // Otherwise `previewImage` says which picture this palette is of.
            const ok = code === 0 && root.image !== "";
            root.preview = ok ? Model.parsePreview(previewOut.text) : Model.parsePreview("");
            root.previewImage = ok ? previewProc.image : "";
            if (code !== 0 && root.image !== "")
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

        // The current stage's keys, then the latest note; an error alone.
        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: root.noticeIsError ? root.notice : [root.hint, root.notice !== "" ? root.notice : previewProc.running ? "generating…" : ""].filter(s => s !== "").join(" · ")
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
            // Enter (a search first, on Wallhaven) or Down: to the pictures.
            // Keys, not onAccepted: TextInput passes an accepted Return on to
            // its parent, where the pictures stage would take it as a pick.
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
            // A click in the field is the search stage too.
            onActiveFocusChanged: if (activeFocus)
                root.stage = "search"
            Keys.onDownPressed: root.setStage("images")
            Keys.onTabPressed: root.setMode(Model.cycle(Model.MODES, root.mode, 1))

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.source === "wallhaven" ? "search wallhaven · Enter searches" : "filter images"
                color: Theme.muted
                visible: input.text === ""
                font: input.font
            }
        }
    }

    StageFrame {
        width: parent.width
        active: root.stage === "images"

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
                onStarted: root.awaitDownload()
                onPicked: (path, id) => root.useDownload(path, id)
                onFailed: root.downloadFailed()
                Component.onCompleted: search("")
            }
        }
    }

    StageFrame {
        width: parent.width
        active: root.stage === "palette"

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
                enabled: root.ready
                onClicked: root.write(false)
            }

            Choice {
                text: "Apply"
                active: true
                enabled: root.ready
                onClicked: root.write(true)
            }
        }
    }

    // Built from a complete preview only: the mock never draws half a palette.
    Loader {
        active: root.preview.ok
        visible: active

        sourceComponent: Row {
            spacing: Theme.gap

            PaletteMock {
                width: root.mockWidth
                height: Math.round(root.mockWidth / 2)
                colors: root.preview.colors
                image: root.image
                pixelRatio: root.pixelRatio
            }

            Column {
                spacing: Theme.gap

                Swatches {
                    colors: root.preview.colors
                    // Seven swatches (the anchor row) across what the mock leaves.
                    swatch: Math.floor((root.width - root.mockWidth - Theme.gap * 2 - Math.round(Theme.gap / 2) * 6) / 7)
                }

                Text {
                    width: root.width - root.mockWidth - Theme.gap * 2
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
