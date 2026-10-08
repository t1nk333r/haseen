# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The boot splash: the colours come from the current theme, the hook and the
# kernel command line are what decide whether it is ever seen, and status says
# which of those is missing.
sandbox plymouth

sysroot="$SANDBOX/sysroot"
mkdir -p "$sysroot/etc/mkinitcpio.conf.d" "$sysroot/etc/plymouth" "$sysroot/proc" \
    "$SANDBOX/state/haseen/current/theme" "$sysroot/boot/EFI"
export HASEEN_SYSROOT="$sysroot" XDG_STATE_HOME="$SANDBOX/state"

cat >"$SANDBOX/state/haseen/current/theme/colors.toml" <<'EOF'
mode = "dark"
accent = "#dcd7ba"
background = "#1f1f28"
foreground = "#dcd7ba"
EOF
printf 'HOOKS=(base udev autodetect modconf block encrypt filesystems fsck)\n' \
    >"$sysroot/etc/mkinitcpio.conf"
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw\n' >"$sysroot/proc/cmdline"
# plymouth_installed looks in the sysroot, so this is what "installed" means.
mkdir -p "$sysroot/usr/bin"
printf '#!/bin/sh\nexit 0\n' >"$sysroot/usr/bin/plymouth-set-default-theme"
chmod +x "$sysroot/usr/bin/plymouth-set-default-theme"
stub plymouth-set-default-theme 'exit 0'
stub mkinitcpio 'exit 0'
stub bootctl 'echo "System: ..."; exit 0'

# --- status before anything is set up -----------------------------------------
capture haseen plymouth status
assert_contains "no theme is set yet" "$OUTPUT" "theme:"
assert_contains "the hook is missing" "$OUTPUT" "missing from HOOKS"
assert_contains "and so is splash" "$OUTPUT" "no 'splash'"
assert_contains "so it is not ready" "$OUTPUT" "ready:     no"

# --- what `plymouth set` plans ------------------------------------------------
capture haseen plymouth set --dry-run
assert_dry_pure "plymouth set dry run" "$OUTPUT"
assert_contains "it reads the theme's colours" "$OUTPUT" "background #1f1f28"
assert_contains "it installs the theme descriptor" "$OUTPUT" "/usr/share/plymouth/themes/haseen/haseen.plymouth"
assert_contains "and the script" "$OUTPUT" "/usr/share/plymouth/themes/haseen/haseen.script"
assert_contains "it adds the initramfs hook" "$OUTPUT" "haseen-plymouth.conf"
assert_contains "sets the default theme" "$OUTPUT" "plymouth-set-default-theme haseen"
assert_contains "puts splash on the command line" "$OUTPUT" "quiet splash"
assert_contains "and rebuilds the initramfs" "$OUTPUT" "mkinitcpio -P"
assert_contains "it renders the selected mark in the accent (plan 059)" "$OUTPUT" "render $HASEEN_PATH/branding/kufic/mark.svg in #dcd7ba -> logo.png (mark: kufic)"
assert_contains "and installs it beside the script" "$OUTPUT" "/usr/share/plymouth/themes/haseen/logo.png"
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo '{"branding": {"mark": "gate"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen plymouth set --dry-run
assert_contains "a mark change reaches the splash" "$OUTPUT" "branding/gate/mark.svg"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"

capture haseen plymouth set --theme kanagawa --dry-run
assert_contains "a named theme is used instead" "$OUTPUT" "background #1f1f28"
capture haseen plymouth set --theme nosuchtheme --dry-run
assert_status "an unknown theme is refused" 1 "$STATUS"

capture haseen plymouth set --dry-run --no-rebuild
assert_not_contains "--no-rebuild skips mkinitcpio" "$OUTPUT" "mkinitcpio -P"
assert_contains "and says what is left to do" "$OUTPUT" "regenerate it yourself"

# --- the script that actually gets installed ----------------------------------
script="$(HASEEN_SYSROOT="$sysroot" bash -c '
    source "'"$REPO"'/share/haseen/lib/plymouth.sh"
    read -r bg fg accent <<<"$(plymouth_theme_colors "'"$SANDBOX"'/state/haseen/current/theme/colors.toml")"
    plymouth_script "$bg" "$fg" "$accent"')"
assert_not_contains "no placeholder survives" "$script" "@@"
# #1f1f28 -> 31/255 = 0.122, 40/255 = 0.157
assert_contains "the background is the theme's, as plymouth floats" "$script" "bg_r = 0.122"
assert_contains "and its blue channel too" "$script" "bg_b = 0.157"
assert_contains "the password prompt is drawn by the theme" "$script" "SetDisplayPasswordFunction"
assert_not_contains "boot messages are not drawn: the splash shows no text" "$script" "SetMessageFunction"

# --- the hook is evaluated the way mkinitcpio does it -------------------------
printf 'HOOKS=(base systemd plymouth autodetect)\n' >"$sysroot/etc/mkinitcpio.conf.d/zz.conf"
capture haseen plymouth status
assert_contains "a drop-in that adds the hook counts" "$OUTPUT" "plymouth is in HOOKS"
capture haseen plymouth set --dry-run
assert_not_contains "and the hook is not added twice" "$OUTPUT" "haseen-plymouth.conf"
rm -f "$sysroot/etc/mkinitcpio.conf.d/zz.conf"

# --- a machine that already boots with splash ---------------------------------
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw quiet splash\n' >"$sysroot/proc/cmdline"
printf 'Theme=haseen\n' >"$sysroot/etc/plymouth/plymouthd.conf"
mkdir -p "$sysroot/usr/share/plymouth/themes/haseen"
touch "$sysroot/usr/share/plymouth/themes/haseen/haseen.script"
printf 'HOOKS=(base udev plymouth autodetect)\n' >"$sysroot/etc/mkinitcpio.conf"
capture haseen plymouth status
assert_contains "the theme is reported" "$OUTPUT" "theme:     haseen"
assert_contains "the splash will show" "$OUTPUT" "ready:     yes"
capture haseen plymouth set --dry-run
assert_not_contains "and the command line is left alone" "$OUTPUT" "quiet splash"

# --- without plymouth installed -----------------------------------------------
rm -f "$sysroot/usr/bin/plymouth-set-default-theme"
capture haseen plymouth status
assert_contains "status says plymouth is absent" "$OUTPUT" "not installed"
capture haseen plymouth set --dry-run
assert_status "and set refuses" 1 "$STATUS"
