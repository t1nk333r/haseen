# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 083: haseen.themegen's keyboard flow, the Wallhaven grid's paging and
# the panel's placement. The panel runs in the real engine (qs, offscreen) in
# a window of its own, with the CLI a stub that logs its argv and answers
# `wallhaven search` from generated pages, `wallhaven get` with a local file
# and `theme generate --json` with a preview recorded from the real CLI (on
# the matugen stub of tests/test-themegen.sh). Keys are real key events, sent
# into the harness window by QtTest's TestEvent through an IPC hook of the
# harness; the panel's state is read through its debugIpc `state`. Nothing
# reaches the network or the session.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.themegen"
M="$PLUGIN/manifest.json"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

sandbox themegen-keys

# --- the manifest ------------------------------------------------------------------------
# The plugin requires matugen; a stub that answers with the recorded scheme.
stub matugen "kind=\$1 mode=dark
while [ \$# -gt 0 ]; do [ \"\$1\" = -m ] && mode=\$2; shift; done
cat '$FIXTURES/matugen'/\$kind-\$mode.json"
capture haseen plugin validate haseen.themegen
assert_status "haseen.themegen validates with placement" 0 "$STATUS"
assert_eq "the panel opens in the middle of the screen" "center" "$(jq -r .settings.placement.default "$M")"
assert_eq "placement is a string, as haseen.menu declares it" "string" "$(jq -r .settings.placement.type "$M")"
assert_eq "four thumbnails to a row" "4" "$(jq -r .settings.columns.default "$M")"
assert_eq "no timers in the panel" "" "$(grep -n 'Timer' "$PLUGIN"/*.qml || true)"
assert_eq "no hex literals in the panel" "" "$(grep -nE '#[0-9A-Fa-f]{3,8}\b' "$PLUGIN"/*.qml || true)"

# --- the grid model under the Qt JS engine ----------------------------------------------
if [[ -x $QML_BIN ]]; then
    units="$SANDBOX/units"
    mkdir -p "$units"
    cat >"$units/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Wallhaven.js" as W
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const s = (i, n, dx, dy) => W.gridStep(i, n, 4, dx, dy);
        out("down", [s(0, 24, 0, 1), s(5, 24, 0, 1), s(20, 24, 0, 1), s(23, 24, 0, 1)]);
        out("up", [s(4, 24, 0, -1), s(2, 24, 0, -1), s(0, 24, 0, -1)]);
        out("side", [s(0, 24, -1, 0), s(3, 24, 1, 0), s(23, 24, 1, 0)]);
        out("shortRow", [s(1, 6, 0, 1), s(2, 6, 0, 1), s(3, 6, 0, 1), s(5, 6, 0, 1), s(4, 6, 0, -1)]);
        out("empty", [s(0, 0, 1, 0), s(-1, 6, 1, 0), W.gridStep(2, 6, 0, 0, 1)]);
        const seen = {};
        const a = W.fresh(seen, [{ id: "a" }, { id: "b" }, { id: "a" }]);
        const b = W.fresh(seen, [{ id: "b" }, { id: "c" }]);
        out("fresh", [a.map(i => i.id).join(""), b.map(i => i.id).join(""), Object.keys(seen).sort().join("")]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$units" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Units.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "grid: down moves by a row of 4, the last row stays" '[4,9,20,23]' "$(r down)"
    assert_eq "grid: up moves by a row, the first row stays" '[0,2,0]' "$(r up)"
    assert_eq "grid: left and right by one, clamped at both ends" '[0,4,23]' "$(r side)"
    assert_eq "grid: down into a shorter last row lands on the last cell" '[5,5,5,5,0]' "$(r shortRow)"
    assert_eq "grid: no cells, no cell yet, no columns" '[-1,0,3]' "$(r empty)"
    assert_eq "pages: only unseen ids are appended" '["ab","c","abc"]' "$(r fresh)"
else
    echo "  skip: $QML_BIN not installed, Wallhaven.js not exercised" >&2
fi

# --- the panel in the real engine ----------------------------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null || [[ ! -d /usr/lib/qt6/qml/QtTest ]]; then
    echo "  skip: qs, dbus-run-session or QtTest missing; the engine scenarios were not run" >&2
    return 0
fi

LOG="$SANDBOX/cli.log"
FIX="$SANDBOX/fix"
PICS="$SANDBOX/pics"
DL="$SANDBOX/dl"
mkdir -p "$FIX" "$PICS" "$DL"
thumb="$FIXTURES/wallhaven/thumb.jpg"
for n in a b c d e f; do cp "$FIXTURES/wallhaven/full-3q797y.jpg" "$PICS/$n.jpg"; done

# The preview the panel parses: the real CLI's --json on the matugen stub.
haseen theme generate "$PICS/a.jpg" --json >"$FIX/preview.json"
assert_eq "the recorded preview is a whole one" "new" "$(jq -r .target "$FIX/preview.json")"

# Search pages: 24 results a page, 3 pages; the query "few" has 6, one page.
page_json() { # PAGE COUNT LAST
    jq -n --arg thumb "$thumb" --argjson page "$1" --argjson n "$2" --argjson last "$3" \
        '{page: $page, last_page: $last, total: ($n * $last), seed: "",
          results: [range($n) | {id: ("p\($page)i\(.)"), thumb: $thumb, resolution: "1920x1080", url: ""}]}'
}
for p in 1 2 3; do page_json "$p" 24 3 >"$FIX/page-$p.json"; done
page_json 1 6 1 >"$FIX/few.json"

# The CLI: argv to the log; SLOW_GET / SLOW_PAGE (files) hold a reply back.
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/share/haseen" "$FAKE/bin"
for entry in "$HASEEN_PATH"/*; do ln -s "$entry" "$FAKE/share/haseen/${entry##*/}"; done
cat >"$FAKE/bin/haseen" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$LOG'
case "\$1 \$2" in
"wallhaven search")
    page=1 query=""
    while [ \$# -gt 0 ]; do
        case "\$1" in --page) page=\$2 ;; --query) query=\$2 ;; esac
        shift
    done
    [ "\$page" -gt 1 ] && [ -e '$SANDBOX/SLOW_PAGE' ] && sleep 2
    if [ "\$query" = few ]; then cat '$FIX/few.json'; else cat '$FIX/page-'"\$page"'.json'; fi ;;
