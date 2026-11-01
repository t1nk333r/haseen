// haseen.capture: the toolbar's pure logic (plan 150), shared by Service.qml
// and Panel.qml and run headless by tests/test-capture-toolbar.sh. What
// to capture is the toolbar's state, { mode, target, delay, desktop, mic,
// format, edit }; this file turns it into the haseen command that does the
// work (haseen capture screenshot, screenrecord or audiorecord), lays out the
// toolbar's rows for the keyboard and controller cursor, and maps a
// controller button to an action. Labels are English, marked N_() and
// translated where the panel shows them (architecture 5.8). Glyphs are Nerd
// Font Material Design codepoints (nf-md-*), as Compat/Dms/Widgets/icons.js.

function N_(s) { return s }

var MODES = [
    { id: "screenshot", label: N_("Screenshot"), glyph: "\u{F0100}" },
    { id: "video", label: N_("Video"), glyph: "\u{F0567}" },
    { id: "audio", label: N_("Audio"), glyph: "\u{F147D}" }
]

// The screenshot targets are haseen capture screenshot's modes; the video
// ones map to screenrecord's picker, --window and --fullscreen.
var TARGETS = {
    screenshot: [
        { id: "region", label: N_("Region"), glyph: "\u{F0A6D}" },
        { id: "window", label: N_("Window"), glyph: "\u{F05AF}" },
        { id: "output", label: N_("Screen"), glyph: "\u{F0379}" },
        { id: "screen", label: N_("All screens"), glyph: "\u{F037A}" }
    ],
    video: [
        { id: "region", label: N_("Region"), glyph: "\u{F0A6D}" },
        { id: "window", label: N_("Window"), glyph: "\u{F05AF}" },
        { id: "output", label: N_("Screen"), glyph: "\u{F0379}" }
    ],
    audio: []
}

// A recording's sound: what the speakers play and the default microphone.
// Sound mode shows them on the bar, where the other modes show targets;
// video shows them in its options.
var SOURCES = [
    { id: "desktop", label: N_("Desktop audio"), glyph: "\u{F057E}" },
    { id: "mic", label: N_("Microphone"), glyph: "\u{F036C}" }
]

// The bar's other glyphs.
var GLYPHS = {
    capture: "\u{F0104}",
    record: "\u{F044A}",
    options: "\u{F0493}",
    close: "\u{F0156}",
    stop: "\u{F04DB}",
    edit: "\u{F03EB}",
    delay: "\u{F051B}",
    format: "\u{F0223}",
    sound: "\u{F147D}"
}

var DELAYS = [0, 3, 5, 10]

// haseen capture audiorecord --format values, in the order the row shows them.
var FORMATS = ["mp3", "opus", "flac", "wav", "m4a", "ogg"]

function toList(v) {
    if (!v)
        return []
    var out = []
    for (var i = 0; i < v.length; i++)
        out.push(v[i])
    return out
}

function modeIds() {
    return MODES.map(function(m) { return m.id })
}

function mode(id) {
    return modeIds().indexOf(String(id || "")) >= 0 ? String(id) : "screenshot"
}

function targets(m) {
    return TARGETS[mode(m)]
}

function target(m, id) {
    var list = targets(m)
    for (var i = 0; i < list.length; i++)
        if (list[i].id === id)
            return id
    return list.length > 0 ? list[0].id : ""
}

function delay(n) {
    var v = Math.round(Number(n))
    return DELAYS.indexOf(v) >= 0 ? v : 0
}

function format(f) {
    return FORMATS.indexOf(String(f || "")) >= 0 ? String(f) : "mp3"
}

// The toolbar's state from the plugin settings, every value checked.
function initialState(settings) {
    var s = settings || {}
    var m = mode(s.mode)
    var picked = {}
    for (var i = 0; i < MODES.length; i++)
        picked[MODES[i].id] = target(MODES[i].id, MODES[i].id === m ? s.target : "")
    return {
        mode: m,
        targets: picked,
        delay: delay(s.delay),
        desktop: s.desktopAudio === true,
        mic: s.microphone === true,
        format: format(s.audioFormat),
        edit: s.edit === true
    }
}

// state with one field changed: a new mode keeps the target it had.
function withChange(state, key, value) {
    var next = {
        mode: state.mode,
        targets: Object.assign({}, state.targets),
        delay: state.delay,
        desktop: state.desktop,
        mic: state.mic,
        format: state.format,
        edit: state.edit === true
    }
    if (key === "mode")
        next.mode = mode(value)
    else if (key === "target")
        next.targets[next.mode] = target(next.mode, value)
    else if (key === "delay")
        next.delay = delay(value)
    else if (key === "desktop")
        next.desktop = value === true
    else if (key === "mic")
        next.mic = value === true
    else if (key === "format")
        next.format = format(value)
    else if (key === "edit")
        next.edit = value === true
    return next
}

