// haseen.menu's look: Omarchy's menu (shell/plugins/menu/Menu.qml and the
// [menu] section of default/themed/shell.toml.tpl) as numbers, so Panel.qml
// and tests/test-menu.sh read the same ones. Colours map Omarchy's tokens
// onto haseen's Theme: menu.background = background, menu.text and the
// border = foreground, scrim = background at SCRIM, selected-background =
// foreground at SELECTED_FILL, selected-text = accent. Sizes are Omarchy's
// pixels at its default base size of 12, which haseen's default fontSize of
// 11 stands for (scale()).
//
// Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson).
.pragma library

var SCRIM = 0.5;
var SELECTED_FILL = 0.08;
var HEADER = 0.58;
var CHEVRON = 0.36;
var DIVIDER = 0.2;
var EMPTY_GLYPH = 0.8;
var EMPTY_TEXT = 0.7;
// Omarchy's card widths: 300, and 520 for the menus with long rows.
var WIDTH = 300;
var WIDE = 520;
var WIDE_MENUS = ["trigger.capture.screenrecord", "style.font"];

// Omarchy's Style.space and font scale for a haseen fontSize.
function scale(fontSize) {
    return Math.max(1 / 11, fontSize / 11);
}

function space(fontSize, px) {
    var n = px * scale(fontSize);
    return n <= 0 ? 0 : Math.max(1, Math.round(n));
}

function fontPx(fontSize, mult) {
    return Math.max(1, Math.round(12 * scale(fontSize) * mult));
}
