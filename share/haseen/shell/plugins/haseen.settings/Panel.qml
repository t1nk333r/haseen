// Adapted from SettingsPanel.qml (the Plugins section and its delete flow)
// and components/DynamicSettingsForm.qml of the owner's fork t1nk33r.settings
// 1.1.0 of AyushKr2003/shell-settings (MIT, Copyright (c) AyushKr2003); see
// LICENSE and UPSTREAM.md beside this file.
// haseen (plan 096): the plugin manager only. Rows come from the shell's own
// registry; every change goes through haseen's CLI (plugin enable, disable,
// settings, uninstall); the Bar, Idle, install and drawer sections of the
// fork are not here, because haseen already has those surfaces.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Every plugin the shell knows: search and filter, turn one on or off, edit
// the settings its manifest declares, and delete the ones installed under
// ~/.config/haseen/plugins (alone or a selection, in one process, with a
// summary). Built-in plugins and the read-only Omarchy and DMS plugin
// directories are never offered for deletion; `haseen plugin uninstall`
// refuses them too.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string bin: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property var allRows: Model.rows(Plugins.registry, id => ({
                listed: Config.isListed(id),
                enabled: Config.isEnabled(id)
            }), Paths.userPlugins)
    property string filter: "all"
    property string query: ""
    readonly property var shown: Model.filterRows(allRows, filter, query)
    property var selected: ({})
    readonly property var selectedNames: Object.keys(selected).filter(k => selected[k])
    property string confirmDelete: ""
    property string notice: ""
    property string busyId: ""

    // The settings form, when one plugin's is open.
    property string formId: ""
    property var edits: ({})
    property var resets: []
    property var fieldErrors: ({})
    readonly property var formRecord: formId !== "" ? Plugins.registry[formId] : null
    readonly property var formFields: formRecord ? Model.fields(formRecord.settings, (Config.pluginEntry(formId) || {}).settings) : []
    readonly property bool formDirty: Object.keys(edits).length > 0 || resets.length > 0

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function setEnabled(row: var, on: bool): void {
        if (cli.running)
            return;
        busyId = row.id;
        cli.enabling = on;
        cli.target = row.id;
        cli.command = [root.bin + "/haseen-plugin-" + (on ? "enable" : "disable"), row.id];
        cli.running = true;
    }

    function openForm(id: string): void {
        formId = id;
        edits = {};
        resets = [];
        fieldErrors = {};
        notice = "";
    }

    function stage(field: var, text: string): void {
        const parsed = Model.parseValue(field.type, text);
        const errs = Object.assign({}, fieldErrors);
        const next = Object.assign({}, edits);
        if (!parsed.ok) {
            errs[field.key] = Model.expects(parsed.error);
            delete next[field.key];
        } else {
            delete errs[field.key];
            next[field.key] = parsed.value;
        }
        fieldErrors = errs;
        edits = next;
        resets = resets.filter(k => k !== field.key);
    }

    function reset(field: var): void {
        const next = Object.assign({}, edits);
        delete next[field.key];
        edits = next;
        if (resets.indexOf(field.key) < 0)
            resets = resets.concat([field.key]);
    }

    // One write for the whole form, through `haseen plugin settings`, which
    // takes the latest shell.json under its lock and replaces it atomically.
    // The running shell is told at once, as the plugins' own panels do.
    function save(): void {
        if (!formDirty || saver.running || Object.keys(fieldErrors).length > 0)
            return;
        for (const k in edits)
            Config.setRuntime(["plugins", formId, "settings", k], edits[k]);
        saver.payload = JSON.stringify(Model.request(formId, edits, resets));
        saver.command = ["sh", "-c", "printf '%s' \"$2\" | \"$1\" \"$3\" --yes >/dev/null", "sh", root.bin + "/haseen-plugin-settings", saver.payload, formId];
        saver.running = true;
    }

    function toggleSelected(row: var): void {
        if (row.deleteName === "")
            return;
        const next = Object.assign({}, selected);
        next[row.deleteName] = !next[row.deleteName];
        selected = next;
        confirmDelete = "";
    }

    // The first press arms, the second deletes: one process for the whole
    // selection, which runs to the end even when one fails, and reports
    // each name.
    function requestDelete(names: var): void {
        const list = names.filter(n => /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(n));
        if (list.length === 0 || deleter.running)
            return;
        const key = list.slice().sort().join(" ");
        if (confirmDelete !== key) {
            confirmDelete = key;
            notice = list.length === 1 ? I18n.tr("Press again to delete %1 from ~/.config/haseen/plugins.", list[0]) : I18n.tn("Press again to delete %1 plugin from ~/.config/haseen/plugins.", "Press again to delete %1 plugins from ~/.config/haseen/plugins.", list.length);
            return;
        }
        confirmDelete = "";
        deleter.command = ["sh", "-c", "u=$1; shift; for n do if out=$(\"$u\" \"$n\" --yes 2>&1); then echo \"ok $n\"; else echo \"fail $n $(printf '%s' \"$out\" | tail -n1)\"; fi; done", "sh", root.bin + "/haseen-plugin-uninstall"].concat(list);
        deleter.running = true;
        notice = I18n.tr("Deleting…");
    }

    width: Theme.fontSize * 34
    spacing: Theme.gap

    Component.onCompleted: search.forceActiveFocus()

    Process {
        id: cli

        property bool enabling: false
        property string target: ""

        stderr: StdioCollector {
            id: cliErr
        }
        onExited: code => {
            root.busyId = "";
            const why = cliErr.text.trim().split("\n").pop();
            root.notice = code === 0 ? "" : enabling ? I18n.tr("Could not enable %1: %2", target, why) : I18n.tr("Could not disable %1: %2", target, why);
        }
    }

    Process {
        id: saver

        property string payload: ""

        onExited: code => {
            if (code === 0) {
                root.edits = {};
                root.resets = [];
                root.notice = I18n.tr("Saved to shell.json.");
            } else {
                root.notice = I18n.tr("haseen plugin settings refused the change.");
            }
        }
    }

    Process {
        id: deleter

        stdout: StdioCollector {
            id: deleteOut
        }
        onExited: {
            const s = Model.deleteSummary(deleteOut.text);
            root.selected = {};
            const parts = [];
            if (s.ok.length > 0)
                parts.push(I18n.tr("Deleted %1.", s.ok.join(", ")));
            if (s.failed.length > 0)
                parts.push(I18n.tr("Not deleted: %1", s.failed.map(f => f.name + " (" + f.reason + ")").join(", ")));
            root.notice = parts.join(" ");
        }
    }

    // Test hook (settings.debugIpc): read and drive the open panel.
    IpcHandler {
        target: "haseen.settings"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                filter: root.filter,
                shown: root.shown.map(r => r.id + ":" + Model.stateLabel(r) + ":" + r.origin + ":" + (r.deleteName !== "" ? "deletable" : "kept")),
                selected: root.selectedNames,
                notice: root.notice,
                form: root.formId,
                fields: root.formFields.map(f => f.key + "=" + JSON.stringify(f.value) + (f.set ? "*" : "")),
                edits: root.edits,
                errors: root.fieldErrors
            });
        }

        function setFilter(name: string): void {
            root.filter = name;
        }

        function setQuery(text: string): void {
            search.text = text;
        }

        function toggle(id: string): void {
            const row = root.allRows.find(r => r.id === id);
            if (row)
                root.setEnabled(row, !row.enabled);
        }

        function form(id: string): void {
            root.openForm(id);
        }

        function edit(key: string, text: string): void {
            const f = root.formFields.find(x => x.key === key);
            if (f)
                root.stage(f, text);
        }

        function resetKey(key: string): void {
            const f = root.formFields.find(x => x.key === key);
            if (f)
                root.reset(f);
        }

        function save(): void {
            root.save();
        }

        function select(id: string): void {
            const row = root.allRows.find(r => r.id === id);
            if (row)
                root.toggleSelected(row);
        }

        function deleteSelected(): void {
            root.requestDelete(root.selectedNames);
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2

        Glyph {
            id: heroGlyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\u{f0493}"
            color: Theme.accent
        }

        Text {
            anchors.left: heroGlyph.right
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.formRecord ? I18n.tr("%1 settings", root.formRecord.name) : I18n.tr("Plugins")
            textFormat: Text.PlainText
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.title
        }

        BarButton {
            anchors.right: parent.right
            height: parent.height
            visible: root.formId !== ""
            text: I18n.tr("Back")
            color: Theme.foreground
            onClicked: root.formId = ""
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: root.notice
        textFormat: Text.PlainText
        color: Theme.warning
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
    }

    // ---------------------------------------------------------------- list
    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        radius: Theme.radius
        visible: root.formId === ""
        color: Theme.surfaceAlt
        border.color: search.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        TextInput {
            id: search

            anchors.fill: parent
            anchors.leftMargin: Theme.gap * 1.5
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.subtitle
            clip: true
            onTextChanged: root.query = text
            Keys.onEscapePressed: {
                if (text !== "")
                    text = "";
                else
                    root.close();
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text === ""
                text: I18n.tr("Search plugins")
                color: Theme.muted
                font: search.font
            }
        }
    }

    Flow {
        width: parent.width
        spacing: 2
        visible: root.formId === ""

        Repeater {
            model: Model.FILTERS

            delegate: BarButton {
                required property string modelData

                height: Theme.fontSize * 2
                text: I18n.tr(Model.FILTER_LABELS[modelData]) + " " + Model.countFor(root.allRows, modelData)
                highlighted: root.filter === modelData
                color: Theme.foreground
                onClicked: root.filter = modelData
            }
        }
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, Theme.fontSize * 28)
        visible: root.formId === ""
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown

        delegate: PluginRow {
            required property var modelData

            width: list.width
            row: modelData
            stateText: I18n.tr(Model.stateLabel(modelData))
            busy: root.busyId === modelData.id
            selected: root.selected[modelData.deleteName] === true
            onToggled: on => root.setEnabled(modelData, on)
            onOpenSettings: root.openForm(modelData.id)
            onSelect: root.toggleSelected(modelData)
            onRemove: root.requestDelete([modelData.deleteName])
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2
        visible: root.formId === "" && root.selectedNames.length > 0

        BarButton {
            anchors.left: parent.left
            height: parent.height
            text: I18n.tr("Clear selection")
            color: Theme.muted
            onClicked: {
                root.selected = {};
                root.confirmDelete = "";
            }
        }

        BarButton {
            anchors.right: parent.right
            height: parent.height
            text: deleter.running ? I18n.tr("Deleting…") : I18n.tr("Delete %1", root.selectedNames.length)
            color: Theme.urgent
            onClicked: root.requestDelete(root.selectedNames)
        }
    }

    // ---------------------------------------------------------------- form
    Text {
        width: parent.width
        visible: root.formRecord !== null && root.formRecord.description !== ""
        wrapMode: Text.WordWrap
        text: root.formRecord ? root.formRecord.description : ""
        textFormat: Text.PlainText
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }

    Repeater {
        model: root.formFields

        delegate: SettingField {
            required property var modelData

            width: root.width
            field: modelData
            pending: root.edits[modelData.key]
            hasPending: Object.prototype.hasOwnProperty.call(root.edits, modelData.key)
            resetting: root.resets.indexOf(modelData.key) >= 0
            error: root.fieldErrors[modelData.key] || ""
            onEdited: text => root.stage(modelData, text)
            onReset: root.reset(modelData)
        }
    }

    Text {
        width: parent.width
        visible: root.formId !== "" && root.formFields.length === 0
        text: I18n.tr("This plugin declares no settings.")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
    }

    BarButton {
        anchors.left: parent.left
        visible: root.formId !== ""
        height: Theme.fontSize * 2.2
        text: saver.running ? I18n.tr("Saving…") : I18n.tr("Save")
        highlighted: root.formDirty
        color: root.formDirty ? Theme.accent : Theme.muted
        onClicked: root.save()
    }
}