function currentTarget(state) {
    return target(state.mode, state.targets ? state.targets[state.mode] : "")
}

// Audio records nothing without a source; the other modes always can.
function canCapture(state) {
    return state.mode !== "audio" || state.desktop || state.mic
}

// The command a capture runs. A screenshot opens the editor when the state
// says so or this one capture asks (Ctrl+Space); the other modes ignore it.
function startCommand(state, edit) {
    var t = currentTarget(state)
    if (state.mode === "screenshot") {
        var shot = ["haseen", "capture", "screenshot", t]
        if (edit === true || state.edit === true)
            shot.push("--edit")
        return shot
    }
    var argv = state.mode === "video" ? ["haseen", "capture", "screenrecord"] : ["haseen", "capture", "audiorecord"]
    if (state.mode === "video") {
        if (t === "window")
            argv.push("--window")
        else if (t === "output")
            argv.push("--fullscreen")
    } else {
        argv.push("--format", state.format)
    }
    if (state.desktop)
        argv.push("--desktop-audio")
    if (state.mic)
        argv.push("--microphone")
    return argv
}

// What stops the recording now running: "video" or "audio".
function stopCommand(kind) {
    return kind === "audio" ? ["haseen", "capture", "audiorecord", "--stop"] : ["haseen", "capture", "screenrecord", "--stop"]
}

// The running recording, video first: the flag files say what runs.
function recordingKind(video, audio) {
    return video ? "video" : audio ? "audio" : ""
}

// How long the toolbar waits before it captures: the chosen delay, but at
// least long enough for its own window to leave the screen.
function waitMs(state, closeMs) {
    var floor = Math.max(0, Number(closeMs) || 0)
    return Math.max(floor, (state.mode === "audio" ? 0 : delay(state.delay)) * 1000)
}

// The flag's first line is the recording's start, in seconds since the epoch.
function sinceSeconds(value) {
    var s = String(value === undefined || value === null ? "" : value).trim()
    return /^[0-9]+$/.test(s) ? Number(s) : 0
}

// 75 -> "1:15", 3725 -> "1:02:05".
function elapsedText(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    var two = function(n) { return (n < 10 ? "0" : "") + n }
    return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
}

// The bar's controls, start to end: the modes, the targets (or, for sound,
// its sources), then capture, options and close.
function barRow(state) {
    var out = modeIds().map(function(id) { return "mode:" + id })
    var t = targets(state.mode)
    if (t.length > 0)
        out = out.concat(t.map(function(x) { return "target:" + x.id }))
    else
        out = out.concat(SOURCES.map(function(x) { return x.id }))
    return out.concat(["capture", "options", "close"])
}

// The options card's rows for a mode, top to bottom.
function optionRows(state) {
    var delays = DELAYS.map(function(d) { return "delay:" + d })
    if (state.mode === "screenshot")
        return [delays, ["edit"]]
    if (state.mode === "video")
        return [["desktop", "mic"], delays]
    return [FORMATS.map(function(f) { return "format:" + f })]
}

// The toolbar's rows for the cursor, top to bottom, each a list of control
// ids: mode:<id>, target:<id>, desktop, mic, capture, options and close on
// the bar; delay:<n>, edit, desktop, mic and format:<f> in the options card,
// which opens above the bar. While a recording runs the bar is its stop and
// close buttons.
function rows(state, recording, options) {
    if (recording)
        return [["stop", "close"]]
    return (options === true ? optionRows(state) : []).concat([barRow(state)])
}

// Where the cursor starts: the capture button, or stop while recording.
function home(rowList) {
    var list = toList(rowList)
    for (var r = 0; r < list.length; r++) {
        var row = toList(list[r])
        if (row.indexOf("capture") >= 0)
            return "capture"
        if (row.indexOf("stop") >= 0)
            return "stop"
    }
    return list.length > 0 && toList(list[0]).length > 0 ? toList(list[0])[0] : ""
}

