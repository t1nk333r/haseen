#!/usr/bin/env node
// From the owner's t1nk33r.wooting (t1nk333r/haseen-wooting tests/model.test.js
// at 184f6fa, MIT, Copyright (c) 2026 t1nk33r); plan 099, unchanged otherwise.
// Unit tests for Model.js (pure view-model logic behind the bar widget). The
// file begins with `.pragma library` (a QML directive, invalid Node JS) —
// strip it, evaluate, then assert against the exported functions.
//
// Every case here defends an observable behaviour of the widget, using the
// exact JSON shapes wootingd emits (captured from a live run against a
// Wooting 60HE+ on firmware v2.14.0).
"use strict"
const fs = require("fs"), path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*\n/, "")
const M = {}
new Function("exports", src + `
  exports.emptyState = emptyState; exports.parseLine = parseLine;
  exports.applyMessage = applyMessage; exports.cloneState = cloneState;
  exports.withConnected = withConnected; exports.disconnected = disconnected;
  exports.activeName = activeName; exports.barLabel = barLabel;
  exports.shortName = shortName; exports.numSetting = numSetting;
  exports.tooltip = tooltip; exports.shouldShow = shouldShow;
  exports.boolSetting = boolSetting;
  exports.keysFor = keysFor; exports.gridSize = gridSize; exports.hidName = hidName;
  exports.analogMap = analogMap; exports.unmapped = unmapped; exports.MATRIX = MATRIX;
  exports.fnHeld = fnHeld; exports.fnMap = fnMap; exports.fnLabel = fnLabel;
  exports.CODE_FN = CODE_FN; exports.FN_LAYER = FN_LAYER; exports.namedCount = namedCount;
  exports.CODE_UNASSIGNED = CODE_UNASSIGNED;
  exports.emptyLink = emptyLink; exports.linkStep = linkStep; exports.linkHint = linkHint;
  exports.LINK_RETRY_LIMIT = LINK_RETRY_LIMIT;`)(M)

let pass = 0, fail = 0
function eq(got, want, label) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) pass++
  else { fail++; console.log(`  FAIL: ${label}: expected ${w} got ${g}`) }
}
function ok(cond, label) { cond ? pass++ : (fail++, console.log(`  FAIL: ${label}`)) }

// Verbatim daemon output, keyboard connected.
const STATUS = {
  ok: true, present: true, firmware: "2.14.0",
  serial: "A00B0000W00T00000S00H00000", node: "/dev/hidraw5", framing: "arm",
  count: 4, active: 0,
  profiles: [
    { slot: 0, name: "1 Typing Profile", named: true, active: true },
    { slot: 1, name: "Profile 2", named: false, active: false },
    { slot: 2, name: "Profile 3", named: false, active: false },
    { slot: 3, name: "Profile 4", named: false, active: false }
  ]
}
// Verbatim daemon output, keyboard unplugged.
const ABSENT = {
  ok: true, present: false, firmware: null, serial: "", node: "",
  framing: "standard", count: 0, active: 0, profiles: []
}

// ---- parseLine ----------------------------------------------------------
eq(M.parseLine(""), null, "parseLine: empty line")
eq(M.parseLine("   \n"), null, "parseLine: whitespace only")
eq(M.parseLine("not json"), null, "parseLine: garbage")
eq(M.parseLine("[1,2]").length, 2, "parseLine: array parses")
eq(M.parseLine("null"), null, "parseLine: bare null is not an object")
eq(M.parseLine("3"), null, "parseLine: bare number is not an object")
eq(M.parseLine(undefined), null, "parseLine: non-string input")
eq(M.parseLine('{"ok":true,"pong":true}').pong, true, "parseLine: object parses")
// A partial write must never be treated as state: SplitParser only ever hands
// us whole lines, but a truncated line would otherwise silently blank the bar.
eq(M.parseLine('{"ok":true,"acti'), null, "parseLine: truncated json")

// ---- empty state --------------------------------------------------------
const empty = M.emptyState()
eq(empty.present, false, "emptyState: not present")
eq(empty.profiles, [], "emptyState: no profiles")
eq(empty.connected, false, "emptyState: not connected")

// ---- applyMessage: full snapshot ---------------------------------------
const live = M.applyMessage(M.emptyState(), STATUS)
eq(live.present, true, "applyMessage: present")
eq(live.firmware, "2.14.0", "applyMessage: firmware")
eq(live.node, "/dev/hidraw5", "applyMessage: node")
eq(live.count, 4, "applyMessage: count")
eq(live.active, 0, "applyMessage: active")
eq(live.profiles.length, 4, "applyMessage: four profiles")
eq(live.profiles[0], { slot: 0, name: "1 Typing Profile", named: true }, "applyMessage: slot 0 mapped")
eq(live.profiles[1].named, false, "applyMessage: unnamed slot flagged")

// A subscription event carries the same fields under a different key.
const evented = M.applyMessage(M.emptyState(), Object.assign({}, STATUS, { ok: undefined, event: "status" }))
eq(evented.present, true, "applyMessage: event snapshot applies")
eq(evented.profiles.length, 4, "applyMessage: event carries profiles")

