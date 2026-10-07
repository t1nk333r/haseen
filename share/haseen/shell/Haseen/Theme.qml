pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Ink.js" as Ink

// Shell tokens (architecture 7) from current/theme/shell.json, rendered by
// `haseen theme set`. Every key has a built-in fallback, so a missing, partial
// or broken file never breaks the bar. Values of the wrong type fall back too.
// The fallbacks are the default theme's rendered shell.json (`haseen`, plan
// 066; its palette is HANCORE's Greek Noir, MIT, Copyright (c) 2026 HANCORE,
// see NOTICE.md; tests/test-theme-haseen.sh keeps them in step), so a missing
// file still looks like haseen.
Singleton {
    id: root

    property var tokens: ({})

    readonly property var fallback: ({
            mode: "dark",
            background: "#171717",
            surface: "#222222",
            surfaceAlt: "#2d2d2d",
            foreground: "#CCD0CF",
            muted: "#525252",
            accent: "#F25623",
            accentFg: "#171717",
            urgent: "#aeab94",
            warning: "#757864",
            success: "#F25623",
            border: "#3b3c3c",
            selection: "#864313",
            fontFamily: "Inter",
            fontMono: "JetBrainsMono Nerd Font",
            fontSize: 11,
            radius: 6,
            gap: 6,
            borderWidth: 1,
            windowRadius: 4
        })

    readonly property var _numeric: ["fontSize", "radius", "gap", "borderWidth", "windowRadius"]
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
    // Hyprland's window rounding under this theme (decoration.rounding), for
    // surfaces that round like the windows: the menu, as Omarchy's does.
    readonly property int windowRadius: token("windowRadius")

    // Normal-state text and glyphs of bar widgets. It is the foreground, or
    // while the bar is transparent the colour FrameTextColor.qml picks for the
    // wallpaper under the bar (plan 015). Panels keep using foreground.
    property color barForeground: foreground

    // Secondary text on an opaque `bg` (descriptions, subtitles): the
    // foreground at Omarchy's description alpha, raised until it reads at 3:1
    // on bg (Ink.js). Never muted: muted on selection drops below 1.5:1 in
    // most stock themes. A translucent row tint goes through over() first.
    function subtle(bg: color): color {
        return Qt.alpha(foreground, Ink.readableAlpha(foreground, bg, Ink.SUBTLE, Ink.MIN_RATIO));
    }

    // fg at alpha painted over an opaque bg, as one opaque colour.
    function over(fg: color, alpha: real, bg: color): color {
        const c = Ink.over(fg, alpha, bg);
        return Qt.rgba(c.r, c.g, c.b, 1);
    }

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
