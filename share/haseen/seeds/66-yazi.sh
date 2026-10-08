# shellcheck shell=bash
# yazi, haseen's file manager. Sourced by bin/haseen-seed-user.
#
# haseen:seed $CONFIG/yazi/yazi.toml|file manager settings and openers
# haseen:seed $CONFIG/yazi/keymap.toml|the extra binds on top of yazi's defaults
# haseen:seed $CONFIG/yazi/theme.toml|link to the theme pipeline's colours
#
# Same split as btop: the colours belong to the theme pipeline, so
# theme.toml is a link to what `haseen theme set` renders, and the seeded
# files carry only what that does not cover. A dangling link is safe — yazi
# maps ENOENT on theme.toml to "no user theme" and keeps its own
# (yazi-config/src/theme/theme.rs reads it through yazi-fs's ok_or_not_found).
seed_main() {
    seed_user_file "$DEFAULTS/yazi/yazi.toml" "$CONFIG/yazi/yazi.toml"
    seed_user_file "$DEFAULTS/yazi/keymap.toml" "$CONFIG/yazi/keymap.toml"

    local link="$CONFIG/yazi/theme.toml"
    local target="$HASEEN_USER_STATE/current/theme/yazi.toml"
    # -L too: a dangling link is still the user's (no theme applied yet).
    if [[ -e $link || -L $link ]]; then
        return 0
    fi
    run mkdir -p "$CONFIG/yazi"
    run ln -snf "$target" "$link"
}
