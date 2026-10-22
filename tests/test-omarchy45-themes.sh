# shellcheck shell=bash
# haseen:covers bin/haseen-theme-{bg,fetch,set} NOTICE.md
# haseen:covers share/haseen/layers/theme/{omarchy-assets.txt,theme-lib.sh}
# haseen:covers share/haseen/migrations/1792681032-tokyo-night-liftoff.sh
# haseen:covers share/haseen/themes/starship/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Themes from Omarchy 4.5 (plan 106): the Starship theme ships its colours
# only; the image pin moves to v4.5.0-rc1 (Starship's photographs, Liftoff
# first in Tokyo Night); each theme gets back the background it last showed,
# through every way a theme becomes current; migration 1792681032 renames
# the cached Tokyo Night copies and the picks that name them.

PIN=03ff1eff3812933f7088484533784d2f63eaf19a
MIGRATION=1792681032-tokyo-night-liftoff.sh

themes_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE HASEEN_THEME_MIRROR HASEEN_USER_CACHE
    export HASEEN_THEME_HEADLESS=1 HASEEN_THEME_FETCH=0
    CUR="$HOME/.local/state/haseen/current"
    MEM="$HOME/.local/state/haseen/theme-backgrounds"
    BGS="$HOME/.config/haseen/backgrounds"
    CACHE="$HOME/.cache/haseen/themes"
}

# img FILE [BYTES] — the smallest bytes `file` types as a PNG.
img() {
    mkdir -p "${1%/*}"
    printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\x08\x06\0\0\0\x1f\x15\xc4\x89%s' "${2:-x}" >"$1"
}
shown() { readlink "$CUR/background" 2>/dev/null || true; }
remembered() { cat "$MEM/$1" 2>/dev/null || true; }

# --- Starship: colours only, never the photographs ---------------------------
star="$HASEEN_PATH/themes/starship"
assert_eq "Starship ships colours and its licence only" "LICENSE colors.toml" "$(ls "$star" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
assert_contains "the palette is Omarchy's" "$(cat "$star/colors.toml")" 'accent = "#ff9f0a"'
assert_contains "the palette names its origin" "$(head -6 "$star/colors.toml")" "Starship To Orbit"
assert_contains "Erik Johansson's notice is kept" "$(cat "$star/LICENSE")" "Copyright (c) 2026 Erik Johansson"
assert_contains "Omarchy's notice is kept" "$(cat "$star/LICENSE")" "Copyright (c) David Heinemeier Hansson"
assert_contains "the photographs are SpaceX's" "$(cat "$star/LICENSE")" "SpaceX retains all rights"
assert_contains "NOTICE lists Starship" "$(cat "$REPO/NOTICE.md")" '`share/haseen/themes/starship/`'
assert_eq "the default theme is still haseen" "THEME_DEFAULT=haseen" "$(grep '^THEME_DEFAULT=' "$HASEEN_PATH/layers/theme/theme-lib.sh")"

