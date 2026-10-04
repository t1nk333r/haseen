# Plan 019: Screensaver (Omarchy ttfx + native), nightlight, idle prevention, DND

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: PLANNED (executor: Ambient)

## Why this matters

The owner asked for a screensaver (both styles, selectable), a daylight shader (hyprsunset), idle prevention and DND, all as toggles that the menu and bar can reach.

## Execution record

### What changed

- **Flags** (`shell/Haseen/Flags.qml`, `qs.Haseen` singleton, one qmldir line): read-only `dnd`, `idleOff`, `screensaverOff`, `nightlight` and `recording` come from FileView watches on `$HASEEN_USER_STATE/flags/<name>`, and `Flags.set(name, on)` writes them. FileView watches both the file and its parent directory (quickshell `src/io/fileview.cpp:494-546`). A missing directory cannot be watched, so the watches start after a one-off `mkdir -p`. Every QML reader uses this singleton, and there is no polling.
- **Toggles** `bin/haseen-toggle-{dnd,idle,screensaver,nightlight} [on|off|toggle|status] [--dry-run]`: "on" always means the feature is on, so `idle off` writes `idle-off`. Writes go through `write_user_file`/`run rm`. `toggle screensaver` sends a notification because nothing else shows that state.
- **haseen.idle**: up to three ext-idle-notify monitors (screensaver 150 s, lock 300 s, dpms 330 s). The decisions are pure JS in `IdleLogic.js`: `timeouts`, `actions`, `monitors`, `parseMonitor`. `idle-off` removes every monitor and `screensaver-off` removes the screensaver one. A screensaver due at or after the lock is dropped. The lock action dismisses the screensaver first. Stay Awake bar indicator: `Widget.qml`, a coffee cup shown only while the flag is set; clicking it allows idle again. Debug hook `haseen.idle state` (`settings.debugIpc`).
- **IdleMonitor bug found and worked around.** In Quickshell 0.3.1, changing an IdleMonitor's `enabled` or `timeout` deletes its notification and creates a new one. The allocator returns the same address, so the `bIsIdle` binding (`monitor.cpp:22-25`) sees an unchanged pointer and the monitor never reports idle again. Observed with `QT_LOGGING_RULES=quickshell.wayland.idle_notify.debug=true`: "has been marked idle" was logged while `isIdle` stayed false, with a static probe IdleMonitor idle at the same time. Fix: each monitor is an `Instantiator` delegate keyed by a `"name:seconds:respect"` string, created once with its final parameters and never reconfigured. The screensaver's 1 s dismiss monitor is in a `LazyLoader`. The test forbids `enabled:` on these IdleMonitors.
- **haseen.notifications**: `dnd` is `Flags.dnd`, and `toggleDnd()` writes the flag, so the CLI, panel, IPC and bar all agree. The bar-widget `Widget.qml` (crossed-out bell, shown only while DND is on) turns DND off on click. The plugin directory still has no FileView (`test-surfaces.sh:105`).
- **haseen.screensaver** (service, provides `screensaver`, IPC `screensaver start <ttfx|native|default>`, debug `haseen.screensaver dismiss|startIdle|state`):
  - **ttfx** (default, owner decision): a port of Omarchy's `omarchy-launch-screensaver` and `omarchy-screensaver` in `bin/haseen-screensaver`. Each monitor gets a fullscreen terminal (`$TERMINAL`, or what `xdg-terminal-exec --print-id` reports; foot by default; foot, alacritty, kitty or ghostty). The launcher focuses each monitor in turn and opens the terminal with `hl.dsp.exec_cmd([[[workspace special:screensaver-<mon>; idle_inhibit none] …]])`, reusing a special workspace that is already shown, then waits for that window to map. Focus goes back to the original monitor afterwards. Inside, ttfx runs Omarchy's exact flags. A key press or focus loss closes every screensaver terminal by PID and restores the hidden cursor. Changes from Omarchy:
    - polling `hyprctl clients` for at most 5 s per monitor, instead of a socat event stream (no new dependency);
    - the shell follows `openwindow`/`closewindow` raw events and hands focus back itself, instead of a background loop;
    - `--stop` kills the terminals by PID, not with `pkill -f`;
    - a failing ttfx stops the loop instead of respawning it.

    The service falls back to native with one warning if the launcher fails, for example when ttfx is missing.
  - **native**: one Overlay-layer PanelWindow per screen with `Theme.background`, the branding (user `screensaver.png`, else `screensaver.txt`, else the default text), a large clock and the date. The card moves 4 px every 2 s and bounces off the edges (pure `Drift.js`), with no animation between steps. Keys and clicks dismiss it, and the cursor is blank.
  - Exit on pointer motion: a fresh 1 s IdleMonitor per show that arms after one idle second.
  - Selection: `settings.style`, `haseen screensaver --style`, and `haseen screensaver style [ttfx|native]` (new `bin/haseen-screensaver-style`, which writes through `shell_config_write`).
