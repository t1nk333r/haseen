import QtQuick
import Quickshell.Io
import qs.Haseen

// One of haseen's mark SVGs (Branding paths) in a theme colour. The files
// fill with currentColor; the shell renders with the software backend (no
// shader recolouring, architecture 6), so the colour is written into the SVG
// text and the result loaded as a data URL. Size it with height; the width
// follows the drawing's aspect ratio.
Image {
    id: root

    property string path: Branding.symbolicPath
    property color color: Theme.accent
    property string svg: ""

    readonly property string hex: "#" + [color.r, color.g, color.b].map(c => Math.round(c * 255).toString(16).padStart(2, "0")).join("")

    fillMode: Image.PreserveAspectFit
    smooth: true
    sourceSize.height: height > 0 ? height : 0
    source: svg === "" ? "" : "data:image/svg+xml;utf8," + encodeURIComponent(svg.replace(/currentColor/g, hex))

    FileView {
        path: root.path
        printErrors: false
        onLoaded: root.svg = text()
        onLoadFailed: root.svg = ""
    }
}
