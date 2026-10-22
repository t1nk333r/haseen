import QtQuick
import Quickshell.Io
import qs.Haseen as Haseen

// qs.Commons.Translations for Omarchy plugins that ship their own catalogs
// (architecture 5.4, plan 109). Adapted from Omarchy
// shell/Commons/Translations.qml (v4.5.0-rc1, MIT, Copyright (c) David
// Heinemeier Hansson); the language is haseen's interface language
// (`haseen language`). A plugin points it at its directory of flat JSON
// catalogs, one per code (en.json, ar.json, …):
//
//   Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
//   Text { text: strings.t("panel.title") }
//
// A value is a string, or an object of CLDR plural forms for tn(). A string
// the language lacks falls back to its base language (pt-BR to pt), then to
// en.json, then to the key. Only the plugin's own files are read.
QtObject {
    id: root

    // A filesystem path or file:// URL (Qt.resolvedUrl("i18n") from the plugin).
    property var directory: ""

    readonly property string language: Haseen.I18n.language
    readonly property string baseLanguage: language.split("-")[0]
    readonly property string directoryPath: String(directory).replace(/^file:\/\//, "").replace(/\/+$/, "")

    property var strings: ({})
    property var englishStrings: ({})
    property var baseStrings: ({})
    property var languageStrings: ({})

    function t(key, fallback) {
        let value = root.strings[key];
        if (value && typeof value === "object")
            value = value.other;
        if (typeof value === "string" && value.length > 0)
            return value;
        return fallback !== undefined ? fallback : key;
    }

    // The layer that carries the entry decides which language's rules apply.
    function tn(key, count, fallback) {
        const layers = [[root.languageStrings, root.language], [root.baseStrings, root.baseLanguage], [root.englishStrings, "en"]];
        for (let i = 0; i < layers.length; i++) {
            const value = Haseen.I18n.pick(layers[i][0][key], count, layers[i][1]);
            if (typeof value === "string" && value.length > 0)
                return value;
        }
        return fallback !== undefined ? fallback : key;
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
        const layers = [root.englishStrings, root.baseStrings, root.languageStrings];
        for (let i = 0; i < layers.length; i++)
            for (const key in layers[i])
                if (typeof layers[i][key] === "string" || (layers[i][key] && typeof layers[i][key] === "object"))
                    merged[key] = layers[i][key];
        root.strings = merged;
    }

    function catalogPath(code) {
        return root.directoryPath !== "" ? root.directoryPath + "/" + code + ".json" : "";
    }

    // A plugin creates this when it loads, which can be long after the
    // shell's load: a FileView made then does not read its file by itself.
    Component.onCompleted: {
        for (const view of [englishFile, baseFile, languageFile])
            if (!view.loaded && view.path !== "")
                view.reload();
    }

    property FileView englishFile: FileView {
        path: root.catalogPath("en")
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: {
            root.englishStrings = root.parseCatalog(text());
            root.rebuildStrings();
        }
        onLoadFailed: {
            root.englishStrings = ({});
            root.rebuildStrings();
        }
        onFileChanged: reload()
    }

    // Only read for a regional code; for "ar" the language file covers it.
    property FileView baseFile: FileView {
        path: root.baseLanguage !== root.language && root.baseLanguage !== "en" ? root.catalogPath(root.baseLanguage) : ""
        printErrors: false
        blockLoading: true
        onLoaded: {
            root.baseStrings = root.parseCatalog(text());
            root.rebuildStrings();
        }
        onLoadFailed: {
            root.baseStrings = ({});
            root.rebuildStrings();
        }
        onPathChanged: if (path === "") {
            root.baseStrings = ({});
            root.rebuildStrings();
        }
    }

    property FileView languageFile: FileView {
        path: root.language !== "en" ? root.catalogPath(root.language) : ""
        printErrors: false
        blockLoading: true
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
