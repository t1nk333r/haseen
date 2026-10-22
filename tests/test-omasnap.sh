# shellcheck shell=bash
# haseen:covers bin/haseen-capture-screenshot bin/haseen-seed-user share/haseen/lib/omasnap.sh
# haseen:covers share/haseen/default/hypr/{binds,windowrules}.lua share/haseen/layers/desktop/packages.txt
# haseen:covers share/haseen/migrations/1792634179-omasnap.sh share/haseen/seeds/80-capture.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-{capture-screenshot,clipboard-open}
# haseen:covers tests/fixtures/desk-cachyos-amd/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 107: Omasnap instead of Tensaku (owner, 2026-10-21). haseen capture
# screenshot hands its picks to Omasnap with haseen's folder and OCR
# languages, keeps its own grim capture for everything scripted, and edits in
# Omasnap; Omarchy's screenshot and clipboard commands answer as 4.5's do; the
# desktop layer and a migration install it from [omarchy] only, and nothing
# removes Tensaku. Omasnap itself is a recording stub: no test opens a window.

OMA="$HASEEN_PATH/omarchy/bin"

# snap_sandbox NAME — a sandbox where omasnap, grim, slurp and the clipboard
# are recorders, and haseen's own picker answers one rectangle.
snap_sandbox() {
    sandbox "$1"
    CALLS="$SANDBOX/calls"
    : >"$CALLS"
    export CALLS EDITOR_KEY=escape
    unset HASEEN_SCREENSHOT_TOOL HASEEN_SCREENSHOT_DIR HASEEN_OCR_LANGS OMASNAP_SCREENSHOT_DIR \
        OMASNAP_OCR_LANGS OMARCHY_SCREENSHOT_DIR OMARCHY_OCR_LANGS DRY_RUN
    stub xdg-user-dir 'echo "$HOME/$1"'
    stub notify-send 'echo "notify-send $*" >>"$CALLS"'
    stub wl-copy 'printf "wl-copy %s: " "$*" >>"$CALLS"; cat >>"$CALLS"; echo >>"$CALLS"'
    stub grim 'echo "grim $*" >>"$CALLS"; for a in "$@"; do o=$a; done; [ "$o" = - ] && printf PNG || printf PNG >"$o"'
    stub slurp 'echo "slurp" >>"$CALLS"; echo "0,0 10x10"'
    # Hyprland answers the two reads the immediate captures make.
    stub hyprctl 'case "$*" in
"activewindow -j") echo "{\"at\":[0,0],\"size\":[10,10]}" ;;
"monitors -j") echo "[{\"name\":\"eDP-1\",\"focused\":true}]" ;;
*) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;;
esac'
    # The upload host: it records the bytes of each quoted file part
    # (-F name=@"path"), drains its stdin and answers one link.
    stub curl 'echo "curl $*" >>"$CALLS"
q="\""
for a in "$@"; do
  case $a in *=@$q*$q) f=${a#*=@$q}; printf "curl-file: %s\n" "$(cat "${f%$q}")" >>"$CALLS" ;; esac
done
cat >/dev/null
printf "%s" "https://files.catbox.moe/zz.png"'
    export HASEEN_UPLOAD_CONFIG="$SANDBOX/upload.toml"
    # Omasnap 1.21.0 as far as haseen relies on it (src/main.cpp,
    # src/capture.cpp, src/editor.cpp at v1.21.0): it records the folder and
    # OCR languages it was given and its arguments. Editing a --file, it
    # announces through omarchy-notification-send with its own arguments
    # (src/capture.cpp:2501-2525): EDITOR_KEY=enter saves the edit under a name
    # of its own in $OMASNAP_SCREENSHOT_DIR and announces the save
    # (src/editor.cpp:4013-4019); ocr announces copied text (:873) and copy a
    # copy, saving nothing; fail cannot load the file (src/main.cpp:344-347:
    # stderr and exit 1, no notice); escape (or a pin) saves nothing.
    stub omasnap 'echo "omasnap [${OMASNAP_SCREENSHOT_DIR-unset}] [${OMASNAP_OCR_LANGS-unset}] $*" >>"$CALLS"
in=""; prev=""
for a in "$@"; do [ "$prev" = --file ] && in=$a; prev=$a; done
[ -n "$in" ] || exit 0
printf "omasnap-input: %s\n" "$(cat "$in")" >>"$CALLS"
case ${EDITOR_KEY:-escape} in
enter)
  mkdir -p "$OMASNAP_SCREENSHOT_DIR"
  saved="$OMASNAP_SCREENSHOT_DIR/screenshot-2026-10-21_10-00-00-firefox.png"
  printf ANNOTATED >"$saved"
  omarchy-notification-send -g "" --app-name omasnap -t 4500 "Screenshot saved and copied" "Click to edit" --image "$saved" --exec omasnap "file://$saved" ;;
