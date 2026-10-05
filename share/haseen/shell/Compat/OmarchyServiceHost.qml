import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import "Host.js" as Host

// Omarchy service entries are instantiated once, independently of screens.
// Copyright (c) David Heinemeier Hansson (upstream API contract, MIT).
Scope {
    id: host
    property string pluginId
    property var settings: ({})
    property var screen: null
    property string kind: "service"
    property var instance: null
    property var _cancelLoad: null
    property bool _claimed: false
    property bool _destroying: false
    property bool _catalogueClaimed: false
    readonly property string registrationKey: kind === "overlay" ? "overlay:" + pluginId : pluginId
    ShellApi { id: shellApi; pluginId: host.pluginId }
    function syncOverlay() {
        if (kind !== "overlay" || !instance) return;
        const opened = instance.opened === true || instance.shown === true || instance.rulesOpen === true;
        if (opened) Compat.Runtime.requestPopout(instance);
        else Compat.Runtime.releasePopout(instance);
    }
    Connections {
        target: host.kind === "overlay" ? host.instance : null
        ignoreUnknownSignals: true
        function onOpenedChanged() { host.syncOverlay(); }
        function onShownChanged() { host.syncOverlay(); }
        function onRulesOpenChanged() { host.syncOverlay(); }
    }

    Component.onCompleted: {
        _claimed = Compat.Runtime.claimService(registrationKey, host);
        if (!_claimed) {
            Plugins.warnOnce("compat-service-duplicate:" + pluginId, "compat: duplicate service host skipped for " + pluginId);
            return;
        }
        const url = Plugins.entryUrl(pluginId, kind);
        if (!url) { Plugins.noteMissing(pluginId, kind); return; }
        const record = Plugins.registry[pluginId];
        let catalogue = null;
        try {
            const declarations = Host.propertiesFor(url, null, host);
            if (declarations.barWidgetRegistry && declarations.barWidgetRegistry.writable) {
                catalogue = Compat.Runtime.acquireCatalogue(host);
                _catalogueClaimed = true;
            }
        } catch (e) {
            const id = pluginId, message = "omarchy: " + String(e);
            Qt.callLater(() => Plugins.reportError(id, message)); return;
        }
        _cancelLoad = Host.load(url, host, result => {
            if (host._destroying) { if (result.item) result.item.destroy(); return; }
            if (result.error) {
                const id = pluginId, message = "omarchy: " + result.error;
                Qt.callLater(() => Plugins.reportError(id, message)); return;
            }
            host.instance = result.item;
            const registered = kind === "overlay" ? Compat.Runtime.registerOverlay(pluginId, host.instance) : Compat.Runtime.registerService(pluginId, host.instance);
            if (!registered) {
                instance.destroy(); instance = null;
                Plugins.warnOnce("compat-service-conflict:" + pluginId, "compat: service already registered for " + pluginId);
            }
            if (registered) host.syncOverlay();
        }, {
            shell: shellApi,
            barWidgetRegistry: catalogue,
            pluginRegistry: Compat.Runtime.pluginRegistry,
            settings: Qt.binding(() => host.settings),
            moduleName: record && record.upstreamId ? record.upstreamId : pluginId,
            pluginId: pluginId,
            screen: Qt.binding(() => host.screen),
            manifest: record ? Object.assign({}, record.upstreamManifest || record, { __sourceDir: record.dir }) : null
        });
    }
    Component.onDestruction: {
        _destroying = true;
        if (_cancelLoad) _cancelLoad();
        if (instance) {
            if (kind === "overlay") Compat.Runtime.unregisterOverlay(pluginId, instance);
            else Compat.Runtime.unregisterService(pluginId, instance);
            instance.destroy(); instance = null;
        }
        if (_claimed) Compat.Runtime.releaseService(registrationKey, host);
        if (_catalogueClaimed) Compat.Runtime.releaseCatalogue(host);
    }
}
