pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shell tokens (architecture 7) from current/theme/shell.json, rendered by
// `haseen theme set`. Every key has a built-in fallback, so a missing, partial
// or broken file never breaks the bar. Values of the wrong type fall back too.
Singleton {
    id: root

    property var tokens: ({})

    readonly property var fallback: ({
            mode: "dark",
            background: "#16161d",
            surface: "#1f1f28",
            surfaceAlt: "#2a2a37",
            foreground: "#dcd7ba",
            muted: "#727169",
            accent: "#7e9cd8",
            accentFg: "#16161d",
            urgent: "#e46876",
            warning: "#e6c384",
            success: "#98bb6c",
            border: "#2a2a37",
            selection: "#2d4f67",
            fontFamily: "sans-serif",
            fontMono: "monospace",
            fontSize: 13,
            radius: 6,
            gap: 6,
            borderWidth: 1
        })

    readonly property var _numeric: ["fontSize", "radius", "gap", "borderWidth"]
    readonly property var _text: ["mode", "fontFamily", "fontMono"]

    function token(key: string): var {
        const v = tokens[key];
        if (_numeric.indexOf(key) >= 0)
            return (typeof v === "number" && isFinite(v) && v >= 0) ? v : fallback[key];
        if (_text.indexOf(key) >= 0)
            return (typeof v === "string" && v.length > 0) ? v : fallback[key];
        return (typeof v === "string" && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)) ? v : fallback[key];
    }

    readonly property string mode: token("mode")
    readonly property color background: token("background")
    readonly property color surface: token("surface")
    readonly property color surfaceAlt: token("surfaceAlt")
    readonly property color foreground: token("foreground")
    readonly property color muted: token("muted")
    readonly property color accent: token("accent")
    readonly property color accentFg: token("accentFg")
    readonly property color urgent: token("urgent")
    readonly property color warning: token("warning")
    readonly property color success: token("success")
    readonly property color border: token("border")
    readonly property color selection: token("selection")
    readonly property string fontFamily: token("fontFamily")
    readonly property string fontMono: token("fontMono")
    readonly property int fontSize: token("fontSize")
    readonly property int radius: token("radius")
    readonly property int gap: token("gap")
    readonly property int borderWidth: token("borderWidth")

    // Normal-state text and glyphs of bar widgets. It is the foreground, or
    // while the bar is transparent the colour FrameTextColor.qml picks for the
    // wallpaper under the bar (plan 015). Panels keep using foreground.
    property color barForeground: foreground

    FileView {
        path: Paths.themeTokens
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.tokens = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
            } catch (e) {
                console.warn("haseen: theme tokens unreadable, using fallbacks:", e.message);
                root.tokens = {};
            }
        }
        onLoadFailed: root.tokens = {}
    }
}