"wallhaven get")
    [ -e '$SANDBOX/SLOW_GET' ] && sleep 3
    [ -e '$SANDBOX/FAIL_GET' ] && { echo "Error: network is unreachable" >&2; exit 1; }
    cp '$thumb' '$DL'/"\$3".jpg
    echo "progress 100" >&2
    echo '$DL'/"\$3".jpg ;;
"theme generate")
    case "\$*" in *--json*) cat '$FIX/preview.json' ;; esac ;;
esac
EOF
chmod +x "$FAKE/bin/haseen"

harness="$SANDBOX/shell"
mkdir -p "$harness"
for module in Haseen Compat Ui Commons plugins; do
    ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
done
cat >"$harness/shell.qml" <<'QML'
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugins/haseen.themegen" as Themegen

// The panel alone in a window; keys come from TestEvent, a QtTest object
// that sends real key events into this window, never into a session.
ShellRoot {
    Window {
        id: win

        width: 1300
        height: 1000
        visible: true
        Component.onCompleted: requestActivate()

        Themegen.Panel {
            pluginId: "haseen.themegen"
            settings: JSON.parse(Quickshell.env("THEMEGEN_SETTINGS"))
        }

        Item {
            TestEvent {
                id: events
            }
        }
    }

    IpcHandler {
        target: "keys"

        // A key by its Qt name ("Down", "Return", "Backspace", "Tab").
        function press(name: string): bool {
            return events.keyClick(Qt["Key_" + name], 0, -1);
        }

        // Characters as typed, one key each.
        function type(text: string): bool {
            let ok = true;
            for (const ch of text)
                ok = events.keyClickChar(ch, 0, -1) && ok;
            return ok;
        }
    }
}
QML

settings="$(jq -nc --arg pics "$PICS" '{debugIpc: true, directories: [$pics], depth: 1}')"
# Its own process group (setsid), so the end of the test stops all of it.
setsid env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
    QT_NO_XDG_DESKTOP_PORTAL=1 HASEEN_PATH="$FAKE/share/haseen" THEMEGEN_SETTINGS="$settings" \
    timeout 120 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness" \
    >"$SANDBOX/qs.log" 2>&1 &
