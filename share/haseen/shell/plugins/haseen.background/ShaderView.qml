import QtQuick
import "Transition.js" as Transition

// The contagion and outline effects (plan 161), drawn by transition.frag.
// This is the one ShaderEffect under share/haseen/shell (architecture 6):
// TransitionView loads it only on a GPU scene graph and only for those two
// effects, and only while a background change runs. On the software
// renderer this file is never instantiated; the crossfade draws instead.
ShaderEffect {
    id: fx

    // The two decoded images (Image items, hidden), each as large as it
    // must be to cover the screen.
    required property Item oldImage
    required property Item newImage
    property string effect: "contagion"
    property real seed: 0
    property real pixelRatio: 1

    // Uniforms, by name (transition.frag's buf block and samplers).
    property real progress: 0
    readonly property var oldTex: oldImage
    readonly property var newTex: newImage
    readonly property real mode: effect === "outline" ? 1 : 0
    readonly property real cell: Transition.cellPx(pixelRatio)
    readonly property size resolution: Qt.size(Math.max(1, width * pixelRatio), Math.max(1, height * pixelRatio))
    readonly property var _oldCover: Transition.coverScale(width, height, oldImage.implicitWidth, oldImage.implicitHeight)
    readonly property var _newCover: Transition.coverScale(width, height, newImage.implicitWidth, newImage.implicitHeight)
    readonly property point oldScale: Qt.point(_oldCover.x, _oldCover.y)
    readonly property point newScale: Qt.point(_newCover.x, _newCover.y)
    // The tint of a contagion cell that has just switched, and the outline's
    // line colour (TransitionCover.qml picks both from Theme).
    property color glow: "transparent"
    property color pencil: "transparent"
    // Only Error is trusted. Qt keeps a compiled shader by URL, and an effect
    // that takes it from that cache, as every change after the shell's first
    // does, draws with it but reports Uncompiled for good, so waiting for
    // Compiled held each later cover until its load timeout (found live on
    // luna). A shader that fails to build reports Error on its first change.
    readonly property bool failed: status === ShaderEffect.Error

    fragmentShader: Qt.resolvedUrl("transition-2.frag.qsb")
}
