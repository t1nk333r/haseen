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
        file.error = Model.path(file.text) ? "" : I18n.mark("Choose an absolute certificate path.");
        if (file.error) { file.focusInput(); Accessible.announce(I18n.tr(file.error), Accessible.Assertive); return; }
        if (!root.checking) root.inspect(file.text);
    }
    signal pathChangedByUser(string value)
    signal inspect(string value)
    signal requested(string operation, bool preview)
    spacing: Theme.gap * 2
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: I18n.tr("Proxy CA anchor") }
    Field { id: file; width: parent.width; label: I18n.tr("Absolute certificate path"); text: root.path; onEdited: value => root.pathChangedByUser(value); onCommitted: { root.pathChangedByUser(text); error = Model.path(text) ? "" : I18n.mark("Choose an absolute certificate path."); } onSubmitted: root.inspectPath() }
    ActionButton { width: parent.width; text: I18n.tr("Inspect certificate"); enabled: !root.checking; onClicked: root.inspectPath() }
    SelectableText { width: parent.width; Accessible.name: I18n.tr("Certificate inspection status and diagnostics"); text: root.checking ? I18n.tr("Inspecting selected certificate…") : (root.inspection ? Model.text(root.inspection.state) + " • " + Model.text(root.inspection.reason) : I18n.tr("No certificate selected. No automatic discovery or trust.")) }
    Label { width: parent.width; text: root.inspection && root.inspection.certificate ? I18n.tr("Subject: %1", Model.text(root.inspection.certificate.subject)) + "\n" + I18n.tr("Issuer: %1", Model.text(root.inspection.certificate.issuer)) + "\n" + I18n.tr("Validity: %1 — %2", Model.text(root.inspection.certificate.notBefore), Model.text(root.inspection.certificate.notAfter)) : "" }
    Label { width: parent.width; text: I18n.tr("Inspected certificate SHA-256 fingerprint") }
    SelectableText { width: parent.width; text: root.inspection && root.inspection.certificate ? Model.fingerprint(root.inspection.certificate.sha256) : ""; Accessible.name: I18n.tr("SHA-256 certificate fingerprint") }
    Label { width: parent.width; text: root.anchor ? I18n.tr("Anchor: %1 • %2", Model.text(root.anchor.state), Model.text(root.anchor.reason)) : I18n.tr("Reading owned anchor status…") }
    Label { width: parent.width; visible: root.anchor && root.anchor.anchor && root.anchor.anchor.transaction !== undefined; text: I18n.tr("Anchor transaction: %1", root.anchor && root.anchor.anchor ? Model.text(root.anchor.anchor.transaction) : "") }
    Label { width: parent.width; text: I18n.tr("Existing anchor SHA-256 fingerprint • ownership: %1", root.anchor ? Model.text(root.anchor.state) : I18n.tr("unknown")) }
    SelectableText { width: parent.width; text: root.anchor && root.anchor.anchor ? Model.fingerprint(root.anchor.anchor.sha256) : I18n.tr("No existing anchor fingerprint available"); Accessible.name: I18n.tr("Existing anchor SHA-256 fingerprint and ownership"); Accessible.description: root.anchor ? root.anchor.state : I18n.tr("unknown") }
    Label { width: parent.width; text: I18n.tr("Adds a machine-wide CA trust anchor. This can allow certificates issued by this CA to be trusted for interception. This does not configure a proxy or browser profile. The terminal requires the full SHA-256 fingerprint typed; no GUI setting or --yes bypasses it.") }
    ActionButton { width: parent.width; text: I18n.tr("Preview trust"); enabled: !root.checking && !root.anchorChecking && Model.anchorTrust(root.anchor, root.inspection) && root.path === file.text; onClicked: root.requested("trust", true) }
    ActionButton { width: parent.width; text: root.anchor && root.anchor.anchor && root.anchor.anchor.transaction === "pending" ? I18n.tr("Review trust retry in terminal") : I18n.tr("Review trust in terminal"); enabled: !root.checking && !root.anchorChecking && Model.anchorTrust(root.anchor, root.inspection) && root.path === file.text; onClicked: root.requested("trust", false) }
    ActionButton { width: parent.width; text: root.anchor && root.anchor.anchor && root.anchor.anchor.transaction === "removing" ? I18n.tr("Review removal retry") : I18n.tr("Review removal of owned anchor"); enabled: !root.anchorChecking; visible: Model.anchorRemoval(root.anchor); onClicked: root.requested("remove", false) }
    Label { width: parent.width; visible: root.anchor && root.anchor.state !== "none" && !Model.anchorRemoval(root.anchor); text: I18n.tr("This anchor has no safe haseen-owned recovery path; removal refused.") }
}
