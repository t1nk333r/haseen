# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 070: haseen.logo first in bar.left by default (and the migration that
# puts it there for a user with their own bar sections), `haseen bar add`, and
# the default browsers Zen, Chromium, Helium in that order.

DEFAULT="$HASEEN_PATH/default/shell.json"
MIGRATION=1791365994-bar-logo.sh
CFG() { printf '%s' "$XDG_CONFIG_HOME/haseen/shell.json"; }
left() { jq -c '.bar.left' "$(CFG)"; }

# --- the default bar ------------------------------------------------------------
assert_eq "default: the logo is first in bar.left" '"haseen.logo"' "$(jq -c '.bar.left[0]' "$DEFAULT")"
assert_eq "default: the workspaces follow it" '["haseen.logo","haseen.workspaces"]' "$(jq -c '.bar.left' "$DEFAULT")"
assert_eq "default: the logo is not turned off" null "$(jq -c '.plugins["haseen.logo"].enabled' "$DEFAULT")"
assert_contains "AGENTS.md approves the logo" "$(cat "$REPO/AGENTS.md")" "bar: logo"
logo="$HASEEN_PATH/shell/plugins/haseen.logo/Widget.qml"
assert_contains "a click toggles the menu (top level by default)" "$(cat "$logo")" '"call", "menu", "toggle", menuPath'
assert_contains "the mark takes the bar's themed colour" "$(cat "$logo")" "color: root.color"

sandbox logo-state
capture haseen plugin list
assert_status "plugin list exits 0" 0 "$STATUS"
assert_contains "the logo reads as enabled" "$(printf '%s\n' "$OUTPUT" | grep 'haseen.logo')" "enabled"

# --- haseen bar add ---------------------------------------------------------------
sandbox bar-add
f="$REPO/bin/haseen-bar-add"
assert_contains "add takes --dry-run" "$(sed -n 's/^# haseen:args //p' "$f")" "--dry-run"
capture haseen bar add --help
assert_status "add --help exits 0" 0 "$STATUS"
assert_contains "add --help prints usage" "$OUTPUT" "Usage: haseen bar add"
capture haseen commands bar
assert_contains "add is listed with the bar commands" "$OUTPUT" "haseen bar add"

mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"left":["haseen.workspaces"],"right":["haseen.tray","haseen.audio"]},"plugins":{"haseen.logo":{"enabled":false}}}\n' >"$(CFG)"
before="$(cat "$(CFG)")"
capture haseen bar add haseen.logo left --before haseen.workspaces --dry-run
assert_status "add --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "add --dry-run" "$OUTPUT"
assert_contains "add dry run shows the write" "$OUTPUT" "DRYRUN: write $(CFG).new"
assert_contains "add dry run shows the new section" "$OUTPUT" '"haseen.logo",'
assert_eq "add dry run left the file alone" "$before" "$(cat "$(CFG)")"

capture haseen bar add haseen.logo left --before haseen.workspaces
assert_status "add exits 0" 0 "$STATUS"
assert_eq "add: in front of --before" '["haseen.logo","haseen.workspaces"]' "$(left)"
assert_eq "add: turns an off plugin on" true "$(jq '.plugins["haseen.logo"].enabled' "$(CFG)")"
after="$(cat "$(CFG)")"
capture haseen bar add haseen.logo right
assert_status "add refuses a widget already in the bar" 1 "$STATUS"
assert_contains "the refusal points at bar move" "$OUTPUT" "haseen bar move haseen.logo right"
assert_eq "a refused add left the file alone" "$after" "$(cat "$(CFG)")"

capture haseen bar add haseen.weather right --before haseen.tray
assert_status "add to the right" 0 "$STATUS"
assert_eq "add: never in front of the tray" '["haseen.tray","haseen.weather","haseen.audio"]' "$(jq -c '.bar.right' "$(CFG)")"
capture haseen bar add haseen.menu left
assert_status "add refuses a plugin that is not a bar widget" 1 "$STATUS"
capture haseen bar add no.such-plugin left
assert_status "add refuses an unknown plugin" 1 "$STATUS"
capture haseen bar add haseen.logo top
assert_status "add refuses an unknown section" 2 "$STATUS"

# --- the migration ----------------------------------------------------------------
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
assert_eq "the migration is shipped" yes "$([[ -r $HASEEN_PATH/migrations/$MIGRATION ]] && echo yes || echo no)"

