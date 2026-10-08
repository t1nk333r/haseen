# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Starter widgets B (plan 022): haseen.clipboard, haseen.weather,
# haseen.bluetooth and the haseen.network Wi-Fi panel. Manifests validate,
# timers follow the resource rule, widgets use Theme tokens only, radios
# are only scanned from panels, and the pure parser Cliphist.js runs under
# the stock `qml` tool. haseen.weather's model, commands and service are
# exercised in tests/test-weather.sh.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
IDS=(haseen.clipboard haseen.weather haseen.bluetooth haseen.network)
DIRS=()
for id in "${IDS[@]}"; do DIRS+=("$PLUGINS/$id"); done

# --- manifests ---------------------------------------------------------------
sandbox widgets-b
capture haseen plugin validate "${IDS[@]}"
assert_status "widgets-b validate" 0 "$STATUS"
for id in "${IDS[@]}"; do
    assert_contains "$id validates" "$OUTPUT" "ok: $id (builtin:"
done
assert_eq "weather and network (panel ping) ask for network" "2" "$(grep -c "requests unrestricted 'network'" <<<"$OUTPUT")"
assert_dry_pure "plugin validate" "$OUTPUT"

kinds() { jq -r '.kinds | join(",")' "$PLUGINS/$1/manifest.json"; }
assert_eq "clipboard kinds" "service,panel,launcher-provider" "$(kinds haseen.clipboard)"
assert_eq "weather kinds" "service,bar-widget,panel" "$(kinds haseen.weather)"
assert_eq "bluetooth kinds" "bar-widget,panel" "$(kinds haseen.bluetooth)"
assert_eq "network kinds" "bar-widget,panel" "$(kinds haseen.network)"
assert_eq "clipboard provides clipboard" "clipboard" "$(jq -r '.provides | join(",")' "$PLUGINS/haseen.clipboard/manifest.json")"
assert_eq "weather provides weather" "weather" "$(jq -r '.provides | join(",")' "$PLUGINS/haseen.weather/manifest.json")"
assert_eq "clipboard and weather roles have no other provider" "" \
    "$(jq -r '.provides[]?' "$PLUGINS"/*/manifest.json | sort | uniq -d | grep -xE 'clipboard|weather' || true)"
for id in "${IDS[@]}"; do
    assert_eq "$id debugIpc defaults off" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGINS/$id/manifest.json")"
done
assert_eq "weather location defaults to automatic (GeoClue, else IP)" "" "$(jq -r '.settings.location.default' "$PLUGINS/haseen.weather/manifest.json")"

# --- theme tokens and timers ---------------------------------------------------
assert_eq "no hex colour literals" "" "$(grep -rnE '"#[0-9a-fA-F]{3,8}"' "${DIRS[@]}" || true)"
assert_eq "bar widgets use Theme.barForeground, never Theme.foreground" "" \
    "$(grep -n 'Theme\.foreground' "$PLUGINS"/haseen.{weather,bluetooth,network}/Widget.qml || true)"
# No Timer outside the network panel (Omarchy port, samples only while open)
# and the weather plugin (Omarchy port: a 15-minute sample in its service,
# single-shot retries and a search debounce); tests/test-shell.sh checks the
# markers of both.
timers="$(find "${DIRS[@]}" -name '*.qml' -exec awk '
    /^[[:space:]]*Timer[[:space:]]*\{/ { print FILENAME ":" FNR ":" prev; inside = 1; next }
    inside && /^[[:space:]]*interval:/ { print "  " $0 }
    inside && /^[[:space:]]*running:/ { print "  " $0 }
    inside && /^[[:space:]]*\}/ { inside = 0 }
    { prev = $0 }
' {} +)"
assert_eq "no Timer outside the network panel and the weather plugin" "0" \
    "$(grep -v -e '/haseen.network/Panel.qml:' -e '/haseen.weather/' <<<"$timers" | grep -c '^/' || true)"

