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
            Accessible.announce(I18n.tr(root.error), Accessible.Assertive);
            return;
        }
        root.requested(value(), preview);
    }
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: root.capability ? {listener: I18n.tr("TCP listener"), "http-server": I18n.tr("Directory server"), "enumeration-host": I18n.tr("Selected file server")}[root.capability.id] : I18n.tr("Unavailable helper") }
    Label { width: parent.width; text: root.capability ? Model.text(root.capability.reason) : I18n.tr("No capability evidence") }
    Field { id: address; width: parent.width; label: I18n.tr("Local bind address"); text: root.draft.address; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.addressError(text); } onSubmitted: root.submit(false) }
    ActionButton { id: chooser; width: parent.width; text: root.showAddresses ? I18n.tr("Hide local interface addresses") : I18n.tr("Choose local interface address"); onClicked: { root.changed(root.value()); root.showAddresses = !root.showAddresses; if (root.showAddresses) root.chooseAddresses(); } }
    // At the start of the form: on the right in a mirrored panel.
    Row { anchors.left: parent.left; spacing: Theme.gap; ActionButton { text: "127.0.0.1"; onClicked: { address.text = text; root.changed(root.value()); } } ActionButton { text: "::1"; onClicked: { address.text = text; root.changed(root.value()); } } }
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
    Field { id: port; width: parent.width; label: I18n.tr("Port (1024–65535)"); text: root.draft.port; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.endpointErrors(root.value(), root.capability.id).port; } onSubmitted: root.submit(false) }
    Field { id: selection; width: parent.width; visible: root.capability && root.capability.id !== "listener"; label: root.capability && root.capability.id === "http-server" ? I18n.tr("Absolute directory path") : I18n.tr("Absolute installed package-owned file path"); text: root.draft.path; onEdited: root.changed(root.value()); onCommitted: { root.changed(root.value()); error = Model.endpointErrors(root.value(), root.capability.id).path; } onSubmitted: root.submit(false) }
    ActionButton { id: fileChooser; width: parent.width; visible: root.capability && root.capability.id === "enumeration-host"; text: root.showFiles ? I18n.tr("Hide verified file choices") : I18n.tr("Show verified file choices"); onClicked: root.showFiles = !root.showFiles }
    Inventory {
        width: parent.width
        choices: true
        viewportHeight: root.viewportHeight
        onReveal: item => root.reveal(item)
        onEmptyFocused: fileChooser.forceActiveFocus()
        rows: root.showFiles ? root.files.map(f => ({id: f, label: I18n.tr("Select owned file: %1", Model.text(f))})) : []
        onInspected: itemId => { selection.text = itemId; root.changed(root.value()); }
    }
    Label { width: parent.width; text: I18n.tr(root.error) }
    Label { width: parent.width; text: I18n.tr("Only literal local addresses; no DNS or probes. Loopback is local-only. Non-loopback and wildcard exposure requires terminal confirmation. Runs in that terminal until stopped with Ctrl+C.") }
    ActionButton { width: parent.width; text: I18n.tr("Preview"); enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(true) }
    ActionButton { width: parent.width; text: I18n.tr("Review"); enabled: root.capability && root.capability.installed && !Model.member(root.capability.state, ["missing", "unknown", "refused"]); onClicked: root.submit(false) }
}
