import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets

// One window in a stack (plan 163): a picture of the window, taken once
// when the stage opens and dropped with it, in a hairline frame. The
// picture is a ScreencopyView of the window's Wayland toplevel with `live`
// off, so Hyprland sends one frame and nothing streams. Where there is no
// picture (no toplevel handle, the capture failed or has not arrived, or the
// headless draw of tests/test-stage.sh) the card is a tile of the theme's
// surface with the app's icon on it.
Item {
    id: card

    // Stage.js client: { address, cls, width, height, toplevel, icon,
    // preview }. `preview` is a picture file, used only by the headless draw.
    required property var modelData
    // Off in the headless draw: there is no compositor to capture from.
    property bool capture: true

    readonly property var source: capture && modelData.toplevel ? modelData.toplevel.wayland : null
    readonly property bool pictured: shot.hasContent || (still.status === Image.Ready)

    // A plain shade one step down and to the side, not a blur (architecture
    // 6): the card stands off whatever is behind it.
    Rectangle {
        x: Math.max(1, Math.round(card.width * 0.015))
        y: Math.max(2, Math.round(card.height * 0.03))
        width: card.width
        height: card.height
        color: Theme.alpha(Theme.background, 0.45)
    }

    Rectangle {
        id: frame

        anchors.fill: parent
        color: Theme.surface
        clip: true

        ScreencopyView {
            id: shot

            anchors.fill: parent
            captureSource: card.source
            live: false
            paintCursor: false
            visible: hasContent
        }

        Image {
            id: still

            anchors.fill: parent
            visible: !shot.hasContent && status === Image.Ready
            source: card.modelData.preview || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            smooth: true
            sourceSize.width: Math.max(1, Math.round(card.width * 2))
        }

        // The tile: the app's icon on the theme's surface.
        IconImage {
            id: icon

            anchors.centerIn: parent
            implicitSize: Math.round(Math.min(card.width, card.height) * 0.42)
            source: card.modelData.icon || ""
            visible: !card.pictured && source.toString() !== "" && status === Image.Ready
        }

        Glyph {
            anchors.centerIn: parent
            visible: !card.pictured && !icon.visible
            glyph: ""
            color: Theme.muted
            font.pixelSize: Theme.font.iconLarge
        }
    }

    // The window's edge: a hairline of the text colour, so a dark window
    // does not sink into a dark wallpaper.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.foreground, 0.28)
    }
}