ocr) omarchy-notification-send -g "" --app-name omasnap -t 4500 "Copied text from screenshot" ;;
copy) omarchy-notification-send -g "" --app-name omasnap -t 4500 "Screenshot copied to clipboard" ;;
fail) echo "Could not load image: $in" >&2; exit 1 ;;
esac
exit 0'
    # The answer Omasnap's notification would reach on PATH.
    stub omarchy-notification-send 'echo "omarchy-notification-send $*" >>"$CALLS"'
    PICS="$HOME/PICTURES"
}
calls() { cat "$CALLS"; }
shots() { find "$PICS" -type f 2>/dev/null; }

# --- help ------------------------------------------------------------------------
snap_sandbox p107-help
capture haseen capture screenshot --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "help names the Omasnap modes" "$OUTPUT" "scroll   a region taller or wider than the screen"
assert_contains "help names the switch back" "$OUTPUT" "HASEEN_SCREENSHOT_TOOL=grim never starts Omasnap"
assert_contains "help names the OCR default" "$OUTPUT" "(default ara+eng)"
capture haseen commands capture
assert_contains "haseen commands lists the modes" "$OUTPUT" "[smart|region|scroll|window|output|screen]"

# --- the picks go to Omasnap --------------------------------------------------------
snap_sandbox p107-route
# check_snap LABEL EXPECTED ARGS... — a real run reaches the omasnap recorder
# with EXPECTED (folder, languages, arguments), and nothing else runs.
check_snap() {
    local label=$1 want=$2
    shift 2
    : >"$CALLS"
    capture haseen capture screenshot "$@"
    assert_status "$label: exits 0" 0 "$STATUS"
    assert_eq "$label" "$want" "$(calls)"
}
check_snap "the default is Omasnap's smart pick, saving where haseen saves, reading Arabic" \
    "omasnap [$PICS] [ara+eng] smart"
check_snap "region is Omasnap's region mode" "omasnap [$PICS] [ara+eng] region" region
check_snap "scroll is Omasnap's scrolling capture" "omasnap [$PICS] [ara+eng] scroll" scroll
check_snap "--no-save copies only" "omasnap [$PICS] [ara+eng] smart --copy" --no-save
check_snap "--no-copy saves only" "omasnap [$PICS] [ara+eng] region --save" region --no-copy
check_snap "--edit opens the editor first, as an overlay" "omasnap [$PICS] [ara+eng] smart --editor overlay" --edit
mkdir -p "$HOME/.config/omasnap"
printf '[editor]\nmode = window\n' >"$HOME/.config/omasnap/omasnap.conf"
check_snap "--edit keeps the user's windowed editor" "omasnap [$PICS] [ara+eng] smart --editor window" --edit
printf '[output]\ndirectory = ~/Pictures/Captures\n[editor]\n  mode = "overlay"\n' >"$HOME/.config/omasnap/omasnap.conf"
check_snap "omasnap.conf's own folder is left to Omasnap" "omasnap [unset] [ara+eng] smart --editor overlay" --edit
HASEEN_SCREENSHOT_DIR="$SANDBOX/shots" check_snap "HASEEN_SCREENSHOT_DIR still wins over omasnap.conf" \
    "omasnap [$SANDBOX/shots] [ara+eng] smart"
