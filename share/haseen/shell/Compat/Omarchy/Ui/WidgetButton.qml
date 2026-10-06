import QtQuick
import qs.Commons

// qs.Ui.WidgetButton for Omarchy plugins (architecture 5.4): a text cell
// sized to its label, with tooltip, click and wheel.
//
// Adapted from Omarchy's shell/Ui/WidgetButton.qml
// (MIT, Copyright (c) David Heinemeier Hansson). Colours come from the bar
// facade or qs.Commons.Color, both backed by the haseen Theme.
Item {
    id: root

    property var bar: null
    property string text: ""
    property string fontFamily: bar ? bar.fontFamily : Style.font.family
    property real fontSize: Style.font.body
    property color foreground: bar ? bar.barForeground : Color.foreground
    property color activeColor: bar ? bar.urgent : Color.urgent
    property bool active: false
    property real horizontalMargin: 8.5
    property real verticalPadding: 6
    property real fixedWidth: -1
    property real fixedHeight: -1
    property real textRotation: 0
    property bool keepSpace: false
    property bool dimmed: false
    property bool concealed: false
    property bool interactive: true
    property bool pressable: true
    property bool useActiveColor: true
    property bool maintainIndicatorReveal: false
    property bool labelVisible: true
    property bool hasVisualContent: text !== ""
    property var revealHost: bar
    property string tooltipText: ""
    property var registeredBar: null

    signal pressed(int button)
    signal wheelMoved(int delta)

    function triggerPress(button) {
        if (root.bar)
            root.bar.hideTooltip(root);
        root.pressed(button);
    }

    function hideOwnTooltip() {
        if (root.bar)
            root.bar.hideTooltip(root);
    }

    function syncClickRegistration() {
        if (registeredBar && registeredBar.unregisterClickTarget)
            registeredBar.unregisterClickTarget(root);
        registeredBar = root.bar;
        if (registeredBar && registeredBar.registerClickTarget)
            registeredBar.registerClickTarget(root);
    }

    onBarChanged: syncClickRegistration()
    onVisibleChanged: if (!visible)
        hideOwnTooltip()
    onInteractiveChanged: if (!interactive)
        hideOwnTooltip()
    onConcealedChanged: if (concealed)
        hideOwnTooltip()
    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget)
        registeredBar.unregisterClickTarget(root)

    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
    readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
    readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
    readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse
    readonly property real labelWidth: label.visible ? label.implicitWidth : 0

    visible: hasVisualContent || keepSpace
    opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
    implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? barSize : Math.max(12, label.implicitWidth + scaledHorizontalMargin * 2))
    implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(12, label.implicitHeight + scaledVerticalPadding * 2) : barSize)

    Text {
        id: label
        textFormat: Text.PlainText
        visible: root.labelVisible
        anchors.centerIn: parent
        text: root.text
        color: root.active && root.useActiveColor ? root.activeColor : root.foreground
        // An icon-only label (private-use code points only) is drawn in
        // "Symbols Nerd Font" when it is installed. In the monospace Nerd Font
        // an icon's advance is one cell while its ink is wider, so the button,
        // sized and centred on the advance, showed a gap left of the icon and
        // the ink ran into the right margin (t1nk33r.omaprayers on io, plan 049).
        font.family: /^[\ue000-\uf8ff\s]+$/.test(root.text) && Qt.fontFamilies().indexOf("Symbols Nerd Font") >= 0 ? "Symbols Nerd Font" : root.fontFamily
        font.pixelSize: root.fontSize
        rotation: root.textRotation
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: {
            if (root.bar)
                root.bar.showTooltip(root, root.tooltipText);
            if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
                root.revealHost.setIndicatorItemHovered(true);
        }
        onExited: {
            if (root.bar)
                root.bar.hideTooltip(root);
            if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
                root.revealHost.setIndicatorItemHovered(false);
        }
        onClicked: mouse => {
            if (root.pressable)
                root.triggerPress(mouse.button);
        }
        onWheel: wheel => root.wheelMoved(wheel.angleDelta.y)
    }
}
