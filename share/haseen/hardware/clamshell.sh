# shellcheck shell=bash
# clamshell — closing the lid while an external monitor is connected turns the
# built-in panel off instead of blanking the session, and opening it brings the
# panel back.
#
# Adapted from Omarchy bin/omarchy-hw-clamshell and
# bin/omarchy-hyprland-monitor-clamshell (MIT, Copyright (c) David Heinemeier
# Hansson), which watch the lid and the connected outputs. Here the lid switch
# calls `haseen hardware laptop-display`, which already refuses to disable the
# only active display: with no external monitor the lid behaves as before and
# logind decides what happens.

toggle="$HASEEN_USER_STATE/toggles/hypr/clamshell.lua"

if [[ -e $toggle ]]; then
    info "hw clamshell: $toggle already exists"
    return 0
fi

write_user_file "$toggle" <<'LUA'
-- Written by `haseen hw apply` (quirk: clamshell). Delete this file and reload
-- Hyprland to let logind handle the lid on its own.
haseen.bind("switch:on:Lid Switch", "Lid closed", "haseen hardware laptop-display off", { locked = true })
haseen.bind("switch:off:Lid Switch", "Lid opened", "haseen hardware laptop-display on", { locked = true })
LUA
info "hw clamshell: lid switch bound (${toggle/#$HOME/\~})"
