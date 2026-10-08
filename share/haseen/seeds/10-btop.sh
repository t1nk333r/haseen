# shellcheck shell=bash
# btop. Sourced by bin/haseen-seed-user, which defines DEFAULTS, CONFIG and
# COMPOSE and calls seed_main once.
#
# haseen:seed $CONFIG/btop/btop.conf|resource monitor settings
# haseen:seed $CONFIG/btop/themes/current.theme|link to the theme pipeline's colours
#
# The colours belong to the theme pipeline: `haseen theme set` renders
# share/haseen/themed/btop.theme.tpl to current/theme/btop.theme. The seed adds
# only what that does not cover — btop's own settings, and the themes link that
# makes `color_theme = "current"` resolve to the rendered file.
seed_main() {
    seed_user_file "$DEFAULTS/btop/btop.conf" "$CONFIG/btop/btop.conf"
    local link="$CONFIG/btop/themes/current.theme"
    local target="$HASEEN_USER_STATE/current/theme/btop.theme"
    # -L too: a dangling link is still the user's (no theme applied yet).
    if [[ -e $link || -L $link ]]; then
        return 0
    fi
    run mkdir -p "$CONFIG/btop/themes"
    run ln -snf "$target" "$link"
}
