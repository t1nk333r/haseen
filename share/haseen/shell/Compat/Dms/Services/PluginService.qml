pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Haseen as Haseen

// qs.Services.PluginService for DankMaterialShell plugins (architecture 5.4):
// the plugin-data, plugin-state and global-variable calls widgets and daemons
// make, on top of SettingsData. Names follow DankMaterialShell's
// quickshell/Services/PluginService.qml (MIT, Copyright (c) 2025 Avenge
// Media LLC). Variants (several instances of one widget with their own
// config) are not supported: a plugin sees an empty variant list and variant
// edits log once.
//
// Plugin state is what a plugin keeps for itself (counters, history), apart
// from its settings. As in DMS it is one JSON object per plugin,
// <state>/plugins/<DMS id>_state.json, here under haseen's state directory.
// It is read on first use and written atomically at every change. DMS
// waits 150 ms first; here a plugin's last save, made while the shell tears
// the plugin down, would then never be written.
Singleton {
    id: root

    // DMS plugin id -> { name: value }, shared by a plugin's surfaces for the
    // life of the shell; never persisted, as in DMS.
    property var globalVars: ({})

    readonly property string stateDir: Haseen.Paths.userState + "/plugins"
    // DMS plugin id -> its state object, and -> the FileView that holds it.
    property var _stateCache: ({})
    property var _stateFiles: ({})

    signal pluginDataChanged(string pluginId)
    signal pluginStateChanged(string pluginId)
    signal globalVarChanged(string pluginId, string varName)

    function getGlobalVar(pluginId: string, varName: string, defaultValue: var): var {
        const vars = globalVars[pluginId];
        return vars && varName in vars ? vars[varName] : defaultValue;
    }

    function setGlobalVar(pluginId: string, varName: string, value: var): void {
        const all = Object.assign({}, globalVars);
        all[pluginId] = Object.assign({}, all[pluginId] || {});
        all[pluginId][varName] = value;
        globalVars = all;
        globalVarChanged(pluginId, varName);
    }

    function savePluginData(pluginId: string, key: string, value: var): bool {
        SettingsData.setPluginSetting(pluginId, key, value);
        return true;
    }

    function loadPluginData(pluginId: string, key: string, defaultValue: var): var {
        return SettingsData.getPluginSetting(pluginId, key, defaultValue);
    }

    // The plugin's directory, for its own assets.
    function getPluginPath(pluginId: string): string {
        const record = Haseen.Plugins.registry[SettingsData.haseenId(pluginId)];
        return record ? record.dir : "";
    }

    function getPluginStatePath(pluginId: string): string {
        return stateDir + "/" + pluginId + "_state.json";
    }

    function loadPluginState(pluginId: string, key: string, defaultValue: var): var {
        const state = _state(pluginId);
        return state && state[key] !== undefined ? state[key] : defaultValue;
    }

    function savePluginState(pluginId: string, key: string, value: var): void {
        const state = _state(pluginId);
        if (!state)
            return;
        state[key] = value;
        _write(pluginId);
    }

    function removePluginStateKey(pluginId: string, key: string): void {
        const state = _state(pluginId);
        if (!state || !(key in state))
            return;
        delete state[key];
        _write(pluginId);
    }

    function clearPluginState(pluginId: string): void {
        if (!_state(pluginId))
            return;
        _stateCache[pluginId] = {};
        _write(pluginId);
    }

    // The cached state object, read from disk the first time. Null for an id
    // that is not a DMS id (it names the file).
    function _state(pluginId: string): var {
        if (!/^[a-zA-Z][a-zA-Z0-9]*$/.test(pluginId)) {
            Haseen.Plugins.warnOnce("dms-state:" + pluginId, "haseen: DMS plugin state needs a DMS plugin id, not '" + pluginId + "'");
            return null;
        }
        if (_stateCache[pluginId] === undefined) {
            const file = stateFile.createObject(root, {
                path: getPluginStatePath(pluginId)
            });
            _stateFiles[pluginId] = file;
            let state = {};
            try {
                const parsed = JSON.parse(file.text() || "{}");
                if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed))
                    state = parsed;
            } catch (e) {
                console.warn("haseen: DMS plugin state", getPluginStatePath(pluginId), "is not JSON; starting empty");
            }
            _stateCache[pluginId] = state;
        }
        return _stateCache[pluginId];
    }

    // FileView's atomic write creates the directory too.
    function _write(pluginId: string): void {
        _stateFiles[pluginId].setText(JSON.stringify(_stateCache[pluginId], null, 2));
        pluginStateChanged(pluginId);
    }

    Component {
        id: stateFile

        FileView {
            blockLoading: true
            blockWrites: true
            atomicWrites: true
            printErrors: false
        }
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
