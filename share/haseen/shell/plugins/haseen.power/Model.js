// haseen.power (plan 095): the bar glyph of the owner's t1nk33r.power, a fork
// of Omarchy's power panel (Model.js, MIT, Copyright (c) David Heinemeier
// Hansson). Devices are UPowerDevice-shaped objects and states are
// UPowerDeviceState numbers (Quickshell 0.3), so tests/test-power.sh runs this
// under the real Qt JS engine.

const CHARGING = 1, DISCHARGING = 2, FULLY_CHARGED = 4, PENDING_CHARGE = 5;

const LEVEL_GLYPHS = ["\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"];
const CHARGING_GLYPHS = ["\u{F089C}", "\u{F0086}", "\u{F0087}", "\u{F0088}", "\u{F089D}", "\u{F0089}", "\u{F089E}", "\u{F008A}", "\u{F008B}", "\u{F0085}"];
const FULL_GLYPH = "\u{F0085}";

function fraction(device) {
    return device && device.isPresent ? Math.max(0, Math.min(1, Number(device.percentage) || 0)) : 0;
}

// The charge limit holds a plugged-in battery: UPower reports it pending, or
// full below 99 %, or charging at a trickle (at most 0.2 W, or eight hours or
// more to full). This is the fork's own rule and needs no root read, so the
// bar knows without `haseen battery status`; the panel asks that for the
// window itself.
function chargeHeld(device, onBattery) {
    if (!device || !device.isPresent || onBattery)
        return false;
    const f = fraction(device);
    if (device.state === DISCHARGING)
        return false;
    if (device.state === PENDING_CHARGE)
        return true;
    if (device.state === FULLY_CHARGED)
        return f < 0.99;
    if (device.state !== CHARGING || f >= 0.99)
        return false;
    return (Number(device.changeRate) || 0) <= 0.2 || (Number(device.timeToFull) || 0) >= 8 * 60 * 60;
}

// A level glyph in tenths; the charging set while current flows in, the
// plain one while the limit holds the battery, a full one when UPower says so.
function glyph(device, onBattery) {
    if (!device || !device.isPresent)
        return "";
    const i = Math.max(0, Math.min(9, Math.floor(fraction(device) * 10)));
    if (chargeHeld(device, onBattery) || onBattery)
        return LEVEL_GLYPHS[i];
    if (device.state === FULLY_CHARGED)
        return FULL_GLYPH;
    return CHARGING_GLYPHS[i];
}

// The fork showed the percentage by default, and a shell.json written as the
// string "false" still meant off: only an explicit false hides it.
function showPercentage(value) {
    return value !== false && String(value).toLowerCase() !== "false";
}
