// Adapted from Omarchy shell/Ui/BorderOverlay.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: one uniform width, a Theme border spec ({ color, width, gradient }).
import QtQuick
import QtQuick.Shapes
import "../BorderGeometry.js" as Geometry

// A border drawn as a filled ring, for a gradient (a theme whose Hyprland
// active border is one: hackerman, last-horizon, solitude), which
// Rectangle.border cannot paint. Flat borders stay on Rectangle.border (see
// PanelSurface). Visual only; it takes no input.
Item {
    id: root

    property var spec: ({ color: "transparent", width: 0, gradient: { colors: [], angle: 0, enabled: false } })
    property real radius: 0

    readonly property real _width: spec && spec.width > 0 ? spec.width : 0
    readonly property var _widths: ({ top: _width, right: _width, bottom: _width, left: _width })
    readonly property var _gradient: spec && spec.gradient ? spec.gradient : ({ colors: [], angle: 0, enabled: false })
    readonly property var _colors: _gradient.enabled ? _gradient.colors : [spec ? spec.color : "transparent", spec ? spec.color : "transparent"]
    readonly property var _endpoints: Geometry.gradientEndpoints(width, height, _gradient.angle || 0)

    visible: _width > 0 && width > 0 && height > 0

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillRule: ShapePath.WindingFill
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: root._endpoints.x1
                y1: root._endpoints.y1
                x2: root._endpoints.x2
                y2: root._endpoints.y2

                GradientStop { position: Geometry.stopPosition(root._colors, 0); color: Geometry.stopColor(root._colors, 0) }
                GradientStop { position: Geometry.stopPosition(root._colors, 1); color: Geometry.stopColor(root._colors, 1) }
                GradientStop { position: Geometry.stopPosition(root._colors, 2); color: Geometry.stopColor(root._colors, 2) }
                GradientStop { position: Geometry.stopPosition(root._colors, 3); color: Geometry.stopColor(root._colors, 3) }
                GradientStop { position: Geometry.stopPosition(root._colors, 4); color: Geometry.stopColor(root._colors, 4) }
                GradientStop { position: Geometry.stopPosition(root._colors, 5); color: Geometry.stopColor(root._colors, 5) }
                GradientStop { position: Geometry.stopPosition(root._colors, 6); color: Geometry.stopColor(root._colors, 6) }
                GradientStop { position: Geometry.stopPosition(root._colors, 7); color: Geometry.stopColor(root._colors, 7) }
            }

            PathSvg {
                path: Geometry.ringPath(root.width, root.height, root.radius, root._widths)
            }
        }
    }
}