// ---- applyMessage: bare active (reply to `profile set`) ----------------
// The set reply has no profile list; the selection must move without losing
// the names the widget already has.
const moved = M.applyMessage(live, { ok: true, active: 2 })
eq(moved.active, 2, "applyMessage: bare active moves selection")
eq(moved.profiles.length, 4, "applyMessage: bare active keeps profiles")
eq(M.activeName(moved), "Profile 3", "activeName: follows moved selection")

// ---- applyMessage: errors ----------------------------------------------
const rejected = M.applyMessage(live, { ok: false, error: "slot 9 out of range (device has 4 profiles)" })
eq(rejected.error, "slot 9 out of range (device has 4 profiles)", "applyMessage: error recorded")
eq(rejected.active, 0, "applyMessage: error leaves selection alone")
eq(rejected.profiles.length, 4, "applyMessage: error leaves profiles alone")
eq(M.applyMessage(live, { ok: false }).error, "command failed", "applyMessage: error without text")
// The next good message clears it, otherwise a transient rejection sticks in
// the tooltip forever.
eq(M.applyMessage(rejected, { ok: true, active: 1 }).error, "", "applyMessage: success clears error")
eq(M.applyMessage(live, null).error, "", "applyMessage: null message is inert")
eq(M.applyMessage(live, null).profiles.length, 4, "applyMessage: null message keeps state")

// ---- applyMessage: unplug ----------------------------------------------
const unplugged = M.applyMessage(live, ABSENT)
eq(unplugged.present, false, "applyMessage: unplug clears present")
eq(unplugged.profiles, [], "applyMessage: unplug empties profiles")
eq(unplugged.firmware, "", "applyMessage: null firmware becomes empty")
eq(unplugged.count, 0, "applyMessage: unplug zeroes count")

// Replug restores everything.
eq(M.applyMessage(unplugged, STATUS).profiles.length, 4, "applyMessage: replug restores profiles")

// ---- malformed profile entries -----------------------------------------
const junk = M.applyMessage(M.emptyState(), {
  ok: true, present: true, count: 2,
  profiles: [{ slot: 0, name: "a", named: true }, { name: "no slot" }, null, 7, "x", { slot: 1 }]
})
eq(junk.profiles.length, 2, "applyMessage: entries without a slot are dropped")
eq(junk.profiles[1], { slot: 1, name: "", named: false }, "applyMessage: missing name defaults empty")
// A null entry must not throw: an exception inside the QML onRead handler
// would drop the whole update.
let threw = false
try { M.applyMessage(M.emptyState(), { ok: true, profiles: [null] }) } catch (e) { threw = true }
ok(!threw, "applyMessage: null profile entry does not throw")

// ---- immutability -------------------------------------------------------
// The widget assigns a fresh object to trigger QML bindings; mutating the
// previous state in place would leave the bar stale.
const before = M.applyMessage(M.emptyState(), STATUS)
const after = M.applyMessage(before, { ok: true, active: 3 })
ok(before !== after, "applyMessage: returns a new object")
eq(before.active, 0, "applyMessage: does not mutate input")
ok(before.profiles !== after.profiles, "applyMessage: profile array is copied")

// ---- connection tracking -----------------------------------------------
eq(M.withConnected(live, true).connected, true, "withConnected: sets flag")
eq(M.withConnected(live, false).connected, false, "withConnected: clears flag")
eq(M.withConnected(rejected, true).error, "", "withConnected: connecting clears error")
eq(M.withConnected(live, true).profiles.length, 4, "withConnected: keeps profiles")

const dropped = M.disconnected(M.withConnected(live, true))
eq(dropped.present, false, "disconnected: drops presence")
eq(dropped.connected, false, "disconnected: drops connection")
eq(dropped.profiles, [], "disconnected: drops profiles")

// ---- activeName ---------------------------------------------------------
eq(M.activeName(live), "1 Typing Profile", "activeName: named slot")
eq(M.activeName(M.applyMessage(live, { ok: true, active: 1 })), "Profile 2", "activeName: unnamed slot")
eq(M.activeName(unplugged), "", "activeName: absent keyboard has no name")
eq(M.activeName(null), "", "activeName: null state")
// Active slot outside the reported list must still render something.
eq(M.activeName(M.applyMessage(live, { ok: true, active: 7 })), "Profile 8", "activeName: unknown slot falls back")

// ---- barLabel / shortName -----------------------------------------------
// The bar gets the informative part of a name, not Wootility's full string:
// the leading slot index is already shown by the popup's checkmark, and
// "Profile" says nothing on a profile indicator.
eq(M.barLabel(live, true), "Typing", "barLabel: slot prefix and the word Profile are dropped")
eq(M.barLabel(live, false), "", "barLabel: name suppressed")
eq(M.barLabel(unplugged, true), "", "barLabel: absent keyboard is blank")
eq(M.barLabel(live, true, 4), "Typ…", "barLabel: nameMaxChars truncates")
eq(M.barLabel(live, true, "4"), "Typ…", "barLabel: a string setting from `omarchy bar set` still counts")

