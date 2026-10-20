// From the tests of the owner's fork t1nk33r.vpn of jkoestinger/omarchy-vpn
// (MIT, Copyright (c) 2026 Justin Köstinger); see ../LICENSE. Unchanged by the
// haseen port (plan 096); tests/test-vpn.sh runs them with node.
// NordVPN: the status block and its three refusals, the country list, the
// settings switches, and every argv this backend can build.
const { test, eq, NordVpn } = require("../harness.js")

// The exact text `nordvpn` 5.3.0 prints — on stdout, with exit code 1 — for a
// user who is not in its group. This is the state the machine this backend was
// merged on is actually in, so it is the case the parser was written against.
const DENIED = [
  "Permission denied. Please grant necessary permissions before using the application by executing the following commands:",
  "",
  "sudo groupadd nordvpn",
  "sudo usermod -aG nordvpn $USER",
  "",
  "After doing so, reboot your device afterwards for this to take an effect."
].join("\n")

const CONNECTED = [
  "Status: Connected",
  "Hostname: ch123.nordvpn.com",
  "IP: 194.187.251.1",
  "Country: Switzerland",
  "City: Zurich",
  "Current technology: NORDLYNX",
  "Current protocol: UDP",
  "Transfer: 1.23 MiB received, 456.78 KiB sent",
  "Uptime: 5 minutes 3 seconds"
].join("\n")

test("parseNordVpnStatus reads a connected block", () => {
  const status = NordVpn.parseNordVpnStatus(CONNECTED)
  eq(status.state, "connected")
  eq(status.connected, true)
  eq(status.server, "ch123.nordvpn.com")
  eq(status.city, "Zurich")
  eq(status.technology, "NORDLYNX")
  eq(NordVpn.nordVpnSummary(status, false), "ch123.nordvpn.com · Zurich, Switzerland")
})

test("parseNordVpnStatus reads the server key by whichever name it arrived under", () => {
  // 3.x said "Current server", 5.x says "Hostname".
  eq(NordVpn.parseNordVpnStatus("Status: Connected\nCurrent server: nl42.nordvpn.com").server,
    "nl42.nordvpn.com")
  eq(NordVpn.parseNordVpnStatus("Status: Connected\nHostname: nl42.nordvpn.com").server,
    "nl42.nordvpn.com")
})

test("parseNordVpnStatus tells the permission refusal apart from every other no", () => {
  const denied = NordVpn.parseNordVpnStatus(DENIED)
  eq(denied.state, "denied")
  eq(denied.connected, false)
  // Verbatim, `$USER` included: it is what the tool printed and what the
  // user's shell will expand.
  eq(denied.remedies, ["sudo groupadd nordvpn", "sudo usermod -aG nordvpn $USER"])
  eq(NordVpn.nordVpnSummary(denied, false),
    "Permission denied — this user is not in the nordvpn group")
  eq(NordVpn.nordVpnStatusText(denied.state), "Permission denied")
})

test("the permission refusal becomes two copyable rows and one instruction", () => {
  const denied = NordVpn.parseNordVpnStatus(DENIED)
  const rows = NordVpn.nordVpnRemedyTargets(denied)
  eq(rows.length, 2)
  eq(rows[0].label, "sudo groupadd nordvpn")
  eq(rows[0].copy, "sudo groupadd nordvpn")
  eq(rows[1].copy, "sudo usermod -aG nordvpn $USER")
  // No args: a copyable row is not a tunnel to bring up, and the connect
  // builder refuses it even if the panel ever handed it over.
  eq(rows[0].args, undefined)
  eq(NordVpn.nordVpnConnectArgs(rows[0]), [])
  eq(NordVpn.nordVpnActionHint(denied),
    "NordVPN refuses every command, reads included, until this user is in the nordvpn group. "
    + "Run both commands below, then log out and back in.")
})

