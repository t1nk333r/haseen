pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// default/shell.json deep-merged with ~/.config/haseen/shell.json, both
// watched. Objects merge key by key; arrays and scalars from the user file
// replace the default (so a user `bar.right` is the whole section).
Singleton {
    id: root

    property var defaults: ({})
    property var user: ({})
    readonly property var merged: deepMerge(defaults, user)

    readonly property var bar: _object(merged.bar)
    readonly property string barPosition: bar.position === "bottom" ? "bottom" : "top"
    readonly property int barHeight: (typeof bar.height === "number" && bar.height >= 16) ? bar.height : 28
    readonly property var services: _ids(merged.services)

    function _object(v: var): var {
        return (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
    }

    function _ids(v: var): var {
        return Array.isArray(v) ? v.filter(x => typeof x === "string") : [];
    }

    function deepMerge(base: var, over: var): var {
        const out = {};
        for (const k in base)
            out[k] = base[k];
        for (const k in over) {
            const a = out[k], b = over[k];
            const bothObjects = a && b && typeof a === "object" && typeof b === "object" && !Array.isArray(a) && !Array.isArray(b);
            out[k] = bothObjects ? deepMerge(a, b) : b;
        }
        return out;
    }

    function section(name: string): var {
        return _ids(bar[name]);
    }

    function pluginEntry(id: string): var {
        return _object(_object(merged.plugins)[id]);
    }

    function isEnabled(id: string): bool {
        return pluginEntry(id).enabled !== false;
    }

    function isListed(id: string): bool {
        return section("left").indexOf(id) >= 0 || section("center").indexOf(id) >= 0 || section("right").indexOf(id) >= 0 || services.indexOf(id) >= 0;
    }

    function _parse(text: string, label: string, previous: var): var {
        // An editor truncating before it writes shows up as an empty read.
        if (text.trim() === "")
            return previous;
        try {
            return _object(JSON.parse(text));
        } catch (e) {
            // Keep the last good value: an editor mid-save must not blank the bar.
            console.warn("haseen:", label, "is not valid JSON, keeping the previous config:", e.message);
            return previous;
        }
    }

    FileView {
        path: Paths.defaultShellConfig
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.defaults = root._parse(text(), path, root.defaults)
        onLoadFailed: error => console.warn("haseen: cannot read", path, "-", FileViewError.toString(error))
    }

    FileView {
        path: Paths.userShellConfig
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.user = root._parse(text(), path, root.user)
        onLoadFailed: root.user = {}
    }
}
