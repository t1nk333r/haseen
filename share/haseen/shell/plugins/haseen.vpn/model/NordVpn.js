.pragma library
.import "Shared.js" as Shared

// Adapted from the owner's fork t1nk33r.vpn 1.4.1-t1nk33r.1 of
// jkoestinger/omarchy-vpn (MIT, Copyright (c) 2026 Justin Köstinger); see
// LICENSE, LICENSE.nordvpn and UPSTREAM.md beside this directory. Unchanged
// by the haseen port (plan 096) apart from this notice. The NordVPN
// vocabulary came from guiestrela/omarchy-norvpn-plugin (MIT, Copyright
// (c) 2026 Guilherme Estrela; LICENSE.nordvpn).

// NordVPN, via the `nordvpn` CLI talking to `nordvpnd`. Parsing and
// row-building only — the process plumbing lives in NordVpnBackend.qml.
//
// Merged from guiestrela/omarchy-norvpn-plugin (MIT), whose single-backend
// widget owned this vocabulary first. Its two allow-lists came across
// deliberately intact: they are the reason a country name printed by one CLI,
// or a code typed into shell.json by hand, can be handed to another CLI at
// all. Everything else was refolded into the shape the four other backends
// already have.

// ------------------------------------------------------------------ status

// `nordvpn` reports four kinds of "no" and they are not interchangeable:
//
//   denied     the calling user is not in the `nordvpn` group, so every
//              command — the reads included — is refused. Installed, one
//              command away from working, and *not* disconnected.
//   daemon     nordvpnd is not answering its socket.
//   loggedout  no account on this machine.
//   ""         nothing parsed. Unknown, which is not the same as down.
//
// The original folded every non-zero exit into one "Unavailable" and told the
// user the daemon was unreachable, which is the wrong fix for three of these
// four and the reason this machine's real state — a missing group membership —
// read as a dead daemon. Each is told apart here because each has its own fix.
function parseNordVpnStatus(raw) {
  var result = {
    state: "",
    connected: false,
    country: "",
    city: "",
    server: "",
    ip: "",
    technology: "",
    protocol: "",
    transfer: "",
    uptime: "",
    // The commands the CLI itself printed as the way out of `denied`, in the
    // order it printed them. Never invented here: a command this widget made
    // up is the one thing worse than no advice at all.
    remedies: [],
    statusText: ""
  }

  var text = String(raw || "")
  if (text.trim() === "") return result

  // Refusals first. They arrive with rc 1 and, on the permission path, on
  // stdout rather than stderr, so a reader keyed on the exit code alone takes
  // the advice for a status block — or throws it away.
  if (/permission denied/i.test(text)) {
    result.state = "denied"
    result.remedies = nordVpnRemedies(text)
    result.statusText = nordVpnStatusText(result.state)
    return result
  }
  if (/cannot reach.*daemon|daemon.*(not running|unreachable|not reachable)|connection refused|is nordvpnd running/i.test(text)) {
    result.state = "daemon"
    result.statusText = nordVpnStatusText(result.state)
    return result
  }
  if (/(you are )?not logged in|log ?in before|please log ?in/i.test(text)) {
    result.state = "loggedout"
    result.statusText = nordVpnStatusText(result.state)
    return result
  }

  var status = nordVpnField(text, ["Status"])
  var normalized = status.toLowerCase()
  if (normalized.indexOf("connected") === 0) result.state = "connected"
  else if (normalized.indexOf("connecting") === 0) result.state = "connecting"
  else if (normalized.indexOf("reconnecting") === 0) result.state = "connecting"
  else if (normalized.indexOf("disconnecting") === 0) result.state = "disconnecting"
  else if (normalized.indexOf("disconnected") === 0) result.state = "disconnected"

  result.connected = result.state === "connected"
  result.country = nordVpnField(text, ["Country"])
  result.city = nordVpnField(text, ["City"])
  // The key naming the server moved between clients: 3.x printed `Current
  // server`, 5.x prints `Hostname`. Matching on the leading key of a line
  // rather than on line position is what lets one parser read both.
  result.server = nordVpnField(text, ["Hostname", "Current server", "Server"])
  result.ip = nordVpnField(text, ["IP", "Server IP", "Your new IP"])
  result.technology = nordVpnField(text, ["Current technology", "Technology"])
  result.protocol = nordVpnField(text, ["Current protocol", "Protocol"])
  result.transfer = nordVpnField(text, ["Transfer"])
  result.uptime = nordVpnField(text, ["Uptime"])
  result.statusText = nordVpnStatusText(result.state)
  return result
}

