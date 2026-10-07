import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Common as DmsCommon
import qs.Services as Dms
import "Host.js" as Host
import "Layers.js" as Layers
import "DesktopGeometry.js" as Geometry

// One screen's window for a DMS desktop widget (DmsDesktopHost). It creates
// the plugin's DesktopPluginComponent and hands it what DMS's
// Modules/Plugins/DesktopWidgetContent.qml hands it on load (pluginService,
// pluginId, screen, widgetWidth/widgetHeight bound to the window, and
// requestResize/clearResize), on the layer and with the keyboard rule of
// Modules/Plugins/DesktopPluginWrapper.qml: below windows, ignoring
// exclusive zones, keyboard focus on demand only for a widget that sets
// acceptsKeyboardFocus. Size and position come from DesktopGeometry.js, read
// from `placement`.
PanelWindow {
    id: win

    property string pluginId
    property string upstreamId
    property string entryUrl
    property var placement: ({})
    property var settings: ({})

    property Item widget: null
    property var _cancelLoad: null
    // The size the plugin asks for, read once it exists
    // (Geometry.defaultSize).
    property real defaultWidth: 280
    property real defaultHeight: 180
    // requestResize(): a size the widget sets for itself until clearResize().
    property real resizeWidth: -1
    property real resizeHeight: -1

    readonly property real screenWidth: screen ? screen.width : 1920
    readonly property real screenHeight: screen ? screen.height : 1080
    readonly property real minWidth: widget && typeof widget.minWidth === "number" ? widget.minWidth : 100
    readonly property real minHeight: widget && typeof widget.minHeight === "number" ? widget.minHeight : 100
    readonly property bool forceSquare: widget !== null && widget.forceSquare === true
    readonly property var geometry: Geometry.place(placement, screenWidth, screenHeight, {
        defaultWidth: defaultWidth,
        defaultHeight: defaultHeight,
        minWidth: minWidth,
        minHeight: minHeight,
        forceSquare: forceSquare,
        resizeWidth: resizeWidth,
        resizeHeight: resizeHeight
    })
    readonly property real widgetWidth: geometry.width
    readonly property real widgetHeight: geometry.height
    readonly property real widgetX: geometry.x
    readonly property real widgetY: geometry.y

    function requestResize(width: real, height: real): void {
        if (width < minWidth || height < minHeight || width > screenWidth || height > screenHeight)
            return;
        resizeWidth = width;
        resizeHeight = height;
    }

    function clearResize(): void {
        resizeWidth = -1;
        resizeHeight = -1;
    }

    visible: widget !== null && DmsCommon.SettingsData.desktopWidgetShown(upstreamId)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: widgetWidth
    implicitHeight: widgetHeight

    anchors {
        left: true
        top: true
    }

    margins {
        left: Math.round(widgetX)
        top: Math.round(widgetY)
    }

    WlrLayershell.namespace: "haseen-desktop-widget"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: widget !== null && widget.acceptsKeyboardFocus === true ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onSettingsChanged: {
        if (widget !== null && typeof widget.loadPluginData === "function")
            widget.loadPluginData();
    }

    Component.onCompleted: {
        _cancelLoad = Host.load(entryUrl, win.contentItem, result => {
            if (result.error !== "") {
                // Deferred: see OmarchyHost.
                const id = win.pluginId;
                const message = "dms: " + result.error;
                Qt.callLater(() => Plugins.reportError(id, message));
                return;
            }
            const w = result.item;
            // pluginService and pluginId first: a widget's own default size
            // usually comes from getData(), which needs both.
            if ("pluginService" in w)
                w.pluginService = Dms.PluginService;
            if ("pluginId" in w)
                w.pluginId = win.upstreamId;
            const size = Geometry.defaultSize(w);
            win.defaultWidth = size.width;
            win.defaultHeight = size.height;
            if ("screen" in w)
                w.screen = Qt.binding(() => win.screen);
            if ("widgetWidth" in w)
                w.widgetWidth = Qt.binding(() => win.width);
            if ("widgetHeight" in w)
                w.widgetHeight = Qt.binding(() => win.height);
            if ("requestResize" in w)
                w.requestResize = win.requestResize;
            if ("clearResize" in w)
                w.clearResize = win.clearResize;
            w.width = Qt.binding(() => win.width);
            w.height = Qt.binding(() => win.height);
            win.widget = w;
            if (Quickshell.env("QT_QUICK_BACKEND") === "software")
                Layers.dropEffects(w);
        });
    }

    // The widget dies before its component (Host.load).
    Component.onDestruction: {
        if (widget !== null)
            widget.destroy();
        widget = null;
        if (_cancelLoad)
            _cancelLoad();
    }
}