rm "$HOME/.config/omasnap/omasnap.conf"
OMASNAP_SCREENSHOT_DIR="$SANDBOX/native" check_snap "OMASNAP_SCREENSHOT_DIR is the user's" \
    "omasnap [$SANDBOX/native] [ara+eng] smart"
HASEEN_OCR_LANGS=eng check_snap "HASEEN_OCR_LANGS picks Omasnap's OCR languages" "omasnap [$PICS] [eng] smart"
OMARCHY_OCR_LANGS=tha+eng check_snap "OMARCHY_OCR_LANGS is left for Omasnap to read" "omasnap [$PICS] [unset] smart"
OMASNAP_OCR_LANGS=deu check_snap "OMASNAP_OCR_LANGS is the user's" "omasnap [$PICS] [deu] smart"
: >"$CALLS"
capture haseen capture screenshot region --no-save --dry-run
assert_status "the Omasnap plan exits 0" 0 "$STATUS"
assert_eq "the Omasnap plan" "DRYRUN: env OMASNAP_SCREENSHOT_DIR=$PICS OMASNAP_OCR_LANGS=ara+eng omasnap region --copy" "$OUTPUT"
assert_dry_pure "Omasnap plan" "$OUTPUT"
assert_eq "a plan starts nothing" "" "$(calls)"

# --- everything scripted stays haseen's own capture ----------------------------
snap_sandbox p107-own
# check_own LABEL NEEDLE ARGS... — a dry run plans grim with NEEDLE, never omasnap.
check_own() {
    local label=$1 needle=$2
    shift 2
    capture haseen capture screenshot "$@" --dry-run
    assert_status "$label: exits 0" 0 "$STATUS"
    assert_contains "$label" "$OUTPUT" "$needle"
    assert_not_contains "$label: no Omasnap" "$OUTPUT" "omasnap"
}
check_own "--geometry" "DRYRUN: grim -g 1,2 30x40 $PICS/screenshot-" --geometry "1,2 30x40"
check_own "window is the focused window at once" "grim -g <focused window>" window
check_own "output is the focused monitor at once" "grim -o <focused monitor>" output
check_own "screen is every monitor" "DRYRUN: grim  $PICS/screenshot-" screen
check_own "--format (dms screenshot always passes one)" "grim -g <slurp selection>" region --format png
check_own "--file" "grim -g <slurp selection> $PICS/named.png" --file named.png
check_own "--upload picks with slurp" "DRYRUN: haseen-upload" --upload
check_own "--no-notify" "DRYRUN: no notification" --no-notify
check_own "--cursor" "grim -g <slurp selection> -c" --cursor
check_own "--stdout" "DRYRUN: grim -g <slurp selection> -" --stdout
capture haseen capture screenshot --stdout
assert_eq "--stdout writes the picture" PNG "$OUTPUT"
capture haseen capture screenshot scroll --upload
assert_status "a scrolling capture takes none of haseen's own options" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "a scrolling screenshot is Omasnap's"

