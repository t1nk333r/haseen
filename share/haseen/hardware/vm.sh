# shellcheck shell=bash
# vm — a virtual machine renders on the CPU, where animations and blur cost
# every frame. Start without them; the user can delete the toggle to get them
# back.
#
# Adapted from Omarchy install/user/hardware/vm-no-animations.sh (MIT,
# Copyright (c) David Heinemeier Hansson). The file lands in haseen's Hyprland
# toggle directory, which `default/hypr/init.lua` loads last.

toggle="$HASEEN_USER_STATE/toggles/hypr/no-animations.lua"

if [[ -e $toggle ]]; then
    info "hw vm: $toggle already exists"
    return 0
fi

write_user_file "$toggle" <<'LUA'
-- Written by `haseen hw apply` (quirk: vm). Delete this file and reload
-- Hyprland to get animations and blur back.
hl.config({
  animations = { enabled = false },
  decoration = { blur = { enabled = false } },
})
LUA
info "hw vm: animations and blur off (${toggle/#$HOME/\~})"
