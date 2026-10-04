import QtQuick
import Quickshell
import qs.Haseen

// Hover tooltip for adapted bar widgets (Omarchy's bar.showTooltip). The
// popup window exists only while a target is hovered with non-empty text.
LazyLoader {
    id: tip

    property Item target: null
    property string text: ""
    readonly property bool atBottom: Config.barPosition === "bottom"

    active: target !== null && text !== ""

    PopupWindow {
        visible: true
        color: "transparent"
        anchor.item: tip.target
        anchor.edges: tip.atBottom ? Edges.Top : Edges.Bottom
        anchor.gravity: tip.atBottom ? Edges.Top : Edges.Bottom
        anchor.margins.top: tip.atBottom ? 0 : Theme.gap
        anchor.margins.bottom: tip.atBottom ? Theme.gap : 0
        implicitWidth: Math.ceil(label.implicitWidth) + Theme.gap * 2
        implicitHeight: Math.ceil(label.implicitHeight) + Theme.gap

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.border

            Text {
                id: label
                anchors.centerIn: parent
                text: tip.text
                textFormat: Text.PlainText
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