// First of the named keys that answers.
function nordVpnField(text, names) {
  for (var i = 0; i < names.length; i++) {
    var match = String(text).match(new RegExp("^[ \\t]*" + names[i] + "[ \\t]*:[ \\t]*(.+)$", "im"))
    if (match) {
      var value = match[1].trim()
      if (value !== "") return value
    }
  }
  return ""
}

// The `sudo` lines out of the permission refusal, verbatim, so the user can
// paste what the tool actually asked for — `$USER` included, since that is
// what it prints and what their shell will expand. Shape-checked all the same:
// this text ends up on a clipboard, and a line that does not read like one of
// those commands is not offered as one.
function nordVpnRemedies(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!/^sudo [a-z][a-zA-Z0-9 _$.,\/=+-]{0,79}$/.test(line)) continue
    if (out.indexOf(line) === -1) out.push(line)
    if (out.length === 4) break
  }
  return out
}

function nordVpnStatusText(state) {
  if (state === "connected") return "Connected"
  if (state === "connecting") return "Connecting"
  if (state === "disconnecting") return "Disconnecting"
  if (state === "disconnected") return "Disconnected"
  if (state === "denied") return "Permission denied"
  if (state === "daemon") return "Daemon unreachable"
  if (state === "loggedout") return "Not logged in"
  return "Unknown"
}

function nordVpnLocation(status) {
  var parts = []
  if (status.city !== "") parts.push(status.city)
  if (status.country !== "") parts.push(nordVpnCountryLabel(status.country))
  return parts.join(", ")
}

// `blocked` is the kill switch, read from the settings rather than from the
// status: NordVPN never reports "traffic is being dropped right now", so the
// only honest source is the setting that causes it.
//
// Nothing here that changes on its own may appear in this string. It is half
// of the controller's `connectionKey`, so a summary carrying the transfer
// counters or the uptime would turn one public-IP lookup per connection into
// one per poll — see nordVpnDetails, which is where those belong.
function nordVpnSummary(status, blocked) {
  var location = nordVpnLocation(status)

  if (status.state === "connected") {
    if (location !== "" && status.server !== "") return status.server + " · " + location
    if (location !== "") return location
    if (status.server !== "") return status.server
    return "Connected"
  }
  if (status.state === "connecting") return location !== "" ? "Connecting to " + location + "…" : "Connecting…"
  if (status.state === "disconnecting") return "Disconnecting…"
  // Installed, refusing, and one group membership away from working. Not down.
  if (status.state === "denied") return "Permission denied — this user is not in the nordvpn group"
  if (status.state === "daemon") return "The NordVPN daemon is not answering"
  if (status.state === "loggedout") return "No NordVPN account on this machine"
  if (status.state === "disconnected") return blocked === true ? "Not connected · traffic blocked" : "Not connected"
  return "Checking…"
}

