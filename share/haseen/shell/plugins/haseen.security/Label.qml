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
    font.pixelSize: Math.round((heading ? 14 : 12) * Math.max(1 / 11, Theme.fontSize / 11))
    font.bold: heading
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    Accessible.role: Accessible.StaticText
    Accessible.name: text
}
