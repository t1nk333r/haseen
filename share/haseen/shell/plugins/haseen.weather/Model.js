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
        + "&forecast_days=4"
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
    for (let i = 0; i < daily.time.length && result.length < 3; ++i) {
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
        return iconForCode(current.weatherCode, false);
    return fallback || "";
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
    return resolvedIcon || currentIcon(current, "");
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
    return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr";
}

function wttrNextForecastDays(report, todayString) {
    const days = report && report.weather ? report.weather : [];
    const result = [];
    for (let i = 0; i < days.length && result.length < 3; ++i) {
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

function iconForOpenMeteoCode(code, night) {
    const c = parseInt(String(code || "0"), 10);
    if (c === 0)
        return iconForCode(113, night);
    if (c === 1 || c === 2)
        return iconForCode(116, night);
    if (c === 3)
        return iconForCode(119, night);
    if (c === 45 || c === 48)
        return iconForCode(143, night);
    if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61)
        return iconForCode(266, night);
    if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82)
        return iconForCode(308, night);
    if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86)
        return iconForCode(338, night);
    if (c === 95 || c === 96 || c === 99)
        return iconForCode(389, night);
    return iconForCode(119, night);
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
function statusLine(place, temp, wind) {
    if (trim(temp) === "")
        return "Weather unavailable";
    const name = trim(place);
    const head = name === "" ? "" : name.charAt(0).toUpperCase() + name.slice(1) + "  ·  ";
    return head + "Temp " + temp + (trim(wind) === "" ? "" : "  ·  Wind " + wind);
}
