# Plan 052: io, sixth round — live compat panels, wifi and weather ports, universal paste, DMS daemons

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (pointer input of every Omarchy compat panel; one write outside haseen's own config)
- **Depends on**: 049 050 051
- **Category**: shell, compat
- **Planned at**: 2026-10-06, owner reports while using io
- **State**: DONE 2026-10-06 (physical clicks, real GeoClue Wi-Fi positioning, region capture and real recording are owner checks)

## Problem and decision

- **Omarchy plugin panels were "dummies"** (display, tailscale, agents,
  nearby-share, power, workspace-layout): they drew live data but took no
  pointer input. Cause, traced with debug logs in a nested shell:
  `Compat/Omarchy/Ui/KeyboardPanel.qml` stored its supplied mask in
  `Component.onCompleted`, after the `mask: openMask` binding had already run
  `onMaskChanged` → `applyMask()`, which swapped in `closedMask`. An open panel
  therefore kept an empty input region forever. `PanelInput.suppliedMask()`
  now refuses to adopt the host's own closed region, and `adoptMask()` runs
  from both hooks. One fix revived all six plugins.
- **Omarchy command shims.** Plugins call Omarchy commands by name. The
  display plugin's restart button ran `omarchy-restart-shell`, which launches
  the Omarchy shell beside haseen; its mirror switch wrote a toggle file that
  haseen's Hyprland config never loads. `share/haseen/shell/Compat/bin/` is
  now prepended to PATH by `haseen-shell-run` (systemd unit and `shell
  restart` both go through it) and holds one-line shims:
  `omarchy-restart-shell` → `haseen shell restart`,
  `omarchy-hyprland-monitor-internal-mirror` → `haseen hardware
  mirror-display`, `dms` → `haseen capture screenshot` / `haseen shell ipc`.
  `haseen shell restart` re-execs itself with `setsid` so the shell it kills
  cannot take it down (seen with a ps trace when run from the button).
- **Omarchy shell.json mirror.** nearby-share reads its settings only from
  `~/.config/omarchy/shell.json` (its `Service.qml:267`), so its receiver
  switch never took effect. `updateEntryInline` for an Omarchy compat plugin
  also mirrors that plugin's own entry into that file, with Omarchy's rule:
  only if the file exists, only the calling plugin's entry, atomic, one-time
  `.haseen-bak`. haseen's shell.json stays the source of truth. Rejected:
  leaving it as a plugin limitation (the switch silently does nothing).
- **Wifi panel**: Omarchy's network panel ported into `haseen.network`
  (`Model.js`, `NetworkRow.qml`, `Pill.qml`, `ToggleSwitch.qml`,
  `bin/haseen-network-{status,band}`). Its timers run only while the panel is
  open.
- **Weather**: Omarchy's weather logic (wttr j1, Open-Meteo, retries, 15-minute
  refresh, unit rule, city search) ported into `haseen.weather`. Location
  order: the setting, then GeoClue (`haseen-weather-location --detect`, city
  accuracy, client stopped at the first fix), then wttr.in's IP lookup as
  Omarchy does. `haseen setup geoclue on|off` installs geoclue and writes
  `/etc/geoclue/conf.d/90-haseen.conf`; without its agent geoclue never
  answers (`Client … waiting for agent for user ID '1000'`, tested on a
  private bus with the real 2.8.2 binaries).
- **SUPER + V stopped pasting.** Omarchy binds SUPER + C/V/X to universal
  copy/paste/cut (`/usr/share/omarchy/default/hypr/bindings/clipboard.lua:45-47`);
  haseen bound nothing there. Ported into `binds.lua` with a `terminal` window
  tag in `windowrules.lua` (terminals get CTRL/SHIFT+Insert).
- **DMS daemon plugins** (owner asked for JDKamalakar/DMS-ScreenCapture_Toolbar).
  The toolbar has no license file, so haseen ships none of it; the owner
  installs it with `haseen plugin install`. A DMS `daemon` now loads once in
  `Compat/DmsServiceHost.qml`; compat gained `DankButtonGroup`,
  `DankDropdown`, `DankTextField`, `DankToggle`, `DankTooltipV2`,
  `PluginService` globals, persisted `savePluginData`, and `Compat/Layers.js`,
  which turns off layer effects under the software renderer (MultiEffect
  draws nothing there and hid the toolbar). `haseen capture screenshot` gained
  the flags the `dms screenshot` shim needs; its default output is unchanged.

## Verification

Tests: `test-compat.sh` (mask creation order), `test-compat-mirror.sh`
(sandbox HOME), `test-network-panel.sh` (52 units), `test-weather.sh` (79,
fake where-am-i and curl), `test-shell.sh` (shim reaches `systemctl --user
restart haseen-shell.service`; mirror shim), `test-keybinds.sh` and
`test-desktop.sh` (SUPER + C/V/X bound to Lua functions).

Nested Hyprland, started through the owner's exec rule on workspace 5 with a
PATH guard: tailscale hover and settings, agents tabs and keys, power profile
and charge limit (blocked by the guard, logged), display brightness, cursor
and restart, workspace-layout "Even" applied to nested workspace 2,
nearby-share receiver off taking effect, weather from IP, a picked city and
GeoClue (static source), the capture toolbar in photo and video mode taking a
real screenshot. Live on io: `hyprctl binds` lists SUPER + C/V/X, foot
windows carry `terminal*`.

## Not done

- The display plugin's text size still writes Omarchy's `shell.toml`, which
  haseen does not read; a haseen-wide text size would be a new feature.
- nearby-share needs `helper-release.env` copied from luna (plugin dirs are
  read-only to haseen) and Bluetooth on for Quick Share.
- The toolbar's own `Settings.qml` is not shown: haseen has no plugin settings
  screen. Its controller listener has a hard-coded home path.

## Incident: a test run outside the runner wrote into the owner's config

An agent ran `bash tests/test-compat.sh` directly. Without `tests/lib.sh`,
`sandbox` was undefined, HOME stayed real, and the fixtures landed in the
owner's `~/.config/omarchy/plugins` (11 `me.*` dirs and omaconnect's
`manifest.json`/`Service.qml` overwritten), `~/.config/DankMaterialShell/plugins`
and `~/.config/haseen/plugins`. All were restored from the morning's config
backup and the strays removed (kept in `~/haseen-io-backup/`). Every
`tests/test-*.sh` now refuses to run unless `tests/run.sh` loaded the harness;
`test-core.sh` runs each file directly against a scratch HOME and expects
exit 2 with nothing written.