# --- HASEEN_SCREENSHOT_TOOL ----------------------------------------------------------
snap_sandbox p107-tool
export HASEEN_SCREENSHOT_TOOL=grim
capture haseen capture screenshot --dry-run
assert_contains "grim: smart is slurp's rectangle again" "$OUTPUT" "DRYRUN: grim -g <slurp selection> $PICS/screenshot-"
assert_not_contains "grim: Omasnap is never planned" "$OUTPUT" "omasnap"
: >"$CALLS"
capture haseen capture screenshot region
assert_status "grim: a real region capture succeeds" 0 "$STATUS"
assert_eq "grim: slurp, then grim" "slurp" "$(head -1 "$CALLS")"
assert_eq "grim: the file is saved" PNG "$(cat "$(shots)")"
assert_not_contains "grim: Omasnap never runs" "$(calls)" "omasnap"
capture haseen capture screenshot scroll
assert_status "grim: scroll fails" 1 "$STATUS"
assert_contains "grim: and says how to get it" "$OUTPUT" "HASEEN_SCREENSHOT_TOOL other than grim"
HASEEN_SCREENSHOT_TOOL=bogus capture haseen capture screenshot --dry-run
assert_status "an unknown tool fails" 1 "$STATUS"
assert_contains "and names the values" "$OUTPUT" "HASEEN_SCREENSHOT_TOOL wants auto, omasnap or grim"
unset HASEEN_SCREENSHOT_TOOL
if [[ ! -e /usr/bin/omasnap && ! -e /bin/omasnap ]]; then
    rm "$SANDBOX/stubs/omasnap"
    capture haseen capture screenshot --dry-run
    assert_contains "auto without Omasnap: slurp's rectangle" "$OUTPUT" "DRYRUN: grim -g <slurp selection>"
    HASEEN_SCREENSHOT_TOOL=omasnap capture haseen capture screenshot --dry-run
    assert_status "omasnap without Omasnap fails" 1 "$STATUS"
    assert_contains "and says how to install it" "$OUTPUT" "haseen layer apply omarchy-repo desktop installs it"
else
    echo "  skip: omasnap is installed on this host; its absence was not exercised" >&2
fi

# --- Omasnap as haseen's editor --------------------------------------------------------
snap_sandbox p107-edit-plan
capture haseen capture screenshot window --edit --upload --dry-run
assert_status "the edit plan exits 0" 0 "$STATUS"
assert_dry_pure "edit plan" "$OUTPUT"
assert_contains "Omasnap edits the grabbed file in a private folder" "$OUTPUT" \
    "DRYRUN: env PATH=<private temp dir>/quiet:\$PATH OMASNAP_SCREENSHOT_DIR=<private runtime dir> OMASNAP_OCR_LANGS=ara+eng omasnap --file <private temp dir>/original.png"
assert_contains "its save notices are dropped, nothing else" "$OUTPUT" "quiet/omarchy-notification-send (drops Omasnap's \"Screenshot saved\" notices"
assert_contains "what it saved is kept" "$OUTPUT" "DRYRUN: mv <the PNG Omasnap saved in <private runtime dir>> $PICS/screenshot-"
assert_contains "and uploaded" "$OUTPUT" "DRYRUN: haseen-upload $PICS/screenshot-"
assert_contains "both private folders are removed" "$OUTPUT" "DRYRUN: rm -r <private temp dir> <private runtime dir>"
capture haseen capture screenshot --edit --no-save --dry-run
assert_contains "--edit --no-save picks with slurp" "$OUTPUT" "DRYRUN: grim -g <slurp selection> <private temp dir>/original.png"
assert_contains "and edits in Omasnap" "$OUTPUT" "omasnap --file <private temp dir>/original.png"

snap_sandbox p107-edit-enter
tmp="$SANDBOX/tmp"
mkdir -p "$tmp"
export EDITOR_KEY=enter
TMPDIR=$tmp capture haseen capture screenshot window --edit --upload
assert_status "edit then upload succeeds" 0 "$STATUS"
assert_eq "Omasnap edits the grabbed picture" "omasnap-input: PNG" "$(grep '^omasnap-input:' "$CALLS")"
assert_contains "in a private runtime folder, with haseen's OCR languages" "$(calls)" \
    "omasnap [$XDG_RUNTIME_DIR/haseen-screenshot."
