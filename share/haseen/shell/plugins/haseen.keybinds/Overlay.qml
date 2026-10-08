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

    readonly property var rows: {
        const needle = query.trim().toLowerCase();
        const matched = needle === "" ? binds : binds.filter(b => (b.combo + " " + b.description + " " + b.action + " " + b.category).toLowerCase().indexOf(needle) >= 0);
        // One flat model with group headers, so a single ListView lays the
        // sheet out and search never leaves an empty heading behind.
        const out = [];
        let group = "";
        for (const bind of matched) {
            if (bind.category !== group) {
                group = bind.category;
                out.push({
                    header: group,
                    combo: "",
                    text: ""
                });
            }
            out.push({
                header: "",
                combo: bind.combo,
                text: bind.description || bind.action
            });
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

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.gap * 2
                    spacing: Theme.gap

                    TextInput {
                        id: search

                        width: parent.width
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        focus: true
                        text: root.query
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.hide()
                        Component.onCompleted: forceActiveFocus()

                        Text {
                            anchors.fill: parent
                            visible: search.text === ""
                            text: root.binds.length + " bindings — type to search"
                            color: Theme.muted
                            font: search.font
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.max(1, Theme.borderWidth)
                        color: Theme.border
                    }

                    ListView {
                        id: list

                        width: parent.width
                        height: parent.height - search.height - Theme.gap * 3
                        clip: true
                        model: root.rows
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            required property var modelData

                            width: list.width
                            height: Math.round(Theme.fontSize * (modelData.header === "" ? 1.7 : 2.4))

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.header !== ""
                                text: modelData.header
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                id: combo

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
                                text: modelData.text
                                elide: Text.ElideRight
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                        }
                    }
                }
            }

            Keys.onEscapePressed: root.hide()
        }
    }
}
