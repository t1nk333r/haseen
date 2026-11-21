.pragma library

// haseen.weather pure model: location setting, URLs, wttr.in / Open-Meteo
// normalization, units and the condition icons. No QML types, so
// tests/test-weather.sh runs it under the stock `qml` tool.
//
// Adapted from Omarchy shell/plugins/panels/weather/Model.js and
// bin/omarchy-weather-{icon,status} (MIT, Copyright (c) David Heinemeier
// Hansson). haseen changes: the location comes from settings.location (a
// city or "lat,lon", with settings.locationName labelling coordinates) or a
// GeoClue position instead of Omarchy's weather.json; URL and status-line
// helpers live here so the service, panel and bar widget share them.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// %1..%9 filled from the further arguments: the English stand-in for
// I18n.tr, which the service passes to statusLine for its language.
function fill(text, ...args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => {
        const value = args[Number(digit) - 1];
        return value === undefined || value === null ? whole : String(value);
    });
}

// Days the panel lists (plan 180): five on its first tab, three on its second.
const FORECAST_DAYS = 5;

const COORDS = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/;

function trim(value) {
    return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "");
}

// "lat,lon" -> { latitude, longitude } or null. Out-of-range values are not
// coordinates (they would be a place name wttr.in cannot find either).
function parseCoordinates(text) {
    const m = COORDS.exec(String(text === undefined || text === null ? "" : text));
    if (!m)
        return null;
    const latitude = parseFloat(m[1]);
    const longitude = parseFloat(m[2]);
    if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180)
        return null;
    return { latitude: latitude, longitude: longitude };
}

// settings.location (+ settings.locationName) -> the state Omarchy's panel
// keeps for its weather.json: { name, latitude, longitude }. Empty = unset.
function parseLocationSetting(location, locationName) {
    const coords = parseCoordinates(location);
    if (coords)
        return { name: trim(locationName), latitude: coords.latitude, longitude: coords.longitude };
    return { name: trim(location), latitude: null, longitude: null };
}

function isLocationSet(state) {
    return !!state && (trim(state.name) !== "" || hasCoordinates(state));
}

function hasCoordinates(state) {
    return !!state && !isNaN(parseFloat(String(state.latitude))) && !isNaN(parseFloat(String(state.longitude)));
}

// The location the forecast is for: the manual setting when there is one,
// else the GeoClue position (coordinates, no name), else unset (wttr.in's
// IP lookup, Omarchy's auto-detect).
function effectiveLocation(manual, detected) {
    if (isLocationSet(manual))
        return manual;
    if (hasCoordinates(detected))
        return { name: "", latitude: detected.latitude, longitude: detected.longitude };
    return { name: "", latitude: null, longitude: null };
}

// `haseen-weather-location --detect` prints "lat,lon"; anything else (an
// error text, nothing) is no position.
function parseDetected(raw) {
    return parseCoordinates(trim(raw).split("\n")[0]);
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback, empty for IP
// auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
    const lat = parseFloat(String(latitude));
    const lon = parseFloat(String(longitude));
    if (!isNaN(lat) && !isNaN(lon))
        return lat + "," + lon;
    const name = trim(location);
    return name === "" ? "" : encodeURIComponent(name);
}

function wttrUrl(query) {
    return "https://wttr.in/" + String(query || "") + "?format=j1";
}

function openMeteoUrl(latitude, longitude) {
    return "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + encodeURIComponent(String(latitude))
        + "&longitude=" + encodeURIComponent(String(longitude))
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
        + "&forecast_days=" + (FORECAST_DAYS + 1)
        + "&timezone=auto";
}

function geocodeUrl(query) {
    return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(trim(query)) + "&count=5&language=en&format=json";
}

// Open-Meteo geocoding response -> suggestion rows for the location picker.
function parseGeocodingResults(raw) {
    try {
        const data = JSON.parse(String(raw || "{}"));
        const results = data.results;
        if (!results || !results.length)
            return [];
        const out = [];
        for (let i = 0; i < results.length; i++) {
            const r = results[i];
            if (!r || !r.name || r.latitude === undefined || r.longitude === undefined)
                continue;
            out.push({
                name: String(r.name),
                description: [r.admin1, r.country].filter(part => !!part).join(", "),
                latitude: r.latitude,
                longitude: r.longitude
            });
        }
        return out;
    } catch (e) {
        return [];
    }
}

