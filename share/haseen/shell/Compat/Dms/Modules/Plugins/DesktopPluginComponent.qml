import QtQuick
import qs.Common

// qs.Modules.Plugins.DesktopPluginComponent for DankMaterialShell plugins
// (architecture 5.4): the root of a DMS desktop widget. Adapted from
// DankMaterialShell's quickshell/Modules/Plugins/DesktopPluginComponent.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC). Compat/DmsDesktopWindow.qml
// sets pluginService, pluginId and the size, as DMS's DesktopWidgetContent
// does. haseen runs one instance per plugin, so instanceId stays empty and
// pluginData is the plugin's shell.json settings (SettingsData).
Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property string instanceId: ""
    property var instanceData: null
    property bool lockScreen: false

    property real widgetWidth: 200
    property real widgetHeight: 200
    property real minWidth: 100
    property real minHeight: 100

    property var requestResize: null
    property var clearResize: null

    readonly property bool isInstance: instanceId !== "" && instanceData !== null
    readonly property var instanceConfig: instanceData?.config ?? {}

    property var pluginData: isInstance ? instanceConfig : _globalPluginData
    property var _globalPluginData: ({})

    Component.onCompleted: loadPluginData()
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()
    onInstanceDataChanged: {
        if (isInstance)
            Qt.callLater(() => {
                pluginData = instanceConfig;
            });
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== root.pluginId)
                return;
            root.loadPluginData();
        }
    }

    function loadPluginData() {
        if (!pluginService || !pluginId) {
            _globalPluginData = {};
            return;
        }
        if (isInstance) {
            pluginData = instanceConfig;
            return;
        }
        _globalPluginData = SettingsData.getPluginSettingsForPlugin(pluginId);
    }

    function getData(key, defaultValue) {
        if (!pluginService || !pluginId)
            return defaultValue;
        return pluginService.loadPluginData(pluginId, key, defaultValue);
    }

    function setData(key, value) {
        if (!pluginService || !pluginId)
            return;
        pluginService.savePluginData(pluginId, key, value);
    }
}
