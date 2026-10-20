.pragma library
// Adapted from the plugin-list and settings-form logic of SettingsPanel.qml
// and components/DynamicSettingsForm.qml in the owner's fork t1nk33r.settings
// 1.1.0 of AyushKr2003/shell-settings (MIT, Copyright (c) AyushKr2003); see
// LICENSE and UPSTREAM.md beside this file.
// haseen: rows from the shell's plugin registry (Haseen/Plugins.qml) and the
// haseen manifest settings schema ({type, default, description}); pure
// functions, so tests/test-settings-panel.sh runs them in the Qt JS engine.

var FILTERS = ["all", "enabled", "builtin", "installed", "readonly", "configurable"]

function str(v) {
  return v === undefined || v === null ? "" : String(v)
}

// Where a plugin lives decides what may be done to it. Only a directory
// directly under haseen's own plugin directory may be deleted: built-ins are
// part of the tree, and ~/.config/omarchy/plugins and
// ~/.config/DankMaterialShell/plugins are read-only sources (CLAUDE.md).
function deletableDir(dir, userPlugins) {
  var d = str(dir)
  var base = str(userPlugins).replace(/\/+$/, "")
  if (base === "" || d.indexOf(base + "/") !== 0) return ""
  var name = d.slice(base.length + 1).replace(/\/+$/, "")
  if (name === "" || name.indexOf("/") >= 0 || name === "." || name === "..") return ""
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name) ? name : ""
}

// registry: Plugins.registry; state(id): {listed, enabled}.
function rows(registry, state, userPlugins) {
  var out = []
  var ids = Object.keys(registry || {}).sort()
  for (var i = 0; i < ids.length; i++) {
    var rec = registry[ids[i]]
    if (!rec) continue
    var s = state(ids[i]) || {}
    var settings = rec.settings && typeof rec.settings === "object" ? rec.settings : {}
    var origin = str(rec.origin)
    out.push({
      id: ids[i],
      name: str(rec.name) || ids[i],
      description: str(rec.description),
      origin: origin,
      kinds: Array.isArray(rec.kinds) ? rec.kinds.slice() : [],
      valid: rec.valid === true,
      unmet: Array.isArray(rec.unmet) ? rec.unmet.slice() : [],
      errors: Array.isArray(rec.errors) ? rec.errors.slice() : [],
      listed: s.listed === true,
      enabled: s.enabled === true,
      settingKeys: Object.keys(settings).filter(function (k) { return k !== "debugIpc" }).sort(),
      readonly: origin === "omarchy" || origin === "dms",
      deleteName: deletableDir(rec.dir, userPlugins)
    })
  }
  return out
}

// The state a row shows, in the words `haseen plugin list` uses.
function stateLabel(row) {
  if (!row.valid) return "invalid"
  if (row.unmet.length > 0) return "unmet"
  if (!row.enabled) return "disabled"
  if (row.listed) return "enabled"
  return row.kinds.indexOf("bar-widget") >= 0 || row.kinds.indexOf("service") >= 0 ? "available" : "on demand"
}

function matchesFilter(row, filter) {
  switch (filter) {
  case "enabled": return row.enabled && row.listed
  case "builtin": return row.origin === "builtin"
  case "installed": return row.deleteName !== ""
  case "readonly": return row.readonly
  case "configurable": return row.settingKeys.length > 0
  default: return true
  }
}

function matchesQuery(row, query) {
  var words = str(query).toLowerCase().split(/\s+/).filter(function (w) { return w !== "" })
  var hay = (row.id + " " + row.name + " " + row.description + " " + row.origin).toLowerCase()
  for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
  return true
}

function filterRows(list, filter, query) {
  return (list || []).filter(function (r) { return matchesFilter(r, filter) && matchesQuery(r, query) })
}

function countFor(list, filter) {
  return filterRows(list, filter, "").length
}

// The text a form field shows for a value of a declared type.
function formatValue(type, value) {
  if (value === undefined || value === null) return ""
  if (type === "array" || type === "object") return JSON.stringify(value)
  return String(value)
}

// Parses what was typed into a field of a declared type:
// {ok: true, value} or {ok: false, error}.
function parseValue(type, text) {
  var t = str(text)
  switch (type) {
  case "boolean":
    if (t === "true") return { ok: true, value: true }
    if (t === "false") return { ok: true, value: false }
    return { ok: false, error: "true or false" }
  case "integer":
    if (!/^-?[0-9]+$/.test(t.trim())) return { ok: false, error: "a whole number" }
    return { ok: true, value: parseInt(t, 10) }
  case "number":
    var n = Number(t.trim())
    if (t.trim() === "" || !isFinite(n)) return { ok: false, error: "a number" }
    return { ok: true, value: n }
  case "array":
  case "object":
    try {
      var v = JSON.parse(t)
      if (type === "array" ? Array.isArray(v) : (v !== null && typeof v === "object" && !Array.isArray(v)))
        return { ok: true, value: v }
    } catch (e) {}
    return { ok: false, error: type === "array" ? "a JSON array" : "a JSON object" }
  default:
    return { ok: true, value: t }
  }
}

// One field per declared setting: the effective value (shell.json over the
// default) and whether shell.json sets it.
function fields(schema, current) {
  var out = []
  var keys = Object.keys(schema || {}).filter(function (k) { return k !== "debugIpc" }).sort()
  var cur = current && typeof current === "object" ? current : {}
  for (var i = 0; i < keys.length; i++) {
    var def = schema[keys[i]] || {}
    var set = Object.prototype.hasOwnProperty.call(cur, keys[i])
    out.push({
      key: keys[i],
      type: str(def.type) || "string",
      description: str(def.description),
      defaultValue: def["default"],
      value: set ? cur[keys[i]] : def["default"],
      set: set
    })
  }
  return out
}

// The request `haseen plugin settings ID` takes for staged edits: values to
// merge and keys to drop back to their defaults.
function request(id, edits, resets) {
  var changes = []
  var keys = Object.keys(edits || {}).sort()
  for (var i = 0; i < keys.length; i++)
    changes.push({ path: ["plugins", id, "settings", keys[i]], value: edits[keys[i]] })
  var drop = (resets || []).slice().sort()
  for (var j = 0; j < drop.length; j++)
    if (keys.indexOf(drop[j]) < 0) changes.push({ path: ["plugins", id, "settings", drop[j]], remove: true })
  return { changes: changes }
}

// Result lines of the delete batch: "ok <name>" or "fail <name> <reason>".
function deleteSummary(text) {
  var ok = [], failed = []
  var lines = str(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(ok|fail) (\S+)(?: (.*))?$/.exec(lines[i])
    if (!m) continue
    if (m[1] === "ok") ok.push(m[2])
    else failed.push({ name: m[2], reason: str(m[3]) })
  }
  return { ok: ok, failed: failed }
}