function locationCommit(text, suggestions, selectedIndex) {
    const name = trim(text);
    if (name === "")
        return { name: "", latitude: null, longitude: null };
    const choices = suggestions || [];
    const index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1));
    const suggestion = choices[index];
    if (suggestion)
        return suggestion;
    return { name: name, latitude: null, longitude: null };
}

// The settings a committed location is stored as (shell.json
// plugins."haseen.weather".settings): coordinates win, the name labels them.
function locationSettings(name, latitude, longitude) {
    const label = trim(name);
    const lat = parseFloat(String(latitude));
    const lon = parseFloat(String(longitude));
    if (label !== "" && !isNaN(lat) && !isNaN(lon))
        return { location: lat + "," + lon, locationName: label };
    return { location: label, locationName: "" };
}

function isFutureForecastDate(dateString, todayString) {
    if (!dateString)
        return false;
    return String(dateString).slice(0, 10) > String(todayString || "");
}

function roundedTemp(value) {
    if (value === undefined || value === null || value === "")
        return "";
    const n = parseFloat(String(value));
    return isNaN(n) ? "" : String(Math.round(n));
}

function celsiusToFahrenheit(value) {
    if (value === undefined || value === null || value === "")
        return "";
    const n = parseFloat(String(value));
    return isNaN(n) ? "" : (n * 9 / 5) + 32;
}

function formatTemp(value, useImperial) {
    if (value === undefined || value === null || value === "")
        return "";
    return value + "°" + (useImperial ? "F" : "C");
}

function normalizedUnit(value) {
    return trim(value).toLowerCase();
}

function localeUsesImperial(localeName) {
    const name = String(localeName || "").replace(".", "_");
    return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name);
}

function countryUsesImperial(countryName) {
    const country = trim(countryName).replace(/[._-]+/g, " ").toLowerCase();
    if (!country)
        return null;
    if (country === "us" || country === "usa" || country === "united states" || country === "united states of america")
        return true;
    if (country === "liberia" || country === "myanmar" || country === "burma")
        return true;
    return false;
}

// settings.units: "metric", "imperial", or empty = the forecast's country,
// else the locale (Omarchy's rule).
function shouldUseImperial(unitOverride, localeName, countryName) {
    const unit = normalizedUnit(unitOverride);
    if (unit === "imperial")
        return true;
    if (unit === "metric")
        return false;
    const countryPreference = countryUsesImperial(countryName);
    if (countryPreference !== null)
        return countryPreference;
    return localeUsesImperial(localeName);
}

function dayName(dateString, formatter) {
    if (!dateString)
        return "";
    const d = new Date(dateString + "T12:00:00");
    if (isNaN(d.getTime()))
        return "";
    if (formatter)
        return formatter(d);
    return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()];
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
    const daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null;
    if (!daily || !daily.time)
        return [];
    const result = [];
    for (let i = 0; i < daily.time.length && result.length < FORECAST_DAYS; ++i) {
        const date = daily.time[i];
        if (!isFutureForecastDate(date, todayString))
            continue;
        const maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : "";
        const minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : "";
        result.push({
            date: date,
            maxtempC: roundedTemp(maxC),
            mintempC: roundedTemp(minC),
            maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
            mintempF: roundedTemp(celsiusToFahrenheit(minC)),
            openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
        });
    }
    return result;
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so either source works. Open-Meteo reports metric.
function openMeteoCurrentCondition(dailyForecastReport) {
    const current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null;
    if (!current || current.temperature_2m === undefined || current.temperature_2m === null)
        return null;
    return {
        temp_C: roundedTemp(current.temperature_2m),
        temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
        FeelsLikeC: roundedTemp(current.apparent_temperature),
        FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
        windspeedKmph: roundedTemp(current.wind_speed_10m),
        windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
        humidity: roundedTemp(current.relative_humidity_2m),
        openMeteoWeatherCode: current.weather_code,
        isDay: current.is_day
    };
}

function currentIcon(current, fallback) {
    if (!current)
        return fallback || "";
    if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
        return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0);
    if (current.weatherCode !== undefined && current.weatherCode !== null)
        return iconForCode(current.weatherCode, wttrIsNight(current));
    return fallback || "";
}