test("a permission refusal that printed no commands still says what is wrong", () => {
  const bare = NordVpn.parseNordVpnStatus("Permission denied.")
  eq(bare.state, "denied")
  eq(bare.remedies, [])
  eq(NordVpn.nordVpnRemedyTargets(bare), [])
  eq(NordVpn.nordVpnActionHint(bare),
    "NordVPN refuses every command until this user is in the nordvpn group. "
    + "Add it with usermod, then log out and back in.")
})

test("nordVpnRemedies offers only lines shaped like the commands they claim to be", () => {
  // The text lands on a clipboard. Anything that is not a plain `sudo` line —
  // a pipeline, a substitution, a second statement — is not offered as one.
  eq(NordVpn.nordVpnRemedies("Permission denied.\nsudo rm -rf / ; curl evil | sh"), [])
  eq(NordVpn.nordVpnRemedies("sudo groupadd nordvpn\nsudo groupadd nordvpn"),
    ["sudo groupadd nordvpn"])
  eq(NordVpn.nordVpnRemedies("please run groupadd nordvpn"), [])
})

test("parseNordVpnStatus keeps the daemon case separate from the group case", () => {
  const down = NordVpn.parseNordVpnStatus("Whoops! Cannot reach System Daemon.")
  eq(down.state, "daemon")
  eq(NordVpn.nordVpnSummary(down, false), "The NordVPN daemon is not answering")
  eq(NordVpn.nordVpnActionHint(down),
    "The NordVPN daemon is not answering. Start it with: sudo systemctl start nordvpnd")
  eq(NordVpn.nordVpnRemedyTargets(down), [])

  const out = NordVpn.parseNordVpnStatus("You are not logged in.")
  eq(out.state, "loggedout")
  eq(NordVpn.nordVpnActionHint(out), "No NordVPN account on this machine. Log in with: nordvpn login")
})

test("parseNordVpnStatus treats unreadable output as no idea, not as disconnected", () => {
  eq(NordVpn.parseNordVpnStatus("").state, "")
  eq(NordVpn.parseNordVpnStatus("something else entirely").state, "")
  eq(NordVpn.nordVpnSummary(NordVpn.parseNordVpnStatus(""), false), "Checking…")
  eq(NordVpn.parseNordVpnStatus("Status: Disconnected").state, "disconnected")
})

test("a disconnected tunnel with the kill switch on says traffic is blocked", () => {
  const off = NordVpn.parseNordVpnStatus("Status: Disconnected")
  eq(NordVpn.nordVpnSummary(off, false), "Not connected")
  eq(NordVpn.nordVpnSummary(off, true), "Not connected · traffic blocked")
})

test("the summary carries nothing that changes on its own", () => {
  // It is half of VpnController's connectionKey, so a summary that moved with
  // the transfer counters would turn one public-IP lookup per connection into
  // one per poll.
  const first = NordVpn.parseNordVpnStatus(CONNECTED)
  const later = NordVpn.parseNordVpnStatus(CONNECTED
    .replace("1.23 MiB received, 456.78 KiB sent", "9.87 MiB received, 1.20 MiB sent")
    .replace("5 minutes 3 seconds", "41 minutes 9 seconds"))
  eq(NordVpn.nordVpnSummary(later, false), NordVpn.nordVpnSummary(first, false))
  // They are not lost, they are just not in the line the controller watches.
  eq(NordVpn.nordVpnDetails(later).filter(r => r.label === "Transfer")[0].value,
    "9.87 MiB received, 1.20 MiB sent")
})

test("nordVpnDetails only reports rows while a tunnel is up", () => {
  eq(NordVpn.nordVpnDetails(NordVpn.parseNordVpnStatus("Status: Disconnected")), [])
  eq(NordVpn.nordVpnDetails(NordVpn.parseNordVpnStatus(DENIED)), [])
  eq(NordVpn.nordVpnDetails(NordVpn.parseNordVpnStatus(CONNECTED)).map(r => r.label),
    ["Server", "Location", "Exit IP", "Tunnel", "Transfer", "Uptime"])
})