sandbox bar-logo-migration
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"left":["haseen.workspaces","me.x"]},"plugins":{"me.x":{"enabled":true}}}\n' >"$(CFG)"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "migration: the logo goes first in a bar lacking it" '["haseen.logo","haseen.workspaces","me.x"]' "$(left)"
assert_eq "migration: the rest of shell.json survives" true "$(jq '.plugins["me.x"].enabled' "$(CFG)")"
after="$(cat "$(CFG)")"
run_migration
assert_eq "migration: a re-run is a no-op" "$after" "$(cat "$(CFG)")"

printf '{"bar":{"left":["haseen.workspaces"],"right":["haseen.tray","haseen.logo"]}}\n' >"$(CFG)"
before="$(cat "$(CFG)")"
run_migration
assert_status "migration with the logo placed exits 0" 0 "$STATUS"
assert_eq "migration: no-op when the logo is already in the bar" "$before" "$(cat "$(CFG)")"

printf '{"bar":{"overflow":["haseen.logo"]}}\n' >"$(CFG)"
before="$(cat "$(CFG)")"
run_migration
assert_eq "migration: no-op when the logo is in the overflow panel" "$before" "$(cat "$(CFG)")"

printf '{"bar":{"height":30}}\n' >"$(CFG)"
before="$(cat "$(CFG)")"
run_migration
assert_eq "migration: no-op when the default sections apply" "$before" "$(cat "$(CFG)")"

rm -f "$(CFG)"
run_migration
assert_status "migration without a shell.json exits 0" 0 "$STATUS"
assert_eq "migration: no shell.json, none written" no "$([[ -e $(CFG) ]] && echo yes || echo no)"

# --- the default browsers -------------------------------------------------------
CATALOG="$HASEEN_PATH/default/catalog.json"
assert_eq "catalog: browsers start Zen, Chromium, Helium" "zen chromium helium" \
    "$(jq -r '[.entries[] | select(.category == "browser") | .id][:3] | join(" ")' "$CATALOG")"
assert_eq "catalog: Helium is helium-browser-bin (Chaotic-AUR; not on Flathub)" "aur helium-browser-bin" \
    "$(jq -r '.entries[] | select(.id == "helium") | "\(.source) \(.ref)"' "$CATALOG")"
assert_eq "menu: default browser choices start Zen, Chromium, Helium" "zen chromium helium" \
    "$(grep -o '"setup\.default\.browser\.[a-z]*"' "$HASEEN_PATH/default/menu.jsonc" | sed 's/.*\.\([a-z]*\)"/\1/' | head -3 | xargs)"
assert_contains "setup default lists them first" "$("$REPO/bin/haseen-setup-default" --help 2>&1 || true)" "browser   zen chromium helium"

sandbox helium-install
ROOT="$SANDBOX/root"
cp -a "$FIXTURES/desk-cachyos-amd" "$ROOT"
mkdir -p "$ROOT/var/lib/pacman/local"
export HASEEN_SYSROOT="$ROOT" HASEEN_INLINE=1
unset HYPRLAND_INSTANCE_SIGNATURE
capture haseen install app helium --dry-run
assert_status "install helium --dry-run exits 0" 0 "$STATUS"
assert_contains "install helium names helium-browser-bin" "$OUTPUT" "helium-browser-bin"
unset HASEEN_SYSROOT HASEEN_INLINE

sandbox default-browser
# Nothing of the live machine's applications: an empty sysroot and data dirs.
mkdir -p "$SANDBOX/root"
export HASEEN_SYSROOT="$SANDBOX/root" XDG_DATA_DIRS="$SANDBOX/root/usr/share"
stub systemctl "exit 0"
stub xdg-settings "exit 0"
stub xdg-mime "exit 0"
capture haseen setup default browser helium --dry-run
assert_contains "helium: xdg-settings gets helium.desktop" "$OUTPUT" "DRYRUN: xdg-settings set default-web-browser helium.desktop"
capture haseen setup default browser zen --dry-run
assert_contains "zen without Flatpak: the native desktop id" "$OUTPUT" "DRYRUN: xdg-settings set default-web-browser zen.desktop"
mkdir -p "$XDG_DATA_HOME/flatpak/exports/share/applications"
: >"$XDG_DATA_HOME/flatpak/exports/share/applications/app.zen_browser.zen.desktop"
capture haseen setup default browser zen --dry-run
assert_contains "zen from Flathub: its app id" "$OUTPUT" "DRYRUN: xdg-mime default app.zen_browser.zen.desktop x-scheme-handler/http"
capture haseen setup default browser zen
stub xdg-settings 'echo app.zen_browser.zen.desktop'
capture haseen setup default browser
assert_eq "current browser: the Flathub zen reads as zen" zen "$OUTPUT"
unset HASEEN_SYSROOT
