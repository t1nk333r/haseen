# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 020: every Omarchy stock theme renders; `haseen theme fetch` against a
# local file:// mirror (pinned URLs, type/size/hash checks, resume,
# idempotency); `haseen theme bg` list/set/next and the background service
# restart; the detached fetch `theme set` starts; the user font override;
# dry-run purity throughout.

SHELL_KEYS="mode background surface surfaceAlt foreground muted accent accentFg urgent warning success border selection fontFamily fontMono fontSize radius gap borderWidth"
PIN=5c4da021469517449770579793b37ce26d0a0d48
OMARCHY_THEMES="catppuccin catppuccin-latte ethereal everforest flexoki-light gruvbox hackerman kanagawa last-horizon lumon lupine matte-black miasma nord osaka-jade retro-82 ristretto rose-pine solitude tokyo-night vantablack white"
# Stock themes that are not Omarchy's (no fetchable images): the owner's default.
HASEEN_THEMES="greek-noir-akane"

# themes2_sandbox NAME — sandbox with probes faked and a private runtime dir,
# so nothing reaches the developer's session or units.
themes2_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    stub pkill 'echo "STUB-CALLED: pkill $*" >&2; exit 97'
    stub gsettings 'echo "STUB-CALLED: gsettings $*" >&2; exit 97'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS HASEEN_THEME_HEADLESS HASEEN_THEME_MIRROR HASEEN_USER_CACHE
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    CUR="$HOME/.local/state/haseen/current"
    CACHE="$HOME/.cache/haseen/themes"
}

tree() { (cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort); }

