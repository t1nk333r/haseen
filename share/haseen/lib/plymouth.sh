# shellcheck shell=bash
# plymouth.sh — the boot screen, coloured by the current haseen theme. Sourced.
#
# Behaviour taken from omarchy bin/omarchy-plymouth-set (MIT, David Heinemeier
# Hansson): theme the splash from the active colour scheme, set it as the
# default, and rebuild the initramfs so the next boot shows it. haseen's theme
# is drawn by a script, not composed from PNGs, so a theme change is a colour
# substitution and this repository ships no binary assets: the one image, the
# mark, is rendered from its SVG when the theme is installed.
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
# shellcheck source=branding.sh
source "$(dirname "${BASH_SOURCE[0]}")/branding.sh"

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

# plymouth_hook_present — `plymouth` is in the effective HOOKS; status 2 when
# they cannot be read (boot_hooks says why).
plymouth_hook_present() {
    local hooks
    hooks="$(boot_hooks)" || return 2
    grep -qx plymouth <<<"$hooks"
}

# plymouth_reset_by_omarchy — Omarchy's omarchy-settings package undid
# haseen's splash. Its install scriptlet copies its own plymouthd.conf
# ([Daemon] Theme=omarchy) over /etc/plymouth/plymouthd.conf on every install
# and upgrade (omarchy-pkgs pkgbuilds/omarchy-settings/omarchy-settings.install
# `_etc_overrides_apply`, the same in 4.0.6-1 as installed on luna), so the
# next initramfs would embed Omarchy's splash. True only when haseen's theme
# is installed (`haseen plymouth set` ran) and plymouthd.conf names exactly the
# theme that scriptlet writes; any other choice is the owner's and stays.
plymouth_reset_by_omarchy() {
    plymouth_installed || return 1
    [[ -r $(sysroot_path "$PLYMOUTH_THEME_DIR/haseen.plymouth") ]] || return 1
    [[ $(plymouth_current_theme) == omarchy ]]
}

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

# plymouth_install_logo ACCENT [MARK] — MARK (default the selected one, haseen
# branding mark) as $PLYMOUTH_THEME_DIR/logo.png, 112 px tall in ACCENT.
# Rendered by ImageMagick (the shell layer's dependency) into a scratch file,
# then installed. Without magick the splash has no mark and says nothing
# worse: the script draws everything else without it.
plymouth_install_logo() {
    local accent="$1" mark="${2:-}" svg tmp
    [[ -n $mark ]] || mark="$(branding_mark)"
    svg="$(branding_file mark "$mark")"
    if $DRY_RUN; then
        echo "DRYRUN: render $svg in $accent -> logo.png (mark: $mark)"
        install_root_file logo.png "$PLYMOUTH_THEME_DIR/logo.png"
        return 0
    fi
    if ! have magick; then
        warn "magick is not installed: the splash shows no mark"
        return 0
    fi
    tmp="$(mktemp -d)"
    branding_svg mark "$accent" "$mark" >"$tmp/logo.svg"
    magick -background none -density 600 "$tmp/logo.svg" -resize x112 "$tmp/logo.png"
    install_root_file "$tmp/logo.png" "$PLYMOUTH_THEME_DIR/logo.png"
    rm -rf "$tmp"
}

# plymouth_install_theme BG FG ACCENT MARK — haseen's splash in these colours
# and this mark into $PLYMOUTH_THEME_DIR: the descriptor, the script, the mark.
# What `haseen plymouth set` and the root side of following (`haseen plymouth
# apply`) both install, so the two paths cannot drift.
plymouth_install_theme() {
    install_root_file "$PLYMOUTH_SOURCE_DIR/haseen.plymouth" "$PLYMOUTH_THEME_DIR/haseen.plymouth"
    plymouth_script "$1" "$2" "$3" | write_root_file "$PLYMOUTH_THEME_DIR/haseen.script"
    plymouth_install_logo "$3" "$4"
}

# plymouth_theme_ours — haseen's splash is installed and is the one plymouthd
# shows. Following recolours only that: a splash the owner chose stays.
plymouth_theme_ours() {
    plymouth_installed || return 1
    [[ -r $(sysroot_path "$PLYMOUTH_THEME_DIR/haseen.plymouth") ]] || return 1
    [[ $(plymouth_current_theme) == haseen ]]
}

