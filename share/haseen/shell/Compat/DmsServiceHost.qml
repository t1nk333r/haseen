import QtQuick
import Quickshell
import qs.Haseen
import qs.Services as Dms
import "Host.js" as Host
import "Layers.js" as Layers

// Daemon host for DankMaterialShell plugins (architecture 5.4). ServiceHost
// loads this file once, shared by every screen, for a registry record with
// compat "dms" and kind "service" (a DMS `daemon` surface). As DMS's
// PluginService._createDaemonInstance does (MIT, Copyright (c) 2025 Avenge
// Media LLC), the daemon gets pluginId (the DMS id, which its own
// savePluginData calls use) and pluginService; shell.json settings reach it
// as pluginData. Under the software renderer its layer effects are turned
// off (Layers.js). A daemon that fails to compile is reported once through
// Plugins.reportError and nothing else starts.
Scope {
    id: host

    // Contract (ServiceHost).
    property string pluginId
    property var settings: ({})
    property var screen: null

    property var instance: null
    property var _cancelLoad: null
    property bool _destroying: false

    onSettingsChanged: {
        if (instance !== null && typeof instance.loadPluginData === "function")
            instance.loadPluginData();
    }

    Component.onCompleted: {
        const url = Plugins.entryUrl(pluginId, "service");
        const record = Plugins.registry[pluginId];
        const upstream = record ? record.upstreamId : "";
        _cancelLoad = Host.load(url, host, result => {
            if (host._destroying) {
                if (result.item)
                    result.item.destroy();
                return;
            }
            if (result.error !== "") {
                // Deferred: see OmarchyHost.
                const id = pluginId;
                const message = "dms: " + result.error;
                Qt.callLater(() => Plugins.reportError(id, message));
                return;
            }
            const daemon = result.item;
            if ("pluginService" in daemon)
                daemon.pluginService = Dms.PluginService;
            if ("pluginId" in daemon)
                daemon.pluginId = upstream;
            host.instance = daemon;
            if (Quickshell.env("QT_QUICK_BACKEND") === "software")
                Layers.dropEffects(daemon);
        });
    }

    // The daemon dies before its component (Host.load).
    Component.onDestruction: {
        _destroying = true;
        if (instance !== null)
            instance.destroy();
        instance = null;
        if (_cancelLoad)
            _cancelLoad();
    }
}
