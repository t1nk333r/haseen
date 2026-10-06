# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Screen frame, transparent bar, chevron tray (plan 015): the `haseen bar …`
# commands (dry-run purity, shell.json persistence, IPC calls), the
# wallpaper-sampling text colour script, and the contracts between the CLI
# and the QML (IPC function names, positions, frame surfaces).

SHELL_DIR="$HASEEN_PATH/shell"

# record CMD — a stub that echoes its argv instead of failing.
record() { stub "$1" "echo \"$1: \$*\""; }
# ipc_stub — qs appends its argv to $SANDBOX/qs.log (the bar commands hide
# the IPC answer, so the call is checked from the log). ipc_calls prints and
# clears it.
ipc_stub() { stub qs "echo \"qs: \$*\" >>'$SANDBOX/qs.log'"; }
ipc_calls() {
    cat "$SANDBOX/qs.log" 2>/dev/null || true
    : >"$SANDBOX/qs.log"
}

# ppm FILE W H ROW... — a plain PPM; each ROW is one "r g b" triple used for
# a horizontal band, bands split the height evenly. ImageMagick reads it, so
# the fixtures need no image tools to create.
ppm() {
    local file="$1" w="$2" h="$3" bands y x
    shift 3
    bands=$#
    {
        printf 'P3\n%d %d\n255\n' "$w" "$h"
        local rows=("$@")
        for ((y = 0; y < h; y++)); do
            for ((x = 0; x < w; x++)); do printf '%s ' "${rows[$((y * bands / h))]}"; done
            printf '\n'
        done
    } >"$file"
}

# ppm_cols FILE W H LEFT RIGHT — left half LEFT, right half RIGHT.
ppm_cols() {
    local file="$1" w="$2" h="$3" y x
    {
        printf 'P3\n%d %d\n255\n' "$w" "$h"
        for ((y = 0; y < h; y++)); do
            for ((x = 0; x < w; x++)); do
                if ((x < w / 2)); then printf '%s ' "$4"; else printf '%s ' "$5"; fi
            done
            printf '\n'
        done
    } >"$file"
}

CFG() { printf '%s' "$XDG_CONFIG_HOME/haseen/shell.json"; }
FG='#dcd7ba' # light theme text
BG='#16161d' # dark theme background

# --- help and headers -------------------------------------------------------
sandbox frame-help
for c in transparent position toggle tray text-color; do
    f="$REPO/bin/haseen-bar-$c"
    assert_eq "haseen-bar-$c is executable" yes "$([[ -x $f ]] && echo yes || echo no)"
    assert_contains "haseen-bar-$c has a summary" "$(cat "$f")" "# haseen:summary "
    assert_contains "haseen-bar-$c has args" "$(cat "$f")" "# haseen:args "
    capture haseen bar "$c" --help
    assert_status "bar $c --help exits 0" 0 "$STATUS"
    assert_contains "bar $c --help prints usage" "$OUTPUT" "Usage: haseen bar $c"
done
for c in transparent position toggle tray; do
    assert_contains "haseen-bar-$c takes --dry-run" "$(sed -n 's/^# haseen:args //p' "$REPO/bin/haseen-bar-$c")" "--dry-run"
done
assert_contains "text-color is an internal helper" "$(cat "$REPO/bin/haseen-bar-text-color")" "# haseen:hidden"
capture haseen commands bar
assert_not_contains "hidden helper not listed" "$OUTPUT" "text-color"
assert_contains "bar commands listed" "$OUTPUT" "haseen bar transparent"

# --- transparent: dry run is pure and writes nothing ----------------------
sandbox frame-transparent
capture haseen bar transparent --dry-run
assert_status "transparent --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "transparent --dry-run" "$OUTPUT"
assert_contains "dry run shows the write" "$OUTPUT" "DRYRUN: write $(CFG).new"
assert_contains "dry run shows the new value" "$OUTPUT" '"transparent": true'
assert_contains "dry run shows the IPC apply" "$OUTPUT" "DRYRUN: haseen shell ipc bar transparent on"
assert_eq "dry run created no shell.json" no "$([[ -e $(CFG) ]] && echo yes || echo no)"

