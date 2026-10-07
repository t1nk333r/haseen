pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen

// qs.Common.Theme for DankMaterialShell plugins (architecture 5.4): the
// Material token names DMS bar widgets read, mapped onto the haseen Theme.
//
// Token names, the spacing/size defaults and the barIconSize()/barTextSize()
// formulas follow DankMaterialShell's quickshell/Common/Theme.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC). No wallpaper-derived palette:
// every colour is a haseen token (primary = accent, surfaceText =
// foreground, surfaceVariantText = muted, error = urgent, …).
Singleton {
    id: root

    readonly property bool isLightMode: Haseen.Theme.mode === "light"

    // ------------------------------------------------------------ colours
    readonly property color primary: Haseen.Theme.accent
    readonly property color primaryText: Haseen.Theme.accentFg
    readonly property color onPrimary: Haseen.Theme.accentFg
    readonly property color primaryContainer: Haseen.Theme.selection
    // Accent state layers and the opaque card surface, derived as DMS does
    // (haseen draws no translucent popups, so readableSurface is opaque).
    readonly property color primaryHover: withAlpha(primary, 0.12)
    readonly property color primaryPressed: withAlpha(primary, 0.16)
    readonly property color primarySelected: withAlpha(primary, 0.3)
    readonly property color readableSurface: Haseen.Theme.background
    readonly property color inverseSurface: Haseen.Theme.foreground
    readonly property color inverseOnSurface: Haseen.Theme.background
    readonly property color secondary: Haseen.Theme.accent
    readonly property color secondaryContainer: Haseen.Theme.selection
    readonly property color onSecondaryContainer: Haseen.Theme.foreground
    readonly property color surface: Haseen.Theme.background
    readonly property color surfaceContainer: Haseen.Theme.surface
    readonly property color surfaceContainerHigh: Haseen.Theme.surfaceAlt
    readonly property color surfaceContainerHighest: Haseen.Theme.surfaceAlt
    readonly property color surfaceVariant: Haseen.Theme.surfaceAlt
    readonly property color hostSurface: Haseen.Theme.background
    readonly property color cardSurface: Haseen.Theme.surface
    readonly property color chipSurface: Haseen.Theme.surfaceAlt
    readonly property color chipSurfaceNested: Haseen.Theme.surfaceAlt
    readonly property color surfaceText: Haseen.Theme.foreground
    readonly property color onSurface: Haseen.Theme.foreground
    readonly property color surfaceVariantText: Haseen.Theme.muted
    readonly property color onSurfaceVariant: Haseen.Theme.muted
    readonly property color outline: Haseen.Theme.border
    readonly property color outlineStrong: Haseen.Theme.border
    readonly property color outlineVariant: Haseen.Theme.border
    readonly property color error: Haseen.Theme.urgent
    readonly property color onError: Haseen.Theme.background
    readonly property color warning: Haseen.Theme.warning
    readonly property color success: Haseen.Theme.success
    readonly property color widgetIconColor: Haseen.Theme.foreground
    readonly property color widgetTextColor: Haseen.Theme.foreground
    // A card inside a popout, error-tinted hover, secondary text: DMS
    // derives them from the tokens above the same way.
    readonly property color nestedSurface: Haseen.Theme.surfaceAlt
    readonly property color errorHover: withAlpha(error, 0.12)
    readonly property color surfaceTextMedium: withAlpha(surfaceText, 0.7)

    function withAlpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // ------------------------------------------------------------ type
    readonly property string fontFamily: Haseen.Theme.fontFamily
    readonly property string monoFontFamily: Haseen.Theme.fontMono
    // DMS sizes are multiples of a 14 px base; haseen's base is Theme.fontSize.
    readonly property real fontScale: Haseen.Theme.fontSize / 14
    readonly property real fontSizeSmall: Math.round(fontScale * 12)
    readonly property real fontSizeMedium: Math.round(fontScale * 14)
    readonly property real fontSizeLarge: Math.round(fontScale * 16)
    readonly property real fontSizeXLarge: Math.round(fontScale * 20)
    readonly property real fontSizeXXLarge: Math.round(fontScale * 28)
    readonly property real fontSizeDisplay: Math.round(fontScale * 36)
    readonly property real fontSizeDisplayLarge: Math.round(fontScale * 57)
    readonly property int fontWeightMedium: Font.Medium
    readonly property int fontWeightBold: Font.Bold

    // ------------------------------------------------------------ geometry
    readonly property real spacingXXS: 2
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real spacingXL: 24
    readonly property real iconSizeSmall: 16
    readonly property real iconSize: 24
    readonly property real iconSizeLarge: 32
    readonly property real cornerRadius: Haseen.Theme.radius
    readonly property real listItemHeight: 56
    readonly property real buttonHeightXS: 32
    readonly property real buttonHeightM: 56

    // ------------------------------------------------------------ motion
    readonly property int shortDuration: 150
    readonly property int mediumDuration: 300
    readonly property int standardEasing: Easing.OutCubic

    function barIconSize(barThickness: real, offset: var, maximizeIcon: var, iconScale: var): int {
        const defaultOffset = offset !== undefined ? offset : -6;
        const size = maximizeIcon ? iconSizeLarge : iconSize;
        const s = iconScale !== undefined ? iconScale : 1.0;
        return 2 * Math.round((barThickness / 48) * (size + defaultOffset) * s / 2);
    }

    function barTextSize(barThickness: real, scale: var, maximizeText: var): int {
        const ratio = barThickness / 48;
        const dankBarScale = scale !== undefined ? scale : 1.0;
        if (ratio <= 0.75)
            return Math.round((maximizeText ? fontSizeMedium : fontSizeSmall * 0.9) * dankBarScale);
        if (ratio >= 1.25)
            return Math.round((maximizeText ? fontSizeXLarge : fontSizeMedium) * dankBarScale);
        return Math.round((maximizeText ? fontSizeLarge : fontSizeSmall) * dankBarScale);
    }
}
