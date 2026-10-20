// Adapted from test/test_model.js of the owner's fork t1nk33r.browser-picker of
// K53N0/omarchy-browser-picker (MIT, Copyright (c) 2026 K53N0); see ../LICENSE.
// Behaviour tests for Model.js; tests/test-browser-picker.sh runs them with node.
//
// No framework on purpose: the plugin ships no node_modules, and a plugin the
// user is asked to trust should be readable end to end without one.

const assert = require("assert")
const M = require("../Model.js")

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (error) {
    console.error("FAIL: " + name)
    console.error("      " + error.message)
    process.exitCode = 1
  }
}

const NOW = 1_800_000_000

const ENTRIES = [
  { id: "google-chrome-stable:Default", label: "🌐  Chrome — Acme", browser: "Chrome", family: "chromium", bin: "google-chrome-stable", profile: "Default" },
  { id: "google-chrome-stable:Profile 17", label: "🌐  Chrome — Design Studio", browser: "Chrome", family: "chromium", bin: "google-chrome-stable", profile: "Profile 17" },
  { id: "chromium:Profile 19", label: "🧪  Chromium — Work", browser: "Chromium", family: "chromium", bin: "chromium", profile: "Profile 19" },
  { id: "firefox:dev", label: "🦊  Firefox — dev", browser: "Firefox", family: "firefox", bin: "firefox", profile: "dev" }
]

// ------------------------------------------------------------------ hostOf

test("hostOf strips scheme, path, port and userinfo", () => {
  assert.equal(M.hostOf("https://github.com/anthropics/claude"), "github.com")
  assert.equal(M.hostOf("http://user:pw@Portal.Example.COM:8443/x"), "portal.example.com")
  assert.equal(M.hostOf("example.com/path"), "example.com")
})

test("hostOf keeps IPv6 literals intact", () => {
  assert.equal(M.hostOf("http://[::1]:8080/admin"), "[::1]")
})

test("hostOf returns empty for things that are not URLs", () => {
  assert.equal(M.hostOf(""), "")
  assert.equal(M.hostOf("   "), "")
})

// ------------------------------------------------------------------- rules

test("a bare domain covers its subdomains", () => {
  assert.ok(M.ruleMatches("example.com", "example.com"))
  assert.ok(M.ruleMatches("example.com", "portal.example.com"))
})

test("a bare domain does not match a lookalike suffix", () => {
  assert.ok(!M.ruleMatches("example.com", "notexample.com"))
  assert.ok(!M.ruleMatches("example.com", "example.com.evil.net"))
})

test("*.domain covers subdomains but not the apex", () => {
  assert.ok(M.ruleMatches("*.example.com", "portal.example.com"))
  assert.ok(!M.ruleMatches("*.example.com", "example.com"))
})

test("the most specific rule wins regardless of order", () => {
  const rules = [
    { pattern: "example.com", entryId: "a" },
    { pattern: "docs.example.com", entryId: "b" }
  ]
  assert.equal(M.matchRule(rules, "docs.example.com").entryId, "b")
  assert.equal(M.matchRule(rules, "www.example.com").entryId, "a")
  assert.equal(M.matchRule(rules, "other.org"), null)
})

test("upsertRule replaces rather than duplicates a pattern", () => {
  let rules = M.upsertRule([], "example.com", "a", false)
  rules = M.upsertRule(rules, "example.com", "b", true)
  assert.equal(rules.length, 1)
  assert.equal(rules[0].entryId, "b")
  assert.equal(rules[0].learned, true)
})

test("parseConfig drops malformed rules instead of throwing", () => {
  const config = M.parseConfig('{"rules":[{"pattern":"a.com","entryId":"x"},{"pattern":""},null,7]}')
  assert.equal(config.rules.length, 1)
  assert.equal(M.parseConfig("not json").rules.length, 0)
})

// --------------------------------------------------------------- frecency