# Smallest byte strings `file` types as each image format.
img_png() { printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\x08\x06\0\0\0\x1f\x15\xc4\x89%s' "$2" >"$1"; }
img_jpg() { printf '\xff\xd8\xff\xe0\0\x10JFIF\0\1\1\0\0\1\0\1\0\0%s' "$2" >"$1"; }
img_webp() { printf 'RIFF\x1a\0\0\0WEBPVP8L\x0d\0\0\0/\0\0\0\x10\x07\x10\x11\x11\x88\x88\xfe\x07\0%s' "$2" >"$1"; }

# --- the stock set is Omarchy's, and every theme renders -------------------
assert_eq "stock themes = Omarchy's at $PIN + haseen's own" "$(tr ' ' '\n' <<<"$OMARCHY_THEMES $HASEEN_THEMES" | LC_ALL=C sort)" "$(ls "$HASEEN_PATH/themes" | LC_ALL=C sort)"
assert_eq "no images shipped" "" "$(find "$HASEEN_PATH/themes" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.webp' \) -print)"
manifest="$HASEEN_PATH/layers/theme/omarchy-assets.txt"
assert_eq "manifest names every stock theme" "$(tr ' ' '\n' <<<"$OMARCHY_THEMES")" "$(awk '!/^#/ { sub(/\/.*/, "", $3); print $3 }' "$manifest" | LC_ALL=C sort -u)"
assert_eq "manifest: one preview per theme" "22" "$(grep -c ' [a-z0-9-]*/preview.png$' "$manifest")"
assert_eq "manifest rows are sha256 size path" "" "$(awk '!/^#/ && !($1 ~ /^[0-9a-f]{64}$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[a-z0-9-]+\/(preview\.png|backgrounds\/[^\/]+\.(png|jpg|jpeg|webp))$/)' "$manifest")"
assert_eq "manifest: largest image under the fetch limit" "yes" "$(awk '!/^#/ && $2 > m { m = $2 } END { print (m <= 8388608 ? "yes" : "no") }' "$manifest")"
assert_contains "manifest records the pin" "$(head -3 "$manifest")" "$PIN"

themes2_sandbox themes2-render
for t in $OMARCHY_THEMES $HASEEN_THEMES; do
    capture env HASEEN_THEME_HEADLESS=1 haseen theme set "$t"
    assert_status "set $t" 0 "$STATUS"
    assert_not_contains "$t: no warnings" "$OUTPUT" "Warning"
    left="$(grep -l '{{' "$CUR/theme"/* 2>/dev/null || true)"
    assert_eq "$t: every output rendered" "" "$left"
    assert_eq "$t: shell.json keys" "$(tr ' ' '\n' <<<"$SHELL_KEYS" | sort)" "$(jq -r 'keys[]' "$CUR/theme/shell.json" 2>/dev/null | sort)"
    if command -v luac >/dev/null; then
        capture luac -p "$CUR/theme/hyprland.lua" "$CUR/theme/neovim.lua"
        assert_status "$t: Lua parses" 0 "$STATUS"
    fi
done
assert_not_contains "kanagawa: no Omarchy-only helper call" "$(<"$HASEEN_PATH/themes/kanagawa/hyprland.lua")" "o.window("

# --- fetch against a local mirror -------------------------------------------
# A copy of share/haseen whose manifest describes images this test serves.
themes2_sandbox themes2-fetch
share="$SANDBOX/share"
cp -r "$REPO/share/haseen" "$share"
export HASEEN_PATH="$share"
mirror="$SANDBOX/mirror"
m="$mirror/$PIN/themes"
mkdir -p "$m/tokyo-night/backgrounds" "$m/nord/backgrounds" "$m/gruvbox/backgrounds"
img_png "$m/tokyo-night/backgrounds/1-a.png" aaaa
img_jpg "$m/tokyo-night/backgrounds/2-b.jpg" bbbb
img_webp "$m/tokyo-night/backgrounds/3-c.webp" "$(printf 'c%.0s' {1..4000})"
img_png "$m/tokyo-night/preview.png" preview
printf '<html>not an image</html>\n' >"$m/nord/preview.png"
img_png "$m/nord/backgrounds/1-x.png" xxxx
img_png "$m/gruvbox/preview.png" served
row() { printf '%s %s %s\n' "$(sha256sum <"$m/$1" | cut -d' ' -f1)" "$(stat -c %s "$m/$1")" "$1"; }
{
    echo "# test manifest for $PIN"
    row tokyo-night/backgrounds/1-a.png
    row tokyo-night/backgrounds/2-b.jpg
    row tokyo-night/backgrounds/3-c.webp
    row tokyo-night/preview.png
    row nord/backgrounds/1-x.png
    row nord/preview.png
    # Right size, wrong hash: a tampered or wrong-commit image.
    printf '%064d %s gruvbox/preview.png\n' 0 "$(stat -c %s "$m/gruvbox/preview.png")"
} >"$share/layers/theme/omarchy-assets.txt"
stub curl "echo \"\$*\" >>'$SANDBOX/curl.log'; exec /usr/bin/curl \"\$@\""
touch "$SANDBOX/curl.log"
# The thumbnailer writes a PNG to --output (args: --input URL --output PATH --size N).
img_png "$SANDBOX/thumb.png" thumb
stub glycin-thumbnailer "echo \"\$*\" >>'$SANDBOX/thumb.log'; cp '$SANDBOX/thumb.png' \"\$4\""

# Pinned upstream URLs (dry run: nothing is downloaded).
capture haseen theme fetch tokyo-night --dry-run
assert_status "fetch dry-run" 0 "$STATUS"
assert_contains "upstream URL names the commit" "$OUTPUT" "DRYRUN: fetch https://raw.githubusercontent.com/omacom/omarchy/$PIN/themes/tokyo-night/backgrounds/1-a.png -> $CACHE/tokyo-night/backgrounds/1-a.png"
assert_not_contains "never a branch URL" "$OUTPUT" "/master/"
assert_eq "four images planned" "4" "$(grep -c '^DRYRUN: fetch ' <<<"$OUTPUT")"

export HASEEN_THEME_MIRROR="file://$mirror"
before="$(tree)"
capture haseen theme fetch tokyo-night --dry-run
assert_dry_pure "fetch" "$OUTPUT"
assert_eq "fetch --dry-run writes nothing" "$before" "$(tree)"
assert_eq "fetch --dry-run runs no curl" "" "$(cat "$SANDBOX/curl.log")"

capture haseen theme fetch tokyo-night
assert_status "fetch tokyo-night" 0 "$STATUS"
assert_contains "summary" "$OUTPUT" "tokyo-night: 4 images in $CACHE/tokyo-night (4 fetched, 0 cached)"
for f in backgrounds/1-a.png backgrounds/2-b.jpg backgrounds/3-c.webp preview.png; do
    assert_eq "fetched $f intact" "$(sha256sum <"$m/tokyo-night/$f")" "$(sha256sum <"$CACHE/tokyo-night/$f" 2>/dev/null)"
done
assert_eq "every request is pinned" "" "$(grep -v -- "-- file://$mirror/$PIN/themes/tokyo-night/" "$SANDBOX/curl.log")"
assert_contains "curl limited to the mirror's scheme" "$(cat "$SANDBOX/curl.log")" "--proto =file --proto-redir =file"
assert_contains "curl size limit" "$(cat "$SANDBOX/curl.log")" "--max-filesize 8388608"
assert_contains "curl resumes" "$(cat "$SANDBOX/curl.log")" "--continue-at -"
assert_eq "no partial files left" "" "$(find "$CACHE" -name '*.part')"
assert_eq "thumbnail made beside the preview" "$(sha256sum <"$SANDBOX/thumb.png")" "$(sha256sum <"$CACHE/tokyo-night/preview-thumb.png" 2>/dev/null)"
assert_eq "thumbnailer gets a file URL and 512 px" "--input file://$CACHE/tokyo-night/preview.png --output $CACHE/tokyo-night/.preview-thumb.png.tmp --size 512" "$(cat "$SANDBOX/thumb.log")"

# Idempotent: intact files are not downloaded again.
: >"$SANDBOX/curl.log"
capture haseen theme fetch tokyo-night
assert_status "re-fetch" 0 "$STATUS"
assert_contains "re-fetch keeps the cache" "$OUTPUT" "(0 fetched, 4 cached)"
assert_eq "re-fetch downloads nothing" "" "$(cat "$SANDBOX/curl.log")"
capture haseen theme fetch tokyo-night --dry-run
assert_contains "dry-run reports cached files" "$OUTPUT" "cached: tokyo-night/preview.png"

# Resume: an interrupted download continues from its .part file; a cached
# file with the right size but other bytes is fetched again.
dest="$CACHE/tokyo-night/backgrounds/3-c.webp"
head -c 1000 "$dest" >"$CACHE/tokyo-night/backgrounds/.3-c.webp.part"
rm "$dest"
printf 'X' | dd of="$CACHE/tokyo-night/preview.png" bs=1 seek=20 conv=notrunc status=none
: >"$SANDBOX/curl.log"
capture haseen theme fetch tokyo-night
assert_status "resume" 0 "$STATUS"
assert_contains "resume + repair fetched two" "$OUTPUT" "(2 fetched, 2 cached)"
assert_eq "resumed file intact" "$(sha256sum <"$m/tokyo-night/backgrounds/3-c.webp")" "$(sha256sum <"$dest")"
assert_eq "corrupted preview replaced" "$(sha256sum <"$m/tokyo-night/preview.png")" "$(sha256sum <"$CACHE/tokyo-night/preview.png")"
assert_eq "two downloads" "2" "$(wc -l <"$SANDBOX/curl.log")"

# A non-image is rejected and deleted; the other image of the theme lands.
capture haseen theme fetch nord
assert_status "fetch with a non-image fails" 1 "$STATUS"
assert_contains "non-image named" "$OUTPUT" "nord/preview.png: not an image (text/html), deleted"
assert_eq "non-image not cached" "" "$(ls -A "$CACHE/nord/preview.png" "$CACHE/nord/.preview.png.part" 2>/dev/null)"
assert_eq "valid image of the same theme kept" "$(sha256sum <"$m/nord/backgrounds/1-x.png")" "$(sha256sum <"$CACHE/nord/backgrounds/1-x.png" 2>/dev/null)"
# A real image whose hash is not the pinned one is rejected too.
capture haseen theme fetch gruvbox
assert_status "hash mismatch fails" 1 "$STATUS"
assert_contains "hash mismatch named" "$OUTPUT" "gruvbox/preview.png: sha256 does not match commit ${PIN:0:7}, deleted"
assert_eq "mismatched image not cached" "" "$(ls -A "$CACHE/gruvbox/preview.png" 2>/dev/null)"
# Over the size limit: curl stops at 8 MiB and the partial is removed.
truncate -s 9M "$m/gruvbox/backgrounds/big.png"
printf '%s 9437184 gruvbox/backgrounds/big.png\n' "$(printf '%064d' 1)" >>"$share/layers/theme/omarchy-assets.txt"
capture haseen theme fetch gruvbox
assert_contains "oversize rejected" "$OUTPUT" "gruvbox/backgrounds/big.png: larger than 8388608 bytes, deleted"
assert_eq "oversize not kept" "" "$(ls -A "$CACHE/gruvbox/backgrounds" 2>/dev/null)"

capture haseen theme fetch no-such-theme
assert_status "unknown theme refused" 1 "$STATUS"
assert_contains "refusal says why" "$OUTPUT" "not an Omarchy stock theme"
capture haseen theme fetch tokyo-night --all
assert_status "--all takes no name" 2 "$STATUS"
capture haseen theme fetch --all --dry-run
assert_contains "--all covers every theme" "$OUTPUT" "DRYRUN: fetch file://$mirror/$PIN/themes/gruvbox/preview.png"
assert_contains "--all covers nord" "$OUTPUT" "DRYRUN: fetch file://$mirror/$PIN/themes/nord/preview.png"

# --- theme set starts the fetch in the background ---------------------------
rm -rf "$CACHE/tokyo-night"
unset HASEEN_THEME_FETCH
capture haseen theme set tokyo-night --dry-run
assert_contains "set --dry-run plans the fetch" "$OUTPUT" "DRYRUN: haseen-theme-fetch --quiet tokyo-night (detached)"
assert_dry_pure "set" "$OUTPUT"
assert_eq "set --dry-run fetches nothing" "" "$(ls -A "$CACHE/tokyo-night" 2>/dev/null)"
capture haseen theme set tokyo-night
assert_status "set starts the fetch" 0 "$STATUS"
for _ in $(seq 50); do
    [[ -L $CUR/background ]] && break
    sleep 0.1
done
assert_eq "fetched background linked once it lands" "$CACHE/tokyo-night/backgrounds/1-a.png" "$(readlink "$CUR/background")"
assert_eq "background fetch logged" "yes" "$([[ -f $HOME/.local/state/haseen/theme-fetch.log ]] && echo yes)"
: >"$SANDBOX/curl.log"
capture haseen theme set tokyo-night
assert_eq "cached theme starts no fetch" "" "$(cat "$SANDBOX/curl.log")"
export HASEEN_THEME_FETCH=0

# --- haseen theme bg ---------------------------------------------------------
mkdir -p "$HOME/.config/haseen/backgrounds/tokyo-night"
img_png "$HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png" mine
printf 'text\n' >"$HOME/notes.txt"
stub systemctl "echo \"systemctl \$*\" >>'$SANDBOX/systemctl.log'"
capture haseen theme bg list
assert_eq "bg list: user first, then cache, full paths" \
    "$HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png"$'\n'"$CACHE/tokyo-night/backgrounds/1-a.png"$'\n'"$CACHE/tokyo-night/backgrounds/2-b.jpg"$'\n'"$CACHE/tokyo-night/backgrounds/3-c.webp" "$OUTPUT"
capture haseen theme bg current
assert_eq "bg current" "$CACHE/tokyo-night/backgrounds/1-a.png" "$OUTPUT"

before="$(tree)"
capture haseen theme bg next --dry-run
assert_dry_pure "bg next" "$OUTPUT"
assert_contains "bg next --dry-run plans the link" "$OUTPUT" "DRYRUN: link $CUR/background -> $CACHE/tokyo-night/backgrounds/2-b.jpg"
assert_eq "bg next --dry-run writes nothing" "$before" "$(tree)"

seen=""
for _ in 1 2 3 4; do
    haseen theme bg next >/dev/null
    seen+="$(basename "$(readlink "$CUR/background")") "
done
assert_eq "bg next cycles and wraps" "2-b.jpg 3-c.webp 0-mine.png 1-a.png " "$seen"
assert_eq "service not running: no restart" "" "$(cat "$SANDBOX/systemctl.log" 2>/dev/null)"

# With the unit active (systemd's invocation link), set/next restart it.
mkdir -p "$XDG_RUNTIME_DIR/systemd/units"
ln -s 0123 "$XDG_RUNTIME_DIR/systemd/units/invocation:haseen-background.service"
capture haseen theme bg next --dry-run
assert_contains "dry run plans the restart" "$OUTPUT" "DRYRUN: systemctl --user try-restart haseen-background.service"
assert_eq "dry run restarts nothing" "" "$(cat "$SANDBOX/systemctl.log" 2>/dev/null)"
capture haseen theme bg set 3-c.webp
assert_status "bg set by file name" 0 "$STATUS"
assert_eq "bg set links it" "$CACHE/tokyo-night/backgrounds/3-c.webp" "$(readlink "$CUR/background")"
assert_eq "bg set restarts the service" "systemctl --user try-restart haseen-background.service" "$(cat "$SANDBOX/systemctl.log")"
capture haseen theme bg set "$HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png"
assert_eq "bg set by path" "$HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png" "$(readlink "$CUR/background")"
capture haseen theme bg set "$HOME/notes.txt"
assert_status "bg set refuses a non-image" 1 "$STATUS"
capture haseen theme bg set nope.png
assert_status "bg set refuses an unknown name" 1 "$STATUS"
assert_eq "refusals keep the link" "$HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png" "$(readlink "$CUR/background")"
assert_eq "no temporary link left" "" "$(ls -A "$CUR/.background.tmp" 2>/dev/null)"
capture haseen theme bg bogus
assert_status "bg unknown verb" 2 "$STATUS"

capture haseen theme bg run --dry-run
assert_eq "bg run shows the link" "DRYRUN: swaybg --mode fill --image $HOME/.config/haseen/backgrounds/tokyo-night/0-mine.png" "$OUTPUT"
rm "$CUR/background"
capture haseen theme bg run --dry-run
assert_eq "bg run without an image paints the theme colour" "DRYRUN: swaybg --color #1a1b26" "$OUTPUT"

haseen theme set catppuccin >/dev/null 2>&1
capture haseen theme bg next
assert_status "bg next without backgrounds" 1 "$STATUS"
assert_contains "bg next says how to get some" "$OUTPUT" "haseen theme fetch catppuccin"

# --- the background unit and the layer ---------------------------------------
unit="$REPO/share/haseen/systemd/user/haseen-background.service"
assert_contains "unit runs the bg runner" "$(<"$unit")" "ExecStart=/usr/bin/env haseen theme bg run"
assert_contains "unit follows the session" "$(<"$unit")" "PartOf=graphical-session.target"
capture haseen theme bg run --help
assert_status "router reaches the runner" 0 "$STATUS"
assert_contains "runner help" "$OUTPUT" "swaybg"
before="$(tree)"
capture bash -c 'source "$HASEEN_PATH/lib/common.sh"; DRY_RUN=true; LAYER_DIR="$HASEEN_PATH/layers/theme"; source "$LAYER_DIR/layer.sh"; layer_apply'
assert_contains "layer apply enables the unit" "$OUTPUT" "DRYRUN: systemctl --user enable haseen-background.service"
assert_dry_pure "layer apply" "$OUTPUT"
assert_eq "layer apply --dry-run writes nothing" "$before" "$(tree)"

# --- user font override (haseen font set) -----------------------------------
export HASEEN_PATH="$REPO/share/haseen"
haseen theme set tokyo-night >/dev/null 2>&1
assert_not_contains "no font file: foot.ini has no font" "$(<"$CUR/theme/foot.ini")" "[main]"
printf 'Fira Code\n' >"$HOME/.config/haseen/font"
capture haseen theme set tokyo-night
assert_eq "font: shell.json fontMono" "Fira Code" "$(jq -r .fontMono "$CUR/theme/shell.json")"
assert_contains "font: foot" "$(<"$CUR/theme/foot.ini")" $'[main]\nfont=Fira Code:size=11'
assert_contains "font: kitty" "$(<"$CUR/theme/kitty.conf")" "font_family Fira Code"
assert_contains "font: ghostty" "$(<"$CUR/theme/ghostty.conf")" $'font-family = ""\nfont-family = Fira Code'
assert_contains "font: alacritty" "$(<"$CUR/theme/alacritty.toml")" $'[font.normal]\nfamily = "Fira Code"'
printf 'Evil"; x\n' >"$HOME/.config/haseen/font"
capture haseen theme set tokyo-night
assert_contains "font: bad name refused" "$OUTPUT" "unsupported characters in the font name"
assert_eq "font: bad name not used" "JetBrainsMono Nerd Font" "$(jq -r .fontMono "$CUR/theme/shell.json")"

# --- commands and the picker plugin -------------------------------------------
for c in haseen-theme-fetch haseen-theme-bg haseen-theme-bg-run; do
    assert_contains "$c summary header" "$(<"$REPO/bin/$c")" "# haseen:summary "
    assert_contains "$c args header" "$(<"$REPO/bin/$c")" "# haseen:args"
    capture "$REPO/bin/$c" --help
    assert_status "$c --help" 0 "$STATUS"
done
capture haseen plugin validate haseen.themepicker
assert_status "themepicker manifest valid" 0 "$STATUS"
assert_eq "themepicker has no hex literals" "" "$(grep -nE '#[0-9A-Fa-f]{3,8}\b' "$REPO"/share/haseen/shell/plugins/haseen.themepicker/*.qml)"
assert_eq "themepicker has no timers" "" "$(grep -n 'Timer' "$REPO"/share/haseen/shell/plugins/haseen.themepicker/*.qml)"
