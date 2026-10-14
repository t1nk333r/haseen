# shellcheck shell=bash
# fcitx5 and the input-method environment. Sourced by bin/haseen-seed-user.
#
# haseen:seed $CONFIG/fcitx5/{config,profile}|English <-> Arabic on Control+space
# haseen:seed $CONFIG/fcitx5/conf/*.conf|fcitx5 addon settings
# haseen:seed $CONFIG/environment.d/10-haseen-fcitx.conf|QT_IM_MODULE and friends
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# config/fcitx5/conf/{xcb,clipboard}.conf and
# default/environment.d/10-omarchy-fcitx.conf.
seed_main() {
    local f
    for f in config profile conf/xcb.conf conf/clipboard.conf; do
        seed_user_file "$DEFAULTS/fcitx5/$f" "$CONFIG/fcitx5/$f"
    done
    seed_user_file "$DEFAULTS/environment.d/10-haseen-fcitx.conf" \
        "$CONFIG/environment.d/10-haseen-fcitx.conf"
}
