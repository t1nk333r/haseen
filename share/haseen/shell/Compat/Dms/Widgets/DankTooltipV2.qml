import QtQuick
import QtQuick.Controls
import qs.Common

// qs.Widgets.DankTooltipV2 for DankMaterialShell plugins (architecture 5.4):
// show(text, item, offsetX, offsetY, preferredSide) / hide() follow
// dank-qml-common DCommon/Widgets/DTooltipV2.qml, which DMS's DankTooltipV2
// wraps (MIT, Copyright (c) 2025-2026 Avenge Media LLC). The tooltip is drawn
// inside the source item's own window, above it unless preferredSide is
// "bottom", "left" or "right".
Item {
    id: root

    property string text: ""
    property alias delay: tip.delay
    property Item sourceItem: null
    property real offsetX: 0
    property real offsetY: 0
    property string side: "top"

    function show(text, item, offsetX, offsetY, preferredSide) {
        root.text = text;
        root.sourceItem = item || null;
        root.offsetX = offsetX || 0;
        root.offsetY = offsetY || 0;
        root.side = preferredSide || "top";
        if (root.sourceItem)
            tip.open();
    }

    function hide() {
        tip.close();
    }

    ToolTip {
        id: tip

        readonly property real gap: Theme.spacingXS

        parent: root.sourceItem
        text: root.text
        delay: 0
        padding: Theme.spacingS
        x: {
            if (!parent)
                return 0;
            if (root.side === "left")
                return -width - gap + root.offsetX;
            if (root.side === "right")
                return parent.width + gap + root.offsetX;
            return (parent.width - width) / 2 + root.offsetX;
        }
        y: {
            if (!parent)
                return 0;
            if (root.side === "bottom")
                return parent.height + gap + root.offsetY;
            if (root.side === "left" || root.side === "right")
                return (parent.height - height) / 2 + root.offsetY;
            return -height - gap + root.offsetY;
        }

        contentItem: StyledText {
            text: tip.text
            font.pixelSize: Theme.fontSizeSmall
        }

        background: Rectangle {
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.outline
        }
    }
}