assert_contains "the editor gets no picker arguments" "$(grep '^omasnap ' "$CALLS")" "[ara+eng] --file $tmp/"
assert_eq "what Omasnap saved is kept" ANNOTATED "$(cat "$(shots)")"
assert_eq "under haseen's name, not Omasnap's" 1 \
    "$(shots | grep -cE "^$PICS/screenshot-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.png\$")"
assert_eq "the upload sends it" "curl-file: ANNOTATED" "$(grep '^curl-file:' "$CALLS")"
assert_eq "the clipboard gets the edit, then the link" \
    "wl-copy -t image/png: ANNOTATED|wl-copy : https://files.catbox.moe/zz.png" "$(grep '^wl-copy' "$CALLS" | paste -sd'|')"
assert_not_contains "Omasnap's own toast about the private file is not shown" "$(calls)" "omarchy-notification-send"
assert_eq "the link is printed after the file" "$(shots)|https://files.catbox.moe/zz.png" "$(paste -sd'|' <<<"$OUTPUT")"
assert_eq "no private folder is left in the runtime dir" "" "$(find "$XDG_RUNTIME_DIR" -mindepth 1 -name 'haseen-screenshot.*')"
assert_eq "nor in TMPDIR" "" "$(find "$tmp" -mindepth 1)"

snap_sandbox p107-edit-escape
tmp="$SANDBOX/tmp"
mkdir -p "$tmp"
TMPDIR=$tmp capture haseen capture screenshot window --edit --upload
assert_status "leaving Omasnap without saving is not an error" 0 "$STATUS"
assert_eq "Escape: nothing is printed" "" "$OUTPUT"
assert_not_contains "Escape: nothing is uploaded" "$(calls)" "curl"
assert_eq "Escape: nothing is copied" "" "$(grep '^wl-copy' "$CALLS")"
assert_eq "Escape: nothing is saved" "" "$(shots)"
assert_eq "Escape: nothing is announced" "" "$(grep -E '^(notify-send|omarchy-notification-send)' "$CALLS")"
assert_eq "Escape: no private folder is left" "" "$(find "$tmp" "$XDG_RUNTIME_DIR" -mindepth 1)"

# Omasnap's other notices still reach the user: the stub drops only the save
# notices haseen replaces.
snap_sandbox p107-edit-notices
tmp="$SANDBOX/tmp"
mkdir -p "$tmp"
export EDITOR_KEY=ocr
TMPDIR=$tmp capture haseen capture screenshot window --edit
assert_status "OCR in the editor: exits 0" 0 "$STATUS"
assert_eq "OCR in the editor: its notice reaches the real command" \
    "omarchy-notification-send -g  --app-name omasnap -t 4500 Copied text from screenshot" \
    "$(grep '^omarchy-notification-send' "$CALLS")"
assert_eq "OCR in the editor: nothing is saved" "" "$(shots)"
: >"$CALLS"
export EDITOR_KEY=copy
TMPDIR=$tmp capture haseen capture screenshot window --edit
assert_status "copy only: exits 0" 0 "$STATUS"
assert_eq "copy only: Omasnap's own notice says what happened" \
    "omarchy-notification-send -g  --app-name omasnap -t 4500 Screenshot copied to clipboard" \
    "$(grep '^omarchy-notification-send' "$CALLS")"
assert_eq "copy only: haseen keeps and announces nothing" "" "$(shots)$(grep '^notify-send' "$CALLS")"
assert_eq "notices: no private folder is left" "" "$(find "$tmp" "$XDG_RUNTIME_DIR" -mindepth 1)"

# A failed Omasnap is reported, not silent: it notifies only from a capture,
# and a file it cannot load goes to stderr alone.
snap_sandbox p107-edit-fail
tmp="$SANDBOX/tmp"
mkdir -p "$tmp"
export EDITOR_KEY=fail
TMPDIR=$tmp capture haseen capture screenshot window --edit --upload
assert_status "a failed editor fails the capture with its status" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "omasnap failed (exit 1): nothing was saved, copied or uploaded"
assert_contains "Omasnap's own reason is kept" "$OUTPUT" "Could not load image:"
assert_eq "and a desktop notification says so" \
    "notify-send -a haseen -u critical Screenshot not edited Omasnap failed (exit 1): nothing was saved, copied or uploaded" \
    "$(grep '^notify-send' "$CALLS")"
