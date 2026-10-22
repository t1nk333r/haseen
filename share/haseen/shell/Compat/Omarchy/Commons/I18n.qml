pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen as Haseen

// qs.Commons.I18n for Omarchy plugins written against Omarchy 4.5
// (architecture 5.4, plan 109). Adapted from Omarchy shell/Commons/I18n.qml
// (v4.5.0-rc1, MIT, Copyright (c) David Heinemeier Hansson): the same API
// (t, tn, formatNumber, language, formatLocale, decimal, zeroDigit,
// rightToLeft), with the language, direction and number format taken from
// haseen's own interface language (qs.Haseen.I18n, `haseen language`), not
// ~/.config/omarchy/language.
//
// Omarchy's keys ("common.search") are Omarchy's: their strings come from
// Omarchy's catalogs when its package is installed
// ($OMARCHY_PATH, else /usr/share/omarchy, /default/i18n/<code>/shell.json,
// English underneath), else from the fallback a plugin passes, else the key.
// Nothing is polled; a language switch re-renders bindings that call t().
// A Singleton with child FileViews, not Omarchy's QtObject with FileView
// properties: a FileView held as a property value never read its file at
// construction here (Quickshell 0.3.2).
Singleton {
    id: root

    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    readonly property string catalogDir: omarchyPath + "/default/i18n"

    readonly property string language: Haseen.I18n.language
    readonly property string formatLocale: Haseen.I18n.formatLocale.replace("_", "-")
    readonly property string decimal: Haseen.I18n.decimal
    readonly property string zeroDigit: Haseen.I18n.zeroDigit
    readonly property bool rightToLeft: Haseen.I18n.rightToLeft

    // Reassigned whole on every load so bindings that called t() re-evaluate.
    property var strings: ({})
    property var englishStrings: ({})
    property var languageStrings: ({})

    function t(key, fallback) {
        let value = root.strings[key];
        if (value && typeof value === "object")
            value = value.other;
        if (typeof value === "string" && value.length > 0)
            return value;
        return fallback !== undefined ? fallback : key;
    }

    function tn(key, count, fallback) {
        let value = Haseen.I18n.pick(root.languageStrings[key], count, root.language);
        if (typeof value !== "string" || value.length === 0)
            value = Haseen.I18n.pick(root.englishStrings[key], count, "en");
        if (typeof value === "string" && value.length > 0)
            return value;
        return fallback !== undefined ? fallback : key;
    }

    function formatNumber(value, decimals) {
        return Haseen.I18n.formatNumber(value, decimals);
    }

    function parseCatalog(raw) {
        try {
            const parsed = JSON.parse(raw || "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    function rebuildStrings() {
        const merged = ({});
        for (const k in root.englishStrings)
            merged[k] = root.englishStrings[k];
        for (const k in root.languageStrings)
            merged[k] = root.languageStrings[k];
        root.strings = merged;
    }

    // Created on a plugin's first use, which can be long after the shell's
    // load: a FileView made then does not read its file by itself, and
    // reload() reads it after this call returns (bindings follow).
    Component.onCompleted: {
        for (const view of [englishView, languageView])
            if (!view.loaded && view.path !== "")
                view.reload();
    }

    FileView {
        id: englishView

        path: root.catalogDir + "/en/shell.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.englishStrings = root.parseCatalog(text());
            root.rebuildStrings();
        }
    }

    FileView {
        id: languageView

        path: root.language !== "en" ? root.catalogDir + "/" + root.language + "/shell.json" : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.languageStrings = root.parseCatalog(text());
            root.rebuildStrings();
        }
        onLoadFailed: {
            root.languageStrings = ({});
            root.rebuildStrings();
        }
        onPathChanged: if (path === "") {
            root.languageStrings = ({});
            root.rebuildStrings();
        }
    }
}