// The control the cursor reaches from id going up, down, left or right, or
// next and previous (Tab order: through every row, wrapping). Up and down
// keep the column where the next row has one, else take its last control;
// left and right stop at a row's ends. An id no longer shown starts at home.
function move(rowList, id, direction) {
    var list = toList(rowList).map(toList)
    var r = -1, c = -1
    for (var i = 0; i < list.length && r < 0; i++) {
        var j = list[i].indexOf(id)
        if (j >= 0) {
            r = i
            c = j
        }
    }
    if (r < 0)
        return home(list)
    if (direction === "left")
        return list[r][Math.max(0, c - 1)]
    if (direction === "right")
        return list[r][Math.min(list[r].length - 1, c + 1)]
    if (direction === "up" || direction === "down") {
        var to = direction === "up" ? r - 1 : r + 1
        if (to < 0 || to >= list.length)
            return id
        return list[to][Math.min(c, list[to].length - 1)]
    }
    var flat = []
    for (var k = 0; k < list.length; k++)
        flat = flat.concat(list[k])
    var at = flat.indexOf(id)
    var step = direction === "previous" ? -1 : 1
    return flat[(at + step + flat.length) % flat.length]
}

// The names the bar's icon buttons go by: the hint under the bar shows the
// one under the cursor (haseen draws no tooltips). Chips carry their text.
var LABELS = {
    capture: N_("Capture"),
    record: N_("Record"),
    options: N_("Options"),
    close: N_("Close"),
    stop: N_("Stop"),
    edit: N_("Open in the editor")
}

function labelIn(list, id) {
    for (var i = 0; i < list.length; i++)
        if (list[i].id === id)
            return list[i].label
    return ""
}

// The English name of control id, or "" for a chip.
function label(state, id) {
    var s = String(id || "")
    var colon = s.indexOf(":")
    var kind = colon >= 0 ? s.slice(0, colon) : s
    var arg = colon >= 0 ? s.slice(colon + 1) : ""
    if (kind === "mode")
        return labelIn(MODES, arg)
    if (kind === "target")
        return labelIn(targets(state.mode), arg)
    if (kind === "desktop" || kind === "mic")
        return labelIn(SOURCES, kind)
    if (kind === "capture")
        return state.mode === "screenshot" ? LABELS.capture : LABELS.record
    return LABELS[kind] || ""
}

// What activating control id does: { key, value } for withChange, or
// { action: "capture" | "stop" | "options" | "close" }.
function activate(state, id) {
    var s = String(id || "")
    var colon = s.indexOf(":")
    var kind = colon >= 0 ? s.slice(0, colon) : s
    var arg = colon >= 0 ? s.slice(colon + 1) : ""
    if (kind === "mode" || kind === "target" || kind === "format")
        return { key: kind, value: arg }
    if (kind === "delay")
        return { key: "delay", value: Number(arg) }
    if (kind === "desktop" || kind === "mic" || kind === "edit")
        return { key: kind, value: !state[kind] }
    if (kind === "capture" || kind === "stop" || kind === "options" || kind === "close")
        return { action: kind }
    return null
}

function stepIn(list, id, step) {
    var i = list.indexOf(id)
    if (i < 0)
        return list.length > 0 ? list[0] : id
    return list[(i + step + list.length) % list.length]
}

// A controller button (gamepad.py's names) while the toolbar is open: the
// D-pad and left stick move the cursor, A presses the control under it,
// B closes (the options card first), Y opens or closes the options, LT/RT
// change the mode, LB/RB the target, Start captures, the Guide button stops
// a recording.
//   -> { move: dir } | { press: true } | { close: true } | { change: {key, value} }
//      | { action: "capture" | "stop" | "options" } | null
function padAction(state, button, recording) {
    switch (button) {
    case "up":
    case "down":
    case "left":
    case "right":
        return { move: button }
    case "a":
        return { press: true }
    case "b":
        return { close: true }
    case "y":
        return recording ? null : { action: "options" }
    case "start":
        return { action: recording ? "stop" : "capture" }
    case "guide":
        return recording ? { action: "stop" } : null
    case "lt":
    case "rt":
        if (recording)
            return null
        return { change: { key: "mode", value: stepIn(modeIds(), state.mode, button === "lt" ? -1 : 1) } }
    case "lb":
    case "rb":
        var ids = targets(state.mode).map(function(t) { return t.id })
        if (recording || ids.length === 0)
            return null
        return { change: { key: "target", value: stepIn(ids, currentTarget(state), button === "lb" ? -1 : 1) } }
    }
    return null
}

// A controller line from gamepad.py: "press <button>", "connected <n>" or
// "error <text>". -> { kind, value } or null for anything else.
function padLine(line) {
    var m = /^(press|connected|error) (.+)$/.exec(String(line || "").trim())
    if (!m)
        return null
    if (m[1] === "connected")
        return /^[0-9]+$/.test(m[2]) ? { kind: "connected", value: Number(m[2]) } : null
    return { kind: m[1], value: m[2] }
}
