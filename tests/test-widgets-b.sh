# shellcheck shell=bash
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
else
    echo "  skip: $QML_BIN not installed, Cliphist.js not exercised" >&2
fi