// One line saying what to do about a refusal. `denied` is the only one whose
// fix is two commands rather than one, so it points at the rows below rather
// than trying to fit them into a sentence nobody can select.
function nordVpnActionHint(status) {
  if (status.state === "denied") {
    return status.remedies.length > 0
      ? "NordVPN refuses every command, reads included, until this user is in the nordvpn group. "
        + "Run both commands below, then log out and back in."
      : "NordVPN refuses every command until this user is in the nordvpn group. "
        + "Add it with usermod, then log out and back in."
  }
  if (status.state === "daemon") return "The NordVPN daemon is not answering. Start it with: sudo systemctl start nordvpnd"
  if (status.state === "loggedout") return "No NordVPN account on this machine. Log in with: nordvpn login"
  return ""
}

// Rows carrying a command to the clipboard rather than a tunnel to bring up.
// They are `targets` because that is where the user is already looking when
// the tool has nothing else to offer, and because a two-command fix reads
// better as two copyable rows than as a paragraph that cannot be selected.
function nordVpnRemedyTargets(status) {
  if (status.state !== "denied") return []
  var rows = []
  for (var i = 0; i < status.remedies.length; i++) {
    rows.push({
      key: "remedy:" + i,
      label: status.remedies[i],
      detail: "Click to copy",
      glyph: Shared.GLYPH_CLIPBOARD,
      copy: status.remedies[i]
    })
  }
  return rows
}

function nordVpnDetails(status) {
  if (status.state !== "connected") return []

  var rows = [Shared.detail("Server", status.server), Shared.detail("Location", nordVpnLocation(status))]
  if (status.ip !== "") rows.push(Shared.detail("Exit IP", status.ip))
  if (status.technology !== "") {
    rows.push(Shared.detail("Tunnel", status.protocol !== ""
      ? status.technology + " · " + status.protocol
      : status.technology))
  }
  if (status.transfer !== "") rows.push(Shared.detail("Transfer", status.transfer))
  if (status.uptime !== "") rows.push(Shared.detail("Uptime", status.uptime))
  return rows.filter(function(row) { return row.value !== "" })
}

// --------------------------------------------------------------- countries

// Ported from guiestrela/omarchy-norvpn-plugin. Two-letter codes are what
// `nordvpn connect` and `nordvpn set autoconnect` take most reliably, and they
// are what `favoriteCountries` is written in, so the name the CLI printed is
// looked up here rather than passed through.
var NORDVPN_COUNTRY_CODES = {
  "argentina": "ar", "australia": "au", "austria": "at", "belgium": "be",
  "botswana": "bw", "brazil": "br", "bulgaria": "bg", "canada": "ca",
  "chile": "cl", "colombia": "co", "costa rica": "cr", "croatia": "hr",
  "cyprus": "cy", "czech republic": "cz", "denmark": "dk", "estonia": "ee",
  "finland": "fi", "france": "fr", "georgia": "ge", "germany": "de",
  "greece": "gr", "hong kong": "hk", "hungary": "hu", "iceland": "is",
  "india": "in", "indonesia": "id", "ireland": "ie", "israel": "il",
  "italy": "it", "japan": "jp", "latvia": "lv", "luxembourg": "lu",
  "malaysia": "my", "mexico": "mx", "moldova": "md", "netherlands": "nl",
  "new zealand": "nz", "nigeria": "ng", "norway": "no", "poland": "pl",
  "portugal": "pt", "romania": "ro", "serbia": "rs", "singapore": "sg",
  "slovakia": "sk", "slovenia": "si", "south africa": "za",
  "south korea": "kr", "spain": "es", "sweden": "se", "switzerland": "ch",
  "taiwan": "tw", "thailand": "th", "turkey": "tr", "ukraine": "ua",
  "united arab emirates": "ae", "united kingdom": "uk",
  "united states": "us", "vietnam": "vn"
}

// The CLI spells a multi-word country with underscores in the older clients
// and with spaces in the newer ones. A row is built from whichever arrived and
// reads back as prose either way.
function nordVpnCountryLabel(name) {
  return String(name || "").trim().replace(/_/g, " ").replace(/\s+/g, " ")
}

