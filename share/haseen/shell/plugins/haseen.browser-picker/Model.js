// Adapted from Model.js of K53N0/omarchy-browser-picker (MIT, Copyright (c)
// 2026 K53N0), via the owner's fork t1nk33r.browser-picker 1.0.0-t1nk33r.1;
// see LICENSE and UPSTREAM.md beside this file.
// haseen change: the routing file (~/.config/haseen/browser-picker.json)
// holds the rules only; the four settings are the plugin's own settings in
// shell.json, so serializeConfig writes no `settings` and the service merges
// parseSettings(plugin settings) into the config it ranks with.
//
// Pure helpers: free of QML types and imports, so the same file loads in the
// shell and under node (tests/test-browser-picker.sh). Everything here is a
// plain function over plain data.

var CONFIG_VERSION = 1
var STATE_VERSION = 1

// A profile you picked two months ago should not outrank one you picked this
// morning. Two weeks is long enough that a habit survives a holiday, short
// enough that last quarter's project stops shadowing this one.
var HALF_LIFE_DAYS = 14

// A host-specific hit outweighs any amount of general use. Opening GitHub in
// the work profile once is a stronger signal about GitHub than a hundred
// unrelated launches of the personal one.
var DOMAIN_WEIGHT = 1000

// ---------------------------------------------------------------- utilities