test("parseNordVpnCountries reads the padded column form", () => {
  const countries = NordVpn.parseNordVpnCountries([
    "Albania\t\t\tArgentina\t\tAustralia\t\tAustria",
    "Bosnia_And_Herzegovina\tBrazil\t\t\tSwitzerland\t\tUnited_States"
  ].join("\n"))
  eq(countries.map(c => c.name), [
    "Albania", "Argentina", "Australia", "Austria",
    "Bosnia And Herzegovina", "Brazil", "Switzerland", "United States"
  ])
  eq(countries.filter(c => c.name === "Switzerland")[0], {
    name: "Switzerland", code: "CH", value: "Switzerland"
  })
  // The underscore form is what goes back on the command line for a country
  // with no code of its own.
  eq(countries.filter(c => c.name === "Bosnia And Herzegovina")[0],
    { name: "Bosnia And Herzegovina", code: "", value: "Bosnia_And_Herzegovina" })
})

test("parseNordVpnCountries reads the comma form and the header line alike", () => {
  eq(NordVpn.parseNordVpnCountries("Countries:\nSwitzerland, Netherlands, United_States")
    .map(c => c.code), ["NL", "CH", "US"])
  eq(NordVpn.parseNordVpnCountries(""), [])
  // Dedupes across separators and lines rather than listing a country twice.
  eq(NordVpn.parseNordVpnCountries("Brazil, Brazil\nBrazil").length, 1)
})

test("nordVpnCountryTargets puts favorites first and keys rows by code", () => {
  const countries = NordVpn.parseNordVpnCountries("Switzerland, Netherlands, Albania")
  eq(NordVpn.nordVpnCountryTargets(countries, ["NL"], "").map(t => t.label),
    ["Netherlands", "Albania", "Switzerland"])
  eq(NordVpn.nordVpnCountryTargets(countries, [], "swit").map(t => t.key), ["country:CH"])
  eq(NordVpn.nordVpnCountryTargets(countries, [], "ch").map(t => t.key), ["country:CH"])
  // A country with no code is still keyed by something stable.
  eq(NordVpn.nordVpnCountryTargets(countries, [], "alba")[0].key, "country:ALBANIA")
})

test("nordVpnCurrentKey looks the connected country back up", () => {
  const countries = NordVpn.parseNordVpnCountries("Switzerland, Albania")
  eq(NordVpn.nordVpnCurrentKey(NordVpn.parseNordVpnStatus(CONNECTED), countries), "country:CH")
  // Before the list has loaded, the code table still answers.
  eq(NordVpn.nordVpnCurrentKey(NordVpn.parseNordVpnStatus(CONNECTED), []), "country:CH")
  eq(NordVpn.nordVpnCurrentKey(NordVpn.parseNordVpnStatus("Status: Disconnected\nCountry: Switzerland"),
    countries), "")
})

test("nordVpnConnectArgs builds the connect vector, or none at all", () => {
  eq(NordVpn.nordVpnConnectArgs({ key: "quick", args: [] }), ["connect"])
  eq(NordVpn.nordVpnConnectArgs({ args: ["Switzerland"] }), ["connect", "ch"])
  eq(NordVpn.nordVpnConnectArgs({ args: ["Bosnia_And_Herzegovina"] }),
    ["connect", "Bosnia_And_Herzegovina"])
  eq(NordVpn.nordVpnConnectArgs({ args: ["nl"] }), ["connect", "nl"])
  eq(NordVpn.nordVpnConnectArgs(null), [])
  eq(NordVpn.nordVpnDisconnectArgs(), ["disconnect"])
})

test("a country value that reads as a flag is refused, not passed", () => {
  // `nordvpn countries` is where these come from, and the original widget put
  // that line straight onto the command line. A value starting with "-" would
  // be read as an option by the next process.
  eq(NordVpn.nordVpnCountryArg("--help"), "")
  eq(NordVpn.nordVpnCountryArg("-Switzerland"), "")
  eq(NordVpn.nordVpnConnectArgs({ args: ["--version"] }), [])
  eq(NordVpn.nordVpnCountryArg("Costa Rica; rm -rf /"), "")
  eq(NordVpn.nordVpnCountryArg("$(id)"), "")
  eq(NordVpn.nordVpnCountryArg(""), "")
  // And the shapes that are allowed through.
  eq(NordVpn.nordVpnCountryArg("costa rica"), "cr")
  eq(NordVpn.nordVpnCountryArg("Costa_Rica"), "cr")
  eq(NordVpn.nordVpnCountryArg("Côte d'Ivoire"), "")
  eq(NordVpn.nordVpnCountryArg("Cote d'Ivoire"), "Cote d'Ivoire")
})

