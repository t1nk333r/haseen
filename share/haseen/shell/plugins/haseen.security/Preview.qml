import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Column {
    id: root
    property string output: ""
    property int exitCode: -1
    property bool loading: false
    function focusHeading(): void { title.focusHeading(); }
    signal back()
    signal review()
    spacing: Theme.gap * 2
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: I18n.tr("Preview — no changes made") }
    Label { width: parent.width; text: root.loading ? I18n.tr("Reading preview…") : root.exitCode === 0 ? I18n.tr("Exit code: %1 • Plan available; not an execution result", root.exitCode) : I18n.tr("Exit code: %1 • Refused or helper error", root.exitCode) }
    // Terminal output: never mirrored, always from the left.
    SelectableText { width: parent.width; text: root.output; Accessible.name: I18n.tr("Read-only dry-run output"); LayoutMirroring.enabled: false; horizontalAlignment: TextEdit.AlignLeft }
    ActionButton { width: parent.width; text: I18n.tr("Back"); onClicked: root.back() }
    ActionButton { width: parent.width; text: I18n.tr("Review"); enabled: !root.loading && root.exitCode === 0; onClicked: root.review() }
}
