pragma Singleton

import QtQuick
import Quickshell

// qs.Common.I18n for DankMaterialShell plugins (architecture 5.4). Function
// names follow DankMaterialShell's quickshell/Common/I18n.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC). Plugin translation files are
// not loaded: every string comes back as written (the plugins' source
// language, English in the examples).
Singleton {
    readonly property string locale: Qt.locale().name

    function tr(text: var, context: var): string {
        return String(text);
    }

    function trFor(pluginId: var, text: var): string {
        return String(text);
    }
}
