# shellcheck shell=bash
# haseen:covers bin/haseen-{hook,hw-apply,layer-apply,migrate,seed-user,setup-nvim,theme-set}
# haseen:covers share/haseen/VERSION share/haseen/branding/** share/haseen/default/**
# haseen:covers share/haseen/hardware/**
# haseen:covers share/haseen/layers/{base,chaotic,desktop,omarchy-repo,shell,theme}/**
# haseen:covers share/haseen/lib/{branding,cairn,greeter,hardware,install-picker,layers,ledger}.sh
# haseen:covers share/haseen/lib/{migrate,packages,preflight,shellrc,terminal,wooting}.sh
# haseen:covers share/haseen/migrations/** share/haseen/seeds/** share/haseen/shell/lib/plugin.sh
# haseen:covers share/haseen/shell/plugins/*/manifest.json share/haseen/systemd/user/**
# haseen:covers share/haseen/themed/** share/haseen/themes/** tests/fixtures/cachyos-grub-plain/**
# haseen:covers install.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The new user-level defaults reach existing users: install.sh seeds on every
# run (fresh or upgrade, never --tree-only), and three migrations cover a HOME
# upgraded without it: the seeds, the theme_hl prefix for the current theme render,
# and a notice about the new key layout. Each is safe to re-run and a no-op
# where there is nothing to do.

SEED_M=1791466288-seed-user.sh
ROUND_M=1791466289-theme-rounding.sh
KEYS_M=1791466290-keybinds-notice.sh

defaults_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    export HASEEN_THEME_HEADLESS=1 HASEEN_THEME_FETCH=0
    export HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain"
    CUR="$HOME/.local/state/haseen/current"
    LEDGER="$HOME/.local/state/haseen/migrations"
}

run_one() { # MIGRATION — the script alone, the way haseen migrate runs it
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$1" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$1"
}

# tree_state DIR — every path under DIR with its checksum, for "nothing changed".
tree_state() {
    (cd "$1" && find . -mindepth 1 -printf '%p %y %l\n' | LC_ALL=C sort &&
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum)
}

# --- install.sh seeds on every run --------------------------------------------
defaults_sandbox defaults-install-fresh
capture "$REPO/install.sh" --dry-run </dev/null
assert_status "fresh install dry run" 0 "$STATUS"
assert_dry_pure "fresh install" "$OUTPUT"
assert_contains "a fresh install seeds the user defaults" "$OUTPUT" "DRYRUN: seed $HOME/.config/btop/btop.conf"
assert_contains "the fontconfig include is planned" "$OUTPUT" "DRYRUN: write $HOME/.config/fontconfig/fonts.conf:"
assert_contains "the rc include is planned" "$OUTPUT" "DRYRUN: append to $HOME/.bashrc:"
assert_contains "the new migrations are sealed on a fresh HOME" "$OUTPUT" "DRYRUN: record migrations $SEED_M (sealed)"

defaults_sandbox defaults-install-upgrade
mkdir -p "$HOME/.config/haseen"
printf '{}\n' >"$HOME/.config/haseen/shell.json"
capture "$REPO/install.sh" --dry-run </dev/null
assert_status "upgrade dry run" 0 "$STATUS"
assert_dry_pure "upgrade install" "$OUTPUT"
assert_contains "an upgrade seeds the user defaults too" "$OUTPUT" "DRYRUN: seed $HOME/.config/btop/btop.conf"
assert_contains "an upgrade runs the seed migration" "$OUTPUT" "DRYRUN: run migration $SEED_M"
assert_contains "an upgrade runs the rounding migration" "$OUTPUT" "DRYRUN: run migration $ROUND_M"
assert_contains "an upgrade runs the keybinds notice" "$OUTPUT" "DRYRUN: run migration $KEYS_M"

defaults_sandbox defaults-install-tree-only
capture "$REPO/install.sh" --dry-run --tree-only </dev/null
assert_status "tree-only dry run" 0 "$STATUS"
assert_not_contains "--tree-only seeds nothing (the migration does, later)" "$OUTPUT" "DRYRUN: seed "

