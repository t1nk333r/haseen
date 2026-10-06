.pragma library

// haseen.gestures: the action catalogue and the axis helpers, free of QML.
//
// Adapted from omagesture's Model.js (github.com/heroesofcode/omagesture,
// MIT, Copyright (c) 2026 Pedro Henrique). Upstream repeats its defaults here
// because its host hands a new widget an empty settings object; haseen's host
// merges the manifest defaults into `settings` (architecture 5.2), and
// `haseen gestures apply` reads the same manifest, so they live there only.
//
// The values are the tokens `haseen gestures apply` accepts (lib/gestures.sh
// GESTURES_JQ_VALID); the labels are what a person reads.

var ACTIONS = [
    { value: "none", label: "Nothing" },
    { value: "workspace", label: "Switch workspace" },
    { value: "special", label: "Scratchpad" },
    { value: "fullscreen", label: "Fullscreen" },
    { value: "maximize", label: "Maximize" },
    { value: "float", label: "Float / tile" },
    { value: "move_window", label: "Move window" },
    { value: "resize_window", label: "Resize window" },
    { value: "close_window", label: "Close window" },
    { value: "zoom", label: "Zoom screen" },
    // Upstream's "Omarchy menu"; haseen's command menu is the same role.
    { value: "menu", label: "Command menu" }
];

var CLICK_METHODS = [
    { value: "clickfinger", label: "Two fingers = right click" },
    { value: "buttonareas", label: "Bottom-right = right click" }
];

var DRAG_MODES = [
    { value: "off", label: "Off" },
    { value: "threefinger", label: "Three fingers" },
    { value: "fourfinger", label: "Four fingers" }
];

var SWIPE_RANGES = [
    { value: "numbered", label: "Every workspace" },
    { value: "existing", label: "Only open ones" }
];

// Upstream's "Paste selection" ran `wl-paste --primary` from a bind, which
// prints the selection to nowhere; it is not offered.
var MIDDLE_BUTTONS = [
    { value: "none", label: "Nothing" },
    { value: "move", label: "Hold & drag to move" },
    { value: "resize", label: "Hold & drag to resize" },
    { value: "screenshot", label: "Screenshot region" }
];

// An axis is the pair of directions the panel edits as one control: the
// combined Hyprland direction shadows its halves and is the only form that
// follows the fingers continuously.
var AXES = {
    horizontal: ["Left", "Right"],
    vertical: ["Up", "Down"],
    pinch: ["PinchIn", "PinchOut"]
};

function key(fingers, direction) {
    return "g" + fingers + direction;
}

// The action on an axis, or "" when its two halves differ (set per direction
// in shell.json); the control then says so instead of showing one half.
function axisValue(settings, fingers, axis) {
    var a = settings[key(fingers, AXES[axis][0])];
    var b = settings[key(fingers, AXES[axis][1])];
    return a === b ? String(a) : "";
}

function axisPatch(fingers, axis, value) {
    var patch = {};
    patch[key(fingers, AXES[axis][0])] = value;
    patch[key(fingers, AXES[axis][1])] = value;
    return patch;
}

function mapped(settings, fingers) {
    for (var axis in AXES)
        for (var i = 0; i < 2; i++) {
            var v = settings[key(fingers, AXES[axis][i])];
            if (v !== undefined && v !== "none")
                return true;
        }
    return false;
}

// A multi-finger drag and a swipe of the same finger count cannot coexist;
// the renderer drops the drag, and the panel says why.
function dragShadowed(settings) {
    if (settings.enabled === false)
        return false;
    if (settings.drag === "threefinger")
        return mapped(settings, 3);
    if (settings.drag === "fourfinger")
        return mapped(settings, 4);
    return false;
}

function workspaceSwipeMapped(settings) {
    if (settings.enabled === false)
        return false;
    for (var f = 2; f <= 4; f++)
        for (var axis in AXES)
            for (var i = 0; i < 2; i++)
                if (settings[key(f, AXES[axis][i])] === "workspace")
                    return true;
    return false;
}

function labelFor(options, value) {
    for (var i = 0; i < options.length; i++)
        if (options[i].value === value)
            return options[i].label;
    return "";
}

// One line for the panel header: what the swipes do, or that they are off.
function summary(settings) {
    if (settings.enabled === false)
        return "Gestures off";
    var parts = [];
    for (var f = 3; f <= 4; f++) {
        var h = axisValue(settings, f, "horizontal");
        if (h !== "" && h !== "none")
            parts.push(f + " fingers: " + labelFor(ACTIONS, h).toLowerCase());
    }
    return parts.length > 0 ? parts.join(" · ") : "No swipes mapped";
}

function applyCommand(cli, patch) {
    return [cli, "gestures", "apply", "--set", JSON.stringify(patch)];
}