# --- Following the theme (plan 110) -----------------------------------------
#
# The splash lives in the initramfs, which only root can rebuild. Following
# splits that in two:
#   - the user's side: `haseen theme set` and `haseen branding mark` restart
#     haseen-splash-follow.timer (plymouth_follow_poke), so it fires about 2
#     minutes after the last change and quick theme flicking rebuilds nothing;
#     its service runs `haseen plymouth follow request`, which compares the
#     current theme with what the boot image carries and asks root for one
#     thing: to start haseen-splash@<request>.service;
#   - root's side: that template unit runs `haseen plymouth apply <request>`,
#     which parses the instance name again, reads nothing in a home, renders
#     the splash and rebuilds the initramfs at idle priority; a shutdown waits
#     for a rebuild that has begun (plymouth_guard_stops).
# A request is the instance name: background, text and accent as six
# lowercase hex digits each, then the mark, e.g. 1f1f28-dcd7ba-dcd7ba-kufic.
# /etc/polkit-1/rules.d/50-haseen-splash.rules lets wheel members start such
# a unit, and nothing else, without a password.

# shellcheck disable=SC2034  # read by bin/haseen-plymouth-*
PLYMOUTH_STAMP=/var/lib/haseen/splash
PLYMOUTH_FOLLOW_TIMER=haseen-splash-follow.timer
PLYMOUTH_FOLLOW_UNIT_SRC="$HASEEN_PATH/default/systemd/haseen-splash@.service"
PLYMOUTH_FOLLOW_UNIT=/etc/systemd/system/haseen-splash@.service
PLYMOUTH_FOLLOW_RULE_SRC="$HASEEN_PATH/default/polkit/50-haseen-splash.rules"
PLYMOUTH_FOLLOW_RULE=/etc/polkit-1/rules.d/50-haseen-splash.rules
# The router the root unit runs, rendered from where this tree is installed
# (PREFIX/share/haseen -> PREFIX/bin/haseen), as the secureboot hook's is.
PLYMOUTH_HASEEN_BIN="$(cd "$HASEEN_PATH/../.." && pwd)/bin/haseen"
# The user's record of the last request: "ok|failed|skipped REQUEST [WHY]".
PLYMOUTH_FOLLOW_RECORD="$HASEEN_USER_STATE/splash-follow"

# plymouth_request BG FG ACCENT MARK — the request (instance name) for them.
plymouth_request() {
    local bg="${1#\#}" fg="${2#\#}" accent="${3#\#}"
    printf '%s-%s-%s-%s\n' "${bg,,}" "${fg,,}" "${accent,,}" "$4"
}

