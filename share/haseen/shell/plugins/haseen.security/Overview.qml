import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var status: null
    property var sources: null
    property int serviceCount: 0
    spacing: Theme.gap * 2
    Label { width: parent.width; text: I18n.tr("Installed status and explicit local actions. Nothing runs when this panel opens.") }
    Label { width: parent.width; heading: true; text: root.status ? I18n.tr("Provisioning: %1", Model.text(root.status.provisioning.state)) : I18n.tr("Reading provisioning status…") }
    Label { width: parent.width; text: root.status ? root.status.provisioning.diagnostics.map(Model.text).join("\n") : "" }
    Label { width: parent.width; text: root.status ? I18n.tr("Installed tools: %1 • Installed service families: %2", root.status.tools.filter(t => t.state === "installed").length, root.serviceCount) + "\n" + I18n.tr("Verified entrypoints: %1 • Documentation ready: %2", root.status.workflow.entrypoints, root.status.workflow.documentationReady) : "" }
    Label { width: parent.width; text: I18n.tr("Installed packages and shared key trust may remain when a source is unavailable. Cached source policy is not executable-byte attestation.") }
    Repeater {
        model: root.status ? root.status.sources : []
        delegate: Label { required property var modelData; width: root.width; text: I18n.tr("%1 — Source policy: %2 • Cached inventory: %3", Model.text(modelData.name), Model.text(modelData.state), modelData.cachedPackages) }
    }
    Label { width: parent.width; text: root.status ? I18n.tr("Private source: %1", Model.text(root.status.privateSource.state)) + "\n" + Model.text(root.status.privateSource.reason) : "" }
    Repeater {
        model: root.sources ? root.sources.repositories : []
        delegate: Label { required property var modelData; width: root.width; text: Model.text(modelData.name) + ": " + Model.text(modelData.state) + "\n" + Model.text(modelData.reason) + "\n" + I18n.tr("Database signature: %1 • Keyring authority: %2", Model.text(modelData.databaseSignatureState), Model.text(modelData.keyringAuthorityState)) }
    }
}
