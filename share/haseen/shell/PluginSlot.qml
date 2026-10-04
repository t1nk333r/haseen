import QtQuick
import qs.Haseen

// Loads one plugin entry (architecture 5.2) and hands it pluginId, settings
// and screen. settings stays bound, so editing shell.json updates the widget
// in place. The slot is visible once loaded and never hidden for a zero
// width: hiding it would hide the widget too, and a widget whose width
// follows its own visibility (an Omarchy idiom: `implicitWidth: visible ? w
// : 0`) could then never come back. BarSection sizes bar slots to the item's
// implicitWidth, so a widget reporting 0 (e.g. no battery) takes no room.
Loader {
    id: slot

    required property string pluginId
    property string kind: "bar-widget"
    property var screen: null
    readonly property string url: Plugins.componentUrl(pluginId, kind)

    visible: status === Loader.Ready && item !== null
    asynchronous: false

    // The url last handed to load(); null before the first load.
    property var _loadedUrl: null
    property bool _completed: false

    // Exactly one build per distinct url: `url` first evaluates while
    // pluginId is still empty, and onUrlChanged fires during construction, so
    // nothing loads before Component.onCompleted (all properties set).
    function load(): void {
        if (!_completed || pluginId === "" || url === _loadedUrl)
            return;
        _loadedUrl = url;
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
    Component.onCompleted: {
        _completed = true;
        load();
    }

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
