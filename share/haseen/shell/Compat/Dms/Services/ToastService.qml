pragma Singleton

import QtQuick
import Quickshell

// qs.Services.ToastService for DankMaterialShell plugins (architecture 5.4).
// Names follow DankMaterialShell's quickshell/Services/ToastService.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC). haseen has no toast surface,
// so a toast becomes a desktop notification (notify-send; urgency critical
// for errors), shown by whichever notification daemon runs.
Singleton {
    readonly property int levelInfo: 0
    readonly property int levelWarn: 1
    readonly property int levelError: 2

    function _notify(urgency: string, message: var, details: var): void {
        const args = ["notify-send", "--app-name=haseen", "--urgency=" + urgency, String(message || "")];
        if (details)
            args.push(String(details));
        Quickshell.execDetached(args);
    }

    function showInfo(message: var, details: var): void {
        _notify("low", message, details);
    }

    function showWarning(message: var, details: var): void {
        _notify("normal", message, details);
    }

    function showError(message: var, details: var): void {
        _notify("critical", message, details);
    }

    function showToast(message: var, level: var, details: var): void {
        _notify(level === 2 ? "critical" : (level === 1 ? "normal" : "low"), message, details);
    }
}