test("a recent choice outranks an old one with the same count", () => {
  const fresh = M.decayedScore({ count: 3, last: NOW }, NOW)
  const stale = M.decayedScore({ count: 3, last: NOW - 60 * 86400 }, NOW)
  assert.ok(fresh > stale * 4, `expected decay, got ${fresh} vs ${stale}`)
})

test("one host-specific hit beats heavy general use elsewhere", () => {
  let state = M.parseState("")
  // The personal profile is used constantly, but never for this host.
  for (let i = 0; i < 50; i++) state = M.recordChoice(state, "chromium:Profile 19", "", NOW)
  // The work profile was used for this host exactly once.
  state = M.recordChoice(state, "google-chrome-stable:Default", "github.com", NOW)

  const work = M.scoreFor(state, "google-chrome-stable:Default", "github.com", NOW)
  const personal = M.scoreFor(state, "chromium:Profile 19", "github.com", NOW)
  assert.ok(work > personal, `host signal must dominate: ${work} vs ${personal}`)
})

test("recordChoice does not mutate the state it was given", () => {
  const before = M.parseState("")
  const after = M.recordChoice(before, "a", "example.com", NOW)
  assert.equal(Object.keys(before.entries).length, 0)
  assert.equal(Object.keys(after.entries).length, 1)
  assert.equal(M.domainHits(after, "example.com", "a"), 1)
})

// ------------------------------------------------------------- rule offers

test("a permanent rule is offered only once the habit repeats", () => {
  const config = M.parseConfig("")
  let state = M.parseState("")
  const entry = ENTRIES[0]

  state = M.recordChoice(state, entry.id, "github.com", NOW)
  assert.ok(!M.shouldOfferRule(state, config, "github.com", entry, 3))
  state = M.recordChoice(state, entry.id, "github.com", NOW)
  state = M.recordChoice(state, entry.id, "github.com", NOW)
  assert.ok(M.shouldOfferRule(state, config, "github.com", entry, 3))
})

test("no offer for a host that already has a rule", () => {
  let state = M.parseState("")
  for (let i = 0; i < 5; i++) state = M.recordChoice(state, ENTRIES[0].id, "github.com", NOW)

  const withRule = M.parseConfig(JSON.stringify({
    rules: [{ pattern: "github.com", entryId: ENTRIES[0].id }]
  }))
  assert.ok(!M.shouldOfferRule(state, withRule, "github.com", ENTRIES[0], 3))
})

// ------------------------------------------------------------------ search

test("an fzf-style subsequence finds the profile", () => {
  assert.ok(M.fuzzyScore("🌐  Chrome — Design Studio", "chdes") >= 0)
  assert.ok(M.fuzzyScore("🌐  Chrome — Design Studio", "zzz") < 0)
})

test("a word-start match outranks a scattered one", () => {
  const wordStart = M.fuzzyScore("🌐  Chrome — Design", "des")
  const scattered = M.fuzzyScore("🧪  Chromium — Faded Rose", "des")
  assert.ok(wordStart > scattered, `${wordStart} should beat ${scattered}`)
})

// ----------------------------------------------------------------- ranking

test("a rule target outranks even the pinned bands", () => {
  const config = M.parseConfig(JSON.stringify({
    rules: [{ pattern: "example.com", entryId: "chromium:Profile 19" }]
  }))
  const ranked = M.rankEntries(ENTRIES, M.parseState(""), config, "example.com", "", NOW)
  assert.equal(ranked[0].id, "chromium:Profile 19")
})

