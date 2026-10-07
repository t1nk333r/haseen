import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import qs.Services as Dms
import "Host.js" as Host
import "Layers.js" as Layers

// Bar-widget host for DankMaterialShell plugins (architecture 5.4).
// PluginSlot loads this file for a registry record with compat "dms"; it
// creates the plugin's widget component (a PluginComponent) and sets what
// DMS's bar sets: pluginId (the DMS id, which the plugin's own
// savePluginData calls use), pluginService, section, parentScreen and the
// bar thickness. Under the software renderer its layer effects are turned
// off (Layers.js). A plugin that fails to compile (an import or type the
// adapter does not provide) is reported once through Plugins.reportError
// and takes no room; so does one whose plugin.json `startupCheck` refuses
// (DmsStartupGate).
Item {
    id: host

    // Contract (architecture 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    property Item widget: null
    readonly property var record: Plugins.registry[pluginId] || null
    readonly property string section: ["left", "center", "right"].find(s => Config.section(s).indexOf(pluginId) >= 0) || "center"

    // A widget hidden with `visible: false` takes no room (BarSection.qml).
    implicitWidth: widget !== null && widget.visible ? widget.implicitWidth : 0
    implicitHeight: parent ? parent.height : Config.barHeight

    // shell.json settings are part of pluginData.
    onSettingsChanged: {
        if (widget !== null && typeof widget.loadPluginData === "function")
            widget.loadPluginData();
    }

    // Set to true on destruction; the startup check can answer later.
    property var _life: ({
            gone: false
        })
    Component.onDestruction: _life.gone = true

    Component.onCompleted: {
        const url = Plugins.entryUrl(pluginId, "bar-widget");
        const upstream = record ? record.upstreamId : "";
        const life = _life;
        Compat.DmsStartupGate.run(pluginId, ok => {
            if (ok && !life.gone)
                host._build(url, upstream);
        });
    }

    function _build(url: string, upstream: string): void {
        Host.load(url, host, result => {
            if (result.error !== "") {
                // Deferred: see OmarchyHost.
                const message = "dms: " + result.error;
                const id = pluginId;
                Qt.callLater(() => Plugins.reportError(id, message));
                return;
            }
            const w = result.item;
            const props = {
                pluginService: Dms.PluginService,
                section: host.section,
                parentScreen: host.screen,
                barConfig: {
                    position: Config.barPosition === "bottom" ? 1 : 0
                },
                pluginId: upstream
            };
            for (const k in props)
                if (k in w)
                    w[k] = props[k];
            if ("barThickness" in w)
                w.barThickness = Qt.binding(() => Config.barHeight);
            if ("widgetThickness" in w)
                w.widgetThickness = Qt.binding(() => Config.barHeight);
            w.height = Qt.binding(() => host.height);
            host.widget = w;
            if (Quickshell.env("QT_QUICK_BACKEND") === "software")
                Layers.dropEffects(w);
        });
    }
}
