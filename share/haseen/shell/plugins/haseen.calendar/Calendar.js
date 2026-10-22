.pragma library

// Pure month-grid math for haseen.calendar (no Qt types; tests run it
// headless). Months are 0-based like JS Date; weekdays 0 = Sunday, which is
// also Qt's Locale.Sunday, so Qt.locale().firstDayOfWeek passes straight in.
//
// monthGrid's UTC walk is adapted from Omarchy
// shell/plugins/panels/clock/Model.js (MIT, Copyright (c) David Heinemeier
// Hansson).

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

// settings.weekStart ("locale", a day name or its first three letters, or
// 0-6) -> 0-6; the locale's first day for "locale" or nonsense.
function weekStart(value, localeFirst) {
    const fallback = ((Number(localeFirst) % 7) + 7) % 7 || 0;
    if (typeof value === "number" && isFinite(value))
        return ((Math.round(value) % 7) + 7) % 7;
    const s = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    for (let i = 0; i < 7; i++)
        if (s !== "" && (WEEKDAYS[i] === s || WEEKDAYS[i].slice(0, 3) === s))
            return i;
    return fallback;
}

// ISO 8601 week number of a date.
function isoWeek(year, month, day) {
    const d = new Date(Date.UTC(year, month, day));
    const dow = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - dow);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
}

// (year, month + delta) normalised -> { year, month }.
function shiftMonth(year, month, delta) {
    const total = year * 12 + month + Math.round(Number(delta) || 0);
    return {
        year: Math.floor(total / 12),
        month: ((total % 12) + 12) % 12
    };
}

// Six weeks of cells starting on `first` (0-6):
// [{ year, month, day, inMonth, weekday }] (42 entries).
//
// Built in UTC, where every day is 24 hours long. A local midnight has to be
// resolved by the engine in zones that start DST at 00:00 (Chile every
// September, Cuba every March), and Qt's V4 resolves the missing midnight
// backwards onto the day before: September 2026 in Santiago drew 5 twice and
// no 6. Samoa skipped 30 December 2011 outright. A grid of civil dates never
// needed a wall clock (Omarchy d74d6ea24, pull request 10476; plan 103).
function monthGrid(year, month, first) {
    const start = new Date(Date.UTC(year, month, 1));
    const lead = (start.getUTCDay() - first + 7) % 7;
    const cells = [];
    for (let i = 0; i < 42; i++) {
        const d = new Date(Date.UTC(year, month, 1 - lead + i));
        cells.push({
            year: d.getUTCFullYear(),
            month: d.getUTCMonth(),
            day: d.getUTCDate(),
            inMonth: d.getUTCMonth() === month,
            weekday: d.getUTCDay()
        });
    }
    return cells;
}

// ISO week number for each of the six rows: the week of the row's Monday
// (every 7-day row holds exactly one Monday, whatever the first weekday).
function rowWeeks(cells) {
    const out = [];
    for (let r = 0; r < 6; r++) {
        const row = cells.slice(r * 7, r * 7 + 7);
        const monday = row.find(c => c.weekday === 1) || row[0];
        out.push(isoWeek(monday.year, monday.month, monday.day));
    }
    return out;
}

// Weekday indices in display order, e.g. first = 1 -> [1,2,3,4,5,6,0].
function weekdayOrder(first) {
    const out = [];
    for (let i = 0; i < 7; i++)
        out.push((first + i) % 7);
    return out;
}

function sameDay(cell, date) {
    return cell.year === date.getFullYear() && cell.month === date.getMonth() && cell.day === date.getDate();
}
