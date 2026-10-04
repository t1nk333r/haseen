# shellcheck shell=bash
# Starter widgets B (plan 022): haseen.clipboard, haseen.weather,
# haseen.bluetooth and the haseen.network Wi-Fi panel. Manifests validate,
# timers follow the resource rule, widgets use Theme tokens only, radios
# are only scanned from panels, and the pure parsers (Weather.js on a
# wttr.in j1 fixture, Cliphist.js) run under the stock `qml` tool.

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
assert_eq "only weather asks for network" "1" "$(grep -c "requests unrestricted 'network'" <<<"$OUTPUT")"
assert_dry_pure "plugin validate" "$OUTPUT"

kinds() { jq -r '.kinds | join(",")' "$PLUGINS/$1/manifest.json"; }
assert_eq "clipboard kinds" "service,panel,launcher-provider" "$(kinds haseen.clipboard)"
assert_eq "weather kinds" "service,bar-widget,panel" "$(kinds haseen.weather)"
assert_eq "bluetooth kinds" "bar-widget,panel" "$(kinds haseen.bluetooth)"
assert_eq "network kinds" "bar-widget,panel" "$(kinds haseen.network)"
assert_eq "clipboard provides clipboard" "clipboard" "$(jq -r '.provides | join(",")' "$PLUGINS/haseen.clipboard/manifest.json")"
assert_eq "weather provides weather" "weather" "$(jq -r '.provides | join(",")' "$PLUGINS/haseen.weather/manifest.json")"
assert_eq "provides roles stay unique across built-ins" "" \
    "$(jq -r '.provides[]?' "$PLUGINS"/*/manifest.json | sort | uniq -d)"
for id in "${IDS[@]}"; do
    assert_eq "$id debugIpc defaults off" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGINS/$id/manifest.json")"
done
assert_eq "weather location defaults to IP lookup" "" "$(jq -r '.settings.location.default' "$PLUGINS/haseen.weather/manifest.json")"

# --- theme tokens and timers ---------------------------------------------------
assert_eq "no hex colour literals" "" "$(grep -rnE '"#[0-9a-fA-F]{3,8}"' "${DIRS[@]}" || true)"
assert_eq "bar widgets use Theme.barForeground, never Theme.foreground" "" \
    "$(grep -n 'Theme\.foreground' "$PLUGINS"/haseen.{weather,bluetooth,network}/Widget.qml || true)"
# Only weather's 30-minute fetch is a Timer: a `haseen:sample` with a literal
# interval >= 2000 and a running: binding that is not the literal true.
timers="$(find "${DIRS[@]}" -name '*.qml' -exec awk '
    /^[[:space:]]*Timer[[:space:]]*\{/ { print FILENAME ":" FNR ":" prev; inside = 1; next }
    inside && /^[[:space:]]*interval:/ { print "  " $0 }
    inside && /^[[:space:]]*running:/ { print "  " $0 }
    inside && /^[[:space:]]*\}/ { inside = 0 }
    { prev = $0 }
' {} +)"
assert_eq "exactly one Timer (weather Service)" "1" "$(grep -c '^/' <<<"$timers")"
assert_contains "weather timer is in Service.qml" "$timers" "haseen.weather/Service.qml:"
assert_contains "weather timer marked haseen:sample" "$timers" "// haseen:sample"
assert_contains "weather refresh every 30 min" "$timers" "interval: 1800000"
assert_not_contains "weather timer is gated" "$timers" "running: true"

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
        printf 'var j1 = %s;\n' "$(jq -Rs . "$FIXTURES/wttr/j1.json")"
        printf 'var list = %s;\n' "$(printf '12\thello world\n11\t[[ binary data 2 KiB png 80x80 ]]\n10\t[[ binary data 9 KiB jpg 10x10 ]]\n9\t[[ binary data 1 KiB application/octet-stream ]]\nnot a line\n8\tSecond Line here\n' | jq -Rs .)"
    } >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.weather/Weather.js" as W
