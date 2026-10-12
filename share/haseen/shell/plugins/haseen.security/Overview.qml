import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var status: null
    property var sources: null
    property int serviceCount: 0
    spacing: Theme.gap * 2
    Label { width: parent.width; text: "Installed status and explicit local actions. Nothing runs when this panel opens." }
    Label { width: parent.width; heading: true; text: root.status ? "Provisioning: " + Model.text(root.status.provisioning.state) : "Reading provisioning status…" }
    Label { width: parent.width; text: root.status ? root.status.provisioning.diagnostics.map(Model.text).join("\n") : "" }
    Label { width: parent.width; text: root.status ? "Installed tools: " + root.status.tools.filter(t => t.state === "installed").length + " • Installed service families: " + root.serviceCount + "\nVerified entrypoints: " + root.status.workflow.entrypoints + " • Documentation ready: " + root.status.workflow.documentationReady : "" }
    Label { width: parent.width; text: "Installed packages and shared key trust may remain when a source is unavailable. Cached source policy is not executable-byte attestation." }
    Repeater {
        model: root.status ? root.status.sources : []
        delegate: Label { required property var modelData; width: root.width; text: Model.text(modelData.name) + " — Source policy: " + Model.text(modelData.state) + " • Cached inventory: " + modelData.cachedPackages }
    }
    Label { width: parent.width; text: root.status ? "Private source: " + Model.text(root.status.privateSource.state) + "\n" + Model.text(root.status.privateSource.reason) : "" }
    Repeater {
        model: root.sources ? root.sources.repositories : []
        delegate: Label { required property var modelData; width: root.width; text: Model.text(modelData.name) + ": " + Model.text(modelData.state) + "\n" + Model.text(modelData.reason) + "\nDatabase signature: " + Model.text(modelData.databaseSignatureState) + " • Keyring authority: " + Model.text(modelData.keyringAuthorityState) }
    }
}
