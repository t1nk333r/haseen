# shellcheck shell=bash
# Default handlers. Sourced by bin/haseen-seed-user.
#
# haseen:seed $CONFIG/xdg-terminals.list|the terminal GTK apps and flea open
#
# xdg-terminal-exec is the four-place model's terminal hop: a desktop entry
# with Terminal=true (yazi, nvim), GTK's "Open in Terminal" and flea's terminal
# action all run it, and it reads $XDG_CONFIG_HOME/xdg-terminals.list before
# anything else (/usr/bin/xdg-terminal-exec:148-153). Seeding that file from
# the terminal the user already chose keeps one answer for "my terminal"
# instead of two.
#
# The vendor fallback for a machine that never ran this seed is
# $PREFIX/share/xdg-terminal-exec/hyprland-xdg-terminals.list, installed by
# install.sh from default/xdg-terminal-exec/.

# The desktop id each terminal name ships, read from the packages
# (pacman -Ql foot / -Fl alacritty ghostty kitty). Kept in step with
# TERMINAL_DESKTOPS in bin/haseen-setup-default, which rewrites this same file
# when the user changes terminal; tests/test-handlers.sh asserts the two maps
# agree.
declare -A SEED_TERMINAL_DESKTOPS=(
    [foot]=foot.desktop
    [alacritty]=Alacritty.desktop
    [ghostty]=com.mitchellh.ghostty.desktop
    [kitty]=kitty.desktop
)

# seed_terminal_name — the terminal `haseen setup default terminal` recorded,
# else $TERMINAL, else foot. The env file is read, not sourced: it belongs to
# the login session and may hold anything.
seed_terminal_name() {
    local env_file="$CONFIG/uwsm/env.d/60-haseen-defaults" name=""
    [[ -r $env_file ]] && name="$(sed -n 's/^export TERMINAL=//p' "$env_file" | tail -n1 | tr -d "'\"")"
    [[ -n $name ]] || name="${TERMINAL:-}"
    name="${name##*/}"
    [[ -n ${SEED_TERMINAL_DESKTOPS[$name]:-} ]] || name=foot
    printf '%s\n' "$name"
}

seed_main() {
    local list="$CONFIG/xdg-terminals.list" name
    [[ -e $list ]] && return 0
    name="$(seed_terminal_name)"
    write_user_file "$list" <<EOF
# Terminal preference for xdg-terminal-exec: desktop entries with
# Terminal=true, GTK's "Open in Terminal" and flea open this one.
# haseen seeded it from your \$TERMINAL; 'haseen setup default terminal NAME'
# rewrites it. The first entry that exists and is valid wins.
${SEED_TERMINAL_DESKTOPS[$name]}
EOF
}
