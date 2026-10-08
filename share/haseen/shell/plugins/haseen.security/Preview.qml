import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Column {
    id: root
    property string output: ""
    property int exitCode: -1
    property bool loading: false
    signal back()
    signal review()
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: "Preview — no changes made" }
    Label { width: parent.width; text: root.loading ? "Reading preview…" : "Exit code: " + root.exitCode + (root.exitCode === 0 ? " • Plan available; not an execution result" : " • Refused or helper error") }
    Controls.TextArea { width: parent.width; readOnly: true; selectByMouse: true; activeFocusOnTab: true; text: root.output; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; color: Theme.foreground; font.family: Theme.fontMono; font.pixelSize: Math.round(12 * Theme.fontSize / 11); background: null; Accessible.name: "Read-only dry-run output" }
    ActionButton { width: parent.width; text: "Back"; onClicked: root.back() }
    ActionButton { width: parent.width; text: "Review"; enabled: !root.loading && root.exitCode === 0; onClicked: root.review() }
}