qs_pid=$!

ipc() { "$QS_BIN" -p "$harness" ipc call "$@" 2>/dev/null; }
key() { for k in "$@"; do ipc keys press "$k" >/dev/null; done; }
typed() { ipc keys type "$1" >/dev/null; }
state() { ipc haseen.themegen state; }
# until_state LABEL JQ — the panel's state once JQ holds (10 s at most).
until_state() {
    local i
    for ((i = 0; i < 100; i++)); do
        STATE="$(state || true)"
        if [[ -n $STATE ]] && jq -e "$2" <<<"$STATE" >/dev/null 2>&1; then
            _pass
            return 0
        fi
        sleep 0.1
    done
    _fail "$1" "state: $(jq -c 'del(.preview)' <<<"$STATE" 2>/dev/null || echo "$STATE")"$'\n'"$(tail -n 20 "$SANDBOX/qs.log")"
}
s() { jq -c "$1" <<<"$(state)"; }
applies() { grep -v -e '--json' -e '^wallhaven' "$LOG" || true; }

until_state "the panel starts on the local images, in the search field" \
    '.count == 6 and .stage == "search" and .preview.ok'

# h j k l in the search field are text, not moves.
typed "hjkl"
assert_eq "search: h j k l land in the field" '["hjkl","search",0]' "$(s '[.query, .stage, .strip]')"
key Backspace Backspace Backspace Backspace
assert_eq "search: Backspace edits the field" '["","search",6]' "$(s '[.query, .stage, .shown]')"

# The pictures: Down enters them; h/l step by one, j/k by a row (two rows of
# four here, six images), as in the Wallhaven grid.
key Down
assert_eq "images: Down from the field" '"images"' "$(s .stage)"
typed "ll"
key Right
typed "h"
assert_eq "images: l l Right h" '2' "$(s .strip)"
typed "j"
assert_eq "images: j from the first row to the short second row's last" '5' "$(s .strip)"
key Up
assert_eq "images: Up a row" '1' "$(s .strip)"
key Up
assert_eq "images: Up on the first row stays" '1' "$(s .strip)"
typed "/"
assert_eq "images: / goes back to the field" '"search"' "$(s .stage)"
key Return
assert_eq "search: Enter (the filter applied) goes to the pictures" '"images"' "$(s .stage)"
key Backspace
assert_eq "images: Backspace goes back to the field" '"search"' "$(s .stage)"
key Down Return
until_state "images: Enter picks the picture and moves to the palette" \
    ".stage == \"palette\" and .image == \"$PICS/b.jpg\" and .ready"

# The palette: h/l and j/k change the scheme, Tab the mode.
typed "l"
assert_eq "palette: l is the next scheme" '"content"' "$(s .scheme)"
typed "h"
key Down Down
typed "k"
assert_eq "palette: h, Down Down, k" '"content"' "$(s .scheme)"
key Tab
assert_eq "palette: Tab flips dark/light" '"light"' "$(s .mode)"
key Backspace
assert_eq "palette: Backspace goes back to the pictures" '"images"' "$(s .stage)"
key Return
until_state "images: Enter again" '.stage == "palette" and .ready'
: >"$LOG"
key Return
for ((i = 0; i < 50; i++)); do [[ -n $(applies) ]] && break; sleep 0.1; done
assert_eq "palette: Enter applies, the scheme and mode chosen by key" \
    "theme generate $PICS/b.jpg --scheme content --mode light --name b" "$(applies)"

# Wallhaven: the grid, paging and the download before Apply.
ipc haseen.themegen setSource wallhaven >/dev/null
until_state "wallhaven: the first page" '.source == "wallhaven" and .wallhaven.count == 24 and .wallhaven.current == 0'
typed "/"
typed "hjkl"
assert_eq "wallhaven: h j k l in the search field are text" '["hjkl","search",0]' "$(s '[.query, .stage, .wallhaven.current]')"
key Backspace Backspace Backspace Backspace
typed "sky"
key Return
until_state "wallhaven: Enter searches and moves to the pictures" \
    '.stage == "images" and .wallhaven.page == 1 and .wallhaven.count == 24'