eq(M.shortName("1 Typing Profile"), "Typing", "shortName: Wootility's default name")
eq(M.shortName("2. Gaming Profile"), "Gaming", "shortName: numbered with a separator")
eq(M.shortName("Rapid Trigger Setup"), "Rapid Trigg…", "shortName: a long name truncates, ellipsis included in the budget")
eq(M.shortName("Rapid Trigger Setup").length, 12, "shortName: the rendered label never exceeds nameMaxChars")
// Stripping must never empty the label: these names are all the user has.
eq(M.shortName("Profile"), "Profile", "shortName: a name that is only the noun survives")
eq(M.shortName("Profile 3"), "Profile 3", "shortName: the synthesised label for a nameless slot survives")
eq(M.shortName("3"), "3", "shortName: a name that is only a number survives")
eq(M.shortName("  4  Split  "), "Split", "shortName: surrounding whitespace is trimmed")
eq(M.shortName(""), "", "shortName: nothing in, nothing out")
eq(M.shortName(null), "", "shortName: null is not the string 'null'")
eq(M.shortName("Typing", 1), "Ty…", "shortName: refuses to shrink below three characters")

eq(M.numSetting(8, 12), 8, "numSetting: a real number")
eq(M.numSetting("8", 12), 8, "numSetting: the string the CLI writes")
eq(M.numSetting("8.9", 12), 8, "numSetting: floored")
eq(M.numSetting("", 12), 12, "numSetting: empty falls back")
eq(M.numSetting("banana", 12), 12, "numSetting: garbage falls back")
eq(M.numSetting(0, 12), 12, "numSetting: zero would blank the label, so it falls back")
eq(M.numSetting(-4, 12), 12, "numSetting: negative falls back")
eq(M.numSetting(undefined, 12), 12, "numSetting: unset falls back")

// ---- shouldShow ---------------------------------------------------------
eq(M.shouldShow(live, true), true, "shouldShow: present and hiding enabled")
eq(M.shouldShow(unplugged, true), false, "shouldShow: absent and hiding enabled")
eq(M.shouldShow(unplugged, false), true, "shouldShow: absent but hiding disabled")
eq(M.shouldShow(null, true), false, "shouldShow: null state hides")
eq(M.shouldShow(null, false), true, "shouldShow: null state shows when configured")

// ---- tooltip ------------------------------------------------------------
ok(M.tooltip(M.withConnected(live, true)).indexOf("1 Typing Profile") >= 0, "tooltip: names the profile")
ok(M.tooltip(M.withConnected(live, true)).indexOf("v2.14.0") >= 0, "tooltip: reports firmware")
ok(M.tooltip(M.withConnected(unplugged, true)).indexOf("no keyboard") >= 0, "tooltip: absent keyboard")
// The daemon only runs while a keyboard is attached, so no connection means no
// keyboard — not a daemon the user should go and start.
ok(M.tooltip(dropped).indexOf("no keyboard connected") >= 0, "tooltip: no connection reads as no keyboard")
ok(M.tooltip(dropped).indexOf("systemctl") < 0, "tooltip: no daemon-start instruction for the normal unplugged state")
ok(M.tooltip(rejected).indexOf("out of range") >= 0, "tooltip: surfaces the last error")
ok(M.tooltip(null).length > 0, "tooltip: null state still has text")

// ---- boolSetting --------------------------------------------------------
// `omarchy bar set` writes strings; manifest defaults and updateEntryInline
// write real booleans. Both must work, or a CLI change is silently ignored.
eq(M.boolSetting("false", true), false, "boolSetting: string false wins over default")
eq(M.boolSetting("true", false), true, "boolSetting: string true wins over default")
eq(M.boolSetting("TRUE", false), true, "boolSetting: case-insensitive")
eq(M.boolSetting("  false  ", true), false, "boolSetting: surrounding whitespace")
eq(M.boolSetting(false, true), false, "boolSetting: real boolean false")
eq(M.boolSetting(true, false), true, "boolSetting: real boolean true")
eq(M.boolSetting("0", true), false, "boolSetting: '0'")
eq(M.boolSetting("1", false), true, "boolSetting: '1'")
eq(M.boolSetting("no", true), false, "boolSetting: 'no'")
eq(M.boolSetting("on", false), true, "boolSetting: 'on'")
eq(M.boolSetting(0, true), false, "boolSetting: numeric zero")
eq(M.boolSetting(1, false), true, "boolSetting: numeric one")
// Unset or unparseable falls back rather than guessing.
eq(M.boolSetting(undefined, true), true, "boolSetting: undefined falls back true")
eq(M.boolSetting(undefined, false), false, "boolSetting: undefined falls back false")
eq(M.boolSetting(null, true), true, "boolSetting: null falls back")
eq(M.boolSetting("", true), true, "boolSetting: empty string falls back")
eq(M.boolSetting("banana", true), true, "boolSetting: garbage falls back true")
eq(M.boolSetting("banana", false), false, "boolSetting: garbage falls back false")

// ---- keyboard layout ----------------------------------------------------
const at = (keys, row, col) => keys.find(k => k.row === row && k.col === col)
const sixty = M.keysFor({ columns: 14, functionRow: false, layout: "ansi" })
const eighty = M.keysFor({ columns: 17, functionRow: true, layout: "ansi" })
const full = M.keysFor({ columns: 21, functionRow: true, layout: "ansi" })
const sixtyIso = M.keysFor({ columns: 14, functionRow: false, layout: "iso" })