function stringValue(value) {
  return String(value === undefined || value === null ? "" : value)
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Host of a URL, lowercased, without userinfo or port. Returns "" for the
// things that are not URLs at all — a bare search term, a file path — because
// those carry no routing signal.
function hostOf(url) {
  var text = stringValue(url).trim()
  if (!text) return ""
  var rest = text
  var schemeEnd = rest.indexOf("://")
  if (schemeEnd >= 0) rest = rest.slice(schemeEnd + 3)
  else if (rest.indexOf(":") >= 0 && rest.indexOf(".") < 0) return ""
  rest = rest.split("/")[0]
  rest = rest.split("?")[0]
  rest = rest.split("#")[0]
  var at = rest.lastIndexOf("@")
  if (at >= 0) rest = rest.slice(at + 1)
  // An IPv6 literal is full of colons, so the port can only be found after the
  // closing bracket. Splitting on ":" first would cut "[::1]" down to "[".
  if (rest.charAt(0) === "[") {
    var close = rest.indexOf("]")
    rest = close >= 0 ? rest.slice(0, close + 1) : rest
  } else {
    rest = rest.split(":")[0]
  }
  return rest.toLowerCase()
}

// ------------------------------------------------------------------- config

// FORK CHANGE - upstream's list also carried a "manage profiles" row per
// browser, opening the browser's own profile screen, and a `manageFirst`
// setting that pinned those rows to the top. Both are gone: with seven browsers
// installed that was seven housekeeping rows above every real destination, and
// the pre-selected row — the one Enter opens — was "Brave (Flatpak) — manage
// profiles" (observed on screen). This picker exists to open a link, so the
// scanner no longer emits those rows and there is nothing left to order or to
// toggle. A config still carrying `manageFirst` is read and dropped, exactly
// like any other key this version does not know.

var DEFAULT_SETTINGS = {
  // Apply a matching rule without showing the picker. Turning this off keeps
  // the rules as ranking hints only, which is the gentler way to live with
  // rules you are not yet sure about.
  autoOpenRules: true,
  // Offer to turn a repeated choice into a rule.
  learnRules: true,
  // How many times the same host must go to the same profile first.
  promptAfter: 3,
  // Keep browsers that have no separate profiles at the top of the list. They
  // are otherwise scattered alphabetically among dozens of named profiles,
  // which buries the simplest choice — "just open Firefox" — the deepest.
  genericFirst: true
}

function parseSettings(raw) {
  var given = isObject(raw) ? raw : {}
  var after = parseInt(given.promptAfter, 10)
  return {
    autoOpenRules: given.autoOpenRules !== false,
    learnRules: given.learnRules !== false,
    promptAfter: isFinite(after) ? Math.max(2, Math.min(20, after)) : DEFAULT_SETTINGS.promptAfter,
    genericFirst: given.genericFirst !== false
  }
}

function parseConfig(raw) {
  var parsed = null
  try { parsed = JSON.parse(stringValue(raw)) } catch (e) { parsed = null }
  if (!isObject(parsed)) parsed = {}

  var rules = []
  if (Array.isArray(parsed.rules)) {
    for (var i = 0; i < parsed.rules.length; i++) {
      var rule = parsed.rules[i]
      if (!isObject(rule)) continue
      var pattern = stringValue(rule.pattern).trim().toLowerCase()
      var entryId = stringValue(rule.entryId).trim()
      if (!pattern || !entryId) continue
      rules.push({ pattern: pattern, entryId: entryId, learned: rule.learned === true })
    }
  }
  return {
    version: CONFIG_VERSION,
    settings: parseSettings(parsed.settings),
    rules: rules
  }
}

function serializeConfig(config) {
  return JSON.stringify({
    version: CONFIG_VERSION,
    rules: (config && config.rules) || []
  }, null, 2) + "\n"
}

// A bare domain covers its subdomains; an explicit `*.` prefix covers only
// them. Matching the host itself against "*.example.com" would surprise
// anyone who wrote that pattern to mean "every subdomain but the apex".
function ruleMatches(pattern, host) {
  if (!pattern || !host) return false
  if (pattern.indexOf("*.") === 0) {
    var bare = pattern.slice(2)
    return host !== bare && endsWithLabel(host, bare)
  }
  return host === pattern || endsWithLabel(host, pattern)
}

function endsWithLabel(host, suffix) {
  if (host.length <= suffix.length) return false
  return host.slice(-(suffix.length + 1)) === "." + suffix
}

// The most specific rule wins, so a rule for docs.example.com is not shadowed
// by one for example.com regardless of the order they were written in.
function matchRule(rules, host) {
  if (!Array.isArray(rules) || !host) return null
  var best = null
  for (var i = 0; i < rules.length; i++) {
    if (!ruleMatches(rules[i].pattern, host)) continue
    if (!best || rules[i].pattern.length > best.pattern.length) best = rules[i]
  }
  return best
}

// Rules matching a typed query, by pattern or by the profile they point at.
// The full rules window needs it once the list outgrows a glance.
function filterRules(rules, query) {
  var needle = stringValue(query).trim().toLowerCase()
  if (!needle) return rules || []
  return (rules || []).filter(function (rule) {
    return rule.pattern.indexOf(needle) >= 0
      || stringValue(rule.entryId).toLowerCase().indexOf(needle) >= 0
  })
}

function removeRule(rules, pattern) {
  var needle = stringValue(pattern).trim().toLowerCase()
  return (rules || []).filter(function (rule) { return rule.pattern !== needle })
}

function upsertRule(rules, pattern, entryId, learned) {
  var needle = stringValue(pattern).trim().toLowerCase()
  if (!needle || !entryId) return rules || []
  var next = removeRule(rules, needle)
  next.push({ pattern: needle, entryId: stringValue(entryId), learned: learned === true })
  next.sort(function (a, b) { return a.pattern < b.pattern ? -1 : 1 })
  return next
}

// -------------------------------------------------------------------- state

function parseState(raw) {
  var parsed = null
  try { parsed = JSON.parse(stringValue(raw)) } catch (e) { parsed = null }
  if (!isObject(parsed)) parsed = {}
  return {
    version: STATE_VERSION,
    entries: isObject(parsed.entries) ? parsed.entries : {},
    domains: isObject(parsed.domains) ? parsed.domains : {}
  }
}

function serializeState(state) {
  return JSON.stringify({
    version: STATE_VERSION,
    entries: (state && state.entries) || {},
    domains: (state && state.domains) || {}
  }, null, 2) + "\n"
}

function domainKey(host, entryId) {
  // A space, not the NUL byte this used to carry: a literal NUL in the source
  // makes the file binary to git and grep, and it is invisible in an editor.
  // Hostnames cannot contain spaces, so the first one is always the separator
  // and no two different pairs can collide on the same key.
  return stringValue(host) + " " + stringValue(entryId)
}

// Exponential decay on a count. Not a true frecency (which keeps every visit
// timestamp) — one count plus one timestamp costs a fraction of the storage
// and ranks the same way for the sizes this deals with.
function decayedScore(stat, nowSeconds) {
  if (!isObject(stat)) return 0
  var count = Number(stat.count) || 0
  if (count <= 0) return 0
  var last = Number(stat.last) || 0
  var ageDays = Math.max(0, (Number(nowSeconds) - last) / 86400)
  return count * Math.pow(0.5, ageDays / HALF_LIFE_DAYS)
}

function scoreFor(state, entryId, host, nowSeconds) {
  var general = decayedScore(state.entries[entryId], nowSeconds)
  if (!host) return general
  var specific = decayedScore(state.domains[domainKey(host, entryId)], nowSeconds)
  return specific * DOMAIN_WEIGHT + general
}

function bump(bucket, key, nowSeconds) {
  var previous = isObject(bucket[key]) ? bucket[key] : { count: 0, last: 0 }
  bucket[key] = { count: (Number(previous.count) || 0) + 1, last: Number(nowSeconds) || 0 }
}

function recordChoice(state, entryId, host, nowSeconds) {
  var next = {
    version: STATE_VERSION,
    entries: {},
    domains: {}
  }
  var key
  for (key in state.entries) next.entries[key] = state.entries[key]
  for (key in state.domains) next.domains[key] = state.domains[key]

  bump(next.entries, stringValue(entryId), nowSeconds)
  if (host) bump(next.domains, domainKey(host, entryId), nowSeconds)
  return next
}

// How many times this exact host went to this exact profile. What the offer to
// make a rule permanent is counted against.
function domainHits(state, host, entryId) {
  var stat = state.domains[domainKey(host, entryId)]
  return isObject(stat) ? (Number(stat.count) || 0) : 0
}

// Offer a permanent rule only once the habit is established, and never for a
// host that already has one.
function shouldOfferRule(state, config, host, entry, promptAfter) {
  if (!host || !entry) return false
  var threshold = Math.max(2, Number(promptAfter) || 3)
  if (matchRule(config.rules, host)) return false
  return domainHits(state, host, entry.id) >= threshold
}

// ------------------------------------------------------------------ ranking

// Subsequence match, the way fzf reads a query: "chdes" finds
// "Chrome — Design Studio". Scoring rewards runs of adjacent characters and
// matches that start a word, so typing "des" ranks "Design" above a profile
// that merely contains d, e and s scattered across it.
function fuzzyScore(text, query) {
  var haystack = stringValue(text).toLowerCase()
  var needle = stringValue(query).toLowerCase().replace(/\s+/g, "")
  if (!needle) return 0
  var score = 0
  var index = 0
  var previousMatch = -2
  for (var i = 0; i < needle.length; i++) {
    var found = haystack.indexOf(needle.charAt(i), index)
    if (found < 0) return -1
    score += 1
    if (found === previousMatch + 1) score += 4
    var before = found > 0 ? haystack.charAt(found - 1) : " "
    if (before === " " || before === "—" || before === "-" || before === ".") score += 3
    previousMatch = found
    index = found + 1
  }
  // A short label matching the whole query beats a long one that merely
  // contains it.
  return score - haystack.length * 0.01
}

function matches(entry, query) {
  if (!query) return true
  return fuzzyScore(entry.label, query) >= 0
}

// Which band an entry sits in when nothing has been typed. Lower sorts first.
//
// The bands only apply to the unfiltered list. Once there is a query, pinning
// a row above a closer text match fights the search instead of helping it —
// typing "chrome" has to rank the Chrome profiles by how well they match, not
// re-order them by band.
function rankBand(entry, settings) {
  if (entry.generic === true && settings.genericFirst !== false) return 1
  return 2
}

// Which browser a row belongs to, for the layers that must reorder rows within
// one browser without touching the order of the browsers themselves. The id's
// prefix, not the display name: the prefix is the scanner's own browser key,
// while two rows can be shown under names that only differ by a suffix.
function browserOf(entry) {
  var id = stringValue(entry && entry.id)
  var cut = id.indexOf(":")
  return cut >= 0 ? id.slice(0, cut) : id
}

// The list the picker shows.
function rankEntries(entries, state, config, host, query, nowSeconds) {
  var rule = host ? matchRule(config.rules, host) : null
  var ruleId = rule ? rule.entryId : ""
  var settings = config.settings || {}

  var scored = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var fuzzy = query ? fuzzyScore(entry.label, query) : 0
    if (query && fuzzy < 0) continue
    scored.push({
      entry: entry,
      // A rule for this host is the answer for this link, so it outranks every
      // band. Only reachable with "apply rules automatically" off — otherwise
      // the link opens without a list to rank.
      isRuleTarget: entry.id === ruleId,
      band: rankBand(entry, settings),
      browser: browserOf(entry),
      // The profile this browser opens when it is started without -P or
      // --profile-directory, as resolved by the scanner from the browser's own
      // records — not the first profile it happens to list.
      isDefault: entry["default"] === true,
      fuzzy: fuzzy,
      score: scoreFor(state, entry.id, host, nowSeconds)
    })
  }

  scored.sort(function (a, b) {
    if (a.isRuleTarget !== b.isRuleTarget) return a.isRuleTarget ? -1 : 1
    if (query) {
      if (b.fuzzy !== a.fuzzy) return b.fuzzy - a.fuzzy
      if (b.score !== a.score) return b.score - a.score
    } else {
      // FORK CHANGE - the bands used to sit above the score, which was
      // survivable while a "generic" row meant a browser with no profiles at
      // all. Now that profiles are enumerated for every browser, a browser
      // with exactly one profile is generic too - so on this host Helium (used
      // twice) was pinned above Zen (used 24 times, and the recorded
      // destination for claude.ai, score 3271 against 2). Learned use decides
      // first; the bands order everything the user has not taught it.
      if (b.score !== a.score) return b.score - a.score
      if (a.band !== b.band) return a.band - b.band
    }
    // Inside one browser, the profile it would have opened by itself leads its
    // siblings. Deliberately below the score and scoped to a single browser:
    // what the user actually picks must keep deciding which browser comes
    // first, and a default profile is only a better guess than another profile
    // of the same browser, never than a profile of a browser you use more.
    if (a.browser === b.browser && a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1
    return a.entry.label < b.entry.label ? -1 : 1
  })

  return scored.map(function (item) { return item.entry })
}

function entryById(entries, id) {
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].id === id) return entries[i]
  }
  return null
}