import "file://$PLUGINS/haseen.clipboard/Cliphist.js" as C
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const noon = new Date(2026, 9, 4, 12, 0);
        const late = new Date(2026, 9, 4, 23, 30);
        out("metric", W.parse(D.j1, false, noon));
        out("imperial", W.parse(D.j1, true, noon));
        out("night", W.parse(D.j1, false, late).current.night);
        out("bad", W.parse("<html>offline</html>", false, noon));
        out("empty", W.parse("{}", false, noon));
        out("glyphs", [W.glyph(113, false), W.glyph("113", true), W.glyph(389, false), W.glyph(999, false)]);
        out("clock", [W.clockMinutes("07:13 AM"), W.clockMinutes("12:05 PM"), W.clockMinutes("06:37 PM"), W.clockMinutes("x")]);
        out("url", [W.url(""), W.url("New York"), W.url(" 52.5,13.4 ")]);
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
    m="$(r metric)"
    assert_eq "weather: parse ok" "true" "$(jq -r .ok <<<"$m")"
    assert_eq "weather: location" "Berlin, Germany" "$(jq -r .location <<<"$m")"
    assert_eq "weather: current" "19 17 Overcast 122 57 9 km/h false" \
        "$(jq -r '.current | "\(.temp) \(.feels) \(.desc) \(.code) \(.humidity) \(.wind) \(.windUnit) \(.night)"' <<<"$m")"
    assert_eq "weather: cloudy glyph" "$(printf '\xee\x8c\xbd')" "$(jq -r .current.glyph <<<"$m")"
    assert_eq "weather: three days" "2026-10-04 20/13 Overcast 15|2026-10-05 21/12 Overcast 13|2026-10-06 22/13 Sunny 4" \
        "$(jq -r '[.days[] | "\(.date) \(.max)/\(.min) \(.desc) \(.rain)"] | join("|")' <<<"$m")"
    assert_eq "weather: unit" "°C" "$(jq -r .unit <<<"$m")"
    i="$(r imperial)"
    assert_eq "weather: imperial" "66 °F 6 mph 68/56" "$(jq -r '"\(.current.temp) \(.unit) \(.current.wind) \(.current.windUnit) \(.days[0].max)/\(.days[0].min)"' <<<"$i")"
    assert_eq "weather: night after sunset" "true" "$(r night)"
    assert_eq "weather: offline html fails quietly" '{"ok":false,"error":"not JSON"}' "$(r bad)"
    assert_eq "weather: empty answer fails" '{"ok":false,"error":"no current_condition"}' "$(r empty)"
    assert_eq "weather: glyph table" "$(printf '["\xee\x8c\x8d","\xee\x8c\xab","\xee\x8c\x9d","\xee\x8c\xbd"]')" "$(r glyphs)"
    assert_eq "weather: 12h clock" "[433,725,1117,-1]" "$(r clock)"
    assert_eq "weather: url" '["https://wttr.in/?format=j1","https://wttr.in/New%20York?format=j1","https://wttr.in/52.5%2C13.4?format=j1"]' "$(r url)"
    c="$(r clip)"
    assert_eq "cliphist: rows" "12 11 10 9 8" "$(jq -r '[.[].id] | join(" ")' <<<"$c")"
    assert_eq "cliphist: image kinds" "false:false: true:true:png true:true:jpeg false:true: false:false:" \
        "$(jq -r '[.[] | "\(.image):\(.binary):\(.ext)"] | join(" ")' <<<"$c")"
    assert_eq "cliphist: line kept verbatim for decode" "$(printf '12\thello world')" "$(jq -r '.[0].line' <<<"$c")"
    assert_eq "cliphist: every word matches, any case" '["8"]' "$(r filter)"
    assert_eq "cliphist: blank query keeps all" "5" "$(r filterAll)"
else
    echo "  skip: $QML_BIN not installed, Weather.js/Cliphist.js not exercised" >&2
fi