function nordVpnCountryCode(name) {
  var code = NORDVPN_COUNTRY_CODES[nordVpnCountryLabel(name).toLowerCase()]
  return code ? code.toUpperCase() : ""
}

// The value that may go on an argv, validated. Ported from guiestrela's
// `autoConnectTarget` and now the single gate for *every* country argument —
// `connect` included, which in the original went straight from a line of
// `nordvpn countries` output onto the command line. Widened only to allow the
// underscore form the CLI itself prints, and tightened to refuse a leading
// "-": argv carries no shell, but a value that reads as a flag is still a
// value the CLI will act on.
function nordVpnCountryArg(value) {
  var target = String(value || "").trim()
  if (target === "" || target.charAt(0) === "-") return ""
  if (/^[a-z]{2}[0-9]*$/i.test(target)) return target.toLowerCase()
  var code = NORDVPN_COUNTRY_CODES[target.toLowerCase().replace(/_/g, " ").replace(/\s+/g, " ")]
  if (code) return code
  // A country this build has no code for is still connectable, so the shape a
  // country name can have is allowed through — and nothing else.
  return /^[a-z][a-z0-9 _.'-]{1,63}$/i.test(target) ? target : ""
}

// Auto-connect is stricter than connect: it is the one country value that
// comes out of the widget's own settings, where anything at all can be typed,
// and it is stored in the daemon rather than used once. A two-letter code and
// nothing else — a name is accepted only as far as the code table can resolve
// it, and an unresolvable one leaves auto-connect without a country, which is
// a valid way to run it.
function nordVpnAutoConnectArg(value) {
  var target = String(value || "").trim()
  if (target === "") return ""
  if (/^[A-Za-z]{2}$/.test(target)) return target.toLowerCase()
  var code = NORDVPN_COUNTRY_CODES[target.toLowerCase().replace(/_/g, " ").replace(/\s+/g, " ")]
  return code ? code : ""
}

// `nordvpn countries` prints a padded column block in some clients and a
// comma-separated run in others, so the separators are read as a set rather
// than assumed. Anything not shaped like a country name is dropped instead of
// becoming a row that cannot be connected to.
function parseNordVpnCountries(raw) {
  var lines = String(raw || "").split("\n")
  var seen = {}
  var out = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*countries:?\s*$/i.test(line)) continue
    var tokens = line.split(/,|\t| {2,}/)
    for (var j = 0; j < tokens.length; j++) {
      var token = tokens[j].trim()
      if (token === "" || !/^[A-Za-z][A-Za-z0-9 _.'-]{1,63}$/.test(token)) continue
      var label = nordVpnCountryLabel(token)
      var key = label.toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      out.push({ name: label, code: nordVpnCountryCode(label), value: label.replace(/ /g, "_") })
    }
  }

  out.sort(function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) })
  return out
}

function nordVpnCountryKey(country) {
  var code = String(country.code || "")
  return "country:" + (code !== "" ? code : String(country.name || "").toUpperCase())
}

// NordVPN's own idea of a default connection: `nordvpn connect` with no target
// picks the fastest server it can find.
function nordVpnQuickTargets() {
  return [
    { key: "quick", label: "Fastest server", detail: "Let NordVPN choose", glyph: Shared.GLYPH_BOLT, args: [] }
  ]
}

function nordVpnCountryTargets(countries, favorites, filter) {
  var needle = String(filter || "").trim().toLowerCase()
  var favored = []
  var rest = []

  for (var i = 0; i < countries.length; i++) {
    var country = countries[i]
    if (needle !== "" && (country.name + " " + country.code).toLowerCase().indexOf(needle) < 0) continue

    var target = {
      key: nordVpnCountryKey(country),
      label: country.name,
      detail: country.code,
      glyph: Shared.GLYPH_VPN,
      args: [country.value]
    }
    if (needle === "" && country.code !== "" && favorites.indexOf(country.code) >= 0) favored.push(target)
    else rest.push(target)
  }

  return favored.concat(rest)
}