test("a browser you actually use outranks a pinned generic row", () => {
  // Observed on the owner's machine: every browser with exactly one profile is
  // "generic" now that profiles are enumerated, so the generic band pinned
  // Helium (used twice) above Zen (used 24 times and the recorded destination
  // for claude.ai). The pre-selected row - what Enter opens - was the wrong
  // browser.
  const entries = [
    { id: "helium:Default", label: "🎈  Helium — You", family: "chromium", bin: "helium", profile: "Default", generic: true },
    { id: "zen-browser:t1ig2skk.Default (release)", label: "🧘  Zen — Default (release)", family: "firefox", bin: "zen", profile: "Default (release)", generic: false, default: true }
  ]
  const taught = M.parseState(JSON.stringify({
    entries: { "helium:Default": { count: 2, last: NOW }, "zen-browser:t1ig2skk.Default (release)": { count: 24, last: NOW } },
    domains: { "claude.ai zen-browser:t1ig2skk.Default (release)": { count: 4, last: NOW } }
  }))
  const ranked = M.rankEntries(entries, taught, M.parseConfig(""), "claude.ai", "", NOW)
  assert.equal(ranked[0].id, "zen-browser:t1ig2skk.Default (release)", "learned use decides before the bands")

  // With nothing learned the band still does its job.
  const cold = M.rankEntries(entries, M.parseState(""), M.parseConfig(""), "", "", NOW)
  assert.equal(cold[0].id, "helium:Default", "an untaught list is still ordered by the bands")
})

test("a query filters the list without losing the match", () => {
  const ranked = M.rankEntries(ENTRIES, M.parseState(""), M.parseConfig(""), "", "firefox", NOW)
  assert.equal(ranked.length, 1)
  assert.equal(ranked[0].id, "firefox:dev")
})

// A Firefox-family store whose profile the browser itself opens is not the one
// that sorts first by name: ids are the profile directories, labels are the
// names, and "Default (release)" loses an alphabetical race it should win.
const ZEN = [
  { id: "zen-browser:2z0zn07a.Default Profile", label: "🧘  Zen — Aaa Profile", browser: "Zen", family: "firefox", bin: "zen", profile: "Aaa Profile", generic: false, default: false },
  { id: "zen-browser:t1ig2skk.Default (release)", label: "🧘  Zen — Zzz Default", browser: "Zen", family: "firefox", bin: "zen", profile: "Zzz Default", generic: false, default: true }
]

test("the profile a browser opens by itself leads that browser's profiles", () => {
  const ranked = M.rankEntries(ZEN, M.parseState(""), M.parseConfig(""), "", "", NOW)
  assert.equal(ranked[0].id, "zen-browser:t1ig2skk.Default (release)")
})

test("a learned pick still beats the default profile of its own browser", () => {
  let state = M.parseState("")
  state = M.recordChoice(state, ZEN[0].id, "", NOW)
  const ranked = M.rankEntries(ZEN, state, M.parseConfig(""), "", "", NOW)
  assert.equal(ranked[0].id, ZEN[0].id, "the score must keep deciding")
})

test("the default flag never reorders one browser against another", () => {
  // Nothing learned, so both rows tie on score. A default-first layer applied
  // across browsers would pull Zen above Chrome for no reason the user gave.
  const mixed = [
    { id: "google-chrome-stable:Default", label: "🌐  Chrome — Acme", browser: "Chrome", family: "chromium", bin: "google-chrome-stable", profile: "Default", generic: false, default: false },
    { id: "google-chrome-stable:Profile 7", label: "🌐  Chrome — Work", browser: "Chrome", family: "chromium", bin: "google-chrome-stable", profile: "Profile 7", generic: false, default: true },
    ZEN[1],
    ZEN[0]
  ]
  const ranked = M.rankEntries(mixed, M.parseState(""), M.parseConfig(""), "", "", NOW)
  assert.deepEqual(ranked.map(e => e.id), [
    "google-chrome-stable:Profile 7",
    "google-chrome-stable:Default",
    "zen-browser:t1ig2skk.Default (release)",
    "zen-browser:2z0zn07a.Default Profile"
  ])
})

// --------------------------------------------------------------- launching

test("each family gets its own profile flag", () => {
  assert.deepEqual(
    M.launchArgs(ENTRIES[0], ["https://x.test"], []),
    ["--profile-directory=Default", "https://x.test"]
  )
  assert.deepEqual(
    M.launchArgs(ENTRIES[3], ["https://x.test"], []),
    ["-P", "dev", "https://x.test"]
  )
})

