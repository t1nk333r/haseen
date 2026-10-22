// Adapted from BarWidget.qml (the bar popup) and the rules window of
// K53N0/omarchy-browser-picker (MIT, Copyright (c) 2026 K53N0), via the
// owner's fork t1nk33r.browser-picker; see LICENSE and UPSTREAM.md beside
// this file.
// haseen: one lazily loaded panel on Theme tokens for both; the default
// browser goes through `haseen setup default browser`, settings through
// `haseen plugin settings`; the rules are the service's.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Whether links ask at all (the default browser), the four settings, and
// every routing rule: edit a site in place, click its profile to pick
// another, ✕ removes it; "Add a rule" takes a site and then a profile.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles["browser-picker"];
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property string bin: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property var pickerSettings: Model.parseSettings(settings)
    readonly property var entries: service ? service.entries : []
    readonly property var rules: service ? Model.filterRules(service.rules, ruleFilter) : []

    property string defaultBrowser: ""
    readonly property bool isDefault: defaultBrowser === "haseen-browser-picker.desktop"
    property string ruleFilter: ""
    // The rule whose profile is being chosen; "" with addPattern set: a new one.
    property string choosingFor: ""
    property string addPattern: ""
    readonly property bool choosing: choosingFor !== "" || addPattern !== ""

    function labelFor(entryId: string): string {
        const e = Model.entryById(entries, entryId);
        return e ? e.label : "";
    }

    // Applied at once, written to shell.json by the CLI; detached so closing
    // the panel on the same click cannot lose it.
    function setSetting(key: string, value: var): void {
        Config.setRuntime(["plugins", root.pluginId, "settings", key], value);
        const body = {};
        body[key] = value;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$2\" | \"$1\" \"$3\" --yes >/dev/null", "sh", root.bin + "/haseen-plugin-settings", JSON.stringify({
                    settings: body
                }), root.pluginId]);
    }

    function pickTarget(entryId: string): void {
        if (!service)
            return;
        if (choosingFor !== "") {
            const rule = service.rules.find(r => r.pattern === choosingFor);
            if (rule)
                service.applyRule(rule.pattern, rule.pattern, entryId);
        } else if (addPattern !== "") {
            service.applyRule("", addPattern, entryId);
            addField.text = "";
        }
        choosingFor = "";
        addPattern = "";
    }

    width: Theme.fontSize * 32
    spacing: Theme.gap

    Component.onCompleted: {
        defaultProbe.running = true;
        if (service)
            service.scan();
    }

    Process {
        id: defaultProbe

        command: ["sh", "-c", "env -u BROWSER xdg-settings get default-web-browser"]
        stdout: StdioCollector {
            id: defaultOut
        }
        onExited: root.defaultBrowser = defaultOut.text.trim()
    }

    Process {
        id: makeDefault

        command: [root.bin + "/haseen-browser-picker", "--default"]
        onExited: defaultProbe.running = true
    }

    // Test hook (settings.debugIpc): read and drive the open panel.
    IpcHandler {
        target: "haseen.browser-picker.panel"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                service: root.service !== null,
                defaultBrowser: root.defaultBrowser,
                isDefault: root.isDefault,
                settings: root.pickerSettings,
                rules: root.rules.map(r => r.pattern + "=" + r.entryId + "=" + root.labelFor(r.entryId)),
                choosing: root.choosing
            });
        }

        function add(pattern: string, entryId: string): void {
            root.addPattern = pattern;
            root.pickTarget(entryId);
        }

        function retarget(pattern: string, entryId: string): void {
            root.choosingFor = pattern;
            root.pickTarget(entryId);
        }

        function remove(pattern: string): void {
            if (root.service)
                root.service.removeRule(pattern);
        }

        function set(key: string, value: bool): void {
            root.setSetting(key, value);
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2

        Glyph {
            id: heroGlyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\u{f059f}"
            color: Theme.accent
        }

        Text {
            anchors.left: heroGlyph.right
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Browser picker")
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        BarButton {
            anchors.right: parent.right
            height: parent.height
            glyph: "\u{f0349}"
            text: I18n.tr("Open a browser")
            color: Theme.foreground
            onClicked: Apps.launch([root.bin + "/haseen-browser-picker"])
        }
    }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        visible: root.service === null
        text: I18n.tr("The picker is not running: add haseen.browser-picker to shell.json services (haseen plugin enable haseen.browser-picker).")
        color: Theme.warning
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.6

        Text {
            anchors.left: parent.left
            anchors.right: defaultButton.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.isDefault ? I18n.tr("Every link asks here (the default browser)") : root.defaultBrowser.replace(/\.desktop$/, "") !== "" ? I18n.tr("Links open in %1", root.defaultBrowser.replace(/\.desktop$/, "")) : I18n.tr("Links open in another browser")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        BarButton {
            id: defaultButton

            anchors.right: parent.right
            height: parent.height
            visible: !root.isDefault
            text: makeDefault.running ? I18n.tr("Setting…") : I18n.tr("Make default")
            color: Theme.accent
            onClicked: if (!makeDefault.running)
                makeDefault.running = true
        }
    }

    SettingRow {
        label: I18n.tr("Open matching rules without asking")
        detail: I18n.tr("Off: rules only rank the list")
        checked: root.pickerSettings.autoOpenRules
        onToggled: on => root.setSetting("autoOpenRules", on)
    }

    SettingRow {
        label: I18n.tn("Offer a rule after %1 pick", "Offer a rule after %1 picks", root.pickerSettings.promptAfter)
        detail: I18n.tr("the same site to the same profile; Ctrl+Enter accepts")
        checked: root.pickerSettings.learnRules
        onToggled: on => root.setSetting("learnRules", on)
    }

    SettingRow {
        label: I18n.tr("Plain browsers first")
        detail: I18n.tr("browsers without profiles head the unfiltered list")
        checked: root.pickerSettings.genericFirst
        onToggled: on => root.setSetting("genericFirst", on)
    }

    Text {
        width: parent.width
        text: root.service ? I18n.tn("%1 rule", "%1 rules", root.service.rules.length) : I18n.tr("Rules")
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.2
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: filterField.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth
        visible: root.service !== null && root.service.rules.length > 3

        TextInput {
            id: filterField

            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            clip: true
            onTextChanged: root.ruleFilter = text

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: filterField.text === ""
                text: I18n.tr("Filter by site or profile")
                color: Theme.muted
                font: filterField.font
            }
        }
    }

    ListView {
        id: ruleList

        width: parent.width
        height: Math.min(contentHeight, Theme.fontSize * 16)
        visible: !root.choosing && root.rules.length > 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.rules

        delegate: RuleRow {
            required property var modelData

            width: ruleList.width
            rule: modelData
            targetLabel: root.labelFor(modelData.entryId)
            onRenamed: (oldPattern, newPattern) => root.service.applyRule(oldPattern, newPattern, modelData.entryId)
            onChooseTarget: root.choosingFor = modelData.pattern
            onRemoved: root.service.removeRule(modelData.pattern)
        }
    }

    Text {
        width: parent.width
        visible: !root.choosing && root.rules.length === 0
        wrapMode: Text.WordWrap
        text: root.ruleFilter !== "" ? I18n.tr("No rule matches.") : I18n.tr("No rules yet. Pick the same profile for a site a few times and the picker offers one, or add one here.")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // A site, then Enter: the profile list below picks where it opens.
    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.2
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: addField.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth
        visible: root.service !== null && !root.choosing

        TextInput {
            id: addField

            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            clip: true
            onAccepted: {
                const p = text.trim().toLowerCase();
                if (p !== "")
                    root.addPattern = p;
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: addField.text === ""
                text: I18n.tr("Add a rule: type a site (example.com covers its subdomains), then Enter")
                elide: Text.ElideRight
                width: parent.width - Theme.gap
                color: Theme.muted
                font: addField.font
            }
        }
    }

    Text {
        width: parent.width
        visible: root.choosing
        text: I18n.tr("Open %1 in:", root.choosingFor || root.addPattern)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    ListView {
        id: targets

        width: parent.width
        height: Math.min(contentHeight, Theme.fontSize * 18)
        visible: root.choosing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.choosing ? root.entries : []

        delegate: Item {
            id: target

            required property var modelData

            width: targets.width
            height: Math.round(Theme.fontSize * 2.2)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surfaceAlt
                visible: hover.containsMouse
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                verticalAlignment: Text.AlignVCenter
                text: target.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.pickTarget(target.modelData.id)
            }
        }
    }

    BarButton {
        anchors.left: parent.left
        visible: root.choosing
        text: I18n.tr("Cancel")
        color: Theme.muted
        height: Theme.fontSize * 2
        onClicked: {
            root.choosingFor = "";
            root.addPattern = "";
        }
    }
}
