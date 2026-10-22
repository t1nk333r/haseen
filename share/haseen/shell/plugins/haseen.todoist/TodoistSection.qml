import QtQuick
import qs.Haseen

// A section label in the haseen.todoist panel (ACCOUNT, BAR COUNT, OVERDUE …).
Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    // Set, not implicit, so a right-to-left panel mirrors it to the right
    // even when the label is Latin (a service name).
    horizontalAlignment: Text.AlignLeft
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Math.max(1, Theme.fontSize - 2)
    font.bold: true
    font.letterSpacing: 1.1
    elide: Text.ElideRight
}