# Real runs: qs records the IPC call instead of failing.
ipc_stub
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"right":["haseen.clock"]},"plugins":{"me.x":{"enabled":false}}}\n' >"$(CFG)"
capture haseen bar transparent
assert_status "transparent (toggle) exits 0" 0 "$STATUS"
assert_eq "toggle from default turns it on" true "$(jq '.bar.transparent' "$(CFG)")"
assert_eq "other bar keys survive" '["haseen.clock"]' "$(jq -c '.bar.right' "$(CFG)")"
assert_eq "other plugin entries survive" false "$(jq '.plugins["me.x"].enabled' "$(CFG)")"
assert_eq "applies live over IPC" "qs: -p $HASEEN_PATH/shell ipc call bar transparent on" "$(ipc_calls)"
capture haseen bar transparent toggle
assert_eq "toggle again turns it off" false "$(jq '.bar.transparent' "$(CFG)")"
assert_contains "toggle off applies live" "$(ipc_calls)" "ipc call bar transparent off"
capture haseen bar transparent on --no-apply
assert_eq "on" true "$(jq '.bar.transparent' "$(CFG)")"
assert_eq "--no-apply skips IPC (the shell's own persist call)" "" "$(ipc_calls)"
before="$(cat "$(CFG)")"
capture haseen bar transparent on --dry-run
assert_dry_pure "transparent on --dry-run (already on)" "$OUTPUT"
assert_not_contains "no write when already on" "$OUTPUT" "DRYRUN: write"
assert_eq "dry run left the file alone" "$before" "$(cat "$(CFG)")"
capture haseen bar transparent sideways
assert_status "unknown mode is a usage error" 2 "$STATUS"
capture haseen bar transparent on off
assert_status "two modes is a usage error" 2 "$STATUS"

# No running shell: the value is saved and the user told.
stub qs 'echo "No running instances" >&2; exit 1'
capture haseen bar transparent off
assert_status "no shell running still succeeds" 0 "$STATUS"
assert_eq "saved without a shell" false "$(jq '.bar.transparent' "$(CFG)")"
assert_contains "says when it applies" "$OUTPUT" "applies at the next start"

# An unreadable user file is never overwritten.
printf '{"bar": ' >"$(CFG)"
capture haseen bar transparent on
assert_status "invalid shell.json refused" 1 "$STATUS"
assert_eq "invalid shell.json untouched" '{"bar": ' "$(cat "$(CFG)")"

# --- position ---------------------------------------------------------------
sandbox frame-position
capture haseen bar position left --dry-run
assert_dry_pure "position --dry-run" "$OUTPUT"
assert_contains "position dry run shows the value" "$OUTPUT" '"position": "left"'
assert_contains "position dry run shows the IPC apply" "$OUTPUT" "DRYRUN: haseen shell ipc bar position left"
assert_eq "position dry run wrote nothing" no "$([[ -e $(CFG) ]] && echo yes || echo no)"
ipc_stub
for p in bottom left right top; do
    capture haseen bar position "$p"
    assert_status "position $p exits 0" 0 "$STATUS"
    assert_eq "position $p saved" "$p" "$(jq -r '.bar.position' "$(CFG)")"
    assert_contains "position $p applied live" "$(ipc_calls)" "ipc call bar position $p"
done
capture haseen bar position middle
assert_status "unknown position is a usage error" 2 "$STATUS"
capture haseen bar position
assert_status "position needs an edge" 2 "$STATUS"

# --- tray pin -----------------------------------------------------------------
sandbox frame-tray
capture haseen bar tray pin --dry-run
assert_dry_pure "tray pin --dry-run" "$OUTPUT"
assert_contains "tray dry run shows the setting" "$OUTPUT" '"pinned": true'
assert_contains "tray dry run shows the IPC apply" "$OUTPUT" "DRYRUN: haseen shell ipc bar tray pin"
ipc_stub
capture haseen bar tray
assert_eq "tray toggle pins" true "$(jq '.plugins["haseen.tray"].settings.pinned' "$(CFG)")"
assert_contains "tray pin applied live" "$(ipc_calls)" "ipc call bar tray pin"
capture haseen bar tray unpin
assert_eq "tray unpin" false "$(jq '.plugins["haseen.tray"].settings.pinned' "$(CFG)")"
capture haseen bar tray stick
assert_status "unknown tray mode is a usage error" 2 "$STATUS"
assert_eq "manifest declares the pinned setting" "boolean false" \
    "$(jq -r '.settings.pinned | "\(.type) \(.default)"' "$SHELL_DIR/plugins/haseen.tray/manifest.json")"
tray_dir="$SHELL_DIR/plugins/haseen.tray"
tray="$(cat "$tray_dir/Widget.qml")"
assert_contains "tray keeps the Omarchy notice" "$tray" "Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml"
assert_contains "NOTICE lists the tray port" "$(cat "$REPO/NOTICE.md")" '`share/haseen/shell/plugins/haseen.tray/`'
# When the drawer is open, under the real Qt JS engine: hover reveals, the
# pin holds, an open item menu holds it, the grace after leaving holds it.
H="$SANDBOX/drawer"
mkdir -p "$H"
cat >"$H/Drawer.qml" <<EOF
import QtQuick
import "file://$tray_dir/Drawer.js" as D

