pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen
import qs.Compat as Compat

// qs.Common.SettingsData for DankMaterialShell plugins (architecture 5.4):
// the per-plugin settings calls plugins make, and the desktop-widget
// instance list (below). Names follow
// DankMaterialShell's quickshell/Common/SettingsData.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC).
//
// A plugin's data is the haseen shell.json `plugins.<id>.settings` object
// overlaid with what the plugin saved and shell.json does not hold yet. A
// save applies at once and is written to shell.json through `haseen plugin
// settings` (Compat.Runtime.persist, the same writer Omarchy plugins use); the
// keys a plugin saves in one event loop turn go out as one request. Once the
// writer confirms a request, shell.json is those keys' record again, so a
// later edit of the file shows through.
Singleton {
    id: root

    readonly property bool reduceMotion: false
    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek

    // DMS plugin id -> { key: value } saved this session, until shell.json
    // holds the same value.
    property var saved: ({})
    // Registry id -> { key: value } not yet handed to the writer.
    property var _unwritten: ({})
    // Registry id -> [{ key: value }] handed to the writer and not answered
    // yet, oldest first: the writer answers one request at a time, in order.
    property var _inflight: ({})

    property Connections _written: Connections {
        target: Compat.Runtime
        function onSettingsWritten(pluginId: string, success: bool) {
            root._settled(pluginId, success);
        }
    }

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
            const inflight = Object.assign({}, _inflight);
            inflight[id] = (inflight[id] || []).concat([unwritten[id]]);
            _inflight = inflight;
            if (!Compat.Runtime.persist(id, {
                changes: changes
            }))
                _settled(id, false);
        }
    }

    // The writer answered the oldest request of `id`. When it was stored, the
    // session copy of each key it wrote is dropped once shell.json shows the
    // same value, so the drop changes nothing the plugin sees; a newer save
    // of another value, still on its way, keeps its copy.
    function _settled(id: string, success: bool): void {
        const queue = _inflight[id];
        if (!queue || !queue.length)
            return;
        const batch = queue[0];
        const inflight = Object.assign({}, _inflight);
        inflight[id] = queue.slice(1);
        if (!inflight[id].length)
            delete inflight[id];
        _inflight = inflight;
        const rec = Haseen.Plugins.registry[id];
        const upstream = rec ? rec.upstreamId : "";
        if (!success || !upstream || !saved[upstream])
            return;
        const stored = Haseen.Plugins.settingsFor(id);
        const own = Object.assign({}, saved[upstream]);
        for (const key in batch)
            if (key in own && JSON.stringify(own[key]) === JSON.stringify(stored[key]))
                delete own[key];
        const all = Object.assign({}, saved);
        if (Object.keys(own).length)
            all[upstream] = own;
        else
            delete all[upstream];
        saved = all;
    }

    // DMS saves its settings file here; haseen already wrote each key above.
    function savePluginSettings(): void {
    }

    // ------------------------------------------------- desktop widgets
    // DMS keeps a list of desktop-widget instances (SettingsData
    // desktopWidgetInstances, read by Modules/DesktopWidgetLayer.qml). haseen
    // runs one per enabled DMS plugin with a desktop surface
    // (Compat/DmsDesktopHost.qml): its id and widgetType are the DMS plugin
    // id and its config is the plugin's settings. Hiding or showing one with
    // updateDesktopWidgetInstance({ enabled }) lasts for the session; turning
    // the plugin off for good is `haseen plugin disable`.
    property var _hiddenDesktopWidgets: ({})
    readonly property var desktopWidgetInstances: {
        const reg = Haseen.Plugins.registry;
        const out = [];
        for (const id of Haseen.Plugins.serviceIds) {
            const rec = reg[id];
            if (rec && rec.valid && rec.compat === "dms" && rec.kinds.indexOf("overlay") >= 0)
                out.push({
                    id: rec.upstreamId,
                    widgetType: rec.upstreamId,
                    name: rec.name,
                    enabled: !_hiddenDesktopWidgets[rec.upstreamId],
                    config: getPluginSettingsForPlugin(rec.upstreamId)
                });
        }
        return out;
    }

    function desktopWidgetShown(instanceId: string): bool {
        return _hiddenDesktopWidgets[instanceId] !== true;
    }

    function updateDesktopWidgetInstance(instanceId: string, updates: var): void {
        if (!updates || typeof updates !== "object")
            return;
        if (typeof updates.enabled === "boolean") {
            const hidden = Object.assign({}, _hiddenDesktopWidgets);
            if (updates.enabled)
                delete hidden[instanceId];
            else
                hidden[instanceId] = true;
            _hiddenDesktopWidgets = hidden;
        }
        if (updates.config && typeof updates.config === "object")
            updateDesktopWidgetInstanceConfig(instanceId, updates.config);
    }

    function updateDesktopWidgetInstanceConfig(instanceId: string, updates: var): void {
        for (const key in updates)
            setPluginSetting(instanceId, key, updates[key]);
    }
}
