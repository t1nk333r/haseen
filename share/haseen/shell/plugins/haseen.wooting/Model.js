.pragma library
// Pure view-model logic for the Wooting bar widget and panel (plan 099),
// from the owner's t1nk33r.wooting (t1nk333r/haseen-wooting Model.js at
// 184f6fa, MIT, Copyright (c) 2026 t1nk33r). Logic unchanged; comments name
// haseen's places. No Qt types below this line: tests/model.test.js runs
// this file under plain node.
//
// The daemon is the only source of truth. This module's whole job is to turn
// the daemon's JSON lines into the handful of values the bar draws, and to
// decide nothing that the daemon could decide instead.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text }

// Empty state: what the widget shows before the first line arrives, and after
// the keyboard goes away.
function emptyState() {
  return {
    present: false,
    firmware: "",
    serial: "",
    node: "",
    count: 0,
    active: 0,
    profiles: [],
    error: "",
    connected: false
  }
}

function parseLine(line) {
  if (typeof line !== "string") return null
  var text = line.trim()
  if (text === "") return null
  try {
    var parsed = JSON.parse(text)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (e) {
    return null
  }
}

// Fold one daemon message into the state.
//
// Three message shapes arrive on the same subscribed socket:
//   {"ok":true, ...full state...}    reply to `status` / `profile list`
//   {"event":"status"|"change", ...} subscription snapshot / push
//   {"ok":true,"active":n}           reply to `profile set` (no full state)
//   {"ok":false,"error":"..."}       any rejected command
// Anything carrying `profiles` replaces the profile list; a bare `active`
// only moves the selection. Unparseable or unknown lines leave state intact.
function applyMessage(state, message) {
  var next = cloneState(state)
  if (!message) return next

  if (message.ok === false) {
    next.error = typeof message.error === "string" ? message.error : N_("command failed")
    return next
  }

  // A successful message clears the last error: the daemon is talking to us.
  next.error = ""

  if (message.pong === true) return next

  if (typeof message.present === "boolean") next.present = message.present
  if (typeof message.firmware === "string") next.firmware = message.firmware
  else if (message.firmware === null) next.firmware = ""
  if (typeof message.serial === "string") next.serial = message.serial
  if (typeof message.node === "string") next.node = message.node
  if (typeof message.count === "number") next.count = message.count
  if (typeof message.active === "number") next.active = message.active

  if (Array.isArray(message.profiles)) {
    next.profiles = message.profiles.filter(function(entry) {
      // A null or non-object entry would throw inside the QML onRead handler
      // and drop the whole update; skip it instead.
      return entry && typeof entry === "object" && typeof entry.slot === "number"
    }).map(function(entry) {
      return {
        slot: entry.slot,
        name: typeof entry.name === "string" ? entry.name : "",
        named: entry.named === true
      }
    })
  }

  return next
}

function cloneState(state) {
  var base = emptyState()
  if (!state) return base
  base.present = state.present === true
  base.firmware = state.firmware || ""
  base.serial = state.serial || ""
  base.node = state.node || ""
  base.count = state.count || 0
  base.active = typeof state.active === "number" ? state.active : 0
  base.error = state.error || ""
  base.connected = state.connected === true
  base.profiles = (state.profiles || []).map(function(entry) {
    return { slot: entry.slot, name: entry.name, named: entry.named === true }
  })
  return base
}

// Socket came up. The connection flag is the widget's own knowledge, not the
// daemon's, so it is set here rather than folded out of a message.
function withConnected(state, flag) {
  var next = cloneState(state)
  next.connected = flag === true
  if (next.connected) next.error = ""
  return next
}

// Losing the socket is not the same as losing the keyboard, but the widget
// cannot tell the difference and must not keep showing a stale profile.
function disconnected(state) {
  var next = emptyState()
  next.error = state && state.error ? state.error : ""
  return next
}

// ---- connection lifecycle -------------------------------------------------
//
// wootingd runs only while a Wooting keyboard is attached: the plugin's udev
// rule starts it and BindsTo= stops it on unplug, and it removes its socket
// when it stops. So "no socket" is the normal state of a desk without the
// keyboard, not a fault to retry - the old 3 s reconnect Timer turned exactly
// that state into a QLocalSocket::ServerNotFoundError in the shell's journal
// every 3 s. The QML now watches the socket path (FileView, inotify) and feeds
// what it sees into this state machine; nothing here ever asks for a connect
// while the socket file is absent.
//
// The one timed path is a bounded retry after a connection fails while the
// socket file exists: the file appears at bind(2), a hair before listen(2),
// and a crashed daemon leaves a stale file until systemd restarts it (which
// replaces the file, a fresh "present"). LINK_RETRY_LIMIT attempts, then quiet
// until the watcher reports a change.
var LINK_RETRY_LIMIT = 3

// `wanted`: whether the consumer wants a connection at all. The bar always
// does; the layout panel only while it is open.
function emptyLink(wanted) {
  return { wanted: wanted !== false, socket: false, connected: false, pending: false, retries: 0 }
}

function cloneLink(link) {
  var base = emptyLink(true)
  if (!link) return base
  base.wanted = link.wanted !== false
  base.socket = link.socket === true
  base.connected = link.connected === true
  base.pending = link.pending === true
  base.retries = typeof link.retries === "number" && link.retries > 0 ? Math.floor(link.retries) : 0
  return base
}

// One event in, the next link state and ONE action out.
//   events:  "present" / "absent"  the watcher saw the socket file / its absence
//            "connected" / "failed" the Socket came up / errored or dropped
//            "retry"                the bounded retry timer fired
//            "open" / "close"       the consumer starts / stops wanting a link
//   actions: "connect" (create a fresh Socket), "drop" (destroy it),
//            "retry" (arm the retry timer once), "none"
function linkStep(link, event) {
  var l = cloneLink(link)
  var action = "none"
  var mayConnect = function() { return l.wanted && l.socket && !l.connected && !l.pending }
  switch (event) {
  case "present":
    l.socket = true
    if (mayConnect()) { l.retries = 0; l.pending = true; action = "connect" }
    break
  case "absent":
    l.socket = false
    l.connected = false
    l.pending = false
    l.retries = 0
    action = "drop"
    break
  case "connected":
    l.connected = true
    l.pending = false
    l.retries = 0
    break
  case "failed":
    // One failure can surface twice (onError and a connection-state change);
    // only the first, which ends an attempt or a live link, counts.
    if (!l.pending && !l.connected) break
    l.connected = false
    l.pending = false
    if (l.wanted && l.socket && l.retries < LINK_RETRY_LIMIT) { l.retries += 1; action = "retry" }
    break
  case "retry":
    if (mayConnect()) { l.pending = true; action = "connect" }
    break
  case "open":
    l.wanted = true
    if (mayConnect()) { l.retries = 0; l.pending = true; action = "connect" }
    break
  case "close":
    l.wanted = false
    l.connected = false
    l.pending = false
    l.retries = 0
    action = "drop"
    break
  }
  return { link: l, action: action }
}

// What a consumer should say while it has no live connection; "" once it has.
function linkHint(link) {
  var l = cloneLink(link)
  if (l.connected) return ""
  if (!l.socket) return N_("no Wooting keyboard connected")
  if (l.retries >= LINK_RETRY_LIMIT && !l.pending) return N_("wootingd is not answering · journalctl --user -u wootingd")
  return N_("connecting to wootingd…")
}

function activeName(state) {
  if (!state || !state.present) return ""
  for (var i = 0; i < state.profiles.length; i++) {
    if (state.profiles[i].slot === state.active) return state.profiles[i].name
  }
  return "Profile " + (state.active + 1)
}

// Bar labels compete with every other widget for width; 12 characters is about
// two profile words. Override per widget with `nameMaxChars`.
var NAME_MAX_CHARS = 12

// Wootility's default names are wordy ("1 Typing Profile") and the bar has no
// room for them. Two parts of such a name carry no information *in the bar*:
// the leading slot index, which the panel already marks with a checkmark, and
// the word "Profile" on a profile indicator. Whatever survives is truncated.
// Nothing here may return an empty string for a named profile, so each step
// keeps its input when stripping would empty it - "Profile 3", the synthesised
// label for a nameless slot, has to stay legible.
function shortName(name, maxChars) {
  var s = String(name === undefined || name === null ? "" : name).trim()
  if (s === "") return ""
  var max = numSetting(maxChars, NAME_MAX_CHARS)
  if (max < 3) max = 3
  var unprefixed = s.replace(/^\d+\s*[.:)\-]?\s+/, "").trim()
  if (unprefixed !== "") s = unprefixed
  var unnouned = s.replace(/\s*profiles?$/i, "").trim()
  if (unnouned !== "") s = unnouned
  if (s.length > max) return s.slice(0, max - 1).trim() + "…"
  return s
}

