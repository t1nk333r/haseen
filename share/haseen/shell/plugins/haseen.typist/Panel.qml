// Adapted from Panel.qml (the picker) in the owner's fork t1nk33r.typist
// 1.1.0 of sanjuanjor/typist (MIT, Copyright (c) 2026 sanjuanjor); see
// LICENSE and UPSTREAM.md beside this file.
// haseen: a lazily loaded haseen panel on Theme tokens; Recent rows come from
// haseen.clipboard's cliphist store and are typed and pinned by cliphist id;
// snippets in ~/.config/haseen/typist.json; `haseen typist` types.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Picker.js" as Picker

// The picker. Row 0 types whatever is on the clipboard now; the Snippets
// section lists the user's saved texts, the Recent section the newest text
// entries of the clipboard history. Nothing about the history is kept here:
// `cliphist list` runs when the panel opens and the rows go when it closes.
//
// Keys: j/k or arrows move; l, Enter or Space types the cursor row and closes
// the panel first, so the keys land in the window that had focus (the
// startupDelayMs setting covers the hand-back). Opened from a hotkey, the
// first Enter only shows the cursor on row 0, so a stray Enter cannot type
// the clipboard unasked. `/` focuses the filter (Escape there clears it and
// gives the keys back to the list); `s` pins a Recent row as a snippet; `dd`
// or `x` deletes the cursor snippet; Escape closes.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string cli: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen-typist"
    readonly property string snippetsPath: Paths.userConfig + "/typist.json"

    function intSetting(name: string, fallback: int, lo: int, hi: int): int {
        const n = Number(settings[name]);
        return isFinite(n) && settings[name] !== undefined ? Math.max(lo, Math.min(hi, Math.round(n))) : fallback;
    }
    readonly property int recentCount: intSetting("recentCount", 8, 0, 50)
    readonly property int maxBytes: intSetting("maxClipboardBytes", 65536, 1, 1048576)

    property bool typing: false
    property var recent: []
    property bool historyAvailable: true
    property var snippetConfig: Picker.parseSnippets("")
    property string filterText: ""
    property string notice: ""
    property bool deleteArmed: false
    property bool cursorActive: false
    property int cursorIndex: 0
    // The last command handed to haseen typist, for the test hook.
    property var lastCommand: []

    // One cursor over a flat list: the clipboard row, the snippets, the
    // recent entries. Headers and notes are display rows only.
    readonly property var rows: {
        const out = [{
                kind: "clipboard"
            }];
        for (const s of Picker.filterRows(Picker.snippetRows(snippetConfig, maxBytes), filterText))
            out.push(Object.assign({
                kind: "snippet"
            }, s));
        for (const r of Picker.filterRows(Picker.recentRows(recent, recentCount), filterText))
            out.push(Object.assign({
                kind: "recent"
            }, r));
        return out;
    }
    readonly property int snippetRowCount: rows.filter(r => r.kind === "snippet").length
    readonly property var display: {
        const out = [{
                header: "Clipboard"
            }, {
                cursor: 0
            }];
        if (snippetRowCount > 0) {
            out.push({
                header: "Snippets"
            });
            for (let i = 1; i <= snippetRowCount; i++)
                out.push({
                    cursor: i
                });
        }
        if (recentCount > 0) {
            out.push({
                header: "Recent"
            });
            const total = rows.length - 1 - snippetRowCount;
            if (total === 0)
                out.push({
                    note: !historyAvailable ? "cliphist is not installed: haseen.clipboard keeps the history." : filterText !== "" ? "No recent entry matches the filter." : "No text in the clipboard history yet."
                });
            for (let j = 0; j < total; j++)
                out.push({
                    cursor: 1 + snippetRowCount + j
                });
        }
        return out;
    }

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function currentRow(): var {
        return rows.length > 0 ? rows[cursorIndex] : null;
    }

    function moveCursor(dy: int): void {
        disarmDelete();
        cursorActive = true;
        cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy));
    }

    function runCli(args: var): void {
        lastCommand = args;
        Quickshell.execDetached([root.cli].concat(args));
    }

    // The panel closes before anything is typed, so the keys land in the
    // window that had focus when it opened.
    function activate(): void {
        if (!cursorActive) {
            cursorActive = rows.length > 0;
            return;
        }
        const row = currentRow();
        if (!row)
            return;
        if (row.kind === "clipboard") {
            runCli([typing ? "stop" : "start"]);
        } else if (row.tooLarge) {
            notice = "That snippet is over the size limit (" + row.bytes + " bytes).";
            return;
        } else if (row.kind === "snippet") {
            runCli(["type", "snippet", String(row.index), Qt.md5(row.text)]);
        } else {
            runCli(["type", "recent", row.id]);
        }
        close();
    }

    // Pinning writes typist's own file, never the clipboard history. The
    // recent preview is truncated, so the entry is decoded first.
    function pin(): void {
        disarmDelete();
        const row = currentRow();
        if (!row || row.kind !== "recent" || decoder.running)
            return;
        decoder.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist decode", "sh", row.id];
        decoder.running = true;
    }

    function writeSnippets(next: var, message: string): void {
        // Adopted at once: the file watch only feeds the write back a moment
        // later, and a second pin in between would compute from the old list.
        snippetConfig = next;
        snippetsFile.setText(JSON.stringify(next, null, 2) + "\n");
        notice = message;
    }

    function remove(): void {
        const row = currentRow();
        if (!row)
            return;
        if (row.kind !== "snippet") {
            notice = "Only Snippets rows can be deleted.";
            return;
        }
        writeSnippets(Picker.removeSnippet(snippetConfig, row.index), "Snippet removed.");
    }

    // Vim `dd`: the first d arms, a second within 1.2 s deletes. Moving,
    // filtering or pinning drops the arm, so it can only land on its own row.
    function disarmDelete(): void {
        if (!deleteArmed)
            return;
        deleteArmed = false;
        armTimer.stop();
        if (notice.indexOf("dd") === 0)
            notice = "";
    }

    function armDelete(): void {
        if (deleteArmed) {
            disarmDelete();
            remove();
            return;
        }
        deleteArmed = true;
        notice = "dd: press d again to delete this snippet";
        armTimer.restart();
    }

    onRowsChanged: if (cursorIndex > rows.length - 1)
        cursorIndex = Math.max(0, rows.length - 1)

    width: Theme.fontSize * 32
    spacing: Theme.gap

    Component.onCompleted: {
        stateProbe.running = true;
        if (recentCount > 0)
            lister.running = true;
        keys.forceActiveFocus();
    }

    FileView {
        id: snippetsFile

        path: root.snippetsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.snippetConfig = Picker.parseSnippets(text())
        onLoadFailed: root.snippetConfig = Picker.parseSnippets("")
        onFileChanged: reload()
    }

    Process {
        id: lister

        // Through sh so a missing cliphist is exit 127, not a start failure.
        command: ["sh", "-c", "exec cliphist list"]
        stdout: StdioCollector {
            id: listing
        }
        onExited: code => {
            root.historyAvailable = code !== 127;
            root.recent = code === 0 ? Picker.parseCliphist(listing.text) : [];
        }
    }

    Process {
        id: decoder

        stdout: StdioCollector {
            id: decoded
        }
        onExited: code => {
            const text = decoded.text;
            if (code !== 0 || text.trim() === "")
                root.notice = "Could not read that clipboard entry.";
            else if (Picker.sizeOf(text) > root.maxBytes)
                root.notice = "That entry is over the size limit.";
            else
                root.writeSnippets(Picker.pinSnippet(root.snippetConfig, text), "Pinned to snippets.");
        }
    }

    Process {
        id: stateProbe

        command: ["systemctl", "--user", "is-active", "--quiet", "haseen-typist.service"]
        onExited: code => root.typing = code === 0
    }

    // haseen:ui-timeout
    Timer {
        id: armTimer

        interval: 1200
        onTriggered: root.disarmDelete()
    }

    // Test hook (settings.debugIpc): drive the open panel without a keyboard.
    IpcHandler {
        target: "haseen.typist"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                typing: root.typing,
                cursorActive: root.cursorActive,
                cursor: root.cursorIndex,
                notice: root.notice,
                filter: root.filterText,
                rows: root.rows.map(r => r.kind + ":" + (r.kind === "recent" ? r.id : r.kind === "snippet" ? r.index : "") + ":" + (r.preview || "")),
                snippets: root.snippetConfig.snippets.map(s => s.text),
                lastCommand: root.lastCommand
            });
        }

        function select(index: int): void {
            root.cursorActive = true;
            root.cursorIndex = Math.max(0, Math.min(index, root.rows.length - 1));
        }

        function activate(): void {
            root.activate();
        }

        function filter(text: string): void {
            filterField.text = text;
        }

        function pin(): void {
            root.pin();
        }

        function remove(): void {
            root.armDelete();
            root.armDelete();
        }
    }

    // Holds the keyboard while the filter field does not.
    Item {
        id: keys

        width: parent.width
        height: header.height
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            event.accepted = true;
            if (k === Qt.Key_Escape) {
                if (root.filterText !== "")
                    filterField.text = "";
                else
                    root.close();
            } else if (k === Qt.Key_Down || t === "j") {
                root.moveCursor(1);
            } else if (k === Qt.Key_Up || t === "k") {
                root.moveCursor(-1);
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Right || t === "l") {
                root.activate();
            } else if (t === "/") {
                root.disarmDelete();
                filterField.forceActiveFocus();
            } else if (t === "s" || t === "S") {
                root.pin();
            } else if (t === "d" || t === "D") {
                root.armDelete();
            } else if (t === "x" || k === Qt.Key_Delete) {
                root.remove();
            } else {
                event.accepted = false;
            }
        }

        Item {
            id: header

            width: parent.width
            height: Theme.fontSize * 2

            Glyph {
                id: heroGlyph

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\u{f030c}"
                color: root.typing ? Theme.accent : Theme.foreground
            }

            Text {
                anchors.left: heroGlyph.right
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                text: "Typist"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width / 2
                horizontalAlignment: Text.AlignRight
                text: root.notice !== "" ? root.notice : root.typing ? "Typing…" : "Pick a text to type"
                textFormat: Text.PlainText
                elide: Text.ElideLeft
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: filterField.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        TextInput {
            id: filterField

            anchors.fill: parent
            anchors.leftMargin: Theme.gap * 1.5
            anchors.rightMargin: Theme.gap * 1.5
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            clip: true
            onTextChanged: {
                root.disarmDelete();
                root.filterText = text;
            }
            Keys.onUpPressed: root.moveCursor(-1)
            Keys.onDownPressed: root.moveCursor(1)
            // Both ways out hand the keys back to the list, or every key stays
            // filter text.
            Keys.onReturnPressed: {
                keys.forceActiveFocus();
                root.activate();
            }
            Keys.onEnterPressed: {
                keys.forceActiveFocus();
                root.activate();
            }
            Keys.onEscapePressed: {
                text = "";
                keys.forceActiveFocus();
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: filterField.text === ""
                text: "Filter: press / to type here"
                color: Theme.muted
                font: filterField.font
            }
        }
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, Theme.fontSize * 30)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.display
        currentIndex: root.display.findIndex(d => d.cursor === root.cursorIndex)
        highlightMoveDuration: 0
        onCurrentIndexChanged: if (currentIndex >= 0)
            positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: entry

            required property var modelData
            required property int index
            readonly property var row: modelData.cursor !== undefined ? root.rows[modelData.cursor] : null
            readonly property bool current: row !== null && root.cursorActive && root.cursorIndex === modelData.cursor

            width: list.width
            height: row !== null ? Math.round(Theme.fontSize * 3.2) : Math.round(Theme.fontSize * 1.8)

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                visible: entry.row === null
                text: entry.modelData.header !== undefined ? entry.modelData.header : (entry.modelData.note || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: entry.modelData.header !== undefined ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - (entry.modelData.header !== undefined ? 0 : 1)
            }

            Rectangle {
                anchors.fill: parent
                visible: entry.row !== null && (entry.current || hover.containsMouse)
                radius: Theme.radius
                color: entry.current ? Theme.selection : Theme.surfaceAlt
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                enabled: entry.row !== null
                hoverEnabled: true
                onClicked: {
                    root.disarmDelete();
                    root.cursorActive = true;
                    root.cursorIndex = entry.modelData.cursor;
                    root.activate();
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.row !== null
                spacing: 1

                Text {
                    width: parent.width
                    text: !entry.row ? "" : entry.row.kind === "clipboard" ? (root.typing ? "Stop typing" : "Type current clipboard") : entry.row.preview
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: entry.row && entry.row.tooLarge ? Theme.muted : Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    width: parent.width
                    text: !entry.row ? "" : entry.row.kind === "clipboard" ? "wl-paste, typed once" : entry.row.kind === "snippet" ? (entry.row.tooLarge ? "too large to type" : entry.row.bytes + " bytes · dd delete") : "recent · s pin as snippet"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    Text {
        width: parent.width
        text: "j/k move · l or ⏎ type · / filter · s pin · dd delete · esc close"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
