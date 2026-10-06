# shellcheck shell=bash
# Starter widgets A (plan 021): haseen.sysusage, haseen.privacy,
# haseen.workspaces (Omarchy port), haseen.media, haseen.calendar and the
# clock's calendar click. Manifests validate, Theme tokens only, timer rules,
# no flag watchers of their own, and the pure JS (/proc parsers, privacy
# classification, workspace list, calendar grid, media label) run headless
# under the real Qt JS engine (/usr/lib/qt6/bin/qml, offscreen). The two
# helper scripts run against fixture sysfs trees and a stub gdbus.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
WIDGETS_A=(haseen.sysusage haseen.privacy haseen.workspaces haseen.media haseen.calendar haseen.clock)

# --- manifests and entry contract --------------------------------------------
sandbox widgets-a
capture haseen plugin validate "${WIDGETS_A[@]}"
assert_status "widgets-a validate" 0 "$STATUS"
for id in "${WIDGETS_A[@]}"; do
    assert_contains "$id ok" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "widgets-a request no network" "$OUTPUT" "warning:"
assert_eq "sysusage is a bar widget with a panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGINS/haseen.sysusage/manifest.json")"
assert_eq "calendar is a panel" "panel" "$(jq -r '.kinds | join(" ")' "$PLUGINS/haseen.calendar/manifest.json")"
assert_eq "calendar debug hook is off by default" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGINS/haseen.calendar/manifest.json")"
for id in "${WIDGETS_A[@]}"; do
    while read -r entry; do
        body="$(cat "$PLUGINS/$id/$entry")"
        for prop in "property string pluginId" "property var settings" "property var screen"; do
            assert_contains "$id/$entry declares $prop" "$body" "$prop"
        done
    done < <(jq -r '.entry[]' "$PLUGINS/$id/manifest.json")
done

# --- theme, resource and flag rules -------------------------------------------
dirs=()
for id in "${WIDGETS_A[@]}"; do dirs+=("$PLUGINS/$id"); done
assert_eq "no hex colour literals" "" \
    "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "${dirs[@]}" --include='*.qml' --include='*.js' || true)"
# Bar widgets use barForeground for normal text (transparent bar, plan 015);
# Theme.foreground belongs to panels and hover popups.
for f in haseen.sysusage/Widget.qml haseen.workspaces/Widget.qml haseen.media/Widget.qml; do
    assert_contains "$f uses Theme.barForeground" "$(cat "$PLUGINS/$f")" "Theme.barForeground"
