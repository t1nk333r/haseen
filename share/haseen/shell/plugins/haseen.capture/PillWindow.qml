import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets

// The recording pill (plan 150): while a screen or sound recording runs, a
// small card beside the bar on the screen that was focused when it started,
// with a red dot, the elapsed time and a stop button. It exists only while
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

        readonly property int padding: Theme.space(6)
        implicitWidth: row.implicitWidth + padding * 2
        implicitHeight: row.implicitHeight + padding * 2
        color: Theme.popups.background
        radius: Theme.radius
        border.color: Theme.popups.border
        border.width: Math.max(1, Theme.borderWidth)
        // Its own layer surface: mirrored for a right-to-left language.
        LayoutMirroring.enabled: I18n.rightToLeft
        LayoutMirroring.childrenInherit: true

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Theme.gap

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.space(10)
                height: width
                radius: width / 2
                color: Theme.urgent
            }

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                glyph: win.service && win.service.recordingKind === "audio" ? "\uf130" : "\uf03d"
                color: Theme.popups.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.service ? win.service.elapsed : ""
                color: Theme.popups.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.body
            }

            PanelButton {
                objectName: "capturePillStop"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf04d"
                text: I18n.tr("Stop")
                bordered: true
                onClicked: if (win.service)
                    win.service.stop()
            }
        }
    }
}