// wttr.in has no day/night flag, but the World Weather Online symbol it links
// for the current condition names the night ones
// (wsymbol_0008_clear_sky_night.png); without a link, day.
function wttrIsNight(current) {
    const urls = current && current.weatherIconUrl;
    const url = urls && urls[0] ? String(urls[0].value || "") : "";
    return /_night\.png$/i.test(url);
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
    return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr";
}

function wttrNextForecastDays(report, todayString) {
    const days = report && report.weather ? report.weather : [];
    const result = [];
    for (let i = 0; i < days.length && result.length < FORECAST_DAYS; ++i) {
        if (isFutureForecastDate(days[i].date, todayString))
            result.push(days[i]);
    }
    return result;
}

function buildForecastDays(report, dailyForecastReport, todayString) {
    const days = openMeteoForecastDays(dailyForecastReport, todayString);
    return days.length > 0 ? days : wttrNextForecastDays(report, todayString);
}

function bareTempForDay(day, kind, useImperial) {
    if (!day)
        return "";
    const v = useImperial ? (kind === "max" ? day.maxtempF : day.mintempF) : (kind === "max" ? day.maxtempC : day.mintempC);
    if (v === undefined || v === null || v === "")
        return "";
    return v + "°";
}

function dayIcon(day) {
    if (!day)
        return "";
    if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
        return iconForOpenMeteoCode(day.openMeteoWeatherCode);
    if (!day.hourly || day.hourly.length === 0)
        return "";
    let best = day.hourly[0];
    let bestDist = 9999;
    for (let i = 0; i < day.hourly.length; ++i) {
        const t = parseInt(String(day.hourly[i].time || "0"), 10);
        const dist = Math.abs(t - 1200);
        if (dist < bestDist) {
            bestDist = dist;
            best = day.hourly[i];
        }
    }
    return iconForCode(best.weatherCode, false);
}

// Open-Meteo (WMO) code -> the wttr.in code that draws and names it.
function wttrCodeForOpenMeteo(code) {
    const c = parseInt(String(code || "0"), 10);
    if (c === 0)
        return 113;
    if (c === 1 || c === 2)
        return 116;
    if (c === 3)
        return 119;
    if (c === 45 || c === 48)
        return 143;
    if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61)
        return 266;
    if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82)
        return 308;
    if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86)
        return 338;
    if (c === 95 || c === 96 || c === 99)
        return 389;
    return 119;
}

function iconForOpenMeteoCode(code, night) {
    return iconForCode(wttrCodeForOpenMeteo(code), night);
}

// wttr.in code -> the condition in words (English, marked for the catalogs;
// the panel translates it). The icons' groups, with rain split into light
// and heavier; "" for an unknown code.
function conditionForCode(code, night) {
    const c = parseInt(String(code || "0"), 10);
    switch (c) {
    case 113:
        return night ? N_("Clear") : N_("Sunny");
    case 116:
        return N_("Partly cloudy");
    case 119:
        return N_("Cloudy");
    case 122:
        return N_("Overcast");
    case 143: case 248: case 260:
        return N_("Fog");
    case 176: case 263: case 266: case 293: case 296: case 353:
        return N_("Light rain");
    case 299: case 302: case 305: case 308: case 356: case 359:
        return N_("Rain");
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377:
        return N_("Sleet");
    case 179: case 227: case 230: case 323: case 326: case 329: case 332:
    case 335: case 338: case 368: case 371:
        return N_("Snow");
    case 200: case 386: case 389: case 392: case 395:
        return N_("Thunderstorm");
    default:
        return "";
    }
}

// The current conditions in words, from either source's shape.
function currentCondition(current) {
    if (!current)
        return "";
    if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
        return conditionForCode(wttrCodeForOpenMeteo(current.openMeteoWeatherCode), Number(current.isDay) === 0);
    if (current.weatherCode !== undefined && current.weatherCode !== null)
        return conditionForCode(current.weatherCode, wttrIsNight(current));
    return "";
}

function pad(n, width) {
    let s = String(n);
    while (s.length < width)
        s = "0" + s;
    return s;
}

