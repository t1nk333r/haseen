import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets

// The OSD card (Osd.js levelCard / layoutCard / lockCard) in an overlay that
// takes no input. A file of its own, loaded by URL, so Service.qml compiles
// where no PanelWindow backend exists (the offscreen engine of
// tests/test-keyboard.sh) and only the window is missing there.
PanelWindow {
    id: win

    // The haseen.osd Service, set by its loader.
    property var service: null
    readonly property var card: service ? service.card : ({ glyph: "", text: "", label: "", value: 0, dim: false })
    readonly property bool level: card.label === ""

    screen: service ? service.focusedScreen() : null
    anchors.bottom: true
    margins.bottom: Theme.gap * 12
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: cardBox.implicitWidth
    implicitHeight: cardBox.implicitHeight
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "haseen-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: cardBox

        implicitWidth: row.implicitWidth + Theme.gap * 4
        implicitHeight: row.implicitHeight + Theme.gap * 3
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
        border.width: Theme.borderWidth

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Theme.gap * 2

            Glyph {
                width: Theme.fontSize * 2
                anchors.verticalCenter: parent.verticalCenter
                visible: win.card.text === ""
                glyph: win.card.glyph
                // Off or muted: the glyph steps back, still readable (3:1).
                color: win.card.dim ? Theme.subtle(Theme.surface) : Theme.foreground
                font.pixelSize: Theme.fontSize * 1.6
            }

            // The layout code where the glyph would be.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.card.text !== ""
                text: win.card.text
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 1.4
                font.bold: true
            }

            Rectangle {
                width: Theme.fontSize * 12
                height: Math.max(Theme.gap, 4)
                anchors.verticalCenter: parent.verticalCenter
                visible: win.level
                radius: height / 2
                color: Theme.surfaceAlt

                Rectangle {
                    width: parent.width * win.card.value
                    height: parent.height
                    radius: parent.radius
                    color: win.card.dim ? Theme.muted : Theme.accent
                }
            }

            Text {
                width: Theme.fontSize * 3
                anchors.verticalCenter: parent.verticalCenter
                visible: win.level
                text: Math.round(win.card.value * 100) + "%"
                color: win.card.dim ? Theme.subtle(Theme.surface) : Theme.foreground
                horizontalAlignment: Text.AlignRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !win.level
                text: win.card.label
                textFormat: Text.PlainText
                // "Caps Lock off" is the message: it stays in the text colour.
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 1.2
            }
        }
    }
}