// Which row to tick. `nordvpn status` names the country in prose, so it is
// looked back up in the list the rows were built from — and failing that, in
// the code table, which covers the stretch before that list has loaded.
function nordVpnCurrentKey(status, countries) {
  if (status.state !== "connected" && status.state !== "connecting") return ""
  var name = nordVpnCountryLabel(status.country).toLowerCase()
  if (name === "") return ""

  for (var i = 0; i < countries.length; i++) {
    if (String(countries[i].name).toLowerCase() === name) return nordVpnCountryKey(countries[i])
  }
  var code = nordVpnCountryCode(name)
  return code !== "" ? "country:" + code : ""
}

// ------------------------------------------------------------------- argv

function nordVpnConnectArgs(target) {
  if (!target) return []
  // A row carrying something to copy is not a tunnel to bring up.
  if (target.copy !== undefined) return []

  var args = target.args || []
  if (args.length === 0) return ["connect"]
  var value = nordVpnCountryArg(args[0])
  return value === "" ? [] : ["connect", value]
}

function nordVpnDisconnectArgs() {
  return ["disconnect"]
}

// ---------------------------------------------------------------- settings

// One switch per setting, in the order the panel draws them: security first,
// because that is what a VPN widget is for. The two entries carrying `on`/`off`
// are enums of exactly two values, which is the only reason they fit a switch
// at all — see the note in ARCHITECTURE.md about what did not fit.
//
// `verb` is what `nordvpn set` calls the setting, which is not what `nordvpn
// settings` calls it: the printed key is "Kill Switch", the verb is
// "killswitch", and "Post-quantum VPN" is set with "post-quantum". Both
// vocabularies sit side by side here rather than being translated twice.
var NORDVPN_TOGGLE_SPEC = [
  { key: "firewall", label: "Firewall", detail: "Block traffic that would leave outside the tunnel", verb: "firewall" },
  { key: "kill-switch", label: "Kill switch", detail: "No traffic at all if the tunnel drops", verb: "killswitch" },
  { key: "threat-protection-lite", label: "Threat Protection Lite", detail: "Block ads, trackers and malware hosts", verb: "threatprotectionlite" },
  { key: "auto-connect", label: "Connect on startup", detail: "Up as soon as the daemon starts", verb: "autoconnect" },
  { key: "technology", label: "NordLynx", detail: "Off runs OpenVPN instead", verb: "technology", on: "NORDLYNX", off: "OPENVPN" },
  { key: "protocol", label: "TCP", detail: "Off uses UDP, which is faster", verb: "protocol", on: "TCP", off: "UDP" },
  { key: "meshnet", label: "Meshnet", detail: "Reach your own devices through NordVPN", verb: "meshnet" },
  { key: "lan-discovery", label: "LAN discovery", detail: "Reach printers and NAS while up", verb: "lan-discovery", onValue: "enable", offValue: "disable" },
  { key: "routing", label: "Routing", detail: "Send any traffic through the tunnel", verb: "routing" },
  { key: "virtual-location", label: "Virtual location", detail: "Offer servers hosted outside the country they present", verb: "virtual-location" },
  { key: "post-quantum-vpn", label: "Post-quantum VPN", detail: "A key exchange that cannot be recorded now and broken later", verb: "post-quantum" },
  { key: "notify", label: "NordVPN notifications", detail: "The CLI's own connect and disconnect notices", verb: "notify" },
  { key: "tray", label: "NordVPN tray icon", detail: "The tray applet that ships with the CLI", verb: "tray" }
]

function nordVpnSpec(key) {
  for (var i = 0; i < NORDVPN_TOGGLE_SPEC.length; i++) {
    if (NORDVPN_TOGGLE_SPEC[i].key === key) return NORDVPN_TOGGLE_SPEC[i]
  }
  return null
}

