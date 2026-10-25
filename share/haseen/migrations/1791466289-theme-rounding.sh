# shellcheck shell=bash
# Plan 046, as plan 114 left it: the current theme's hyprland.lua loads after
# `haseen toggle …` and hyprmod, so `haseen theme set` prefixes it with
# haseen.theme_hl, through which the theme yields to them. A theme rendered
# before plan 046 has no prefix, so a toggle or the GUI could not win over its
# corners or gaps: this adds the prefix to the current render, and nothing
# else. A full `theme set` would also relink the background (a wallpaper the
# user picked outside the theme is lost), nvim and gtk.css, and reload the
# session. The change shows at Hyprland's next config reload.
# Plan 046 also wrote current/theme/rounding.lua here, the shell frame's
# radius; plan 114 gave the corners back to the theme and init.lua no longer
# loads that file, so it is not written.
# Safe to re-run: a render that has the prefix is already new, and a HOME
# without a current theme has nothing to change.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

[[ -r $THEME_NAME_FILE && -d $THEME_CURRENT_PATH ]] || exit 0
# theme set's lock: the copy below must not race a theme change.
exec 9>"$THEME_CURRENT_DIR/.theme-set.lock"
flock 9
[[ -e $THEME_CURRENT_PATH/hyprland.lua ]] || exit 0
[[ $(sed -n 2p "$THEME_CURRENT_PATH/hyprland.lua") == "$THEME_HL_PREFIX" ]] && exit 0
# Changed in a copy, then swapped in whole, as theme set does: Hyprland never
# reads a half-written hyprland.lua.
rm -rf -- "$THEME_NEXT_PATH"
cp -a -- "$THEME_CURRENT_PATH" "$THEME_NEXT_PATH"
_theme_hyprland_prefix "$THEME_NEXT_PATH"
theme_swap "$(<"$THEME_NAME_FILE")"