# --- the seed migration -----------------------------------------------------------
defaults_sandbox defaults-seed
mkdir -p "$HOME/.config/tmux"
printf 'set -g prefix C-a # mine\n' >"$HOME/.config/tmux/tmux.conf"
run_one "$SEED_M"
assert_status "seed migration" 0 "$STATUS"
assert_eq "fonts.conf seeded" "yes" "$([[ -f $HOME/.config/fontconfig/fonts.conf ]] && echo yes || echo no)"
assert_contains "the rc include is in ~/.bashrc" "$(cat "$HOME/.bashrc")" "default/shell/init.sh"
assert_eq "yazi seeded" "yes" "$([[ -e $HOME/.config/yazi/yazi.toml ]] && echo yes || echo no)"
assert_eq "the user's own tmux.conf is untouched" "set -g prefix C-a # mine" "$(cat "$HOME/.config/tmux/tmux.conf")"
before="$(tree_state "$HOME")"
run_one "$SEED_M"
assert_status "seed migration re-run" 0 "$STATUS"
assert_eq "a re-run changes nothing" "$before" "$(tree_state "$HOME")"
assert_eq "one rc include after two runs" 1 "$(grep -c 'default/shell/init.sh' "$HOME/.bashrc")"

# A seed that fails does not fail the migration: later migrations still run.
defaults_sandbox defaults-seed-readonly
printf '# mine\n' >"$HOME/.bashrc"
chmod 0444 "$HOME/.bashrc"
run_one "$SEED_M"
assert_status "a failing seed does not fail the migration" 0 "$STATUS"
assert_contains "the failed seed is named" "$OUTPUT" "60-shell.sh"
assert_contains "and how to retry" "$OUTPUT" "run: haseen seed user"
assert_eq "the other seeds are in place" "yes" "$([[ -e $HOME/.config/yazi/yazi.toml ]] && echo yes || echo no)"
chmod 0644 "$HOME/.bashrc"

# --- the rounding migration ------------------------------------------------------
defaults_sandbox defaults-round-none
run_one "$ROUND_M"
assert_status "no theme: nothing to do" 0 "$STATUS"
assert_eq "no theme: nothing written" "" "$(ls -A "$HOME")"

# old_render THEME — a current/theme rendered before plan 046: no theme_hl
# prefix, and hyprland.lua carries its own rounding.
old_render() {
    haseen theme set "$1" >/dev/null 2>&1
    rm -f "$CUR/theme/rounding.lua"
    printf 'hl.config({ decoration = { rounding = 4 } })\n' >"$CUR/theme/hyprland.lua"
}

# The migration adds the theme_hl prefix and changes nothing else: a
# background the user picked outside the theme stays (theme set would relink
# it), and no GTK or nvim link is written. Since plan 114 it writes no
# rounding.lua: the corners are the theme's.
defaults_sandbox defaults-round-old
old_render gruvbox
mkdir -p "$HOME/Pictures"
: >"$HOME/Pictures/mine.png"
ln -sfn "$HOME/Pictures/mine.png" "$CUR/background"
rm -f "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
before_home="$(cd "$HOME" && find . -path ./.local/state/haseen/current -prune -o -print | LC_ALL=C sort)"
run_one "$ROUND_M"
assert_status "old render migrated" 0 "$STATUS"
assert_eq "no rounding.lua written (plan 114)" "no" "$([[ -e $CUR/theme/rounding.lua ]] && echo yes || echo no)"
assert_contains "the theme's hyprland.lua is prefixed" "$(head -2 "$CUR/theme/hyprland.lua")" "haseen.theme_hl(hl)"
assert_contains "the theme's own rounding is kept below the prefix" "$(cat "$CUR/theme/hyprland.lua")" "rounding = 4"
assert_eq "the same theme stays current" "gruvbox" "$(cat "$CUR/theme.name")"
assert_eq "the user's background survives" "$HOME/Pictures/mine.png" "$(readlink "$CUR/background")"
assert_eq "nothing else in HOME changed (no gtk.css, no nvim link)" "$before_home" \
    "$(cd "$HOME" && find . -path ./.local/state/haseen/current -prune -o -print | LC_ALL=C sort)"
