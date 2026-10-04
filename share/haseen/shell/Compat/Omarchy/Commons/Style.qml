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
    readonly property bool reduceMotion: false

    // ------------------------------------------------------------ state tokens
    readonly property int normalBorderWidth: Theme.borderWidth
    readonly property int hoverBorderWidth: Theme.borderWidth
    readonly property int selectedBorderWidth: 0
    readonly property int focusBorderWidth: Theme.borderWidth

    readonly property real normalFillAlpha: 0.04
    readonly property real hoverFillAlpha: 0.08
    readonly property real selectedFillAlpha: 0.18
    readonly property real pressedFillAlpha: 0.22
    readonly property real focusFillAlpha: hoverFillAlpha
    readonly property real selectionFillAlpha: 0.35
    readonly property real normalBorderAlpha: 0.4
    readonly property real hoverBorderAlpha: 0.25
    readonly property real selectedBorderAlpha: 1.0
    readonly property real focusBorderAlpha: hoverBorderAlpha

    function _alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property color normalFill: _alpha(Theme.foreground, normalFillAlpha)
    readonly property color hoverFill: _alpha(Theme.foreground, hoverFillAlpha)
    readonly property color selectedFill: _alpha(Theme.foreground, selectedFillAlpha)
    readonly property color pressedFill: _alpha(Theme.foreground, pressedFillAlpha)
    readonly property color focusFillColor: _alpha(Theme.foreground, focusFillAlpha)
    readonly property color normalBorderColor: _alpha(Theme.foreground, normalBorderAlpha)
    readonly property color hoverBorderColor: _alpha(Theme.foreground, hoverBorderAlpha)
    readonly property color selectedBorderColor: _alpha(Theme.foreground, selectedBorderAlpha)
    readonly property color focusBorderColor: _alpha(Theme.foreground, focusBorderAlpha)
    readonly property color selectedAccentFill: _alpha(Theme.accent, selectedFillAlpha)
    readonly property color selectionFill: _alpha(Theme.foreground, selectionFillAlpha)

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