// The next `count` three-hourly forecasts after `now` (a Date) from
// wttr.in's report: { hour: "15", tempC, tempF, icon }, night icons where
// wttr.in's symbol says so. wttr.in gives each day's date and hours in the
// forecast place's time; they are compared with this machine's clock.
function hourlySlots(report, now, count) {
    const days = report && report.weather ? report.weather : [];
    const nowKey = now.getFullYear() + "-" + pad(now.getMonth() + 1, 2) + "-" + pad(now.getDate(), 2) + " " + pad(now.getHours() * 100 + now.getMinutes(), 4);
    const result = [];
    for (let d = 0; d < days.length && result.length < count; ++d) {
        const hourly = days[d].hourly || [];
        for (let i = 0; i < hourly.length && result.length < count; ++i) {
            const time = parseInt(String(hourly[i].time || "0"), 10);
            if (isNaN(time) || String(days[d].date) + " " + pad(time, 4) <= nowKey)
                continue;
            result.push({
                hour: pad(Math.floor(time / 100), 2),
                tempC: roundedTemp(hourly[i].tempC),
                tempF: roundedTemp(hourly[i].tempF),
                icon: iconForCode(hourly[i].weatherCode, wttrIsNight(hourly[i]))
            });
        }
    }
    return result;
}

// Today's high and low: Open-Meteo's when its first day is today, else
// wttr.in's. { maxC, minC, maxF, minF }, "" where unknown.
function todayRange(report, dailyForecastReport, todayString) {
    const daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null;
    if (daily && daily.time && String(daily.time[0]).slice(0, 10) === String(todayString)) {
        const maxC = daily.temperature_2m_max ? daily.temperature_2m_max[0] : "";
        const minC = daily.temperature_2m_min ? daily.temperature_2m_min[0] : "";
        return { maxC: roundedTemp(maxC), minC: roundedTemp(minC), maxF: roundedTemp(celsiusToFahrenheit(maxC)), minF: roundedTemp(celsiusToFahrenheit(minC)) };
    }
    const days = report && report.weather ? report.weather : [];
    for (let i = 0; i < days.length; ++i) {
        if (String(days[i].date) === String(todayString))
            return { maxC: roundedTemp(days[i].maxtempC), minC: roundedTemp(days[i].mintempC), maxF: roundedTemp(days[i].maxtempF), minF: roundedTemp(days[i].mintempF) };
    }
    return { maxC: "", minC: "", maxF: "", minF: "" };
}

// The lowest low and highest high of the listed days, the shared scale of
// their range bars; null without two distinct numbers.
function daysScale(days, useImperial) {
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < (days || []).length; ++i) {
        const min = parseFloat(String(useImperial ? days[i].mintempF : days[i].mintempC));
        const max = parseFloat(String(useImperial ? days[i].maxtempF : days[i].maxtempC));
        if (!isNaN(min))
            lo = Math.min(lo, min);
        if (!isNaN(max))
            hi = Math.max(hi, max);
    }
    return isFinite(lo) && isFinite(hi) && hi > lo ? { lo: lo, hi: hi } : null;
}

// Where a day's range bar starts and how wide it is, as fractions of the
// track; a day without numbers gets none.
function rangeBar(day, scale, useImperial) {
    if (!day || !scale)
        return { start: 0, width: 0 };
    const min = parseFloat(String(useImperial ? day.mintempF : day.mintempC));
    const max = parseFloat(String(useImperial ? day.maxtempF : day.maxtempC));
    if (isNaN(min) || isNaN(max))
        return { start: 0, width: 0 };
    const span = scale.hi - scale.lo;
    return { start: (min - scale.lo) / span, width: Math.max(0, max - min) / span };
}