// The widget is hidden when there is no keyboard, so a visible widget with an
// empty label would be a bug: fall back to the plain product name.
function barLabel(state, showName, maxChars) {
  if (!state || !state.present) return ""
  if (!showName) return ""
  return shortName(activeName(state), maxChars)
}

function tooltip(state) {
  if (!state) return "Wooting"
  if (state.error) return "Wooting · " + state.error
  // No socket is what a desk without the keyboard looks like: the daemon only
  // runs while one is attached.
  if (!state.connected) return "Wooting · no keyboard connected"
  if (!state.present) return "Wooting · no keyboard"
  var parts = ["Wooting · " + activeName(state)]
  if (state.firmware) parts.push("firmware v" + state.firmware)
  parts.push("click to switch profile")
  return parts.join(" · ")
}

// Whether the bar should draw anything at all. `hideWhenAbsent` defaults on:
// a dead icon for an unplugged keyboard is worse than no icon.
function shouldShow(state, hideWhenAbsent) {
  if (!hideWhenAbsent) return true
  return !!(state && state.present)
}

// Read a boolean setting out of the plugin's shell.json settings.
//
// The same setting can arrive in two shapes: a command-line writer (the
// original's `omarchy bar set <id> <key> <value>`) stores every value as a
// STRING ("true"/"false"), while manifest defaults store real booleans. A
// plain `=== true` test therefore silently ignored every such change — the
// widget stayed icon-only forever, with no error to explain it.
function boolSetting(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback === true
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  switch (String(value).trim().toLowerCase()) {
  case "true": case "1": case "yes": case "on": return true
  case "false": case "0": case "no": case "off": return false
  default: return fallback === true
  }
}

