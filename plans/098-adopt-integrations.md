# Plan 098: Adopt three integrations as first-party plugins

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (three new opt-in plugins and four new commands; one migration that rewrites `shell.json` ids; nothing changes for a HOME that does not use the old ids)
- **Depends on**: 005 011 027 028 057 074 077
- **Category**: shell
- **Planned at**: 2026-10-20, owner decision (below)
- **State**: DONE 2026-10-20 (focused suites: test-monitor-settings 76/76, test-omaconnect 91/91, test-syncthing 74/74, test-migrate-integrations 30/30; full gate in the PR)

## Decision

On 2026-10-20 the owner, asked to list the third-party plugins they run "so i
can choose which to adopt into haseen as a 1st party plugin", picked 13. This
plan ports three of them (plans 095–097 port the rest):

| Old id | New id | Upstream (MIT) |
|---|---|---|
| `io.github.juliusmork-sys.monitor-settings-extender` | `haseen.monitor-settings` | juliusmork-sys/Omarchy-Monitor-Settings-Extender, © 2026 Julius Getz Mørk |
| `omaconnect` (registry id `omarchy.omaconnect`, §5.4) | `haseen.omaconnect` | jitendradara12/omaconnect, © 2026 OmaConnect contributors |
| `io.github.ilyazar.syncthing` | `haseen.syncthing` | ilyaZar/omarchy-syncthing, © 2026 IlyaZar |

Per the owner's rule recorded on luna, a plugin haseen changes takes a
`haseen.*` id. Per CLAUDE.md a new built-in plugin is off until the owner adds
it to the default list, so adoption is not default-on: none of the three is
in `share/haseen/default/shell.json` (each test asserts it). For these three
the decision overrides CLAUDE.md's "third-party plugins are never bundled";
the upstream notices stay in the file headers and in `NOTICE.md`.

## Sources

Read only; nothing under `~/.config` on luna or IO was written.

- **Monitor settings.** luna's clone was 3 ahead, 0 behind upstream main
  (`git rev-list --left-right --count HEAD...up/main`: 3 0): commit 45ead93
  (the Qt 6.12 `Commons.Color` fix), d0c4bc5 (the widget's own IPC target
  instead of `omarchy.monitor`) and b5f1ce3 (fork topology notes). IO's copy
  equals luna's (`diff -rq`: only `.gitignore` differs). IO's haseen
  `shell.json` lists the widget in `bar.right` with no settings. Ported from
  that copy; d0c4bc5's point (own IPC target) holds by construction, the IPC
  target being `haseen.monitor-settings`.
- **OmaConnect.** luna's clone was 5 ahead, 7 behind. Its committed owner work
  (cee1583 Qt fix, 8558499 refresh button not dimming on the rescan, 2e2708a
  null-service guards and `isCurrent`, 54b2bd0 and 4a0f257 metadata) was taken
  as the feature base; the uncommitted `BarWidget.qml` hunk (a smaller icon
  `fontSize` for Omarchy's bar) equals IO's copy and is about Omarchy's bar
  metrics, so it has no counterpart on BarButton. Upstream added since (up to
  1.5.0): a refactor with stale-generation guards, a scan queue, an IPv6 `:`
  check, no blocking per-device network probes (trust the daemon's
  reachability), the gdbus variant-with-comma reply fix and an address
  option-injection guard; keyboard (hjkl) navigation; a bridge singleton for
  replacement bars; rewritten Python tests; media status only through
  Python. The port takes the script fixes (no probes, the comma fix, no
  address starting with `-`, a scan queue, generation guards by device id)
  and not the keyboard navigation, the bridge or the Python media path.
  IO lists OmaConnect only in Omarchy's own `shell.json`, not haseen's.
- **Syncthing.** luna's clone was 3 ahead, 153 behind; its own commits are
  the Qt fix e4e6039 and two metadata/docs commits (9302f42, 1aef4c2), none
  functional. As the brief asked, upstream's current version (0.2.3, head
  45b25c8 at the time of reading) is the base. IO's haseen `shell.json` names
  it only inside the `t1nk33r.nook` drawer's items.

## What was built

### haseen.monitor-settings (bar widget + panel)

