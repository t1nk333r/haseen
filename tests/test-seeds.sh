# shellcheck shell=bash
# Config seeds: btop, fcitx5, the input-method environment and XCompose into
# $HOME; the udev rule and the snapper policy through the privileged helpers.
sandbox seeds

CONFIG="$HOME/.config"
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"

# --- user seeds: the plan ----------------------------------------------------
capture haseen seed user --dry-run
assert_status "a user seed dry run succeeds" 0 "$STATUS"
assert_dry_pure "user seed dry run" "$OUTPUT"
assert_contains "btop.conf is planned" "$OUTPUT" "DRYRUN: seed $CONFIG/btop/btop.conf"
assert_contains "the btop theme link is planned" "$OUTPUT" \
    "DRYRUN: ln -snf $HOME/.local/state/haseen/current/theme/btop.theme $CONFIG/btop/themes/current.theme"
assert_contains "the fcitx5 hotkeys are planned" "$OUTPUT" "DRYRUN: seed $CONFIG/fcitx5/config"
assert_contains "the fcitx5 group is planned" "$OUTPUT" "DRYRUN: seed $CONFIG/fcitx5/profile"
assert_contains "the fcitx5 addon configs are planned" "$OUTPUT" "DRYRUN: seed $CONFIG/fcitx5/conf/xcb.conf"
assert_contains "the input-method environment is planned" "$OUTPUT" \
    "DRYRUN: seed $CONFIG/environment.d/10-haseen-fcitx.conf"
assert_contains "XCompose is planned with its content" "$OUTPUT" "DRYRUN: write $HOME/.XCompose"
assert_contains "the XCompose plan includes haseen's sequences" "$OUTPUT" \
    "include \"$REPO/share/haseen/default/xcompose/compose\""
assert_eq "the dry run wrote nothing" "" "$(find "$HOME" -type f -o -type l | sort | tr '\n' ' ')"

# --- user seeds: applied -----------------------------------------------------
capture haseen seed user
assert_status "seeding succeeds" 0 "$STATUS"
assert_contains "the user is told to log in again" "$OUTPUT" "log out and back in"

assert_eq "btop.conf landed" "yes" "$([[ -f $CONFIG/btop/btop.conf ]] && echo yes)"
assert_contains "btop uses the theme pipeline's theme" "$(cat "$CONFIG/btop/btop.conf")" 'color_theme = "current"'
assert_contains "btop polls no faster than 2 s" "$(cat "$CONFIG/btop/btop.conf")" "update_ms = 2000"
assert_not_contains "the seed carries no colours of its own" "$(cat "$CONFIG/btop/btop.conf")" "theme[main_bg]"
assert_eq "the btop theme link points at the rendered theme" \
    "$HOME/.local/state/haseen/current/theme/btop.theme" \
    "$(readlink "$CONFIG/btop/themes/current.theme")"

profile="$(cat "$CONFIG/fcitx5/profile")"
assert_contains "English is in the group" "$profile" "Name=keyboard-us"
assert_contains "Arabic is in the group" "$profile" "Name=keyboard-ara"
assert_contains "the group starts in English" "$profile" "DefaultIM=keyboard-us"
config="$(cat "$CONFIG/fcitx5/config")"
assert_contains "Control+space switches script" "$config" $'[Hotkey/TriggerKeys]\n0=Control+space'
assert_not_contains "the switch key does not take Hyprland's SUPER+SPACE" "$config" "Super+space"
assert_contains "fcitx5 keeps Hyprland's XKB layout" "$(cat "$CONFIG/fcitx5/conf/xcb.conf")" \
    "Allow Overriding System XKB Settings=False"
assert_contains "the clipboard addon claims no key" "$(cat "$CONFIG/fcitx5/conf/clipboard.conf")" "TriggerKey="

env_file="$(cat "$CONFIG/environment.d/10-haseen-fcitx.conf")"
assert_contains "Qt apps find fcitx" "$env_file" "QT_IM_MODULE=fcitx"
assert_contains "X11 apps find fcitx" "$env_file" "XMODIFIERS=@im=fcitx"
assert_eq "GTK is left to the Wayland text-input protocol" "" \
    "$(grep -c '^GTK_IM_MODULE' "$CONFIG/environment.d/10-haseen-fcitx.conf" | tr -d '0')"

compose="$(cat "$HOME/.XCompose")"
assert_contains "XCompose keeps the locale's sequences" "$compose" 'include "%L"'
assert_contains "XCompose includes haseen's file" "$compose" \
    "include \"$REPO/share/haseen/default/xcompose/compose\""
assert_contains "haseen's sequences carry Arabic punctuation" \
    "$(cat "$REPO/share/haseen/default/xcompose/compose")" "<Multi_key> <a> <question>"

