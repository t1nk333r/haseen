import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// qs.Modules.Plugins.PluginComponent for DankMaterialShell plugins
// (architecture 5.4): the root of a DMS bar widget. It draws the plugin's
// horizontalBarPill in a hover cell, runs pillClickAction /
// pillRightClickAction, and keeps pluginData in sync with SettingsData.
//
// The property names and the pill-action calling convention
// (action() or action(x, y, width, section, screen)) follow
// DankMaterialShell's quickshell/Modules/Plugins/PluginComponent.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC).
//
// Not provided by haseen, so declared only for the plugins that set them:
//   - popouts (popoutContent): a click logs once; nothing opens;
//   - the control center (cc*) and attached expansions;
//   - vertical bars (verticalBarPill is never shown: the haseen bar is
//     horizontal);
//   - visibilityInterval polling: visibilityCommand runs once per change.
// iconSize and textSize follow the haseen bar font, not DMS's 48 px bar.
Item {
    id: root

    property string layerNamespacePlugin: "plugin"
    property var surfaceContext: null
    property var hostContext: null
    property string widgetInstanceId: ""
    property var axis: null
    property string section: "center"
    property var parentScreen: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property var barConfig: null
    property var blurBarWindow: null
    property string pluginId: ""
    property var pluginService: null
    property bool isFirst: false
    property bool isLast: false

    property string visibilityCommand: ""
    property int visibilityInterval: 0
    property bool conditionVisible: true
    property bool _visibilityOverride: false
    property bool _visibilityOverrideValue: true
    readonly property bool effectiveVisible: _visibilityOverride ? _visibilityOverrideValue : (visibilityCommand === "" || conditionVisible)

    property Component horizontalBarPill: null
    property Component verticalBarPill: null
    property Component popoutContent: null
    property real popoutWidth: 400
    property real popoutHeight: 0
    property var pillClickAction: null
    property var pillRightClickAction: null
    property Component attachedContent: null

    property Component controlCenterWidget: null
    property string ccWidgetIcon: ""
    property string ccWidgetPrimaryText: ""
    property string ccWidgetSecondaryText: ""
    property bool ccWidgetIsActive: false
    property bool ccWidgetIsToggle: true
    property Component ccExpandedContent: null
    property Component ccFooterContent: null
    property real ccExpandedMinimumHeight: Theme.listItemHeight
    property Component ccDetailContent: null
    property real ccDetailHeight: 250

    signal ccWidgetToggled
    signal ccWidgetExpanded

    property var pluginData: ({})
    property var variants: []

    readonly property bool isVertical: false
    readonly property bool hasHorizontalPill: horizontalBarPill !== null
    readonly property bool hasVerticalPill: verticalBarPill !== null
    readonly property bool hasPopout: popoutContent !== null

    readonly property int iconSize: Math.round(Theme.fontSizeMedium * 1.25)
    readonly property int iconSizeLarge: Math.round(Theme.fontSizeMedium * 1.5)
    readonly property int textSize: Theme.fontSizeMedium

    implicitWidth: hasHorizontalPill && effectiveVisible ? pill.implicitWidth : 0
    implicitHeight: barThickness
    width: implicitWidth

    function loadPluginData() {
        pluginData = pluginId !== "" ? SettingsData.getPluginSettingsForPlugin(pluginId) : {};
        variants = [];
    }

    onPluginIdChanged: loadPluginData()
    Component.onCompleted: {
        loadPluginData();
        checkVisibility();
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadPluginData();
        }
    }

    function checkVisibility() {
        if (visibilityCommand === "") {
            conditionVisible = true;
            return;
        }
        visibilityProcess.running = true;
    }

    function setVisibilityOverride(visible) {
        _visibilityOverride = true;
        _visibilityOverrideValue = visible;
    }

    function clearVisibilityOverride() {
        _visibilityOverride = false;
        checkVisibility();
    }

    onVisibilityCommandChanged: Qt.callLater(checkVisibility)

    Process {
        id: visibilityProcess
        command: ["sh", "-c", root.visibilityCommand]
        onExited: exitCode => root.conditionVisible = exitCode === 0
    }

    function createVariant(variantName, variantConfig) {
        return PluginService.createPluginVariant(pluginId, variantName, variantConfig);
    }

    function removeVariant(variantId) {
        PluginService.removePluginVariant(pluginId, variantId);
    }

    function updateVariant(variantId, variantConfig) {
        PluginService.updatePluginVariant(pluginId, variantId, variantConfig);
    }

    function closePopout() {
    }

    function runPillAction(action) {
        if (!action)
            return;
        if (action.length === 0) {
            action();
            return;
        }
        const p = pill.mapToItem(null, 0, 0);
        action(p.x, p.y, pill.width, section, parentScreen);
    }

    property bool _popoutWarned: false

    function triggerPopout() {
        if (pillClickAction) {
            runPillAction(pillClickAction);
            return;
        }
        if ((hasPopout || attachedContent !== null) && !_popoutWarned) {
            _popoutWarned = true;
            console.warn("haseen: plugin", pluginId + ": DMS popouts are not supported by the compat adapter");
        }
    }

    Item {
        id: pill

        implicitWidth: content.implicitWidth + Theme.spacingS * 2
        width: implicitWidth
        height: root.height
        visible: root.hasHorizontalPill && root.effectiveVisible

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: 3
            radius: Theme.cornerRadius
            color: Theme.chipSurface
            visible: mouse.containsMouse
        }

        Loader {
            id: content
            anchors.centerIn: parent
            sourceComponent: root.horizontalBarPill
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: root.pillClickAction || root.hasPopout ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: event => {
                if (event.button === Qt.RightButton)
                    root.runPillAction(root.pillRightClickAction);
                else
                    root.triggerPopout();
            }
        }
    }
}
