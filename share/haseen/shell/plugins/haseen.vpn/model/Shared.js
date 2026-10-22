.pragma library

// Adapted from the owner's fork t1nk33r.vpn 1.4.1-t1nk33r.1 of
// jkoestinger/omarchy-vpn (MIT, Copyright (c) 2026 Justin Köstinger); see
// LICENSE, LICENSE.nordvpn and UPSTREAM.md beside this directory. Unchanged
// by the haseen port (plan 096) apart from this notice; plan 109 added the
// translation helpers below.

// Helpers every backend leans on, and the widget's own settings. Anything here
// is by definition not one tool's problem: a parser or row-builder that only
// one backend calls belongs in that backend's file instead.

// Nerd Font glyphs are built from codepoints instead of raw characters so the
// file survives editing tools that mangle multi-byte sequences.
var GLYPH_VPN = String.fromCodePoint(0xF0582)
var GLYPH_CHECK = String.fromCodePoint(0xF012C)
var GLYPH_LOCK = String.fromCodePoint(0xF033E)
var GLYPH_BOLT = String.fromCodePoint(0xF04C5)
var GLYPH_DICE = String.fromCodePoint(0xF01D5)
var GLYPH_SWAP = String.fromCodePoint(0xF04E1)
var GLYPH_SHIELD = String.fromCodePoint(0xF0498)
// A shield with a lock in it: reads as neither the bare shield WireGuard uses
// nor the bare padlock OpenVPN does, which is the point — the three sit next
// to each other in the same list.
var GLYPH_SHIELD_LOCK = String.fromCodePoint(0xF099D)
var GLYPH_CHEVRON_DOWN = String.fromCodePoint(0xF0140)
var GLYPH_CHEVRON_UP = String.fromCodePoint(0xF0143)
var GLYPH_COG = String.fromCodePoint(0xF0493)
// Two overlapping sheets: a row that copies a command rather than connecting
// anywhere. Only the NordVPN backend has one so far, and only for as long as
// the CLI is refusing it.
var GLYPH_CLIPBOARD = String.fromCodePoint(0xF018F)

// ------------------------------------------------------------ translation

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text }

// A sentence built around values ("Connecting to %1…", "3 cities") comes
// back in English, filled in, as it always did: the tests, the IPC status
// and the settings matching read it. compose() and composeCount() also
// remember its template and values under that English, so the panel can
// translate the sentence whole, and its values in turn, when it shows it:
// composition(text) gives them back, or null for plain text. The memory is
// bounded; a sentence forgotten shows in English until it is built again.
var _composed = {}
var _composedSize = 0

function _remember(text, entry) {
  if (!Object.prototype.hasOwnProperty.call(_composed, text)) {
    if (_composedSize >= 4000) {
      _composed = {}
      _composedSize = 0
    }
    _composedSize += 1
  }
  _composed[text] = entry
  return text
}

function _fill(template, args) {
  return String(template).replace(/%([1-9])/g, function(whole, digit) {
    var value = args[Number(digit) - 1]
    return value === undefined || value === null ? whole : String(value)
  })
}

function compose(template) {
  var args = Array.prototype.slice.call(arguments, 1)
  return _remember(_fill(template, args), { template: String(template), args: args })
}

// `one` and `other` as for I18n.tn: %1 is the count.
function composeCount(one, other, count) {
  return _remember(_fill(count === 1 ? one : other, [count]), { one: String(one), other: String(other), count: count })
}

function composition(text) {
  var key = String(text)
  return Object.prototype.hasOwnProperty.call(_composed, key) ? _composed[key] : null
}

// ----------------------------------------------------------------- shared

