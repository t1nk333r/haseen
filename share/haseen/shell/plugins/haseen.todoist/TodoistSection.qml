import QtQuick
import qs.Haseen

// A section label in the haseen.todoist panel (ACCOUNT, BAR COUNT, OVERDUE …).
Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Math.max(1, Theme.fontSize - 2)
    font.bold: true
    font.letterSpacing: 1.1
    elide: Text.ElideRight
}
