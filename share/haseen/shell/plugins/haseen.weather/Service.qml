import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.weather service (role `weather`), shared by the bar widget and the
// lazily loaded panel. It exists only while the plugin is enabled.
//
// The fetch logic is Omarchy's weather panel (shell/plugins/panels/weather/
// Panel.qml; MIT, Copyright (c) David Heinemeier Hansson): wttr.in j1 for the
// current conditions and the reported area, Open-Meteo for the day/night-aware
// icon and the next three days (at once when coordinates are known, else from
// the area wttr.in reports), three quick retries per source, a refresh every
// 15 minutes, and wttr.in's IP lookup when no location is known.
// haseen changes: the location is settings.location (a city or "lat,lon",
// locationName labels coordinates), else a GeoClue position from
// `haseen-weather-location --detect`, else the IP lookup; edits persist
// through `haseen-weather-location --set/--clear` into shell.json.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    // With the debugIpc test hook on nothing is fetched on its own.
    readonly property bool autoFetch: settings.debugIpc !== true

    // ---- Location: manual setting, else GeoClue, else IP (empty query).
    readonly property var manualLocation: Model.parseLocationSetting(settings.location, settings.locationName)
    readonly property bool hasManualLocation: Model.isLocationSet(manualLocation)
    // Last GeoClue fix {latitude, longitude}, kept when a later ask fails.
    property var detectedLocation: null
    // Why GeoClue gave nothing (stderr of --detect), "" after a fix.
    property string geoclueNote: ""
    property bool needDetect: true
    readonly property var configuredLocationState: Model.effectiveLocation(manualLocation, detectedLocation)
    readonly property string locationSource: hasManualLocation ? "manual" : (detectedLocation ? "geoclue" : "ip")
    readonly property string configuredLocation: configuredLocationState.name
    readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)
    readonly property bool hasConfiguredCoordinates: Model.hasCoordinates(configuredLocationState)

    // ---- Reports. Kept on failure so stale data stays visible.
    property var report: null
    property var dailyForecastReport: null
    property string wttrLocation: ""
    // The condition glyph for the bar and the panel hero.
    property string label: ""
    property real updated: 0
    property int forecastRetries: 0
    property int dailyForecastRetries: 0

    // A committed location shows a spinner until its first answer arrives.
    property bool savingLocation: false
    property bool savingLocationQueryStarted: false
    // shell.json is still being written (`haseen-weather-location --set/--clear`).
    readonly property bool persistingLocation: locationSaveProc.running

    readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
    readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
    readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
    readonly property var forecastDays: Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(updated || Date.now()), "yyyy-MM-dd"))
    readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""
    readonly property bool useImperial: Model.shouldUseImperial(settings.units, Qt.locale().name, reportCountry)

    readonly property string reportLocation: configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
    readonly property string reportTempNum: current ? String(useImperial ? current.temp_F : current.temp_C) : ""
    readonly property string tempUnit: "°" + (useImperial ? "F" : "C")
    readonly property string reportFeels: current ? Model.formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC, useImperial) : ""
    readonly property string reportWind: current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
    readonly property string reportHumidity: current ? (current.humidity + "%") : ""
    readonly property string statusLine: Model.statusLine(reportLocation, reportTempNum === "" ? "" : reportTempNum + tempUnit, reportWind)

    // Keep the previous report visible while the new location loads.
    onLocationQueryChanged: {
        if (savingLocation)
            savingLocationQueryStarted = true;
        forecastRetries = 0;
        dailyForecastRetries = 0;
        forecastProc.running = false;
        dailyForecastProc.running = false;
        Qt.callLater(run);
    }
    // Clearing the manual location hands over to GeoClue: ask it first.
    onHasManualLocationChanged: {
        if (!hasManualLocation)
            needDetect = true;
    }

    // A full refresh cycle: a fresh retry budget, a new GeoClue ask when no
    // location is stored, then the fetches.
    function refresh(): void {
        forecastRetries = 0;
        dailyForecastRetries = 0;
        needDetect = !hasManualLocation;
        Qt.callLater(run);
    }

    function run(): void {
        if (!hasManualLocation && needDetect) {
            if (!detectProc.running)
                detectProc.running = true;
            return;
        }
        fetch();
    }

    function fetch(): void {
        if (!forecastProc.running)
            forecastProc.running = true;
        if (root.locationQuery === "" && !locationProc.running)
            locationProc.running = true;
        // With known coordinates this fetches Open-Meteo right away; without
        // them it waits for the area wttr.in reports.
        refreshDailyForecast(null);
    }

    function refreshDailyForecast(sourceReport: var): void {
        if (dailyForecastProc.running)
            return;
        let lat = parseFloat(String(root.configuredLocationState.latitude));
        let lon = parseFloat(String(root.configuredLocationState.longitude));
        if (isNaN(lat) || isNaN(lon)) {
            const area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo;
            if (!area)
                return;
            lat = parseFloat(String(area.latitude || ""));
            lon = parseFloat(String(area.longitude || ""));
        }
        if (isNaN(lat) || isNaN(lon))
            return;
        dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", Model.openMeteoUrl(lat, lon)];
        dailyForecastProc.running = true;
    }

    function acceptReport(raw: string): bool {
        const text = String(raw || "").trim();
        if (!text)
            return false;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            return false;
        }
        if (!parsed || !Array.isArray(parsed.current_condition))
            return false;
        root.report = parsed;
        root.updated = Date.now();
        if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition[0], root.label);
        root.forecastRetries = 0;
        if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation();
        // Known coordinates already drove the Open-Meteo fetch; only the
        // IP/name path needs the area wttr.in reported.
        if (!root.hasConfiguredCoordinates)
            root.refreshDailyForecast(parsed);
        return true;
    }

    function acceptDaily(raw: string): bool {
        const text = String(raw || "").trim();
        if (!text)
            return false;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            return false;
        }
        const parsedCurrent = Model.openMeteoCurrentCondition(parsed);
        if (!parsedCurrent && !(parsed && parsed.daily))
            return false;
        root.dailyForecastReport = parsed;
        root.updated = Date.now();
        root.label = Model.currentIcon(parsedCurrent, root.label);
        root.dailyForecastRetries = 0;
        if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
            root.finishSavingLocation();
        return true;
    }

    function acceptDetected(raw: string, note: string): void {
        const fix = Model.parseDetected(raw);
        root.needDetect = false;
        if (fix) {
            root.detectedLocation = fix;
            root.geoclueNote = "";
        } else {
            root.geoclueNote = String(note || "").trim().split("\n")[0];
        }
        Qt.callLater(root.run);
    }

    // ---- Location editing (the panel's search field).
    function setLocation(name: string, latitude: var, longitude: var): void {
        const values = Model.locationSettings(name, latitude, longitude);
        if (values.location === "") {
            clearLocation();
            return;
        }
        root.savingLocation = true;
        root.savingLocationQueryStarted = false;
        Config.setRuntime(["plugins", root.pluginId, "settings", "location"], values.location);
        Config.setRuntime(["plugins", root.pluginId, "settings", "locationName"], values.locationName);
        const lat = parseFloat(String(latitude));
        const lon = parseFloat(String(longitude));
        const args = [root.binDir + "/haseen-weather-location", "--set", values.locationName || values.location];
        if (!isNaN(lat) && !isNaN(lon))
            args.push(lat + "," + lon);
        locationSaveProc.command = args;
        locationSaveProc.running = true;
    }

    function clearLocation(): void {
        root.savingLocation = false;
        root.wttrLocation = "";
        Config.setRuntime(["plugins", root.pluginId, "settings", "location"], "");
        Config.setRuntime(["plugins", root.pluginId, "settings", "locationName"], "");
        locationSaveProc.command = [root.binDir + "/haseen-weather-location", "--clear"];
        locationSaveProc.running = true;
    }

    function finishSavingLocation(): void {
        if (savingLocation && savingLocationQueryStarted)
            savingLocation = false;
    }

    function cancelSaving(): void {
        savingLocation = false;
        savingLocationQueryStarted = false;
    }

    function notifyStatus(): void {
        Quickshell.execDetached([root.binDir + "/haseen-notification-send", root.statusLine]);
    }

    Process {
        id: detectProc

        command: [root.binDir + "/haseen-weather-location", "--detect"]
        stdout: StdioCollector {
            id: detectOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: detectErr
            waitForEnd: true
        }
        onExited: code => root.acceptDetected(code === 0 ? detectOut.text : "", detectErr.text)
    }

    Process {
        id: forecastProc

        command: ["curl", "-fsS", "--max-time", "10", Model.wttrUrl(root.locationQuery)]
        stdout: StdioCollector {
            id: forecastOut
            waitForEnd: true
        }
        onExited: code => {
            if (code !== 0 || !root.acceptReport(forecastOut.text))
                root.scheduleForecastRetry();
        }
    }

    // wttr.in can be slow or flaky for a location it has not cached yet.
    function scheduleForecastRetry(): void {
        if (forecastRetries >= 3)
            return;
        forecastRetries++;
        forecastRetryTimer.restart();
    }

    // One wttr.in retry, at most three per refresh.
    // haseen:ui-timeout
    Timer {
        id: forecastRetryTimer

        interval: 2500
        repeat: false
        onTriggered: {
            if (!forecastProc.running)
                forecastProc.running = true;
        }
    }

    // With coordinates Open-Meteo alone updates the icon, so a dropped answer
    // (waking before the network is back) retries too.
    function scheduleDailyForecastRetry(): void {
        if (dailyForecastRetries >= 3)
            return;
        dailyForecastRetries++;
        dailyForecastRetryTimer.restart();
    }

    // One Open-Meteo retry, at most three per refresh.
    // haseen:ui-timeout
    Timer {
        id: dailyForecastRetryTimer

        interval: 2500
        repeat: false
        onTriggered: root.refreshDailyForecast(null)
    }

    Process {
        id: dailyForecastProc

        stdout: StdioCollector {
            id: dailyOut
            waitForEnd: true
        }
        onExited: code => {
            if (code !== 0 || !root.acceptDaily(dailyOut.text))
                root.scheduleDailyForecastRetry();
        }
    }

    Process {
        id: locationProc

        command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
        stdout: StdioCollector {
            id: locationOut
            waitForEnd: true
        }
        onExited: code => {
            const raw = String(locationOut.text || "").trim();
            if (code === 0 && raw !== "" && raw.indexOf("<") < 0)
                root.wttrLocation = raw.split(",")[0];
        }
    }

    Process {
        id: locationSaveProc

        onExited: code => {
            if (code !== 0) {
                root.cancelSaving();
                return;
            }
            // Saving the already-active location must not strand the spinner.
            if (root.savingLocation && !root.savingLocationQueryStarted) {
                root.savingLocationQueryStarted = true;
                root.refresh();
            }
        }
    }

    // Omarchy's refresh cadence (15 minutes); the first run is at start.
    // haseen:sample
    Timer {
        interval: 900000
        repeat: true
        running: root.autoFetch
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Test hook (settings.debugIpc): answers from files instead of the
    // network, so a smoke run never depends on wttr.in or Open-Meteo.
    FileView {
        id: wttrFixture

        printErrors: false
        onLoaded: root.acceptReport(text())
    }

    FileView {
        id: dailyFixture

        printErrors: false
        onLoaded: root.acceptDaily(text())
    }

    IpcHandler {
        target: "haseen.weather"
        enabled: root.settings.debugIpc === true

        function loadFixture(wttrPath: string, openMeteoPath: string): void {
            wttrFixture.path = "";
            wttrFixture.path = wttrPath;
            dailyFixture.path = "";
            dailyFixture.path = openMeteoPath;
        }

        function refresh(): void {
            root.refresh();
        }

        function state(): string {
            return JSON.stringify({
                source: root.locationSource,
                query: root.locationQuery,
                location: root.reportLocation,
                geoclueNote: root.geoclueNote,
                imperial: root.useImperial,
                label: root.label,
                temp: root.reportTempNum,
                feels: root.reportFeels,
                wind: root.reportWind,
                humidity: root.reportHumidity,
                days: root.forecastDays.length,
                status: root.statusLine,
                updated: root.updated
            });
        }
    }
}