- **haseen.nightlight** (IPC `nightlight on|off|toggle|refresh|status`) follows the `nightlight` flag. If an existing hyprsunset answers `hyprctl hyprsunset temperature K` (exit 0), the service uses it and sets it back to `identity` when the light goes off. Otherwise it runs its own `hyprsunset -t K` child process and stops it. Temperature changes go live through `hyprctl`. Optional fixed `sunset`/`sunrise` schedule (`NightlightLogic.js`): the flag follows the schedule at startup and at each crossing, and a manual toggle holds until the next one.
- Timers: the native tick (`haseen:sample`, 2000 ms, `running: active && native`), the schedule check (`haseen:sample`, 60000 ms, `running: hasSchedule`) and the ttfx no-window grace (`haseen:ui-timeout`, single-shot).

### Evidence

- `tests/run.sh tests/test-ambient.sh tests/test-surfaces.sh tests/test-shell.sh`: 486/486 passed. test-ambient covers:
  - the flag toggles (state, idempotence, dry-run purity, HASEEN_USER_STATE);
  - `haseen screensaver` and `screensaver style` (including invalid values and keeping the rest of shell.json);
  - the ttfx launcher against a fake two-monitor Hyprland: exact dispatch sequence, one terminal per monitor, nothing launched while one is showing;
  - `--stop` killing only screensaver PIDs;
  - `--ttfx-run` flags, branding choice, cursor restore, focus-loss exit and no tight respawn;
  - the idle decision table, monitor keys, drift bounds and the nightlight schedule, run in Qt's own JS engine (`qml`).

  The missing-ttfx message is skipped while `/usr/bin/ttfx` is installed.
- shellcheck (warning, `-x`) and `bash -n` are clean on all six commands and the test. `jq empty` passes on the manifests. qmllint with the `tools/lint.sh` flags reports 0 errors.
- **ttfx CLI**: `ttfx --help` (0.3.2 installed) lists every flag Omarchy uses, and so does `src/cli.rs` at tag v0.5.0 (AUR version).
- **Live smoke** (scratch `XDG_CONFIG_HOME`/`XDG_STATE_HOME`/`XDG_RUNTIME_DIR`, `dbus-run-session --config-file=tools/smoke-session.conf`, fake `hyprsunset`/`hyprctl` first in PATH, lock disabled):
  - Bar indicators: the coffee cup and bell appeared from `haseen toggle dnd on` / `idle off` and went away again. IPC `notifications toggleDnd` removed and recreated the flag. With DND on, `notify-send` on the scratch bus showed no popup layer; with DND off, `haseen-notifications` appeared.
  - Native screensaver via `haseen screensaver --force`: screenshots show the clock and branding, and the card moved between two shots. Debug `dismiss` removed the layer. CPU over 20 s: 2-3 ticks idle and 3-5 ticks shown (0.15-0.25 %).
  - Flag handling: `screensaver-off` blocked `haseen screensaver` and `startIdle`; `--force` overrode it.
  - Idle-driven run (`screensaverAfter: 3`, lock/dpms 0): the screensaver started 1-6 s after the owner went idle (checked against a probe IdleMonitor). `idle-off` and `screensaver-off` removed the monitors, and re-enabling started it again. Stay Awake turned on during the screensaver dismissed it.
  - Nightlight with fakes:
    - own mode: `hyprctl hyprsunset temperature 4000` failed, so `hyprsunset -t 4000` was started; a settings change sent `hyprctl … 3500`; `refresh` restarted the child with `-t 3500`; off sent TERM;
    - external mode: `temperature 3500`, then `identity`;
    - schedule: a window containing "now" set the flag on.

    The owner's own hyprsunset (pid 1741600) was untouched, apart from a 0.2 s check that `hyprctl hyprsunset identity` answers `ok`, restored to 6500 straight away.
  - ttfx inside a single foot window (killed by PID): ttfx ran with the flags above over the default branding (screenshot). The kill closed it, and `cursor:invisible` was false again afterwards.
  - The earlier python-tte version also ran once, fullscreen on the owner's workspace, before the owner's ttfx decision; that code is gone.
- **Idle RSS** (scratch instance, 25 s settle, same bar): without the ambient plugins 113.5 MB RSS / 75.4 MB PSS; with screensaver, nightlight and both indicators 111.7 / 73.7. The difference is noise; no windows exist at idle.

### Rejected

- python-terminaltexteffects (`tte`): replaced by ttfx on the owner's decision.
- A single-shot timer to the next sunset: Qt timers are monotonic and oversleep a suspend, so the schedule uses a 60 s check, and only while a schedule is set.
- A continuous animation for the native drift: it would repaint every frame on the software backend. A 2 s step costs about 0 % CPU.
- Reconfiguring IdleMonitors in place: the Quickshell bug above.
- A per-plugin FileView for each flag: the shared Flags singleton was approved by Main.

### Not verified

- The ttfx launcher on real monitors and special workspaces. Smoke rules forbid it on the owner's workspaces, so it is covered only by the fake-Hyprland test and the single-window run.
- Real hyprsunset own mode (the owner's instance holds the CTM).
- dpms and lock through idle (disabled in scratch).
- The `haseen_screensaver` window rule (requested from Main).