// ----------------------------------------------------------------- launching

// Every spelling of "open this privately" that reaches the picker. Which one a
// browser understands is a property of its family, so a flag has to be
// translated on the way through rather than passed on trust.
var PRIVATE_FLAGS = ["--incognito", "--inprivate", "--private-window", "--private"]

function isPrivateFlag(flag) {
  return PRIVATE_FLAGS.indexOf(flag) >= 0
}

// argv for one launch, without the binary. Kept here rather than in the shim
// so the same rules are visible to the tests.
//
// Omarchy always passes --incognito, because omarchy-launch-browser decides the
// private flag by grepping the default browser's --help for MOZ_LOG and this
// picker answers that probe with silence. Translating it for the Firefox family
// is therefore not an edge case, it is the normal path.
function launchArgs(entry, urls, flags) {
  var args = []
  if (!entry) return args

  if (entry.profile) {
    if (entry.family === "firefox") args.push("-P", entry.profile)
    else args.push("--profile-directory=" + entry.profile)
  }

  var list = flags || []
  for (var i = 0; i < list.length; i++) {
    var flag = list[i]
    if (entry.family === "firefox" && (flag === "--incognito" || flag === "--inprivate")) {
      args.push("--private-window")
    } else if (entry.family === "chromium" && (flag === "--private-window" || flag === "--private")) {
      args.push("--incognito")
    } else if (isPrivateFlag(flag) && entry.family !== "firefox" && entry.family !== "chromium") {
      // A browser whose family could not be established has no private-window
      // flag we can name. Dropping it opens an ordinary window; passing a
      // guess opens nothing at all, and losing the link is the worse failure.
      continue
    } else {
      args.push(flag)
    }
  }

  var targets = urls || []
  for (var u = 0; u < targets.length; u++) args.push(targets[u])
  return args
}

