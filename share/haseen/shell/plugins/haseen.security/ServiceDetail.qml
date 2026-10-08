import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var service: null
    property bool stale: false
    readonly property bool owned: !stale && service && service.installed && service.ownership === "verified" && service.state !== "transitioning"
    signal requested(string verb, bool preview)
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: root.service ? Model.text(root.service.id) + " — " + Model.serviceState(root.service) : "This item changed since it was listed. Refresh and choose again." }
    Label { width: parent.width; mono: true; text: root.service ? "Unit: " + Model.text(root.service.unit) + "\nFragment: " + Model.text(root.service.fragmentPath) + "\nPackage: " + Model.text(root.service.package) + "\nActivity: " + Model.text(root.service.activeState) + "/" + Model.text(root.service.subState) : "" }
    Label { width: parent.width; text: root.service ? "Ownership: " + Model.text(root.service.ownership) + "\n" + Model.text(root.service.reason) : "" }
    Label { width: parent.width; text: "Exposure unknown: local configuration may listen beyond loopback. No enablement, initialization, binding or firewall change is performed. Authentication may be required. Stop has no confirmation prompt." }
    ActionButton { width: parent.width; text: "Start in terminal"; visible: root.service && root.service.state !== "running"; enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested("service-start", false) }
    ActionButton { width: parent.width; text: "Stop in terminal"; enabled: root.owned; onClicked: root.requested("service-stop", false) }
    ActionButton { width: parent.width; text: "Restart in terminal"; enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested("service-restart", false) }
    ActionButton { width: parent.width; text: "Preview"; enabled: root.owned && root.service.state !== "unknown"; onClicked: root.requested(root.service.state === "running" ? "service-restart" : "service-start", true) }
}
