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
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: root.tool ? Model.text(root.tool.id) : "This item changed since it was listed. Refresh and choose again." }
    Label { width: parent.width; text: root.tool ? Model.toolState(root.tool) + "\n" + Model.text(root.tool.reason) + "\nGroups: " + root.tool.groups.map(Model.text).join(", ") : "" }
    Repeater { model: root.tool ? root.tool.packages : []; delegate: Label { required property var modelData; width: root.width; text: Model.text(modelData.name) + " " + Model.text(modelData.version) + " • Provenance: " + Model.text(modelData.provenance) + " • Sources: " + modelData.source.map(Model.text).join(", ") } }
    Label { width: parent.width; text: root.tool && root.tool.resolution ? "Recorded resolution: " + Model.text(root.tool.resolution.source) + "/" + Model.text(root.tool.resolution.target) + " (not installed evidence)" : "" }
    SelectableText { width: parent.width; Accessible.name: "Selected entrypoint path"; text: root.selected ? Model.text(root.selected.path) : "No verified executable entrypoint selected. Data-only or unavailable entry evidence." }
    ActionButton { width: parent.width; visible: root.tool && root.tool.entrypoints.length > 1; text: "Choose entrypoint"; onClicked: root.pick() }
    Label { width: parent.width; text: root.selected ? (root.selected.usage.state === "ready" ? (root.selected.usage.kind === "reviewed-argv" ? "Explicit request will invoke the reviewed help-only binding." : "Owned documentation available.") : "Documentation unavailable. haseen will not guess a help command.\n" + Model.text(root.selected.usage.reason)) : "No help or shell action is authorized without selected usage evidence." }
    Repeater { model: root.selected ? root.selected.documentation : []; delegate: SelectableText { required property var modelData; width: root.width; Accessible.name: "Owned documentation path"; text: Model.text(modelData.kind) + ": " + Model.text(modelData.path) } }
    Label { width: parent.width; text: "The selected tool is not executed or prefilled. The terminal revalidates usage and shell evidence and may refuse." }
    ActionButton { width: parent.width; text: "Show documentation"; enabled: root.allowed; explanation: root.selected ? Model.text(root.selected.usage.reason) : "No selected entry"; onClicked: root.requested("tool-help", false) }
    ActionButton { width: parent.width; text: "Open shell after documentation"; enabled: root.allowed; onClicked: root.requested("tool-run", false) }
    ActionButton { width: parent.width; text: "Preview"; enabled: root.allowed; onClicked: root.requested("tool-run", true) }
}