- `bin/haseen-hardware-monitor`: `list` (hyprctl `monitors all` plus the
  recorded settings, whether the user's `monitors.lua` or hyprmod's file names
  the output, mirror/laptop-off state, cursor size), `set OUTPUT --mode
  --position --scale --transform --on/--off`, `reset [OUTPUT]`, `cursor SIZE`.
  Upstream applied changes with `hyprctl eval` only, so they vanished at the
  next reload (its README: "This only applies live"). Here each change is also
  recorded in `$HASEEN_USER_STATE/monitor-settings.json` and rendered to
  `toggles/hypr/display-layout.lua`, which `init.lua` loads with the other
  toggles: after the defaults, before `laptop-display-off.lua` and
  `mirror-display.lua` (alphabetical, so those still win) and before the
  user's `~/.config/hypr/monitors.lua` (user files win, CLAUDE.md). A rule is
  keyed `desc:<EDID description>` when that is unique, so a dock that renumbers
  `DP-7` keeps its layout (upstream's README names the renumbering problem).
  `set` refuses while mirroring and refuses turning off the last display.
- Overlap decisions: brightness stays in `haseen.display` (the panel's
  Brightness pill and the widget's right click open it; the wheel runs
  `haseen brightness up|down`); mirror/extend runs `haseen hardware
  mirror-display`; the built-in panel's on/off runs `haseen hardware
  laptop-display`, so each toggle keeps one owner. Upstream's text-size
  slider (`omarchy-display-text-size`), screensaver timeout (`haseen setup
  idle` owns it, plan 082), "Restart Omarchy Shell" button and auto-reopen
  marker were not ported.
- Upstream re-read the monitors every 5 s while open; the panel reads once on
  open, 200 ms after each change (a `// haseen:ui-timeout`), and on
  Hyprland's `monitoradded`/`monitorremoved`/`configreloaded` events.
- The cursor size goes to `hyprctl setcursor`, gsettings, and
  `~/.config/uwsm/env.d/61-haseen-cursor` (after the desktop layer's
  `60-haseen-defaults`, which sets 20) for the next login. Upstream set only
  the first two.
- `Model.js` keeps upstream's clean-scale rule, friendly EDID names, refresh
  rates per resolution, rotated footprint, edge snapping and overlap push-out;
  scales are a fixed list snapped by the clean-scale rule (upstream read them
  from `omarchy-monitor-state`).

### haseen.omaconnect (service + bar widget + panel)

- `bin/haseen-kdeconnect`: `devices [--refresh]`, `pair accept|reject`,
  `media status|action|player`, `address add|remove`, `pick-file` (upstream's
  four scripts). D-Bus writes go through `run`, so `--dry-run` prints them.
- `bin/haseen-setup-kdeconnect on|off|status`: `pkg_install kdeconnect` and
  ports 1714–1764 in ufw or firewalld through `run_root` (upstream ran `sudo`
  in its scripts; CLAUDE.md allows `sudo` only in `common.sh`); `off` closes
  them. The manifest's `requires.bins` (kdeconnect-cli, gdbus, dbus-monitor)
  replaces upstream's in-panel installer: the plugin does not load until
  they exist, and says why (plan 064).
- The service (role `kdeconnect`) keeps upstream's design: one
  `dbus-monitor` on the daemon's signals, a scan 300 ms after the last, a
  15 s rescan only while that monitor is down (`// haseen:sample`, gated on
  `!monitor.running`), one action at a time, a 30 s pairing watchdog.
  SMS, the KDE Connect app and the firewall step start through `Apps.launch`
  (plan 074); the file list goes to `haseen menu select` (plan 071) instead
  of `omarchy-menu-select`. A pairing request while no panel is open is one
  notification (`haseen notification send`).
- The phone's cover art is shown only when KDE Connect downloaded it to a
  local file; a remote URL is dropped (no request from the shell, plan 010).
- Settings keep upstream's 15 names, so the migration copies them as they are.

### haseen.syncthing (service + bar widget + panel)

- Upstream's Go core (`core/`, 448 KB of Go source and tests by `du -sh`) is committed as
  prebuilt binaries (`bin/x86_64/syncshell-core`, `bin/aarch64/…`). haseen
  never vendors prebuilt binaries. Everything the panel needs is in
  Syncthing's own REST API, so the core is dropped, not rebuilt:
  `bin/haseen-syncthing` calls it with curl. It finds `config.xml` where
  upstream's discovery looks (`STCONFDIR`, `STHOMEDIR`,
  `$XDG_STATE_HOME/syncthing`, `$XDG_CONFIG_HOME/syncthing`,
  `~/.local/share/syncthing`; upstream `core/internal/syncthing/discovery.go`),
  passes the API key to curl as `-H @/dev/fd/N` (never on argv), and talks only
  to a loopback GUI address (a wildcard one is reached on 127.0.0.1).
