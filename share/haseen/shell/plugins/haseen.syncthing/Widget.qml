import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.syncthing bar widget (plan 098): one glyph from the haseen.syncthing
// service (role `syncthing`): accent while syncing or invited, urgent on a
// folder error, muted while stopped or paused. Click opens the panel. Takes
// no room until the service runs (it must be listed in `services`). Adapted
// from the status icon of ilyaZar's omarchy-syncthing (MIT, Copyright (c)
// 2026 IlyaZar); its SVGs (MPL-2.0, Syncthing's) are not used.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    property var service: {
        const entry = Plugins.roles.syncthing;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property string kind: service ? service.summary.kind : "offline"

    glyph: Model.glyph(kind)
    color: kind === "error" ? Theme.urgent : kind === "syncing" || kind === "invited" ? Theme.accent : kind === "idle" ? Theme.barForeground : Theme.muted
    implicitWidth: service ? contentWidth : 0

    onClicked: Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId])
}
