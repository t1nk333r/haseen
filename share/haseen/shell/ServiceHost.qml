import QtQuick
import Quickshell
import qs.Haseen

// Creates one service-kind plugin instance (a non-visual object) and
// registers it for every role its manifest `provides`.
Scope {
    id: host

    required property string modelData
    readonly property string pluginId: modelData
    readonly property string url: Plugins.componentUrl(pluginId, "service")
    property var instance: null
    property var _roles: []

    function unload(): void {
        for (const role of _roles)
            Plugins.unregisterRole(role, instance);
        _roles = [];
        if (instance)
            instance.destroy();
        instance = null;
    }

    function load(): void {
        unload();
        if (url === "") {
            Plugins.noteMissing(pluginId, "service");
            return;
        }
        const component = Qt.createComponent(url);
        if (component.status !== Component.Ready) {
            Plugins.reportError(pluginId, component.errorString().trim());
            return;
        }
        const obj = component.createObject(host, {
            pluginId: pluginId,
            settings: Plugins.settingsFor(pluginId),
            screen: null
        });
        if (!obj) {
            Plugins.reportError(pluginId, "service failed to instantiate");
            return;
        }
        obj.settings = Qt.binding(() => Plugins.settingsFor(host.pluginId));
        instance = obj;
        const rec = Plugins.registry[pluginId];
        _roles = rec ? rec.provides.slice() : [];
        for (const role of _roles)
            Plugins.registerRole(role, pluginId, obj);
    }

    onUrlChanged: load()
    Component.onCompleted: load()
    Component.onDestruction: unload()

    Connections {
        target: Plugins
        function onReadyChanged() {
            if (host.url === "")
                Plugins.noteMissing(host.pluginId, "service");
        }
    }
}
