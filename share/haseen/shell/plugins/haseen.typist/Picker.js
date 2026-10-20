.pragma library
// Adapted from Picker.js in the owner's fork t1nk33r.typist 1.1.0 of
// sanjuanjor/typist (MIT, Copyright (c) 2026 sanjuanjor); see LICENSE and
// UPSTREAM.md beside this file. haseen change: the Recent section is
// haseen.clipboard's cliphist store (`cliphist list` lines), addressed by
// cliphist id instead of an index into Omarchy's history file.
//
// Pure list logic for the typist picker: the cliphist listing and a snippets
// file in, rows out. No Qt, no I/O, no state; the panel owns the processes,
// the file view and the command it runs. tests/test-typist.sh loads it in
// the Qt JS engine.
//
// Every function is total (never throws, never returns undefined), so a
// half-written file cannot turn into a QML warning storm.

var PREVIEW_CHARS = 64
var NAME_CHARS = 24
var SNIPPET_LIMIT = 200

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

function parseJson(raw) {
  if (raw === undefined || raw === null) return null
  if (typeof raw !== "string") return raw
  try {
    return JSON.parse(raw)
  } catch (error) {
    return null
  }
}

function codePointBytes(code) {
  if (code < 0x80) return 1
  if (code < 0x800) return 2
  if (code < 0x10000) return 3
  return 4
}

// UTF-8 length, counted by hand rather than through encodeURIComponent,
// which throws on a lone surrogate. A file this widget reads is one someone
// else writes, so it must not be able to take the panel down.
function sizeOf(text) {
  var value = str(text)
  var bytes = 0
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
      var low = value.charCodeAt(i + 1)
      if (low >= 0xDC00 && low <= 0xDFFF) {
        bytes += 4
        i++
        continue
      }
    }
    bytes += codePointBytes(code)
  }
  return bytes
}

// One line, at most `max` characters. Full text is never rendered: it is what
// the widget types, not something it shows.
function previewText(text, max) {
  var limit = max === undefined || max === null ? PREVIEW_CHARS : Number(max)
  if (!isFinite(limit) || limit < 0) limit = PREVIEW_CHARS
  var collapsed = str(text).replace(/\s+/g, " ").trim()
  if (limit === 0) return ""
  if (collapsed.length <= limit) return collapsed
  return collapsed.slice(0, limit - 1) + "…"
}

// `cliphist list` prints one `<id>\t<preview>` line per entry, newest first;
// a binary entry previews as `[[ binary data … ]]` and has no text to type.
// The preview is cliphist's own: whitespace collapsed and cut to 100 runes,
// so a recent row cannot know its size; the worker enforces the byte cap.
function parseCliphist(text) {
  var kept = []
  var lines = str(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var tab = line.indexOf("\t")
    if (tab <= 0) continue
    var id = line.slice(0, tab)
    if (!/^[0-9]+$/.test(id)) continue
    var preview = line.slice(tab + 1)
    if (/^\[\[ binary data .*\]\]$/.test(preview)) continue
    if (preview.trim().length === 0) continue
    kept.push({ id: id, preview: preview })
  }
  return kept
}

function recentRows(entries, count) {
  var rows = []
  var limit = Number(count)
  if (!isFinite(limit) || limit <= 0) return rows
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length && rows.length < limit; i++) {
    var entry = list[i]
    if (!entry || !/^[0-9]+$/.test(str(entry.id))) continue
    rows.push({
      source: "recent",
      id: str(entry.id),
      // No `text`: the preview is truncated, so typing and pinning decode
      // the entry by id instead.
      preview: previewText(entry.preview),
      bytes: -1,
      tooLarge: false
    })
  }
  return rows
}

function entryRow(source, index, text, cap, name) {
  var bytes = sizeOf(text)
  var row = {
    source: source,
    index: index,
    text: text,
    preview: previewText(text),
    bytes: bytes,
    tooLarge: bytes > cap
  }
  if (name !== undefined) row.name = name
  return row
}

function byteCap(maxBytes) {
  var cap = Number(maxBytes)
  return isFinite(cap) && cap > 0 ? cap : Infinity
}

function parseSnippets(raw) {
  var config = { version: 1, snippets: [] }
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return config
  var snippets = Array.isArray(parsed.snippets) ? parsed.snippets : []
  for (var i = 0; i < snippets.length; i++) {
    var snippet = snippets[i]
    if (!snippet || typeof snippet !== "object" || Array.isArray(snippet)) continue
    if (typeof snippet.text !== "string" || snippet.text.trim().length === 0) continue
    config.snippets.push({
      name: str(snippet.name).trim() || previewText(snippet.text, NAME_CHARS),
      text: snippet.text
    })
  }
  return config
}

function snippetList(config) {
  return config && Array.isArray(config.snippets) ? config.snippets : []
}

function snippetRows(config, maxBytes) {
  var rows = []
  var cap = byteCap(maxBytes)
  var snippets = snippetList(config)
  for (var i = 0; i < snippets.length; i++) {
    var snippet = snippets[i]
    if (!snippet || typeof snippet.text !== "string") continue
    var name = str(snippet.name).trim() || previewText(snippet.text, NAME_CHARS)
    rows.push(entryRow("snippet", i, snippet.text, cap, name))
  }
  return rows
}

// The same text pinned twice is one snippet, and pinning an existing one
// moves it back to the top rather than duplicating it.
function pinSnippet(config, text, limit) {
  var max = limit === undefined || limit === null ? SNIPPET_LIMIT : Number(limit)
  if (!isFinite(max) || max < 0) max = SNIPPET_LIMIT
  var value = str(text)
  if (value.trim().length === 0) return config

  var next = { version: 1, snippets: [{ name: previewText(value, NAME_CHARS), text: value }] }
  var snippets = snippetList(config)
  for (var i = 0; i < snippets.length; i++) {
    var snippet = snippets[i]
    if (!snippet || typeof snippet.text !== "string") continue
    if (snippet.text === value) continue
    next.snippets.push({
      name: str(snippet.name).trim() || previewText(snippet.text, NAME_CHARS),
      text: snippet.text
    })
  }
  next.snippets = next.snippets.slice(0, max)
  return next
}

function removeSnippet(config, index) {
  var drop = Number(index)
  var next = { version: 1, snippets: [] }
  var snippets = snippetList(config)
  for (var i = 0; i < snippets.length; i++) {
    if (i === drop) continue
    var snippet = snippets[i]
    if (!snippet || typeof snippet.text !== "string") continue
    next.snippets.push({
      name: str(snippet.name).trim() || previewText(snippet.text, NAME_CHARS),
      text: snippet.text
    })
  }
  return next
}

function filterRows(rows, query) {
  var values = Array.isArray(rows) ? rows : []
  var needle = str(query).trim().toLowerCase()
  if (needle === "") return values.slice()
  var out = []
  for (var i = 0; i < values.length; i++) {
    var row = values[i]
    if (!row) continue
    var haystack = (str(row.preview) + " " + str(row.name)).toLowerCase()
    if (haystack.indexOf(needle) !== -1) out.push(row)
  }
  return out
}
