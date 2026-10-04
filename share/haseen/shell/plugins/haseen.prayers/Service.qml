import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Engine.js" as Engine
import "Model.js" as Model

// haseen.prayers service (role `prayers`): the one engine and notifier. It
// asks haseen-prayers-zone.sh for the timezone window, computes the schedule
// offline with Engine.js, ticks every 30 s, queues notifications through
// haseen-prayers-notify.sh, and holds the session state the panel layouts
// read as `host` (the bar widgets read it too). Bar widgets exist once per
// screen; keeping this here means one schedule and one notification per
// prayer however many bars there are.
//
// Adapted from Panel.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem Sayed);
// see LICENSE and UPSTREAM.md beside this file.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool debugIpc: settings.debugIpc === true

    property var schedule: null
    property var zone: null
    property string lastError: ""
    // Test hook (debugIpc): shifts the clock the schedule is read at.
    property real clockOffset: 0
    property date nowTick: new Date()
    property double previousTickEpoch: Date.now()
    property string zoneRequestedTimezone: ""
    property var notificationQueue: []
    property var activeNotification: null
    property int notificationRetryAttempt: 0
    property string notificationWarning: ""
    // Session-only: which of the panel's settings are unfolded, and whether a
    // text field or dropdown owns the keyboard. Neither belongs in shell.json.
    property bool displaySettingsOpen: false
    property bool keysBlocked: false
    property var pendingMethodSuggestion: null

    // Location picker state. All session-only: nothing is written until the
    // user picks a row, and then only through commitLocation.
    property var locationChoices: []
    property string locationStatus: ""
    property string geocodePendingQuery: ""
    property string geocodeActiveQuery: ""
    property bool detectingLocation: false
    readonly property bool searchingLocation: geocodeProcess.running

    readonly property string zoneScript: Model.filePath(Qt.resolvedUrl("haseen-prayers-zone.sh"))
    readonly property string notificationScript: Model.filePath(Qt.resolvedUrl("haseen-prayers-notify.sh"))
    readonly property string setScript: Model.filePath(Qt.resolvedUrl("haseen-prayers-set.sh"))

    function setting(key: string, fallback: var): var {
        const v = settings ? settings[key] : undefined;
        return v === undefined || v === null ? fallback : v;
    }

    readonly property string locationLabel: String(setting("locationLabel", "Riyadh"))
    readonly property string locationLabelAr: String(setting("locationLabelAr", ""))
    readonly property string latitude: String(setting("latitude", "24.7136"))
    readonly property string longitude: String(setting("longitude", "46.6753"))
    readonly property string timezone: String(setting("timezone", "Asia/Riyadh"))
    readonly property int calculationMethod: Math.round(Model.number(setting("calculationMethod", 4), 4))
    readonly property bool hanafi: Model.bool(setting("hanafi", false))
    readonly property int school: hanafi ? 1 : 0
    readonly property int latitudeAdjustmentMethod: latitudeRule(String(setting("highLatitudeRule", "Angle based")))
    readonly property int midnightMode: String(setting("midnightMode", "Standard")) === "Jafari" ? 1 : 0
    readonly property string shafaq: shafaqValue(String(setting("shafaq", "General")))
    readonly property int hijriAdjustment: Math.round(Model.number(setting("hijriAdjustment", 0), 0))
    readonly property string tune: String(setting("tune", "0,0,0,0,0,0,0,0,0"))
    readonly property string methodSettings: String(setting("customMethodSettings", ""))
    readonly property string panelStyle: String(setting("panelStyle", "Horizon"))
    readonly property string timeFormat: String(setting("timeFormat", "24-hour"))
    readonly property string language: String(setting("language", "English"))
    readonly property string arabicFont: String(setting("arabicFont", "Noto Naskh Arabic"))
    readonly property string barDisplay: String(setting("barDisplay", "Strip + countdown"))
    readonly property bool isArabic: language === "Arabic"
    readonly property bool showSunrise: Model.bool(setting("showSunrise", true))
    readonly property bool showNightMarkers: Model.bool(setting("showNightMarkers", true))
    readonly property int highlightBeforeMinutes: Math.max(0, Math.round(Model.number(setting("highlightBeforeMinutes", 15), 15)))
    readonly property bool notificationsEnabled: Model.bool(setting("notifications", false))
    readonly property int notifyBeforeMinutes: Math.max(0, Math.round(Model.number(setting("notifyBeforeMinutes", 10), 10)))
    readonly property int notificationGraceMinutes: Math.max(1, Math.round(Model.number(setting("notificationGraceMinutes", 10), 10)))
    readonly property bool notificationSoundEnabled: Model.bool(setting("notificationSound", true))
    readonly property string notificationSoundFile: String(setting("notificationSoundFile", "") || "").trim()
    readonly property int notificationSoundVolume: Math.max(0, Math.min(100, Math.round(Model.number(setting("notificationSoundVolume", 60), 60))))
    // What the notify script plays: "off", a path, or the bundled chime.
    readonly property string notificationSound: {
        if (!notificationSoundEnabled || notificationSoundVolume <= 0)
            return "off";
        return notificationSoundFile !== "" ? notificationSoundFile : Model.filePath(Qt.resolvedUrl("assets/prayer-chime.ogg"));
    }
    // Friday's istijabah alert is a single note, not the three-note chime.
    readonly property string istijabahSound: {
        if (!notificationSoundEnabled || notificationSoundVolume <= 0)
            return "off";
        return Model.filePath(Qt.resolvedUrl("assets/istijabah-note.ogg"));
    }

    function clampSetting(key: string, fallback: int): int {
        return Math.max(0, Math.min(60, Math.round(Model.number(setting(key, fallback), fallback))));
    }

    // Iqama: minutes after each adhan, 0 = that prayer has none.
    readonly property var iqamaOffsets: ({
            Fajr: clampSetting("iqamaFajr", 25),
            Dhuhr: clampSetting("iqamaDhuhr", 20),
            Asr: clampSetting("iqamaAsr", 20),
            Maghrib: clampSetting("iqamaMaghrib", 5),
            Isha: clampSetting("iqamaIsha", 20),
            Jumuah: clampSetting("iqamaJumuah", 25)
        })

    readonly property bool istijabahEnabled: Model.bool(setting("istijabah", true))
    readonly property int istijabahLead: Math.max(0, Math.min(180, Math.round(Model.number(setting("istijabahLeadMinutes", 60), 60))))
    readonly property int istijabahRepeat: Math.max(0, Math.min(60, Math.round(Model.number(setting("istijabahRepeatMinutes", 10), 10))))
    readonly property var istijabahWindow: ({
            enabled: istijabahEnabled,
            leadMinutes: istijabahLead,
            repeatMinutes: istijabahRepeat
        })

    readonly property var expectedConfig: ({
            locationLabel: locationLabel,
            latitude: latitude,
            longitude: longitude,
            timezone: timezone,
            method: calculationMethod,
            school: school,
            latitudeAdjustmentMethod: latitudeAdjustmentMethod,
            midnightMode: midnightMode,
            hijriAdjustment: hijriAdjustment,
            tune: tune,
            shafaq: shafaq,
            methodSettings: methodSettings
        })

    readonly property string configKey: [locationLabel, latitude, longitude, timezone, calculationMethod, school, latitudeAdjustmentMethod, midnightMode, hijriAdjustment, tune, shafaq, methodSettings].join("|")

    readonly property var todayDay: Model.today(schedule)
    readonly property var nextPrayer: Model.nextPrayer(schedule, nowTick)
    readonly property var currentPrayer: Model.currentPrayer(schedule, nowTick)
    readonly property var nextEvent: Model.nextEvent(schedule, nowTick, iqamaOffsets)
    readonly property int minutesToNext: Model.minutesUntil(nextEvent, nowTick)
    readonly property bool prayerSoon: isFinite(minutesToNext) && minutesToNext >= 0 && minutesToNext <= highlightBeforeMinutes
    readonly property bool unavailable: !schedule || schedule.ok !== true
    readonly property var prayerRows: Model.dayRows(todayDay, showSunrise, iqamaOffsets, istijabahWindow)
    readonly property var nightRows: showNightMarkers ? Model.nightRows(todayDay) : []
    readonly property string displayLocation: isArabic && locationLabelAr !== "" ? locationLabelAr : locationLabel
    readonly property string nameFontFamily: isArabic ? arabicFont : fontFamily
    readonly property var daySegments: Model.daySegments(todayDay, showSunrise)
    readonly property var nightBand: showNightMarkers ? Model.nightMarkers(todayDay) : null
    readonly property real dayFraction: Model.fractionOfDay(todayDay, nowTick)
    readonly property string methodShort: Model.methodShortName(calculationMethod, todayDay ? todayDay.methodName : "", language)
    readonly property string hijriText: {
        const hijri = Model.hijriLabel(todayDay, language);
        if (!hijri)
            return "";
        return isArabic ? "\u2068" + hijri + "\u2069" : hijri;
    }
    readonly property string footerText: methodShort + "  \u00b7  " + Model.schoolLabel(school, language) + "  \u00b7  " + timezone
    readonly property string tomorrowPrayerText: {
        const prayer = nextPrayer;
        const day = todayDay;
        if (!prayer || !day || prayer.date === day.date)
            return "";
        return Model.tomorrowPrayerLabel(prayer, language, timeFormat);
    }
    readonly property string tooltipText: Model.tooltip(schedule, nextEvent, nowTick, language, timeFormat, displayLocation)
    readonly property string statusMessage: {
        if (lastError !== "")
            return lastError;
        if (todayDay && todayDay.approximate)
            return Model.uiLabel("approximate", language);
        if (notificationWarning !== "")
            return notificationWarning;
        return "";
    }

    // Theme mapping for the ported layouts. Upstream sized everything on a
    // 12 px design grid; haseen scales the same grid by Theme.fontSize.
    readonly property color foreground: Theme.foreground
    readonly property color urgent: Theme.urgent
    readonly property color dim: alpha(foreground, 0.62)
    readonly property color faint: alpha(foreground, 0.42)
    readonly property string fontFamily: Theme.fontFamily
    readonly property real scale: Math.max(1, Theme.fontSize) / 12
    readonly property int fCaption: fontPx(0.833)
    readonly property int fBodySmall: fontPx(0.917)
    readonly property int fBody: fontPx(1.0)
    readonly property int fTitle: fontPx(1.167)
    readonly property int fDisplay: fontPx(2.0)
    readonly property int hairline: sp(1)

    function fontPx(mult: real): int {
        return Math.max(1, Math.round(Math.max(1, Theme.fontSize) * mult));
    }

    function sp(px: real): int {
        return px <= 0 ? 0 : Math.max(1, Math.round(px * scale));
    }

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function latitudeRule(value: string): int {
        if (value === "Middle of the night")
            return 1;
        if (value === "One seventh")
            return 2;
        return 3;
    }

    function shafaqValue(value: string): string {
        if (value === "Red")
            return "ahmer";
        if (value === "White")
            return "abyad";
        return "general";
    }

    // Applied to the running shell first (Config's runtime layer), so the
    // panel repaints on the click itself; haseen-prayers-set.sh then writes
    // the same values to ~/.config/haseen/shell.json.
    function persistSettings(values: var): void {
        for (const key in values)
            Config.setRuntime(["plugins", root.pluginId, "settings", key], values[key]);
        Quickshell.execDetached([root.setScript, JSON.stringify(values)]);
    }

    function setSetting(key: string, value: var): void {
        const values = {};
        values[key] = value;
        persistSettings(values);
    }

    function cycleSetting(key: string, ring: var): void {
        const next = Model.nextInRing(ring, root.setting(key, ring[0]));
        if (next !== "")
            setSetting(key, next);
    }

    function cyclePanelStyle(): void {
        cycleSetting("panelStyle", Model.PANEL_STYLES);
    }
    function cycleBarDisplay(): void {
        cycleSetting("barDisplay", Model.BAR_DISPLAYS);
    }
    function cycleTimeFormat(): void {
        cycleSetting("timeFormat", Model.TIME_FORMATS);
    }
    function cycleLanguage(): void {
        cycleSetting("language", Model.LANGUAGES);
    }

    function toggleDisplaySettings(): void {
        root.displaySettingsOpen = !root.displaySettingsOpen;
        if (!root.displaySettingsOpen)
            root.keysBlocked = false;
    }

    // Debounced so a typed query issues one request per pause. Only one curl
    // runs at a time; a query that moved on is fetched when it finishes.
    function searchLocation(query: string): void {
        const trimmed = String(query || "").replace(/^\s+|\s+$/g, "");
        root.geocodePendingQuery = trimmed;
        if (trimmed.length < 2) {
            root.locationChoices = [];
            root.locationStatus = "";
            geocodeDebounce.stop();
            return;
        }
        geocodeDebounce.restart();
    }

    function startGeocode(): void {
        if (geocodeProcess.running || root.geocodePendingQuery.length < 2)
            return;
        root.geocodeActiveQuery = root.geocodePendingQuery;
        root.locationStatus = "";
        geocodeProcess.command = Model.geocodeCommand(root.geocodeActiveQuery);
        geocodeProcess.running = true;
    }

    function applyLocationResults(raw: string): void {
        const choices = Model.parseLocationResults(raw);
        root.locationChoices = choices;
        root.locationStatus = choices.length === 0 ? Model.uiLabel("noMatches", root.language) : "";
    }

    // The detected place only seeds the search box; it is never committed on
    // its own, because a wrong location means confidently wrong prayer times.
    function detectLocation(): void {
        if (detectProcess.running)
            return;
        root.detectingLocation = true;
        root.locationStatus = "";
        detectProcess.running = true;
    }

    function applyDetectedLocation(raw: string): void {
        const query = Model.detectedLocationQuery(raw);
        root.detectingLocation = false;
        if (query === "") {
            root.locationStatus = Model.uiLabel("detectFailed", root.language);
            return;
        }
        root.locationStatus = Model.uiLabel("detectHint", root.language);
        root.locationDetected(query);
    }

    signal locationDetected(string query)
    signal locationSearchRequested
    signal methodPickerRequested

    function requestLocationSearch(): void {
        root.displaySettingsOpen = true;
        root.locationSearchRequested();
    }

    function requestMethodPicker(): void {
        root.displaySettingsOpen = true;
        root.methodPickerRequested();
    }

    function commitLocation(choice: var): void {
        const values = Model.locationSettings(choice);
        if (!values)
            return;
        root.pendingMethodSuggestion = null;
        const suggestion = Model.suggestedMethod(choice.countryCode, root.calculationMethod);
        if (suggestion) {
            root.pendingMethodSuggestion = {
                id: suggestion.id,
                label: suggestion.label,
                country: String(choice.country || choice.region || choice.name || "")
            };
        }
        root.locationChoices = [];
        root.locationStatus = "";
        root.geocodePendingQuery = "";
        persistSettings(values);
    }

    function applySuggestedMethod(): void {
        if (!root.pendingMethodSuggestion)
            return;
        const method = root.pendingMethodSuggestion.id;
        root.pendingMethodSuggestion = null;
        root.setSetting("calculationMethod", method);
    }

    function dismissMethodSuggestion(): void {
        root.pendingMethodSuggestion = null;
    }

    function applyZone(raw: string): void {
        const value = Model.parseEnvelope(raw);
        if (!value) {
            lastError = "Timezone data was not valid JSON";
            return;
        }
        if (value.ok !== true) {
            lastError = String(value.error || "Timezone data refresh failed");
            return;
        }
        if (String(value.timezone || "") !== root.timezone) {
            Qt.callLater(() => root.refresh());
            return;
        }
        root.zone = value;
        root.lastError = "";
    }

    function recompute(): void {
        if (!root.zone || root.zone.ok !== true || String(root.zone.timezone || "") !== root.timezone)
            return;
        const value = Engine.buildSchedule(root.expectedConfig, root.zone, root.now());
        if (!value || value.ok !== true) {
            root.schedule = null;
            root.lastError = String(value && value.error ? value.error : "Prayer schedule calculation failed");
            root.armZoneRefresh();
            return;
        }
        if (!Model.sameConfig(value.config, root.expectedConfig))
            return;
        root.schedule = value;
        root.lastError = "";
        root.armZoneRefresh();
    }

    function now(): real {
        return Date.now() + root.clockOffset;
    }

    function armZoneRefresh(): void {
        const t = root.now();
        let delay = 86400000;
        const nextMidnight = root.schedule ? new Date(root.schedule.nextRefreshAt || "").getTime() : NaN;
        if (isFinite(nextMidnight) && nextMidnight > t)
            delay = Math.min(delay, nextMidnight - t);
        zoneRefresh.interval = Math.max(1000, Math.round(delay));
        zoneRefresh.restart();
    }

    function refresh(): void {
        if (zoneProcess.running)
            return;
        root.zoneRequestedTimezone = root.timezone;
        zoneProcess.command = [root.zoneScript, "--timezone", root.timezone, "--now", String(Math.floor(root.now() / 1000))];
        zoneProcess.running = true;
        root.armZoneRefresh();
    }

    function statusText(): string {
        if (!schedule)
            return lastError || (isArabic ? "مواقيت الصلاة غير محملة" : "Prayer times are not loaded");
        const next = nextEvent;
        const nextText = next ? Model.label(next.name, language) + (next.kind === "iqama" ? " " + Model.uiLabel(next.label || "iqama", language) : "") + (isArabic ? " بعد " : " in ") + Model.remaining(next, nowTick, language) : (isArabic ? "لا توجد صلاة قادمة" : "No upcoming prayer");
        return displayLocation + ": " + nextText + " [" + Model.statusLabel(schedule.status, language) + "]";
    }

    function queueNotifications(events: var): void {
        if (!events || events.length === 0)
            return;
        notificationQueue = notificationQueue.concat(events);
        startNotification();
    }

    function startNotification(): void {
        if (notificationProcess.running || notificationQueue.length === 0)
            return;
        const event = notificationQueue[0];
        activeNotification = event;
        const message = Model.notificationText(event, language, timeFormat);
        const sound = event.kind === "istijabah" ? istijabahSound : notificationSound;
        notificationProcess.command = [notificationScript, event.key, message.title, message.body, sound, String(notificationSoundVolume)];
        notificationProcess.running = true;
    }

    function finishNotification(exitCode: int): void {
        if (exitCode === 0) {
            notificationWarning = "";
            notificationRetryAttempt = 0;
            activeNotification = null;
            if (notificationQueue.length > 0)
                notificationQueue = notificationQueue.slice(1);
            Qt.callLater(startNotification);
            return;
        }
        if (notificationRetryAttempt < 2 && activeNotification) {
            notificationRetryAttempt++;
            notificationRetry.restart();
            return;
        }
        notificationWarning = "Prayer notification delivery failed";
        notificationRetryAttempt = 0;
        activeNotification = null;
        if (notificationQueue.length > 0)
            notificationQueue = notificationQueue.slice(1);
        Qt.callLater(startNotification);
    }

    function tick(): void {
        const currentEpoch = root.now();
        const previousEpoch = previousTickEpoch;
        previousTickEpoch = currentEpoch;
        nowTick = new Date(currentEpoch);
        if (notificationsEnabled && schedule)
            queueNotifications(Model.notificationEvents(schedule, previousEpoch, currentEpoch, notifyBeforeMinutes, notificationGraceMinutes, istijabahWindow));
        if (!schedule)
            return;
        const nextRefresh = new Date(schedule.nextRefreshAt || "").getTime();
        if (isFinite(nextRefresh) && currentEpoch >= nextRefresh) {
            root.recompute();
            root.refresh();
        }
    }

    onConfigKeyChanged: configRefresh.restart()
    onTimezoneChanged: {
        root.zone = null;
        root.schedule = null;
        root.lastError = "";
        Qt.callLater(() => root.refresh());
    }
    onZoneChanged: configRefresh.restart()
    onNotificationsEnabledChanged: {
        previousTickEpoch = root.now();
        if (!notificationsEnabled) {
            notificationQueue = [];
            activeNotification = null;
            notificationRetryAttempt = 0;
            notificationWarning = "";
            notificationRetry.stop();
        }
    }
    Component.onCompleted: Qt.callLater(() => root.refresh())

    Process {
        id: zoneProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyZone(text)
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.lastError === "")
                root.lastError = "Timezone data command failed (exit " + exitCode + ")";
            root.armZoneRefresh();
            if (root.zoneRequestedTimezone !== root.timezone)
                Qt.callLater(() => root.refresh());
        }
    }

    Process {
        id: notificationProcess

        onExited: exitCode => root.finishNotification(exitCode)
    }

    Process {
        id: geocodeProcess

        stdout: StdioCollector {
            id: geocodeOutput
            waitForEnd: true
        }
        onExited: exitCode => {
            // Never apply a partial response from a failed or size-limited transfer.
            if (exitCode === 0)
                root.applyLocationResults(geocodeOutput.text);
            else {
                root.locationChoices = [];
                root.locationStatus = Model.uiLabel("searchFailed", root.language);
            }
            if (root.geocodePendingQuery !== root.geocodeActiveQuery)
                Qt.callLater(root.startGeocode);
        }
    }

    Process {
        id: detectProcess

        command: Model.detectLocationCommand()
        stdout: StdioCollector {
            id: detectOutput
            waitForEnd: true
        }
        onExited: exitCode => {
            if (exitCode === 0)
                root.applyDetectedLocation(detectOutput.text);
            else {
                root.detectingLocation = false;
                root.locationStatus = Model.uiLabel("detectFailed", root.language);
            }
        }
    }

    // Typing pause before a city search.
    // haseen:ui-timeout
    Timer {
        id: geocodeDebounce

        interval: 350
        repeat: false
        onTriggered: root.startGeocode()
    }

    // Retry a failed notification delivery (at most twice).
    // haseen:ui-timeout
    Timer {
        id: notificationRetry

        interval: 5000
        repeat: false
        onTriggered: root.startNotification()
    }

    // Settle a burst of setting changes into one recompute.
    // haseen:ui-timeout
    Timer {
        id: configRefresh

        interval: 250
        repeat: false
        onTriggered: root.recompute()
    }

    // Re-read the timezone window at the next local midnight (armZoneRefresh).
    // haseen:ui-timeout
    Timer {
        id: zoneRefresh

        interval: 86400000
        repeat: false
        onTriggered: root.refresh()
    }

    // The countdown and the notification check: the minute display needs no
    // finer step. Runs only while the plugin is enabled (the service exists
    // only then).
    // haseen:sample
    Timer {
        interval: 30000
        running: root.pluginId !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    // User target (upstream's): refresh() and status(). The rest is the
    // debugIpc test hook: move the clock, pick a layout, fire a notification.
    IpcHandler {
        target: "haseen.prayers"

        function refresh(): void {
            root.refresh();
        }

        function status(): string {
            return root.statusText();
        }

        function state(): string {
            if (!root.debugIpc)
                return "";
            return JSON.stringify({
                today: root.todayDay ? root.todayDay.date : null,
                timings: root.todayDay ? root.todayDay.timings : null,
                hijri: root.hijriText,
                next: root.nextEvent,
                bar: Model.barText(root.nextEvent, root.nowTick, root.language, root.barDisplay, root.timeFormat),
                error: root.lastError,
                queue: root.notificationQueue.length,
                warning: root.notificationWarning
            });
        }

        // Shift the clock so `now` reads as epochMs (0 = real time).
        function setNow(epochMs: string): void {
            if (!root.debugIpc)
                return;
            const target = Number(epochMs);
            root.clockOffset = target > 0 ? target - Date.now() : 0;
            root.previousTickEpoch = root.now();
            root.zone = null;
            root.refresh();
            root.tick();
        }

        function set(key: string, json: string): void {
            if (root.debugIpc)
                root.setSetting(key, JSON.parse(json));
        }

        function openSettings(open: bool): void {
            if (root.debugIpc)
                root.displaySettingsOpen = open;
        }

        // Advance the tick from (now - minutes) to now, so the notification
        // window logic runs exactly as it would have over that span.
        function replay(minutes: int): void {
            if (!root.debugIpc)
                return;
            root.previousTickEpoch = root.now() - minutes * 60000;
            root.tick();
        }
    }
}
