# Plan 026: haseen.prayers, a built-in port of the owner's OmaPrayers fork

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: LOW
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (luna's Omarchy plugins become built-ins)
- **State**: DONE 2026-10-04 (42 tests incl. Riyadh vs AlAdhan ±1 min; live bar + both panels + notify path)

## Why this matters

The owner uses `t1nk33r.omaprayers` on luna every day. As a haseen built-in it
runs without the Omarchy compat layer, with haseen names, the haseen theme and
the haseen notification server.

## Design

- One plugin, `haseen.prayers`, kinds `service` + `bar-widget` + `panel`,
  role `prayers` (approved by Main). Upstream's bar widget kept a hidden
  `Panel.qml` alive to own the engine. Bar widgets exist once per screen, so
  owning the engine there would compute the schedule and send each
  notification once per monitor (upstream deduplicated that in its script).
  `Service.qml` owns the engine once; `Widget.qml` and `Panel.qml` read it
  through `Plugins.roles.prayers`.
- The engine is unchanged: `Engine.js` and `Model.js` are upstream's. The
  timezone window comes from `haseen-prayers-zone.sh`. No network is used at
  runtime. The network is used only for the city search (open-meteo geocoding)
  and for "Detect" (wttr.in `%l`), and only when the user clicks them.
- The four layout files keep upstream's structure. `Style`/`Color`/`Util`
  map to `Theme` and to the service's `sp()`/`alpha()`/font sizes: the 12 px
  design grid is scaled by `Theme.fontSize`. Omarchy's `qs.Ui` controls are
  replaced by local `Prayer*.qml` controls. Dropdowns open inline, because a
  second popup window would clear the panel's `HyprlandFocusGrab`.
- Settings are written to `Config.setRuntime` at once and to
  `~/.config/haseen/shell.json` through `haseen-prayers-set.sh`, which uses
  `shell/lib/plugin.sh` (`shell_user_json`, `shell_config_write`) and supports
  `--dry-run`.
- Notifications: `haseen-prayers-notify.sh` runs `notify-send -a "haseen
  prayers"` and deduplicates by event key under
  `$XDG_STATE_HOME/haseen/prayers/`. It plays the chime with pw-play, or with
  paplay as a fallback, and stays silent while the `dnd` flag is on. All
  writes go through common.sh (`run`, `write_user_file`).
- Defaults: Riyadh's public city-centre coordinates (24.7136, 46.6753),
  `Asia/Riyadh`, method 4 Umm al-Qura, English. All other defaults are
  upstream's. Notifications are off by default, as upstream has them.

### Rejected

- Engine in the bar widget, as upstream does it: one engine per screen, see
  above.
- Running the Omarchy original through `Compat/`: the task asks for a native
  plugin, and the compat layer has no `Panel`/`KeyboardPanel` or settings
  controls.
- Dropping the bundled chimes for the freedesktop sound theme. Upstream's README
  states that `assets/prayer-chime.ogg` is generated from decaying sine notes
  with no third-party audio, so it is the upstream author's MIT work.
- `centerOnBar`: haseen's `PanelPopup` places every panel itself, so the
  setting and its switch are dropped.

## Execution record

### What changed

- New `share/haseen/shell/plugins/haseen.prayers/`:
  - `manifest.json`: 36 upstream settings plus `debugIpc`; permissions `exec`,
    `network`, `notifications`, `files:write`; provides `prayers`.
  - `Service.qml`: the engine, the 30 s tick (`// haseen:sample`, running only
    while the plugin is enabled), the notification queue with two retries,
    location search and detection, settings writes, and IPC target
    `haseen.prayers`. `refresh()` and `status()` are always available.
    `state()`, `setNow(epochMs)`, `set(key, json)`, `openSettings(bool)` and
    `replay(minutes)` work only with `debugIpc`.
  - `Widget.qml`: the strip + countdown, or a `BarButton` label for the other
    four `barDisplay` modes. Text uses `Theme.barForeground`, or `Theme.accent`
    within `highlightBeforeMinutes`. A hover tooltip opens through a
    `LazyLoader`. Left click toggles the panel, middle click cycles the label,
    right click refreshes.
  - `Panel.qml`: picks the Horizon or Compact layout, scrolls when taller than
    80 % of the screen, and handles the single-letter keys (r m d s b t a c /).
  - `PanelHorizon.qml`, `PanelCompact.qml`, `PanelDisplay.qml`,
    `PanelLocation.qml`: ported layouts.
  - `PrayerButton`, `PrayerChoice`, `PrayerSwitch`, `PrayerSlider`,
    `PrayerNumberField`, `PrayerDropdown`, `PrayerTextField`,
    `PrayerSectionHeader`, `PrayerToolTip`: local controls, using Theme tokens
    only.
  - `haseen-prayers-zone.sh`, `haseen-prayers-notify.sh`,
    `haseen-prayers-set.sh`.
  - `Engine.js`, `Model.js`: upstream's. The provider string is now "haseen
    prayers engine". `setHostProperty`, which existed only for Omarchy's bar
    façade, is removed along with its tests.
  - `LICENSE` (upstream MIT, unchanged), `UPSTREAM.md` (source, base commit
    and full change list), `THIRD_PARTY_NOTICES.md` (upstream's).
  - `assets/prayer-chime.ogg`, `assets/istijabah-note.ogg`, both upstream's
    generated sounds.
  - `tests/`: upstream's `Engine.test.js`, `Model.test.js`, `Aladhan.test.js`,
    `qml-js-loader.js`, the vendored adhan-js oracle and the fixtures, plus a
    new `Riyadh.test.js`.
- Upstream bug fixed: in `PanelCompact.qml` the Sunrise row evaluated
  `modelData.iqama.label` on a null iqama. This logged a TypeError on every
  open, seen in the smoke log.
- New `tests/test-prayers.sh` (42 checks).

### Riyadh reference

`tests/Riyadh.test.js` computes 2026-10-04 and 2027-03-15 at the manifest
defaults, through the real zone script. It compares 10 times per day and the
Hijri date against the AlAdhan timings API, method 4. Both days match within
±1 min (20 comparisons). The reference URLs:
`https://api.aladhan.com/v1/timings/04-10-2026?latitude=24.7136&longitude=46.6753&method=4&timezonestring=Asia/Riyadh`
(Fajr 04:29, Dhuhr 11:42, Asr 15:06, Maghrib 17:37, Isha 19:07; Hijri
23-04-1448) and the same query for `15-03-2027`. The engine gives Asr 15:05
against AlAdhan's 15:06, within tolerance.

### Verification

- `tests/run.sh tests/test-prayers.sh`: 42/42 passed, about 42 s, mostly
  `Aladhan.test.js`, which builds 60 timezone windows. The suites need node; the
  file prints a skip line when node is absent.
  `tests/run.sh tests/test-shell.sh tests/test-widgets-a.sh
  tests/test-widgets-b.sh tests/test-compat.sh`: 405/405 passed.
- `/tmp/tools/shellcheck --severity=warning -x`: clean on the three scripts and
  the test. `bash -n`: clean. `jq empty manifest.json`: ok.
  `haseen plugin validate`: ok, with the expected `network` warning.
- `qmllint` with the tools/lint.sh flags: 0 errors. The warnings are the usual
  unresolved `qs.Haseen` imports and `QProcess::ExitStatus` handler types.
- Live smoke on an isolated scratch instance (`dbus-run-session` with
  `tools/smoke-session.conf`, scratch XDG dirs, services list containing only
  `haseen.prayers`, so idle, lock, polkit, screensaver and nightlight were off;
  stub `notify-send` on PATH). It was driven only through `qs ipc --pid <own
  pid>`, and only the started PIDs were killed. Screenshots taken with grim and
  viewed:
  - bar, strip + countdown (`50m`), `Name + countdown` (`Isha 50m`), Arabic
    (`49 د`, mirrored strip), and accent tint with highlightBeforeMinutes 60;
  - Horizon panel: hero, to-scale day strip, window lengths, iqama captions,
    night band with thirds;
  - Compact panel in English and Arabic (RTL, Hijri 23 Rabi' al-Thani 1448);
  - settings fold in Arabic (method dropdown, chips, switches, sliders).
- Notification path, live: `setNow` to 04:21 Riyadh on 2026-10-05, then
  `replay 5`, gave `notify-send -a haseen prayers Fajr in 10 minutes Scheduled
  for 04:29`. A second replay was deduplicated. At 04:30, `replay 3` gave `It is
  time for Fajr 04:29`, and the bar changed to `Iqama 24m`. The test file also
  covers dry-run purity, the chime command line, the DND silence and failure
  propagation.
- Settings writes, live: `set panelStyle "Compact"` and the other changes
  landed in the scratch `shell.json` under `plugins."haseen.prayers".settings`.
- RSS (`ps -o rss`, KiB):
  - baseline instance without the plugin, idle: 161112 to 161388;
  - with `haseen.prayers` in the bar and services, idle 45 s: 160372, so the
    idle delta is within noise (about 0 MiB);
  - after opening the panel and switching both layouts: 199532. The panel is
    lazy and its components stay cached after the first open (+38 MiB). Only
    that first open costs anything, and it adds nothing at idle.

### Integration (for Main)

- `default/shell.json`: add `"haseen.prayers"` to `bar.right` and to
  `services`.
- `NOTICE.md` rows:
  - `share/haseen/shell/plugins/haseen.prayers/` | OmaPrayers,
    https://github.com/salemsayed/omaprayers (base `e101d4c`, v2.5.0, via the
    owner's fork t1nk33r.omaprayers 2.8.0) | MIT, Copyright (c) 2026 Salem
    Sayed | ported
  - `haseen.prayers/Engine.js` (algorithm) | adhan-js,
    https://github.com/batoulapps/adhan-js | MIT, Batoul Apps | ported
    (carried by upstream)
  - `haseen.prayers/Engine.js` (Umm al-Qura table) | hijridate,
    https://github.com/dralshehri/hijridate | MIT | data (carried by upstream)
  - `haseen.prayers/tests/vendor/adhan.umd.min.js` and
    `tests/fixtures/batoulapps/` | adhan-js 4.4.4 | MIT, Batoul Apps |
    test-only, vendored
