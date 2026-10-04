import QtQuick
import qs.Commons

// qs.Ui.BarIconButton for Omarchy plugins (architecture 5.4): a WidgetButton
// that paints one optically centred glyph, or an iconComponent.
//
// Adapted from Omarchy's shell/Ui/BarIconButton.qml
// (MIT, Copyright (c) David Heinemeier Hansson); the debug outlines are left out.
WidgetButton {
    id: root

    property Component iconComponent: null
    property real slotSize: Style.bar.iconSlot
    property real opticalSize: Style.bar.iconCanvas
    property bool debugOpticalBounds: false
    readonly property real opticalCenterErrorX: glyph.visible ? opticalCanvas.x + glyph.paintedCenterX - root.width / 2 : 0
    readonly property real glyphPaintedWidth: glyph.visible ? glyph.tightWidth : 0
    readonly property real glyphBaselineY: glyph.visible ? glyph.baselineY : 0
    readonly property int glyphFontSize: glyph.visible ? glyph.renderedFontSize : 0

    labelVisible: false
    hasVisualContent: text !== "" || iconComponent !== null
    fontSize: Style.bar.iconFont
    fixedWidth: vertical ? -1 : slotSize
    fixedHeight: vertical ? slotSize : -1

    Item {
        id: opticalCanvas
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: root.opticalSize
        height: root.opticalSize

        OpticalGlyph {
            id: glyph
            anchors.fill: parent
            visible: root.iconComponent === null
            text: root.text
            fontFamily: root.fontFamily
            fontSize: root.fontSize
            color: root.active && root.useActiveColor ? root.activeColor : root.foreground
            rotation: root.textRotation
        }

        Loader {
            anchors.fill: parent
            visible: root.iconComponent !== null
            sourceComponent: root.iconComponent
        }
    }
}