# --- radios: scanning only from open panels -------------------------------------
assert_eq "bar widgets never scan" "" \
    "$(grep -nE 'discovering|scannerEnabled' "$PLUGINS"/haseen.{bluetooth,network}/Widget.qml || true)"
bt="$(cat "$PLUGINS/haseen.bluetooth/Panel.qml")"
assert_contains "bluetooth panel starts discovery" "$bt" "adapter.discovering = true"
assert_contains "bluetooth panel stops discovery on close" "$bt" $'Component.onDestruction: {\n        if (adapter && adapter.discovering)\n            adapter.discovering = false;'
net="$(cat "$PLUGINS/haseen.network/Panel.qml")"
assert_contains "network panel starts the scanner" "$net" "wifiDevice.scannerEnabled = true"
assert_contains "network panel stops the scanner on close" "$net" $'Component.onDestruction: {\n        if (wifiDevice)\n            wifiDevice.scannerEnabled = false;'
# Test hooks never mutate radios or connections.
hooks() { awk '/IpcHandler \{/,/^    \}$/' "$PLUGINS/$1/Panel.qml"; }
assert_eq "bluetooth hook calls no device or adapter mutators" "" \
    "$(hooks haseen.bluetooth | grep -nE 'connect\(|pair\(|forget\(|enabled =|discovering =' || true)"
assert_eq "network hook calls no connection mutators" "" \
    "$(hooks haseen.network | grep -nE 'connect\(|connectWithPsk|forget\(' || true)"
assert_not_contains "network hook never toggles wifi" "$(hooks haseen.network)" "wifiEnabled ="

# --- clipboard watcher ---------------------------------------------------------
svc="$(cat "$PLUGINS/haseen.clipboard/Service.qml")"
assert_contains "watcher pipes wl-paste into cliphist store" "$svc" 'exec \"$@\" wl-paste --type \"$t\" --watch cliphist -max-items \"$n\" store'
assert_contains "watcher dies with the shell" "$svc" "setpriv --pdeathsig TERM"
assert_contains "text watcher" "$svc" 'type: "text"'
assert_contains "image watcher" "$svc" 'type: "image"'
assert_contains "missing tools exit 127 before wl-paste runs" "$svc" "command -v cliphist >/dev/null || exit 127"
assert_eq "no privilege escalation" "" "$(grep -rnE '\b(sudo|pkexec|run_root)\b' "${DIRS[@]}" || true)"
assert_eq "clipboard launcher prefix is >" '">"' "$(sed -n 's/^ *readonly property string prefix: //p' "$PLUGINS/haseen.clipboard/Provider.qml")"

