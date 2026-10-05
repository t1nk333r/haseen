# shellcheck shell=bash
# fkeys — F-keys stay F-keys on Apple-style keyboards (Apple, Lofree Flow,
# Keychron in Mac mode). Run by `haseen hw apply`; sourced helpers come from it.
#
# Adapted from Omarchy install/hardware/fix-fkeys.sh (MIT, Copyright (c) David
# Heinemeier Hansson). fnmode=2 makes the top row send F1-F12 directly, with the
# media keys on Fn.

conf=/etc/modprobe.d/haseen-hid-apple.conf

if [[ -e $(sysroot_path "$conf") ]]; then
    info "hw fkeys: $conf already exists"
    return 0
fi

echo "options hid_apple fnmode=2" | write_root_file "$conf"
info "hw fkeys: wrote $conf (applies after the module reloads or a reboot)"