test("the auto-connect country is stricter than a connect target", () => {
  // It comes out of the widget's own settings, where anything can be typed,
  // and the daemon stores it rather than using it once.
  eq(NordVpn.nordVpnAutoConnectArg("ch"), "ch")
  eq(NordVpn.nordVpnAutoConnectArg("CH"), "ch")
  eq(NordVpn.nordVpnAutoConnectArg("Switzerland"), "ch")
  eq(NordVpn.nordVpnAutoConnectArg("switzerland"), "ch")
  // No code for it: auto-connect runs without a country rather than with a
  // value the daemon would store and refuse.
  eq(NordVpn.nordVpnAutoConnectArg("Bosnia_And_Herzegovina"), "")
  eq(NordVpn.nordVpnAutoConnectArg("us1"), "")
  eq(NordVpn.nordVpnAutoConnectArg("--help"), "")
  eq(NordVpn.nordVpnAutoConnectArg(""), "")
})

test("parseNordVpnSettings records only the keys it knows, and only if answered", () => {
  const settings = NordVpn.parseNordVpnSettings([
    "Technology: OPENVPN",
    "Protocol: UDP",
    "Firewall: enabled",
    "Firewall Mark: 0xe1f1",
    "Kill Switch: disabled",
    "Threat Protection Lite: disabled",
    "Auto-connect: disabled",
    "LAN Discovery: disabled",
    "Post-quantum VPN: disabled"
  ].join("\n"))
  eq(settings.loaded, true)
  eq(settings.values["kill-switch"], "disabled")
  // Not in the spec, so not recorded: a switch nobody wrote a label for is not
  // drawn from a machine-generated one.
  eq(settings.values["firewall-mark"], undefined)
  eq(NordVpn.nordVpnToggles(settings, "").map(t => t.key), [
    "firewall", "kill-switch", "threat-protection-lite", "auto-connect",
    "technology", "protocol", "lan-discovery", "post-quantum-vpn"
  ])

  const none = NordVpn.parseNordVpnSettings("")
  eq(none.loaded, false)
  eq(NordVpn.nordVpnToggles(none, ""), [])
  // A refusal is not a report that everything is off.
  eq(NordVpn.parseNordVpnSettings(DENIED).loaded, false)
})

test("a setting the CLI did not answer for draws no switch", () => {
  // `Protocol` exists only while the technology is OpenVPN, so a NordLynx
  // client shows one fewer switch rather than a confident wrong one.
  const lynx = NordVpn.parseNordVpnSettings("Technology: NORDLYNX\nKill Switch: enabled")
  eq(NordVpn.nordVpnToggles(lynx, "").map(t => t.key), ["kill-switch", "technology"])
  eq(NordVpn.nordVpnToggles(lynx, "").filter(t => t.key === "technology")[0].value, true)
  eq(NordVpn.nordVpnBlocked(lynx), true)
  eq(NordVpn.nordVpnBlocked(NordVpn.parseNordVpnSettings("Firewall: enabled")), false)
})

test("a qualified value still reads as the value", () => {
  const qualified = NordVpn.parseNordVpnSettings("Auto-connect: enabled (Switzerland)")
  eq(NordVpn.nordVpnToggles(qualified, "")[0].value, true)
  eq(NordVpn.nordVpnSettingEnabled("enabled (Switzerland)"), true)
  eq(NordVpn.nordVpnSettingEnabled("disabled"), false)
})

test("the auto-connect switch names the country it will use", () => {
  const settings = NordVpn.parseNordVpnSettings("Auto-connect: disabled")
  eq(NordVpn.nordVpnToggles(settings, "")[0].detail, "Up as soon as the daemon starts")
  eq(NordVpn.nordVpnToggles(settings, "Switzerland")[0].detail,
    "Connects to CH as soon as the daemon starts")
})

