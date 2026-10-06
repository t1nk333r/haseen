# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.weather: Omarchy's weather (wttr.in + Open-Meteo, 15-minute refresh,
# city search) with the location from settings, else GeoClue, else wttr.in's
# IP lookup. The pure model runs under the stock `qml` tool; the location,
# status and icon commands run against a fake GeoClue client and a fake curl;
# `haseen setup geoclue` is checked as a dry run; the service runs in the real
# Quickshell engine against the same fakes. Coordinates are public city
# centres (Berlin, Paris), never a real machine's position.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.weather"
QML=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

sandbox weather
capture haseen plugin validate haseen.weather
assert_status "weather validates" 0 "$STATUS"
assert_contains "weather ok" "$OUTPUT" "ok: haseen.weather (builtin:"
assert_dry_pure "plugin validate" "$OUTPUT"
assert_eq "kinds" "service,bar-widget,panel" "$(jq -r '.kinds | join(",")' "$PLUGIN/manifest.json")"
assert_eq "manual location empty by default (GeoClue, else IP)" "" "$(jq -r '.settings.location.default' "$PLUGIN/manifest.json")"
assert_eq "debug hook off by default" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGIN/manifest.json")"

# --- fakes: GeoClue's where-am-i and curl ------------------------------------
# where-am-i prints the fix and keeps running until its -t timeout (geoclue
# 2.8 output format); a denial is one CRITICAL line on stderr.
WAI="$SANDBOX/where-am-i"
cat >"$WAI" <<'EOF'
#!/bin/sh
case "$WAI_MODE" in
ok)
    printf 'Client object: /org/freedesktop/GeoClue2/Client/1\n\nNew location:\n'
    printf 'Latitude:    52.520902\302\260\nLongitude:   13.404954\302\260\nAccuracy:    4000 meters\n'
    exec sleep 30
    ;;
denied)
    echo "** (where-am-i:1): CRITICAL **: Failed to connect to GeoClue2 service: GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: 'geoclue-where-am-i' disallowed by configuration for UID 1000" >&2
    exit 255
    ;;
esac
exec sleep 30
EOF
chmod +x "$WAI"
export HASEEN_WHERE_AM_I="$WAI"

J1="$SANDBOX/j1.json"
jq '.nearest_area[0].latitude = "52.520" | .nearest_area[0].longitude = "13.405"' "$FIXTURES/wttr/j1.json" >"$J1"
OM="$SANDBOX/open-meteo.json"
d() { date -d "+$1 day" +%F; }
cat >"$OM" <<EOF
{"latitude":52.52,"longitude":13.4,
 "current":{"temperature_2m":18.6,"apparent_temperature":16.9,"relative_humidity_2m":60,"wind_speed_10m":11.2,"weather_code":0,"is_day":0},
 "daily":{"time":["$(d 0)","$(d 1)","$(d 2)","$(d 3)"],"weather_code":[3,61,0,95],"temperature_2m_max":[20.1,17.4,22.6,19],"temperature_2m_min":[12,10.5,13.2,11]}}
EOF
CURL_LOG="$SANDBOX/curl.log"
export J1 OM CURL_LOG
stub curl 'url=""; for a in "$@"; do url="$a"; done
echo "$url" >>"$CURL_LOG"
case "$url" in
*api.open-meteo.com*) cat "$OM" ;;
*format=%l*) echo "Berlin, Berlin, Germany" ;;
*format=j1*) cat "$J1" ;;
*) exit 22 ;;
esac'
mkdir -p "$HOME/.config/haseen"
echo '{}' >"$HOME/.config/haseen/shell.json"
CFG="$HOME/.config/haseen/shell.json"
wsetting() { jq -r --arg k "$1" '.plugins["haseen.weather"].settings[$k] // empty' "$CFG"; }

# --- haseen weather location ---------------------------------------------------
SECONDS=0
WAI_MODE=ok capture timeout 20 haseen weather location --detect
assert_status "GeoClue fix" 0 "$STATUS"
assert_eq "city accuracy: two decimals" "52.52,13.40" "$OUTPUT"
assert_eq "the client is stopped at the first fix, not at its timeout" "1" "$((SECONDS < 10))"
WAI_MODE=denied capture haseen weather location --detect
assert_status "GeoClue denial fails" 1 "$STATUS"
assert_contains "denial reason is passed on" "$OUTPUT" "GeoClue: 'geoclue-where-am-i' disallowed by configuration for UID 1000"
assert_contains "points at the setup command" "$OUTPUT" "haseen setup geoclue"
HASEEN_WHERE_AM_I=/nonexistent capture haseen weather location --detect
assert_status "no GeoClue fails" 1 "$STATUS"
assert_contains "no GeoClue is named" "$OUTPUT" "not installed"

