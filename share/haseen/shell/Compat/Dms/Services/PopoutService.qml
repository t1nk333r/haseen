pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen
import qs.Compat as Compat

// qs.Services.PopoutService for DankMaterialShell plugins (architecture 5.4):
// the calls plugins make to open DMS's settings window on a page. Names follow
// DankMaterialShell's quickshell/Services/PopoutService.qml and the page ids
// of quickshell/Common/SettingsTabs.qml (MIT, Copyright (c) 2025 Avenge Media
// LLC). haseen has no settings window: a page with a haseen panel of the
// same subject opens that panel (`network_wifi` opens haseen.network); any
// other page is logged once and nothing opens.
Singleton {
    id: root

    // DMS settings page id, or the part before its first "_" -> haseen panel.
    readonly property var panels: ({
            "network": "haseen.network",
            "audio": "haseen.audio",
            "sound": "haseen.audio",
            "sounds": "haseen.audio",
            "theme": "haseen.themepicker",
            "personalization": "haseen.themepicker",
            "wallpaper": "haseen.background",
            "notifications": "haseen.notifications"
        })

    function panelFor(tabName: var): string {
        const page = String(tabName || "").trim().toLowerCase();
        return panels[page] || panels[page.split("_")[0]] || "";
    }

    function openSettingsWithTab(tabName: string, returnOrigin: var, reopen: var): void {
        const id = panelFor(tabName);
        if (id !== "" && Compat.Runtime.summon(id))
            return;
        Haseen.Plugins.warnOnce("dms-settings:" + tabName, "haseen: DMS settings page '" + tabName + "' has no haseen panel; nothing opened");
    }

    function openSettings(): void {
        Haseen.Plugins.warnOnce("dms-settings:", "haseen: DMS settings window is not provided by haseen; nothing opened");
    }

    function closeSettings(): void {
    }
}