// The launch prefix: what to run before any of the arguments above. A Flatpak's
// entry point is `flatpak run --branch=… <app-id>`, not a binary of its own, so
// the scanner hands over the whole argv and `bin` is only its first token.
function launchPrefix(entry) {
  if (!entry) return []
  if (Array.isArray(entry.exec) && entry.exec.length) return entry.exec.slice()
  return entry.bin ? [entry.bin] : []
}

// The complete, ready-to-run argv for one choice.
function launchArgv(entry, urls, flags) {
  return launchPrefix(entry).concat(launchArgs(entry, urls, flags))
}

// ----------------------------------------------------------------- migration

// Import the v2 bash chooser's rules file. Its target was a case-insensitive
// substring of the menu label, so resolve it against the live entries the same
// way the old script did: first label that contains it.
function migrateLegacyRules(text, entries) {
  var rules = []
  var lines = stringValue(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var parts = line.split(/\s+/)
    if (parts.length < 2) continue
    var pattern = parts[0].toLowerCase()
    var target = parts.slice(1).join(" ").toLowerCase()
    for (var e = 0; e < entries.length; e++) {
      if (entries[e].label.toLowerCase().indexOf(target) >= 0) {
        rules.push({ pattern: pattern, entryId: entries[e].id, learned: false })
        break
      }
    }
  }
  return rules
}

