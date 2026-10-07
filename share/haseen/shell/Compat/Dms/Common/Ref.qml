import QtQuick
import Quickshell

// qs.Common.Ref for DankMaterialShell plugins (architecture 5.4): holds a
// reference on a sampling service while it exists and `active` is true, so
// the service samples only while someone shows its data. Adapted from
// DankMaterialShell's quickshell/Common/Ref.qml (MIT, Copyright (c) 2025
// Avenge Media LLC): with `modules` it calls service.addRef(modules) /
// removeRef(modules), without them it moves service.refCount.
QtObject {
    required property Singleton service
    property var modules: null
    property bool active: true

    property bool _held: false

    function sync(wanted) {
        if (wanted === _held)
            return;
        _held = wanted;
        if (modules === null) {
            service.refCount += wanted ? 1 : -1;
            return;
        }
        if (wanted) {
            service.addRef(modules);
            return;
        }
        service.removeRef(modules);
    }

    onActiveChanged: sync(active)
    Component.onCompleted: sync(active)
    Component.onDestruction: sync(false)
}
