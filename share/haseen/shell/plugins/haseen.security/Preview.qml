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
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: "Preview — no changes made" }
    Label { width: parent.width; text: root.loading ? "Reading preview…" : "Exit code: " + root.exitCode + (root.exitCode === 0 ? " • Plan available; not an execution result" : " • Refused or helper error") }
    SelectableText { width: parent.width; text: root.output; Accessible.name: "Read-only dry-run output" }
    ActionButton { width: parent.width; text: "Back"; onClicked: root.back() }
    ActionButton { width: parent.width; text: "Review"; enabled: !root.loading && root.exitCode === 0; onClicked: root.review() }
}