test("nordVpnToggleArgs speaks each setting's own vocabulary", () => {
  eq(NordVpn.nordVpnToggleArgs("firewall", true, ""), ["set", "firewall", "on"])
  eq(NordVpn.nordVpnToggleArgs("kill-switch", false, ""), ["set", "killswitch", "off"])
  eq(NordVpn.nordVpnToggleArgs("threat-protection-lite", true, ""),
    ["set", "threatprotectionlite", "on"])
  eq(NordVpn.nordVpnToggleArgs("post-quantum-vpn", true, ""), ["set", "post-quantum", "on"])
  // LAN discovery is the one that takes enable/disable rather than on/off.
  eq(NordVpn.nordVpnToggleArgs("lan-discovery", true, ""), ["set", "lan-discovery", "enable"])
  eq(NordVpn.nordVpnToggleArgs("lan-discovery", false, ""), ["set", "lan-discovery", "disable"])
  // The two enums of exactly two values.
  eq(NordVpn.nordVpnToggleArgs("technology", true, ""), ["set", "technology", "NORDLYNX"])
  eq(NordVpn.nordVpnToggleArgs("technology", false, ""), ["set", "technology", "OPENVPN"])
  eq(NordVpn.nordVpnToggleArgs("protocol", true, ""), ["set", "protocol", "TCP"])
  eq(NordVpn.nordVpnToggleArgs("protocol", false, ""), ["set", "protocol", "UDP"])
  eq(NordVpn.nordVpnToggleArgs("meshnet", true, ""), ["set", "meshnet", "on"])
  eq(NordVpn.nordVpnToggleArgs("routing", false, ""), ["set", "routing", "off"])
  eq(NordVpn.nordVpnToggleArgs("virtual-location", true, ""), ["set", "virtual-location", "on"])
  eq(NordVpn.nordVpnToggleArgs("notify", false, ""), ["set", "notify", "off"])
  eq(NordVpn.nordVpnToggleArgs("tray", true, ""), ["set", "tray", "on"])
})

test("nordVpnToggleArgs appends the auto-connect country, and only a valid one", () => {
  eq(NordVpn.nordVpnToggleArgs("auto-connect", true, "ch"), ["set", "autoconnect", "on", "ch"])
  eq(NordVpn.nordVpnToggleArgs("auto-connect", true, "Switzerland"),
    ["set", "autoconnect", "on", "ch"])
  eq(NordVpn.nordVpnToggleArgs("auto-connect", true, ""), ["set", "autoconnect", "on"])
  eq(NordVpn.nordVpnToggleArgs("auto-connect", true, "; rm -rf /"), ["set", "autoconnect", "on"])
  eq(NordVpn.nordVpnToggleArgs("auto-connect", true, "--config=/etc/shadow"),
    ["set", "autoconnect", "on"])
  // Turning it off never carries a country.
  eq(NordVpn.nordVpnToggleArgs("auto-connect", false, "ch"), ["set", "autoconnect", "off"])
})

test("nordVpnToggleArgs refuses a setting the spec does not name", () => {
  // The allow-list is the whole point: nothing typed into shell.json becomes a
  // `nordvpn set` verb.
  eq(NordVpn.nordVpnToggleArgs("nonsense", true, ""), [])
  eq(NordVpn.nordVpnToggleArgs("dns", true, ""), [])
  eq(NordVpn.nordVpnToggleArgs("", true, ""), [])
})

test("nordVpnExplainError translates the refusals worth translating", () => {
  eq(NordVpn.nordVpnExplainError("Error: routing is currently used by Meshnet."),
    "Routing cannot be changed while Meshnet is on. Turn Meshnet off first.")
  eq(NordVpn.nordVpnExplainError("Permission denied."),
    "NordVPN refused: this user is not in the nordvpn group.")
  eq(NordVpn.nordVpnExplainError(""), "NordVPN refused that setting")
})