test("--incognito becomes --private-window for the Firefox family", () => {
  assert.deepEqual(
    M.launchArgs(ENTRIES[3], ["https://x.test"], ["--incognito"]),
    ["-P", "dev", "--private-window", "https://x.test"]
  )
  assert.deepEqual(
    M.launchArgs(ENTRIES[0], ["https://x.test"], ["--incognito"]),
    ["--profile-directory=Default", "--incognito", "https://x.test"]
  )
})

// The rows the fork added: a Flatpak whose launch command is an argv rather
// than a binary, a Chromium-family browser whose binary name says nothing
// about its family, and a browser whose family could not be established.
const FLATPAK_BRAVE = {
  id: "com.brave.Browser:Profile 2", label: "🦁  Brave (Flatpak) — Work",
  browser: "Brave (Flatpak)", family: "chromium", bin: "/usr/bin/flatpak",
  exec: ["/usr/bin/flatpak", "run", "--branch=stable", "--arch=x86_64",
         "--command=brave", "--file-forwarding", "com.brave.Browser"],
  profile: "Profile 2", generic: false
}
const FLATPAK_ZEN = {
  id: "app.zen_browser.zen:", label: "🧘  Zen (Flatpak)",
  browser: "Zen (Flatpak)", family: "firefox", bin: "/usr/bin/flatpak",
  exec: ["/usr/bin/flatpak", "run", "--branch=stable", "app.zen_browser.zen"],
  profile: "", generic: true
}
const HELIUM = {
  id: "helium:Default", label: "🎈  Helium — You", browser: "Helium",
  family: "chromium", bin: "helium-browser", exec: ["helium-browser"],
  profile: "Default", generic: true
}
const UNKNOWN = {
  id: "nomad-browser:", label: "🧭  Nomad", browser: "Nomad", family: "other",
  bin: "nomad-browser", exec: ["nomad-browser"], profile: "",
  generic: true
}

test("a Flatpak keeps its whole launch argv, not just the binary", () => {
  assert.deepEqual(
    M.launchArgv(FLATPAK_BRAVE, ["https://x.test"], []),
    ["/usr/bin/flatpak", "run", "--branch=stable", "--arch=x86_64",
     "--command=brave", "--file-forwarding", "com.brave.Browser",
     "--profile-directory=Profile 2", "https://x.test"]
  )
})

test("a Flatpak launches with no URL just as well", () => {
  assert.deepEqual(
    M.launchArgv(FLATPAK_ZEN, [], []),
    ["/usr/bin/flatpak", "run", "--branch=stable", "app.zen_browser.zen"]
  )
})

test("private browsing is translated per family, Flatpak included", () => {
  assert.deepEqual(
    M.launchArgv(FLATPAK_ZEN, ["https://x.test"], ["--incognito"]),
    ["/usr/bin/flatpak", "run", "--branch=stable", "app.zen_browser.zen",
     "--private-window", "https://x.test"]
  )
  assert.deepEqual(
    M.launchArgs(FLATPAK_BRAVE, [], ["--private-window"]),
    ["--profile-directory=Profile 2", "--incognito"]
  )
})

test("Helium launches by its own binary, with and without a URL", () => {
  assert.deepEqual(
    M.launchArgv(HELIUM, ["https://x.test"], []),
    ["helium-browser", "--profile-directory=Default", "https://x.test"]
  )
  assert.deepEqual(M.launchArgv(HELIUM, [], []), ["helium-browser", "--profile-directory=Default"])
  assert.deepEqual(
    M.launchArgv(HELIUM, [], ["--incognito"]),
    ["helium-browser", "--profile-directory=Default", "--incognito"]
  )
})

