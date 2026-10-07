# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 066: greek-noir-akane became haseen's own theme `haseen`, the default.
# The old name still sets it (with a notice), an old theme.name reads as
# haseen, the old background folder is still found, the migration renames
# both for a user on the old name only, and install.sh runs migrations for
# any existing haseen HOME (sealing them only in a fresh one).

MIGRATION=1791356361-theme-haseen.sh

haseen_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    export HASEEN_THEME_HEADLESS=1 HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run"
    export HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain"
    CUR="$HOME/.local/state/haseen/current"
    BGS="$HOME/.config/haseen/backgrounds"
    LEDGER="$HOME/.local/state/haseen/migrations"
}

# old_user THEME — a HOME from before plan 066: THEME current, the owner's
# images in backgrounds/greek-noir-akane/, current/background on one of them.
old_user() {
    mkdir -p "$BGS/greek-noir-akane"
    printf 'jpg' >"$BGS/greek-noir-akane/1-akane.jpg"
    printf 'jpg' >"$BGS/greek-noir-akane/2-akane.jpg"
    haseen theme set gruvbox >/dev/null 2>&1
    printf '%s\n' "$1" >"$CUR/theme.name"
    ln -nsf "$BGS/greek-noir-akane/1-akane.jpg" "$CUR/background"
}

# --- the theme --------------------------------------------------------------
theme="$HASEEN_PATH/themes/haseen"
assert_eq "greek-noir-akane is no longer a separate theme" "no" "$([[ -e $HASEEN_PATH/themes/greek-noir-akane ]] && echo yes || echo no)"
assert_contains "the Greek Noir licence is kept" "$(cat "$theme/LICENSE")" "Copyright (c) 2026 HANCORE"
assert_contains "UPSTREAM credits HANCORE's Greek Noir" "$(cat "$theme/UPSTREAM.md")" "HANCORE-linux/omarchy-greek-noir-theme"
assert_contains "colors.toml names its origin" "$(head -5 "$theme/colors.toml")" "HANCORE's Greek Noir (MIT"
assert_contains "NOTICE lists the theme under its new path" "$(cat "$REPO/NOTICE.md")" '`share/haseen/themes/haseen/`'

haseen_sandbox theme-haseen-set
capture haseen theme set haseen
assert_status "set haseen" 0 "$STATUS"
assert_eq "theme.name" "haseen" "$(cat "$CUR/theme.name")"
assert_eq "the shell selection stays readable" "#864313" "$(jq -r .selection "$CUR/theme/shell.json")"
assert_eq "the menu rounds like haseen's windows" "4" "$(jq -r .windowRadius "$CUR/theme/shell.json")"

# --- Theme.qml falls back to the haseen palette -----------------------------
qml="$HASEEN_PATH/shell/Haseen/Theme.qml"
while IFS=$'\t' read -r key value; do
    if [[ $value =~ ^[0-9]+$ ]]; then
        assert_contains "Theme.qml fallback $key = haseen's $value" "$(cat "$qml")" "            $key: $value"
    else
        assert_contains "Theme.qml fallback $key = haseen's $value" "$(cat "$qml")" "            $key: \"$value\""
    fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$CUR/theme/shell.json")

# --- the old name is an alias -------------------------------------------------
haseen_sandbox theme-haseen-alias
capture haseen theme set Greek-Noir-Akane
assert_status "the old name sets the theme" 0 "$STATUS"
assert_contains "with a one-line notice" "$OUTPUT" "theme 'greek-noir-akane' is now called 'haseen'"
assert_eq "theme.name is the new name" "haseen" "$(cat "$CUR/theme.name")"
capture haseen theme set greek-noir-akane --dry-run
assert_contains "dry run plans the new name" "$OUTPUT" "DRYRUN: write $CUR/theme.name: haseen"
printf 'greek-noir-akane\n' >"$CUR/theme.name"
assert_eq "an old theme.name reads as haseen (stdout)" "haseen" "$(haseen theme current 2>/dev/null)"
capture haseen theme current
assert_contains "and says so" "$OUTPUT" "is now called 'haseen'"

# A user theme of the old name is the user's own: no alias.
haseen_sandbox theme-haseen-user-old
mkdir -p "$HOME/.config/haseen/themes/greek-noir-akane"
cp "$theme/colors.toml" "$HOME/.config/haseen/themes/greek-noir-akane/"
capture haseen theme set greek-noir-akane
assert_not_contains "a user theme of the old name is not aliased" "$OUTPUT" "is now called"
assert_eq "it is set under its own name" "greek-noir-akane" "$(cat "$CUR/theme.name")"

