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
    property bool showAddresses: false
    property real viewportHeight: 0
    signal reveal(var item)
    function focusHeading(): void { title.focusHeading(); }
    function cancelChoices(): bool {
        if (!showAddresses) return false;
        showAddresses = false;
        chooser.forceActiveFocus();
        return true;
    }
    property string error: ""
    signal changed(var value)
    signal chooseAddresses()
    signal requested(var value, bool preview)
    spacing: Theme.gap * 2
    function value(): var { return {address: address.text, port: port.text, path: selection.text}; }
    function validate(): var {
        const d = value();
        root.changed(d);
        const errors = Model.endpointErrors(d, capability.id);
        address.error = errors.address; port.error = errors.port; selection.error = errors.path;
        root.error = errors.address || errors.port || errors.path;
        return errors;
    }
    function submit(preview: bool): void {
        const errors = validate();
        if (root.error !== "") {
            if (errors.address) address.focusInput();
            else if (errors.port) port.focusInput();
            else selection.focusInput();
            Accessible.announce(root.error, Accessible.Assertive);
            return;
        }
        root.requested(value(), preview);
    }
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: root.capability ? {listener: "TCP listener", "http-server": "Directory server", "enumeration-host": "Selected file server"}[root.capability.id] : "Unavailable helper" }
    Label { width: parent.width; text: root.capability ? Model.text(root.capability.reason) : "No capability evidence" }
    Field { id: address; width: parent.width; label: "Local bind address"; text: root.draft.address; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.addressError(text); } onSubmitted: root.submit(false) }
    ActionButton { id: chooser; width: parent.width; text: root.showAddresses ? "Hide local interface addresses" : "Choose local interface address"; onClicked: { root.changed(root.value()); root.showAddresses = !root.showAddresses; if (root.showAddresses) root.chooseAddresses(); } }
    Row { spacing: Theme.gap; ActionButton { text: "127.0.0.1"; onClicked: { address.text = text; root.changed(root.value()); } } ActionButton { text: "::1"; onClicked: { address.text = text; root.changed(root.value()); } } }
    Inventory {
        id: addressChoices
        width: parent.width
        choices: true
        visible: root.showAddresses
        viewportHeight: root.viewportHeight
        rows: root.showAddresses ? root.addresses.map(a => ({id: JSON.stringify([a.interface, a.family, a.address]), address: a.address, label: Model.text(a.interface) + " • " + Model.text(a.address) + " • " + Model.text(a.scope)})) : []
        onReveal: item => root.reveal(item)
        onEmptyFocused: chooser.forceActiveFocus()
        onInspected: itemId => { const chosen = addressChoices.rows.find(a => a.id === itemId); if (!chosen) return; address.text = chosen.address; root.changed(root.value()); root.showAddresses = false; address.focusInput(); }
    }
    Field { id: port; width: parent.width; label: "Port (1024–65535)"; text: root.draft.port; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.endpointErrors(root.value(), root.capability.id).port; } onSubmitted: root.submit(false) }
    Field { id: selection; width: parent.width; visible: root.capability && root.capability.id !== "listener"; label: root.capability && root.capability.id === "http-server" ? "Absolute directory path" : "Absolute installed package-owned file path"; text: root.draft.path; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.endpointErrors(root.value(), root.capability.id).path; } onSubmitted: root.submit(false) }
    ActionButton { id: fileChooser; width: parent.width; visible: root.capability && root.capability.id === "enumeration-host"; text: root.showFiles ? "Hide verified file choices" : "Show verified file choices"; onClicked: root.showFiles = !root.showFiles }
    Inventory {
        width: parent.width
        choices: true
        viewportHeight: root.viewportHeight
        onReveal: item => root.reveal(item)
        onEmptyFocused: fileChooser.forceActiveFocus()
        rows: root.showFiles ? root.files.map(f => ({id: f, label: "Select owned file: " + Model.text(f)})) : []
        onInspected: itemId => { selection.text = itemId; root.changed(root.value()); }
    }
    Label { width: parent.width; text: root.error }
    Label { width: parent.width; text: "Only literal local addresses; no DNS or probes. Loopback is local-only. Non-loopback and wildcard exposure requires terminal confirmation. Runs in that terminal until stopped with Ctrl+C." }
    ActionButton { width: parent.width; text: "Preview"; enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(true) }
    ActionButton { width: parent.width; text: "Review"; enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(false) }
}
