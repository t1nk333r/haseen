import QtQuick
import qs.Haseen

// Loads one plugin entry (architecture 5.2) and hands it pluginId, settings
// and screen. settings stays bound, so editing shell.json updates the widget
// in place. A widget reporting implicitWidth 0 (e.g. no battery) takes no room.
Loader {
    id: slot

    required property string pluginId
    property string kind: "bar-widget"
    property var screen: null
    readonly property string url: Plugins.componentUrl(pluginId, kind)

    visible: status === Loader.Ready && item !== null && item.implicitWidth > 0
    asynchronous: false

    function load(): void {
        if (url === "") {
            source = "";
            Plugins.noteMissing(pluginId, kind);
            return;
        }
        setSource(url, {
            pluginId: pluginId,
            settings: Plugins.settingsFor(pluginId),
            screen: screen
        });
    }

    onUrlChanged: load()
    Component.onCompleted: load()

    Connections {
        target: Plugins
        function onReadyChanged() {
            if (slot.url === "")
                Plugins.noteMissing(slot.pluginId, slot.kind);
        }
    }

    onLoaded: item.settings = Qt.binding(() => Plugins.settingsFor(slot.pluginId))
    onStatusChanged: {
        if (status === Loader.Error)
            Plugins.reportError(pluginId, "failed to load " + url);
    }
}