Item {
    Component.onCompleted: {
        const s = (p, h, m, l) => ({ pinned: p, hovered: h, menuOpen: m, lingering: l });
        const rows = [["collapsed", s(false, false, false, false)], ["hover", s(false, true, false, false)],
                      ["pinned", s(true, false, false, false)], ["menu", s(false, false, true, false)],
                      ["grace", s(false, false, false, true)]];
        for (const [name, st] of rows)
            console.warn("DRAWER " + name + " open=" + D.isOpen(st) + " grace=" + D.startsGrace(st));
        Qt.exit(0);
    }
}
EOF
drawer="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "${QML_BIN:-/usr/lib/qt6/bin/qml}" "$H/Drawer.qml" 2>&1 | grep -o 'DRAWER .*' || true)"
assert_contains "collapsed until hovered" "$drawer" "DRAWER collapsed open=false grace=true"
assert_contains "hover reveals, no grace while hovered" "$drawer" "DRAWER hover open=true grace=false"
assert_contains "pinned stays open, no grace" "$drawer" "DRAWER pinned open=true grace=false"
assert_contains "an open item menu holds the drawer" "$drawer" "DRAWER menu open=true grace=false"
assert_contains "the grace after leaving holds the drawer" "$drawer" "DRAWER grace open=true grace=true"
assert_contains "chevron click toggles the pin" "$tray" "root.togglePinned();"
assert_contains "chevron click persists through the bar CLI" "$tray" '"bar", "tray", next ? "pin" : "unpin", "--no-apply"'
assert_contains "passive items stay hidden" "$tray" "item.status !== Status.Passive"
item="$(cat "$tray_dir/TrayItem.qml")"
for call in "modelData.activate()" "modelData.secondaryActivate()" "modelData.scroll(event.angleDelta.y, false)" "root.menuRequested("; do
    assert_contains "tray item calls $call" "$item" "$call"
done
menu="$(cat "$tray_dir/TrayMenu.qml")"
assert_contains "menu drills into submenus" "$menu" "function enterSubmenu("
assert_contains "menu entries trigger" "$menu" "entry.modelData.triggered();"
assert_contains "menu settle is a marked UI timeout" "$menu" $'// haseen:ui-timeout\n    Timer {'
assert_contains "menu closes on outside click" "$menu" "HyprlandFocusGrab {"

# --- toggle (session only) --------------------------------------------------
sandbox frame-toggle
capture haseen bar toggle --dry-run
assert_dry_pure "toggle --dry-run" "$OUTPUT"
assert_contains "toggle dry run shows the IPC call" "$OUTPUT" "haseen-shell-ipc bar toggle"
record qs
capture haseen bar toggle
assert_eq "toggle calls bar.toggle" "qs: -p $HASEEN_PATH/shell ipc call bar toggle" "$OUTPUT"
assert_eq "toggle saves nothing" no "$([[ -e $(CFG) ]] && echo yes || echo no)"
capture haseen bar toggle now
assert_status "toggle takes no argument" 2 "$STATUS"

# --- text colour: wallpaper decisions -----------------------------------------
sandbox frame-textcolor
W="$SANDBOX/wall"
mkdir -p "$W"
ppm "$W/dark.ppm" 8 8 "16 16 24"
ppm "$W/light.ppm" 8 8 "244 241 232"
ppm "$W/top-dark.ppm" 8 8 "10 10 10" "250 250 250"
ppm_cols "$W/left-light.ppm" 8 8 "250 250 250" "10 10 10"
tc() { capture haseen bar text-color "$@"; }
if command -v magick >/dev/null; then
    tc top 28 "$FG" "$BG" --background "$W/dark.ppm" --screen 160x90
    assert_eq "dark wallpaper keeps the light theme text" "$FG" "$OUTPUT"
    tc top 28 "$FG" "$BG" --background "$W/light.ppm" --screen 160x90
    assert_eq "light wallpaper takes the contrast colour" "$BG" "$OUTPUT"
    tc top 10 "$FG" "$BG" --background "$W/top-dark.ppm" --screen 160x90
    assert_eq "top bar samples the top strip (dark)" "$FG" "$OUTPUT"
    tc bottom 10 "$FG" "$BG" --background "$W/top-dark.ppm" --screen 160x90
    assert_eq "bottom bar samples the bottom strip (light)" "$BG" "$OUTPUT"
    tc left 10 "$FG" "$BG" --background "$W/left-light.ppm" --screen 160x90
    assert_eq "left bar samples the left strip (light)" "$BG" "$OUTPUT"
    tc right 10 "$FG" "$BG" --background "$W/left-light.ppm" --screen 160x90
    assert_eq "right bar samples the right strip (dark)" "$FG" "$OUTPUT"
    # A light theme (dark text, light background) inverts on a dark wallpaper.
    tc top 28 '#1a1a1a' '#f5f5f5' --background "$W/dark.ppm" --screen 160x90
    assert_eq "light theme on a dark wallpaper inverts" '#f5f5f5' "$OUTPUT"
    # Default source: $HASEEN_USER_STATE/current/background, followed as a link.
    mkdir -p "$XDG_STATE_HOME/haseen/current"
    ln -sfn "$W/light.ppm" "$XDG_STATE_HOME/haseen/current/background"
    tc top 28 "$FG" "$BG" --screen 160x90
    assert_eq "samples current/background by default" "$BG" "$OUTPUT"
    ln -sfn "$W/dark.ppm" "$XDG_STATE_HOME/haseen/current/background"
    tc top 28 "$FG" "$BG" --screen 160x90
    assert_eq "follows the link to the new wallpaper" "$FG" "$OUTPUT"
    rm "$XDG_STATE_HOME/haseen/current/background"
