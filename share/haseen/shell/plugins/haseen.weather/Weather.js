.pragma library

// wttr.in `?format=j1` -> the shape the weather widget and panel show.
// Pure functions, no QML types, so tests/test-widgets-b.sh runs them on a
// fixture with the stock `qml` tool.
//
// The weather-code -> Nerd Font glyph table is adapted from Omarchy's
// bin/omarchy-weather-icon (MIT, Copyright (c) David Heinemeier Hansson).

// Codes wttr.in (WorldWeatherOnline) reports, grouped as Omarchy does.
// [day glyph, night glyph]
const GROUPS = [
    { codes: [113], glyph: ["\u{e30d}", "\u{e32b}"] },                        // clear
    { codes: [116], glyph: ["\u{e302}", "\u{e32e}"] },                        // partly cloudy
    { codes: [119, 122], glyph: ["\u{e33d}", "\u{e33d}"] },                   // cloudy, overcast
    { codes: [143, 248, 260], glyph: ["\u{e313}", "\u{e313}"] },              // mist, fog
    { codes: [176, 263, 353], glyph: ["\u{e308}", "\u{e333}"] },              // patchy rain, drizzle
    { codes: [179, 227, 230, 323, 326, 368], glyph: ["\u{e30a}", "\u{e327}"] }, // patchy / light snow
    { codes: [182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377], glyph: ["\u{e3ad}", "\u{e3ad}"] }, // sleet, freezing rain
    { codes: [200, 386, 389, 392, 395], glyph: ["\u{e31d}", "\u{e31d}"] },    // thunder
    { codes: [266, 293, 296, 299, 302, 305, 308, 356, 359], glyph: ["\u{e318}", "\u{e318}"] }, // rain
    { codes: [329, 332, 335, 338, 371], glyph: ["\u{e31a}", "\u{e31a}"] }     // snow
];
const FALLBACK = "\u{e33d}";

function glyph(code, night) {
    const n = parseInt(code, 10);
    for (const g of GROUPS)
        if (g.codes.indexOf(n) >= 0)
            return g.glyph[night ? 1 : 0];
    return FALLBACK;
}

// "07:13 AM" -> minutes after midnight, or -1.
function clockMinutes(text) {
    const m = /^\s*(\d{1,2}):(\d{2})\s*([AP]M)\s*$/i.exec(String(text || ""));
    if (!m)
        return -1;
    let h = parseInt(m[1], 10) % 12;
    if (m[3].toUpperCase() === "PM")
        h += 12;
    return h * 60 + parseInt(m[2], 10);
}

function number(v) {
    const n = parseFloat(v);
    return isFinite(n) ? Math.round(n) : null;
}

function text0(list) {
    return Array.isArray(list) && list[0] && typeof list[0].value === "string" ? list[0].value.trim() : "";
}

// The midday hour stands for the day; wttr.in reports 3-hourly slots.
function dayCode(day) {
    const hours = Array.isArray(day.hourly) ? day.hourly : [];
    const noon = hours.find(h => String(h.time) === "1200") || hours[Math.floor(hours.length / 2)] || {};
    return { code: noon.weatherCode, desc: text0(noon.weatherDesc), rain: number(noon.chanceofrain) };
}

// parse(raw, imperial, now) -> { ok: true, location, current, days } or
// { ok: false, error }. `now` is a Date (local time) used to pick day or
// night glyphs against the first day's sunrise and sunset.
function parse(raw, imperial, now) {
    let data;
    try {
        data = typeof raw === "string" ? JSON.parse(raw) : raw;
    } catch (e) {
        return { ok: false, error: "not JSON" };
    }
    if (!data || !Array.isArray(data.current_condition) || !data.current_condition[0])
        return { ok: false, error: "no current_condition" };
    const c = data.current_condition[0];
    const temp = number(imperial ? c.temp_F : c.temp_C);
    if (temp === null)
        return { ok: false, error: "no temperature" };
    const unit = imperial ? "°F" : "°C";
    const days = Array.isArray(data.weather) ? data.weather : [];

    let night = false;
    const astro = days[0] && Array.isArray(days[0].astronomy) ? days[0].astronomy[0] : null;
    if (astro && now) {
        const rise = clockMinutes(astro.sunrise);
        const set = clockMinutes(astro.sunset);
        const mins = now.getHours() * 60 + now.getMinutes();
        if (rise >= 0 && set >= 0)
            night = mins < rise || mins >= set;
    }

    const area = Array.isArray(data.nearest_area) ? data.nearest_area[0] : null;
    return {
        ok: true,
        unit: unit,
        location: area ? [text0(area.areaName), text0(area.country)].filter(s => s !== "").join(", ") : "",
        current: {
            temp: temp,
            feels: number(imperial ? c.FeelsLikeF : c.FeelsLikeC),
            desc: text0(c.weatherDesc),
            code: parseInt(c.weatherCode, 10),
            glyph: glyph(c.weatherCode, night),
            humidity: number(c.humidity),
            wind: number(imperial ? c.windspeedMiles : c.windspeedKmph),
            windUnit: imperial ? "mph" : "km/h",
            night: night
        },
        days: days.slice(0, 3).map(d => {
            const k = dayCode(d);
            return {
                date: String(d.date || ""),
                max: number(imperial ? d.maxtempF : d.maxtempC),
                min: number(imperial ? d.mintempF : d.mintempC),
                code: parseInt(k.code, 10),
                desc: k.desc,
                rain: k.rain,
                glyph: glyph(k.code, false)
            };
        })
    };
}

// wttr.in URL for a location setting; empty = wttr.in's IP lookup.
function url(location) {
    const loc = String(location || "").trim();
    return "https://wttr.in/" + (loc === "" ? "" : encodeURIComponent(loc)) + "?format=j1";
}
