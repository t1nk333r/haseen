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
// (MIT, Copyright (c) David Heinemeier Hansson). Omarchy reads them from
// theme/shell.toml and hyprctl; here the base size is Theme.fontSize, the
// corner radius Theme.radius, the edge gap Theme.gap and the horizontal bar
// size Config.barHeight. Nothing is polled.
Singleton {
    id: root

    readonly property int cornerRadius: Theme.radius
    readonly property int gapsOut: Theme.gap
    readonly property bool reduceMotion: Theme.tokens.reduceMotion === true

    // ------------------------------------------------------------ state tokens
    readonly property int normalBorderWidth: Math.max(0, Math.round(styleNum("normal-border-width", Theme.borderWidth)))
    readonly property int hoverBorderWidth: Math.max(0, Math.round(styleNum("hover-cursor-border-width", normalBorderWidth)))
    readonly property int selectedBorderWidth: Math.max(0, Math.round(styleNum("selected-border-width", 0)))
    readonly property int focusBorderWidth: Math.max(0, Math.round(styleNum("focus-border-width", hoverBorderWidth)))

    readonly property real normalFillAlpha: styleAlpha("normal-fill-alpha", 0.04)
    readonly property real hoverFillAlpha: styleAlpha("hover-cursor-fill-alpha", 0.08)
    readonly property real selectedFillAlpha: styleAlpha("selected-fill-alpha", 0.18)
    readonly property real pressedFillAlpha: styleAlpha("pressed-fill-alpha", 0.22)
    readonly property real focusFillAlpha: styleAlpha("focus-fill-alpha", hoverFillAlpha)
    readonly property real selectionFillAlpha: styleAlpha("selection-fill-alpha", 0.35)
    readonly property real normalBorderAlpha: styleAlpha("normal-border-alpha", 0.4)
    readonly property real hoverBorderAlpha: styleAlpha("hover-cursor-border-alpha", 0.25)
    readonly property real selectedBorderAlpha: styleAlpha("selected-border-alpha", 1.0)
    readonly property real focusBorderAlpha: styleAlpha("focus-border-alpha", hoverBorderAlpha)
    readonly property var styleOverrides: Theme.tokens.controls && typeof Theme.tokens.controls === "object" && !Array.isArray(Theme.tokens.controls) ? Theme.tokens.controls : ({})
    readonly property string normalColorToken: styleString("normal-color", "foreground")
    readonly property string hoverColorToken: styleString("hover-cursor-color", "foreground")
    readonly property string selectedColorToken: styleString("selected-color", "foreground")
    readonly property string pressedColorToken: styleString("pressed-color", hoverColorToken)
    readonly property string focusColorToken: styleString("focus-color", hoverColorToken)
    readonly property string selectionColorToken: styleString("selection-color", "foreground")

    function styleRawNum(key) {
      var v = styleOverrides[key]
      var n = Number(v)
      return isFinite(n) ? n : null
    }

    function styleNum(key, fallback) {
      var n = styleRawNum(key)
      return n === null ? fallback : n
    }

    function styleAlpha(key, fallback) {
      return Util.clampAlpha(styleNum(key, fallback))
    }

    function styleString(key, fallback) {
      var v = styleOverrides[key]
      if (typeof v !== "string") return fallback
      v = v.replace(/^\s+|\s+$/g, "")
      return v.length > 0 ? v : fallback
    }





    function colorFromHex(value, fallback) {
      var s = String(value || "").replace(/^\s+|\s+$/g, "")
      var shortHex = s.match(/^#([0-9A-Fa-f]{3})$/)
      if (shortHex) {
        var sh = shortHex[1]
        return Qt.rgba(
          parseInt(sh.charAt(0) + sh.charAt(0), 16) / 255,
          parseInt(sh.charAt(1) + sh.charAt(1), 16) / 255,
          parseInt(sh.charAt(2) + sh.charAt(2), 16) / 255,
          1)
      }
      var hex = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/)
      if (!hex) return fallback
      var h = hex[1]
      return Qt.rgba(
        parseInt(h.substr(0, 2), 16) / 255,
        parseInt(h.substr(2, 2), 16) / 255,
        parseInt(h.substr(4, 2), 16) / 255,
        hex[2] ? parseInt(hex[2], 16) / 255 : 1)
    }

    function resolveStateColor(token, foreground, accent, urgent, fallback) {
      var fb = fallback || foreground || Color.foreground
      var s = String(token || "").replace(/^\s+|\s+$/g, "")
      var role = s.toLowerCase()
      if (role === "foreground" || role === "text") return foreground || Color.foreground
      if (role === "accent") return accent || Color.accent
      if (role === "urgent") return urgent || Color.urgent
      if (role === "background") return Color.background
      if (role === "transparent") return Qt.rgba(0, 0, 0, 0)
      return colorFromHex(s, fb)
    }

    function normalStateColor(foreground, accent, urgent) {
      return resolveStateColor(normalColorToken, foreground, accent, urgent, foreground || Color.foreground)
    }

    function hoverStateColor(foreground, accent, urgent) {
      return resolveStateColor(hoverColorToken, foreground, accent, urgent, foreground || Color.foreground)
    }

    function selectedStateColor(foreground, accent, urgent) {
      return resolveStateColor(selectedColorToken, foreground, accent, urgent, foreground || Color.foreground)
    }

    function pressedStateColor(foreground, accent, urgent) {
      return resolveStateColor(pressedColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent))
    }

    function focusStateColor(foreground, accent, urgent) {
      var role = String(focusColorToken || "").replace(/^\s+|\s+$/g, "").toLowerCase()
      if (role === "hover" || role === "hover-cursor" || role === "inherit")
        return hoverStateColor(foreground, accent, urgent)
      return resolveStateColor(focusColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent))
    }

    function selectionStateColor(foreground, accent, urgent) {
      return resolveStateColor(selectionColorToken, foreground, accent, urgent, foreground || Color.foreground)
    }

    function normalFillFor(foreground, accent, urgent) { return Util.alpha(normalStateColor(foreground, accent, urgent), normalFillAlpha) }
    function hoverFillFor(foreground, accent, urgent) { return Util.alpha(hoverStateColor(foreground, accent, urgent), hoverFillAlpha) }
    function selectedFillFor(foreground, accent, urgent) { return Util.alpha(selectedStateColor(foreground, accent, urgent), selectedFillAlpha) }
    function pressedFillFor(foreground, accent, urgent) { return Util.alpha(pressedStateColor(foreground, accent, urgent), pressedFillAlpha) }
    function focusFillFor(foreground, accent, urgent) { return Util.alpha(focusStateColor(foreground, accent, urgent), focusFillAlpha) }
    function selectionFillFor(foreground, accent, urgent) { return Util.alpha(selectionStateColor(foreground, accent, urgent), selectionFillAlpha) }

    function normalBorderFor(foreground, accent, urgent) { return Util.alpha(normalStateColor(foreground, accent, urgent), normalBorderAlpha) }
    function hoverBorderFor(foreground, accent, urgent) { return Util.alpha(hoverStateColor(foreground, accent, urgent), hoverBorderAlpha) }
    function selectedBorderFor(foreground, accent, urgent) { return Util.alpha(selectedStateColor(foreground, accent, urgent), selectedBorderAlpha) }
    function focusBorderFor(foreground, accent, urgent) { return Util.alpha(focusStateColor(foreground, accent, urgent), focusBorderAlpha) }

    // Composite helpers for the focus > hover > normal priority chain used by
    // every form control surface (TextField, NumberField, Dropdown, Toggle,
    // etc.). Saves callers from re-writing the three-line ternary ladder for
    // fill / border / border-width on every Rectangle background.
    function controlFill(focused, hot, foreground, accent) {
      if (focused) return focusFillFor(foreground, accent)
      if (hot) return hoverFillFor(foreground, accent)
      return normalFillFor(foreground, accent)
    }

    function controlBorder(focused, hot, foreground, accent) {
      if (focused) return focusBorderFor(foreground, accent)
      if (hot) return hoverBorderFor(foreground, accent)
      return normalBorderFor(foreground, accent)
    }

    function controlBorderWidth(focused, hot) {
      if (focused) return focusBorderWidth
      if (hot) return hoverBorderWidth
      return normalBorderWidth
    }

    readonly property color normalFill: normalFillFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color hoverFill: hoverFillFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color selectedFill: selectedFillFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color pressedFill: pressedFillFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color focusFillColor: focusFillFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color normalBorderColor: normalBorderFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color hoverBorderColor: hoverBorderFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color selectedBorderColor: selectedBorderFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color focusBorderColor: focusBorderFor(Theme.foreground, Theme.accent, Theme.urgent)
    readonly property color selectedAccentFill: Util.alpha(Theme.accent, selectedFillAlpha)
    readonly property color selectionFill: selectionFillFor(Theme.foreground, Theme.accent, Theme.urgent)

    // ------------------------------------------------------------ typography
    readonly property string fontFamily: Theme.fontFamily
    readonly property string resolvedFontFamily: Theme.fontFamily
    readonly property string menuFontFamily: Theme.fontFamily
    readonly property int fontBaseSize: Math.max(1, Theme.fontSize)
    readonly property real fontScale: Math.max(1 / 12, fontBaseSize / 12)

    function fontPx(mult: real): int {
        return Math.max(1, Math.round(fontBaseSize * mult));
    }

    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property string resolvedFamily: root.resolvedFontFamily
        readonly property string menuFamily: root.menuFontFamily
        readonly property int baseSize: root.fontBaseSize
        readonly property int caption: root.fontPx(0.833)
        readonly property int bodySmall: root.fontPx(0.917)
        readonly property int body: root.fontPx(1.0)
        readonly property int subtitle: root.fontPx(1.083)
        readonly property int title: root.fontPx(1.167)
        readonly property int heading: root.fontPx(1.333)
        readonly property int display: root.fontPx(2.0)
        readonly property int displayLarge: root.fontPx(2.333)
        readonly property int iconSmall: bodySmall
        readonly property int icon: title
        readonly property int iconLarge: root.fontPx(1.5)
    }

    // ------------------------------------------------------------ spacing
    readonly property real effectiveSpacingScale: fontScale

    function spaceReal(px: var): real {
        const n = Number(px);
        if (!isFinite(n) || n <= 0)
            return 0;
        return n * effectiveSpacingScale;
    }

    function space(px: var): int {
        const n = spaceReal(px);
        if (n <= 0)
            return 0;
        return Math.max(1, Math.round(n));
    }

    readonly property QtObject spacing: QtObject {
        readonly property real scale: root.effectiveSpacingScale
        readonly property int hairline: root.space(1)
        readonly property int xxs: root.space(2)
        readonly property int xs: root.space(3)
        readonly property int sm: root.space(4)
        readonly property int md: root.space(6)
        readonly property int lg: root.space(8)
        readonly property int xl: root.space(10)
        readonly property int xxl: root.space(12)
        readonly property int xxxl: root.space(14)
        readonly property int huge: root.space(18)
        readonly property int controlGap: root.space(8)
        readonly property int controlPaddingX: root.space(10)
        readonly property int controlPaddingY: root.space(6)
        readonly property int inputPaddingY: root.space(7)
        readonly property int controlHeight: root.space(28)
        readonly property int popupRowHeight: root.space(28)
        readonly property int dropdownWidth: root.space(240)
        readonly property int searchableDropdownWidth: root.space(260)
        readonly property int numberFieldWidth: root.space(120)
        readonly property int searchablePopupMinHeight: root.space(220)
        readonly property int rowGap: root.space(8)
        readonly property int rowPaddingX: root.space(12)
        readonly property int labelGap: root.space(4)
        readonly property int panelGap: root.space(14)
        readonly property int panelPadding: root.space(18)
        readonly property int popupPadding: root.space(14)
    }

    // ------------------------------------------------------------ bar
    function barToken(fallback: real): int {
        return Math.max(1, Math.round(fallback * fontScale));
    }

    readonly property QtObject bar: QtObject {
        readonly property int sizeHorizontal: Config.barHeight
        readonly property int sizeVertical: Config.barHeight
        readonly property int iconSlot: root.barToken(27)
        readonly property int iconCanvas: root.barToken(16)
        readonly property int iconFont: root.barToken(13)
        readonly property int statusSlot: root.barToken(21)
    }

    function duration(ms: real): real {
        return reduceMotion ? 0 : ms;
    }
}
