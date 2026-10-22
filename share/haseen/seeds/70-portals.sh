# shellcheck shell=bash
# xdg-desktop-portal. Sourced by bin/haseen-seed-user.
#
# haseen:seed $CONFIG/xdg-desktop-portal/hyprland-portals.conf|portal backends, gnome-keyring as the Secret portal
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# config/xdg-desktop-portal/hyprland-portals.conf and migration 1788261467.
#
# The hyprland package's /usr/share/xdg-desktop-portal/hyprland-portals.conf
# names hyprland and gtk, and neither implements the Secret portal, so Flatpak
# apps had no way into gnome-keyring. The portal reads one file, the first it
# finds, with the desktop's own name ahead of portals.conf in each directory:
# a portals.conf of the user's would lose to this seed, so its presence means
# the user already chose, and nothing is seeded (plan 103).
seed_main() {
    local dir="$CONFIG/xdg-desktop-portal"
    # -L too: a dangling link is the user's, never written through.
    [[ -e $dir/portals.conf || -L $dir/portals.conf ]] && return 0
    seed_user_file "$DEFAULTS/xdg-desktop-portal/hyprland-portals.conf" "$dir/hyprland-portals.conf"
}