// The matrix is Wooting's diagram. Its null pattern must equal the SDK's
// NOLED positions in `rgb_led_index` (wooting-rgb-sdk.c) exactly, and the
// non-null count is fixed; spot-checks cover the keys a wrong row/col would
// most visibly misplace.
const NOLED = { 0: [1], 1: [], 2: [], 3: [14, 15, 16, 20], 4: [12, 14, 16], 5: [3, 4, 5, 7, 8, 9, 17, 20] }
for (let r = 0; r < 6; r++) {
  const nulls = M.MATRIX[r].map((c, i) => c === null ? i : -1).filter(i => i >= 0)
  eq(nulls, NOLED[r], `matrix: row ${r} nulls match the SDK's NOLED cells`)
}
eq(M.MATRIX.flat().filter(c => c !== null).length, 110, "matrix: 110 labelled cells (126 minus 16 NOLED)")
eq(M.MATRIX[0][0], "Esc", "matrix: (0,0) Esc")
eq(M.MATRIX[1][13], "Bksp", "matrix: (1,13) Backspace")
eq(M.MATRIX[2][1], "Q", "matrix: (2,1) Q")
eq(M.MATRIX[3][10], ";", "matrix: (3,10) semicolon")
eq(M.MATRIX[3][11], "'", "matrix: (3,11) quote")
eq(M.MATRIX[3][13], "Enter", "matrix: (3,13) Enter")
eq(M.MATRIX[4][13], "Shift", "matrix: (4,13) right Shift")
eq(M.MATRIX[5][6], "Space", "matrix: (5,6) Space")
eq(M.MATRIX[5][12], "Fn", "matrix: (5,12) Fn")
eq(M.MATRIX[4][15], "\u2191", "matrix: (4,15) up arrow")
eq(M.MATRIX[1][15], "Home", "matrix: (1,15) Home")
eq(M.MATRIX[2][15], "End", "matrix: (2,15) End")
eq(M.MATRIX[0][20], "Mode", "matrix: (0,20) Mode")

// Geometry invariant for every model: no two keys on the same row overlap.
// This is the check that catches a wrong width or x-override anywhere.
function overlaps(keys) {
  const rows = {}
  keys.forEach(k => { (rows[k.y] = rows[k.y] || []).push(k) })
  const bad = []
  for (const y in rows) {
    const row = rows[y].slice().sort((a, b) => a.x - b.x)
    for (let i = 1; i < row.length; i++) {
      if (row[i].x < row[i - 1].x + row[i - 1].w - 1e-9) bad.push(`y${y}: c${row[i - 1].col}@${row[i - 1].x}+${row[i - 1].w} vs c${row[i].col}@${row[i].x}`)
    }
  }
  return bad
}
for (const [name, keys] of [["60 ANSI", sixty], ["60 ISO", sixtyIso], ["80", eighty], ["full", full],
                            ["full ISO", M.keysFor({ columns: 21, functionRow: true, layout: "iso" })]]) {
  eq(overlaps(keys), [], `${name}: no overlapping keys`)
}

// 60%: five rows, fourteen columns, ANSI count 61.
eq(sixty.length, 61, "60%: 61 keys")
ok(!at(sixty, 0, 0), "60%: no function row")
eq(at(sixty, 1, 0).label, "Esc", "60%: Esc drawn where ~ sits (UNVERIFIED assumption, see Model.js)")
eq(at(sixty, 1, 0).y, 0, "60%: first drawn row is y=0")
ok(!at(sixty, 3, 12), "60% ANSI: no ISO # key")
ok(!at(sixty, 4, 1), "60% ANSI: no ISO \\ key")
ok(!at(sixty, 1, 14), "60%: no nav column")
// Every ANSI row of the main block spans exactly 15 units.
for (let r = 1; r <= 5; r++) {
  const row = sixty.filter(k => k.row === r)
  const span = Math.max(...row.map(k => k.x + k.w))
  eq(span, 15, `60%: row ${r} spans 15u`)
}
eq(at(sixty, 5, 6).w, 6.25, "60%: space bar 6.25u")
eq(at(sixty, 5, 10).x, 10, "60%: right Alt sits after the space bar (3×1.25 + 6.25)")
// ISO adds two keys and reshapes Shift/Enter; the (2,13) cell is the tall
// Enter's upper half, never a `\`.
eq(sixtyIso.length, 63, "60% ISO: 63 keys")
eq(at(sixtyIso, 3, 12).label, "#", "60% ISO: # key present")
eq(at(sixtyIso, 4, 1).label, "\\", "60% ISO: \\ key present")
eq(at(sixtyIso, 4, 0).w, 1.25, "60% ISO: short left Shift")
eq(at(sixtyIso, 2, 13).label, "Enter", "60% ISO: (2,13) is Enter's upper half")
eq(at(sixty, 2, 13).label, "\\", "60% ANSI: (2,13) is backslash")

// 80%: function row, no numpad. The nav-column labels and offset are an
// UNVERIFIED placeholder (see Model.js header), so only structure is pinned.
ok(at(eighty, 0, 0) && at(eighty, 0, 0).label === "Esc", "80%: Esc on the function row")
eq(at(eighty, 0, 13).x, 14, "80%: F12 at 14u")
eq(eighty.filter(k => k.col >= 14).length, 13, "80%: thirteen keys in the three extra columns (3+3+3+0+1+3)")
ok(eighty.filter(k => k.col >= 14).every(k => k.x >= 15), "80%: extra columns sit right of the main block")
ok(!at(eighty, 1, 17), "80%: no numpad")
eq(M.gridSize(eighty).h, 6, "80%: six rows tall")

