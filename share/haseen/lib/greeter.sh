# shellcheck shell=bash
# greeter.sh — who logs in and with what. Sourced, never executed.
#
# Shape adapted from DankMaterialShell quickshell/Modules/Greetd (MIT,
# Copyright (c) 2025 Avenge Media LLC): greetd runs a compositor whose only job
# is to run the shell's greeter, the user list comes from getent, and the
# session list comes from the .desktop files in the session directories.
#
# haseen keeps tuigreet as the default. The graphical greeter is opt-in
# (`haseen setup greeter haseen`), because a greeter that fails to start locks
# the machine out of its own desktop, and tuigreet cannot.

[[ -n ${HASEEN_GREETER_SH:-} ]] && return 0
HASEEN_GREETER_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/preflight.sh" # preflight_luks -> LUKS_DETECTED

# shellcheck disable=SC2034  # read by bin/haseen-setup-greeter and layers/desktop
GREETD_CONFIG=/etc/greetd/config.toml
GREETER_CHOICE_FILE=/etc/haseen/greeter
# shellcheck disable=SC2034  # read by bin/haseen-greeter and bin/haseen-setup-greeter
GREETER_STATE_DIR=/var/lib/haseen/greeter
# Same marker layers/desktop stamps on the files it owns: `haseen setup
# greeter` and a layer apply write this file, and both must recognise it.
GREETER_MARKER="# Written by haseen layers/desktop"

GREETER_AUTOLOGIN_FILE=/etc/haseen/autologin

# greeter_choice — tuigreet (default) or haseen.
greeter_choice() {
    local f
    f="$(sysroot_path "$GREETER_CHOICE_FILE")"
    if [[ -r $f ]]; then
        case "$(tr -d '[:space:]' <"$f")" in
        haseen) echo haseen ;;
        *) echo tuigreet ;;
        esac
    else
        echo tuigreet
    fi
}

# greeter_autologin_user — the user the machine logs in at boot without asking
# again, or "" when it asks. Omarchy's arrangement: with an encrypted root the
# disk password typed at the Plymouth splash *is* the authentication, so a
# second password on the same boot proves nothing. greetd's [initial_session]
# is exactly that: it runs once, at boot, and every later login goes through
# the greeter.
greeter_autologin_user() {
    local f
    f="$(sysroot_path "$GREETER_AUTOLOGIN_FILE")"
    [[ -r $f ]] || return 0
    tr -d '[:space:]' <"$f"
}

# greeter_session_command — what a logged-in session starts with.
greeter_session_command() { printf '%s\n' "uwsm start hyprland.desktop"; }

# greeter_command CHOICE — what greetd starts. tuigreet logs in on the VT;
# the haseen greeter is a Hyprland session that runs the shell's greeter
# config and exits when it does (bin/haseen-greeter).
greeter_command() {
    case "${1:-$(greeter_choice)}" in
    haseen) printf '%s\n' "haseen-greeter" ;;
    *) printf '%s\n' "tuigreet --time --remember --asterisks --cmd '$(greeter_session_command)'" ;;
    esac
}

# greetd_config [CHOICE] [AUTOLOGIN_USER] — the whole /etc/greetd/config.toml.
greetd_config() {
    local autologin="${2-$(greeter_autologin_user)}"
    cat <<EOF
$GREETER_MARKER. Rewritten on every apply while this line is here;
# delete the line to take the file over.
[terminal]
vt = 1

[default_session]
command = "$(greeter_command "${1:-}")"
user = "greeter"
EOF
    [[ -n $autologin ]] || return 0
    cat <<EOF

# The disk password at the boot splash already authenticated this boot, so the
# first session starts without asking again. A logout lands on the greeter.
[initial_session]
command = "$(greeter_session_command)"
user = "$autologin"
EOF
}

# greeter_users — "name<TAB>display name" for the humans on this machine.
# Upstream's filter (GreeterUsersService.qml): uid 1000-59999, not nobody, a
# real shell, a real home.
greeter_users() {
    local passwd
    passwd="$(sysroot_path /etc/passwd)"
    [[ -r $passwd ]] || return 0
    awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" &&
             $7 !~ /(nologin|false)$/ && $6 != "/var/empty" {
        split($5, gecos, ",")
        print $1 "\t" (gecos[1] == "" ? $1 : gecos[1])
    }' "$passwd" | sort
}

# greeter_sessions — "id<TAB>name<TAB>exec" for every installed session.
# Wayland first, the way a Wayland greeter should offer them.
greeter_sessions() {
    local dir file id name exec
    for dir in /usr/share/wayland-sessions /usr/local/share/wayland-sessions \
        /usr/share/xsessions /usr/local/share/xsessions; do
        for file in "$(sysroot_path "$dir")"/*.desktop; do
            [[ -r $file ]] || continue
            id="${file##*/}"
            id="${id%.desktop}"
            name="$(sed -n 's/^Name=//p' "$file" | head -n1)"
            exec="$(sed -n 's/^Exec=//p' "$file" | head -n1)"
            [[ -n $exec ]] || continue
            printf '%s\t%s\t%s\n' "$id" "${name:-$id}" "$exec"
        done
    done
}
