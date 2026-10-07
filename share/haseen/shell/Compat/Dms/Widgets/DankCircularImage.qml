import QtQuick
import qs.Common

// qs.Widgets.DankCircularImage for DankMaterialShell plugins (architecture
// 5.4): an image cropped to a circle, with a fallback icon or text while
// there is none. Properties follow dank-qml-common
// DCommon/Widgets/DCircularImage.qml, which DMS's DankCircularImage wraps
// (MIT, Copyright (c) 2025-2026 Avenge Media LLC). The root is a Rectangle,
// so a plugin's border.* applies to the circle as upstream. Upstream clips
// with a shader (ClippingRectangle), which the software scene graph haseen
// renders with cannot draw; here a Canvas clips to the circle instead, so
// an animated image shows its first frame and saveImageToFile is absent.
Rectangle {
    id: root

    property string imageSource: ""
    property string fallbackIcon: "notifications"
    property string fallbackText: ""
    property bool cacheImages: true
    property real ringWidth: 0
    property color ringColor: Theme.surfaceVariant
    property bool hasImage: imageSource !== ""
    readonly property int imageStatus: probe.status
    readonly property bool showsImage: imageSource !== "" && probe.status === Image.Ready

    radius: width / 2
    color: Theme.primaryHover
    border.color: "transparent"
    border.width: 0

    // Loads the image (shared with the Canvas through the pixmap cache) and
    // gives its natural size for the crop; never drawn itself.
    Image {
        id: probe

        visible: false
        asynchronous: true
        cache: root.cacheImages
        source: root.imageSource
        onStatusChanged: canvas.requestPaint()
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        anchors.margins: 2
        visible: root.showsImage
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.showsImage || width <= 0 || height <= 0)
                return;
            // PreserveAspectCrop: the largest centred square of the image.
            const iw = probe.implicitWidth, ih = probe.implicitHeight;
            const side = Math.min(iw, ih);
            ctx.save();
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, 2 * Math.PI);
            ctx.closePath();
            ctx.clip();
            ctx.drawImage(probe, (iw - side) / 2, (ih - side) / 2, side, side, 0, 0, width, height);
            ctx.restore();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2 - root.ringWidth / 2
        radius: width / 2
        color: "transparent"
        border.width: root.ringWidth
        border.color: root.ringColor
        visible: root.ringWidth > 0
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.fallbackIcon.replace(/^material:/, "")
        size: Math.round(root.width * 0.5)
        color: Theme.surfaceVariantText
        visible: !root.showsImage && root.fallbackText === "" && root.fallbackIcon !== ""
    }

    StyledText {
        anchors.centerIn: parent
        text: root.fallbackText
        font.pixelSize: Math.round(root.width * 0.4)
        visible: !root.showsImage && root.fallbackText !== ""
    }
}
