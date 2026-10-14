# shellcheck shell=bash
# Plan 046: window corners follow the shell's frame. `haseen theme set` now
# writes current/theme/rounding.lua (the shared radius, which toggles and
# hyprmod still override) and prefixes the theme's hyprland.lua so its own
# rounding is dropped. A theme rendered before that keeps its own corners, so
# this adds those two files to the current render, and nothing else: a full
# `theme set` would also relink the background (a wallpaper the user picked
# outside the theme is lost), nvim and gtk.css, and reload the session. The
# new corners show at Hyprland's next config reload.
# Safe to re-run: a render that has rounding.lua is already new, and a HOME
# without a current theme has nothing to change. A render whose colors.toml
# no longer parses is left as it is and does not hold back the migrations
# after this one.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

[[ -r $THEME_NAME_FILE && -d $THEME_CURRENT_PATH ]] || exit 0
# theme set's lock: the copy below must not race a theme change.
exec 9>"$THEME_CURRENT_DIR/.theme-set.lock"
flock 9
[[ -e $THEME_CURRENT_PATH/rounding.lua ]] && exit 0
if ! theme_colors_load "$THEME_CURRENT_PATH/colors.toml"; then
    warn "the current theme has no readable colors.toml; its windows keep their own corners until: haseen theme set <name>"
    exit 0
fi
_theme_window_radius
# Changed in a copy, then swapped in whole, as theme set does: Hyprland never
# reads a half-written hyprland.lua.
rm -rf -- "$THEME_NEXT_PATH"
cp -a -- "$THEME_CURRENT_PATH" "$THEME_NEXT_PATH"
_theme_window_rounding "$THEME_NEXT_PATH"
theme_swap "$(<"$THEME_NAME_FILE")"