// The exit address lookup answers with a bare address and nothing else. A
// captive portal's login page, a proxy's error body, or anything else that
// came back with it is not an answer — and this is the one number a user reads
// to decide whether the tunnel is carrying their traffic, so rendering
// whatever arrived would be the widget confirming a route it never saw.
// Returns "" for anything that is not an address literal.
function parsePublicIp(raw) {
  var text = String(raw || "").trim()
  // Longest possible IPv6 text form; anything longer is not an address.
  if (text === "" || text.length > 45) return ""

  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(text)) {
    var octets = text.split(".")
    for (var i = 0; i < octets.length; i++) {
      if (parseInt(octets[i], 10) > 255) return ""
    }
    return text
  }

  // IPv6 has too many legal spellings to re-implement here, so this checks the
  // alphabet and the shape rather than the grouping.
  if (/^[0-9a-fA-F:]+$/.test(text) && text.indexOf("::") === text.lastIndexOf("::")) {
    if (text.indexOf(":") !== -1 && !/:::/.test(text)) return text.toLowerCase()
  }
  return ""
}

function elide(text, limit) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > limit ? value.substring(0, limit - 1) + "…" : value
}

// A NetworkManager connection uuid, and nothing that merely resembles one.
// Here rather than in NetworkManager.js because the reason it exists is not
// NetworkManager's: this is the one value in the widget that reaches a shell,
// through the terminal launcher the credential prompt goes out on, and the
// rule is "shaped like a uuid or it does not go".
function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value || ""))
}

// "a", "a or b", "a, b, or c". Used for the line listing what a user could
// install, which is assembled from the backends rather than written out, so
// that adding one cannot leave the sentence naming a shorter list than the
// widget actually supports.
function sentenceList(items, conjunction) {
  var parts = []
  for (var i = 0; i < (items || []).length; i++) {
    var item = String(items[i] || "").trim()
    if (item !== "" && parts.indexOf(item) === -1) parts.push(item)
  }
  var word = conjunction || "or"
  if (parts.length === 0) return ""
  if (parts.length === 1) return parts[0]
  if (parts.length === 2) return parts[0] + " " + word + " " + parts[1]
  return parts.slice(0, -1).join(", ") + ", " + word + " " + parts[parts.length - 1]
}

function detail(label, value) {
  return { label: label, value: String(value || "") }
}

// A tool setting the panel can flip. The value is always what the tool last
// reported, never something the widget stores — nothing here owns a setting.
function toggle(key, label, description, value) {
  return { key: key, label: label, detail: description, value: value === true, busy: false }
}

// A toggle the user just flipped shows the new position and a busy marker until
// the tool confirms it, so the switch does not sit still under the click.
function applyPendingToggles(toggles, pending) {
  if (!pending) return toggles
  return toggles.map(function(entry) {
    if (pending[entry.key] === undefined) return entry
    return { key: entry.key, label: entry.label, detail: entry.detail, value: pending[entry.key] === true, busy: true }
  })
}

// The favourite-countries setting, split and upper-cased. Shared because every
// tool reads the same setting, though not in the same way: Proton and Mullvad
// take the two-letter codes literally, while Windscribe names regions rather
// than countries and matches these against those names. The parsing is common
// to all of them; what a match means is the backend's own business.
function favoriteCodes(raw) {
  var codes = []
  var parts = String(raw || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var code = parts[i].trim().toUpperCase()
    if (code !== "" && codes.indexOf(code) < 0) codes.push(code)
  }
  return codes
}

// --------------------------------------------------------- widget settings

// Which tools the user told the widget to ignore, stored as one comma-separated
// string so the setting stays hand-editable in shell.json and in Omarchy's own
// settings dialog, which has no array field.
function parseBackendIds(raw) {
  var ids = []
  var parts = String(raw || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var id = parts[i].trim().toLowerCase()
    if (id !== "" && ids.indexOf(id) === -1) ids.push(id)
  }
  return ids
}

function joinBackendIds(ids) {
  return ids.join(",")
}

function toggleBackendId(ids, id) {
  var next = []
  var found = false
  for (var i = 0; i < ids.length; i++) {
    if (ids[i] === id) found = true
    else next.push(ids[i])
  }
  if (!found) next.push(id)
  return next
}