assert_not_contains "nothing is uploaded" "$(calls)" "curl"
assert_eq "nothing is copied or saved" "" "$(grep '^wl-copy' "$CALLS")$(shots)"
assert_eq "no private folder is left" "" "$(find "$tmp" "$XDG_RUNTIME_DIR" -mindepth 1)"
: >"$CALLS"
TMPDIR=$tmp capture haseen capture screenshot window --edit --no-notify
assert_status "--no-notify: still fails" 1 "$STATUS"
assert_eq "--no-notify: no desktop notification" "" "$(grep '^notify-send' "$CALLS")"

# Without a private runtime dir, the editor's folder lives in the temp dir.
snap_sandbox p107-edit-noruntime
tmp="$SANDBOX/tmp"
mkdir -p "$tmp"
export EDITOR_KEY=enter
XDG_RUNTIME_DIR="$SANDBOX/missing" TMPDIR=$tmp capture haseen capture screenshot output --edit --no-save
assert_status "no runtime dir: the edit still succeeds" 0 "$STATUS"
assert_contains "no runtime dir: the editor saves into the temp dir" "$(calls)" "omasnap [$tmp/"
assert_eq "no runtime dir: the edit is copied" "wl-copy -t image/png: ANNOTATED" "$(grep '^wl-copy' "$CALLS")"
assert_eq "no runtime dir: nothing is saved" "" "$(shots)"
assert_eq "no runtime dir: nothing is left" "" "$(find "$tmp" -mindepth 1)"

# The editors after Omasnap, for a machine without it.
snap_sandbox p107-edit-fallback
export HASEEN_SCREENSHOT_TOOL=grim
stub tensaku 'echo "tensaku $*" >>"$CALLS"'
capture haseen capture screenshot window --edit --dry-run
assert_contains "without Omasnap, Tensaku edits" "$OUTPUT" "DRYRUN: tensaku --filename <private temp dir>/original.png"
rm "$SANDBOX/stubs/tensaku"
if ! command -v tensaku >/dev/null; then
    stub swappy 'echo "swappy $*" >>"$CALLS"'
    capture haseen capture screenshot window --edit --dry-run
    assert_contains "then swappy" "$OUTPUT" "DRYRUN: swappy -f <private temp dir>/original.png"
else
    echo "  skip: tensaku is installed on this host; the swappy fallback was not exercised" >&2
fi

# --- Omarchy's screenshot command, as 4.5's ----------------------------------------
# The cases of Omarchy's own test/shell.d/omasnap-test.sh@v4.5.0-rc1, plus
# haseen's folder and languages.
snap_sandbox p107-omarchy
check_oma() { # LABEL EXPECTED ARGS...
    local label=$1 want=$2
    shift 2
    : >"$CALLS"
    capture "$OMA/omarchy-capture-screenshot" "$@"
    assert_status "$label: exits 0" 0 "$STATUS"
    assert_eq "$label" "$want" "$(calls)"
}
check_oma "the default opens Omasnap with no arguments" "omasnap [$PICS] [ara+eng] "
OMARCHY_SCREENSHOT_DIR="$SANDBOX/legacy" check_oma "the legacy folder and copy map to Omasnap" \
    "omasnap [$SANDBOX/legacy] [ara+eng] windows --copy" windows copy
OMARCHY_SCREENSHOT_DIR="$SANDBOX/legacy" OMASNAP_SCREENSHOT_DIR="$SANDBOX/native" check_oma \
    "Omasnap's own folder wins, and save still works" "omasnap [$SANDBOX/native] [ara+eng] fullscreen --save" fullscreen save