WAI_MODE=ok capture haseen weather location --query
assert_eq "no location: GeoClue coordinates" "52.52,13.40" "$OUTPUT"
WAI_MODE=denied capture haseen weather location --query
assert_eq "no location, no GeoClue: IP lookup (empty)" "" "$OUTPUT"
WAI_MODE=denied capture haseen weather location
assert_eq "IP city from wttr.in" "Berlin" "$OUTPUT"

capture haseen weather location --set Paris 48.8566,2.3522 --dry-run
assert_status "set dry run" 0 "$STATUS"
assert_contains "dry run shows the settings write" "$OUTPUT" '"locationName": "Paris"'
assert_dry_pure "weather location --set" "$OUTPUT"
assert_eq "dry run writes nothing" "{}" "$(jq -c . "$CFG")"
capture haseen weather location --set Paris 48.8566,2.3522
assert_status "set" 0 "$STATUS"
assert_eq "coordinates stored" "48.8566,2.3522" "$(wsetting location)"
assert_eq "name labels them" "Paris" "$(wsetting locationName)"
WAI_MODE=ok capture haseen weather location --query
assert_eq "manual location wins over GeoClue" "48.8566,2.3522" "$OUTPUT"
capture haseen weather location
assert_eq "manual name" "Paris" "$OUTPUT"
capture haseen weather location --set "New York"
assert_eq "a city alone" "New York|" "$(wsetting location)|$(wsetting locationName)"
capture haseen weather location --query
assert_eq "city query is URL-encoded" "New%20York" "$OUTPUT"
capture haseen weather location --set Paris 48.85
assert_status "bad coordinates refused" 1 "$STATUS"
capture haseen weather location --clear
assert_eq "clear" "|" "$(wsetting location)|$(wsetting locationName)"

# --- status and icon -----------------------------------------------------------
WAI_MODE=denied capture haseen weather status
assert_eq "status: wttr.in's area, metric" "Berlin  ·  Temp 19°C  ·  Wind 9 km/h" "$OUTPUT"
jq '.plugins["haseen.weather"].settings = {"location":"48.8566,2.3522","locationName":"Paris","units":"imperial"}' "$CFG" >"$CFG.new" && mv "$CFG.new" "$CFG"
capture haseen weather status
assert_eq "status: stored name, imperial" "Paris  ·  Temp 66°F  ·  Wind 6 mph" "$OUTPUT"
assert_contains "status asks for the stored coordinates" "$(tail -n1 "$CURL_LOG")" "wttr.in/48.8566,2.3522?format=j1"
capture haseen weather icon
assert_eq "icon: overcast" "$(printf '\xee\x8c\xbd')" "$OUTPUT"
echo '{}' >"$CFG"
stub curl 'exit 6'
capture haseen weather status
assert_status "offline status fails" 1 "$STATUS"
assert_eq "offline status" "Weather unavailable" "$OUTPUT"

