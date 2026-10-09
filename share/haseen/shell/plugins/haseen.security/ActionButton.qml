import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
import qs.Haseen.Widgets
import "../../Haseen/Ink.js" as Ink
Controls.Button {
    id: control
    property bool current: false
    property string explanation: ""
    property string glyph: ""
    property bool glyphOnly: false
    readonly property real scale: Math.max(1 / 11, Theme.fontSize / 11)
    implicitHeight: Math.max(40 * scale, contentItem.implicitHeight + 24 * scale)
    implicitWidth: contentItem.implicitWidth + 24 * scale
    padding: 12 * scale
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.description: explanation
    contentItem: Item {
        implicitWidth: label.implicitWidth + (icon.visible ? icon.width : 0)
        implicitHeight: Math.max(label.implicitHeight, icon.visible ? icon.height : 0)
        Glyph {
            id: icon
            glyph: control.glyph
            visible: glyph !== ""
            width: 28 * control.scale
            height: 24 * control.scale
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Math.round(18 * control.scale)
            Accessible.ignored: true
        }
        Label {
            id: label
            x: icon.visible ? icon.width : 0
            width: parent.width - x
            height: implicitHeight
            text: control.text
            font.family: control.glyphOnly ? Theme.fontMono : Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    background: Rectangle {
        color: control.current && Ink.ratio(Theme.foreground, Theme.selection) >= 4.5 ? Theme.selection : (control.hovered ? Theme.surfaceAlt : Theme.surface)
        radius: Theme.radius
        border.width: control.activeFocus ? 2 : Theme.borderWidth
        border.color: control.activeFocus && Ink.ratio(Theme.accent, color) >= 3 ? Theme.accent : (control.activeFocus ? Theme.foreground : Theme.border)
    }
}
