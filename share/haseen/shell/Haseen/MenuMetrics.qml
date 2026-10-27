pragma Singleton
import QtQuick
import qs.Haseen

// Omarchy's menu card metrics, in one place (plan 122). `haseen.launcher`
// reads them so its card opens at the same width and height as the menu that
// SUPER + SPACE opens; `haseen.menu` computes the same numbers in
// plugins/haseen.menu/MenuStyle.js (and its Panel.qml turns them into
// pixels).
//
// The numbers are Omarchy's pixels at its base size of 12, which is haseen's
// default fontSize too (plan 115), scaled by Theme.fontScale exactly as
// MenuStyle.js scales them, so a font change moves both cards together.
QtObject {
    readonly property real scale: Theme.fontScale

    function space(px: real): int {
        const n = px * scale;
        return n <= 0 ? 0 : Math.max(1, Math.round(n));
    }

    function fontPx(mult: real): int {
        return Math.max(1, Math.round(12 * scale * mult));
    }

    // MenuStyle.js: WIDTH, and the card's one-pixel border at space(2).
    readonly property int width: space(300)
    readonly property int borderWidth: space(2)
    // Omarchy's Menu.qml:100-109, as MenuStyle.js numbers them.
    readonly property int contentMargin: space(18)
    readonly property int headerHeight: Math.max(space(34), fontPx(1.167) + space(6) * 2)
    readonly property int contentSpacing: space(6)
    readonly property int baseRowHeight: Math.max(space(50), fontPx(1) + space(12) * 2)
    readonly property int detailRowHeight: Math.max(space(58), fontPx(1) + fontPx(0.833) + space(12) * 2)
    readonly property int rowSpacing: space(3)
    readonly property int iconColumn: space(36)
    readonly property int headingSize: Theme.font.heading
    readonly property int iconSize: Theme.font.iconLarge
}