// Some clients qualify a value — "enabled (Switzerland)" for auto-connect — so
// the parenthetical comes off before the value is read.
function nordVpnSettingValue(raw) {
  return String(raw || "").trim().replace(/\s*\(.*\)\s*$/, "").trim()
}

function nordVpnSettingEnabled(value) {
  return /^(enabled|on|yes|true)$/i.test(nordVpnSettingValue(value))
}

// `nordvpn settings` prints "Key: value" lines, sometimes under a heading and
// sometimes indented. Only the keys the spec knows are recorded, and `seen` is
// which of those actually answered: an unanswered setting is unknown, not off.
// Reporting the kill switch as off while it is on is the one mistake this
// widget must not make.
function parseNordVpnSettings(raw) {
  var settings = { values: {}, seen: {}, loaded: false }
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([^:]+):\s*(.*?)\s*$/)
    if (!match) continue
    var key = match[1].trim().toLowerCase().replace(/\s+/g, "-")
    var value = match[2].trim()
    if (value === "" || nordVpnSpec(key) === null) continue
    settings.values[key] = value
    settings.seen[key] = true
    settings.loaded = true
  }
  return settings
}

function nordVpnToggleValue(settings, spec) {
  var raw = settings.values[spec.key]
  if (spec.on !== undefined) return nordVpnSettingValue(raw).toUpperCase() === spec.on
  return nordVpnSettingEnabled(raw)
}

// A switch is drawn only for a setting the CLI answered for, so a client that
// does not have one — `protocol` exists only while the technology is OpenVPN —
// shows one fewer switch rather than a confident wrong one.
function nordVpnToggles(settings, autoConnectCountry) {
  if (!settings || !settings.loaded) return []

  var country = nordVpnAutoConnectArg(autoConnectCountry)
  var toggles = []
  for (var i = 0; i < NORDVPN_TOGGLE_SPEC.length; i++) {
    var spec = NORDVPN_TOGGLE_SPEC[i]
    if (settings.seen[spec.key] !== true) continue
    var detail = spec.detail
    if (spec.key === "auto-connect" && country !== "") {
      detail = "Connects to " + country.toUpperCase() + " as soon as the daemon starts"
    }
    toggles.push(Shared.toggle(spec.key, spec.label, detail, nordVpnToggleValue(settings, spec)))
  }
  return toggles
}

// The kill switch drops every packet while the tunnel is down, which is what
// the controller warns about before taking this backend down for another one.
function nordVpnBlocked(settings) {
  return settings.seen["kill-switch"] === true && nordVpnSettingEnabled(settings.values["kill-switch"])
}

// Ported allow-list: a setting is settable only if the spec names it, and only
// to the two values the spec allows. Nothing typed into shell.json reaches
// `nordvpn set` as a verb or as a value.
function nordVpnToggleArgs(key, value, autoConnectCountry) {
  var spec = nordVpnSpec(key)
  if (spec === null) return []

  var argument = spec.on !== undefined
    ? (value ? spec.on : spec.off)
    : (value ? (spec.onValue || "on") : (spec.offValue || "off"))
  var args = ["set", spec.verb, argument]

  // Auto-connect takes an optional country, and it is the one place a widget
  // setting becomes a command argument — hence the stricter validator.
  if (spec.key === "auto-connect" && value === true) {
    var country = nordVpnAutoConnectArg(autoConnectCountry)
    if (country !== "") args.push(country)
  }
  return args
}

// Ported from guiestrela: NordVPN refuses to change routing while Meshnet is
// on, and says so in a sentence that means nothing to anyone who has not read
// the manual.
function nordVpnExplainError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  if (/routing is currently used by meshnet/i.test(value)) {
    return "Routing cannot be changed while Meshnet is on. Turn Meshnet off first."
  }
  if (/permission denied/i.test(value)) {
    return "NordVPN refused: this user is not in the nordvpn group."
  }
  return Shared.elide(value || "NordVPN refused that setting", 140)
}
