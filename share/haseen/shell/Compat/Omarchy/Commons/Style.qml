pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen

// qs.Commons.Style for Omarchy plugins (architecture 5.4), backed by the
// haseen Theme tokens and Config.barHeight.
//
// Token names, defaults and the rem-style scaling (space(), spaceReal(),
// font.* multipliers of the base size, bar.* scaled with the font) are
// adapted from Omarchy's shell/Commons/Style.qml
// (MIT, Copyright (c) David Heinemeier Hansson). Since plan 115 haseen's own
// Theme carries the same vocabulary and values (its shellValues are what
// Omarchy's shell.toml.tpl renders, its radius and gapsOut follow Hyprland as
// Omarchy's do), so every value here is Theme's: one source of truth for
// native panels and Omarchy plugins alike. The horizontal and vertical bar
// sizes stay the host bar's (Config.barHeight), which a plugin sits in.
Singleton {
    id: root

    readonly property int cornerRadius: Theme.radius
    readonly property int gapsOut: Theme.gapsOut
    readonly property bool reduceMotion: Theme.reduceMotion

    // ------------------------------------------------------------ state tokens
    // Omarchy's flat [controls] keys ("normal-border-width", …), as its
    // Border.qml reads them.
    readonly property var styleOverrides: {
        const out = {};
        const v = Theme.shellValues;
        for (const k in v) {
            if (k.indexOf("controls.") === 0)
                out[k.substr(9)] = v[k];
        }
        return out;
    }
    readonly property string normalColorToken: Theme.normalColorToken
    readonly property string hoverColorToken: Theme.hoverColorToken
    readonly property string selectedColorToken: Theme.selectedColorToken
    readonly property string pressedColorToken: Theme.pressedColorToken
    readonly property string focusColorToken: Theme.focusColorToken
    readonly property string selectionColorToken: Theme.selectionColorToken

    readonly property int normalBorderWidth: Theme.normalBorderWidth
    readonly property int hoverBorderWidth: Theme.hoverBorderWidth
    readonly property int selectedBorderWidth: Theme.selectedBorderWidth
    readonly property int focusBorderWidth: Theme.focusBorderWidth

    readonly property real normalFillAlpha: Theme.normalFillAlpha
    readonly property real hoverFillAlpha: Theme.hoverFillAlpha
    readonly property real selectedFillAlpha: Theme.selectedFillAlpha
    readonly property real pressedFillAlpha: Theme.pressedFillAlpha
    readonly property real focusFillAlpha: Theme.focusFillAlpha
    readonly property real selectionFillAlpha: Theme.selectionFillAlpha
    readonly property real normalBorderAlpha: Theme.normalBorderAlpha
    readonly property real hoverBorderAlpha: Theme.hoverBorderAlpha
    readonly property real selectedBorderAlpha: Theme.selectedBorderAlpha
    readonly property real focusBorderAlpha: Theme.focusBorderAlpha

    function styleRawNum(key) {
        var n = Number(styleOverrides[key]);
        return isFinite(n) ? n : null;
    }

    function styleNum(key, fallback) {
        var n = styleRawNum(key);
        return n === null ? fallback : n;
    }

    function styleAlpha(key, fallback) {
        return Util.clampAlpha(styleNum(key, fallback));
    }

    function styleString(key, fallback) {
        var v = styleOverrides[key];
        if (typeof v !== "string")
            return fallback;
        v = v.replace(/^\s+|\s+$/g, "");
        return v.length > 0 ? v : fallback;
    }

    function colorFromHex(value, fallback) {
        var s = String(value || "").replace(/^\s+|\s+$/g, "");
        var shortHex = s.match(/^#([0-9A-Fa-f]{3})$/);
        if (shortHex) {
            var sh = shortHex[1];
            return Qt.rgba(parseInt(sh.charAt(0) + sh.charAt(0), 16) / 255, parseInt(sh.charAt(1) + sh.charAt(1), 16) / 255, parseInt(sh.charAt(2) + sh.charAt(2), 16) / 255, 1);
        }
        var hex = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/);
        if (!hex)
            return fallback;
        var h = hex[1];
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255, hex[2] ? parseInt(hex[2], 16) / 255 : 1);
    }

    function resolveStateColor(token, foreground, accent, urgent, fallback) {
        return Theme.resolveStateColor(token, foreground, accent, urgent, fallback);
    }
    function normalStateColor(foreground, accent, urgent) {
        return Theme.normalStateColor(foreground, accent, urgent);
    }
    function hoverStateColor(foreground, accent, urgent) {
        return Theme.hoverStateColor(foreground, accent, urgent);
    }
    function selectedStateColor(foreground, accent, urgent) {
        return Theme.selectedStateColor(foreground, accent, urgent);
    }
    function pressedStateColor(foreground, accent, urgent) {
        return Theme.pressedStateColor(foreground, accent, urgent);
    }
    function focusStateColor(foreground, accent, urgent) {
        return Theme.focusStateColor(foreground, accent, urgent);
    }
    function selectionStateColor(foreground, accent, urgent) {
        return Theme.selectionStateColor(foreground, accent, urgent);
    }

    function normalFillFor(foreground, accent, urgent) {
        return Theme.normalFillFor(foreground, accent, urgent);
    }
    function hoverFillFor(foreground, accent, urgent) {
        return Theme.hoverFillFor(foreground, accent, urgent);
    }
    function selectedFillFor(foreground, accent, urgent) {
        return Theme.selectedFillFor(foreground, accent, urgent);
    }
    function pressedFillFor(foreground, accent, urgent) {
        return Theme.pressedFillFor(foreground, accent, urgent);
    }
    function focusFillFor(foreground, accent, urgent) {
        return Theme.focusFillFor(foreground, accent, urgent);
    }
    function selectionFillFor(foreground, accent, urgent) {
        return Theme.selectionFillFor(foreground, accent, urgent);
    }
    function normalBorderFor(foreground, accent, urgent) {
        return Theme.normalBorderFor(foreground, accent, urgent);
    }
    function hoverBorderFor(foreground, accent, urgent) {
        return Theme.hoverBorderFor(foreground, accent, urgent);
    }
    function selectedBorderFor(foreground, accent, urgent) {
        return Theme.selectedBorderFor(foreground, accent, urgent);
    }
    function focusBorderFor(foreground, accent, urgent) {
        return Theme.focusBorderFor(foreground, accent, urgent);
    }

    // Composite helpers for the focus > hover > normal priority chain used by
    // every form control surface (TextField, NumberField, Dropdown, Toggle,
    // etc.).
    function controlFill(focused, hot, foreground, accent) {
        return Theme.controlFill(focused, hot, foreground, accent);
    }
    function controlBorder(focused, hot, foreground, accent) {
        return Theme.controlBorder(focused, hot, foreground, accent);
    }
    function controlBorderWidth(focused, hot) {
        return Theme.controlBorderWidth(focused, hot);
    }

    readonly property color normalFill: Theme.normalFill
    readonly property color hoverFill: Theme.hoverFill
    readonly property color selectedFill: Theme.selectedFill
    readonly property color pressedFill: Theme.pressedFill
    readonly property color focusFillColor: Theme.focusFillColor
    readonly property color normalBorderColor: Theme.normalBorderColor
    readonly property color hoverBorderColor: Theme.hoverBorderColor
    readonly property color selectedBorderColor: Theme.selectedBorderColor
    readonly property color focusBorderColor: Theme.focusBorderColor
    readonly property color selectedAccentFill: Theme.selectedAccentFill
    readonly property color selectionFill: Theme.selectionFill

    // ------------------------------------------------------------ typography
    // Omarchy's family is the system monospace (a Nerd Font on Omarchy
    // installs), and its plugins draw Nerd Font codepoints (e.g. U+EED3) as
    // plain text in it. Theme.fontFamily is the user's monospace too
    // (`haseen font set`, plan 115), the one haseen's own panels use.
    readonly property string fontFamily: Theme.font.family
    readonly property string resolvedFontFamily: Theme.font.resolvedFamily
    readonly property string menuFontFamily: Theme.font.menuFamily
    readonly property int fontBaseSize: Theme.fontBaseSize
    readonly property real fontScale: Theme.fontScale

    function fontPx(mult: real): int {
        return Theme.fontPx(mult);
    }

    readonly property QtObject font: Theme.font

    // ------------------------------------------------------------ spacing
    readonly property real effectiveSpacingScale: Theme.effectiveSpacingScale

    function spaceReal(px: var): real {
        return Theme.spaceReal(px);
    }

    function space(px: var): int {
        return Theme.space(px);
    }

    readonly property QtObject spacing: Theme.spacing

    // ------------------------------------------------------------ bar
    function barToken(fallback: real): int {
        return Math.max(1, Math.round(fallback * fontScale));
    }

    readonly property QtObject bar: QtObject {
        readonly property int sizeHorizontal: Config.barHeight
        readonly property int sizeVertical: Config.barHeight
        readonly property int iconSlot: Theme.barMetrics.iconSlot
        readonly property int iconCanvas: Theme.barMetrics.iconCanvas
        readonly property int iconFont: Theme.barMetrics.iconFont
        readonly property int iconSize: Theme.barMetrics.iconSize
        readonly property int statusSlot: Theme.barMetrics.statusSlot
    }

    function duration(ms: real): real {
        return Theme.duration(ms);
    }
}
