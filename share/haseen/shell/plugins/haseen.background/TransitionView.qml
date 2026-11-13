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
//
// Two image slots, not an old and a new Image: when a change follows a
// change, the next old image is usually the one the last change ended on,
// and the slot that holds it becomes the old one without decoding it again
// (a change during a change keeps its covers, Transition.qml).
Item {
    id: view

    property url oldSource
    property url newSource
    property string effect: "fade"
    property real progress: 0
    property real seed: 0
    property real pixelRatio: 1
    property color glow: "transparent"
    property color pencil: "transparent"

    // Unknown until the scene graph starts; nothing is drawn by a shader
    // before the renderer is known.
    readonly property bool rendererKnown: GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool wantsShader: rendererKnown && Transition.drawsWithShader(effect, software)
    readonly property bool shaderFailed: shaderLoader.status === Loader.Error || (shaderLoader.item !== null && shaderLoader.item.failed)
    readonly property bool useShader: wantsShader && !shaderFailed
    readonly property bool shaderLoaded: shaderLoader.item !== null

    // Which slot plays which part (place()).
    property Image oldPicture: slotA
    property Image newPicture: slotB
    // A source changed and place() has not run yet: the slots still hold
    // the last change's images.
    property bool placing: true

    // Both images decoded and, for the shader, the effect created. Not its
    // Compiled status: an effect built from Qt's shader cache never reports
    // it (ShaderView.qml). The cover waits two frames after this anyway.
    readonly property bool ready: rendererKnown && !placing && oldPicture.status === Image.Ready && newPicture.status === Image.Ready && (!useShader || shaderLoader.item !== null)
    readonly property bool failed: !placing && (oldPicture.status === Image.Error || newPicture.status === Image.Error)

    // Decoded at the screen's pixel size, large enough to cover it: an image
    // is never kept larger than the screen shows it.
    readonly property size decodeSize: Qt.size(Math.max(1, Math.ceil(width * pixelRatio)), Math.max(1, Math.ceil(height * pixelRatio)))

    // A source URL without its query: TransitionCover adds one per change
    // so Qt's image cache never hands back a file that changed on disk.
    function file(u: url): string {
        const s = String(u);
        const q = s.indexOf("?");
        return q < 0 ? s : s.slice(0, q);
    }

    // Give each source to a slot. A slot that already shows the wanted file
    // keeps it, so the picture on screen does not change while the other
    // decodes. Both sources change in one call (Transition.begin), so this
    // runs once, after both.
    function place(): void {
        let o = oldPicture;
        let n = newPicture;
        if (file(o.source) !== file(oldSource) && (file(n.source) === file(oldSource) || file(o.source) === file(newSource))) {
            o = newPicture;
            n = oldPicture;
        }
        if (file(o.source) !== file(oldSource))
            o.source = oldSource;
        if (file(n.source) !== file(newSource))
            n.source = newSource;
        oldPicture = o;
        newPicture = n;
        placing = false;
    }

    onOldSourceChanged: {
        placing = true;
        Qt.callLater(place);
    }
    onNewSourceChanged: {
        placing = true;
        Qt.callLater(place);
    }
    Component.onCompleted: place()

    // cache: screens of one size share a decode (Qt's image cache keys on
    // the URL and sourceSize). retainWhileLoading: a slot given a new file,
    // or a new size, keeps its last picture until the new one is decoded,
    // never a blank cover over swaybg's restart. autoTransform: swaybg
    // turns a photo by its EXIF orientation, and so must the cover.
    //
    // On the crossfade the new slot is drawn over the old at `progress`.
    // At 1 the old one is hidden: the cover fades out as a whole at the end
    // (Transition.qml fadeOut), and the software renderer applies an item's
    // opacity to each child, so an old picture still drawn under it would
    // show through at up to a quarter.
    Image {
        id: slotA

        readonly property bool isNew: view.newPicture === slotA

        anchors.fill: parent
        sourceSize: view.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        retainWhileLoading: true
        autoTransform: true
        smooth: true
        // The outline reads blurred copies of the new image from its mipmaps.
        mipmap: view.wantsShader
        z: isNew ? 1 : 0
        visible: !view.useShader && (isNew || view.progress < 1)
        opacity: isNew ? view.progress : 1
    }

    Image {
        id: slotB

        readonly property bool isNew: view.newPicture === slotB

        anchors.fill: parent
        sourceSize: view.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        retainWhileLoading: true
        autoTransform: true
        smooth: true
        mipmap: view.wantsShader
        z: isNew ? 1 : 0
        visible: !view.useShader && (isNew || view.progress < 1)
        opacity: isNew ? view.progress : 1
    }

    // A component, not a URL: the file's type is checked with the rest, and
    // the shader exists only while the loader is active.
    Loader {
        id: shaderLoader

        anchors.fill: parent
        z: 2
        active: view.wantsShader
        sourceComponent: ShaderView {
            oldImage: view.oldPicture
            newImage: view.newPicture
            effect: view.effect
            progress: view.progress
            seed: view.seed
            pixelRatio: view.pixelRatio
            glow: view.glow
            pencil: view.pencil
        }
    }
}
