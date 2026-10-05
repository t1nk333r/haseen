import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import "Compat/Host.js" as EntryLoader

// Creates one service-kind plugin instance (a non-visual object) and
// registers it for every role its manifest `provides`.
Scope {
    id: host

    required property string modelData
    readonly property string pluginId: modelData.indexOf(":") >= 0 ? modelData.slice(modelData.indexOf(":") + 1) : modelData
    readonly property string kind: modelData.indexOf(":") >= 0 ? modelData.slice(0, modelData.indexOf(":")) : Plugins.serviceKind(pluginId)
    readonly property string url: Plugins.componentUrl(pluginId, kind)
    readonly property string loadKey: url + "|" + Plugins.entryUrl(pluginId, kind)
    property var instance: null
    property var _roles: []
    property bool _nativeService: false
    property bool _nativeOverlay: false
    property bool _completed: false
    property var _loadedKey: null
    property var _cancelLoad: null

    function unload(): void {
        for (const role of _roles)
            Plugins.unregisterRole(role, instance);
        _roles = [];
        // Summon routes an overlay-kind record through overlayFor(), which
        // reads the overlays map only; a native overlay must live there.
        if (_nativeOverlay && instance)
            Compat.Runtime.unregisterOverlay(pluginId, instance);
        if (_nativeService && instance)
            Compat.Runtime.unregisterService(pluginId, instance);
        _nativeService = false;
        _nativeOverlay = false;
        // The instance dies before its component: a destroyed component must
        // not invalidate bindings that a live instance still evaluates.
        if (instance)
            instance.destroy();
        instance = null;
        if (_cancelLoad)
            _cancelLoad();
        _cancelLoad = null;
    }

    function load(): void {
        // Registry error reports can rebuild the model. Only an actual entry
        // change should restart a service, not that rebuild or a second
        // construction callback.
        if (!_completed || pluginId === "" || loadKey === _loadedKey)
            return;
        _loadedKey = loadKey;
        unload();
        if (url === "") {
            Plugins.noteMissing(pluginId, kind);
            return;
        }
        const rec = Plugins.registry[pluginId];
        const props = {
            pluginId: pluginId,
            settings: Qt.binding(() => Plugins.settingsFor(host.pluginId)),
            screen: null
        };
        if (rec.compat === "omarchy")
            props.kind = kind;
        const key = _loadedKey;
        _cancelLoad = EntryLoader.load(url, host, result => {
            if (!host._completed || key !== host._loadedKey) {
                if (result.item)
                    result.item.destroy();
                return;
            }
            if (result.error) {
                const id = pluginId, message = result.error;
                Qt.callLater(() => Plugins.reportError(id, message));
                return;
            }
            instance = result.item;
            _nativeOverlay = rec.compat === "" && kind === "overlay";
            _nativeService = rec.compat === "" && !_nativeOverlay;
            if (_nativeOverlay)
                Compat.Runtime.registerOverlay(pluginId, instance);
            else if (_nativeService)
                Compat.Runtime.registerService(pluginId, instance);
            _roles = rec.provides.slice();
            for (const role of _roles)
                Plugins.registerRole(role, pluginId, instance);
        }, props);
    }

    onLoadKeyChanged: Qt.callLater(load)
    Component.onCompleted: {
        _completed = true;
        Qt.callLater(load);
    }
    Component.onDestruction: {
        _completed = false;
        unload();
    }

    Connections {
        target: Plugins
        function onReadyChanged() {
            if (host.url === "")
                Plugins.noteMissing(host.pluginId, host.kind);
        }
    }
}