# --- pure parsers under qml ----------------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    {
        printf 'var list = %s;\n' "$(printf '12\thello world\n11\t[[ binary data 2 KiB png 80x80 ]]\n10\t[[ binary data 9 KiB jpg 10x10 ]]\n9\t[[ binary data 1 KiB application/octet-stream ]]\nnot a line\n8\tSecond Line here\n' | jq -Rs .)"
        printf 'var big = %s;\n' "$(printf '21\t[[ binary data 52 MiB png 7680x4320 ]]\n20\t[[ binary data 3 MiB png 9000x9000 ]]\n19\t[[ binary data 400 KiB jpg 1920x1080 ]]\n' | jq -Rs .)"
    } >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.clipboard/Cliphist.js" as C
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const rows = C.parse(D.list);
        out("clip", rows);
        out("filter", C.filter(rows, "LINE sec").map(r => r.id));
        out("filterAll", C.filter(rows, "  ").length);
        out("types", rows.map(r => r.type));
        const big = C.parse(D.big);
        out("meta", big.map(r => [r.type, r.size, r.bytes, r.width, r.height]));
        out("large", big.map(r => C.tooLarge(r, 8388608, 12000000)));
        out("human", [C.humanSize(0), C.humanSize(1536), C.humanSize(8388608), C.humanSize(-1)]);
        out("summary", [C.summary(rows[0], 42, 3), C.summary(big[2], -1, 0)]);
        out("limit", [C.limit(3000000000, 7), C.limit(0.2, 7), C.limit(-1, 7), C.limit(Infinity, 7), C.limit("9", 7), C.limit(8388608, 7)]);
        out("cacheDir", [C.cacheDir(undefined), C.cacheDir(""), C.cacheDir("run/user/1"), C.cacheDir("/run/user/1")]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    c="$(r clip)"
    assert_eq "cliphist: rows" "12 11 10 9 8" "$(jq -r '[.[].id] | join(" ")' <<<"$c")"
    assert_eq "cliphist: image kinds" "false:false: true:true:png true:true:jpeg false:true: false:false:" \
        "$(jq -r '[.[] | "\(.image):\(.binary):\(.ext)"] | join(" ")' <<<"$c")"
    assert_eq "cliphist: line kept verbatim for decode" "$(printf '12\thello world')" "$(jq -r '.[0].line' <<<"$c")"
    assert_eq "cliphist: every word matches, any case" '["8"]' "$(r filter)"
    assert_eq "cliphist: blank query keeps all" "5" "$(r filterAll)"
    assert_eq "cliphist: cliphist's own type word" "text png jpg application/octet-stream text" "$(jq -r 'join(" ")' <<<"$(r types)")"
    assert_eq "cliphist: image size and pixel size off the list line" \
        "png|52 MiB|54525952|7680|4320 png|3 MiB|3145728|9000|9000 jpg|400 KiB|409600|1920|1080" \
        "$(jq -r '[.[] | map(tostring) | join("|")] | join(" ")' <<<"$(r meta)")"
    assert_eq "cliphist: bytes refuse first, then pixels" \
        "52 MiB, over the 8 MiB preview limit|9000×9000, over the 12 MP preview limit|" \
        "$(jq -r 'join("|")' <<<"$(r large)")"
    assert_eq "cliphist: sizes use cliphist's units" '["0 B","2 KiB","8 MiB",""]' "$(r human)"
    assert_eq "cliphist: preview metadata line" "text · 42 B · 3 lines|jpg · 400 KiB · 1920×1080" \
        "$(jq -r 'join("|")' <<<"$(r summary)")"
    assert_eq "cliphist: int bounds clamp, never wrap" "[2147483647,1,7,7,7,8388608]" "$(r limit)"
    assert_eq "cliphist: the image cache needs an absolute XDG_RUNTIME_DIR, no /tmp fallback" '["","","","/run/user/1/haseen-clipboard"]' "$(r cacheDir)"
else
    echo "  skip: $QML_BIN not installed, Cliphist.js not exercised" >&2
fi

# --- clipboard preview in the real engine (plan 042) ---------------------------
# The real Panel.qml under qs, offscreen, on a stub cliphist that logs every
# decode. What is decoded, what the pane shows and what the toggle persists
# are read back through the panel's own test hook (its IpcHandler), called
# in-process; no keystroke is injected.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; the clipboard preview was not run" >&2
else
    sandbox clipboard-preview
    LOG="$SANDBOX/decode.log"
    MODES="$SANDBOX/modes.log"
    FIX="$SANDBOX/entries"
    export LOG MODES FIX
    mkdir -p "$FIX"
    printf 'alpha\nbeta\ngamma' >"$FIX/3"
    for i in $(seq 7000); do printf 'row %05d\n' "$i"; done >"$FIX/5"
    printf 'not really a png' >"$FIX/2"
    printf 'never read' >"$FIX/1"
    # Newest first: a short text, a 70 000-byte text, a small image and a
    # 9000x9000 screenshot over the 12 MP pixel bound.
    printf '3\talpha beta gamma\n5\trow 00001 row 00002\n2\t[[ binary data 1 KiB png 4x4 ]]\n1\t[[ binary data 3 MiB png 9000x9000 ]]\n' >"$FIX/list"
    # The decode log takes one line per decode. When the decode writes to a
    # file (the image cache), the modes of that file and its directory are
    # logged as well, so the cache's privacy is read off the real write.
    stub cliphist 'case "$1" in
list) cat "$FIX/list" ;;
decode) id="${2:-$(cut -f1)}"; echo "decode $id" >>"$LOG"
    out="$(readlink "/proc/$$/fd/1")"
    [ -f "$out" ] && echo "dir $(stat -c %a "${out%/*}") file $(stat -c %a "$out")" >>"$MODES"
    cat "$FIX/$id" ;;
esac'
    stub wl-copy 'cat >/dev/null'
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.clipboard" as Clipboard
ShellRoot {
    id: shell

    // "select:N", "preview:on|off|toggle", "scroll:N" or "wait"; a state
    // line is printed after each step has had a second to settle.
    readonly property var steps: JSON.parse(Quickshell.env("CLIP_STEPS"))
    property int step: 0

    function hook(): var {
        for (const o of panel.data)
            if (o && o.target === "haseen.clipboard")
                return o;
        return null;
    }

    // In a window, as the shell hosts it: the list only creates the rows,
    // and so the row thumbnails, that it lays out.
    FloatingWindow {
        implicitWidth: 520
        implicitHeight: 700
        visible: true

        Clipboard.Panel {
            id: panel

            pluginId: "haseen.clipboard"
            settings: Plugins.settingsFor("haseen.clipboard")
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            const h = shell.hook();
            if (shell.step > 0)
                console.warn("STATE " + (shell.step - 1) + " " + h.state());
            if (shell.step >= shell.steps.length) {
                Qt.quit();
                return;
            }
            const [verb, arg] = String(shell.steps[shell.step]).split(":");
            if (verb === "select")
                h.select(Number(arg));
            else if (verb === "preview")
                h.preview(arg);
            else if (verb === "scroll")
                h.scroll(Number(arg));
            shell.step++;
        }
    }
}
QML
    # clip_run STEPS [RUNTIME_DIR | -] -> OUTPUT, STATUS; state N FILTER reads
    # step N's state. Without a RUNTIME_DIR each run gets an empty private one,
    # so no thumbnail is left over; "-" runs with XDG_RUNTIME_DIR unset. The
    # shell runs under umask 022, the usual login default, so a file the cache
    # does not make private on purpose shows up as 644.
    clip_run() {
        : >"$LOG"
        : >"$MODES"
        local run=${2:-} rt mask
        if [[ -z $run ]]; then
            run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
            chmod 700 "$run"
        fi
        if [[ $run == - ]]; then rt=(-u XDG_RUNTIME_DIR); else rt=(XDG_RUNTIME_DIR="$run"); fi
        mask="$(umask)"
        umask 022
        capture env "${rt[@]}" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            CLIP_STEPS="$1" timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
        umask "$mask"
        if [[ $STATUS == 0 ]]; then _pass; else _fail "clipboard preview: harness completes in the real engine (exit $STATUS)" "$OUTPUT"; fi
    }
    state() { sed -n "s/^.*STATE $1 //p" <<<"$OUTPUT" | head -1 | jq -r "$2"; }
    decodes() { sort -u "$LOG" | paste -sd' ' -; }

    # Default settings: the pane is on and shows the newest entry in full.
    clip_run '["wait","select:1","select:3","select:2","preview:off"]'
    assert_eq "preview: on by default, the pane is loaded" "true true" "$(state 0 '"\(.preview.on) \(.preview.loaded)"')"
    assert_eq "preview: the newest entry, decoded in full" "3|alpha
beta
gamma" "$(state 0 '"\(.preview.entry)|\(.preview.head)"')"
    assert_eq "preview: type, decoded size and line count" "text · 16 B · 3 lines" "$(state 0 .preview.meta)"
    assert_eq "preview: a long text is capped at 64 KiB" "5 70000 true" \
        "$(state 1 '"\(.preview.entry) \(.preview.bytes) \(.preview.truncated)"')"
    assert_contains "preview: the cap is named in the metadata line" "$(state 1 .preview.meta)" "first 64 KiB"
    assert_eq "preview: an image over the pixel bound is described" "1|png, 9000×9000, over the 12 MP preview limit|false" \
        "$(state 2 '"\(.preview.entry)|\(.preview.notice)|\(.preview.imageReady)"')"
    assert_eq "preview: a small image is decoded for the pane" "2 true true" \
        "$(state 3 '"\(.preview.entry) \(.preview.image) \(.preview.imageReady)"')"
    assert_eq "preview: turned off, the pane is gone at once" "false false" "$(state 4 '"\(.preview.on) \(.preview.loaded)"')"
    assert_eq "preview: the oversize screenshot is never decoded, by the pane or its row" "decode 2 decode 3 decode 5" "$(decodes)"
    # SEC-5: written under umask 022, the image cache is still private.
    assert_eq "image cache: a 0700 directory and 0600 files under umask 022" "dir 700 file 600" "$(sort -u "$MODES" | paste -sd' ' -)"
    # One decode per selection: the size and the capped body come from the
    # same `cliphist decode`.
    assert_eq "preview: each text entry is decoded once, not once for the size and again for the body" "1 1" \
        "$(grep -cx 'decode 3' "$LOG") $(grep -cx 'decode 5' "$LOG")"
    # The toggle is persisted by a detached `haseen plugin settings`, which
    # may finish after the shell has quit.
    user_json="$XDG_CONFIG_HOME/haseen/shell.json"
    for _ in $(seq 50); do [[ -s $user_json ]] && break; sleep 0.1; done
    assert_eq "preview: the toggle is written to shell.json" "false" \
        "$(jq -r '.plugins["haseen.clipboard"].settings.preview' "$user_json" 2>/dev/null)"

    # Persisted off: nothing is decoded for a pane, only the small image's
    # row thumbnail; turning it on decodes the selected entry.
    clip_run '["wait","preview:on"]'
    assert_eq "preview off: no pane" "false false" "$(state 0 '"\(.preview.on) \(.preview.loaded)"')"
    assert_eq "preview on again: the pane loads the selection" "true 3" "$(state 1 '"\(.preview.on) \(.preview.entry)"')"
    assert_eq "preview on again: persisted" "true" \
        "$(for _ in $(seq 50); do [[ $(jq -r '.plugins["haseen.clipboard"].settings.preview' "$user_json") == true ]] && break; sleep 0.1; done
            jq -r '.plugins["haseen.clipboard"].settings.preview' "$user_json")"
    printf '%s\n' '{"plugins":{"haseen.clipboard":{"settings":{"preview":false}}}}' >"$user_json"
    clip_run '["wait"]'
    assert_eq "preview off: no entry is decoded except the row thumbnail" "decode 2" "$(decodes)"
    assert_eq "preview off: the pane stays unloaded" "false false" "$(state 0 '"\(.preview.on) \(.preview.loaded)"')"

    # U-042: binary entries are described, never shown as text. cliphist
    # marks a TIFF and other non-image data as binary; the pane takes neither
    # to the decoder. Current cliphist previews unmarked binary as text, so a
    # decoded body holding a NUL byte is withheld too.
    printf '{}\n' >"$user_json"
    printf 'II*\0\10\0\0\0binary' >"$FIX/7"
    cp "$FIX/7" "$FIX/8"
    cp "$FIX/7" "$FIX/9"
    cp "$FIX/list" "$FIX/list.default"
    printf '7\t[[ binary data 3 KiB tiff 4x4 ]]\n8\t[[ binary data 1 KiB application/octet-stream ]]\n9\tII* binary\n3\talpha beta gamma\n' >"$FIX/list"
    clip_run '["wait","select:1","select:2","select:3"]'
    assert_eq "binary: a TIFF is described, not dumped as text" "7|tiff · 3 KiB · 4×4||Binary data, not shown as text." \
        "$(state 0 '"\(.preview.entry)|\(.preview.meta)|\(.preview.head)|\(.preview.notice)"')"
    assert_eq "binary: marked non-image data is described" "8|application/octet-stream · 1 KiB||Binary data, not shown as text." \
        "$(state 1 '"\(.preview.entry)|\(.preview.meta)|\(.preview.head)|\(.preview.notice)"')"
    assert_eq "binary: unmarked data with a NUL byte is withheld, its size kept" "9|14||Binary data, not shown as text." \
        "$(state 2 '"\(.preview.entry)|\(.preview.bytes)|\(.preview.head)|\(.preview.notice)"')"
    assert_eq "binary: text after it still shows" "3|alpha|" "$(state 3 '"\(.preview.entry)|\(.preview.head | split("\n")[0])|\(.preview.notice)"')"
    assert_eq "binary: marked binary is never decoded" "decode 3 decode 9" "$(decodes)"
    mv "$FIX/list.default" "$FIX/list"

    # U-042: QML int is 32-bit. A byte or pixel bound past 2^31-1 is clamped,
    # not wrapped negative (which switched the byte bound off and cut text
    # to 1 KiB).
    printf '%s\n' '{"plugins":{"haseen.clipboard":{"settings":{"previewMaxBytes":3000000000,"previewMaxPixels":3000000000}}}}' >"$user_json"
    clip_run '["wait","select:1"]'
    assert_eq "bounds: clamped to the int range" "2147483647 2147483647" "$(state 0 '"\(.limits.bytes) \(.limits.pixels)"')"
    assert_contains "bounds: the text cap stays 64 KiB" "$(state 1 .preview.meta)" "first 64 KiB"
    printf '{}\n' >"$user_json"

    # SEC-5: the image cache is used only when it is private. Image 2 is the
    # small image; its row and the pane would both decode it.
    elsewhere="$SANDBOX/elsewhere"
    mkdir -m 700 "$elsewhere"
    run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
    chmod 700 "$run"
    ln -s "$elsewhere" "$run/haseen-clipboard"
    clip_run '["wait","select:2"]' "$run"
    assert_eq "cache: a symlinked cache dir is refused, nothing decoded" "decode 3" "$(decodes)"
    assert_eq "cache: nothing is written through the link" "" "$(ls -A "$elsewhere")"
    assert_contains "cache: the pane says why" "$(state 1 .preview.notice)" "not a private directory"
    assert_eq "cache: the planted link is left alone" "$elsewhere" "$(readlink "$run/haseen-clipboard")"

    run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
    chmod 700 "$run"
    mkdir -m 755 "$run/haseen-clipboard"
    clip_run '["wait","select:2"]' "$run"
    assert_eq "cache: an existing cache dir open to others is refused" "decode 3" "$(decodes)"
    assert_eq "cache: its mode and contents are not touched" "755|" "$(stat -c %a "$run/haseen-clipboard")|$(ls -A "$run/haseen-clipboard")"

    run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
    chmod 755 "$run"
    clip_run '["wait","select:2"]' "$run"
    assert_eq "cache: a runtime dir open to others is refused" "decode 3" "$(decodes)"
    assert_eq "cache: no cache dir is made in it" "absent" "$([[ -e $run/haseen-clipboard ]] && echo present || echo absent)"

    clip_run '["wait","select:2"]' -
    assert_eq "cache: no XDG_RUNTIME_DIR, no image decode (no /tmp fallback)" "decode 3" "$(decodes)"
    assert_contains "cache: the pane says why" "$(state 1 .preview.notice)" "XDG_RUNTIME_DIR"
    assert_eq "cache: the text pane still works without it" "3" "$(state 0 .preview.entry)"
fi