# plymouth_request_parse NAME — NAME is a well-formed request: three colours
# of exactly six lowercase hex digits and one of haseen's marks, nothing
# else. Sets PLYMOUTH_REQUEST=(#bg #fg #accent mark). The root side's only
# input, so anything else is refused, never repaired.
plymouth_request_parse() {
    local re='^([0-9a-f]{6})-([0-9a-f]{6})-([0-9a-f]{6})-([a-z]{1,16})$'
    PLYMOUTH_REQUEST=()
    [[ ${#1} -le 48 && $1 =~ $re ]] || return 1
    branding_known "${BASH_REMATCH[4]}" || return 1
    # shellcheck disable=SC2034  # read by the callers
    PLYMOUTH_REQUEST=("#${BASH_REMATCH[1]}" "#${BASH_REMATCH[2]}" "#${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
}

# plymouth_built_request — the request the boot image was last built with
# ($PLYMOUTH_STAMP, written after each successful rebuild); empty when
# unknown (none recorded, or a record that does not parse).
plymouth_built_request() {
    local f line=""
    f="$(sysroot_path "$PLYMOUTH_STAMP")"
    [[ -f $f && -r $f ]] && IFS= read -r line <"$f"
    if plymouth_request_parse "$line"; then printf '%s\n' "$line"; fi
    return 0
}

# plymouth_record_built REQUEST — the boot image now carries REQUEST.
plymouth_record_built() {
    printf '%s\n' "$1" | write_root_file "$PLYMOUTH_STAMP" 0644
}

# plymouth_current_request — the request for the user's current theme and
# mark; fails when no theme has been set.
plymouth_current_request() {
    local colors="$HASEEN_USER_STATE/current/theme/colors.toml" bg fg accent
    [[ -r $colors ]] || return 1
    read -r bg fg accent <<<"$(plymouth_theme_colors "$colors")"
    plymouth_request "$bg" "$fg" "$accent" "$(branding_mark)"
}

# plymouth_signed_boot — this machine checks its boot files, so a rebuild
# also has to be signed or enrolled again: Secure Boot is on (or cannot be
# read on UEFI), sbctl holds keys (haseen secureboot setup), or Limine's
# config hash is enrolled. Prints which; fails when none. Following never
# rebuilds there: limine-mkinitcpio outside a pacman transaction runs no
# signing hook of haseen's (§8), and a background rebuild nobody watches is
# no place to find out. The secureboot library is sourced only here, so
# nothing else that sources this file as root (the Omarchy guard's pacman
# hook) reads a directory its trust check did not cover.
plymouth_signed_boot() {
    preflight_firmware
    if [[ $SECUREBOOT_STATE == enabled ]]; then
        echo "Secure Boot is on"
        return 0
    fi
    if [[ $FIRMWARE == uefi && $SECUREBOOT_STATE == unknown ]]; then
        echo "the firmware's Secure Boot state cannot be read"
        return 0
    fi
    # shellcheck source=../layers/secureboot/secureboot.sh
    source "$HASEEN_PATH/layers/secureboot/secureboot.sh"
    if sb_keys_exist; then
        echo "sbctl holds Secure Boot keys"
        return 0
    fi
    if [[ $(sb_limine_value ENABLE_ENROLL_LIMINE_CONFIG) == yes ]]; then
        echo "Limine's config hash is enrolled"
        return 0
    fi
    return 1
}

# plymouth_signed_hint — what to run by hand where following does not.
plymouth_signed_hint() {
    echo "run haseen plymouth set after a theme change (then haseen secureboot sign, with haseen's Secure Boot keys)"
}

# plymouth_follow_trusted — the root unit runs this tree's router as root
# for anyone in wheel, so it is written only when the router, the command it
# routes to and everything that command sources or reads as root are files
# only root can change (root_trusted_haseen): never for a checkout a user
# owns, whose next edit would be root's code. Prints why not.
plymouth_follow_trusted() {
    local dirs=(lib layers/secureboot default/plymouth branding) mark
    for mark in "${BRANDING_MARKS[@]}"; do dirs+=("branding/$mark"); done
    root_trusted_haseen "$PLYMOUTH_HASEEN_BIN" plymouth-apply "${dirs[@]}"
}

# plymouth_follow_unit_render — the root unit with this tree's router and the
# ESP filled in (the rebuild writes there, so a shutdown unmounts it only
# after the unit has stopped).
plymouth_follow_unit_render() {
    [[ -n ${ESP_PATH:-} ]] || preflight_bootloader
    sed -e "s|@HASEEN_BIN@|$PLYMOUTH_HASEEN_BIN|" -e "s|@ESP@|$ESP_PATH|" "$PLYMOUTH_FOLLOW_UNIT_SRC"
}

# plymouth_follow_root_state — "installed", "stale" or "missing": the root
# unit as following would install it. Only the unit: the polkit rule sits in
# /etc/polkit-1/rules.d, which only root and polkitd may list, so a user
# cannot see it; plymouth_follow_enable writes it every time, and a missing
# rule shows as a refused start.
plymouth_follow_root_state() {
    local unit
    unit="$(sysroot_path "$PLYMOUTH_FOLLOW_UNIT")"
    if [[ ! -e $unit ]]; then
        echo missing
    elif cmp -s <(plymouth_follow_unit_render) "$unit"; then
        echo installed
    else
        echo stale
    fi
}

# plymouth_follow_on — the user's timer is enabled (`systemctl --user enable`
# links it into timers.target.wants). Read from the file system, so a theme
# change with following off starts no systemctl at all.
plymouth_follow_on() {
    [[ -L ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/timers.target.wants/$PLYMOUTH_FOLLOW_TIMER ]]
}

# plymouth_follow_poke — a theme or mark changed: restart the timer, so the
# rebuild waits for the theme to settle. Nothing when following is off.
plymouth_follow_poke() {
    plymouth_follow_on || return 0
    run systemctl --user restart --no-block "$PLYMOUTH_FOLLOW_TIMER" ||
        warn "the boot splash was not told about the change (haseen plymouth follow status)"
}

# plymouth_follow_enable — install the root side when it is missing or stale,
# then enable the user's timer (which fires once 2 minutes from now, to catch
# up). Status 3 on a machine that checks its boot files and 4 for a tree root
# does not own, both said; 1 when a step fails. Callers run it as `|| rc=$?`,
# where errexit does not apply, so every step is checked here.
plymouth_follow_enable() {
    local why
    if why="$(plymouth_signed_boot)"; then
        warn "the splash does not follow the theme here: $why, so a rebuild must be signed again; $(plymouth_signed_hint)"
        return 3
    fi
    if ! why="$(plymouth_follow_trusted)"; then
        warn "the splash does not follow the theme: its root service would run $PLYMOUTH_HASEEN_BIN, but $why; install haseen as root (./install.sh)"
        return 4
    fi
    # The rule lets wheel start the rebuild; anyone else is refused at the
    # first request, so say it now.
    if ! id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx wheel; then
        warn "you are not in the wheel group: polkit will refuse the background rebuild (sudo usermod -aG wheel $(id -un), then log in again)"
    fi
    # The unit first, loaded, then the rule: while the rule exists, every name
    # it allows resolves to this template, so systemd refuses a transient
    # unit of that name (unit_is_pristine) whatever polkit says.
    if [[ $(plymouth_follow_root_state) != installed ]]; then
        plymouth_follow_unit_render | write_root_file "$PLYMOUTH_FOLLOW_UNIT" 0644 || return 1
        run_root systemctl daemon-reload || return 1
    fi
    if ! $DRY_RUN && [[ $(plymouth_follow_root_state) != installed ]]; then
        warn "$PLYMOUTH_FOLLOW_UNIT was not written; its polkit rule is not installed"
        return 1
    fi
    # Written every time: a user cannot see whether it is there.
    install_root_file "$PLYMOUTH_FOLLOW_RULE_SRC" "$PLYMOUTH_FOLLOW_RULE" 0644 || return 1
    run systemctl --user enable --now "$PLYMOUTH_FOLLOW_TIMER" || return 1
    # A fresh start: a skipped request is notified again.
    if [[ -e $PLYMOUTH_FOLLOW_RECORD ]]; then
        run rm -f -- "$PLYMOUTH_FOLLOW_RECORD"
    fi
    return 0
}

# plymouth_follow_disable — the timer off, then the rule, then the unit (the
# reverse order of enabling, for the same reason: the unit goes only once the
# rule is gone). Every step is checked, as in plymouth_follow_enable.
plymouth_follow_disable() {
    if plymouth_follow_on; then
        run systemctl --user disable --now "$PLYMOUTH_FOLLOW_TIMER" || return 1
    fi
    # Removed whether or not it is there (a user cannot see it); rm -f fails
    # only when an existing file stays, and then the unit stays too.
    run_root rm -f "$PLYMOUTH_FOLLOW_RULE" || return 1
    if [[ -e $(sysroot_path "$PLYMOUTH_FOLLOW_UNIT") ]]; then
        run_root rm -f "$PLYMOUTH_FOLLOW_UNIT" || return 1
        run_root systemctl daemon-reload || return 1
    fi
    return 0
}

# plymouth_follow_record STATE REQUEST [WHY] — the outcome of a request, for
# `haseen plymouth status` and so a skipped request is notified once.
plymouth_follow_record() {
    printf '%s %s%s\n' "$1" "$2" "${3:+ $3}" | replace_user_file "$PLYMOUTH_FOLLOW_RECORD"
}

# plymouth_follow_last — the last record, or nothing.
plymouth_follow_last() {
    local line=""
    [[ -r $PLYMOUTH_FOLLOW_RECORD ]] && IFS= read -r line <"$PLYMOUTH_FOLLOW_RECORD"
    printf '%s\n' "$line"
}

# plymouth_matches — "yes", "pending" or "no (WHY)": whether the boot image
# carries the current theme's colours and mark (plan 110).
plymouth_matches() {
    local want have last why
    want="$(plymouth_current_request)" || {
        echo "no (no theme is set: haseen theme set NAME)"
        return 0
    }
    have="$(plymouth_built_request)"
    if [[ $want == "$have" ]]; then
        echo yes
        return 0
    fi
    if ! plymouth_theme_ours; then
        echo "no (haseen's splash is not the one plymouthd shows: haseen plymouth set)"
    elif why="$(plymouth_signed_boot)"; then
        echo "no ($why: $(plymouth_signed_hint))"
    elif ! plymouth_follow_on; then
        echo "no (haseen plymouth set, or haseen plymouth follow on)"
    else
        last="$(plymouth_follow_last)"
        if [[ $last == "failed $want"* ]]; then
            echo "no (the rebuild failed: journalctl -b -u 'haseen-splash@*'; haseen plymouth set rebuilds it by hand)"
        else
            echo "pending (rebuilt in the background about 2 minutes after the last theme or mark change)"
        fi
    fi
}

# plymouth_guard_stops — from here on a SIGTERM or SIGINT is held, not obeyed:
# haseen-splash@.service stops with KillMode=mixed, which signals this shell
# alone, and bash runs the trap only once the command it waits for (the
# initramfs rebuild) has returned. The caller checks PLYMOUTH_STOPPED between
# steps: before the rebuild it stops having changed nothing that boots,
# during it the rebuild finishes first. TimeoutStopSec bounds the wait.
# shellcheck disable=SC2034  # read by bin/haseen-plymouth-apply
PLYMOUTH_STOPPED=false
plymouth_guard_stops() {
    trap 'PLYMOUTH_STOPPED=true' TERM INT
}