done
# Every Timer is marked on the line above (test-shell.sh rule): either a
# `haseen:sample` with a literal interval >= 2000 and a gated `running:`, or a
# `haseen:ui-timeout` that is single-shot. Since plan 032 no widget samples at
# all: haseen-sidecar does, and the QML side only subscribes.
timers="$(find "${dirs[@]}" -name '*.qml' -exec awk '
    /^[[:space:]]*Timer[[:space:]]*\{/ { inside = 1; depth = 0; start = FNR; sample = (prev ~ /haseen:sample/); ui = (prev ~ /haseen:ui-timeout/); iv = ""; gated = 0; single = 0 }
    inside {
        if (match($0, /^[[:space:]]*interval:[[:space:]]*[0-9]+[[:space:]]*$/)) { iv = $0; gsub(/[^0-9]/, "", iv) }
        if ($0 ~ /^[[:space:]]*running:/ && $0 !~ /running:[[:space:]]*true[[:space:]]*$/) gated = 1
        if ($0 ~ /^[[:space:]]*repeat:[[:space:]]*false/) single = 1
        n = split($0, ch, ""); for (i = 1; i <= n; i++) { if (ch[i] == "{") depth++; else if (ch[i] == "}") depth-- }
        if (depth <= 0) { inside = 0; print FILENAME ":" start ":" ((ui && single) || (sample && iv != "" && iv + 0 >= 2000 && gated) ? "ok" : "bad") }
    }
    { prev = $0 }' {} +)"
assert_not_contains "no fast or ungated Timer" "$timers" ":bad"
assert_eq "no widget has a Timer any more" "" "$(cut -d: -f1 <<<"$timers" | sort -u)"
sampler="$(cat "$PLUGINS/haseen.sysusage/Sampler.qml")"
assert_not_contains "the sampler has no timer" "$sampler" "Timer"
assert_not_contains "the sampler reads no files" "$sampler" "FileView"
assert_not_contains "the sampler starts no process" "$sampler" "Process"
assert_contains "the sampler subscribes to the daemon" "$sampler" 'Sidecar.want(_key, "sysusage"'
assert_contains "it unsubscribes when it is not shown" "$sampler" "Sidecar.drop(_key)"
assert_contains "the feature is gated on the capability" "$sampler" 'Sidecar.has("sysusage")'
assert_contains "the widget hides without the daemon" "$(cat "$PLUGINS/haseen.sysusage/Widget.qml")" "sampler.available"
assert_contains "widget samples only while its window shows" "$(cat "$PLUGINS/haseen.sysusage/Widget.qml")" "QsWindow.window.visible"
assert_eq "privacy, media, workspaces, calendar never poll (no Timer/SystemClock ticks)" "" \
    "$(grep -lE 'Timer \{' "$PLUGINS"/haseen.{privacy,media,workspaces,calendar}/*.qml || true)"
assert_eq "flags come from qs.Haseen Flags, never an own watcher" "" \
    "$(grep -rn 'flags/' "${dirs[@]}" --include='*.qml' || true)"
assert_contains "privacy red dot reads Flags.recording" "$(cat "$PLUGINS/haseen.privacy/Widget.qml")" "Flags.recording"
assert_contains "clock click toggles the calendar panel" "$(cat "$PLUGINS/haseen.clock/Widget.qml")" '"ipc", "call", "panel", "toggle", calendar'
assert_eq "clock opens haseen.calendar by default" "haseen.calendar" "$(jq -r '.settings.calendar.default' "$PLUGINS/haseen.clock/manifest.json")"
assert_contains "workspaces keeps the Omarchy MIT notice" "$(cat "$PLUGINS/haseen.workspaces/Widget.qml")" "MIT, Copyright (c) David"

# --- pure JS under the Qt JS engine --------------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.sysusage/Usage.js" as U
import "file://$PLUGINS/haseen.privacy/Privacy.js" as P
import "file://$PLUGINS/haseen.workspaces/Workspaces.js" as W
import "file://$PLUGINS/haseen.calendar/Calendar.js" as C
import "file://$PLUGINS/haseen.calendar/Moon.js" as Moon
import "file://$PLUGINS/haseen.media/Media.js" as M

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    function node(id, flags, props) {
        return Object.assign({ id: id, name: "n" + id, description: "", nickname: "", audio: false, video: false, source: false, stream: false, props: props || {} }, flags);
    }

    // An exception must still end the run, or the window would stay up.
    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        // Parsing moved into haseen-sidecar (plan 032); core/internal/sysusage
        // owns those tests. Only formatting is left here.
        eq("format GiB", "3.0 GiB", U.formatKiB(3145728));
        eq("format MiB", "512 MiB", U.formatKiB(524288));

        // Privacy: mic -> capture stream (orange), camera (green), screencast (red).
        const mic = node(44, { audio: true, source: true });
        const rec = node(90, { audio: true, source: true, stream: true }, { "application.name": "pw-record" });
        const cam = node(80, { video: true, source: true }, { "device.api": "v4l2", "media.role": "Camera" });
        const camUnbound = node(81, { video: true, source: true });
        camUnbound.name = "v4l2_input.pci-0000_00_14.0";
        const share = node(70, { video: true, source: true });
        share.name = "xdph-streaming-0";
        const zoom = node(91, {}, { "application.name": "zoom" });
        const obs = node(92, {}, { "application.name": "OBS" });
        const sink = node(20, { audio: true, source: false });
        const desktop = node(93, { audio: true, source: true, stream: true }, { "application.name": "recorder" });
        const peak = node(94, { audio: true, source: true, stream: true }, { "application.name": "pavucontrol", "media.name": "Peak detect" });
        eq("idle -> nothing", { camera: [], mic: [], screen: [] }, P.classify([], []));
        eq("mic capture", ["pw-record"], P.classify([{ source: mic, target: rec, active: true }], []).mic);
        eq("paused mic link ignored", [], P.classify([{ source: mic, target: rec, active: false }], []).mic);
        eq("sink monitor capture is not a mic", [], P.classify([{ source: sink, target: desktop, active: true }], []).mic);
        eq("peak meter ignored", [], P.classify([{ source: mic, target: peak, active: true }], []).mic);
        eq("ignore list", [], P.classify([{ source: mic, target: rec, active: true }], ["PW-Record"]).mic);
        eq("camera by role", ["zoom"], P.classify([{ source: cam, target: zoom, active: true }], []).camera);
        eq("camera by unbound name", ["zoom"], P.classify([{ source: camUnbound, target: zoom, active: true }], []).camera);
        const sc = P.classify([{ source: share, target: obs, active: true }, { source: share, target: obs, active: true }], []);
        eq("screencast", ["OBS"], sc.screen);
        eq("screencast is not a camera", [], sc.camera);
        eq("interesting: mic->stream", true, P.interesting({ source: mic, target: rec }));
        eq("interesting: sink->stream", false, P.interesting({ source: sink, target: desktop }));
        eq("geoclue property true", true, P.parseGeoclue("/org/freedesktop/GeoClue2/Manager: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.GeoClue2.Manager', {'InUse': <true>}, @as [])"));
        eq("geoclue owner lost", false, P.parseGeoclue("The name org.freedesktop.GeoClue2 does not have an owner"));
        eq("geoclue unavailable", false, P.parseGeoclue("unavailable"));
        eq("geoclue noise", null, P.parseGeoclue("The name org.freedesktop.GeoClue2 is owned by :1.5"));

        // Workspaces (Omarchy): 1..5 persistent + existing up to 10.
        eq("persistent only", [1, 2, 3, 4, 5], W.workspaceIds([], 5, "eDP-1", false));
        eq("plus occupied", [1, 2, 3, 4, 5, 7, 10], W.workspaceIds([{ id: 10, monitor: "eDP-1" }, { id: 7, monitor: "eDP-1" }, { id: 3, monitor: "eDP-1" }, { id: 12, monitor: "eDP-1" }, { id: -98, monitor: "eDP-1" }], 5, "eDP-1", false));
        eq("other monitor filtered", [1, 2], W.workspaceIds([{ id: 6, monitor: "DP-1" }], 2, "eDP-1", false));
        eq("allMonitors", [1, 2, 6], W.workspaceIds([{ id: 6, monitor: "DP-1" }], 2, "eDP-1", true));
        eq("10 labelled 0", "0", W.label(10));
        eq("special name", "scratchpad", W.specialName("special:scratchpad"));
        eq("lua focus", "hl.dsp.focus({ workspace = \"3\" })", W.focusCommand("3", true));
        eq("legacy focus", "workspace 3", W.focusCommand("3", false));
        eq("lua toggle special", "hl.dsp.workspace.toggle_special(\"scratchpad\")", W.toggleSpecialCommand("scratchpad", true));
        eq("wheel up = previous", "e-1", W.scrollTarget(1));
        eq("wheel down = next", "e+1", W.scrollTarget(-2));

        // Calendar: October 2026 starts on a Thursday.
        const oct = C.monthGrid(2026, 9, 1);
        eq("monday grid starts Sep 28", [8, 28], [oct[0].month, oct[0].day]);
        eq("oct 1 in column 3", [1, true], [oct[3].day, oct[3].inMonth]);
        eq("42 cells", 42, oct.length);
        eq("sunday grid starts Sep 27", 27, C.monthGrid(2026, 9, 0)[0].day);
        eq("iso weeks oct 2026", [40, 41, 42, 43, 44, 45], C.rowWeeks(oct));
        eq("iso week 2026-01-01", 1, C.isoWeek(2026, 0, 1));
        eq("iso week 2027-01-01 is 53", 53, C.isoWeek(2027, 0, 1));
        eq("shift back over year", { year: 2025, month: 11 }, C.shiftMonth(2026, 0, -1));
        eq("shift forward", { year: 2027, month: 1 }, C.shiftMonth(2026, 11, 2));
        eq("week start name", 1, C.weekStart("Monday", 0));
        eq("week start abbrev", 6, C.weekStart("sat", 1));
        eq("week start locale", 1, C.weekStart("locale", 1));
        eq("week start junk", 0, C.weekStart("blursday", 7));
        eq("weekday order", [1, 2, 3, 4, 5, 6, 0], C.weekdayOrder(1));
        // Published phases (UTC): the formula is good to about a day.
        eq("moon: the reference new moon", "New Moon", Moon.phase(Date.UTC(2000, 0, 6, 18, 14)).name);
        eq("moon: full moon of 25 January 2024", "Full Moon", Moon.phase(Date.UTC(2024, 0, 25, 17, 54)).name);
        eq("moon: first quarter of 17 January 2024", "First Quarter", Moon.phase(Date.UTC(2024, 0, 18, 3, 52)).name);
        eq("moon: a full moon is fully lit", true, Moon.phase(Date.UTC(2024, 0, 25, 17, 54)).illumination >= 98);
        eq("moon: a new moon is dark", true, Moon.phase(Date.UTC(2024, 0, 11, 11, 57)).illumination <= 2);
        eq("moon: the age stays inside one synodic month", true, (() => { for (let d = 0; d < 400; d++) { const a = Moon.phase(Date.UTC(2025, 0, 1) + d * 86400000).age; if (a < 0 || a > 29.6) return false; } return true; })());
        eq("moon: the waybar lines", { title: "🌕  Full Moon", detail: "100% lit · 14.6 days old" }, Moon.lines(Date.UTC(2024, 0, 25, 17, 54)));

        // Media: playing wins, then paused; truncation by code point.
        eq("pick playing", 1, M.pickIndex([{ isPlaying: false, stopped: false }, { isPlaying: true, stopped: false }]));
        eq("pick paused over stopped", 1, M.pickIndex([{ isPlaying: false, stopped: true }, { isPlaying: false, stopped: false }]));
        eq("no players", -1, M.pickIndex([]));
        eq("label", "Artist - Song", M.label("Song", "Artist", "spotify", true));
        eq("label no artist", "Song", M.label("Song", "Artist", "spotify", false));
        eq("label untitled", "spotify", M.label("", "", "spotify", true));
        eq("truncate", "abcd…", M.truncate("abcdefgh", 5));
        eq("truncate short", "abc", M.truncate("abc", 5));
        eq("truncate emoji safe", "🎵🎵…", M.truncate("🎵🎵🎵🎵", 3));

        return;
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "qml unit runner exits 0" 0 "$rc"
    assert_contains "qml unit runner ran" "$units" "UNIT-PASS format GiB"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" "59" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- geoclue-watch.sh with a stub gdbus ---------------------------------------
watch="$PLUGINS/haseen.privacy/geoclue-watch.sh"
gdbus_stub() { # ACTIVATABLE_NAME OWNED(true|false) — Get prints STUB-GET on stderr
    stub gdbus "case \"\$*\" in
*ListActivatableNames*) echo \"(['$1'],)\" ;;
*NameHasOwner*) echo \"($2,)\" ;;
*Properties.Get*) echo STUB-GET >&2; echo \"(<true>,)\" ;;
monitor*) echo \"\$*\" ;;
*) echo \"STUB-CALLED: gdbus \$*\" >&2; exit 97 ;;
esac"
}
gdbus_stub org.freedesktop.DBus false
out="$(bash "$watch" 2>&1)"
assert_eq "geoclue absent: unavailable, nothing else" "unavailable" "$out"
gdbus_stub org.freedesktop.GeoClue2 true
out="$(bash "$watch" 2>&1)"
assert_contains "geoclue running: current InUse first" "$out" "'InUse': <true>"
assert_contains "then gdbus monitor on the Manager" "$out" "monitor --system --dest org.freedesktop.GeoClue2 --object-path /org/freedesktop/GeoClue2/Manager"
gdbus_stub org.freedesktop.GeoClue2 false
out="$(bash "$watch" 2>&1)"
assert_not_contains "geoclue not running: no activating Get" "$out" "STUB-GET"
assert_eq "geoclue not running: straight to monitor" \
    "monitor --system --dest org.freedesktop.GeoClue2 --object-path /org/freedesktop/GeoClue2/Manager" "$out"