# --- the pin: v4.5.0-rc1 ------------------------------------------------------
manifest="$HASEEN_PATH/layers/theme/omarchy-assets.txt"
assert_contains "theme-lib pins v4.5.0-rc1" "$(cat "$HASEEN_PATH/layers/theme/theme-lib.sh")" "THEME_OMARCHY_COMMIT=$PIN"
assert_contains "the manifest records the same pin" "$(head -3 "$manifest")" "$PIN"
assert_eq "Starship's four photographs and preview are hashed" \
    "starship/backgrounds/1-starbase.webp starship/backgrounds/2-flight14-dawn.webp starship/backgrounds/3-engine-cluster.webp starship/backgrounds/4-morning-pad.webp starship/preview.png" \
    "$(awk '!/^#/ && $3 ~ /^starship\// { print $3 }' "$manifest" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "Liftoff leads Tokyo Night, the rest moved up one" \
    "0-liftoff.webp 1-winding-road.webp 2-quattro.webp 3-swirl-buck.webp 4-sunset-lake.webp 5-omakub.webp 6-oma-cityscape.jpg 7-oma.webp omarchy.webp" \
    "$(awk '!/^#/ && $3 ~ /^tokyo-night\/backgrounds\// { sub(/.*\//, "", $3); print $3 }' "$manifest" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "no intro videos" "" "$(grep -E 'intros|\.mp4' "$manifest" || true)"
assert_eq "Liftoff's hash at the pin" "c7e65d41f1a10e678d8fde799e4f01e81e1c9a95a7f1cb7b52e5f81ca7007e72 2240964" \
    "$(awk '$3 == "tokyo-night/backgrounds/0-liftoff.webp" { print $1, $2 }' "$manifest")"

themes_sandbox themes45-fetch
capture haseen theme fetch starship --dry-run
assert_status "fetch starship --dry-run" 0 "$STATUS"
assert_contains "Starship's photographs come from Omarchy at the pin" "$OUTPUT" \
    "DRYRUN: fetch https://raw.githubusercontent.com/omacom/omarchy/$PIN/themes/starship/backgrounds/1-starbase.webp -> $CACHE/starship/backgrounds/1-starbase.webp (690606 bytes"
assert_eq "five Starship images planned" "5" "$(grep -c '^DRYRUN: fetch' <<<"$OUTPUT")"
assert_dry_pure "fetch starship" "$OUTPUT"
capture haseen theme set starship
assert_status "set starship" 0 "$STATUS"
assert_eq "theme.name" "starship" "$(cat "$CUR/theme.name")"
assert_eq "the shell takes Starship's accent" "#ff9f0a" "$(jq -r .accent "$CUR/theme/shell.json")"

# --- each theme keeps its background ------------------------------------------
themes_sandbox themes45-memory
img "$BGS/nord/a.png"
img "$BGS/nord/b.png"
img "$BGS/gruvbox/g1.png"
img "$BGS/gruvbox/g2.png"
img "$HOME/Pictures/mine.png"
haseen theme set nord >/dev/null 2>&1
assert_eq "a theme never shown starts on its first image" "$BGS/nord/a.png" "$(shown)"
haseen theme bg set b.png >/dev/null 2>&1
haseen theme set gruvbox >/dev/null 2>&1
assert_eq "leaving nord remembers its background" "$BGS/nord/b.png" "$(remembered nord)"
assert_eq "gruvbox starts on its first image" "$BGS/gruvbox/g1.png" "$(shown)"
haseen theme bg next >/dev/null 2>&1
haseen theme set nord >/dev/null 2>&1
assert_eq "back to nord: the background it last showed" "$BGS/nord/b.png" "$(shown)"
assert_eq "leaving gruvbox remembered its pick" "$BGS/gruvbox/g2.png" "$(remembered gruvbox)"
haseen theme set nord >/dev/null 2>&1
assert_eq "setting the current theme again keeps its background" "$BGS/nord/b.png" "$(shown)"

# Omarchy's command and a theme without backgrounds take the same path.
capture "$HASEEN_PATH/omarchy/bin/omarchy-theme-set" gruvbox
assert_status "omarchy-theme-set" 0 "$STATUS"
assert_eq "omarchy-theme-set restores the pick too" "$BGS/gruvbox/g2.png" "$(shown)"
haseen theme set catppuccin >/dev/null 2>&1
assert_eq "a theme without backgrounds shows none" "" "$(shown)"
assert_eq "and leaves gruvbox's pick" "$BGS/gruvbox/g2.png" "$(remembered gruvbox)"
haseen theme set gruvbox >/dev/null 2>&1
assert_eq "gruvbox after a theme without backgrounds" "$BGS/gruvbox/g2.png" "$(shown)"
assert_eq "nothing is remembered for a theme that showed none" "no" "$([[ -e $MEM/catppuccin ]] && echo yes || echo no)"

# An image of the user's set by path is what was chosen for that theme.
haseen theme bg set "$HOME/Pictures/mine.png" >/dev/null 2>&1
haseen theme set nord >/dev/null 2>&1
haseen theme set gruvbox >/dev/null 2>&1
assert_eq "an image set by path comes back with its theme" "$HOME/Pictures/mine.png" "$(shown)"

# A remembered image that is gone, or a record that is not an absolute path,
# falls back to the theme's own rule.
rm "$HOME/Pictures/mine.png"
haseen theme set nord >/dev/null 2>&1
haseen theme set gruvbox >/dev/null 2>&1
assert_eq "a remembered image that is gone: the first image" "$BGS/gruvbox/g1.png" "$(shown)"
printf 'g2.png\n' >"$MEM/nord"
haseen theme set nord >/dev/null 2>&1
assert_eq "a relative record is ignored" "$BGS/nord/a.png" "$(shown)"

before="$(cd "$HOME" && find . | LC_ALL=C sort)"
capture haseen theme set gruvbox --dry-run
assert_status "set --dry-run" 0 "$STATUS"
assert_contains "dry run plans the record" "$OUTPUT" "DRYRUN: write $MEM/nord:"
assert_contains "with the image nord shows" "$OUTPUT" "    | $BGS/nord/a.png"
assert_contains "dry run names the rule" "$OUTPUT" "to the background last shown with gruvbox, else its first"
assert_dry_pure "set" "$OUTPUT"
assert_eq "dry run writes nothing" "$before" "$(cd "$HOME" && find . | LC_ALL=C sort)"
assert_eq "dry run keeps the record" "g2.png" "$(remembered nord)"
# A record naming a file that is not named as an image (an edited or garbled
# record, a log) is ignored too, as theme_backgrounds would never list it; one
# named in another case still counts (plan 111).
printf 'not an image\n' >"$HOME/notes.txt"
haseen theme set gruvbox >/dev/null 2>&1
printf '%s\n' "$HOME/notes.txt" >"$MEM/nord"
haseen theme set nord >/dev/null 2>&1
assert_eq "a record naming a non-image file: the first image" "$BGS/nord/a.png" "$(shown)"
img "$HOME/Pictures/SHOT.PNG"
haseen theme set gruvbox >/dev/null 2>&1
printf '%s\n' "$HOME/Pictures/SHOT.PNG" >"$MEM/nord"
haseen theme set nord >/dev/null 2>&1
assert_eq "an image name in capitals counts" "$HOME/Pictures/SHOT.PNG" "$(shown)"

# --- migration 1792681032: Tokyo Night renumbered ------------------------------
# A copy of the tree whose manifest hashes this test's bytes under the new
# names; the cache holds copies under the old ones.
themes_sandbox themes45-migrate
share="$SANDBOX/share"
cp -r "$REPO/share/haseen" "$share"
export HASEEN_PATH="$share"
tn="$CACHE/tokyo-night/backgrounds"
sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
{
    grep -v ' tokyo-night/' "$REPO/share/haseen/layers/theme/omarchy-assets.txt"
    for pair in 1-winding-road.webp:W 2-quattro.webp:Q 3-swirl-buck.webp:B 4-sunset-lake.webp:S 5-omakub.webp:K 6-oma-cityscape.jpg:C 7-oma.webp:O; do
        printf '%s 1 tokyo-night/backgrounds/%s\n' "$(sha "${pair#*:}")" "${pair%:*}"
    done
} >"$share/layers/theme/omarchy-assets.txt"
mkdir -p "$tn" "$MEM" "$CUR"
printf W >"$tn/0-winding-road.webp"
printf Q >"$tn/1-quattro.webp"
printf B >"$tn/2-swirl-buck.webp"
printf B >"$tn/3-swirl-buck.webp"
printf S >"$tn/3-sunset-lake.webp"
printf 'not K' >"$tn/4-omakub.webp"
printf C >"$tn/5-oma-cityscape.jpg"
ln -s "$tn/3-sunset-lake.webp" "$CUR/background"
printf '%s\n' "$tn/1-quattro.webp" >"$MEM/tokyo-night"
printf '%s\n' "$BGS/nord/a.png" >"$MEM/nord"

run_migration() { capture env HASEEN_MIGRATION="$MIGRATION" bash -Eeuo pipefail "$share/migrations/$MIGRATION"; }
run_migration
assert_status "migration" 0 "$STATUS"
assert_eq "renamed, the duplicate dropped, the foreign file kept" \
    "1-winding-road.webp 2-quattro.webp 3-swirl-buck.webp 4-omakub.webp 4-sunset-lake.webp 6-oma-cityscape.jpg" \
    "$(ls "$tn" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "renamed bytes unchanged" "W" "$(cat "$tn/1-winding-road.webp")"
assert_eq "the background shown follows the rename" "$tn/4-sunset-lake.webp" "$(shown)"
assert_eq "the remembered Tokyo Night pick follows it" "$tn/2-quattro.webp" "$(remembered tokyo-night)"
assert_eq "other themes' picks untouched" "$BGS/nord/a.png" "$(remembered nord)"
run_migration
assert_status "re-run" 0 "$STATUS"
assert_eq "re-run changes nothing" \
    "1-winding-road.webp 2-quattro.webp 3-swirl-buck.webp 4-omakub.webp 4-sunset-lake.webp 6-oma-cityscape.jpg" \
    "$(ls "$tn" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "re-run: link" "$tn/4-sunset-lake.webp" "$(shown)"

themes_sandbox themes45-migrate-empty
share="$SANDBOX/share"
cp -r "$REPO/share/haseen" "$share"
export HASEEN_PATH="$share"
run_migration
assert_status "no Tokyo Night cache: nothing to do" 0 "$STATUS"
assert_eq "and nothing made" "" "$(ls -A "$HOME/.cache" 2>/dev/null)"
export HASEEN_PATH="$REPO/share/haseen"