check_oma "slurp is a harmless no-op" "omasnap [$PICS] [ara+eng] region" region slurp
check_oma "Omasnap's modes and flags pass through" "omasnap [$PICS] [ara+eng] scroll --save --editor=overlay" \
    scroll --save --editor=overlay
check_oma "copy and save stand anywhere" "omasnap [$PICS] [ara+eng] --copy smart" copy smart
capture "$OMA/omarchy-capture-screenshot" windows copy --dry-run
assert_eq "the plan" "DRYRUN: env OMASNAP_SCREENSHOT_DIR=$PICS OMASNAP_OCR_LANGS=ara+eng omasnap windows --copy" "$OUTPUT"
assert_dry_pure "omarchy-capture-screenshot plan" "$OUTPUT"
export HASEEN_SCREENSHOT_TOOL=grim
stub tensaku 'exit 0'
capture "$OMA/omarchy-capture-screenshot" save fullscreen --dry-run
assert_contains "without Omasnap: haseen's capture, in any order" "$OUTPUT" "DRYRUN: grim -o <focused monitor> $PICS/screenshot-"
capture "$OMA/omarchy-capture-screenshot" fullscreen --editor=overlay --dry-run
assert_contains "without Omasnap: --editor annotates first" "$OUTPUT" "original.png"
capture "$OMA/omarchy-capture-screenshot" scroll
assert_status "without Omasnap: scroll fails" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "scroll is Omasnap's mode"
unset HASEEN_SCREENSHOT_TOOL

# --- an image from the clipboard history opens in Omasnap ---------------------------
snap_sandbox p107-clipboard
stub cliphist 'case $1 in
list) printf "0\t[[ binary data 12 KiB png 10x10 ]]\n" ;;
decode) printf PNGDATA ;;
esac'
capture "$OMA/omarchy-clipboard-open" --history-index 0 --dry-run
assert_contains "the image is planned for Omasnap" "$OUTPUT" \
    "DRYRUN: env OMASNAP_SCREENSHOT_DIR=$PICS OMASNAP_OCR_LANGS=ara+eng omasnap $XDG_RUNTIME_DIR/haseen/clipboard-open.XXXXXX.png"
assert_not_contains "not Tensaku" "$OUTPUT" "tensaku"
: >"$CALLS"
capture "$OMA/omarchy-clipboard-open" --history-index 0
assert_status "the image opens" 0 "$STATUS"
assert_contains "in Omasnap" "$(calls)" "omasnap [$PICS] [ara+eng] $XDG_RUNTIME_DIR/haseen/clipboard-open."
HASEEN_SCREENSHOT_TOOL=grim capture "$OMA/omarchy-clipboard-open" --history-index 0 --dry-run
assert_contains "without Omasnap: tensaku-edit, as before" "$OUTPUT" "DRYRUN: tensaku-edit"

# --- the desktop layer and the migration ----------------------------------------------
manifest="$HASEEN_PATH/layers/desktop/packages.txt"
snap_sandbox p107-packages
capture bash -c 'source "$HASEEN_PATH/lib/packages.sh"; manifest_entries "$1" omarchy; echo --; manifest_entries "$1" aur; echo --; manifest_entries "$1" repo' _ "$manifest"
assert_status "the manifest reads" 0 "$STATUS"
assert_contains "Omasnap comes only from [omarchy]" "$(sed -n '1,/^--$/p' <<<"$OUTPUT")" "omasnap"
assert_not_contains "Tensaku is no longer installed" "$OUTPUT" "tensaku"
assert_contains "Arabic OCR data is kept" "$OUTPUT" "tesseract-data-ara"

