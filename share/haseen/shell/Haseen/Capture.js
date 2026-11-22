.pragma library

// The capture tools' layer surfaces (plan 184), by the namespace each one
// gives its layer: Omasnap's overlay (`hyprctl layers` on luna, 2026-11-22),
// slurp's `selection`, hyprpicker's freeze and wayfreeze. Omasnap's preview
// after a capture is a window (`omasnap-pin`), not a layer, so it does not
// count: a capture ends when its overlay goes.
var namespaces = ["omasnap", "selection", "hyprpicker", "wayfreeze"];

function isCaptureLayer(ns) {
    return namespaces.indexOf(String(ns)) >= 0;
}

// The number of capture layers open after one of Hyprland's raw events. A
// tool opens one layer per monitor; a close the shell saw no open for (it
// started mid-capture) never takes the count below zero.
function nextCount(count, name, data) {
    if (!isCaptureLayer(data))
        return count;
    if (name === "openlayer")
        return count + 1;
    if (name === "closelayer")
        return Math.max(0, count - 1);
    return count;
}
