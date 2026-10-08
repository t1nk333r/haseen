import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Cliphist.js" as Cliphist

// Clipboard history (cliphist), newest first. Type to search, arrows move,
// Enter or a click copies the entry back (`cliphist decode | wl-copy`) and
// closes, Delete or the trash button removes it. Image entries show a
// thumbnail decoded on demand into $XDG_RUNTIME_DIR/haseen-clipboard/, which
// is removed when the panel closes. Open with
// `haseen shell ipc panel toggle haseen.clipboard`.
//
// Ctrl+P (or the eye button) toggles the preview pane, which shows the
// selected entry in full: `cliphist list` collapses whitespace and truncates
// a text preview to 100 characters, so the list alone cannot tell two long
// entries apart. The toggle is persisted to shell.json as
// `plugins."haseen.clipboard".settings.preview`. PageUp/PageDown scroll the
// pane. The pane lives in a Loader bound to that setting, so a preview that
// is off decodes nothing; Preview.qml documents the size bounds.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.clipboard;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool recording: service !== null && service.available
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/haseen-clipboard"
    readonly property int maxRows: typeof settings.maxRows === "number" && settings.maxRows >= 3 ? Math.round(settings.maxRows) : 10
    readonly property int rowHeight: Math.round(Theme.fontSize * 2.2)
    readonly property int imageHeight: Theme.fontSize * 6
    property string query: ""
    readonly property var results: Cliphist.filter(history.entries, query)

    // Preview pane. Default on: without it the panel shows cliphist's own
    // truncated one-line previews, which is the gap this plugin had.
    readonly property bool previewOn: settings.preview !== false
    readonly property int previewHeight: typeof settings.previewHeight === "number" && settings.previewHeight >= 80 ? Math.round(settings.previewHeight) : 220
    readonly property int maxBytes: typeof settings.previewMaxBytes === "number" && settings.previewMaxBytes > 0 ? Math.round(settings.previewMaxBytes) : 8388608
    readonly property int maxPixels: typeof settings.previewMaxPixels === "number" && settings.previewMaxPixels > 0 ? Math.round(settings.previewMaxPixels) : 12000000
    readonly property string settingsCli: Paths.haseenPath + "/../../bin/haseen-plugin-settings"

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function copy(index: int): void {
        const entry = results[index];
        if (!entry)
            return;
        history.copy(entry);
        close();
    }

    function remove(index: int): void {
        const entry = results[index];
        if (entry)
            history.remove(entry);
    }

    function shift(delta: int): void {
        if (results.length > 0)
            list.currentIndex = (list.currentIndex + delta + results.length) % results.length;
    }

    // The runtime layer repaints the panel on the key itself; `haseen plugin
    // settings` then writes the same value to ~/.config/haseen/shell.json.
    // Detached, so closing the panel on the same key cannot lose the write.
    function setPreview(on: bool): void {
        if (on === root.previewOn)
            return;
        Config.setRuntime(["plugins", root.pluginId, "settings", "preview"], on);
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$2\" | \"$1\" \"$3\" --yes >/dev/null", "sh", root.settingsCli, JSON.stringify({
                    settings: {
                        preview: on
                    }
                }), root.pluginId]);
    }

    function togglePreview(): void {
        setPreview(!root.previewOn);
    }

    function scrollPreview(direction: int): void {
        if (previewPane.item)
            previewPane.item.scroll(direction);
    }

    onResultsChanged: list.currentIndex = Math.min(Math.max(list.currentIndex, 0), results.length - 1)

    width: typeof settings.width === "number" && settings.width >= 280 ? settings.width : 480
    spacing: Theme.gap

    Component.onCompleted: input.forceActiveFocus()
    Component.onDestruction: Quickshell.execDetached(["rm", "-rf", "--", root.thumbDir])

    History {
        id: history
    }

    // Test hook (settings.debugIpc): drive the open panel without a keyboard.
    IpcHandler {
        target: "haseen.clipboard"
        enabled: root.settings.debugIpc === true

        function search(text: string): void {
            input.text = text;
        }

        function select(index: int): void {
            list.currentIndex = Math.max(0, Math.min(index, root.results.length - 1));
        }

        function copy(): void {
            root.copy(list.currentIndex);
        }

        function remove(): void {
            root.remove(list.currentIndex);
        }

        function refresh(): void {
            history.refresh();
        }

        // "on", "off" or anything else to toggle.
        function preview(mode: string): void {
            if (mode === "on")
                root.setPreview(true);
            else if (mode === "off")
                root.setPreview(false);
            else
                root.togglePreview();
        }

        function scroll(direction: int): void {
            root.scrollPreview(direction);
        }

        function state(): string {
            const pane = previewPane.item;
            return JSON.stringify({
                recording: root.recording,
                available: history.available,
                loaded: history.loaded,
                total: history.entries.length,
                query: root.query,
                current: list.currentIndex,
                preview: {
                    on: root.previewOn,
                    loaded: pane !== null,
                    entry: pane ? pane.entryId : "",
                    meta: pane ? pane.meta : "",
                    image: pane ? pane.isImage : false,
                    imageReady: pane ? pane.imageReady : false,
                    bytes: pane ? pane.bytes : -1,
                    lines: pane ? pane.lines : 0,
                    truncated: pane ? pane.truncated : false,
                    notice: pane ? pane.notice : "",
                    head: pane ? pane.body.slice(0, 160) : ""
                },
                results: root.results.slice(0, 20).map(e => ({
                            id: e.id,
                            preview: e.preview,
                            image: e.image,
                            type: e.type,
                            size: e.size
                        }))
            });
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Clipboard"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            spacing: Theme.gap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.query === "" ? history.entries.length + " items" : root.results.length + " of " + history.entries.length
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            BarButton {
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.previewOn ? "\uf06e" : "\uf070"
                color: root.previewOn ? Theme.accent : Theme.muted
                onClicked: root.togglePreview()
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
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            clip: true
            onTextChanged: root.query = text

            // Runs before the specific handlers below; anything not accepted
            // here falls through to them and then to the text field.
            Keys.onPressed: event => {
                if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                    root.togglePreview();
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    root.scrollPreview(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.scrollPreview(-1);
                    event.accepted = true;
                }
            }
            Keys.onUpPressed: root.shift(-1)
            Keys.onDownPressed: root.shift(1)
            Keys.onTabPressed: root.shift(1)
            Keys.onBacktabPressed: root.shift(-1)
            Keys.onReturnPressed: root.copy(list.currentIndex)
            Keys.onEnterPressed: root.copy(list.currentIndex)
            Keys.onDeletePressed: event => {
                if (input.text === "") {
                    root.remove(list.currentIndex);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: "Search clipboard history"
                color: Theme.muted
                font: input.font
            }
        }
    }

    Text {
        width: parent.width
        visible: !root.recording || (history.loaded && root.results.length === 0)
        wrapMode: Text.WordWrap
        text: !history.available ? "cliphist is not installed." : !root.recording ? "History is not being recorded: add haseen.clipboard to shell.json services." : root.query === "" ? "Nothing copied yet." : "No matches."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, root.maxRows * root.rowHeight)
        visible: root.results.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results
        currentIndex: 0
        highlightMoveDuration: 0

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool current: ListView.isCurrentItem
            // An image past the preview bounds stays a text line: decoding it
            // for a thumbnail would cost the same pixmap as the pane.
            readonly property bool showImage: modelData.image && Cliphist.tooLarge(modelData, root.maxBytes, root.maxPixels) === ""
            readonly property string thumb: showImage ? root.thumbDir + "/" + modelData.id + "." + modelData.ext : ""
            property bool thumbReady: false

            width: list.width
            height: showImage ? root.imageHeight : root.rowHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: row.current ? Theme.selection : Theme.surfaceAlt
                visible: row.current || hover.containsMouse
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.copy(row.index)
            }

            // Decoded once per id while the panel is open; ListView only
            // creates delegates for visible rows, so only those decode. The
            // temporary file keeps this and the preview pane, which share the
            // path, from reading a half-written image.
            Process {
                running: row.showImage
                command: ["sh", "-c", "mkdir -p \"${2%/*}\" && { [ -s \"$2\" ] || { cliphist decode \"$1\" > \"$2.part.$$\" && mv -f \"$2.part.$$\" \"$2\"; }; }", "sh", row.modelData.id, row.thumb]
                onExited: code => row.thumbReady = code === 0
            }

            Image {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - Theme.gap
                width: parent.width - del.width - Theme.gap * 3
                visible: row.showImage
                source: row.thumbReady ? Paths.fileUrl(row.thumb) : ""
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                cache: false
                sourceSize.width: Math.max(1, Math.round(width))
                sourceSize.height: root.imageHeight
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.right: del.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.showImage
                text: row.modelData.preview.replace(/\s+/g, " ").trim()
                color: row.modelData.binary ? Theme.muted : Theme.foreground
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            BarButton {
                id: del

                anchors.right: parent.right
                height: root.rowHeight
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\uf1f8"
                color: Theme.muted
                onClicked: root.remove(row.index)
            }
        }
    }

    // Nothing is instantiated, and nothing decodes, until the preview is on.
    Loader {
        id: previewPane

        width: parent.width
        height: root.previewHeight
        active: root.previewOn && root.results.length > 0
        visible: active
        sourceComponent: previewComponent
    }

    Component {
        id: previewComponent

        Preview {
            entry: root.results[list.currentIndex] || null
            thumbDir: root.thumbDir
            maxBytes: root.maxBytes
            maxPixels: root.maxPixels
        }
    }
}
