pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// qs.Services.PluginService for DankMaterialShell plugins (architecture 5.4):
// the plugin-data calls bar widgets make, on top of SettingsData. Names
// follow DankMaterialShell's quickshell/Services/PluginService.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC). Variants (several instances
// of one widget with their own config) are not supported: a plugin sees an
// empty variant list and variant edits log once.
Singleton {
    id: root

    signal pluginDataChanged(string pluginId)

    function savePluginData(pluginId: string, key: string, value: var): bool {
        SettingsData.setPluginSetting(pluginId, key, value);
        return true;
    }

    function loadPluginData(pluginId: string, key: string, defaultValue: var): var {
        return SettingsData.getPluginSetting(pluginId, key, defaultValue);
    }

    function getPluginVariants(pluginId: string): var {
        return [];
    }

    function _noVariants(pluginId: string): var {
        console.warn("haseen: plugin", pluginId + ": DMS widget variants are not supported by the compat adapter");
        return null;
    }

    function createPluginVariant(pluginId: string, name: var, config: var): var {
        return _noVariants(pluginId);
    }

    function removePluginVariant(pluginId: string, variantId: var): void {
        _noVariants(pluginId);
    }

    function updatePluginVariant(pluginId: string, variantId: var, config: var): void {
        _noVariants(pluginId);
    }

    Connections {
        target: SettingsData
        function onPluginSettingChanged(pluginId) {
            root.pluginDataChanged(pluginId);
        }
    }
}
