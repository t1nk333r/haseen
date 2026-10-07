# Plan 054: io, seventh round — steady indicators, gestures that stay on, DMS links and plugins, the default-plugin rule

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (DMS compat grows new surfaces; plugin install learns browse URLs)
- **Depends on**: 035 048 050 052
- **Category**: shell, compat, plugins
- **Planned at**: 2026-10-07, owner reports while using io
- **State**: DONE 2026-10-07 (real touchpad swipes, real fingerprint and real typing through the virtual keyboard are owner checks)

Plan 053 is taken by the Aether plan in luna's uncommitted work; this round
skips it.

## Problem and decision

- **Rule: never ship optional plugins by default** (AGENTS.md). The owner
  approved the default set plugin by plugin. It keeps every built-in that was
  on. A new built-in stays off until he adds it. Third-party plugins are never
  bundled and never enabled by install. Rejected: moving the personal built-ins
  (prayers, weather, sysusage, media, gestures) out to opt-in; the owner kept
  them.
- **Indicators broke the bar when one was switched off** (PR #19 follow-up).
  Reproduced in a nested session with a WAYLAND_DEBUG log. Two different
  `set_anchor_rect` values came 3 ms apart: Quickshell's popup anchor kept the
  stale widget rect while QtWayland used the fresh one. The strip then shrank
  to the clamped 1 px before it was destroyed, and Hyprland faded that ghost out
  over the clock. Third, the widget changed width under the pointer, so hover
  dropped and the strip reopened on the next repaint. Fix: the strip is drawn
  inside the bar window, positioned from a reactive ancestor sum (no popup, no
  anchor). The active/inactive split is frozen while the pointer is on it, so
  cells flip in place and the bar takes the one-cell change after the pointer
  leaves.
- **Swipes stopped working.** `shell.json` held
  `haseen.gestures.settings.enabled=false`, written at 03:30:28 together with
  an empty toggles file by `haseen gestures apply --set`. The cause was a right
  click on the gestures cell in the overflow panel; with clickfinger on, a
  two-finger tap is a right click, and it was a silent master toggle. Fix: every
  click opens the gestures panel, and switching gestures off or on by any route
  sends a notification that names how to turn them back on. Gestures were turned
  back on with `haseen gestures apply --set '{"enabled":true}'`.
- **Lock screen fingerprint.** A finger was enrolled, but
  `/etc/pam.d/haseen-lock-fingerprint` was missing because `haseen setup
  fingerprint` had never run on io. It has now been run. The lock looks for the
  service file at every lock.
- **`dms://` links.** The DMS gallery's install button is
  `dms://plugin/install/<id>`; the repository comes from the registry entry.
  `haseen plugin url` handles it: the id is looked up in the registry clone, only
  https repositories are accepted, and the user is asked before the install.
  `haseen-dms-url.desktop` registers `x-scheme-handler/dms`, and the shell layer
  never overrides a handler the user chose. Also fixed: `plugin install --enable`
  and `plugin uninstall` always passed `--dry-run`, so they never changed
  `shell.json`.
- **DMS plugins the owner asked for**: ScreenCapture Toolbar, Network-Indicator,
  tlp-power-profile, ModernClockDMS, virtualkeyboard, dms-conky. They are
  installed as his user plugins, not enabled and not bundled (licences:
  virtualkeyboard GPL-3.0; dms-conky and the toolbar unlicensed; all reference
  only). Compat gained:
  - popouts (`PluginPopout`, `PopoutComponent`);
  - the plugin-state API;
  - `Proc`, `BatteryService`, `PopoutService`, `DgopService` (over the sidecar),
    `MprisController`, `CavaService`, `WeatherService`, `DMSNetworkService`;
  - the desktop type, mapped to overlay (`DmsDesktopHost`/`DmsDesktopWindow`),
    and the `startupCheck` gate;
  - Theme tokens and Dank widgets;
  - a `ydotool` shim that types through Hyprland's `send_key_state`;
  - browse-URL installs (`…/tree/<ref>/<dir>`) for plugins inside a monorepo.
- **hyprmod**: installed on io from the catalog (AUR, last resort; owner's call).
  It is a GPL GTK4 app, so it is not ported; it owns
  `~/.config/hypr/hyprland-gui.lua` (luna's plan 043).

## Verification

- Tests:
  - `test-indicators.sh`: the real engine with real offscreen hover covers the
    strip position, the flip, the side bar, following the section, and on/off
    under the pointer.
  - `test-gestures.sh`: the notifications; a right click opens the panel.
  - `test-dms-url.sh`.
  - `test-plugin-tree-url.sh`.
  - `test-compat-dms.sh`.
  - `test-compat.sh` (desktop→overlay).
- Nested Hyprland screenshots for the indicators (before and after) and for each
  DMS plugin.

## Not done

- Real swipes, a real finger on the lock, and real typing through the virtual
  keyboard on io.
- The virtual keyboard's bar pill has zero width under DMS too: it reads
  `parent.widgetThickness` from a Loader. This is an upstream bug.
- cava and dgop are not installed on io, so conky's visualiser stays empty.

## Addendum: the lock test that kept failing on CI

Since #13, `test-lock.sh` "a reader that fails at once is given up on" failed on
most CI runs and passed locally. A throwaway CI run with a timeline
(`ci/lock-diag`) showed the cause: the fourth fingerprint conversation started
but never sent a message or ended, so it never reached the fifth quick failure.
On a real lock the same hang would leave fingerprint dead until the next lock.
Fix: a fingerprint attempt that stays silent past `fingerprintStallMs` (default
5 s; pam_fprintd prompts at once when it holds the reader) is aborted and
counted as a failure that came at once. A context that stays active after the
abort counts again on each retry, so the give-up rule still applies. The test
gains a `pam_exec` stack that hangs; it fails without the watchdog.
