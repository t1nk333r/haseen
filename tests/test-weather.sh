# shellcheck shell=bash
# haseen:covers bin/haseen-notification-send bin/haseen-plugin-settings bin/haseen-plugin-validate
# haseen:covers bin/haseen-setup-geoclue bin/haseen-weather-{icon,location,status}
# haseen:covers share/haseen/VERSION share/haseen/default/shell.json share/haseen/lib/packages.sh
# haseen:covers share/haseen/shell/Compat/** share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.weather/** tests/fixtures/wttr/**
# haseen:covers tools/smoke-session.conf share/haseen/shell/plugins/*/manifest.json
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
# Plan 180: the temperature beside the bar icon, on unless turned off.
assert_eq "the bar's temperature is on by default" "true" "$(jq -r '.settings.temperature.default' "$PLUGIN/manifest.json")"
assert_contains "the curve asks for antialiased curves on the GPU scene graph" "$(cat "$PLUGIN/Panel.qml")" \
    'preferredRendererType: Shape.CurveRenderer'
assert_contains "the pill shows it unless settings.temperature is false" "$(cat "$PLUGIN/Widget.qml")" \
    'text: settings.temperature !== false && service && service.reportTempNum !== "" ? service.reportTempNum + "°" : ""'
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
# The forecast days are today and the next two, so the hourly slots are live.
jq --arg d0 "$(date +%F)" --arg d1 "$(date -d '+1 day' +%F)" --arg d2 "$(date -d '+2 day' +%F)" \
    '.nearest_area[0].latitude = "52.520" | .nearest_area[0].longitude = "13.405"
     | .weather[0].date = $d0 | .weather[1].date = $d1 | .weather[2].date = $d2' "$FIXTURES/wttr/j1.json" >"$J1"
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
*api.open-meteo.com*) if [ "${WEATHER_OM:-}" = refused ]; then exit 22; fi; cat "$OM" ;;
*format=%l*) echo "Berlin, Berlin, Germany" ;;
*format=j1*) if [ "${WEATHER_WTTR:-}" = refused ]; then exit 22; fi; cat "$J1" ;;
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
        eq("the future days, five at most", ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10"], days.map(x => x.date));
        eq("day temps", ["17°", "11°", "63°"], [M.bareTempForDay(days[0], "max", false), M.bareTempForDay(days[0], "min", false), M.bareTempForDay(days[0], "max", true)]);
        eq("day icons", ["\ue318", "\ue30d", "\ue31d", "\ue33d"], days.map(M.dayIcon));
        eq("wttr days when open-meteo is missing", ["2026-10-05"], M.buildForecastDays({ weather: [{ date: "2026-10-04" }, { date: "2026-10-05" }] }, null, "2026-10-04").map(x => x.date));
        eq("wttr icon nearest noon", "\ue318", M.dayIcon({ hourly: [{ time: "0", weatherCode: "113" }, { time: "1200", weatherCode: "296" }] }));
        eq("fog at night", "\ue346", M.iconForCode(143, true));
        eq("unknown code", "\ue33d", M.iconForCode(999, false));
        eq("wttr icon: night from its symbol's name, else day", ["\ue32b", "\ue30d", "\ue30d"], [
            M.currentIcon({ weatherCode: "113", weatherIconUrl: [{ value: "https://cdn.worldweatheronline.com/images/wsymbols01_png_64/wsymbol_0008_clear_sky_night.png" }] }, ""),
            M.currentIcon({ weatherCode: "113", weatherIconUrl: [{ value: "https://cdn.worldweatheronline.com/images/wsymbols01_png_64/wsymbol_0001_sunny.png" }] }, ""),
            M.currentIcon({ weatherCode: "113" }, "")]);
        eq("save completes on the source that has the location", [true, false, true], [M.weatherResponseCompletesSave(true, "open-meteo"), M.weatherResponseCompletesSave(true, "wttr"), M.weatherResponseCompletesSave(false, "wttr")]);
        // Plan 180: the redesigned panel's data.
        eq("open-meteo asks for today and five days", true, M.openMeteoUrl(1, 2).indexOf("&forecast_days=6") > 0);
        const sixDays = { daily: { time: ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12"], weather_code: [0, 0, 0, 0, 0, 0, 0],
            temperature_2m_max: [1, 2, 3, 4, 5, 6, 7], temperature_2m_min: [0, 0, 0, 0, 0, 0, 0] } };
        eq("five days at most", 5, M.buildForecastDays(null, sixDays, "2026-10-06").length);
        const night = "https://cdn.worldweatheronline.com/images/wsymbols01_png_64/wsymbol_0008_clear_sky_night.png";
        const wttr = { weather: [
            { date: "2026-10-06", maxtempC: "22", mintempC: "13", maxtempF: "72", mintempF: "55", hourly: [
                { time: "900", tempC: "15", tempF: "59", weatherCode: "113" }, { time: "1200", tempC: "20", tempF: "68", weatherCode: "116" },
                { time: "1500", tempC: "21", tempF: "70", weatherCode: "119" }, { time: "2100", tempC: "16", tempF: "61", weatherCode: "113", weatherIconUrl: [{ value: night }] }] },
            { date: "2026-10-07", hourly: [{ time: "0", tempC: "14", tempF: "57", weatherCode: "296" }, { time: "300", tempC: "13", tempF: "55", weatherCode: "296" }] }] };
        eq("hours after now, across midnight", ["15|21|70", "21|16|61", "00|14|57"],
            M.hourlySlots(wttr, new Date(2026, 9, 6, 12, 30), 3).map(h => h.hour + "|" + h.tempC + "|" + h.tempF));
        eq("an hour's night icon from its symbol", "\ue32b", M.hourlySlots(wttr, new Date(2026, 9, 6, 20, 0), 1)[0].icon);
        eq("an hour on the clock is past", "1500", M.hourlySlots(wttr, new Date(2026, 9, 6, 12, 0), 1)[0].hour + "00");
        eq("today's range from open-meteo", { maxC: "20", minC: "12", maxF: "68", minF: "54" }, M.todayRange(wttr, om, "2026-10-06"));
        eq("today's range from wttr.in without it", { maxC: "22", minC: "13", maxF: "72", minF: "55" }, M.todayRange(wttr, null, "2026-10-06"));
        eq("no range for another day", "", M.todayRange(wttr, null, "2026-10-09").maxC);
        eq("conditions in words", ["Sunny", "Clear", "Partly cloudy", "Light rain", "Thunderstorm", "Snow", "Sleet", ""],
            [M.conditionForCode(113, false), M.conditionForCode(113, true), M.conditionForCode("116"), M.conditionForCode(296), M.conditionForCode(389),
             M.conditionForCode(179), M.conditionForCode(182), M.conditionForCode(999)]);
        eq("open-meteo's condition, day and night", ["Clear", "Rain"], [M.currentCondition(cur), M.currentCondition({ openMeteoWeatherCode: 63, isDay: 1 })]);
        eq("wttr.in's condition, night from its symbol", "Clear", M.currentCondition({ weatherCode: "113", weatherIconUrl: [{ value: night }] }));
        const scaled = [{ mintempC: "10", maxtempC: "20" }, { mintempC: "15", maxtempC: "30" }];
        eq("the days' shared scale", { lo: 10, hi: 30 }, M.daysScale(scaled, false));
        eq("a range bar on it", { start: 0.25, width: 0.75 }, M.rangeBar(scaled[1], M.daysScale(scaled, false), false));
        eq("no scale for one number", null, M.daysScale([{ mintempC: "10", maxtempC: "10" }], false));
        const c = M.curve(["20", "30", "10"], 300, 10, 100, 120);
        eq("curve points: slot centres, warmest at the top", [[50, 60], [150, 10], [250, 110]], c.points);
        eq("the line starts at the first point", "M 50 60 C", c.line.slice(0, 9));
        eq("the area closes at the bottom", true, /L 250 120 L 50 120 Z$/.test(c.area));
        eq("a flat curve sits in the middle", [60, 60], M.curve(["5", "5"], 100, 10, 100, 120).points.map(p => p[1]));
        eq("no curve for one value", "", M.curve(["5"], 100, 10, 100, 120).line);
        eq("no curve with a missing value", "", M.curve(["5", "", "7"], 300, 10, 100, 120).line);
        const zig = M.curve(["10", "30", "10", "30"], 400, 10, 100, 120);
        // Plan 181: smooth through every point. At each inner point the
        // incoming and outgoing control points and the point are on one line.
        const wave = M.curve(["20", "28", "24", "26", "18", "22"], 600, 10, 100, 120);
        const segs = wave.line.split(" C ").slice(1).map(seg => seg.split(" ").map(Number));
        eq("the curve turns smoothly through every point", true, segs.slice(0, -1).every((seg, i) => {
            const inc = [seg[2], seg[3]], pt = [seg[4], seg[5]], out = [segs[i + 1][0], segs[i + 1][1]];
            return Math.abs((pt[1] - inc[1]) * (out[0] - pt[0]) - (out[1] - pt[1]) * (pt[0] - inc[0])) < 0.5;
        }));
        eq("flat at a peak", true, Math.abs(segs[0][3] - segs[0][5]) < 0.01 && Math.abs(segs[1][1] - segs[0][5]) < 0.01);
        // The exact paths: a straight line for two points (tangents at the
        // ends, controls a third along), and the zig-zag flat at each turn.
        eq("two points: a straight line", "M 75 110 C 125 76.67 175 43.33 225 10", M.curve(["1", "2"], 300, 10, 100, 120).line);
        eq("a zig-zag: flat at every turn", "M 50 110 C 83.33 76.67 116.67 10 150 10 C 183.33 10 216.67 110 250 110 C 283.33 110 316.67 43.33 350 10",
            M.curve(["10", "30", "10", "30"], 400, 10, 100, 120).line);
        // Steep between flat stretches: the limit keeps every control point
        // between its segment's two points, so nothing overshoots.
        const steep = M.curve(["0", "1", "100", "101"], 400, 10, 100, 120).line.split(" C ").slice(1).map(seg => seg.split(" ").map(Number));
        const starts = [110].concat(steep.map(seg => seg[5]));
        eq("a steep segment between flat ones stays between its points", true, steep.every((seg, i) => {
            const lo = Math.min(starts[i], seg[5]) - 0.011, hi = Math.max(starts[i], seg[5]) + 0.011;
            return [seg[1], seg[3]].every(y => y >= lo && y <= hi);
        }));
        eq("no curve before the panel has a width", ["", ""], [M.curve(["1", "2", "3"], 0, 10, 100, 120).line, M.curve(["1", "2", "3"], 0.1, 10, 100, 120).line]);
        eq("the line's control points stay inside the band", true,
            zig.line.split(" C ").slice(1).every(seg => { const n = seg.split(" ").map(Number); return [n[1], n[3], n[5]].every(y => y >= 10 && y <= 110); }));
        eq("status line", "Berlin  ·  Temp 19°C  ·  Wind 9 km/h", M.statusLine("berlin", "19°C", "9 km/h"));
        eq("status without data", "Weather unavailable", M.statusLine("Berlin", "", ""));
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml"
    assert_status "Model.js units" 0 "$STATUS"
    assert_eq "no unit failures" "" "$(grep 'UNIT-FAIL' <<<"$OUTPUT" || true)"
    assert_eq "units ran" "61" "$(grep -c 'UNIT-PASS' <<<"$OUTPUT")"
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
*api.open-meteo.com*) if [ "${WEATHER_OM:-}" = refused ]; then exit 22; fi; cat "$OM" ;;
*format=%l*) echo "Berlin, Berlin, Germany" ;;
*format=j1*) if [ "${WEATHER_WTTR:-}" = refused ]; then exit 22; fi; cat "$J1" ;;
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
            days: svc.forecastDays.length, status: svc.statusLine, saving: svc.savingLocation, fromOpenMeteo: svc.labelFromOpenMeteo,
            hours: svc.hours.length, condition: svc.condition, high: svc.todayRange.maxC, low: svc.todayRange.minC, panel: panelState(), pill: pillState() };
    }

    // Plan 180: the redesigned panel on this service: "Now" and the hours,
    // the curve's points, the tab it opens on, and switching.
    function panelState(): var {
        const c = Qt.createComponent("file://$PLUGIN/Panel.qml");
        const p = c.createObject(probe, { pluginId: "haseen.weather", service: svc });
        if (!p)
            return { error: c.errorString() };
        svc.panelTab = 0;
        const s = { tab: p.tab, first: p.slots.length ? p.slots[0].hour + "|" + p.slots[0].temp : "", slots: p.slots.length, points: p.curve.points.length,
            hasHours: p.hasHours, scale: p.daysScale !== null,
            tall: p.bodyHeight >= p.hoursTabHeight && p.bodyHeight >= p.curveTabHeight && p.hoursTabHeight > 0 && p.curveTabHeight > 0,
            // A forecast slot's temperature is in the panel's unit.
            unit: p.slots.length > 1 && svc.hours.length > 0 ? p.slots[1].temp === (svc.useImperial ? svc.hours[0].tempF : svc.hours[0].tempC) : null };
        // Keys: Tab cycles, the arrows point at the tab they select and stop.
        s.keys = [p.tabForKey(Qt.Key_Left), p.tabForKey(Qt.Key_Right), p.tabForKey(Qt.Key_Tab)].join(",");
        p.setTab(1);
        s.switched = svc.panelTab;
        s.keysOnSecond = [p.tabForKey(Qt.Key_Right), p.tabForKey(Qt.Key_Left), p.tabForKey(Qt.Key_Backtab)].join(",");
        p.LayoutMirroring.enabled = true;
        s.keysMirrored = [p.tabForKey(Qt.Key_Left), p.tabForKey(Qt.Key_Right)].join(",");
        p.setTab(0);
        s.keysMirroredFirst = [p.tabForKey(Qt.Key_Left), p.tabForKey(Qt.Key_Right)].join(",");
        p.destroy();
        return s;
    }

    // The bar pill on the same service: the temperature beside the icon,
    // none with settings.temperature false or without a service.
    function pillState(): var {
        const c = Qt.createComponent("file://$PLUGIN/Widget.qml");
        const on = c.createObject(probe, { pluginId: "haseen.weather", service: svc });
        const off = c.createObject(probe, { pluginId: "haseen.weather", service: svc, settings: { temperature: false } });
        const none = c.createObject(probe, { pluginId: "haseen.weather", service: null });
        if (!on || !off || !none)
            return { error: c.errorString() };
        const s = { on: on.text, off: off.text, offGlyph: off.glyph !== "", none: none.text, noneVisible: none.visible };
        on.destroy();
        off.destroy();
        none.destroy();
        return s;
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
            // With Open-Meteo refusing (WEATHER_OM=refused) there is no
            // forecast to wait for: wttr.in's report and its icon are all.
            const refused = Quickshell.env("WEATHER_OM") === "refused";
            const noWttr = Quickshell.env("WEATHER_WTTR") === "refused";
            if (!probe.svc || probe.svc.updated <= 0 || (!noWttr && !probe.svc.report) || probe.svc.savingLocation || probe.svc.persistingLocation)
                return;
            if (refused ? probe.svc.label === "" : !probe.svc.dailyForecastReport)
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
    assert_eq "GeoClue: and wttr.in's day icon does not replace it" "true" "$(sr .fromOpenMeteo)"
    # Plan 180: the redesigned panel's data, with Open-Meteo answering.
    assert_eq "GeoClue: seven hours ahead from wttr.in" "7" "$(sr .hours)"
    assert_eq "GeoClue: the condition in words" "Clear" "$(sr .condition)"
    assert_eq "GeoClue: today's high and low from Open-Meteo" "20|12" "$(sr '"\(.high)|\(.low)"')"
    assert_eq "panel: built on the service" "null" "$(sr .panel.error)"
    assert_eq "panel: Now first, at the current temperature" "Now|19" "$(sr .panel.first)"
    assert_eq "panel: then the seven hours" "8" "$(sr .panel.slots)"
    assert_eq "panel: a curve point per slot" "8|true" "$(sr '"\(.panel.points)|\(.panel.hasHours)"')"
    assert_eq "panel: the days have a shared scale" "true" "$(sr .panel.scale)"
    assert_eq "panel: opens on the first tab" "0" "$(sr .panel.tab)"
    assert_eq "panel: the body is as tall as either tab" "true" "$(sr .panel.tall)"
    assert_eq "panel: forecast temperatures in Celsius" "true" "$(sr .panel.unit)"
    assert_eq "panel: on the first tab, Left stays, Right and Tab select the second" "0,1,1" "$(sr .panel.keys)"
    assert_eq "panel: switching is kept by the service" "1" "$(sr .panel.switched)"
    assert_eq "panel: on the second tab, Right stays, Left and Shift+Tab go back" "1,0,0" "$(sr .panel.keysOnSecond)"
    assert_eq "panel: mirrored, on the second tab Left stays and Right goes back" "1,0" "$(sr .panel.keysMirrored)"
    assert_eq "panel: mirrored, on the first tab Left selects the second" "1,0" "$(sr .panel.keysMirroredFirst)"
    assert_eq "pill: built on the service" "null" "$(sr .pill.error)"
    assert_eq "pill: the temperature beside the icon" "19°" "$(sr .pill.on)"
    assert_eq "pill: none with settings.temperature false, the icon stays" "|true" "$(sr '"\(.pill.off)|\(.pill.offGlyph)"')"
    assert_eq "pill: nothing without a service" "|false" "$(sr '"\(.pill.none)|\(.pill.noneVisible)"')"
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
    assert_eq "manual: the panel's hours in Fahrenheit too" "true" "$(sr .panel.unit)"
    assert_eq "manual: and the pill" "66°" "$(sr .pill.on)"

    # Plan 179: saved coordinates and Open-Meteo refusing every request (the
    # owner's luna, 2026-11-21): the bar still gets wttr.in's icon, night
    # when its symbol says so, and its current conditions.
    J1_DAY="$J1"
    J1="$SANDBOX/j1-night.json"
    jq '.current_condition[0].weatherCode = "113" | .current_condition[0].weatherIconUrl = [{"value": "https://cdn.worldweatheronline.com/images/wsymbols01_png_64/wsymbol_0008_clear_sky_night.png"}]' "$J1_DAY" >"$J1"
    export WEATHER_OM=refused
    run_service ok '{"location":"52.52,13.4","locationName":"Berlin"}'
    unset WEATHER_OM
    J1="$J1_DAY"
    assert_contains "Open-Meteo refused: it was asked" "$(cat "$CURL_LOG")" "api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.4&"
    assert_eq "Open-Meteo refused: the bar has wttr.in's night icon" "$(printf '\xee\x8c\xab')" "$(sr .label)"
    assert_eq "Open-Meteo refused: not marked as Open-Meteo's" "false" "$(sr .fromOpenMeteo)"
    assert_eq "Open-Meteo refused: wttr.in's temperature" "19" "$(sr .temp)"
    assert_eq "Open-Meteo refused: wttr.in's condition, at night" "Clear" "$(sr .condition)"
    assert_eq "Open-Meteo refused: today's range from wttr.in" "20|13" "$(sr '"\(.high)|\(.low)"')"
    assert_eq "Open-Meteo refused: wttr.in's next two days" "2" "$(sr .days)"

    # Plan 180 review: wttr.in failing with saved coordinates. Open-Meteo
    # alone gives the icon, the temperature and the days; there are no hours,
    # and the panel says so on both tabs instead of a lone column or a blank
    # curve.
    # Metric pinned: without wttr.in's country the test locale would pick
    # Fahrenheit.
    export WEATHER_WTTR=refused
    run_service ok '{"location":"52.52,13.4","locationName":"Berlin","units":"metric"}'
    unset WEATHER_WTTR
    assert_eq "wttr.in refused: Open-Meteo's temperature and icon" "19|$(printf '\xee\x8c\xab')" "$(sr '"\(.temp)|\(.label)"')"
    assert_eq "wttr.in refused: no hours" "0" "$(sr .hours)"
    assert_eq "wttr.in refused: the panel has only Now and no curve" "1|false" "$(sr '"\(.panel.slots)|\(.panel.hasHours)"')"
    assert_eq "wttr.in refused: Open-Meteo's days" "3" "$(sr .days)"

    # The panel's pick: Config.setRuntime at once, shell.json via --set.
    run_service ok '{}' 1
    assert_eq "saved pick: manual" "manual" "$(sr .source)"
    assert_eq "saved pick: coordinates query" "48.8566,2.3522" "$(sr .query)"
    assert_eq "saved pick: spinner done" "false" "$(sr .saving)"
    assert_contains "saved pick: Open-Meteo at the pick" "$(cat "$CURL_LOG")" "latitude=48.8566&longitude=2.3522&"
    assert_eq "saved pick: persisted to shell.json" "48.8566,2.3522|Paris" "$(wsetting location)|$(wsetting locationName)"
fi
