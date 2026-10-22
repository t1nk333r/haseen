import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var tool: null
    property string entryId: ""
    property bool stale: false
    function focusHeading(): void { title.focusHeading(); }
    readonly property var selected: Model.entry(tool, entryId)
    readonly property bool allowed: !stale && tool && tool.state === "installed" && selected && selected.usage.state === "ready"
    signal pick()
    signal requested(string verb, bool preview)
    spacing: Theme.gap * 2
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: root.tool ? Model.text(root.tool.id) : I18n.tr("This item changed since it was listed. Refresh and choose again.") }
    Label { width: parent.width; text: root.tool ? I18n.tr(Model.toolState(root.tool)) + "\n" + Model.text(root.tool.reason) + "\n" + I18n.tr("Groups: %1", root.tool.groups.map(Model.text).join(", ")) : "" }
    Repeater { model: root.tool ? root.tool.packages : []; delegate: Label { required property var modelData; width: root.width; text: I18n.tr("%1 %2 • Provenance: %3 • Sources: %4", Model.text(modelData.name), Model.text(modelData.version), Model.text(modelData.provenance), modelData.source.map(Model.text).join(", ")) } }
    Label { width: parent.width; text: root.tool && root.tool.resolution ? I18n.tr("Recorded resolution: %1/%2 (not installed evidence)", Model.text(root.tool.resolution.source), Model.text(root.tool.resolution.target)) : "" }
    SelectableText { width: parent.width; Accessible.name: I18n.tr("Selected entrypoint path"); text: root.selected ? Model.text(root.selected.path) : I18n.tr("No verified executable entrypoint selected. Data-only or unavailable entry evidence.") }
    ActionButton { width: parent.width; visible: root.tool && root.tool.entrypoints.length > 1; text: I18n.tr("Choose entrypoint"); onClicked: root.pick() }
    Label { width: parent.width; text: root.selected ? (root.selected.usage.state === "ready" ? (root.selected.usage.kind === "reviewed-argv" ? I18n.tr("Explicit request will invoke the reviewed help-only binding.") : I18n.tr("Owned documentation available.")) : I18n.tr("Documentation unavailable. haseen will not guess a help command.") + "\n" + Model.text(root.selected.usage.reason)) : I18n.tr("No help or shell action is authorized without selected usage evidence.") }
    Repeater { model: root.selected ? root.selected.documentation : []; delegate: SelectableText { required property var modelData; width: root.width; Accessible.name: I18n.tr("Owned documentation path"); text: Model.text(modelData.kind) + ": " + Model.text(modelData.path) } }
    Label { width: parent.width; text: I18n.tr("The selected tool is not executed or prefilled. The terminal revalidates usage and shell evidence and may refuse.") }
    ActionButton { width: parent.width; text: I18n.tr("Show documentation"); enabled: root.allowed; explanation: root.selected ? Model.text(root.selected.usage.reason) : I18n.tr("No selected entry"); onClicked: root.requested("tool-help", false) }
    ActionButton { width: parent.width; text: I18n.tr("Open shell after documentation"); enabled: root.allowed; onClicked: root.requested("tool-run", false) }
    ActionButton { width: parent.width; text: I18n.tr("Preview"); enabled: root.allowed; onClicked: root.requested("tool-run", true) }
}