// Same trap as booleans: a string writer stores "8", not 8, for nameMaxChars.
// Anything that is not a positive number falls back rather than shrinking the
// label to nothing.
function numSetting(value, fallback) {
  if (typeof value === "number" && isFinite(value) && value > 0) return Math.floor(value)
  if (typeof value === "string" && value.trim() !== "") {
    var n = Number(value.trim())
    if (isFinite(n) && n > 0) return Math.floor(n)
  }
  return fallback
}

// ---------------------------------------------------------------------------
// Keyboard layout.
//
// Positions are the firmware's own row/column matrix, the same 6×21 space the
// RGB SDK addresses and the analog stream reports keys in
// (wooting-rgb-sdk/src/wooting-rgb-sdk.c `rgb_led_index`;
// wooting-analog-sdk/wooting-analog-sdk/src/device.rs:443-444
// `row = pos >> 5, col = pos & 0x1F`; commits pinned in
// core/wootingd/src/proto.rs). Labels are transcribed from Wooting's own
// diagram, wooting-rgb-sdk/resources/keyboard-matrix-rows-columns.png
// (MPL-2.0): key names at matrix positions, facts, not the image.
// A model is drawn as a *column-prefix window* onto this matrix: `columns`
// from the SDK's per-model `max_columns` (14 = 60HE family, 17 = 80HE,
// 21 = full-size), and whether row 0 (the function row) exists.
//
// Everything below the matrix — key widths, gaps, where the nav cluster sits —
// is ordinary ANSI/ISO layout knowledge, not Wooting data, and is marked so.
//
// UNVERIFIED assumptions, each of which the live analog feed will confirm or
// refute the first time the relevant board is plugged in (a key reported at a
// position the grid does not draw shows up as an "unmapped" chip, never
// silently):
//   - that a smaller board reports positions as a prefix of the full-size
//     matrix at all — consistent with `max_columns`, but the SDK's table is
//     for the V1 boards and V2 firmware reports row/col directly;
//   - 60%: no `~` key, so Esc is drawn at row 1 col 0;
//   - 80HE: columns 14-16 of the full matrix are the V1 Two's 3-wide nav
//     column (PrtSc/Pause/ScrLk, Ins/Home/PgUp, Del/End/PgDn). The shipped
//     80HE is a compact 80% with a 2×2 nav block and F-row ending
//     `F12 Mode PrtSc Pause`, so both the labels and the 15.25u offset are
//     placeholders until an 80HE reports its own matrix. Verified on hardware:
//     only the 60HE+.
//   - `jis` draws as ANSI; `iso-split` as ISO; UwU (5-row matrix in the SDK)
//     would render as the left 7 columns of a 60%, which is wrong but harmless.

