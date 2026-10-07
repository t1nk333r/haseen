import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat

// Desktop-widget host for DankMaterialShell plugins (architecture 5.4).
// ServiceHost loads this file once, shared by every screen, for a registry
// record with compat "dms" and kind "overlay" (a DMS `desktop` surface). As
// DMS's Modules/DesktopWidgetLayer.qml does (MIT, Copyright (c) 2025 Avenge
// Media LLC), every chosen screen gets its own window holding its own
// instance of the plugin's DesktopPluginComponent (DmsDesktopWindow).
//
// DMS keeps a list of widget instances, each placed by dragging in an edit
// mode. haseen has neither: an enabled plugin is one instance, placed by
// shell.json `plugins.<id>.settings.desktop`:
//   { "x": 24, "y": 24, "anchorX": "start|center|end", "anchorY": …,
//     "width": 300, "height": 520, "screens": ["eDP-1"] }
// x/y are offsets from the anchored edge (DMS's DesktopWidgetGeometry rule);
// without them the widget is centred, and without width/height it takes the
// size the plugin asks for. `screens` lists output names; absent, empty or
// ["all"] means every screen. Nothing starts before the plugin's
// startupCheck passes (DmsStartupGate).
Scope {
    id: host

    // Contract (ServiceHost).
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var record: Plugins.registry[pluginId] || null
    readonly property string upstreamId: record ? record.upstreamId : ""
    readonly property string entryUrl: Plugins.entryUrl(pluginId, "overlay")
    readonly property var placement: {
        const p = settings ? settings.desktop : null;
        return p !== null && typeof p === "object" && !Array.isArray(p) ? p : {};
    }
    readonly property var screenNames: Array.isArray(placement.screens) ? placement.screens.filter(n => typeof n === "string" && n !== "all") : []
    property bool started: false
    property var _life: ({
            gone: false
        })

    Component.onCompleted: {
        const life = _life;
        Compat.DmsStartupGate.run(pluginId, ok => {
            if (ok && !life.gone)
                host.started = true;
        });
    }
    Component.onDestruction: _life.gone = true

    Variants {
        model: host.started && host.entryUrl !== "" ? Quickshell.screens.filter(s => host.screenNames.length === 0 || host.screenNames.indexOf(s.name) >= 0) : []

        DmsDesktopWindow {
            required property var modelData

            screen: modelData
            pluginId: host.pluginId
            upstreamId: host.upstreamId
            entryUrl: host.entryUrl
            placement: host.placement
            settings: host.settings
        }
    }
}
