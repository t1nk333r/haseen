pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen
import qs.Compat as Compat

// qs.Common.SettingsData for DankMaterialShell plugins (architecture 5.4):
// only the per-plugin settings calls plugins make. Names follow
// DankMaterialShell's quickshell/Common/SettingsData.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC).
//
// A plugin's data is the haseen shell.json `plugins.<id>.settings` object
// overlaid with what the plugin saved during this session. A save applies at
// once and is written to shell.json through `haseen plugin settings`
// (Compat.Runtime.persist, the same writer Omarchy plugins use); the keys a
// plugin saves in one event loop turn go out as one request.
Singleton {
    id: root

    readonly property bool reduceMotion: false
    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek

    // DMS plugin id -> { key: value } saved this session.
    property var saved: ({})
    // Registry id -> { key: value } not yet handed to the writer.
    property var _unwritten: ({})

    signal pluginSettingChanged(string pluginId)

    // The registry id ("dms.example-plugin") of a DMS plugin id.
    function haseenId(pluginId: string): string {
        const reg = Haseen.Plugins.registry;
        for (const id in reg)
            if (reg[id].compat === "dms" && reg[id].upstreamId === pluginId)
                return id;
        return "";
    }

    function getPluginSettingsForPlugin(pluginId: string): var {
        const id = haseenId(pluginId);
        const out = id !== "" ? Haseen.Plugins.settingsFor(id) : {};
        const own = saved[pluginId] || {};
        for (const k in own)
            out[k] = own[k];
        return out;
    }

    function getPluginSetting(pluginId: string, key: string, defaultValue: var): var {
        const v = getPluginSettingsForPlugin(pluginId)[key];
        return v === undefined ? defaultValue : v;
    }

    function setPluginSetting(pluginId: string, key: string, value: var): void {
        const all = Object.assign({}, saved);
        const own = Object.assign({}, all[pluginId] || {});
        own[key] = value;
        all[pluginId] = own;
        saved = all;
        pluginSettingChanged(pluginId);
        const id = haseenId(pluginId);
        if (id === "")
            return;
        const unwritten = Object.assign({}, _unwritten);
        unwritten[id] = Object.assign({}, unwritten[id] || {});
        unwritten[id][key] = value;
        _unwritten = unwritten;
        Qt.callLater(root._write);
    }

    function _write(): void {
        const unwritten = _unwritten;
        _unwritten = {};
        for (const id in unwritten) {
            const changes = Object.keys(unwritten[id]).map(key => unwritten[id][key] === undefined ? {
                    path: ["plugins", id, "settings", key],
                    remove: true
                } : {
                    path: ["plugins", id, "settings", key],
                    value: unwritten[id][key]
                });
            Compat.Runtime.persist(id, {
                changes: changes
            });
        }
    }
}
