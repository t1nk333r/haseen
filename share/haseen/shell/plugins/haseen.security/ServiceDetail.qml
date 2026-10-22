import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var service: null
    property bool stale: false
    function focusHeading(): void { title.focusHeading(); }
    readonly property bool owned: !stale && service && service.installed && service.ownership === "verified" && service.state !== "transitioning"
    signal requested(string verb, bool preview)
    spacing: Theme.gap * 2
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: root.service ? Model.text(root.service.id) + " — " + I18n.tr(Model.serviceState(root.service)) : I18n.tr("This item changed since it was listed. Refresh and choose again.") }
    SelectableText { width: parent.width; Accessible.name: I18n.tr("Service unit and FragmentPath"); text: root.service ? I18n.tr("Unit: %1", Model.text(root.service.unit)) + "\n" + I18n.tr("FragmentPath: %1", Model.text(root.service.fragmentPath)) + "\n" + I18n.tr("Package: %1", Model.text(root.service.package)) + "\n" + I18n.tr("Activity: %1/%2", Model.text(root.service.activeState), Model.text(root.service.subState)) : "" }
    Label { width: parent.width; text: root.service ? I18n.tr("Ownership: %1", Model.text(root.service.ownership)) + "\n" + Model.text(root.service.reason) : "" }
    Label { width: parent.width; text: I18n.tr("Exposure unknown: local configuration may listen beyond loopback. No enablement, initialization, binding or firewall change is performed. Authentication may be required. Stop has no confirmation prompt.") }
    ActionButton { width: parent.width; text: I18n.tr("Start in terminal"); visible: root.service && root.service.state !== "running"; enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested("service-start", false) }
    ActionButton { width: parent.width; text: I18n.tr("Stop service"); enabled: root.owned; onClicked: root.requested("service-stop", false) }
    ActionButton { width: parent.width; text: I18n.tr("Restart in terminal"); enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested("service-restart", false) }
    ActionButton { width: parent.width; text: I18n.tr("Preview"); enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested(root.service.state === "running" ? "service-restart" : "service-start", true) }
}