// Full-size reaches the numpad; 0 is 2u and starts under the 1 key.
eq(at(full, 1, 17).label, "Num", "full: NumLock")
eq(at(full, 5, 18).w, 2, "full: numpad 0 is 2u")
eq(at(full, 5, 18).x, at(full, 4, 17).x, "full: numpad 0 starts under numpad 1")
eq(at(full, 5, 19).x, at(full, 4, 19).x, "full: numpad . sits under numpad 3")
eq(at(full, 4, 20).label, "Enter", "full: numpad Enter")
ok(M.gridSize(full).w > 22, "full: wider than the nav column")

// Unknown model falls back to the whole matrix rather than nothing.
ok(M.keysFor(null).length > 90, "keysFor: null model draws full matrix")
ok(M.keysFor({ columns: 0 }).length > 90, "keysFor: zero columns falls back")

// ---- bottom-right: Fn is the rightmost key (PROBED on a 60HE+) ----------
// The firmware reported the Fn key at matrix (5,13) — namespace 4, code
// 0x409 — so Fn is rightmost and Right-Ctrl sits left of it, the opposite of
// the matrix diagram's ordering and matching Wooting's own 60HE Fn1 diagram.
eq(at(sixty, 5, 13).label, "Fn", "60%: (5,13) is Fn, the rightmost bottom key")
eq(at(sixty, 5, 12).label, "Ctrl", "60%: (5,12) is right Ctrl")
eq(at(full, 5, 12).label, "Fn", "full-size keeps the diagram's ordering (unprobed)")
eq(at(full, 5, 13).label, "Ctrl", "full-size keeps Ctrl at (5,13)")

// ---- Fn detection and layer labels -------------------------------------
const fnDown = M.analogMap({ keys: [{ row: 5, col: 13, code: M.CODE_FN, value: 0.9, actuated: true }] })
eq(M.CODE_FN, 0x409, "CODE_FN is the probed namespace-4 usage")
eq(M.hidName(0x409), "Fn", "hidName: the Fn usage is named, not shown as hex")
eq(M.hidName(0x502), "woot:5:2", "hidName: an unnameable namespaced usage is labelled Wooting-internal")
// Namespace 3 is the HID Consumer page; the sweep's media keys are its usages.
eq(M.hidName(0x3B6), "\u23ee", "hidName: 0x3B6 is Scan Previous Track")
eq(M.hidName(0x3CD), "\u23ef", "hidName: 0x3CD is Play/Pause")
eq(M.hidName(0x3E2), "\ud83d\udd07", "hidName: 0x3E2 is Mute")
eq(M.hidName(0x3E9), "\ud83d\udd0a", "hidName: 0x3E9 is Volume Up")
eq(M.hidName(0x3EA), "\ud83d\udd09", "hidName: 0x3EA is Volume Down")
// Namespace 4 is Wooting's own; only the probed ones are named.
eq(M.hidName(0x401), "\u2600+", "hidName: 0x401 is LED brightness up (PROBED at the ' cell)")
eq(M.hidName(0x402), "\u2600-", "hidName: 0x402 is LED brightness down (PROBED at the ; cell)")
// Profile selectors, measured with the analog stream naming the cell and the
// daemon reporting the slot: 0x403 -> slot 1, 0x404 -> slot 2, 0x405 -> slot 3
// (refused on this board because slot 3 is empty, which the label must not
// hide - it says what the key asks for).
eq(M.hidName(0x403), "\u21921", "hidName: 0x403 selects onboard slot 1 (PROBED)")
eq(M.hidName(0x404), "\u21922", "hidName: 0x404 selects onboard slot 2 (PROBED)")
eq(M.hidName(0x405), "\u21923", "hidName: 0x405 selects onboard slot 3 (PROBED, refused while empty)")
// Recorded with Fn held from slot 2: the active slot did not move, so this is
// not the missing slot-0 selector and must not be labelled as one.
eq(M.hidName(0x40C), "woot:4:12", "hidName: 0x40C does something unnamed and is not dressed up")
eq(M.hidName(0x603), "woot:6:3", "hidName: an unexplained namespace-6 usage stays raw")
eq(M.hidName(0x6F), "F20", "hidName: 0x6F in namespace 0 is the keyboard page's F20, not a consumer usage")
ok(M.fnHeld(fnDown), "fnHeld: true while the Fn usage is reported")
ok(!M.fnHeld(M.analogMap({ keys: [{ row: 2, col: 2, code: 26, value: 0.5, actuated: true }] })), "fnHeld: false for an ordinary key")
ok(!M.fnHeld({}), "fnHeld: false with nothing pressed")

// The Fn map arrives from the daemon, which learns it from the analog stream
// and keeps it across shell restarts. The panel only parses it.
const learned = M.fnMap({ event: "fn", count: 1, keys: { "5,10": 0x50 } })
eq(learned, { "5,10": 0x50 }, "fnMap: the fn event carries position -> code")
eq(M.fnMap({ ok: true, count: 2, keys: { "3,3": 73, "4,2": 77 } }), { "3,3": 73, "4,2": 77 },
  "fnMap: the `fn get` reply parses the same way")
