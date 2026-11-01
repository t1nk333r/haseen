import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The recording pill (plan 150): while a screen or sound recording runs, a
// small pill beside the bar on the screen that was focused when it started,
// with a red dot, the elapsed time, what it records and a stop button, in
// the original toolbar's look and the theme's colours (`shape` as the
// toolbar's). It exists only while
// a recording runs (the service's LazyLoader) and takes no keyboard. A file
// of its own, loaded by URL, so Service.qml compiles where no PanelWindow
// backend exists.
PanelWindow {
    id: win

    // The haseen.capture Service, set by its loader.
    property var service: null
    readonly property bool top: Config.barPosition !== "bottom"

    // Placed once: following the focus would move the pill under the pointer.
    screen: service ? service.focusedScreen() : null
    anchors.top: win.top
    anchors.bottom: !win.top
    // Normal: the pill sits next to the bar, outside its exclusive zone.
    exclusionMode: ExclusionMode.Normal
    margins.top: win.top ? Theme.gapsOut : 0
    margins.bottom: win.top ? 0 : Theme.gapsOut
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "haseen-capture-pill"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: card

        readonly property bool round: !win.service || win.service.settings.shape !== "theme"
        readonly property int padding: Theme.space(6)
        implicitWidth: row.implicitWidth + padding * 2
        implicitHeight: row.implicitHeight + padding * 2
        color: Theme.popups.background
        radius: round ? height / 2 : Theme.radius
        border.color: Theme.popups.border
        border.width: Math.max(1, Theme.borderWidth)
        // Its own layer surface: mirrored for a right-to-left language.
        LayoutMirroring.enabled: I18n.rightToLeft
        LayoutMirroring.childrenInherit: true

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Theme.space(10)
            leftPadding: Theme.space(10)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.space(10)
                height: width
                radius: width / 2
                color: Theme.urgent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.service ? win.service.elapsed : ""
                color: Theme.popups.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.title
            }

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                glyph: win.service && win.service.recordingKind === "audio" ? Model.GLYPHS.sound : Model.MODES[1].glyph
                color: Qt.alpha(Theme.popups.text, 0.7)
            }

            PanelButton {
                objectName: "capturePillStop"
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.round(Theme.spacing.controlHeight * 1.3)
                implicitHeight: implicitWidth
                horizontalPadding: 0
                verticalPadding: 0
                radius: card.round ? Theme.space(10) : Theme.radius
                iconText: Model.GLYPHS.stop
                iconSize: Theme.font.iconLarge
                foreground: Theme.popups.text
                active: true
                Accessible.name: I18n.tr("Stop")
                onClicked: if (win.service)
                    win.service.stop()
            }
        }
    }
}
