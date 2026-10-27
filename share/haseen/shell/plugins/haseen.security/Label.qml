import QtQuick
import qs.Haseen
Text {
    property bool heading: false
    property bool mono: false
    property bool entryHeading: false
    activeFocusOnTab: entryHeading
    function focusHeading(): void {
        forceActiveFocus();
        Accessible.announce(text, Accessible.Polite);
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        color: "transparent"
        border.width: parent.activeFocus && parent.entryHeading ? 2 : 0
        border.color: Theme.foreground
    }
    color: Theme.foreground
    font.family: mono ? Theme.fontMono : Theme.fontFamily
    font.pixelSize: heading ? Theme.font.title : Theme.font.body
    font.bold: heading
    wrapMode: Text.Wrap
    // Set, not implied: Qt mirrors only an explicit alignment, so in a
    // mirrored (right-to-left) panel every label, Latin evidence included,
    // starts on the right instead of following its own script.
    horizontalAlignment: Text.AlignLeft
    textFormat: Text.PlainText
    Accessible.role: Accessible.StaticText
    Accessible.name: text
}
