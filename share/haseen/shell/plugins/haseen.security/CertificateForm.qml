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
    signal pathChangedByUser(string value)
    signal inspect(string value)
    signal requested(string operation, bool preview)
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: "Proxy CA anchor" }
    Field { id: file; width: parent.width; label: "Absolute certificate path"; text: root.path; onCommitted: root.pathChangedByUser(text) }
    ActionButton { width: parent.width; text: "Inspect certificate"; enabled: !root.checking && Model.path(file.text); onClicked: { root.pathChangedByUser(file.text); root.inspect(file.text); } }
    Label { width: parent.width; text: root.checking ? "Inspecting selected certificate…" : (root.inspection ? Model.text(root.inspection.state) + " • " + Model.text(root.inspection.reason) : "No certificate selected. No automatic discovery or trust.") }
    Label { width: parent.width; text: root.inspection && root.inspection.certificate ? "Subject: " + Model.text(root.inspection.certificate.subject) + "\nIssuer: " + Model.text(root.inspection.certificate.issuer) + "\nValidity: " + Model.text(root.inspection.certificate.notBefore) + " — " + Model.text(root.inspection.certificate.notAfter) : "" }
    Controls.TextArea { width: parent.width; readOnly: true; selectByMouse: true; activeFocusOnTab: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; text: root.inspection && root.inspection.certificate ? Model.fingerprint(root.inspection.certificate.sha256) : ""; color: Theme.foreground; font.family: Theme.fontMono; font.pixelSize: Math.round(12 * Theme.fontSize / 11); background: null; Accessible.name: "SHA-256 certificate fingerprint" }
    Label { width: parent.width; text: root.anchor ? "Anchor: " + Model.text(root.anchor.state) + " • " + Model.text(root.anchor.reason) : "Reading owned anchor status…" }
    Label { width: parent.width; text: "Adds a machine-wide CA trust anchor. This can allow certificates issued by this CA to be trusted for interception. This does not configure a proxy or browser profile. The terminal requires the full SHA-256 fingerprint typed; no GUI setting or --yes bypasses it." }
    ActionButton { width: parent.width; text: "Preview trust"; enabled: !root.checking && root.inspection && root.inspection.state === "valid" && root.path === file.text; onClicked: root.requested("trust", true) }
    ActionButton { width: parent.width; text: "Review trust in terminal"; enabled: !root.checking && root.inspection && root.inspection.state === "valid" && root.path === file.text; onClicked: root.requested("trust", false) }
    ActionButton { width: parent.width; text: "Review removal of owned anchor"; enabled: !root.anchorChecking; visible: root.anchor && root.anchor.state === "owned" && root.anchor.anchor && root.anchor.anchor.unchanged; onClicked: root.requested("remove", false) }
    Label { width: parent.width; visible: root.anchor && ["foreign", "modified", "unknown", "refused"].indexOf(root.anchor.state) >= 0; text: "This anchor is not unchanged haseen-owned state; removal refused." }
}
