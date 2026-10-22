import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Haseen

// haseen.keybinds: the key bindings this session actually has, grouped by the
// section they were written under. Type to search, Escape or a click outside
// closes. Open with `haseen shell ipc keybinds toggle` (SUPER + F1).
//
// Sheet shape (search over every bind, grouped columns, modal overlay) adapted
// from DankMaterialShell quickshell/Modals/KeybindsModal.qml and
// KeybindsContent.qml (MIT, Copyright (c) 2025 Avenge Media LLC). The rows come
// from `haseen keybinds --json`, which reads the running compositor, so an edit
// to the Lua config is listed as soon as Hyprland has reloaded it.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})

    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property int columns: typeof settings.columns === "number" && settings.columns >= 1 ? Math.round(settings.columns) : 2
    property bool shown: false
    property string query: ""
    property var binds: []

    // `haseen keybinds` names a bind outside any section "Other".
    readonly property string otherSection: I18n.mark("Other")

    // A description from the Lua config in the interface language. The
    // workspace binds build theirs at run time ("Workspace " .. n), so they
    // are matched by pattern and translated as one template each.
    function describe(text: string): string {
        const patterns = [[/^Workspace (\S+)$/, I18n.tr("Workspace %1", "%1")], [/^Move window silently to workspace (\S+)$/, I18n.tr("Move window silently to workspace %1", "%1")], [/^Move window to workspace (\S+)$/, I18n.tr("Move window to workspace %1", "%1")], [/^Move window to left monitor$/, I18n.tr("Move window to left monitor")], [/^Move window to right monitor$/, I18n.tr("Move window to right monitor")], [/^Move window to up monitor$/, I18n.tr("Move window to the monitor above")], [/^Move window to down monitor$/, I18n.tr("Move window to the monitor below")]];
        for (const [pattern, template] of patterns) {
            const m = pattern.exec(text);
            if (m)
                return template.replace("%1", m[1] || "");
        }
        return I18n.tr(text);
    }

    readonly property var rows: {
        const needle = query.trim().toLowerCase();
        // The English and the shown (translated) description and section both
        // match, so a search works in either language (plan 109).
        const matched = needle === "" ? binds : binds.filter(b => (b.combo + " " + b.description + " " + describe(b.description) + " " + b.action + " " + b.category + " " + I18n.tr(b.category)).toLowerCase().indexOf(needle) >= 0);
        // One flat list with group headers (columnRows lays it out), so
        // search never leaves an empty heading behind.
        const out = [];
        let group = "";
        for (const bind of matched) {
            if (bind.category !== group) {
                group = bind.category;
                out.push({
                    header: group,
                    combo: "",
                    text: "",
                    described: false
                });
            }
            // text stays English; a description is translated where it
            // shows, a bare action (a command) never is.
            out.push({
                header: "",
                combo: bind.combo,
                text: bind.description || bind.action,
                described: !!bind.description
            });
        }
        return out;
    }

    // The rows in `columns` columns, read down then across. A section is never
    // split: each one goes to the column its middle falls in, measured in row
    // heights, so the columns come out about the same length.
    readonly property var columnRows: {
        const sections = [];
        for (const row of rows) {
            if (row.header !== "" || sections.length === 0)
                sections.push({
                    rows: [],
                    height: 0
                });
            const section = sections[sections.length - 1];
            section.rows.push(row);
            section.height += row.header === "" ? 1.7 : 2.4;
        }
        const total = sections.reduce((sum, section) => sum + section.height, 0);
        const out = [[]];
        let before = 0;
        for (const section of sections) {
            if (out[out.length - 1].length > 0 && out.length < columns && before + section.height / 2 > total * out.length / columns)
                out.push([]);
            out[out.length - 1] = out[out.length - 1].concat(section.rows);
            before += section.height;
        }
        return out;
    }

    function show(): void {
        query = "";
        reader.running = true;
        shown = true;
    }

    function hide(): void {
        shown = false;
    }

    function toggle(): void {
        if (shown)
            hide();
        else
            show();
    }

    Process {
        id: reader

        command: [root.cli, "keybinds", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.binds = JSON.parse(text);
                } catch (e) {
                    root.binds = [];
                }
            }
        }
    }

    // `open`/`close`, not `show`/`hide`: Quickshell's IPC listing reserves
    // those two names, and a call to them never reaches the handler.
    IpcHandler {
        target: "keybinds"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.show();
        }

        function close(): void {
            root.hide();
        }
    }

    // Test hook (settings.debugIpc): read the sheet without a keyboard.
    IpcHandler {
        target: "haseen.keybinds"
        enabled: root.settings.debugIpc === true

        function search(text: string): void {
            root.query = text;
        }

        function state(): string {
            return JSON.stringify({
                shown: root.shown,
                query: root.query,
                binds: root.binds.length,
                rows: root.rows.length,
                first: root.rows.length > 0 ? root.rows[0] : null
            });
        }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: window

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "haseen-keybinds"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                opacity: 0.75

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.hide()
                }
            }

            // A fixed-size card: PanelSurface sizes itself to its content, and
            // the list inside this one fills the card instead.
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.gap * 8, Theme.fontSize * 34 * root.columns)
                height: Math.min(parent.height - Theme.gap * 8, Theme.fontSize * 40)
                color: Theme.surface
                radius: Theme.radius
                border.color: Theme.border
                border.width: Theme.borderWidth
                // The sheet's own window, not a PanelPopup: mirror it here in
                // a right-to-left language (plan 109). Key names stay as is.
                LayoutMirroring.enabled: I18n.rightToLeft
                LayoutMirroring.childrenInherit: true

                // Takes the clicks the card's own items leave, so a click on
                // its margin does not reach the backdrop and close the sheet.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.gap * 2
                    spacing: Theme.gap

                    TextInput {
                        id: search

                        width: parent.width
                        // Explicit, so a mirrored sheet starts the field and
                        // its hint at the right like the rest of the sheet.
                        horizontalAlignment: TextInput.AlignLeft
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        focus: true
                        text: root.query
                        onTextChanged: root.query = text
                        Component.onCompleted: forceActiveFocus()

                        Text {
                            anchors.fill: parent
                            visible: search.text === ""
                            text: I18n.tn("%1 binding — type to search", "%1 bindings — type to search", root.binds.length)
                            horizontalAlignment: Text.AlignLeft
                            color: Theme.muted
                            font: search.font
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.max(1, Theme.borderWidth)
                        color: Theme.border
                    }

                    Flickable {
                        id: list

                        width: parent.width
                        height: parent.height - search.height - Theme.gap * 3
                        clip: true
                        contentHeight: sheet.height
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: sheet

                            readonly property real columnWidth: (list.width - spacing * (root.columns - 1)) / root.columns

                            spacing: Theme.gap * 2

                            Repeater {
                                model: root.columnRows

                                delegate: Column {
                                    id: column

                                    required property var modelData

                                    width: sheet.columnWidth

                                    Repeater {
                                        model: column.modelData

                                        delegate: Item {
                                            required property var modelData

                                            width: column.width
                                            height: Math.round(Theme.fontSize * (modelData.header === "" ? 1.7 : 2.4))

                                            // Anchored, not at x 0, so a mirrored sheet
                                            // starts each row at the right.
                                            Text {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: modelData.header !== ""
                                                // A section name from the Lua config.
                                                text: I18n.tr(modelData.header)
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize
                                                font.bold: true
                                            }

                                            Text {
                                                id: combo

                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: modelData.header === ""
                                                width: Math.round(parent.width * 0.42)
                                                text: modelData.combo
                                                elide: Text.ElideRight
                                                color: Theme.foreground
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontSize
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: combo.right
                                                anchors.right: parent.right
                                                visible: modelData.header === ""
                                                // The description from the Lua config,
                                                // collected for the catalog (plan 109).
                                                text: modelData.described ? root.describe(modelData.text) : modelData.text
                                                elide: Text.ElideRight
                                                color: Theme.muted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Escape closes the sheet whatever has focus. Keys cannot attach to
            // a window (only to an Item), and a window shortcut runs before
            // the search field sees the key (PanelPopup.qml does the same).
            Shortcut {
                sequence: "Escape"
                context: Qt.WindowShortcut
                onActivated: root.hide()
            }
        }
    }
}
