# shellcheck shell=bash
# Plan 101: Omarchy's own migration runner must never run on a haseen machine.
# /usr/bin/omarchy-migrate, and Omarchy's own /usr/bin/omarchy-update, which
# runs it right after its pacman transaction, run every script the omarchy
# package ships that this user's Omarchy ledger does not list; 4.5's edit
# /boot/limine.conf without re-enrolling it for Secure Boot, delete a link in
# ~/.config/omarchy/plugins, drop Ctrl+Space from fcitx5, uninstall Tensaku
# and enable a second wallpaper daemon. This records every one of them as done
# in that ledger, for this user, now; the base layer's pacman hook does the
# same whenever the omarchy package changes (lib/omarchy-guard.sh).
# Safe to re-run: a sealed or applied migration is left alone, and without
# Omarchy's package there is nothing to seal. It never touches
# ~/.config/omarchy/plugins.

# shellcheck source=../lib/omarchy-guard.sh
source "$HASEEN_PATH/lib/omarchy-guard.sh"

[[ -d $(omarchy_migrations_dir) ]] || exit 0
omarchy_seal_migrations