printf 'marker\n' >"$CUR/theme/.unchanged"
before="$(tree_state "$CUR")"
run_one "$ROUND_M"
assert_status "re-run" 0 "$STATUS"
assert_eq "a prefixed render is left alone" "$before" "$(tree_state "$CUR")"

# A render from `haseen theme set` today is already prefixed: nothing to do.
defaults_sandbox defaults-round-new
haseen theme set gruvbox >/dev/null 2>&1
before="$(tree_state "$CUR")"
run_one "$ROUND_M"
assert_status "a current render: nothing to do" 0 "$STATUS"
assert_eq "a current render is left alone" "$before" "$(tree_state "$CUR")"

# Only the current render is read, so a theme removed since still gets it.
defaults_sandbox defaults-round-renamed
old_render gruvbox
printf 'no-such-theme\n' >"$CUR/theme.name"
run_one "$ROUND_M"
assert_status "a theme no longer installed: migrated" 0 "$STATUS"
assert_contains "a theme no longer installed: prefixed" "$(head -2 "$CUR/theme/hyprland.lua")" "haseen.theme_hl(hl)"

# A render without colors.toml still gets the prefix: nothing in it is read.
defaults_sandbox defaults-round-broken
old_render gruvbox
rm -f "$CUR/theme/colors.toml"
run_one "$ROUND_M"
assert_status "a render without colors.toml: migrated" 0 "$STATUS"
assert_contains "a render without colors.toml: prefixed" "$(head -2 "$CUR/theme/hyprland.lua")" "haseen.theme_hl(hl)"

# --- the keybinds notice ------------------------------------------------------------
defaults_sandbox defaults-keys
mkdir -p "$HOME/.config"
before="$(tree_state "$HOME")"
run_one "$KEYS_M"
assert_status "keybinds notice" 0 "$STATUS"
assert_contains "names the new sheet key" "$OUTPUT" "SUPER + F1 opens the keybindings sheet (was SUPER + /)"
assert_contains "names the new clipboard key" "$OUTPUT" "ALT + V opens clipboard history (was SUPER + CTRL + V)"
assert_contains "says how to resolve a double bind" "$OUTPUT" "hl.unbind()"
assert_eq "the notice writes nothing" "$before" "$(tree_state "$HOME")"
# Every key the notice names is a key binds.lua binds.
binds="$(cat "$HASEEN_PATH/default/hypr/binds.lua")"
for key in '"SUPER + F1"' '"ALT + V"' '"SUPER + Q"' '"ALT + J"' '"ALT + L"' 'HYPER .. "G"' 'HYPER .. "BACKSLASH"'; do
    assert_contains "binds.lua binds $key" "$binds" "$key"
done
assert_not_contains "SUPER + SLASH is gone" "$binds" '"SUPER + SLASH"'

# --- all three through haseen migrate, in an upgraded HOME --------------------------
defaults_sandbox defaults-migrate
old_render haseen
capture haseen migrate
assert_status "haseen migrate" 0 "$STATUS"
for m in "$SEED_M" "$ROUND_M" "$KEYS_M"; do
    assert_contains "$m recorded as applied" "$(cat "$LEDGER/$m" 2>/dev/null)" "applied"
done
assert_eq "seeded through migrate" "yes" "$([[ -f $HOME/.config/fontconfig/fonts.conf ]] && echo yes || echo no)"
assert_contains "prefixed through migrate" "$(head -2 "$CUR/theme/hyprland.lua")" "haseen.theme_hl(hl)"
capture haseen migrate
assert_contains "a second run has nothing pending" "$OUTPUT" "no pending migrations"
