import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "EmojiSearch.js" as EmojiSearch

// haseen.emoji: type to filter, arrows move, Enter (or a click) copies the
// emoji with wl-copy and closes. Emoji data and search are adapted from
// Omarchy shell/plugins/emojis (MIT, Copyright (c) David Heinemeier Hansson).
// Opened with `haseen shell ipc panel toggle haseen.emoji`. The panel is lazy,
// so the 100 KiB list is read only while it is open.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 4 ? Math.round(settings.columns) : 9
    readonly property int rows: typeof settings.rows === "number" && settings.rows >= 2 ? Math.round(settings.rows) : 6
    readonly property int cell: Theme.fontSize * 3
    property var emojis: []
    property string query: ""
    property string lastCopied: ""
    readonly property var results: EmojiSearch.filterEmojis(emojis, query, 1000)

    function accept(index: int): void {
        const item = results[index];
        if (!item)
            return;
        lastCopied = item.e;
        Quickshell.execDetached(["wl-copy", "--", item.e]);
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function move(delta: int): void {
        if (results.length === 0)
            return;
        grid.currentIndex = Math.max(0, Math.min(results.length - 1, grid.currentIndex + delta));
    }

    onResultsChanged: grid.currentIndex = 0

    width: columns * cell + Theme.gap * 2
    spacing: Theme.gap

    Component.onCompleted: input.forceActiveFocus()

    FileView {
        path: Qt.resolvedUrl("emojis.json").toString().replace("file://", "")
        onLoaded: root.emojis = EmojiSearch.parseEmojis(text())
    }

    // Test hook (settings.debugIpc): drive the open panel without injecting
    // keys: `qs ipc call haseen.emoji setQuery heart`, `accept`, `state`.
    IpcHandler {
        target: "haseen.emoji"
        enabled: root.settings.debugIpc === true

        function setQuery(text: string): void {
            input.text = text;
        }

        function right(): void {
            root.move(1);
        }

        function accept(): void {
            root.accept(grid.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                query: root.query,
                loaded: root.emojis.length,
                count: root.results.length,
                current: grid.currentIndex,
                first: root.results.slice(0, 5).map(r => r.e),
                lastCopied: root.lastCopied
            });
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.8
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
            font.pixelSize: Theme.fontSize + 2
            onTextChanged: root.query = text
            onAccepted: root.accept(grid.currentIndex)
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
            Keys.onUpPressed: root.move(-root.columns)
            Keys.onDownPressed: root.move(root.columns)
            Keys.onTabPressed: root.move(1)
            Keys.onBacktabPressed: root.move(-1)
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gap * 1.5
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "Search emoji"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }
    }

    GridView {
        id: grid

        x: Theme.gap
        width: root.columns * root.cell
        height: root.rows * root.cell
        visible: root.results.length > 0
        clip: true
        cellWidth: root.cell
        cellHeight: root.cell
        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        currentIndex: 0

        delegate: Rectangle {
            id: tile

            required property var modelData
            required property int index

            width: root.cell
            height: root.cell
            radius: Theme.radius
            color: GridView.isCurrentItem ? Theme.selection : "transparent"

            Text {
                anchors.centerIn: parent
                text: tile.modelData.e
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSize * 1.8
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: grid.currentIndex = tile.index
                onClicked: root.accept(tile.index)
            }
        }
    }

    Text {
        width: parent.width
        visible: root.results.length === 0
        text: root.emojis.length === 0 ? "Loading…" : "No matches"
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
