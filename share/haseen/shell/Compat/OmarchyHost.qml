import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import "Host.js" as Host

// PluginBarApi and panel-loader injection contracts adapted from Omarchy (MIT).
// Copyright (c) David Heinemeier Hansson
Item {
    id: host
    property string pluginId
    property var settings: ({})
    property var screen: null
    property string kind: "bar-widget"
    property bool vertical: Config.barVertical
    property Item widget: null
    readonly property var barApi: api
    property var _cancelLoad: null
    property bool _destroying: false
    property bool _catalogueClaimed: false
    // Upstream hands a panel entry no surface, so one that builds its own
    // window is loaded outside the native popup and keeps its own geometry.
    readonly property bool selfWindowed: kind === "panel" && Compat.Runtime.panelSelfWindowed(pluginId)
    implicitWidth: widget ? widget.implicitWidth : 0
    implicitHeight: widget ? widget.implicitHeight : Config.barThickness

    ShellApi { id: shellApi; pluginId: host.pluginId; bar: api }
    QtObject {
        id: api
        readonly property string pluginId: host.pluginId
        readonly property string moduleName: host.pluginId
        readonly property var screen: host.screen
        readonly property string kind: host.kind
        readonly property var shell: shellApi
        readonly property color foreground: Theme.barForeground
        readonly property color barForeground: Theme.barForeground
        readonly property color themeForeground: Theme.foreground
        readonly property color text: Theme.barForeground
        readonly property color background: Theme.background
        readonly property color urgent: Theme.urgent
        readonly property string fontFamily: Theme.fontMono // Omarchy's bar font is `monospace`
        readonly property string position: Config.barPosition
        readonly property bool vertical: host.vertical
        readonly property int barSize: Config.barThickness
        readonly property bool transparent: Config.barTransparent
        readonly property bool foregroundAnimationEnabled: true
        property bool centerSectionRevealHeld: activePopout !== null
        property bool _centerHoverRevealSuppressed: false
        readonly property bool centerHoverRevealSuppressed: _centerHoverRevealSuppressed
        readonly property var activePopout: Compat.Runtime.activePopout
        readonly property var layoutConfig: Config.bar
        readonly property var foreignPopoutMarker: ({ foreign: true })
        property var clickTargets: []
        property int tooltipRequest: 0
        property Item tooltipTarget: null
        property string tooltipText: ""
        property bool tooltipShown: false
        property Item pendingTooltipTarget: null
        property string pendingTooltipText: ""
        // Upstream Bar.qml: a tooltip needs its target still hovered, visible
        // and opaque. A target without `tooltipHovered` (a plugin's own item)
        // counts as hovered until it says otherwise.
        function targetTooltipHovered(target) {
            return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered !== false;
        }
        // This widget's own panel is open: its tooltip would sit on top of it.
        readonly property bool ownPopoutOpen: activePopout !== null && host.widget !== null
            && (activePopout === host.widget || Compat.Runtime.belongsTo(activePopout, host.widget))
        // What the tooltip window follows. A binding, not a poll: it drops the
        // moment the target stops being hovered or the widget's panel opens.
        readonly property bool tooltipVisible: tooltipShown && !ownPopoutOpen && targetTooltipHovered(tooltipTarget)
        onOwnPopoutOpenChanged: if (ownPopoutOpen) clearTooltip()

        function clearTooltip() {
            tooltipDelay.stop();
            pendingTooltipTarget = null; pendingTooltipText = "";
            tooltipShown = false; tooltipTarget = null; tooltipText = "";
        }
        // Shown after 400 ms of hover, as upstream: a pointer crossing the bar
        // or clicking straight through does not flash one.
        function showTooltip(target, text) {
            clearTooltip(); tooltipRequest++;
            const value = String(text || "");
            if (value === "" || ownPopoutOpen || !targetTooltipHovered(target)) return;
            pendingTooltipTarget = target; pendingTooltipText = value;
            tooltipDelay.restart();
        }
        function revealPendingTooltip() {
            const target = pendingTooltipTarget, value = pendingTooltipText;
            pendingTooltipTarget = null; pendingTooltipText = "";
            if (ownPopoutOpen || !targetTooltipHovered(target)) { clearTooltip(); return; }
            tooltipTarget = target; tooltipText = value; tooltipShown = true;
        }
        function hideTooltip(target) {
            if (!target || tooltipTarget === target || pendingTooltipTarget === target) { tooltipRequest++; clearTooltip(); }
        }
        function registerClickTarget(target) {
            if (target && clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target]);
        }
        function unregisterClickTarget(target) {
            hideTooltip(target); clickTargets = clickTargets.filter(t => t !== target);
        }
        function requestPopout(owner) {
            if (!Compat.Runtime.belongsTo(owner, host.widget) && owner !== host.widget) return false;
            clearTooltip(); return Compat.Runtime.requestPopout(owner);
        }
        function releasePopout(owner) {
            return Compat.Runtime.belongsTo(owner, host.widget) || owner === host.widget ? Compat.Runtime.releasePopout(owner) : false;
        }
        function switchPanelFrom(owner, direction) {
            return Compat.Runtime.belongsTo(owner, host.widget) || owner === host.widget ? Compat.Runtime.switchPanelFrom(owner, direction) : false;
        }
        function targetBelongsToWindow(target, window) { return target && target.QsWindow.window === window; }
        function moduleWidgets(id) { return Compat.Runtime.moduleWidgets(Compat.Runtime.resolve(id)); }
        function setCenterHoverRevealSuppressed(value) { _centerHoverRevealSuppressed = !!value; }
        function forwardClick(button, x, y) {
            for (const target of clickTargets) {
                if (!target || !target.visible || target.interactive === false || target.pressable === false) continue;
                const point = target.mapFromItem(host, x, y);
                if (point.x < 0 || point.y < 0 || point.x >= target.width || point.y >= target.height) continue;
                if (typeof target.triggerPress !== "function") continue;
                target.triggerPress(button); return true;
            }
            return false;
        }
        function run(command) {
            if (!command) return false;
            Quickshell.execDetached(["bash", "-lc", String(command)]); return true;
        }
    }
    // haseen:ui-timeout
    Timer {
        id: tooltipDelay
        interval: 400
        repeat: false
        onTriggered: api.revealPendingTooltip()
    }
    Tooltip {
        target: api.tooltipVisible ? api.tooltipTarget : null
        text: api.tooltipVisible ? api.tooltipText : ""
    }
    // Below the plugin's own MouseAreas: forwards only otherwise unhandled
    // slot presses, avoiding a duplicate press on interactive plugin children.
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => { mouse.accepted = api.forwardClick(mouse.button, mouse.x, mouse.y); }
    }
    Component.onCompleted: {
        const url = Plugins.entryUrl(pluginId, kind);
        if (!url) { Plugins.noteMissing(pluginId, kind); return; }
        const record = Plugins.registry[pluginId];
        const candidates = {
            bar: api, shell: shellApi,
            moduleName: pluginId, pluginId: pluginId,
            settings: Qt.binding(() => host.settings),
            screen: Qt.binding(() => host.screen)
        };
        // What Omarchy's panel loader injects before a panel is constructed:
        // the manifest as written, this plugin's companion service, and the
        // registries a panel asks for. The service binding stays live because
        // a companion can register after its panel is built.
        if (kind === "panel") {
            candidates.manifest = record ? Object.assign({}, record.upstreamManifest || record, { __sourceDir: record.dir }) : null;
            candidates.service = Qt.binding(() => Compat.Runtime.serviceFor(host.pluginId));
            candidates.pluginRegistry = Compat.Runtime.pluginRegistry;
            try {
                const declarations = Host.propertiesFor(url, null, host);
                if (declarations.barWidgetRegistry && declarations.barWidgetRegistry.writable) {
                    candidates.barWidgetRegistry = Compat.Runtime.acquireCatalogue(host);
                    _catalogueClaimed = true;
                }
            } catch (e) {
                const id = pluginId, message = "omarchy: " + String(e);
                Qt.callLater(() => Plugins.reportError(id, message)); return;
            }
        }
        _cancelLoad = Host.load(url, host, result => {
            if (host._destroying) { if (result.item) result.item.destroy(); return; }
            if (result.error) {
                const id = pluginId, message = "omarchy: " + result.error;
                Qt.callLater(() => Plugins.reportError(id, message)); return;
            }
            const w = result.item;
            if (!(w instanceof Item)) {
                w.destroy();
                const id = pluginId;
                Qt.callLater(() => Plugins.reportError(id, "omarchy: visual entry must be an Item")); return;
            }
            host.widget = w;
            if (!host.selfWindowed) {
                w.width = Qt.binding(() => host.kind !== "bar-widget" || host.vertical ? host.width : w.implicitWidth);
                w.height = Qt.binding(() => host.kind !== "bar-widget" || !host.vertical ? host.height : w.implicitHeight);
            }
            Compat.Runtime.registerWidget(pluginId, w, api);
        }, candidates);
    }
    Component.onDestruction: {
        _destroying = true;
        api.clearTooltip(); api.clickTargets = [];
        // The instance goes first: releasing the component invalidates the
        // context its functions and bindings were created in.
        if (widget) { Compat.Runtime.unregisterWidget(pluginId, widget); widget.destroy(); widget = null; }
        if (_cancelLoad) _cancelLoad();
        if (_catalogueClaimed) Compat.Runtime.releaseCatalogue(host);
    }
}