# --- haseen setup geoclue (dry run against an empty system) --------------------
mkdir -p "$SANDBOX/root"
HASEEN_SYSROOT="$SANDBOX/root" capture haseen setup geoclue
assert_eq "off on a system without geoclue" "off" "$OUTPUT"
HASEEN_SYSROOT="$SANDBOX/root" capture haseen setup geoclue on --dry-run
assert_status "setup geoclue on" 0 "$STATUS"
assert_dry_pure "setup geoclue on" "$OUTPUT"
assert_contains "installs geoclue" "$OUTPUT" "DRYRUN: sudo pacman -S --needed geoclue libnotify"
assert_contains "writes the drop-in" "$OUTPUT" "DRYRUN: write /etc/geoclue/conf.d/90-haseen.conf"
assert_contains "allows where-am-i for this user" "$OUTPUT" $'    | [geoclue-where-am-i]\n    | allowed=true\n    | system=false\n    | users='"$(id -u)"
assert_contains "geoclue rereads it" "$OUTPUT" "DRYRUN: sudo systemctl try-restart geoclue.service"
assert_contains "starts the agent" "$OUTPUT" 'DRYRUN: systemctl --user start app-geoclue\x2ddemo\x2dagent@autostart.service'
HASEEN_SYSROOT="$SANDBOX/root" capture haseen setup geoclue off --dry-run
assert_dry_pure "setup geoclue off" "$OUTPUT"
assert_contains "off denies where-am-i" "$OUTPUT" $'    | allowed=false\n    | system=false\n    | users=\n'
assert_not_contains "off installs nothing" "$OUTPUT" "pacman"
mkdir -p "$SANDBOX/root/etc/geoclue/conf.d" "$SANDBOX/root/usr/lib/geoclue-2.0/demos"
cp "$WAI" "$SANDBOX/root/usr/lib/geoclue-2.0/demos/where-am-i"
printf '[geoclue-where-am-i]\nallowed=true\nsystem=false\nusers=1000\n' >"$SANDBOX/root/etc/geoclue/conf.d/90-haseen.conf"
HASEEN_SYSROOT="$SANDBOX/root" capture haseen setup geoclue
assert_eq "on once allowed and installed" "on" "$OUTPUT"
capture haseen setup geoclue maybe
assert_status "unknown choice" 2 "$STATUS"

# --- Model.js under the stock qml tool -------------------------------------------
if [[ -x $QML ]]; then
    H="$SANDBOX/js"
    mkdir -p "$H"
    cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as M

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
        eq("coordinates setting", { name: "Berlin", latitude: 52.52, longitude: 13.4 }, M.parseLocationSetting(" 52.52, 13.40 ", "Berlin"));
        eq("city setting", { name: "Paris", latitude: null, longitude: null }, M.parseLocationSetting(" Paris ", "ignored"));
        eq("out-of-range is a name", "91,500", M.parseLocationSetting("91,500", "").name);
        eq("unset", false, M.isLocationSet(M.parseLocationSetting("", "")));
        const geo = M.parseDetected("52.52,13.40\n");
        eq("detected fix", { latitude: 52.52, longitude: 13.4 }, geo);
        eq("detect error is no fix", null, M.parseDetected("GeoClue: no answer"));
        eq("GeoClue when nothing is stored", { name: "", latitude: 52.52, longitude: 13.4 }, M.effectiveLocation(M.parseLocationSetting("", ""), geo));
        eq("manual wins", "Paris", M.effectiveLocation(M.parseLocationSetting("Paris", ""), geo).name);
        eq("IP when neither", "", M.wttrLocationQuery(M.effectiveLocation(M.parseLocationSetting("", ""), null).name, null, null));
        eq("wttr query: coordinates", "52.52,13.4", M.wttrLocationQuery("", 52.52, 13.4));
        eq("wttr query: name", "New%20York", M.wttrLocationQuery(" New York ", null, null));
        eq("wttr url", "https://wttr.in/?format=j1", M.wttrUrl(""));
        eq("store a pick", { location: "48.85,2.35", locationName: "Paris" }, M.locationSettings("Paris", 48.85, 2.35));
        eq("store a typed city", { location: "Tokyo", locationName: "" }, M.locationSettings(" Tokyo ", null, null));
        eq("commit picks the highlighted suggestion", "Lyon", M.locationCommit("ly", [{ name: "Paris" }, { name: "Lyon" }], 1).name);
        eq("geocoding rows", [{ name: "Berlin", description: "Land Berlin, Germany", latitude: 52.52, longitude: 13.41 }],
            M.parseGeocodingResults('{"results":[{"name":"Berlin","admin1":"Land Berlin","country":"Germany","latitude":52.52,"longitude":13.41},{"name":"x"}]}'));
        eq("geocoding junk", [], M.parseGeocodingResults("<html>"));
        eq("units: explicit metric", false, M.shouldUseImperial("metric", "en_US", "USA"));
        eq("units: auto, US forecast", true, M.shouldUseImperial("", "de_DE", "United States of America"));
        eq("units: auto, German forecast", false, M.shouldUseImperial("", "en_US", "Germany"));
        eq("units: auto, locale", true, M.shouldUseImperial("", "en_US.UTF-8", ""));
        const om = { current: { temperature_2m: 18.6, apparent_temperature: 16.9, relative_humidity_2m: 60, wind_speed_10m: 11.2, weather_code: 0, is_day: 0 },
            daily: { time: ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10"], weather_code: [3, 61, 0, 95, 3],
                temperature_2m_max: [20.1, 17.4, 22.6, 19, 18], temperature_2m_min: [12, 10.5, 13.2, 11, 9] } };
        const cur = M.openMeteoCurrentCondition(om);
        eq("open-meteo current", ["19", "65", "17", "11", "60"], [cur.temp_C, cur.temp_F, cur.FeelsLikeC, cur.windspeedKmph, cur.humidity]);
        eq("night clear icon", "\ue32b", M.currentIcon(cur, ""));
        const days = M.buildForecastDays(null, om, "2026-10-06");
        eq("three future days", ["2026-10-07", "2026-10-08", "2026-10-09"], days.map(x => x.date));
        eq("day temps", ["17°", "11°", "63°"], [M.bareTempForDay(days[0], "max", false), M.bareTempForDay(days[0], "min", false), M.bareTempForDay(days[0], "max", true)]);
        eq("day icons", ["\ue318", "\ue30d", "\ue31d"], days.map(M.dayIcon));
        eq("wttr days when open-meteo is missing", ["2026-10-05"], M.buildForecastDays({ weather: [{ date: "2026-10-04" }, { date: "2026-10-05" }] }, null, "2026-10-04").map(x => x.date));
        eq("wttr icon nearest noon", "\ue318", M.dayIcon({ hourly: [{ time: "0", weatherCode: "113" }, { time: "1200", weatherCode: "296" }] }));
        eq("fog at night", "\ue346", M.iconForCode(143, true));
        eq("unknown code", "\ue33d", M.iconForCode(999, false));
        eq("wttr fills an empty icon only", ["\ue33d", "\ue32b"], [M.provisionalCurrentIcon({ weatherCode: "122" }, ""), M.provisionalCurrentIcon({ weatherCode: "122" }, "\ue32b")]);
        eq("save completes on the source that has the location", [true, false, true], [M.weatherResponseCompletesSave(true, "open-meteo"), M.weatherResponseCompletesSave(true, "wttr"), M.weatherResponseCompletesSave(false, "wttr")]);
        eq("status line", "Berlin  ·  Temp 19°C  ·  Wind 9 km/h", M.statusLine("berlin", "19°C", "9 km/h"));
        eq("status without data", "Weather unavailable", M.statusLine("Berlin", "", ""));
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml"
    assert_status "Model.js units" 0 "$STATUS"
    assert_eq "no unit failures" "" "$(grep 'UNIT-FAIL' <<<"$OUTPUT" || true)"
    assert_eq "units ran" "34" "$(grep -c 'UNIT-PASS' <<<"$OUTPUT")"
