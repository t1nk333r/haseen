import QtQuick
import Quickshell
import qs.Haseen

// The screen frame (plan 015): the bar is its thick edge, and three thin
// strips close it on the other edges. Every strip reserves its thickness as
// an exclusive zone, so windows never sit under the frame. Two corner rows
// round the inner corners of the area left for windows.
//
// Layer surfaces instead of one full-screen window: a strip is a few pixels
// deep, so the software backend renders kilobytes, not a screen-sized
// buffer, and nothing but the bar takes input (each strip has an empty
// mask). The edges and corners live on the bottom layer: decoration belongs
// behind windows, so a fullscreen window covers the frame (the owner's
// t1nk33r.screen-frame made the same choice).
Scope {
    id: frame

    required property var screen
    property bool transparent: false
    // Transparent keeps the hue so the cross-fade does not dip through black.
    readonly property color fill: transparent ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) : Theme.background

    Variants {
        model: Config.frameEnabled ? ["top", "bottom", "left", "right"].filter(e => e !== Config.barPosition) : []

        FrameEdge {
            required property string modelData

            screen: frame.screen
            edge: modelData
            thickness: Config.frameThickness
            fill: frame.fill
        }
    }

    Variants {
        model: Config.frameEnabled && Config.frameRadius > 0 ? ["top", "bottom"] : []

        FrameCorners {
            required property string modelData

            screen: frame.screen
            atBottom: modelData === "bottom"
            radius: Config.frameRadius
            fill: frame.fill
        }
    }
}
