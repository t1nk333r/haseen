pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "I18nPlural.js" as Plural

// The shell's display language (plan 109), after Omarchy 4.5's I18n
// (shell/Commons/I18n.qml, MIT, Copyright (c) David Heinemeier Hansson).
//
// `haseen language <code>` writes the code to ~/.config/haseen/language; a
// missing or unknown code is English. Catalogs live in
// $HASEEN_PATH/i18n/<code>/: shell.json for the shell's strings, menu.json
// for the menu's rows, and locales.json names each language's direction and
// date locale. The language file is watched, so a switch re-renders every
// binding that called tr() without a restart.
//
// Strings are keyed by their English text (docs/architecture.md §5.8):
//   Text { text: I18n.tr("Sign in to network") }
//   Text { text: I18n.tr("%1 of %2", done, total) }
//   Text { text: I18n.tn("%1 update", "%1 updates", count) }
// A string the current catalog lacks shows in English, never as a key. JS
// helpers that return English mark it N_("…") for tools/i18n.py, and QML
// translates the result with tr().
Singleton {
    id: root

    readonly property string dir: Paths.haseenPath + "/i18n"
    readonly property string languageFile: Paths.userConfig + "/language"

    // What the language file asks for; `language` is it when the registry
    // knows it, else English.
    property string requested: ""
    // locales.json.
    property var registry: ({})
    readonly property string language: /^[a-z]{2,3}$/.test(requested) && registry[requested] ? requested : "en"
    readonly property var entry: registry[language] || ({})
    readonly property bool rightToLeft: entry.direction === "rtl"
    // Dates and month names follow the interface language, not the session's
    // LANG: Qt.formatDate() and a bare Qt.locale() read LANG.
    readonly property string formatLocale: entry.formatLocale || "en_US"
    readonly property var locale: Qt.locale(formatLocale)
    readonly property string decimal: entry.decimal || "."
    readonly property string zeroDigit: entry.zeroDigit || "0"
    // The registry codes in its order, for a picker.
    readonly property var languages: Object.keys(registry)

    // Reassigned whole on every load, never mutated in place, so bindings
    // that called tr() re-evaluate. English needs no catalog at run time: the
    // key is the English, and tn() carries both English forms.
    property var strings: ({})
    property var menuStrings: ({})

    // The translation of text, with %1..%9 filled from the further arguments.
    function tr(text, ...args): string {
        if (text === undefined || text === null)
            return "";
        const key = String(text);
        let value = root.language !== "en" ? root.strings[key] : undefined;
        if (value && typeof value === "object")
            value = value.other;
        return Plural.fill(typeof value === "string" && value !== "" ? value : key, args);
    }

    // The form of a counted string: plural (the English plural form) is the
    // key; %1 is the count in the language's digits, %2.. the further args.
    function tn(singular, plural, count, ...args): string {
        const key = String(plural);
        let value = root.language !== "en" ? Plural.pick(root.strings[key], root.language, count) : undefined;
        if (typeof value !== "string" || value === "")
            value = Plural.category("en", count) === "one" ? String(singular) : key;
        return Plural.fill(value, [root.formatNumber(count)].concat(args));
    }

    // The form for count of a plural catalog entry ({"one": …, "other": …})
    // by the rules of code (default: the interface language), or the entry
    // itself when it is a string. For the compat host's I18n and
    // Translations, which read Omarchy-style keyed catalogs.
    function pick(entry, count, code): var {
        return Plural.pick(entry, code || root.language, count);
    }

    // A no-op that marks English kept in QML data (a model's labels) for
    // tools/i18n.py; translate it where it is shown, with tr().
    function mark(text: string): string {
        return text;
    }

    function formatNumber(value, decimals): string {
        return Plural.formatNumber(value, decimals, root.decimal, root.zeroDigit);
    }

    // Qt.formatDateTime() with the interface language's day and month names.
    function formatDate(date, format: string): string {
        return date ? date.toLocaleString(root.locale, format) : "";
    }

    // The menu catalog's fields for a menu id ({label, title, description}),
    // or an empty object.
    function menuEntry(id: string): var {
        const value = root.language !== "en" ? root.menuStrings[id] : undefined;
        return value && typeof value === "object" ? value : ({});
    }

    function _parse(raw: string): var {
        try {
            const parsed = JSON.parse(raw || "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
        } catch (e) {
            console.warn("haseen: I18n: a catalog is not valid JSON:", e.message);
            return ({});
        }
    }

    // A FileView created after the shell's load (the singleton's first use
    // in a late plugin or a test) does not read its file by itself.
    Component.onCompleted: {
        for (const view of [registryView, languageView, stringsView, menuView])
            if (!view.loaded && view.path !== "")
                view.reload();
    }

    // Small local files read synchronously, so the first frame already has
    // the language rather than flashing English.
    FileView {
        id: registryView

        path: root.dir + "/locales.json"
        blockLoading: true
        printErrors: false
        onLoaded: root.registry = root._parse(text())
    }

    // `haseen shell run` creates ~/.config/haseen before qs starts: a watch
    // needs the directory to exist.
    FileView {
        id: languageView

        path: root.languageFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.requested = text().trim()
        onLoadFailed: root.requested = ""
    }

    FileView {
        id: stringsView

        path: root.language !== "en" ? root.dir + "/" + root.language + "/shell.json" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.strings = root._parse(text())
        onLoadFailed: root.strings = ({})
        onPathChanged: if (path === "")
            root.strings = ({})
    }

    FileView {
        id: menuView

        path: root.language !== "en" ? root.dir + "/" + root.language + "/menu.json" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.menuStrings = root._parse(text())
        onLoadFailed: root.menuStrings = ({})
        onPathChanged: if (path === "")
            root.menuStrings = ({})
    }
}
