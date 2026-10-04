import QtQuick
import qs.Commons

// qs.Ui.OpticalGlyph for Omarchy plugins (architecture 5.4): one icon glyph
// centred on its painted bounds rather than its advance width.
//
// Adapted from Omarchy's shell/Ui/OpticalGlyph.qml
// (MIT, Copyright (c) David Heinemeier Hansson); the debug outlines are left out.
Item {
    id: root

    property string text: ""
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.body
    property color color: Color.foreground
    property bool debugBounds: false

    readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
    readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
    readonly property real horizontalCorrection: glyph.implicitWidth / 2 - (glyphMetrics.tightBoundingRect.x + tightWidth / 2)
    readonly property real paintedCenterX: glyph.x + glyphMetrics.tightBoundingRect.x + tightWidth / 2
    readonly property real baselineY: glyph.y + glyph.baselineOffset

    TextMetrics {
        id: glyphMetrics
        font.family: root.fontFamily
        font.pixelSize: root.renderedFontSize
        text: root.text
    }

    Text {
        id: glyph
        textFormat: Text.PlainText
        x: (root.width - width) / 2 + root.horizontalCorrection
        y: Math.round((root.height - height) / 2)
        text: root.text
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.renderedFontSize
    }
}
