import QtQuick
import "Transition.js" as Transition

// One screen's picture during a background change (plan 161): the old image
// at progress 0, the new one at 1, both shown as swaybg's `fill` shows them
// (covering the screen, centred). Plain QtQuick, so the tests draw it in a
// bare window on either renderer.
//
// contagion and outline draw through ShaderView.qml on a GPU scene graph.
// fade, and every effect on the software renderer (GraphicsInfo.Software),
// is a crossfade of the two images, and there ShaderView.qml is never
// created. If the shader fails to build, the crossfade takes over.
Item {
    id: view

    property url oldSource
    property url newSource
    property string effect: "fade"
    property real progress: 0
    property real seed: 0
    property real pixelRatio: 1
    property color ember: "transparent"
    property color ink: "transparent"

    // Unknown until the scene graph starts; nothing is drawn by a shader
    // before the renderer is known.
    readonly property bool rendererKnown: GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool wantsShader: rendererKnown && Transition.drawsWithShader(effect, software)
    readonly property bool shaderFailed: shaderLoader.status === Loader.Error || (shaderLoader.item !== null && shaderLoader.item.failed)
    readonly property bool useShader: wantsShader && !shaderFailed
    readonly property bool shaderLoaded: shaderLoader.item !== null
    // Both images decoded and, for the shader, the shader built.
    readonly property bool ready: rendererKnown && oldPicture.status === Image.Ready && newPicture.status === Image.Ready && (!useShader || (shaderLoader.item !== null && shaderLoader.item.compiled))
    readonly property bool failed: oldPicture.status === Image.Error || newPicture.status === Image.Error

    // Decoded at the screen's pixel size, large enough to cover it: an image
    // is never kept larger than the screen shows it.
    readonly property size decodeSize: Qt.size(Math.max(1, Math.ceil(width * pixelRatio)), Math.max(1, Math.ceil(height * pixelRatio)))

    Image {
        id: oldPicture

        anchors.fill: parent
        source: view.oldSource
        sourceSize: view.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        visible: !view.useShader
    }

    Image {
        id: newPicture

        anchors.fill: parent
        source: view.newSource
        sourceSize: view.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        // The outline reads blurred copies of the new image from its mipmaps.
        mipmap: view.wantsShader
        visible: !view.useShader
        opacity: view.progress
    }

    // A component, not a URL: the file's type is checked with the rest, and
    // the shader exists only while the loader is active.
    Loader {
        id: shaderLoader

        anchors.fill: parent
        active: view.wantsShader
        sourceComponent: ShaderView {
            oldImage: oldPicture
            newImage: newPicture
            effect: view.effect
            progress: view.progress
            seed: view.seed
            pixelRatio: view.pixelRatio
            ember: view.ember
            ink: view.ink
        }
    }
}