# migrate_root NAME — a CachyOS machine whose desktop layer haseen applied.
migrate_root() {
    MROOT="$SANDBOX/$1"
    cp -a "$FIXTURES/desk-cachyos-amd/." "$MROOT/"
    mkdir -p "$MROOT/var/lib/haseen/layers" "$MROOT/var/lib/pacman/sync" "$MROOT/var/lib/pacman/local/tensaku-0.29.0-2"
    printf 'version=0.1\napplied=2026-10-14T00:00:00Z\n' >"$MROOT/var/lib/haseen/layers/desktop"
}
migration="$HASEEN_PATH/migrations/1792634179-omasnap.sh"
migrate_plan() {
    capture env DRY_RUN=true HASEEN_SYSROOT="$MROOT" HASEEN_MIGRATION=1792634179-omasnap.sh \
        bash -Eeuo pipefail "$migration"
}
snap_sandbox p107-migrate
migrate_root repo
printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = x\n' >>"$MROOT/etc/pacman.conf"
printf 'omarchy-keyring\nherdr\nomasnap\ntensaku\n' >"$MROOT/var/lib/pacman/sync/omarchy.pkgs"
migrate_plan
assert_status "with [omarchy]: the migration plans" 0 "$STATUS"
assert_dry_pure "migration plan" "$OUTPUT"
assert_eq "with [omarchy]: Omasnap is installed from it, and nothing else" \
    "DRYRUN: sudo pacman -S --needed omarchy/omasnap" "$OUTPUT"
mkdir -p "$MROOT/var/lib/pacman/local/omasnap-1.21.0-2"
migrate_plan
assert_eq "installed already: nothing to do" "0 " "$STATUS $OUTPUT"
migrate_root norepo
migrate_plan
assert_status "without [omarchy]: the migration still succeeds" 0 "$STATUS"
assert_contains "without [omarchy]: it says how to add Omasnap" "$OUTPUT" \
    "skipping omasnap: haseen installs them only from Omarchy's [omarchy] repo, which is not enabled. To add them: haseen layer apply omarchy-repo desktop"
assert_not_contains "without [omarchy]: nothing is installed from anywhere" "$OUTPUT" "DRYRUN"
migrate_root nodesktop
rm "$MROOT/var/lib/haseen/layers/desktop"
printf '[omarchy]\nServer = x\n' >>"$MROOT/etc/pacman.conf"
printf 'omasnap\n' >"$MROOT/var/lib/pacman/sync/omarchy.pkgs"
migrate_plan
assert_eq "without the desktop layer: nothing to do" "0 " "$STATUS $OUTPUT"

# --- binds, the overlay rule and the seed ---------------------------------------------
binds="$(cat "$HASEEN_PATH/default/hypr/binds.lua")"
assert_contains "PRINT is Omasnap's pick" "$binds" 'b("PRINT", "Screenshot", "haseen capture screenshot")'
assert_contains "SHIFT + PRINT stays the focused window at once" "$binds" '"haseen capture screenshot window"'
rules="$(sed -n '/name = "haseen_omasnap_overlay"/,/})/p' "$HASEEN_PATH/default/hypr/windowrules.lua")"
assert_contains "Omasnap's overlay opens without the layer fade" "$rules" 'match = { namespace = "^omasnap$" }'
assert_contains "and with no animation" "$rules" 'animation = "none"'
assert_not_contains "and stays in screen captures, which scrolling capture stitches" "$rules" "no_screen_share"

snap_sandbox p107-seed
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
capture haseen seed user --dry-run
assert_status "the seed dry run succeeds" 0 "$STATUS"
assert_not_contains "no Tensaku file is seeded" "$OUTPUT" "tensaku"
assert_contains "the uploader's file still is" "$OUTPUT" "DRYRUN: write $HOME/.config/haseen/upload.toml"
unset HASEEN_SYSROOT
assert_eq "haseen ships no Tensaku file any more" "" "$(find "$HASEEN_PATH" -iname '*tensaku*')"
assert_not_contains "and installs it from no source" "$(cat "$manifest")" "tensaku"