test("an unknown family drops the private flag rather than failing to launch", () => {
  assert.deepEqual(
    M.launchArgv(UNKNOWN, ["https://x.test"], ["--incognito"]),
    ["nomad-browser", "https://x.test"]
  )
  assert.deepEqual(
    M.launchArgv(UNKNOWN, ["https://x.test"], ["--new-window"]),
    ["nomad-browser", "--new-window", "https://x.test"]
  )
})

test("an entry with no exec array still launches by bin", () => {
  assert.deepEqual(
    M.launchArgv(ENTRIES[3], ["https://x.test"], []),
    ["firefox", "-P", "dev", "https://x.test"]
  )
})

// --------------------------------------------------------------- migration

test("the v2 bash rules file imports by label substring", () => {
  const legacy = [
    "# a comment",
    "",
    "example.com        Design Studio",
    "work.example.com   Work",
    "orphan.test        NoSuchProfile"
  ].join("\n")

  const rules = M.migrateLegacyRules(legacy, ENTRIES)
  assert.equal(rules.length, 2)
  assert.equal(rules[0].entryId, "google-chrome-stable:Profile 17")
  assert.equal(rules[1].entryId, "chromium:Profile 19")
})

// ----------------------------------------------------- generic entries

test("a browser with no separate profiles leads the list", () => {
  const entries = [
    { id: "google-chrome-stable:Default", label: "🌐  Chrome — Aaa", family: "chromium", bin: "google-chrome-stable", profile: "Default", generic: false },
    { id: "firefox:", label: "🦊  Firefox", family: "firefox", bin: "firefox", profile: "", generic: true }
  ]
  const ranked = M.rankEntries(entries, M.parseState(""), M.parseConfig(""), "", "", NOW)
  assert.equal(ranked[0].id, "firefox:", "the generic band leads the list")
})

test("genericFirst false puts it back in alphabetical order", () => {
  const entries = [
    { id: "google-chrome-stable:Default", label: "🌐  Chrome — Aaa", family: "chromium", bin: "google-chrome-stable", profile: "Default", generic: false },
    { id: "firefox:", label: "🦊  Firefox", family: "firefox", bin: "firefox", profile: "", generic: true }
  ]
  const config = M.parseConfig(JSON.stringify({ settings: { genericFirst: false } }))
  const ranked = M.rankEntries(entries, M.parseState(""), config, "", "", NOW)
  assert.equal(ranked[0].id, "google-chrome-stable:Default")
})

test("a typed query outranks the generic pin", () => {
  const entries = [
    { id: "chromium:Profile 19", label: "🧪  Chromium — Work", family: "chromium", bin: "chromium", profile: "Profile 19", generic: false },
    { id: "firefox:", label: "🦊  Firefox", family: "firefox", bin: "firefox", profile: "", generic: true }
  ]
  const ranked = M.rankEntries(entries, M.parseState(""), M.parseConfig(""), "", "work", NOW)
  assert.equal(ranked[0].id, "chromium:Profile 19", "search relevance must win while typing")
})

// ----------------------------------------------- learned ranking across a rename

const RENAMED = [
  { id: "zen-browser:t1ig2skk.Default (release)", label: "🧘  Zen — Default (release)", family: "firefox", bin: "zen", profile: "Default (release)", default: true },
  { id: "zen-browser:2z0zn07a.Default Profile", label: "🧘  Zen — Default Profile", family: "firefox", bin: "zen", profile: "Default Profile", default: false },
  { id: "helium:Default", label: "🎈  Helium — You", family: "chromium", bin: "helium", profile: "Default", default: true }
]

function stateWith(entries, domains) {
  return M.parseState(JSON.stringify({ entries: entries, domains: domains || {} }))
}

