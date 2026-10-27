import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "Osd.js" as Osd

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
    // A lock card's line is interface text (Osd.js N_); a layout card's is
    // the layout's own name, shown as Hyprland gives it.
    readonly property bool lockLine: !level && card.text === "" && card.glyph !== "\uf11c"

    screen: service ? service.focusedScreen() : null
    anchors.bottom: true
    // Omarchy's OSD: 67 px above the screen edge (Style.space(67)).
    margins.bottom: Theme.space(67)
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

        // Omarchy's card: 16 px padding and the display-large line height,
        // the [popups] surface and its 2 px border. Whole pixels, so the
        // window is exactly the card and no edge of the border is cut
        // (Osd.js extent, plan 139).
        readonly property int padding: Theme.space(16)
        implicitWidth: Osd.extent(row.implicitWidth, 0, padding)
        implicitHeight: Osd.extent(row.implicitHeight, Theme.font.displayLarge, padding)
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.97)
        radius: Theme.radius
        border.color: Theme.popups.border
        border.width: Math.max(1, Theme.space(2))
        // Its own layer surface: in a right-to-left language the row runs
        // from the right and the level fills from the right (plan 109).
        LayoutMirroring.enabled: I18n.rightToLeft
        LayoutMirroring.childrenInherit: true

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
                font.pixelSize: Theme.font.heading
            }

            // The layout code where the glyph would be.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.card.text !== ""
                text: win.card.text
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.heading
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
                    // Anchored, not at x 0, so a mirrored card fills from the right.
                    anchors.left: parent.left
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
                font.pixelSize: Theme.font.body
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !win.level
                text: win.lockLine ? I18n.tr(win.card.label) : win.card.label
                textFormat: Text.PlainText
                // "Caps Lock off" is the message: it stays in the text colour.
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.title
            }
        }
    }
}
