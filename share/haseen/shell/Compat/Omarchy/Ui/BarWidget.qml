import QtQuick
import qs.Commons

// qs.Ui.BarWidget for Omarchy plugins (architecture 5.4): the base item every
// Omarchy bar widget extends. Compat/OmarchyHost.qml injects `bar` (the
// facade), `moduleName` and `settings`, the way Omarchy's bar does.
//
// Adapted from Omarchy's shell/Ui/BarWidget.qml
// (MIT, Copyright (c) David Heinemeier Hansson).
Item {
    id: root

    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})

    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

    // Calls `method` on every live instance of this widget (one per screen).
    function broadcast(method) {
        var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root];
        for (var i = 0; i < items.length; i++) {
            if (items[i] && typeof items[i][method] === "function")
                items[i][method]();
        }
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }
}
