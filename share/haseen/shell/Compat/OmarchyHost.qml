import QtQuick
import Quickshell
import qs.Haseen
import "Host.js" as Host

// Bar-widget host for Omarchy plugins (architecture 5.4). PluginSlot loads
// this file for a registry record with compat "omarchy"; it creates the
// plugin's barWidget entry and injects what Omarchy's bar injects:
//   bar        - the facade below (Omarchy's PluginBarApi surface)
//   moduleName - the plugin id
//   settings   - manifest barWidget.defaults merged with shell.json settings
// A plugin that fails to compile (an import or type the adapter does not
// provide) is reported once through Plugins.reportError and takes no room.
//
// The facade's members follow Omarchy's shell/Ui/PluginBarApi.qml
// (MIT, Copyright (c) David Heinemeier Hansson). Popouts, click-target
// forwarding and the plugin shell API have no haseen counterpart: popout
// requests log once, `shell` is null (Omarchy's value when no shell API is
// bound), and click targets keep their own MouseArea.
Item {
    id: host

    // Contract (architecture 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    property Item widget: null

    // Not gated on widget.visible: the widget's effective visibility depends
    // on the slot's, so the width must not feed back into it.
    implicitWidth: widget !== null ? widget.implicitWidth : 0
    implicitHeight: parent ? parent.height : Config.barHeight

    QtObject {
        id: api

        readonly property string pluginId: host.pluginId
        readonly property string moduleName: host.pluginId
        readonly property var shell: null
        readonly property color foreground: Theme.foreground
        readonly property color barForeground: Theme.foreground
        readonly property color themeForeground: Theme.foreground
        readonly property color text: Theme.foreground
        readonly property color background: Theme.background
        readonly property color urgent: Theme.urgent
        readonly property string fontFamily: Theme.fontFamily
        readonly property string position: Config.barPosition
        readonly property bool vertical: false
        readonly property int barSize: Config.barHeight
        readonly property bool transparent: false
        readonly property bool foregroundAnimationEnabled: true
        readonly property bool centerSectionRevealHeld: false
        readonly property bool centerHoverRevealSuppressed: false
        readonly property var activePopout: null
        readonly property var layoutConfig: ({})
        property var clickTargets: []

        function showTooltip(target, text) {
            tooltip.target = target;
            tooltip.text = String(text || "");
        }

        function hideTooltip(target) {
            if (tooltip.target === target)
                tooltip.target = null;
        }

        // Omarchy's bar forwards slot-wide presses to these; the widgets
        // here keep their own MouseArea, so only the list is kept.
        function registerClickTarget(target) {
            if (clickTargets.indexOf(target) < 0)
                clickTargets = clickTargets.concat([target]);
        }

        function unregisterClickTarget(target) {
            clickTargets = clickTargets.filter(t => t !== target);
        }

        function requestPopout(owner) {
            Plugins.warnOnce("omarchy-popout:" + host.pluginId, "plugin " + host.pluginId + ": Omarchy popouts are not supported by the compat adapter");
        }

        function releasePopout(owner) {
        }

        function switchPanelFrom(owner, direction) {
            return false;
        }

        function targetBelongsToWindow(target, window) {
            return false;
        }

        function moduleWidgets(id) {
            return String(id || "") === host.pluginId ? Host.instances(host.pluginId) : [];
        }

        function setCenterHoverRevealSuppressed(value) {
        }

        // Omarchy runs bar commands through a login bash (Util.execDetached).
        function run(command) {
            if (command)
                Quickshell.execDetached(["bash", "-lc", String(command)]);
        }
    }

    Tooltip {
        id: tooltip
    }

    Component.onCompleted: {
        const url = Plugins.entryUrl(pluginId, "bar-widget");
        Host.load(url, host, result => {
            if (result.error !== "") {
                // Deferred: this runs inside PluginSlot's url change, and
                // reportError rebuilds the registry that url is bound to.
                const message = "omarchy: " + result.error;
                const id = pluginId;
                Qt.callLater(() => Plugins.reportError(id, message));
                return;
            }
            const w = result.item;
            if ("bar" in w)
                w.bar = api;
            if ("moduleName" in w)
                w.moduleName = pluginId;
            if ("settings" in w)
                w.settings = Qt.binding(() => host.settings);
            w.height = Qt.binding(() => host.height);
            w.width = Qt.binding(() => w.implicitWidth);
            Host.register(pluginId, w);
            host.widget = w;
        });
    }

    Component.onDestruction: {
        if (widget !== null)
            Host.unregister(pluginId, widget);
    }
}