eq(M.fnMap({ event: "fn", count: 0, keys: {} }), {}, "fnMap: an empty map is a map, not a refusal")
// `analog get` also has a `keys` field - an array of pressed keys. Taking it
// as an Fn map would wipe the learned labels on the first keypress.
ok(M.fnMap({ ok: true, present: true, keys: [{ row: 2, col: 2, code: 26 }] }) === null,
  "fnMap: an analog frame is not an Fn map")
ok(M.fnMap({ event: "analog", present: true, keys: [] }) === null, "fnMap: an empty analog frame is not an Fn map")
ok(M.fnMap({ event: "status", present: true }) === null, "fnMap: a status event is not an Fn map")
ok(M.fnMap(null) === null, "fnMap: null in, null out")
// Junk from a corrupt cache must not become keys at impossible positions.
eq(M.fnMap({ event: "fn", keys: { "3,3": 73, "nonsense": 1, "4,2": "77" } }), { "3,3": 73 },
  "fnMap: only numeric codes at row,col positions are kept")

// Label precedence: learned > documented > nothing; the Fn key labels itself.
eq(M.fnLabel(at(sixty, 5, 10), learned), { label: "\u2190", source: "learned" }, "fnLabel: learned wins")
eq(M.fnLabel(at(sixty, 1, 1), learned), { label: "F1", source: "documented" }, "fnLabel: documented default for Fn+1")
eq(M.fnLabel(at(sixty, 1, 13), {}), { label: "Del", source: "documented" }, "fnLabel: Fn+Backspace is Delete")
eq(M.fnLabel(at(sixty, 3, 1), {}), { label: "Home", source: "documented" }, "fnLabel: Fn+A is Home")
eq(M.fnLabel(at(sixty, 5, 13), {}), { label: "Fn", source: "self" }, "fnLabel: the Fn key shows itself")
eq(M.fnLabel(at(sixty, 2, 5), {}), { label: "", source: "none" }, "fnLabel: unmapped key is blank in Fn view")

// This board's own sweep, verbatim: Fn+D reports Insert where Wooting's
// diagram documents End, and Fn+Z reports End where the diagram documents
// nothing. A remapped board must win in both directions.
eq(M.fnLabel(at(sixty, 3, 3), { "3,3": 0x49 }), { label: "Ins", source: "learned" },
  "fnLabel: learned Insert overrides the documented End")
eq(M.fnLabel(at(sixty, 4, 2), { "4,2": 0x4D }), { label: "End", source: "learned" },
  "fnLabel: learned End appears where nothing is documented")
// 0x400 is the firmware saying "this Fn cell does nothing on this board". It
// must blank a documented default rather than let the panel claim a mapping
// the keyboard does not have.
eq(M.fnLabel(at(sixty, 1, 1), { "1,1": M.CODE_UNASSIGNED }), { label: "", source: "unassigned" },
  "fnLabel: an unassigned cell overrides the documented default")
eq(M.fnLabel(at(sixty, 2, 5), { "2,5": M.CODE_UNASSIGNED }), { label: "", source: "unassigned" },
  "fnLabel: an unassigned cell with nothing documented is blank")
// An action the firmware performs but will not name: documented label if there
// is one, else a mark - never the raw token, which overflowed the key.
// The diagram draws A1..A3 one column right of where the probe found these
// actions, and the probe says what they do: select an onboard slot.
eq(M.fnLabel(at(sixty, 2, 10), { "2,10": 0x404 }), { label: "\u21922", source: "learned" },
  "fnLabel: the probed slot-2 selector outranks the documented A1 label")
eq(M.fnLabel(at(sixty, 4, 0), { "4,0": 0x40C }), { label: "\u25aa", source: "internal" },
  "fnLabel: an unnameable action with nothing documented is marked, not spelled out")
eq(M.fnLabel(at(sixty, 1, 1), {}), { label: "F1", source: "documented" },
  "fnLabel: the diagram is used only where the firmware has said nothing")
ok(M.fnLabel(at(sixty, 4, 0), { "4,0": 0x40C }).label.length === 1,
  "fnLabel: the mark is one character, so it cannot overflow a 1u key")

eq(M.namedCount({ "1,1": 0x49, "1,2": M.CODE_UNASSIGNED, "1,3": 0x403, "1,4": 0x3CD }), 3,
  "namedCount: an unassigned cell never counts, a named or probed one does")
eq(M.namedCount({}), 0, "namedCount: nothing learned yet")