# --- a seeded file belongs to the user --------------------------------------
echo "# mine" >"$CONFIG/btop/btop.conf"
echo "# mine too" >"$HOME/.XCompose"
capture haseen seed user
assert_status "a second run succeeds" 0 "$STATUS"
assert_eq "an edited btop.conf is never overwritten" "# mine" "$(cat "$CONFIG/btop/btop.conf")"
assert_eq "an edited XCompose is never overwritten" "# mine too" "$(cat "$HOME/.XCompose")"
capture haseen seed user --dry-run
assert_eq "a re-run plans nothing" "" "$(grep -c DRYRUN <<<"$OUTPUT" | tr -d '0')"

capture haseen seed user bogus
assert_status "an unexpected argument is rejected" 2 "$STATUS"
capture haseen seed user --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help names the files" "$OUTPUT" ".XCompose"

# --- system seeds: a Framework laptop on btrfs -------------------------------
export HASEEN_SYSROOT="$FIXTURES/seeds-framework"
capture haseen seed system --dry-run
assert_status "a system seed dry run succeeds" 0 "$STATUS"
assert_dry_pure "system seed dry run" "$OUTPUT"
assert_contains "the udev rule is installed as root" "$OUTPUT" \
    "DRYRUN: sudo install -Dm0644 $REPO/share/haseen/default/udev/framework-qmk-hid.rules /etc/udev/rules.d/50-haseen-framework-qmk-hid.rules"
assert_contains "udev is reloaded as root" "$OUTPUT" "DRYRUN: sudo udevadm control --reload"
assert_contains "the snapper config is created as root" "$OUTPUT" \
    "DRYRUN: sudo snapper --no-dbus -c root create-config /"
assert_contains "the retention policy is installed as root" "$OUTPUT" \
    "DRYRUN: sudo install -Dm0644 $REPO/share/haseen/default/snapper/root /etc/snapper/configs/root"
assert_contains "the snapper default config list is written as root" "$OUTPUT" \
    'DRYRUN: write /etc/conf.d/snapper (mode 0644)'
assert_contains "the plan shows what lands in /etc/conf.d/snapper" "$OUTPUT" '| SNAPPER_CONFIGS="root"'
assert_contains "the timeline timer is turned off" "$OUTPUT" \
    "DRYRUN: sudo systemctl disable --now snapper-timeline.timer"
assert_contains "the cleanup timer is turned on" "$OUTPUT" \
    "DRYRUN: sudo systemctl enable --now snapper-cleanup.timer"
assert_contains "the limine sync unit is enabled where it exists" "$OUTPUT" \
    "DRYRUN: sudo systemctl enable --now limine-snapper-sync.service"
assert_contains "no timeline in the policy itself" \
    "$(cat "$REPO/share/haseen/default/snapper/root")" 'TIMELINE_CREATE="no"'

# --- system seeds: other hardware, no btrfs ----------------------------------
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
capture haseen seed system --dry-run
assert_status "a plain machine succeeds" 0 "$STATUS"
assert_dry_pure "plain machine dry run" "$OUTPUT"
assert_contains "the Framework rule is skipped elsewhere" "$OUTPUT" "not a Framework machine"
assert_not_contains "nothing lands in /etc/udev on other hardware" "$OUTPUT" "udev/rules.d"
assert_contains "an ext4 root gets no snapshot policy" "$OUTPUT" "/ is not btrfs"
assert_not_contains "and no snapper call either" "$OUTPUT" "snapper"

# --- system seeds: already applied -------------------------------------------
SYS="$SANDBOX/sysroot"
mkdir -p "$SYS/etc/udev/rules.d" "$SYS/etc/snapper/configs" "$SYS/sys/class/dmi/id"
cp "$FIXTURES/seeds-framework/etc/fstab" "$SYS/etc/fstab"
cp "$FIXTURES/seeds-framework/sys/class/dmi/id/sys_vendor" "$SYS/sys/class/dmi/id/sys_vendor"
cp "$REPO/share/haseen/default/udev/framework-qmk-hid.rules" \
    "$SYS/etc/udev/rules.d/50-haseen-framework-qmk-hid.rules"
cp "$REPO/share/haseen/default/snapper/root" "$SYS/etc/snapper/configs/root"
export HASEEN_SYSROOT="$SYS"
capture haseen seed system --dry-run
assert_status "an applied machine succeeds" 0 "$STATUS"
assert_dry_pure "applied machine dry run" "$OUTPUT"
assert_contains "an installed udev rule is left alone" "$OUTPUT" "is already installed"
assert_not_contains "and is not re-installed" "$OUTPUT" "install -Dm0644 $REPO/share/haseen/default/udev"
assert_contains "an applied policy is left alone" "$OUTPUT" "already carries haseen's policy"
assert_not_contains "and snapper is not asked to create a config" "$OUTPUT" "create-config"
assert_not_contains "no limine unit on a machine without it" "$OUTPUT" "limine-snapper-sync"

capture haseen seed system bogus
assert_status "an unexpected argument is rejected" 2 "$STATUS"
capture haseen seed system --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help names the snapper policy" "$OUTPUT" "/etc/snapper/configs/root"

# --- the router knows both ---------------------------------------------------
capture haseen commands seed
assert_contains "seed user is listed" "$OUTPUT" "haseen seed user"
assert_contains "seed system is listed" "$OUTPUT" "haseen seed system"
