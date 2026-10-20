// Adapted from NordVpnBackend.qml of the owner's fork t1nk33r.vpn 1.4.1-t1nk33r.1
// of jkoestinger/omarchy-vpn (MIT, Copyright (c) 2026 Justin Köstinger); see
// LICENSE, LICENSE.nordvpn and UPSTREAM.md beside this file.
// haseen (plan 096): `command -v` instead of omarchy-cmd-present; every
// Timer marked for architecture 6, the post-command re-reads every 2 s
// instead of 1.5 s.
import QtQuick
import Quickshell.Io
import "model/Shared.js" as Shared
import "model/NordVpn.js" as NordVpn

// NordVPN backend, driven by the `nordvpn` CLI talking to `nordvpnd`.
// Implements the backend contract documented in VpnController.qml.
//
// Merged from guiestrela/omarchy-norvpn-plugin (MIT), which was a whole widget
// of its own before it was one chip of five. Its status, settings and country
// vocabulary is intact; its own panel, its notification path and its pause
// timer are not — see ARCHITECTURE.md for what did not survive the fold and
// why.
//
// Every invocation is an argv array. There is no shell anywhere in this
// backend, which is a property worth keeping: the one `bash -c` the original
// had was in the notification path that came out.
Item {
  id: root
  visible: false

  property var settings: ({})
  property string filter: ""

  readonly property string backendId: "nordvpn"
  readonly property string label: "NordVPN"
  readonly property var installNames: ["NordVPN"]
  readonly property string glyph: Shared.GLYPH_SHIELD_LOCK
  readonly property bool supportsFilter: true
  readonly property string filterPlaceholder: "Filter countries — press / to search"

  property bool detected: false
  property var status: NordVpn.parseNordVpnStatus("")
  property var countries: []
  property bool countriesLoaded: false
  property var vpnSettings: NordVpn.parseNordVpnSettings("")
  property string actionStatus: ""
  property string lastError: ""

  // Installed and refusing is not the same as absent. The CLI is here, it will
  // work the moment the user is in its group, and the chip is the only place
  // that fix is going to be shown — so `detected` follows the binary, and the
  // refusal is rendered rather than hidden. Dropping the chip would also drop
  // the only way to bring down a tunnel this tool had already brought up.
  readonly property bool refusing: status.state === "denied"
    || status.state === "daemon"
    || status.state === "loggedout"

  // The kill switch blocks all traffic while the tunnel is down, so the
  // controller warns before tearing this backend down for another tool rather
  // than turning it off behind the user's back.
  readonly property bool lockdownMode: NordVpn.nordVpnBlocked(vpnSettings)
  readonly property string lockdownHint: "nordvpn set killswitch off"

  readonly property var toggles: Shared.applyPendingToggles(
    NordVpn.nordVpnToggles(vpnSettings, autoConnectCountry), _pendingToggles)
  property var _pendingToggles: ({})

  // Which country `nordvpn set autoconnect on` should name. A widget setting
  // rather than a tool one: the daemon stores only the answer, and the widget
  // is where the question is asked.
  readonly property string autoConnectCountry: String(setting("nordvpnAutoConnectCountry", ""))

  // Optimistic connection state, so the switch moves on the click rather than
  // on the next poll. -1 follows the CLI, 0/1 while a command is in flight.
  property int _desired: -1

  readonly property bool connected: _desired === -1 ? status.connected : (_desired === 1)
  // A status poll runs on the interval whether or not anybody is looking, so
  // it says nothing about whether a click can be taken: only a command in
  // flight does. `busy` is what the switch spins on; `_working` is what the
  // verbs refuse on.
  readonly property bool _working: commandProcess.running
  readonly property bool busy: _working || statusProcess.running
  readonly property string summary: NordVpn.nordVpnSummary(status, lockdownMode)
  readonly property var details: NordVpn.nordVpnDetails(status)
  readonly property var favorites: Shared.favoriteCodes(setting("favoriteCountries", "CH,NL,US"))
  readonly property string currentKey: NordVpn.nordVpnCurrentKey(status, countries)

  // A refusal replaces the connect list with the two commands that end it.
  // Anything else is the country list, with the quick row on top while nothing
  // is being filtered.
  readonly property var targets: {
    if (refusing) return NordVpn.nordVpnRemedyTargets(status)
    if (filter === "") {
      return NordVpn.nordVpnQuickTargets().concat(
        NordVpn.nordVpnCountryTargets(countries, favorites, ""))
    }
    return NordVpn.nordVpnCountryTargets(countries, favorites, filter)
  }

  readonly property string emptyText: {
    if (status.state === "denied") return "NordVPN answered, but refused: this user is not in the nordvpn group."
    if (status.state === "daemon") return "The NordVPN daemon is not answering."
    if (status.state === "loggedout") return "Log in with: nordvpn login"
    return countriesLoaded ? "No countries match." : "Loading countries…"
  }

  // Which switch is in flight, so a refusal rolls back the right one.
  property string _toggleKey: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Asked once. `force` is the user asking again, which is the only time the
  // answer could have changed — see refreshAll() in VpnController.
  property bool _probed: false

  function detect(force) {
    if (detectProcess.running) return
    if (force === true) countriesLoaded = false
    if (_probed && force !== true) return
    detectProcess.running = true
  }

  function refresh() {
    if (!detected || statusProcess.running) return
    statusProcess.running = true
    // Cheap: a Go binary answering a local socket, unlike Proton's Python
    // start, so the settings are re-read on every poll and the switches follow
    // the CLI even when it is driven from a terminal.
    if (!settingsProcess.running) settingsProcess.running = true
    // A refusing CLI has no country list to give, and asking again every poll
    // for something that will be refused until a group changes is what the
    // latch is for.
    if (!countriesLoaded && !refusing && !countriesProcess.running) countriesProcess.running = true
  }

  // Every verb refuses while the CLI does, and says why. Spawning a connect
  // that is going to be refused would replace the actionable message with a
  // generic failure, which is the message the user needs least.
  function refuseWhileBlocked() {
    if (!refusing) return false
    lastError = NordVpn.nordVpnActionHint(status)
    actionStatus = ""
    _desired = -1
    return true
  }

  function connectTo(target) {
    if (!detected || _working || !target) return
    if (refuseWhileBlocked()) return

    var args = NordVpn.nordVpnConnectArgs(target)
    if (args.length === 0) {
      lastError = "NordVPN would not accept that country."
      return
    }

    _desired = 1
    lastError = ""
    actionStatus = "Connecting to " + target.label + "…"
    run(args)
  }

  function disconnect() {
    if (!detected || _working) return
    if (refuseWhileBlocked()) return

    _desired = 0
    lastError = ""
    actionStatus = "Disconnecting…"
    run(NordVpn.nordVpnDisconnectArgs())
  }

  // NordVPN's own default connection: `connect` with no target picks the
  // fastest server it can reach.
  function toggleConnection() {
    if (connected) {
      disconnect()
      return
    }
    if (!detected || _working) return
    if (refuseWhileBlocked()) return

    _desired = 1
    lastError = ""
    actionStatus = "Connecting…"
    run(["connect"])
  }

  function setToggle(key, value) {
    if (!detected || toggleProcess.running) return
    if (refuseWhileBlocked()) return

    var args = NordVpn.nordVpnToggleArgs(key, value, autoConnectCountry)
    if (args.length === 0) return

    var pending = {}
    for (var name in _pendingToggles) pending[name] = _pendingToggles[name]
    pending[key] = value
    _pendingToggles = pending

    lastError = ""
    _toggleKey = key
    toggleProcess.command = ["nordvpn"].concat(args)
    toggleProcess.running = true
    pendingTimer.restart()
  }

  function run(args) {
    commandProcess.command = ["nordvpn"].concat(args)
    commandProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = NordVpn.parseNordVpnStatus(raw)
    root.status = parsed
    var hint = NordVpn.nordVpnActionHint(parsed)
    // The refusal is the standing condition, so it owns lastError until it is
    // gone — a transient failure from an earlier command is not what the user
    // needs to read while every command is being refused.
    if (hint !== "") {
      root.lastError = hint
      root.actionStatus = ""
      root._desired = -1
    } else if (root._standingHint !== "") {
      // It has just cleared: the line it owned goes with it.
      root.lastError = ""
    }
    root._standingHint = hint
    if (root._desired !== -1 && parsed.connected === (root._desired === 1)) root._desired = -1
  }

  // The refusal hint the previous reading left on lastError, so clearing it is
  // this backend's business and not a guess about who wrote that line.
  property string _standingHint: ""

  function applySettings(raw) {
    var parsed = NordVpn.parseNordVpnSettings(raw)
    // A read that answered nothing is not a report that everything is off.
    if (!parsed.loaded) return
    root.vpnSettings = parsed

    // Drop the optimistic value only for the switches the CLI now agrees with,
    // so a poll landing mid-flight cannot flick the others back.
    var pending = {}
    var changed = false
    for (var key in _pendingToggles) {
      var spec = NordVpn.nordVpnSpec(key)
      if (parsed.seen[key] === true && spec !== null
          && NordVpn.nordVpnToggleValue(parsed, spec) === _pendingToggles[key]) changed = true
      else pending[key] = _pendingToggles[key]
    }
    if (changed) _pendingToggles = pending
  }

  function clearPending(key) {
    var pending = {}
    for (var name in _pendingToggles) {
      if (name !== key) pending[name] = _pendingToggles[name]
    }
    _pendingToggles = pending
  }

  // A command that exits clean but does not take would otherwise leave the
  // switch showing the position the user asked for, marked busy, for as long
  // as the panel is open. Optimism gets a deadline.
  // haseen:ui-timeout
  Timer {
    id: pendingTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (Object.keys(root._pendingToggles).length === 0) return
      root._pendingToggles = ({})
      root.lastError = "NordVPN did not apply that setting."
    }
  }

  // The CLI returns before the daemon has finished the handshake, so the
  // reading that matters comes a beat later.
  // haseen:sample
  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 2000
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 6) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: detectProcess
    command: ["sh", "-c", "command -v \"$1\" >/dev/null", "sh", "nordvpn"]
    running: true
    onExited: function(exitCode) {
      root._probed = true
      root.detected = exitCode === 0
      if (root.detected) root.refresh()
    }
  }

  // The permission refusal arrives on stdout with a non-zero exit, so both
  // streams are read and the exit code decides nothing on its own: the parser
  // is what tells "refused" from "unreadable".
  Process {
    id: statusProcess
    running: false
    command: ["nordvpn", "status"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var output = String(statusStdout.text || "") + "\n" + String(statusStderr.text || "")
      var parsed = NordVpn.parseNordVpnStatus(output)
      if (parsed.state !== "") {
        root.applyStatus(output)
        return
      }
      if (exitCode === 0) {
        root.applyStatus(output)
        return
      }
      // Nothing recognisable and a failure: keep the last reading rather than
      // replacing it with a blank one that would report the tunnel as down.
      root.lastError = Shared.elide(output.trim() || "Could not read NordVPN status", 140)
    }
  }

  Process {
    id: settingsProcess
    running: false
    command: ["nordvpn", "settings"]
    stdout: StdioCollector { id: settingsStdout; waitForEnd: true }
    stderr: StdioCollector { id: settingsStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.applySettings(String(settingsStdout.text || "") + "\n" + String(settingsStderr.text || ""))
    }
  }

  // "Loaded" means asked and answered, not answered with something: keying it
  // off the parsed count would re-fetch the whole list on every poll, forever,
  // if the format ever changed.
  Process {
    id: countriesProcess
    running: false
    command: ["nordvpn", "countries"]
    stdout: StdioCollector { id: countriesStdout; waitForEnd: true }
    stderr: StdioCollector { id: countriesStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.countriesLoaded = true
      if (exitCode !== 0) return
      root.countries = NordVpn.parseNordVpnCountries(String(countriesStdout.text || ""))
    }
  }

  Process {
    id: toggleProcess
    running: false
    command: []
    stdout: StdioCollector { id: toggleStdout; waitForEnd: true }
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = NordVpn.nordVpnExplainError(
          String(toggleStderr.text || "") + " " + String(toggleStdout.text || ""))
        root.clearPending(root._toggleKey)
      }
      root._toggleKey = ""
      if (!settingsProcess.running) settingsProcess.running = true
    }
  }

  Process {
    id: commandProcess
    running: false
    command: []
    stdout: StdioCollector { id: commandStdout; waitForEnd: true }
    stderr: StdioCollector { id: commandStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var output = String(commandStderr.text || "") + "\n" + String(commandStdout.text || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = NordVpn.nordVpnExplainError(output)
      } else {
        root.lastError = ""
      }
      root.actionStatus = ""
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