// The whole recorded sweep of this 60HE+ (Fn held, deepest travel per key),
// replayed through the model. It is the input that produced "woot:4:0"
// painted across the key borders, so it is the input that has to stay clean.
const SWEEP = {
  "1,0": 0x035, "1,1": 0x03a,
  "2,1": 0x400, "2,2": 0x04b, "2,3": 0x400, "2,4": 0x400, "2,5": 0x400,
  "2,6": 0x400, "2,7": 0x400, "2,8": 0x400, "2,9": 0x403, "2,10": 0x404,
  "2,11": 0x405, "2,12": 0x046,
  "3,0": 0x039, "3,1": 0x04a, "3,2": 0x04e, "3,3": 0x049, "3,4": 0x400,
  "3,5": 0x400, "3,6": 0x400, "3,7": 0x3b6, "3,8": 0x3cd, "3,9": 0x3b5,
  "3,10": 0x402, "3,11": 0x401,
  "4,0": 0x40c, "4,2": 0x04d, "4,3": 0x400, "4,4": 0x400, "4,5": 0x400,
  "4,6": 0x400, "4,7": 0x06f, "4,8": 0x3e2, "4,9": 0x3ea, "4,10": 0x3e9,
  "4,11": 0x052,
  "5,0": 0x0e0, "5,1": 0x0e3, "5,2": 0x0e2, "5,6": 0x02c,
  "5,10": 0x050, "5,11": 0x051, "5,12": 0x04f
}
const swept = sixty.map(k => M.fnLabel(k, SWEEP))
eq(swept.filter(f => f.label.indexOf("woot:") === 0).length, 0,
  "sweep: no raw Wooting token reaches a key label")
eq(swept.filter(f => f.label.length > 5).map(f => f.label), [],
  "sweep: no label is wide enough to overflow a key")
// Spot-checks against the recording: a keyboard usage, a consumer usage, a
// probed Wooting action, an unassigned cell, and an unnameable action.
eq(M.fnLabel(at(sixty, 4, 7), SWEEP), { label: "F20", source: "learned" }, "sweep: Fn+N is F20")
eq(M.fnLabel(at(sixty, 4, 8), SWEEP), { label: "\ud83d\udd07", source: "learned" }, "sweep: Fn+M is Mute")
eq(M.fnLabel(at(sixty, 3, 11), SWEEP), { label: "\u2600+", source: "learned" }, "sweep: Fn+' is LED brightness up")
eq(M.fnLabel(at(sixty, 2, 12), SWEEP), { label: "PrtSc", source: "learned" }, "sweep: Fn+] is Print Screen on this board")
eq(M.fnLabel(at(sixty, 2, 4), SWEEP), { label: "", source: "unassigned" }, "sweep: Fn+R does nothing on this board")
eq(M.fnLabel(at(sixty, 5, 6), SWEEP), { label: "Space", source: "learned" }, "sweep: Fn+Space is still Space")
eq(M.namedCount(SWEEP), 29, "sweep: 29 of the 45 recorded cells carry a name")

// Every documented Fn cell must land on a key the 60% grid actually draws,
// or the transcription has drifted from the matrix.
const sixtyIds = {}
sixty.forEach(k => { sixtyIds[k.row + "," + k.col] = true })
eq(Object.keys(M.FN_LAYER).filter(id => !sixtyIds[id]), [], "FN_LAYER: every documented cell exists on the 60% grid")
eq(M.FN_LAYER["5,10"], "\u2190", "FN_LAYER: bottom-row arrows match the probe")

// ---- connection lifecycle (no polling while the socket is absent) --------
// Drive the state machine the way the QML does: apply an event, record the
// action it asks for.
function drive(link, events) {
  const actions = []
  for (const e of events) {
    const r = M.linkStep(link, e)
    link = r.link
    actions.push(r.action)
  }
  return { link, actions }
}

const bar0 = M.emptyLink(true)
eq(bar0, { wanted: true, socket: false, connected: false, pending: false, retries: 0 }, "link: bar starts wanted, idle")
eq(M.emptyLink(false).wanted, false, "link: the layout panel starts unwanted")

// The whole point: while the socket file is absent, NO event leads to a
// connection attempt or an armed retry - so no ServerNotFoundError, ever.
// Every sequence of up to 4 non-"present" events, from every reachable
// absent state (bar and panel, wanted or not), is checked.
const nonPresent = ["absent", "connected", "failed", "retry", "open", "close"]
let sequences = [[]]
for (let depth = 0; depth < 4; depth++) {
  const next = []
  for (const seq of sequences) for (const e of nonPresent) next.push(seq.concat([e]))
  sequences = sequences.concat(next)
}
let leaked = 0
for (const start of [M.emptyLink(true), M.emptyLink(false), M.linkStep(M.emptyLink(true), "absent").link]) {
  for (const seq of sequences) {
    // "connected" cannot happen without a Socket, and a Socket only exists
    // after "connect"; skip impossible sequences rather than assert on them.
    if (seq.includes("connected")) continue
    const r = drive(start, seq)
    if (r.actions.some(a => a === "connect" || a === "retry")) leaked++
  }
}
eq(leaked, 0, "link: no event sequence connects or arms a retry while the socket is absent")
ok(sequences.length > 1000, "link: the absent-state search covered >1000 sequences")

// Socket appears: exactly one connect, then nothing while it is up.
let r = M.linkStep(bar0, "present")
eq(r.action, "connect", "link: the socket appearing triggers one connect")
eq(r.link.pending, true, "link: the attempt is pending")
eq(M.linkStep(r.link, "present").action, "none", "link: a repeat 'present' while connecting does not stack attempts")
r = M.linkStep(r.link, "connected")
eq(r.action, "none", "link: connected needs no action")
eq(r.link.connected, true, "link: connected recorded")
eq(M.linkStep(r.link, "present").action, "none", "link: 'present' while connected is ignored")
eq(M.linkHint(r.link), "", "link: no hint while connected")