// Carry learned ranking across an entry-id rename. Two renames have happened:
// firefox-family ids went from `<key>:<profile name>` to `<key>:<profile dir>`
// (the directory survives a profile rename, the name does not), and before
// that a browser whose profiles could not be enumerated was one bare `<key>:`
// row. Both leave counters stranded under an id no live entry answers to, and
// the domain buckets are the loss that shows: `claude.ai zen-browser:` is the
// only record that this host wants Zen, and a stranded bucket stops routing
// links there.
//
// Only unambiguous moves are made: same browser key, and either the same
// profile name or - for the bare `<key>:` shape - that browser's default
// profile. Anything else is left alone rather than guessed at, because a wrong
// move puts one profile's history on another.
function adoptRenamedEntries(state, entries) {
  var live = {}, byName = {}, defaults = {}, ambiguous = {}
  var i, entry, key
  for (i = 0; i < entries.length; i++) {
    entry = entries[i]
    if (!entry) continue
    live[stringValue(entry.id)] = true
    key = stringValue(entry.id).split(":")[0]
    var named = key + ":" + stringValue(entry.profile)
    byName[named] = byName[named] === undefined ? stringValue(entry.id) : ambiguous
    if (entry.default) {
      defaults[key] = defaults[key] === undefined ? stringValue(entry.id) : ambiguous
    }
  }

  function targetFor(id) {
    var colon = stringValue(id).indexOf(":")
    if (colon < 0) return ""
    var browser = id.substring(0, colon)
    var profile = id.substring(colon + 1)
    var found = profile === "" ? defaults[browser] : byName[browser + ":" + profile]
    if (typeof found !== "string" || found === id || live[id]) return ""
    return found
  }

  function merge(bucket, from, to) {
    var a = isObject(bucket[from]) ? bucket[from] : null
    var b = isObject(bucket[to]) ? bucket[to] : null
    if (!a) return
    bucket[to] = {
      count: (a.count || 0) + (b ? (b.count || 0) : 0),
      last: Math.max(Number(a.last) || 0, b ? (Number(b.last) || 0) : 0)
    }
    delete bucket[from]
  }

  var next = { version: STATE_VERSION, entries: {}, domains: {} }
  for (key in state.entries) next.entries[key] = state.entries[key]
  for (key in state.domains) next.domains[key] = state.domains[key]
  var moves = []

  for (key in state.entries) {
    var to = targetFor(key)
    if (!to) continue
    merge(next.entries, key, to)
    moves.push({ from: key, to: to, bucket: "entries" })
  }
  for (key in state.domains) {
    // `<host> <entryId>`: hostnames cannot contain spaces, so the first one
    // separates them.
    var space = key.indexOf(" ")
    if (space < 0) continue
    var host = key.substring(0, space)
    var domainTo = targetFor(key.substring(space + 1))
    if (!domainTo) continue
    merge(next.domains, key, domainKey(host, domainTo))
    moves.push({ from: key, to: domainKey(host, domainTo), bucket: "domains" })
  }

  return { state: next, moves: moves }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    HALF_LIFE_DAYS: HALF_LIFE_DAYS,
    DOMAIN_WEIGHT: DOMAIN_WEIGHT,
    hostOf: hostOf,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    parseSettings: parseSettings,
    parseConfig: parseConfig,
    serializeConfig: serializeConfig,
    ruleMatches: ruleMatches,
    matchRule: matchRule,
    upsertRule: upsertRule,
    removeRule: removeRule,
    filterRules: filterRules,
    parseState: parseState,
    serializeState: serializeState,
    decayedScore: decayedScore,
    scoreFor: scoreFor,
    recordChoice: recordChoice,
    domainHits: domainHits,
    shouldOfferRule: shouldOfferRule,
    fuzzyScore: fuzzyScore,
    matches: matches,
    rankEntries: rankEntries,
    entryById: entryById,
    launchArgs: launchArgs,
    launchPrefix: launchPrefix,
    launchArgv: launchArgv,
    isPrivateFlag: isPrivateFlag,
    migrateLegacyRules: migrateLegacyRules,
    adoptRenamedEntries: adoptRenamedEntries
  }
}