else
    echo "  (magick missing: wallpaper decisions not exercised, fallbacks only)" >&2
fi
tc top 28 "$FG" "$BG" --screen 160x90
assert_eq "no wallpaper falls back to the theme text" "$FG" "$OUTPUT"
tc top 28 "$FG" "$BG" --background "$W/missing.png" --screen 160x90
assert_eq "missing wallpaper falls back" "$FG" "$OUTPUT"
tc diagonal 28 "$FG" "$BG" --background "$W/light.ppm" --screen 160x90
assert_eq "bad position falls back" "$FG" "$OUTPUT"
tc top 28 "dcd7ba" "$BG" --background "$W/light.ppm" --screen 160x90
assert_eq "bad text colour is echoed back (nothing better known)" "dcd7ba" "$OUTPUT"
tc top 28 "$FG" "$BG" --background "$W/light.ppm"
assert_eq "no screen size (hyprctl stubbed) falls back" "$FG" "$OUTPUT"
assert_dry_pure "text-color never runs a stubbed binary visibly" "$OUTPUT"
tc bottom 200 "$FG" "$BG" --background "$W/light.ppm" --screen 160x90
assert_eq "bar taller than the screen falls back" "$FG" "$OUTPUT"
stub magick 'exit 1'
tc top 28 "$FG" "$BG" --background "$W/light.ppm" --screen 160x90
assert_eq "failing ImageMagick falls back" "$FG" "$OUTPUT"

# --- contracts: CLI <-> QML -----------------------------------------------------
sandbox frame-contract
shell_qml="$(cat "$SHELL_DIR/shell.qml")"
assert_contains "shell.qml exposes the bar IPC target" "$shell_qml" 'target: "bar"'
for fn in toggle transparent position tray status; do
    assert_contains "bar IPC has $fn()" "$shell_qml" "function $fn("
done
# Every `bar <fn>` the CLI sends exists in shell.qml.
sent="$(grep -ohE 'haseen-shell-ipc" bar [a-z]+|shell-ipc bar [a-z]+|ipc bar [a-z]+' "$REPO"/bin/haseen-bar-* | awk '{print $NF}' | sort -u)"
for fn in $sent; do
    assert_contains "CLI call bar.$fn exists in QML" "$shell_qml" "function $fn("
done
assert_eq "QML and CLI agree on bar positions" '"top", "bottom", "left", "right"' \
    "$(sed -n 's/.*readonly property string barPosition: \[\(.*\)\]\.indexOf.*/\1/p' "$SHELL_DIR/Haseen/Config.qml")"
assert_contains "CLI accepts the same positions" "$(cat "$REPO/bin/haseen-bar-position")" '^(top|bottom|left|right)$'
edge="$(cat "$SHELL_DIR/FrameEdge.qml")"
assert_contains "frame strips reserve their thickness" "$edge" "exclusiveZone: thickness"
assert_contains "frame strips take no input" "$edge" "mask: Region {}"
corners="$(cat "$SHELL_DIR/FrameCorners.qml")"
assert_contains "corner rows take no input" "$corners" "mask: Region {}"
assert_contains "corner rows sit inside the free area" "$corners" "exclusiveZone: 0"
assert_contains "bar can turn transparent (alpha surface)" "$(cat "$SHELL_DIR/Bar.qml")" "surfaceFormat.opaque: false"
assert_contains "strips can turn transparent (alpha surface)" "$edge" "surfaceFormat.opaque: false"
assert_contains "transparent text colour reaches widgets" "$(cat "$SHELL_DIR/Haseen/Theme.qml")" "property color barForeground: foreground"
assert_contains "text colour script is the one the shell runs" "$(cat "$SHELL_DIR/FrameTextColor.qml")" '"/../../bin/haseen-bar-text-color"'
assert_eq "no hex colour literals in frame/bar QML" "" \
    "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$SHELL_DIR"/{Bar,BarSection,Frame,FrameEdge,FrameCorners,FrameCorner,FrameTextColor}.qml || true)"