// The temperature curve through `values`, one point per slot centre across
// `width`, between y = top (warmest) and top + height (coldest); flat values
// sit in the middle. A monotone cubic through the points (Fritsch and
// Carlson, 1980), as cubic Béziers: one tangent per point, so the line
// turns smoothly through every point, and each segment stays between its
// two points, so it never overshoots the band (plan 181; Catmull-Rom with
// clamped control points left corners at the peaks).
// { points: [[x, y]], line: SVG path, area: the line closed down to
// `bottom` }; empty for fewer than two values or any value that is not a
// number, so a gap never shifts the points against their slots.
function curve(values, width, top, height, bottom) {
    const nums = (values || []).map(v => parseFloat(String(v)));
    if (nums.length < 2 || nums.some(v => isNaN(v)))
        return { points: [], line: "", area: "" };
    const lo = Math.min(...nums), hi = Math.max(...nums);
    const points = nums.map((v, i) => [
        Math.round((i + 0.5) * width / nums.length * 10) / 10,
        Math.round((hi === lo ? top + height / 2 : top + (1 - (v - lo) / (hi - lo)) * height) * 10) / 10
    ]);
    const n = points.length;
    // Slots too narrow to tell apart (a panel not laid out yet): no curve,
    // never a path with a division by zero in it.
    for (let i = 0; i < n - 1; ++i) {
        if (!(points[i + 1][0] > points[i][0]))
            return { points: [], line: "", area: "" };
    }
    // Secant slopes, then each point's tangent: the mean of its two secants,
    // zero at a peak, a trough or a level stretch, limited so no segment
    // overshoots.
    const d = [];
    for (let i = 0; i < n - 1; ++i)
        d.push((points[i + 1][1] - points[i][1]) / (points[i + 1][0] - points[i][0]));
    const m = points.map((p, i) => i === 0 ? d[0] : i === n - 1 ? d[n - 2] : (d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2));
    for (let i = 0; i < n - 1; ++i) {
        // A level segment's ends already have tangent 0 (the sign rule).
        if (d[i] === 0)
            continue;
        const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
        if (s > 9) {
            const t = 3 / Math.sqrt(s);
            m[i] = t * a * d[i];
            m[i + 1] = t * b * d[i];
        }
    }
    // Control points at a third of each segment along the tangents; finer
    // rounding than the points, so the tangents stay continuous.
    const r = v => Math.round(v * 100) / 100;
    let line = "M " + points[0][0] + " " + points[0][1];
    for (let i = 0; i < n - 1; ++i) {
        const dx = (points[i + 1][0] - points[i][0]) / 3;
        line += " C " + r(points[i][0] + dx) + " " + r(points[i][1] + m[i] * dx)
            + " " + r(points[i + 1][0] - dx) + " " + r(points[i + 1][1] - m[i + 1] * dx)
            + " " + points[i + 1][0] + " " + points[i + 1][1];
    }
    const last = points[points.length - 1];
    const area = line + " L " + last[0] + " " + bottom + " L " + points[0][0] + " " + bottom + " Z";
    return { points: points, line: line, area: area };
}

// wttr.in (WorldWeatherOnline) code -> Nerd Font glyph, as
// omarchy-weather-icon maps it.
function iconForCode(code, night) {
    const c = parseInt(String(code || "0"), 10);
    switch (c) {
    case 113:
        return night ? "\ue32b" : "\ue30d";
    case 116:
        return night ? "\ue32e" : "\ue302";
    case 119: case 122:
        return "\ue33d";
    case 143: case 248: case 260:
        return night ? "\ue346" : "\ue313";
    case 176: case 263: case 353:
        return night ? "\ue333" : "\ue308";
    case 179: case 227: case 230: case 323: case 326: case 368:
        return night ? "\ue327" : "\ue30a";
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377:
        return "\ue3ad";
    case 200: case 386: case 389: case 392: case 395:
        return "\ue31d";
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359:
        return "\ue318";
    case 329: case 332: case 335: case 338: case 371:
        return "\ue31a";
    default:
        return "\ue33d";
    }
}

// The right-click notification, worded as omarchy-weather-status:
// "Place  ·  Temp 21°C  ·  Wind 9 km/h"; "Weather unavailable" without data.
// tr: I18n.tr for the interface's language; English without it.
function statusLine(place, temp, wind, tr) {
    const t = typeof tr === "function" ? tr : fill;
    if (trim(temp) === "")
        return t(N_("Weather unavailable"));
    const name = trim(place);
    const parts = name === "" ? [] : [name.charAt(0).toUpperCase() + name.slice(1)];
    parts.push(t(N_("Temp %1"), temp));
    if (trim(wind) !== "")
        parts.push(t(N_("Wind %1"), wind));
    return parts.join("  ·  ");
}