test("a profile renamed by id keeps the count it earned under the old id", () => {
  const before = stateWith({ "zen-browser:Default (release)": { count: 7, last: NOW } })
  const after = M.adoptRenamedEntries(before, RENAMED)
  assert.equal(after.state.entries["zen-browser:t1ig2skk.Default (release)"].count, 7)
  assert.ok(!("zen-browser:Default (release)" in after.state.entries), "the stranded id is gone")
  // The caller only writes the file when a move is reported, so an unreported
  // move is a migration that silently does not persist.
  assert.deepEqual(after.moves, [{
    from: "zen-browser:Default (release)",
    to: "zen-browser:t1ig2skk.Default (release)",
    bucket: "entries"
  }])
})

test("a browser whose profiles could not be enumerated lands on its default profile", () => {
  // The `<key>:` shape from before this browser's profiles were readable, and
  // the domain bucket that is the only record of where this host sends links.
  const before = stateWith({ "zen-browser:": { count: 24, last: NOW } },
                           { "claude.ai zen-browser:": { count: 4, last: NOW } })
  const after = M.adoptRenamedEntries(before, RENAMED)
  assert.equal(after.state.entries["zen-browser:t1ig2skk.Default (release)"].count, 24)
  assert.equal(after.state.domains["claude.ai zen-browser:t1ig2skk.Default (release)"].count, 4)
  assert.ok(!("claude.ai zen-browser:" in after.state.domains), "the stranded bucket is gone")
  assert.equal(after.moves.length, 2, "one entry move and one domain move, both reported")
  assert.deepEqual(after.moves.map(m => m.bucket).sort(), ["domains", "entries"])
})

test("counts merge rather than overwrite when both ids carry history", () => {
  const before = stateWith({
    "zen-browser:Default (release)": { count: 3, last: NOW - 100 },
    "zen-browser:t1ig2skk.Default (release)": { count: 2, last: NOW }
  })
  const after = M.adoptRenamedEntries(before, RENAMED)
  const merged = after.state.entries["zen-browser:t1ig2skk.Default (release)"]
  assert.equal(merged.count, 5, "both histories count")
  assert.equal(merged.last, NOW, "the newer timestamp wins")
})

test("an id a live entry still answers to is never moved", () => {
  const before = stateWith({ "helium:Default": { count: 9, last: NOW } })
  const after = M.adoptRenamedEntries(before, RENAMED)
  assert.equal(after.moves.length, 0)
  assert.equal(after.state.entries["helium:Default"].count, 9)
})

test("an unresolvable id is left alone rather than guessed at", () => {
  // A browser that is not installed any more, and a profile name no live entry
  // has: moving either would put one profile's history on another.
  const before = stateWith({
    "opera:Default": { count: 5, last: NOW },
    "zen-browser:Ancient Profile": { count: 5, last: NOW }
  })
  const after = M.adoptRenamedEntries(before, RENAMED)
  assert.equal(after.moves.length, 0)
  assert.equal(after.state.entries["opera:Default"].count, 5)
  assert.equal(after.state.entries["zen-browser:Ancient Profile"].count, 5)
})

test("two live profiles with the same name block the move", () => {
  // Two stores of the same browser can both call a profile "Default (release)".
  // Nothing here can say which one earned the count.
  const twins = [
    { id: "zen-browser:aaaa.Default (release)", family: "firefox", bin: "zen", profile: "Default (release)", default: true, label: "a" },
    { id: "zen-browser:bbbb.Default (release)", family: "firefox", bin: "zen", profile: "Default (release)", default: false, label: "b" }
  ]
  const before = stateWith({ "zen-browser:Default (release)": { count: 4, last: NOW } })
  const after = M.adoptRenamedEntries(before, twins)
  assert.equal(after.moves.length, 0, "ambiguity is not a coin flip")
})

test("adoption is idempotent", () => {
  const before = stateWith({ "zen-browser:": { count: 24, last: NOW } },
                           { "claude.ai zen-browser:": { count: 4, last: NOW } })
  const once = M.adoptRenamedEntries(before, RENAMED)
  const twice = M.adoptRenamedEntries(once.state, RENAMED)
  assert.equal(twice.moves.length, 0)
  assert.deepEqual(twice.state, once.state)
})

console.log(`${passed} passed`)
