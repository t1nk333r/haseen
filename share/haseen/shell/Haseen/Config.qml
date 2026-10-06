pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// default/shell.json deep-merged with ~/.config/haseen/shell.json, both
// watched. Objects merge key by key; arrays and scalars from the user file
// replace the default (so a user `bar.right` is the whole section).
//
// `runtime` sits on top: a setting changed from the shell (bar double-click,
// tray pin, the `bar` IPC target) applies from there at once while
// `haseen bar …` persists it to the user file. The next load of that file
// clears the layer, so the file stays the truth (plan 015).
Singleton {
    id: root

    property var defaults: ({})
    property var user: ({})
    property var runtime: ({})
    readonly property var fileMerged: deepMerge(defaults, user)
    readonly property var merged: deepMerge(fileMerged, runtime)

    readonly property var bar: _object(merged.bar)
    readonly property string barPosition: ["top", "bottom", "left", "right"].indexOf(bar.position) >= 0 ? bar.position : "top"
    readonly property bool barVertical: barPosition === "left" || barPosition === "right"
    readonly property int barHeight: (typeof bar.height === "number" && bar.height >= 16) ? bar.height : 28
    // Size across the bar. A vertical bar needs room for a short label.
    readonly property int barThickness: barVertical ? Math.max(barHeight, Theme.fontSize * 3) : barHeight
    readonly property bool barTransparent: bar.transparent === true
    // Overflow panel (Bar.qml): ids always in it, and ids never moved there
    // automatically.
    readonly property var barOverflow: _ids(bar.overflow)
    readonly property var barPinned: _ids(bar.pinned)
    readonly property var frame: _object(merged.frame)
    readonly property bool frameEnabled: frame.enabled !== false
    readonly property int frameThickness: _int(frame.thickness, 1, 64, 6)
    // Inner corner radius: twice the theme radius unless frame.radius is set.
    readonly property int frameRadius: _int(frame.radius, 0, 64, Theme.radius * 2)
    readonly property var services: _ids(merged.services)

    function _int(v: var, min: int, max: int, fallback: int): int {
        return (typeof v === "number" && v >= min && v <= max) ? Math.round(v) : fallback;
    }

    // The value at path (["bar", "transparent"]) in the files alone.
    function fileValue(path: var): var {
        let v = fileMerged;
        for (const k of path)
            v = (v && typeof v === "object") ? v[k] : undefined;
        return v;
    }

    function setRuntime(path: var, value: var): void {
        let over = value;
        for (let i = path.length - 1; i >= 0; i--) {
            const o = {};
            o[path[i]] = over;
            over = o;
        }
        runtime = deepMerge(runtime, over);
    }

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
        onLoaded: {
            root.user = root._parse(text(), path, root.user);
            root.runtime = {};
        }
        onLoadFailed: root.user = {}
    }
}
