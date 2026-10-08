import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var capability: null
    property var draft: ({address: "", port: "", path: ""})
    property var addresses: []
    property var files: []
    property bool showFiles: false
    property string error: ""
    signal changed(var value)
    signal chooseAddresses()
    signal requested(var value, bool preview)
    spacing: Theme.gap * 2
    function value(): var { return {address: address.text, port: port.text, path: selection.text}; }
    function submit(preview: bool): void {
        const d = value();
        root.changed(d);
        root.error = Model.endpointError(d, capability.id);
        address.error = ""; port.error = ""; selection.error = "";
        if (root.error !== "") {
            if (!d.address || root.error.indexOf("address") >= 0) { address.error = root.error; address.focusInput(); }
            else if (!d.port || root.error.indexOf("port") >= 0) { port.error = root.error; port.focusInput(); }
            else { selection.error = root.error; selection.focusInput(); }
            return;
        }
        root.requested(d, preview);
    }
    Label { width: parent.width; heading: true; text: root.capability ? {listener: "TCP listener", "http-server": "Directory server", "enumeration-host": "Selected file server"}[root.capability.id] : "Unavailable helper" }
    Label { width: parent.width; text: root.capability ? Model.text(root.capability.reason) : "No capability evidence" }
    Field { id: address; width: parent.width; label: "Local bind address"; text: root.draft.address; onCommitted: root.changed(root.value()) }
    ActionButton { width: parent.width; text: "Choose local interface address"; onClicked: { root.changed(root.value()); root.chooseAddresses(); } }
    Row { spacing: Theme.gap; ActionButton { text: "127.0.0.1"; onClicked: { address.text = text; root.changed(root.value()); } } ActionButton { text: "::1"; onClicked: { address.text = text; root.changed(root.value()); } } }
    Inventory {
        width: parent.width
        choices: true
        rows: root.addresses.map(a => ({id: a.address + (a.scope === "link" && a.family === "ipv6" ? "%" + a.interface : ""), label: Model.text(a.interface) + " • " + Model.text(a.address) + " • " + Model.text(a.scope)}))
        onInspected: itemId => { address.text = itemId; root.changed(root.value()); }
    }
    Field { id: port; width: parent.width; label: "Port (1024–65535)"; text: root.draft.port; onCommitted: root.changed(root.value()) }
    Field { id: selection; width: parent.width; visible: root.capability && root.capability.id !== "listener"; label: root.capability && root.capability.id === "http-server" ? "Absolute directory path" : "Absolute installed package-owned file path"; text: root.draft.path; onCommitted: root.changed(root.value()) }
    ActionButton { width: parent.width; visible: root.capability && root.capability.id === "enumeration-host"; text: root.showFiles ? "Hide verified file choices" : "Show verified file choices"; onClicked: root.showFiles = !root.showFiles }
    Inventory {
        width: parent.width
        choices: true
        rows: root.showFiles ? root.files.map(f => ({id: f, label: "Select owned file: " + Model.text(f)})) : []
        onInspected: itemId => { selection.text = itemId; root.changed(root.value()); }
    }
    Label { width: parent.width; text: root.error }
    Label { width: parent.width; text: "Only literal local addresses; no DNS or probes. Loopback is local-only. Non-loopback and wildcard exposure requires terminal confirmation. Runs in that terminal until stopped with Ctrl+C." }
    ActionButton { width: parent.width; text: "Preview"; enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(true) }
    ActionButton { width: parent.width; text: "Review"; enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(false) }
}