var MATRIX = [
  ["Esc", null, "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "PrtSc", "Pause", "ScrLk", "A1", "A2", "A3", "Mode"],
  ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Bksp", "Ins", "Home", "PgUp", "Num", "/", "*", "-"],
  ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\", "Del", "End", "PgDn", "7", "8", "9", "+"],
  ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "ISO#", "Enter", null, null, null, "4", "5", "6", null],
  ["Shift", "ISO\\", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", null, "Shift", null, "\u2191", null, "1", "2", "3", "Enter"],
  ["Ctrl", "Win", "Alt", null, null, null, "Space", null, null, null, "Alt", "Win", "Fn", "Ctrl", "\u2190", "\u2193", "\u2192", null, "0", ".", null]
]

// Wooting's documented Fn1 layer for the 60HE(+), transcribed from
// wooting.io/quickstart/keyboard/wooting-60he/prebuilt (the `fn1`,
// `arrow-keys`, `media-keys`, `brightness-keys` and `profiles` diagrams),
// keyed "row,col" in the same matrix space. These are the FACTORY defaults:
// anything remapped in Wootility will differ, which is why a press seen while
// Fn is held always wins over this table (see `fnMap` and the daemon).
//
// Cross-checked against the hardware: holding Fn and pressing (5,10) reported
// HID 0x50 (Left Arrow), exactly as this table claims.
var FN_LAYER = {
  // digits row -> ` and F1..F12, Backspace -> Delete
  "1,0": "`", "1,1": "F1", "1,2": "F2", "1,3": "F3", "1,4": "F4", "1,5": "F5",
  "1,6": "F6", "1,7": "F7", "1,8": "F8", "1,9": "F9", "1,10": "F10",
  "1,11": "F11", "1,12": "F12", "1,13": "Del",
  // QWERTY row -> print screen, page up, analog A1-A3
  "2,0": "PrtSc", "2,2": "PgUp", "2,10": "A1", "2,11": "A2", "2,12": "A3",
  // home row -> Fn2, nav, media, LED brightness, Mode
  "3,0": "Fn2", "3,1": "Home", "3,2": "PgDn", "3,3": "End",
  "3,7": "\u23ee", "3,8": "\u23ef", "3,9": "\u23ed",
  "3,10": "\u2600-", "3,11": "\u2600+", "3,13": "Mode",
  // ZXCV row -> volume and up arrow
  "4,8": "\ud83d\udd07", "4,9": "\ud83d\udd09", "4,10": "\ud83d\udd0a", "4,11": "\u2191",
  // bottom row -> arrows (PROBED: (5,10) really does report Left Arrow)
  "5,10": "\u2190", "5,11": "\u2193", "5,12": "\u2192"
}

/// Analog records carry a key *namespace* in the packed byte; namespace 0 is
/// the HID keyboard page. PROBED: the Fn key on this 60HE+ reports namespace 4
/// key 9 (code 0x409) at matrix (5,13) — so Fn IS observable, unlike what its
/// absence from the HID page suggests.
var CODE_FN = 0x409

// Horizontal positions and widths in key units (1u = one letter key), ANSI
// unless a layout says otherwise. Main block spans 15u; nav cluster starts at
// 15.25u; numpad at 18.5u. Keys absent from a table get width 1 and are
// placed after their predecessor, which is right for every plain letter key.
var WIDTHS = {
  "0,0": 1, "1,13": 2, "2,0": 1.5, "2,13": 1.5, "3,0": 1.75, "3,13": 2.25,
  "4,0": 2.25, "4,13": 2.75, "5,0": 1.25, "5,1": 1.25, "5,2": 1.25, "5,6": 6.25,
  "5,10": 1.25, "5,11": 1.25, "5,12": 1.25, "5,13": 1.25,
  "5,18": 2
}
var ISO_WIDTHS = { "3,0": 1.75, "3,12": 1, "3,13": 1.25, "4,0": 1.25, "4,1": 1 }
// Function row is spaced in groups of four; explicit x per column.
var FROW_X = { 0: 0, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6.5, 7: 7.5, 8: 8.5, 9: 9.5, 10: 11, 11: 12, 12: 13, 13: 14 }
var NAV_X = { 14: 15.25, 15: 16.25, 16: 17.25 }
var PAD_X = { 17: 18.5, 18: 19.5, 19: 20.5, 20: 21.5 }

function isIsoOnly(row, col) { return (row === 3 && col === 12) || (row === 4 && col === 1) }

// keysFor(model) -> [{row, col, label, x, y, w}] in matrix units.
// model: {columns, functionRow, layout}. Unknown model -> full-size grid.
function keysFor(model) {
  var columns = model && model.columns > 0 ? model.columns : 21
  var functionRow = !model || model.functionRow !== false
  var iso = !!(model && String(model.layout || "").indexOf("iso") === 0)
  var sixty = columns <= 14 && !functionRow
  var keys = []
  for (var row = functionRow ? 0 : 1; row < 6; row++) {
    var x = 0
    for (var col = 0; col < columns && col < 21; col++) {
      var label = MATRIX[row][col]
      if (label === null) continue
      if (isIsoOnly(row, col) && !iso) continue
      // ANSI Enter on row 3 col 13 becomes the ISO one-unit-wide tall key's
      // lower half; ANSI Left Shift on row 4 col 0 shrinks to make room.
      var w = (iso && ISO_WIDTHS[row + "," + col] !== undefined)
        ? ISO_WIDTHS[row + "," + col] : (WIDTHS[row + "," + col] || 1)
      var kx
      if (row === 0 && FROW_X[col] !== undefined) kx = FROW_X[col]
      else if (NAV_X[col] !== undefined) kx = NAV_X[col]
      // Numpad 0 is 2u and sits under 1 and 2, i.e. starts at column 17's x.
      else if (row === 5 && col === 18) kx = PAD_X[17]
      else if (PAD_X[col] !== undefined) kx = PAD_X[col]
      else kx = x
      if (col < 14) x = kx + w
      // UNVERIFIED (see header): a 60% board draws Esc where `~` sits.
      if (sixty && row === 1 && col === 0) label = "Esc"
      // PROBED on a 60HE+: the rightmost bottom cell (5,13) reports the Fn
      // key (namespace 4, code 0x409), not Right-Ctrl — the opposite of the
      // matrix diagram's `FN, RCTR` ordering, and matching Wooting's own
      // 60HE Fn1 diagram where Fn is the rightmost key. Scoped to 60% boards
      // because only a 60HE+ was probed.
      if (sixty && row === 5 && col === 12) label = "Ctrl"
      if (sixty && row === 5 && col === 13) label = "Fn"
      // ISO: the (2,13) cell is the upper half of the tall Enter, not `\`.
      // UNVERIFIED that ISO firmware reports it at (2,13) at all — the V1
      // SDK gives the ISO Enter its own LED outside the matrix table.
      if (iso && row === 2 && col === 13) label = "Enter"
      if (label === "ISO#") label = "#"
      if (label === "ISO\\") label = "\\"
      keys.push({ row: row, col: col, label: label, x: kx, y: functionRow ? row : row - 1, w: w })
    }
  }
  return keys
}

// Overall size in units, for the panel to scale to.
function gridSize(keys) {
  var w = 0, h = 0
  for (var i = 0; i < keys.length; i++) {
    if (keys[i].x + keys[i].w > w) w = keys[i].x + keys[i].w
    if (keys[i].y + 1 > h) h = keys[i].y + 1
  }
  return { w: w, h: h }
}

// HID keyboard usage ids -> labels, so a pressed key can be named from the
// code the firmware reports even when its matrix position is not in the grid.
// USB HID Usage Tables 1.12, §10 (Keyboard/Keypad page 0x07).
var HID_NAMES = {
  4: "A", 5: "B", 6: "C", 7: "D", 8: "E", 9: "F", 10: "G", 11: "H", 12: "I", 13: "J",
  14: "K", 15: "L", 16: "M", 17: "N", 18: "O", 19: "P", 20: "Q", 21: "R", 22: "S", 23: "T",
  24: "U", 25: "V", 26: "W", 27: "X", 28: "Y", 29: "Z",
  30: "1", 31: "2", 32: "3", 33: "4", 34: "5", 35: "6", 36: "7", 37: "8", 38: "9", 39: "0",
  40: "Enter", 41: "Esc", 42: "Bksp", 43: "Tab", 44: "Space", 45: "-", 46: "=", 47: "[", 48: "]",
  49: "\\", 50: "#", 51: ";", 52: "'", 53: "`", 54: ",", 55: ".", 56: "/", 57: "Caps",
  58: "F1", 59: "F2", 60: "F3", 61: "F4", 62: "F5", 63: "F6", 64: "F7", 65: "F8", 66: "F9",
  67: "F10", 68: "F11", 69: "F12", 70: "PrtSc", 71: "ScrLk", 72: "Pause", 73: "Ins", 74: "Home",
  75: "PgUp", 76: "Del", 77: "End", 78: "PgDn", 79: "\u2192", 80: "\u2190", 81: "\u2193", 82: "\u2191",
  83: "Num", 84: "/", 85: "*", 86: "-", 87: "+", 88: "Enter", 89: "1", 90: "2", 91: "3", 92: "4",
  93: "5", 94: "6", 95: "7", 96: "8", 97: "9", 98: "0", 99: ".", 100: "\\", 101: "Menu",
  // F13..F24: the sweep found Fn+N mapped to 0x6F, which is F20 - a real key
  // on this page, and printing it as "0x6f" made a valid mapping look broken.
  104: "F13", 105: "F14", 106: "F15", 107: "F16", 108: "F17", 109: "F18",
  110: "F19", 111: "F20", 112: "F21", 113: "F22", 114: "F23", 115: "F24",
  224: "Ctrl", 225: "Shift", 226: "Alt", 227: "Win", 228: "Ctrl", 229: "Shift", 230: "Alt", 231: "Win"
}

// Namespace 3 is the HID *Consumer* page (0x0C), not something Wooting made
// up: the sweep's media keys land on its documented usages - 0x3B6 Scan
// Previous, 0x3CD Play/Pause, 0x3E2 Mute, 0x3E9 Volume Up, 0x3EA Volume Down.
// USB HID Usage Tables 1.12, §15 (Consumer page 0x0C).
var CONSUMER_NAMES = {
  0x6F: "\u2600+", 0x70: "\u2600-",
  0xB5: "\u23ed", 0xB6: "\u23ee", 0xB7: "\u23f9", 0xCD: "\u23ef",
  0xE2: "\ud83d\udd07", 0xE9: "\ud83d\udd0a", 0xEA: "\ud83d\udd09",
  0x183: "Media", 0x18A: "Mail", 0x192: "Calc", 0x194: "Files",
  0x221: "Search", 0x223: "Home", 0x224: "Back", 0x225: "Fwd"
}

// Namespace 4 is Wooting's own. PROBED on a 60HE+, all with Fn held:
//   0 at 13 keys whose Fn cell is empty in Wooting's Fn1 diagram -> no action
//   9 at the rightmost bottom key                                -> Fn itself
//   2 at `;` and 1 at `'`, exactly where that diagram draws LED
//     brightness down and up                                     -> ☀- / ☀+
//
// 3, 4 and 5 select an onboard profile *slot*. Measured, not inferred: with
// the analog stream recording the cell that fired and the daemon reporting the
// active slot, `0x403` (at O) took slot 0 -> 1 and left slot 1 unchanged,
// `0x404` (at P) took slot 0 -> 2 and left slot 2 unchanged, and `0x405`
// (at `[`) moved nothing from either slot 0 or slot 2 — which is what a
// selector aimed at slot 3 does on this board, because slot 3 is empty and the
// firmware refuses to activate an empty slot. The label is the slot the key
// asks for, in this plugin's own 0-based vocabulary, so it stays truthful even
// when the firmware refuses.
//
// No code was found that selects slot 0, and `0x40C` (at left Shift) is *not*
// it: recorded with Fn held from slot 2, the active slot did not move. It does
// something unnamed, so it keeps the ▪ mark. Same for `0x603`, seen once at
// the Fn cell itself during a release.
var CODE_UNASSIGNED = 0x400
var PROFILE_SELECT = { 0x03: 1, 0x04: 2, 0x05: 3 }
var WOOTING_NAMES = {
  0x01: "\u2600+", 0x02: "\u2600-", 0x09: "Fn"
}

function hidName(code) {
  var ns = code >> 8, key = code & 0xFF
  if (ns === 0) {
    var n = HID_NAMES[key]
    if (n !== undefined) return n
    return "0x" + Number(code).toString(16)
  }
  if (ns === 3) {
    var c = CONSUMER_NAMES[code & 0x3FF] || CONSUMER_NAMES[key]
    if (c !== undefined) return c
  }
  if (ns === 4) {
    if (WOOTING_NAMES[key] !== undefined) return WOOTING_NAMES[key]
    // "→N": this key asks the firmware for onboard slot N.
    if (PROFILE_SELECT[key] !== undefined) return "\u2192" + PROFILE_SELECT[key]
  }
  // Anything else is a usage this firmware refuses to name. Say so; never
  // dress it up as a HID keyboard code.
  return "woot:" + ns + ":" + key
}

// Is Fn physically held? The firmware reports it like any other key, in its
// own namespace, so the panel can follow the layer instead of guessing.
function fnHeld(pressed) {
  for (var id in pressed) if (pressed[id].code === CODE_FN) return true
  return false
}

// The daemon's learned Fn map, as sent by `fn get` and the `fn` event:
// `{"keys":{"3,3":73,...}}`, position -> the code this board reports under Fn.
// Learning moved into the daemon because it owns the analog stream and
// outlives the shell; a panel that learned for itself showed the documented
// defaults again after every shell restart, including on the keys where this
// board contradicts them.
//
// Returns null for any other message so the caller can keep dispatching, and
// only accepts an object: `analog get` also has a `keys` field, an array.
function fnMap(message) {
  if (!message || typeof message !== "object") return null
  var keys = message.keys
  if (!keys || typeof keys !== "object" || Array.isArray(keys)) return null
  if (message.event !== "fn" && message.count === undefined) return null
  var out = {}
  for (var id in keys) {
    if (!/^\d+,\d+$/.test(id)) continue
    var code = keys[id]
    if (typeof code === "number") out[id] = code
  }
  return out
}

// Label for a key in Fn view, resolved from what this board reported.
//
// Precedence, and why: the firmware outranks Wooting's diagram in both
// directions, and the diagram is only used where the firmware has said
// nothing at all.
//
//  - a code it names            -> that name ("learned"); this is the truth
//  - 0x400                      -> blank: this Fn cell does nothing on THIS
//                                  board, so a documented default must not be
//                                  drawn - that claimed a mapping the keyboard
//                                  does not have
//  - a code it will not name    -> "▪": the key does something, and which
//                                  action it is remains unknown. Borrowing the
//                                  diagram's label here was wrong: the probe
//                                  found these actions one column left of where
//                                  the diagram draws A1..A3, so "A1" on that
//                                  key was an assertion nothing supports.
//  - nothing learned            -> the documented default, dimmed by the UI
function fnLabel(key, learned) {
  var id = key.row + "," + key.col
  var code = learned ? learned[id] : undefined
  if (typeof code === "number") {
    if (code === CODE_UNASSIGNED) return { label: "", source: "unassigned" }
    var name = hidName(code)
    if (name.indexOf("woot:") !== 0) return { label: name, source: "learned" }
    return { label: "\u25aa", source: "internal" }
  }
  if (FN_LAYER[id] !== undefined) return { label: FN_LAYER[id], source: "documented" }
  if (key.label === "Fn") return { label: "Fn", source: "self" }
  return { label: "", source: "none" }
}

// Learned cells the firmware named. An unassigned or unnameable cell is
// learned too - both are real answers - but neither teaches a label, so the
// UI does not count them as knowledge gained.
function namedCount(learned) {
  var n = 0
  for (var id in learned) {
    var code = learned[id]
    if (typeof code !== "number" || code === CODE_UNASSIGNED) continue
    if (hidName(code).indexOf("woot:") !== 0) n++
  }
  return n
}

// Fold an analog event into a map keyed "row,col" -> key record. Keys not in
// the event are released; the daemon sends the full set every time.
function analogMap(message) {
  var out = {}
  if (!message || !Array.isArray(message.keys)) return out
  for (var i = 0; i < message.keys.length; i++) {
    var k = message.keys[i]
    if (!k || typeof k !== "object") continue
    var row = typeof k.row === "number" ? k.row : 255
    var col = typeof k.col === "number" ? k.col : 255
    out[row + "," + col] = {
      row: row, col: col,
      code: typeof k.code === "number" ? k.code : 0,
      value: typeof k.value === "number" ? Math.max(0, Math.min(1, k.value)) : 0,
      actuated: k.actuated === true
    }
  }
  return out
}

// Pressed keys whose position the grid does not draw — the panel lists them
// so a wrong layout assumption shows up instead of being swallowed.
function unmapped(pressed, keys) {
  var known = {}
  for (var i = 0; i < keys.length; i++) known[keys[i].row + "," + keys[i].col] = true
  var out = []
  for (var id in pressed) if (!known[id]) out.push(pressed[id])
  out.sort(function(a, b) { return a.row - b.row || a.col - b.col })
  return out
}
