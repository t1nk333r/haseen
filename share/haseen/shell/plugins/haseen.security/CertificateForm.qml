import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property string path: ""
    property var inspection: null
    property var anchor: null
    property bool checking: false
    property bool anchorChecking: false
    function focusHeading(): void { title.focusHeading(); }
    function inspectPath(): void {
        root.pathChangedByUser(file.text);
        file.error = Model.path(file.text) ? "" : "Choose an absolute certificate path.";
        if (file.error) { file.focusInput(); Accessible.announce(file.error, Accessible.Assertive); return; }
        if (!root.checking) root.inspect(file.text);
    }
    signal pathChangedByUser(string value)
    signal inspect(string value)
    signal requested(string operation, bool preview)
    spacing: Theme.gap * 2
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: "Proxy CA anchor" }
    Field { id: file; width: parent.width; label: "Absolute certificate path"; text: root.path; onEdited: value => root.pathChangedByUser(value); onCommitted: { root.pathChangedByUser(text); error = Model.path(text) ? "" : "Choose an absolute certificate path."; } onSubmitted: root.inspectPath() }
    ActionButton { width: parent.width; text: "Inspect certificate"; enabled: !root.checking; onClicked: root.inspectPath() }
    SelectableText { width: parent.width; Accessible.name: "Certificate inspection status and diagnostics"; text: root.checking ? "Inspecting selected certificate…" : (root.inspection ? Model.text(root.inspection.state) + " • " + Model.text(root.inspection.reason) : "No certificate selected. No automatic discovery or trust.") }
    Label { width: parent.width; text: root.inspection && root.inspection.certificate ? "Subject: " + Model.text(root.inspection.certificate.subject) + "\nIssuer: " + Model.text(root.inspection.certificate.issuer) + "\nValidity: " + Model.text(root.inspection.certificate.notBefore) + " — " + Model.text(root.inspection.certificate.notAfter) : "" }
    Label { width: parent.width; text: "Inspected certificate SHA-256 fingerprint" }
    SelectableText { width: parent.width; text: root.inspection && root.inspection.certificate ? Model.fingerprint(root.inspection.certificate.sha256) : ""; Accessible.name: "SHA-256 certificate fingerprint" }
    Label { width: parent.width; text: root.anchor ? "Anchor: " + Model.text(root.anchor.state) + " • " + Model.text(root.anchor.reason) : "Reading owned anchor status…" }
    Label { width: parent.width; text: "Existing anchor SHA-256 fingerprint • ownership: " + (root.anchor ? Model.text(root.anchor.state) : "unknown") }
    SelectableText { width: parent.width; text: root.anchor && root.anchor.anchor ? Model.fingerprint(root.anchor.anchor.sha256) : "No existing anchor fingerprint available"; Accessible.name: "Existing anchor SHA-256 fingerprint and ownership"; Accessible.description: root.anchor ? root.anchor.state : "unknown" }
    Label { width: parent.width; text: "Adds a machine-wide CA trust anchor. This can allow certificates issued by this CA to be trusted for interception. This does not configure a proxy or browser profile. The terminal requires the full SHA-256 fingerprint typed; no GUI setting or --yes bypasses it." }
    ActionButton { width: parent.width; text: "Preview trust"; enabled: !root.checking && root.inspection && root.inspection.state === "valid" && root.path === file.text; onClicked: root.requested("trust", true) }
    ActionButton { width: parent.width; text: "Review trust in terminal"; enabled: !root.checking && root.inspection && root.inspection.state === "valid" && root.path === file.text; onClicked: root.requested("trust", false) }
    ActionButton { width: parent.width; text: "Review removal of owned anchor"; enabled: !root.anchorChecking; visible: root.anchor && root.anchor.state === "owned" && root.anchor.anchor && root.anchor.anchor.unchanged; onClicked: root.requested("remove", false) }
    Label { width: parent.width; visible: root.anchor && ["foreign", "modified", "unknown", "refused"].indexOf(root.anchor.state) >= 0; text: "This anchor is not unchanged haseen-owned state; removal refused." }
}
