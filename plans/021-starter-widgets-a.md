# Plan 021: Starter widgets A: system usage, privacy dots, Omarchy workspaces, media, calendar

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. sysusage, privacy (mic and recording dots live), workspaces, media and calendar were verified live. Camera, screencast and GeoClue were checked by detection only.

## Why this matters

The owner asked for RAM/CPU/GPU usage, iPhone-style privacy dots (green = camera, orange = microphone, red = screen recording/share, blue = location), Omarchy's workspaces plugin copied (MIT), and media and calendar starters.

## Execution record

### What changed

All under `share/haseen/shell/plugins/`, plus `tests/test-widgets-a.sh`.

- **`haseen.sysusage`** (new; bar-widget + panel; permissions `files:read`, `exec`).
  - `Sampler.qml` is shared by the widget and the panel. It samples every 3 s through one `// haseen:sample` Timer, gated by `running: root.active`. The widget's `active` is `visible && QsWindow.window.visible`, and the panel only exists while it is open.
  - CPU comes from a `/proc/stat` delta, where idle counts idle + iowait. RAM is `MemTotal - MemAvailable`, which is `free`'s figure. Both are FileView reloads; the parsers live in `Usage.js`.
  - GPU: `gpu-probe.sh` runs once, on first activation. It is read-only and takes a sysfs-root argument so tests can run it. It picks one method per card:
    - amdgpu: `gpu_busy_percent`.
    - NVIDIA: one long-running `nvidia-smi --query-gpu=utilization.gpu … -i <pci> -l 3` Process, only while active.
    - Intel i915/xe: the idle-residency counter (`gt/gt0/rc6_residency_ms`, `power/rc6_residency_ms`, or xe `device/tile0/gt0/gtidle/idle_residency_ms`), with busy = 1 − Δidle/Δwall. This needs no root.
    - Intel fallback when no residency file is readable: `gt_act_freq_mhz/gt_max_freq_mhz`, labelled "GPU freq".
  - `settings.gpu=auto` reads the boot-VGA card, so a hybrid laptop never wakes a runtime-suspended dGPU (reading amdgpu's busy file or running nvidia-smi does). `off` and `cardN` are also accepted.
  - The panel shows meters for CPU, memory, swap and GPU, and the top 8 processes from `top -b -n 2 -d 1 -o %CPU` (the last frame, `LC_ALL=C`). It opens on a click of the widget.
- **`haseen.privacy`** (new; bar-widget).
  - The dots are green = camera (`Theme.success`), orange = mic (`Theme.warning`), red = screen (`Theme.urgent`), blue = location (`Theme.accent`). The widget has zero size while nothing is active.
  - Detection uses Quickshell's PipeWire link groups. Node types come from the registry and need no binding. Only the matching groups and their two ends are bound (`PwObjectTracker`), to read the link state and the consumer's `application.name`, so nothing is bound while idle.
  - Only `PwLinkState.Active` counts. The rules, in `Privacy.js`:
    - mic: an audio-source device linked to an audio capture stream. A sink monitor does not count, and neither do `Peak detect` meters or `stream.monitor`.
    - camera: a video source that has `media.role=Camera`, or `device.api` v4l2/libcamera, or a `v4l2_input`/`libcamera_input` name.
    - screen: any other video source (the portal's `xdph-streaming-N`).
  - Red also lights from `Flags.recording` (Ambient's singleton; no watcher of its own). Clicking the red dot while recording runs `haseen capture screenrecord --stop`.
  - Location: `geoclue-watch.sh` checks `ListActivatableNames`. It reads `InUse` only if GeoClue already has an owner, because a Get would D-Bus-activate it. It then `exec`s `gdbus monitor` on the Manager, which is event-driven and does not activate GeoClue. It prints `unavailable` and exits when GeoClue is not installed.
  - Hover shows a PopupWindow listing apps per dot. It opens away from the bar edge in any of the four positions.
  - Settings: `showCamera|showMicrophone|showScreen|showLocation`, `ignore[]`, and `debugIpc`, which exposes IPC `haseen.privacy summary()`.
  - The design follows the owner's `t1nk33r.privacy` (bind only the interesting groups; key on the source node). The colours and the extra location/camera split follow this plan's brief, as theme tokens, not the owner's literal iOS hex values.
- **`haseen.workspaces`** (replaced; v2.0.0). This is a port of Omarchy's `shell/plugins/bar/widgets/Workspaces.qml` (MIT notice in both file headers).
  - It shows persistent 1..`persistent` (default 5) plus any existing workspace up to 10. The active workspace gets Omarchy's glyph U+F14FB, empty ones are at 0.5 opacity, 10 is labelled "0", and urgent ones use `Theme.urgent`.
  - Added on top of Omarchy's version:
    - special workspaces as stars, bright while shown on this monitor; a click runs `hl.dsp.workspace.toggle_special(name)`;
    - the wheel sends `e-1`/`e+1`, like SUPER+wheel;
    - per-monitor filtering (`allMonitors`);
    - a vertical layout.
  - Dispatch uses Hyprland 0.56 Lua expressions (`hl.dsp.focus({ workspace = "N" })`) and falls back to legacy dispatchers. The shown special workspace comes from `monitor.lastIpcObject`, refreshed only on `activespecial` events.
- **`haseen.media`** (new; bar-widget). It uses MPRIS through `Quickshell.Services.Mpris`. A playing player wins, then a paused one.
  - The label is "Artist - Title", truncated by code point (`maxLength`, default 40).
  - Left click toggles play/pause; wheel up/down goes to previous/next.
  - It has zero width without a player and shows only the glyph in a vertical bar.
- **`haseen.calendar`** (new; panel). It shows a month grid (`Calendar.js`) with ISO week numbers.
  - The week start follows the locale, or a day name set in `weekStart`.
  - Navigation: arrows, wheel, PgUp/PgDn/Left/Right; Home or a click on the title returns to today.
  - `SystemClock` ticks hourly, only while open.
  - `debugIpc` exposes `haseen.calendar shift(n)/today()/shown()`.
- **`haseen.clock`** (v1.1.0). A left click runs `qs -p <shellDir> ipc call panel toggle <settings.calendar>`. That is the same in-process-less route WidgetsB uses, because no shared toggle API exists. There is a `verticalFormat` setting (default `HH\nmm`). Permission: `exec`.
- All bar widgets declare `vertical` and use `Theme.barForeground`. Panels use `Theme.foreground`.

### Evidence

- `tests/run.sh tests/test-widgets-a.sh`: 65/65.
  - Validate, entry contract, no hex, `barForeground`, and the timer rule (marker + literal ≥ 2000 + gated `running:`); only the sampler ticks.
  - No own flag watchers.
  - 79 pure-JS assertions run under `/usr/lib/qt6/bin/qml` offscreen (the real Qt JS engine): /proc/stat delta, meminfo, residency, frequency, nvidia, GPU pick, top parse, privacy classification, workspace list and dispatch strings, calendar grid and ISO weeks, media pick and truncation.
  - gpu-probe on fixture sysfs trees (i915 rc6, freq fallback, xe, amdgpu, nvidia slot, no nvidia-smi, connectors skipped; it never executes nvidia-smi).
  - geoclue-watch against a stub gdbus (absent → `unavailable`; owned → InUse first, then monitor; not owned → no activating Get).
- `tests/run.sh tests/test-shell.sh tests/test-surfaces.sh tests/test-compat.sh`: 352/352 (with the `haseen:sample` rule).
- shellcheck (`--severity=warning -x`) and `bash -n` pass on the test and both scripts. `jq empty` passes on the 6 manifests. qmllint with the `tools/lint.sh` flags reports 0 errors.
- Live smoke: a scratch instance with its own `XDG_CONFIG_HOME`/`XDG_STATE_HOME`/`XDG_RUNTIME_DIR` (symlinks to the wayland/hypr/pipewire sockets only), `dbus-run-session --config-file=tools/smoke-session.conf`, `QT_NO_XDG_DESKTOP_PORTAL=1`, and idle/lock disabled. A silent `mpv --ao=null` on the private bus served as the MPRIS player. All screenshots were taken with grim and viewed.
  - sysusage bar: CPU 16 %, RAM 44 %, GPU 16 %. At the same moment `top` showed 85.3 % idle (14.7 % busy) and `/proc/meminfo` gave 44.3 % used (`free` used + unreclaimable). The panel's top processes matched `top -b` (electron, herdr, omp, Hyprland).
  - Privacy: idle `summary()` was `dots:[]`. During `pw-record /tmp/wa/x.wav` it was `{"dots":["Microphone"],"usage":{"mic":["pw-record"]…},"tooltip":"Microphone: pw-record"}` and the orange dot was on screen; it went back to `[]` after the recording stopped. Touching `flags/recording` in the scratch state gave the red dot and `"recording":true`; removing it cleared the dot.
  - Camera detection was checked without opening the camera: the real nodes 80/82 (`v4l2_input…`, `device.api=v4l2`, `media.role=Camera`) classify as camera both bound and unbound, and the mics 44/63 as mic.
  - Workspaces: 1 shows the active glyph, 2–4 (occupied, matching `hyprctl workspaces`) are full, and 5 is dimmed.
  - Media: "⏸ haseen - A Fairly Long Smoke Test Song…" with the player running. After the mpv PID was killed, only the clock is left.
  - Calendar via IPC: `panel toggle haseen.calendar` gives October 2026 with today circled and weeks 40–45. `shift -10` gives `2025-12 … weeks=49,50,51,52,1,2`.
  - Left bar (`position: left`): workspaces stack, the clock is `16\n05`, media is glyph only, the red dot shows, and sysusage stacks. There are no binding loops after the fixes below.
- Idle RSS and CPU (software backend, 28 s idle, then CPU over 30 s; same tree):

| config | RSS | PSS | CPU ticks / 30 s |
|---|---|---|---|
| A: HEAD workspaces + clock (user-copy overrides) | 165 / 157 MiB | 106 / 100 MiB | 2 / 1 |
| B: new workspaces + clock + media + privacy + sysusage | 164 / 164 MiB | 103 / 105 MiB | 10 / 9 → **4** after the delegate fix |
| C: B without sysusage | 164 MiB | 103 MiB | 0 |

  RSS is unchanged within noise (under the 10 MiB note threshold). The only idle CPU is sysusage's 3 s sample, about 0.13 % of one core, and only while the bar shows it.

### Bugs found in the smoke and fixed

- `FileView { preload: false }` never loads, even after `reload()`. This was shown with a scratch config: `/proc/stat` printed nothing, while the preloaded view re-read on every `reload()`. The sampler now uses the default preload.
- Workspaces rendered nothing. BarSection sizes a slot's height only once its width is non-zero, and Grid skips zero-height cells, so measuring `grid.implicitWidth` stayed 0. The width is now computed from the cell count.
- In a vertical bar, implicit sizes that read `parent.width/height` looped through BarSection. They now come from content or `Config.barHeight`.
- sysusage rebuilt its Repeater delegates every tick, because its model was an array of values. It now uses a static key model. That took idle ticks from 9–10 to 4 per 30 s.

### Rejected

- **Intel i915 PMU (intel_gpu_top's source):** `perf_event_paranoid` is 2 here, so it needs root or CAP_PERFMON.
- **Per-client DRM fdinfo scanning:** it means walking `/proc/*/fdinfo` every tick (polling).
- **Frequency ratio as the primary Intel source:** that is clock, not load. It is kept only as the labelled fallback.
- **Detecting V4L2-direct camera use (`/dev/video*` opened outside PipeWire):** this needs polling `/proc/*/fd` or `fuser` (architecture 6). Privacy covers PipeWire cameras only.
- **GeoClue client names:** Client objects belong to the requesting peer. The blue dot's tooltip says "Location in use" without an app.
- **A shared privacy service:** each bar runs its own widget. PipeWire bindings are in-process and shared. The GeoClue watcher runs per bar, and only when GeoClue is installed.
- **`Array.from` for code points:** Qt's V4 iterates strings by UTF-16 unit (unit test). A surrogate-pair regex is used instead.

### Not verified live

- Mouse paths, because no pointer injection is allowed:
  - workspace click and scroll;
  - media click and scroll;
  - the privacy hover popup (its text was verified through `summary()`);
  - the red-dot stop click;
  - the clock click.
  The equivalent IPC/dispatch strings are unit-tested.
- Special-workspace stars: none existed, and creating one would move the owner's windows.
- An actual camera or portal screencast: the camera was not opened, and the portal is excluded from smoke buses. The rule was checked against the real camera nodes.
- GeoClue: not installed on this machine. Only the stub-gdbus paths were exercised.
- AMD/NVIDIA/xe readings: fixtures only. This machine is i915.