assert_contains "wallhaven: the query reached the CLI" "$(cat "$LOG")" "wallhaven search --query sky --sort toplist --page 1 --json"
typed "j"
assert_eq "grid: j moves down a row" '4' "$(s .wallhaven.current)"
typed "l"
assert_eq "grid: l moves right by one" '5' "$(s .wallhaven.current)"
key Up Up
assert_eq "grid: Up moves a row up, the first row stays" '1' "$(s .wallhaven.current)"
typed "hh"
assert_eq "grid: h stops at the first cell" '0' "$(s .wallhaven.current)"
assert_eq "grid: moving downloaded nothing" "" "$(grep 'wallhaven get' "$LOG" || true)"

# Down to the last row: the grid scrolls, reaches its end and loads page 2,
# which is held back so the position can be read before it lands.
touch "$SANDBOX/SLOW_PAGE"
typed "jjjjj"
until_state "grid: the last row of page 1, scrolled" '.wallhaven.current == 20 and .wallhaven.scrollY > 0'
before="$(s .wallhaven.scrollY)"
until_state "grid: page 2 appended" '.wallhaven.page == 2 and .wallhaven.count == 48'
rm "$SANDBOX/SLOW_PAGE"
assert_eq "grid: page 2 kept the scroll position and the cell" "[$before,20]" "$(s '[.wallhaven.scrollY, .wallhaven.current]')"
typed "j"
assert_eq "grid: and moving on goes into page 2" '24' "$(s .wallhaven.current)"

# A new search starts at the top.
typed "/"
key Backspace Backspace Backspace
typed "few"
key Return
until_state "grid: a new search starts at the top" \
    '.wallhaven.count == 6 and .wallhaven.page == 1 and .wallhaven.current == 0 and .wallhaven.scrollY == 0'
typed "lljj"
assert_eq "grid: down into a shorter last row lands on the last cell" '5' "$(s .wallhaven.current)"
typed "khll"
assert_eq "grid: k h l l" '2' "$(s .wallhaven.current)"

# Enter downloads; Enter on the palette waits for the picture's preview.
touch "$SANDBOX/SLOW_GET"
: >"$LOG"
key Return
until_state "wallhaven: Enter starts the download and moves to the palette" \
    '.stage == "palette" and .wallhaven.downloading == "p1i2" and (.ready | not)'
key Return
assert_eq "wallhaven: Enter during the download applies nothing" "" "$(applies)"
assert_contains "wallhaven: and says why" "$(s .notice)" "still downloading"
until_state "wallhaven: the download previewed" \
    ".wallhaven.downloading == \"\" and .image == \"$DL/p1i2.jpg\" and .ready"
rm "$SANDBOX/SLOW_GET"
key Return
for ((i = 0; i < 50; i++)); do [[ -n $(applies) ]] && break; sleep 0.1; done
assert_eq "wallhaven: then Enter applies the downloaded picture" \
    "theme generate $DL/p1i2.jpg --scheme content --mode light --name wallhaven-p1i2" "$(applies)"

# A pick whose download fails: the picture on show before (p1i2) is dropped
# at the pick, so neither Enter nor Apply uses it, and the panel goes back to
# the pictures with the error.
touch "$SANDBOX/SLOW_GET" "$SANDBOX/FAIL_GET"
: >"$LOG"
key Backspace
typed "l"
key Return
until_state "wallhaven: a new pick drops the picture on show" \
    '.stage == "palette" and .wallhaven.downloading == "p1i3" and .image == "" and (.ready | not) and (.preview.ok | not)'
key Return
until_state "wallhaven: a failed download goes back to the pictures, nothing ready" \
    '.stage == "images" and .wallhaven.downloading == "" and .image == "" and (.ready | not)'
assert_contains "wallhaven: and shows the download's error" "$(s .notice)" "network is unreachable"
rm "$SANDBOX/SLOW_GET"
ipc haseen.themegen apply >/dev/null
key Backspace Down Return
for ((i = 0; i < 30; i++)); do [[ $(grep -c 'wallhaven get' "$LOG") -ge 2 ]] && break; sleep 0.1; done
until_state "wallhaven: the second failed pick also ends on the pictures" '.stage == "images" and .wallhaven.downloading == "" and (.ready | not)'
assert_eq "wallhaven: nothing applied after a failed download (Enter, Apply)" "" "$(applies)"
rm "$SANDBOX/FAIL_GET"

kill -- -"$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true