- Commands: `status`, `events` (Syncthing's long poll), `rescan`,
  `pause|resume`, `pause-all|resume-all`, `add-folder`, `share … on|off`,
  `remove-folder`, `accept-device`, `dismiss-device`, `accept-folder`,
  `dismiss-folder`, `service start|stop|restart|status`, `gui-url`.
  Verified against a scratch Syncthing 2.1.3 (own home, loopback GUI,
  discovery and relays off): status, add-folder, pause/resume, rescan,
  events, accept-device, share on/off and remove-folder all applied.
- The service (role `syncthing`) reads the status once, then runs the event
  long poll (60 s per request) and reads the status 500 ms after any event
  that is not a finished file; finished files feed the recent activity.
  While Syncthing is down it asks again after 5, 10, 20, 40 s, then every
  `refreshIntervalSec` (upstream's one setting, kept, min 60). An empty poll
  that comes back at once waits 1 s before the next, so a misbehaving
  server cannot spin it.
- Not ported: upstream's themed web UI and its importer (Open web UI opens
  Syncthing's own), its Waybar/Caelestia/DMS hosts, the MPL-2.0 status SVGs
  (Nerd Font glyphs instead), folder types, ignore patterns and versioning
  (Syncthing's web UI).

### Migration

`share/haseen/migrations/1791560300-adopt-integrations.sh`: for a HOME whose
`shell.json` uses an old id, every bar section (`left`, `center`, `right`,
`overflow`, `pinned`) and `services` get the new id in its place, once; a
listed OmaConnect or Syncthing widget gets its service added to `services`
(the Omarchy originals started theirs beside a listed widget, §5.4; a native
service runs only from `services`, `Haseen/Plugins.qml` `serviceIds`);
`plugins.<old>` moves to `plugins.<new>` with `enabled` and only the
settings the new manifest declares, an entry already under the new id
winning. Atomic through `shell_config_write`, `DRY_RUN` honoured, idempotent.
It never touches the old plugin directories, and another plugin's own
settings that name an old id (the owner's `t1nk33r.nook` drawer lists
Syncthing on IO) are left and reported: the original still loads there.

## Evidence

- `tests/test-monitor-settings.sh`: manifest, contract, no Omarchy names, one
  timer; the CLI against a fake hyprctl (desc keys, the toggle is valid Lua,
  the user's `monitors.lua` untouched, refusals, mirror refusal, cursor
  three ways, reset); Model.js under `qml`; the panel and widget in `qs`.
- `tests/test-omaconnect.sh`: the CLI against `tests/fixtures/kdeconnect-gdbus.sh`
  (scan lines, no network probe, 69 without the daemon, media JSON, pairing
  dry run, address list writes and refusals), `setup kdeconnect` dry runs;
  Model.js; the service, widget and panel in `qs` (one action at a time, the
  ring and ping calls, an unpaired device refused, the pairing answer, one
  notification).
- `tests/test-syncthing.sh`: no file but QML, JS and JSON in the plugin; the
  CLI against `tests/fixtures/syncthing-curl.sh` (the key never in the log or
  argv, every request shape, refusals, a non-local GUI refused, `STCONFDIR`);
  Model.js; the service in `qs` following the long poll by event id.
- `tests/test-migrate-integrations.sh`: an owner-like HOME, a HOME relying on
  the default `services`, no file, no old ids, a broken file.

## Rejected

- Rebuilding upstream's Go core in `tools/build-sidecar.sh`: it would add a
  second Go module of that size and a long-running process for what
  the REST API answers directly; the brief allowed either.
- Extending `haseen.display` with the monitor controls: it is a panel opened
  from the menu and the brightness keys' world (plan 077), on-demand and
  without a bar widget; the owner runs the monitor extender as a bar widget,
  so it stays its own plugin and links to the brightness panel.
- Writing monitor changes into `~/.config/hypr/monitors.lua` (what Omarchy's
  scaling script does): a user file after seeding (CLAUDE.md).
- Rewriting the nook drawer's item ids in the migration: that is another
  plugin's own data, and the native widgets are not known to load in it.
- Keeping upstream's in-panel dependency installer: `requires` already
  refuses the plugin with a reason, and the install belongs to `haseen setup
  kdeconnect`.

## Remaining

- No nested-Hyprland screenshots were taken of the three panels.
- Drag in the arrangement diagram was exercised through `Model.place` under
  the Qt JS engine, not with a pointer.
- `haseen settings` (plan 045) has no rows for the cursor size or the new
  setup step, and the menu has no Setup › KDE Connect row; both are shared
  files other plans were changing at the same time.
