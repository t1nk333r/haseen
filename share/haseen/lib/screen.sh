# shellcheck shell=bash
# screen.sh — display power (DPMS) for `haseen screen off|on` (plan 084).
# Sourced after common.sh, never executed.
#
# Only DPMS: the outputs stay enabled and keep their workspaces, and the
# next key press or pointer motion wakes them (misc.key_press_enables_dpms
# and mouse_move_enables_dpms, share/haseen/default/hypr/input.lua). Not the
# Blackout overlay and not `haseen hardware laptop display off`, which
# disables an output.

# screen_lua — true when Hyprland reads a Lua config and so takes Lua
# dispatcher expressions. Same question Quickshell asks for
# Hyprland.usingLua: the configProvider of `hyprctl status -j`. A Hyprland
# without that request (before 0.56) answers no JSON and is the legacy kind.
screen_lua() {
    [[ "$(hyprctl status -j 2>/dev/null | jq -r '.configProvider // empty' 2>/dev/null)" == lua ]]
}

# screen_dpms on|off — the dispatcher haseen.idle sends
# (shell/plugins/haseen.idle/Service.qml `_dpms`), through hyprctl.
screen_dpms() {
    local args out
    if screen_lua; then
        args=(dispatch "hl.dsp.dpms({ action = \"$([[ $1 == on ]] && echo enable || echo disable)\" })")
    else
        args=(dispatch dpms "$1")
    fi
    if $DRY_RUN; then
        echo "DRYRUN: hyprctl ${args[*]}"
        return 0
    fi
    out="$(hyprctl "${args[@]}" 2>&1)" || die "hyprctl failed: $out"
    [[ -z $out || $out == ok ]] || die "Hyprland refused '${args[*]:1}': $out"
}
