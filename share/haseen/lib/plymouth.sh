# shellcheck shell=bash
# plymouth.sh — the boot screen, coloured by the current haseen theme. Sourced.
#
# Behaviour taken from omarchy bin/omarchy-plymouth-set (MIT, David Heinemeier
# Hansson): theme the splash from the active colour scheme, set it as the
# default, and rebuild the initramfs so the next boot shows it. haseen's theme
# is drawn by a script, not composed from PNGs, so a theme change is a colour
# substitution and this repository ships no binary assets.
#
# The point of the splash is not decoration: with an encrypted root the disk
# password is typed here, and with autologin that is the only password the
# machine asks for.

[[ -n ${HASEEN_PLYMOUTH_SH:-} ]] && return 0
HASEEN_PLYMOUTH_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=boot.sh
source "$(dirname "${BASH_SOURCE[0]}")/boot.sh"

# shellcheck disable=SC2034  # read by bin/haseen-plymouth-*
PLYMOUTH_THEME_DIR=/usr/share/plymouth/themes/haseen
# shellcheck disable=SC2034  # read by bin/haseen-plymouth-set
PLYMOUTH_HOOK_CONF=/etc/mkinitcpio.conf.d/haseen-plymouth.conf
PLYMOUTH_SOURCE_DIR="$HASEEN_PATH/default/plymouth"

# Read through the sysroot like every other probe: what matters is whether the
# machine being configured has plymouth, not whether this one does.
plymouth_installed() { [[ -x $(sysroot_path /usr/bin/plymouth-set-default-theme) ]]; }

# plymouth_current_theme — what plymouthd will show, or "" when none is set.
plymouth_current_theme() {
    local f
    f="$(sysroot_path /etc/plymouth/plymouthd.conf)"
    [[ -r $f ]] || return 0
    sed -n 's/^[[:space:]]*Theme[[:space:]]*=[[:space:]]*//p' "$f" | tail -n1
}

plymouth_hook_present() { boot_hooks | grep -qx plymouth; }

# plymouth_theme_colors FILE — "background foreground accent" as #rrggbb, from
# a theme's colors.toml. Missing keys fall back to the shipped defaults, so a
# half-written theme still produces a readable boot screen.
plymouth_theme_colors() {
    local file="$1" bg fg accent
    bg="$(sed -n 's/^background[[:space:]]*=[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$file" | head -n1)"
    fg="$(sed -n 's/^foreground[[:space:]]*=[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$file" | head -n1)"
    accent="$(sed -n 's/^accent[[:space:]]*=[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$file" | head -n1)"
    printf '%s %s %s\n' "${bg:-#171717}" "${fg:-#cccccc}" "${accent:-${fg:-#cccccc}}"
}

# plymouth_script BG FG ACCENT — the theme script with its colours filled in.
# Plymouth's script language takes components as 0..1 floats.
plymouth_script() {
    local bg="${1#\#}" fg="${2#\#}" accent="${3#\#}" out
    out="$(cat "$PLYMOUTH_SOURCE_DIR/haseen.script")"
    local name hex channel offset value
    for name in BG FG ACCENT; do
        case "$name" in
        BG) hex="$bg" ;;
        FG) hex="$fg" ;;
        *) hex="$accent" ;;
        esac
        offset=0
        for channel in R G B; do
            value="$(awk -v n="$((16#${hex:offset:2}))" 'BEGIN { printf "%.3f", n / 255 }')"
            out="${out//@@${name}_${channel}@@/$value}"
            offset=$((offset + 2))
        done
    done
    printf '%s\n' "$out"
}