# --- backgrounds under the old folder are still found ------------------------
haseen_sandbox theme-haseen-bg
mkdir -p "$BGS/greek-noir-akane"
printf 'jpg' >"$BGS/greek-noir-akane/1-akane.jpg"
haseen theme set haseen >/dev/null 2>&1
assert_eq "haseen links an image from backgrounds/greek-noir-akane" "$BGS/greek-noir-akane/1-akane.jpg" "$(readlink "$CUR/background")"
mkdir -p "$BGS/haseen"
printf 'png' >"$BGS/haseen/a.png"
assert_eq "backgrounds/haseen first, then the old folder" \
    "$BGS/haseen/a.png"$'\n'"$BGS/greek-noir-akane/1-akane.jpg" "$(haseen theme bg list 2>/dev/null)"

# --- the migration --------------------------------------------------------------
haseen_sandbox theme-haseen-migrate
old_user greek-noir-akane
capture haseen migrate --pending
assert_contains "the rename is a pending migration" "$OUTPUT" "$MIGRATION"
capture haseen migrate
assert_status "migrate" 0 "$STATUS"
assert_eq "theme.name renamed" "haseen" "$(cat "$CUR/theme.name")"
assert_eq "background folder moved" "1-akane.jpg 2-akane.jpg" "$(ls "$BGS/haseen" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "old folder gone" "no" "$([[ -e $BGS/greek-noir-akane ]] && echo yes || echo no)"
assert_eq "the same image still shows" "$BGS/haseen/1-akane.jpg" "$(readlink "$CUR/background")"
assert_contains "recorded as applied" "$(cat "$LEDGER/$MIGRATION")" "applied"
capture haseen migrate
assert_contains "a second run has nothing pending" "$OUTPUT" "no pending migrations"
capture env HASEEN_MIGRATION="$MIGRATION" bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
assert_status "re-running the script itself" 0 "$STATUS"
assert_eq "re-run: theme.name" "haseen" "$(cat "$CUR/theme.name")"
assert_eq "re-run: link" "$BGS/haseen/1-akane.jpg" "$(readlink "$CUR/background")"
assert_eq "re-run: folder" "1-akane.jpg 2-akane.jpg" "$(ls "$BGS/haseen" | tr '\n' ' ' | sed 's/ $//')"

# Any other current theme: nothing moves.
haseen_sandbox theme-haseen-migrate-other
old_user gruvbox
capture haseen migrate
assert_status "migrate on gruvbox" 0 "$STATUS"
assert_eq "theme.name kept" "gruvbox" "$(cat "$CUR/theme.name")"
assert_eq "old folder kept" "yes" "$([[ -d $BGS/greek-noir-akane && ! -e $BGS/haseen ]] && echo yes || echo no)"
assert_eq "link kept" "$BGS/greek-noir-akane/1-akane.jpg" "$(readlink "$CUR/background")"

# backgrounds/haseen already there: it is not overwritten, the old folder stays.
haseen_sandbox theme-haseen-migrate-both
old_user greek-noir-akane
mkdir -p "$BGS/haseen"
printf 'png' >"$BGS/haseen/mine.png"
capture haseen migrate
assert_status "migrate with both folders" 0 "$STATUS"
assert_eq "theme.name renamed" "haseen" "$(cat "$CUR/theme.name")"
assert_eq "backgrounds/haseen untouched" "mine.png" "$(ls "$BGS/haseen")"
assert_eq "old folder and link kept" "$BGS/greek-noir-akane/1-akane.jpg" "$(readlink "$CUR/background")"

# --- install.sh: seal only in a fresh HOME ------------------------------------
haseen_sandbox theme-haseen-install-fresh
capture "$REPO/install.sh" --dry-run </dev/null
assert_status "fresh install dry run" 0 "$STATUS"
assert_contains "a fresh HOME plans the default theme" "$OUTPUT" "DRYRUN: write $CUR/theme.name: haseen"
assert_contains "a fresh HOME seals the migration" "$OUTPUT" "DRYRUN: record migrations $MIGRATION (sealed)"
assert_not_contains "a fresh HOME runs none" "$OUTPUT" "DRYRUN: run migration"

haseen_sandbox theme-haseen-install-theme
old_user greek-noir-akane
capture "$REPO/install.sh" --dry-run </dev/null
assert_status "upgrade dry run (theme.name, no ledger)" 0 "$STATUS"
assert_contains "an existing theme.name runs the migration" "$OUTPUT" "DRYRUN: run migration $MIGRATION"
assert_not_contains "and seals nothing" "$OUTPUT" "(sealed)"

haseen_sandbox theme-haseen-install-shell
mkdir -p "$HOME/.config/haseen"
printf '{}\n' >"$HOME/.config/haseen/shell.json"
capture "$REPO/install.sh" --dry-run </dev/null
assert_contains "an existing shell.json runs the migration" "$OUTPUT" "DRYRUN: run migration $MIGRATION"
