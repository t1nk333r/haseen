import QtQuick
import QtQuick.Shapes
import qs.Haseen
import "Computer.js" as Computer

// One reading's last 90 s as a smooth line with a faint fill under it and a
// dot on the newest sample (plan 162). Drawn with QtQuick.Shapes, which has a
// software backend: haseen's default renderer draws it at any scale, where a
// Canvas or a layer comes out wrong at a fractional one (plan 156). On the
// GPU renderer the curve renderer antialiases the line without multisampling.
//
// Time runs left to right in every language: a time graph opts out of the
// right-to-left mirroring (architecture 5.8).
Item {
    id: graph

    property var history: []
    property real lo: 0
    property real hi: 100
    property color stroke: Theme.accent

    readonly property real lineWidth: Math.max(1.5, Theme.space(2))
    readonly property real dotSize: Math.max(6, Theme.space(7))
    readonly property var points: Computer.points(history, Math.max(0, width - dotSize / 2 - 1), height, lo, hi, Computer.WINDOW_MS, dotSize / 2 + 1)
    readonly property var newest: points.length > 0 ? points[points.length - 1] : null

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // The floor the line stands on.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separator
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                y1: 0
                y2: graph.height

                GradientStop {
                    position: 0
                    color: Theme.alpha(graph.stroke, 0.22)
                }
                GradientStop {
                    position: 1
                    color: Theme.alpha(graph.stroke, 0)
                }
            }

            PathSvg {
                path: Computer.areaPath(graph.points, graph.height)
            }
        }

        ShapePath {
            strokeColor: graph.stroke
            strokeWidth: graph.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: Computer.linePath(graph.points)
            }
        }
    }

    Rectangle {
        visible: graph.newest !== null
        x: graph.newest ? graph.newest.x - width / 2 : 0
        y: graph.newest ? graph.newest.y - height / 2 : 0
        width: graph.dotSize
        height: width
        radius: width / 2
        color: graph.stroke
    }
}