else
    echo "  skip: $QML not installed, Model.js not exercised" >&2
fi

# --- the service in the real Quickshell engine -----------------------------------
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; weather service scenarios not run" >&2
else
    stub curl 'url=""; for a in "$@"; do url="$a"; done
echo "$url" >>"$CURL_LOG"
case "$url" in
*api.open-meteo.com*) cat "$OM" ;;
*format=%l*) echo "Berlin, Berlin, Germany" ;;
*format=j1*) cat "$J1" ;;
*) exit 22 ;;
esac'
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-weather.XXXXXX")"
    export XDG_RUNTIME_DIR
    chmod 700 "$XDG_RUNTIME_DIR"
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    # WEATHER_SAVE: after the first answer, commit a city as the panel does
    # and wait for its answer.
    cat >"$harness/shell.qml" <<EOF
import QtQuick
import Quickshell
import qs.Haseen

ShellRoot {
    id: probe

    property var svc: null
    property bool saved: false

    function state(): var {
        return { source: svc.locationSource, query: svc.locationQuery, location: svc.reportLocation, note: svc.geoclueNote,
            label: svc.label, temp: svc.reportTempNum, feels: svc.reportFeels, wind: svc.reportWind, humidity: svc.reportHumidity,
            days: svc.forecastDays.length, status: svc.statusLine, saving: svc.savingLocation };
    }

    // Created once the registry knows the plugin; settings stay bound to
    // shell.json (+ runtime edits), as ServiceHost binds them.
    function create(): void {
        const c = Qt.createComponent("file://$PLUGIN/Service.qml");
        svc = c.createObject(probe, { pluginId: "haseen.weather", settings: Qt.binding(() => Plugins.settingsFor("haseen.weather")) });
        if (!svc) {
            console.log("RESULT " + JSON.stringify({ error: c.errorString() }));
            Qt.quit();
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!probe.svc && Plugins.registry["haseen.weather"])
                probe.create();
            // Wait for the forecast and for the pick to reach shell.json: the
            // save runs as its own process and may finish after the forecast.
            if (!probe.svc || probe.svc.updated <= 0 || !probe.svc.dailyForecastReport || !probe.svc.report || probe.svc.savingLocation || probe.svc.persistingLocation)
                return;
            if (Quickshell.env("WEATHER_SAVE") === "1" && !probe.saved) {
                probe.saved = true;
                probe.svc.setLocation("Paris", 48.8566, 2.3522);
                return;
            }
            console.log("RESULT " + JSON.stringify(probe.state()));
            Qt.quit();
        }
    }
}
EOF
    run_service() { # MODE SETTINGS [SAVE]
        : >"$CURL_LOG"
        jq -n --argjson s "$2" '{plugins: {"haseen.weather": {settings: $s}}}' >"$CFG"
        capture env WAI_MODE="$1" WEATHER_SAVE="${3:-0}" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
            QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            timeout 40 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
        result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
        [[ -n $result ]] || _fail "weather service ($1) produced no result" "$OUTPUT"
    }
    sr() { jq -r "$1" <<<"$result"; }

    run_service ok '{}'
    assert_eq "GeoClue: source" "geoclue" "$(sr .source)"
    assert_eq "GeoClue: wttr.in asked for the coordinates" "52.52,13.4" "$(sr .query)"
    assert_contains "GeoClue: Open-Meteo at once with them" "$(cat "$CURL_LOG")" "api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.4&"
    assert_not_contains "GeoClue: no IP lookup" "$(cat "$CURL_LOG")" "format=%l"
    assert_eq "GeoClue: Open-Meteo's current conditions" "19|17°C|11 km/h|60%" "$(sr '"\(.temp)|\(.feels)|\(.wind)|\(.humidity)"')"
    assert_eq "GeoClue: night icon from is_day" "$(printf '\xee\x8c\xab')" "$(sr .label)"
    assert_eq "GeoClue: area name from wttr.in" "Berlin" "$(sr .location)"
    assert_eq "three days" "3" "$(sr .days)"
    assert_eq "status line" "Berlin  ·  Temp 19°C  ·  Wind 11 km/h" "$(sr .status)"

    run_service denied '{}'
    assert_eq "denied: IP source" "ip" "$(sr .source)"
    assert_eq "denied: empty wttr.in query" "" "$(sr .query)"
    assert_contains "denied: reason kept for the panel" "$(sr .note)" "disallowed by configuration"
    assert_contains "denied: wttr.in IP city" "$(cat "$CURL_LOG")" "https://wttr.in/?format=%l"
    assert_contains "denied: Open-Meteo at the reported area" "$(cat "$CURL_LOG")" "latitude=52.52&longitude=13.405&"
    assert_eq "denied: wttr.in's current conditions" "19|17°C|9 km/h" "$(sr '"\(.temp)|\(.feels)|\(.wind)"')"

    run_service ok '{"location":"Paris","units":"imperial"}'
    assert_eq "manual: source" "manual" "$(sr .source)"
    assert_eq "manual: city query" "Paris" "$(sr .query)"
    assert_eq "manual: name shown" "Paris" "$(sr .location)"
    assert_eq "manual: imperial" "66" "$(sr .temp)"

    # The panel's pick: Config.setRuntime at once, shell.json via --set.
    run_service ok '{}' 1
    assert_eq "saved pick: manual" "manual" "$(sr .source)"
    assert_eq "saved pick: coordinates query" "48.8566,2.3522" "$(sr .query)"
    assert_eq "saved pick: spinner done" "false" "$(sr .saving)"
    assert_contains "saved pick: Open-Meteo at the pick" "$(cat "$CURL_LOG")" "latitude=48.8566&longitude=2.3522&"
    assert_eq "saved pick: persisted to shell.json" "48.8566,2.3522|Paris" "$(wsetting location)|$(wsetting locationName)"
fi