// Unplug: systemd stops the daemon, the daemon removes its socket.
const up = r.link
r = drive(up, ["failed", "absent"])
eq(r.actions, ["retry", "drop"], "link: a drop with the file still there arms one retry; the file vanishing drops")
eq(M.linkStep(r.link, "retry").action, "none", "link: the retry armed before the socket vanished does nothing")
eq(M.linkHint(r.link), "no Wooting keyboard connected", "link: unplugged reads as no keyboard")
// The same in the other order (inotify can beat the socket's own close).
r = drive(up, ["absent", "failed", "retry"])
eq(r.actions, ["drop", "none", "none"], "link: file gone first - the close and timer are quiet")

// Replug: the daemon binds a new socket, the watcher reports it.
eq(M.linkStep(r.link, "present").action, "connect", "link: replug reconnects at once, event-driven")

// A connect that fails while the file exists is retried a bounded number of
// times (bind→listen race; a crashed daemon's stale socket), then goes quiet.
r = drive(M.emptyLink(true), ["present"])
let retries = 0, connects = 1
for (let i = 0; i < 10; i++) {
  const f = M.linkStep(r.link, "failed")
  r = { link: f.link }
  if (f.action !== "retry") break
  retries++
  const t = M.linkStep(r.link, "retry")
  r = { link: t.link }
  if (t.action === "connect") connects++
}
eq(retries, M.LINK_RETRY_LIMIT, "link: retries are bounded by LINK_RETRY_LIMIT")
eq(connects, M.LINK_RETRY_LIMIT + 1, "link: one attempt per retry, plus the first")
eq(M.linkStep(r.link, "failed").action, "none", "link: past the limit a failure arms nothing")
eq(M.linkHint(r.link), "wootingd is not answering · journalctl --user -u wootingd", "link: an unanswering socket says where to look")
// A restarted daemon replaces the socket file: a fresh 'present' resets the budget.
r = M.linkStep(r.link, "present")
eq([r.action, r.link.retries], ["connect", 0], "link: a new socket file resets the retry budget")
eq(M.linkHint(r.link), "connecting to wootingd…", "link: in-flight attempt reads as connecting")

// onError and onConnectionStateChanged can both report one failure.
r = drive(M.emptyLink(true), ["present", "failed", "failed"])
eq(r.actions, ["connect", "retry", "none"], "link: a doubly-reported failure arms one retry")
eq(r.link.retries, 1, "link: and spends one unit of the retry budget")

// The layout panel: watches always, connects only while open.
let panel = M.linkStep(M.emptyLink(false), "present")
eq(panel.action, "none", "link: a closed panel does not connect when the socket appears")
panel = M.linkStep(panel.link, "open")
eq(panel.action, "connect", "link: opening the panel connects when the socket is there")
panel = drive(panel.link, ["connected", "close"])
eq(panel.actions, ["none", "drop"], "link: closing the panel drops the link")
eq(M.linkStep(panel.link, "failed").action, "none", "link: the dropped Socket's close is not retried")
eq(M.linkStep(M.emptyLink(false), "open").action, "none", "link: opening with no keyboard does not connect")

// ---- HID names ----------------------------------------------------------
eq(M.hidName(0x1A), "W", "hidName: W")
eq(M.hidName(0x29), "Esc", "hidName: Esc")
eq(M.hidName(0xE1), "Shift", "hidName: left Shift")
eq(M.hidName(0x0F01), "woot:15:1", "hidName: a namespaced usage is labelled Wooting-internal, not faked as a HID code")
eq(M.hidName(0xFF), "0xff", "hidName: unknown code shown as hex")

// ---- analog events -----------------------------------------------------
const ev = { event: "analog", present: true, keys: [
  { row: 2, col: 2, code: 26, value: 0.62, actuated: true },
  { row: 5, col: 6, code: 44, value: 1.7, actuated: false },
  null, { row: "x" }
] }
const pressed = M.analogMap(ev)
eq(Object.keys(pressed).length, 3, "analogMap: null dropped, malformed kept as unknown position")
eq(pressed["2,2"].value, 0.62, "analogMap: value kept")
eq(pressed["5,6"].value, 1, "analogMap: value clamped to 1")
eq(pressed["255,255"].code, 0, "analogMap: malformed entry lands on the unknown position")
eq(Object.keys(M.analogMap({ keys: [] })).length, 0, "analogMap: empty release frame")
eq(Object.keys(M.analogMap(null)).length, 0, "analogMap: null message")

// A key at a position the grid does not draw must surface, not vanish.
const stray = M.analogMap({ keys: [{ row: 0, col: 0, code: 41, value: 0.5, actuated: true }, { row: 2, col: 2, code: 26, value: 0.3, actuated: false }] })
const un = M.unmapped(stray, sixty)
eq(un.length, 1, "unmapped: one key outside the 60% grid")
eq(un[0].code, 41, "unmapped: it is the (0,0) Esc press")
eq(M.unmapped(stray, full).length, 0, "unmapped: nothing stray on a full grid")

console.log(`model.test.js: ${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
