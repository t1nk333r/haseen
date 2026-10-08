# shellcheck shell=bash
# Plan 046: window corners follow the shell's frame. `haseen theme set` now
# writes current/theme/rounding.lua (the shared radius, which toggles and
# hyprmod still override) and prefixes the theme's hyprland.lua so its own
# rounding is dropped. A theme rendered before that keeps its old rounding
# until the next theme set, so render the current theme again here.
# Safe to re-run: a render that has rounding.lua is already new, and a HOME
# without a current theme has nothing to render. A render that fails (a user
# theme whose colors.toml broke since) leaves the old one in place and does
# not hold back the migrations after this one.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

[[ -r $THEME_NAME_FILE && -d $THEME_CURRENT_PATH ]] || exit 0
[[ -e $THEME_CURRENT_PATH/rounding.lua ]] && exit 0
name="$(<"$THEME_NAME_FILE")"
[[ -n $name ]] || exit 0

haseen theme set "$name" ||
    warn "theme '$name' was not rendered again; its windows keep the old corners until: haseen theme set <name>"
