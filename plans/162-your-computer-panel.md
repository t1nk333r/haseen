# Plan 162: the Your computer panel

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. A new panel plugin. Nothing runs until it opens; while
  it is open it adds one subscriber to the `sysusage` stream the bar
  widget already holds.
- **Depends on**: 032 (haseen-sidecar), 109 (interface language), 115
  (Omarchy's panel look), 141 (type roles), 156 (drawing at a fractional
  scale)
- **Category**: shell
- **Planned at**: 2026-11-12, from the owner
- **State**: DONE 2026-11-12 (`tests/test-computer.sh` 59/59; the
  affected set of 75 files 8707/8710 from the worktree, the three failures
  Unix socket paths too long there, and those three files, `test-media`,
  `test-menu-back` and `test-wooting`, 368/368 from a short bind mount; seen live
  in a harness against a real haseen-sidecar on luna; the panel in the
  owner's session on luna and IO is an owner step). The history moved to a
  background service in plan 165 (owner, 2026-11-13): the panel no longer
  starts an empty graph each time it opens.

## Problem

The owner, 2026-11-12, sent pocket-dots
(https://github.com/diegoMalagrida/pocket-dots) and asked: "implement from
this: 1. the wallpaper transitions 2. the widget 'your computer' 3. stage
manager". Asked how, they chose "New panel": a new `haseen.computer` panel
opened from the menu and over IPC, with the default-on sysusage widget and
panel left as they are (rejected: "Upgrade sysusage panel"). They approved
"Your computer panel" and the "SUPER+SHIFT+D bind" on by default (owner,
2026-11-12).

pocket-dots' panel (its `media/system.webp`, the frame in the session's
`sys.png`) shows, under a chip icon, "Your computer" and "Uptime 17 h 58 min
· Battery 67 %": a processor card with its percentage, the load and the
thread count and a 90-second line graph; memory with "6,5 of 15,4 GiB" and
its own graph; a temperature card with a word ("Cool") and a graph; and a
storage card with a bar and "49,6 GiB free of 176,1". Behaviour taken from
pocket-dots (GPL-3.0, reference only, nothing copied): its
`PerformancePanel.qml` and README were read for what the panel shows; no
code, string or comment was taken, and NOTICE.md gains no row.

## Decision

### Data: the sidecar's stream, no new Go

haseen-sidecar already samples everything the panel shows when a
subscriber asks for `system`: `subscribeSysusage` reads the flag
(`core/internal/server/server.go:285`), and `Sample` embeds `*System`
(`core/internal/sysusage/sysusage.go:38-46`), which adds `cpuTempC` (-1 when
unknown), `cpuFreqMHz`, `net` and `disks` at the frame's top level
(`core/internal/sysusage/system.go:20-25`). `disks` lists each block device
once, at its shortest mountpoint (`system.go:329-362`), so a btrfs root is
found at `/`.

The panel subscribes as `haseen.sysusage/Sampler.qml` does, in its own code
(plugins never import each other's files): its own key, `Sidecar.ensure()`,
then `Sidecar.want(key, "sysusage", { intervalMs: 3000, gpu: "off", system:
true })` while it is visible and `Sidecar.drop(key)` when it is hidden or
destroyed (`haseen.computer/Panel.qml:105-136`). `Sidecar._sync` merges every
consumer into one subscription (the shortest interval, `system` when anyone
asks; `Haseen/Sidecar.qml:101-124`), so with the bar widget running the
daemon still runs one sampler, and `gpu: "off"` leaves the widget's GPU
choice in force. The panel is gated on `Sidecar.has("sysusage")` and says
"No readings: haseen-sidecar is not running. Start it with: haseen sidecar
start" without it.

The uptime and the load come from `/proc/uptime` and `/proc/loadavg`, read
by a `FileView` that is reloaded when a new frame arrives, with no timer of
its own; the thread count is the online CPU list
(`/sys/devices/system/cpu/online`), read once when the panel opens
(`Panel.qml:138-159`). All three paths start with `$HASEEN_SYSROOT`, as the
CLI's `sysroot_path` does, so the test reads a fixture tree. The battery is
Quickshell's `UPower.displayDevice`, shown only for a present laptop
battery, as the battery panel tests it.

### History only while open

The host creates a panel only while it is open (one `LazyLoader` per panel,
`share/haseen/shell/shell.qml:255-268`), so the histories live in the panel
and go with it. Each sample is `{t, v}` stamped with its arrival time;
`Computer.push` drops samples older than 90 s (`Computer.js:26-32`). At 3 s
a sample, the 90-second line holds 30. Placing points by time, not by
count, keeps the line right if another consumer makes the merged interval
shorter. A freshly opened panel draws a short line at the right edge that
grows leftwards over 90 s (seen in the live run below).

That the history starts at open is the resource rules' price
(architecture 6): nothing may sample while nothing is shown, and panels are
lazy. Rejected: **a history kept by the sidecar** (a ring buffer per stream
in Go). It would have the line full at once, but the daemon would have to
sample `system` all the time for a panel that is rarely open, or keep a
buffer that is empty whenever it matters; it is new Go and a new protocol
field for a convenience. Rejected: **an always-on sampler in the shell**
(a service keeping the 90 s while the panel is closed). It breaks
"samplers gated on visibility" and costs a sample every 3 s forever.

### Graphs: QtQuick.Shapes

`Graph.qml` draws the line and a faint fill under it as two `ShapePath`s
whose `PathSvg` paths come from `Computer.linePath` and `Computer.areaPath`,
plus a dot on the newest sample. Shapes has a software backend: on
haseen's default renderer it paints with QPainter at the window's scale. A
Canvas or a layer comes out wrong at a fractional scale on that renderer
(plan 156); IO runs software at 1.25. On rhi, `preferredRendererType:
Shape.CurveRenderer` (`Graph.qml:41`) antialiases the line without
multisampling. The line is a monotone cubic (Fritsch and Carlson,
`Computer.js:105-132`): smooth, but it never swings past its samples, so a
0 % line does not dip under the floor. Time runs left to right in every
language (`LayoutMirroring.enabled: false`, `Graph.qml:27`), as
architecture 5.8 asks of time graphs.

Each percentage graph has its own top, the smallest of 10, 25, 50 and 100
over its samples (`Computer.js:37-47`), shown at its top left ("50 %"), so
the scale changes rarely and a busy line is not flattened. The
temperature graph's range is whole tens around its samples, at least
20 °C tall (`Computer.js:52-71`).

### Temperature words

Under 60 °C Cool, 60 to 79 Warm, 80 and over Hot (`Computer.js:158-173`).
Processors idle between about 35 and 55 °C and run in the 60s and 70s
under sustained load; Intel parts throttle at 100 °C and AMD's at 95 °C
(Tctl), with fans at full speed from about 80 °C. Warm turns the word and
the line the warning colour, Hot the urgent one. When the sidecar reports
-1 (no sensor) the card says "Unknown", draws no graph and records nothing.

### Look

Omarchy's panel vocabulary on Theme tokens: the host's `PanelSurface`
card, a `PanelSeparator` under the header, cards in `Theme.normalFill` with
a `Theme.separator` hairline and Hyprland's rounding, Theme type roles
(title for the header, heading for readings, body, bodySmall, caption) and
spacing tokens; `tools/fonts.py check` passes. The storage bar is the shared
`TrackBar`, read only, which Omarchy fills in muted (pocket-dots fills it
in its accent). Numbers go through `I18n.formatNumber`; sizes show one
decimal, none when the total reaches 1000 GiB ("592 GiB free of 1861"). The
panel is `Theme.fontSize * 54` wide (648 px at 12), two columns: processor
and memory on the left, temperature over storage on the right. There is no
"Control Centre" back button: haseen has no control centre.

In Arabic the panel mirrors (PanelPopup's `LayoutMirroring`): the header,
the headings and the cards swap sides and the storage bar fills from the
right, while the graphs keep time running to the right. The Arabic storage
line starts with a word ("متاح %1 GiB من %2") so the paragraph reads right
to left; starting with the number made it a left-to-right paragraph.

### Wiring

- `haseen.computer`: `manifest.json` (kind `panel`, setting `mount`,
  default `/`), `Panel.qml`, `Graph.qml`, `Computer.js`. On by default: it
  is not switched off in `share/haseen/default/shell.json` (a panel plugin
  is enabled unless `plugins.<id>.enabled` is false,
  `Haseen/Config.qml:101-103`), and CLAUDE.md lists it with the bind.
- `SUPER + SHIFT + D` → `ipc("panel", "toggle", "haseen.computer")`, "Your
  computer", in the Shell section of `share/haseen/default/hypr/binds.lua`.
  The chord was free in haseen; Omarchy binds its Docker TUI there
  (`/usr/share/omarchy/default/hypr/bindings/applications.lua:16`), which
  haseen does not bind.
- The menu's Trigger gets "Your Computer" right after Emoji, the other row
  that opens a panel there; the root is Omarchy's tree and
  `tests/test-menu.sh` pins it. Its guard shows the row unless the user
  switched the plugin off, and with no `shell.json` at all: `! jq -e
  '.plugins["haseen.computer"].enabled == false' …`, the "on unless off"
  form of the `.enabled == true` guards the off-by-default rows use.
- 19 interface strings and the menu row in English and Arabic
  (machine-made, `ar/provenance.json`).

## Verification

- `tests/test-computer.sh` 59/59:
  - Computer.js under `/usr/lib/qt6/bin/qml`: the window (40 samples keep
    31), unknown readings skipped, the scale steps, the temperature
    range, points by time inside the pad, the path strings, a zigzag whose
    curve stays inside its samples, the words at 59.9/60/79/80, GiB, the
    uptime, the load, the thread count and the disk pick.
  - The real `Panel.qml` under qs, offscreen, software renderer, against a
    fake frame and a fixture `/proc`: the subscription it asks for
    (`intervalMs` 3000, `system` true), the no-daemon message, the texts
    "Your computer|Uptime 17 h 58 min|Processor|7 %|load 1.35 · 8
    threads|last 90 s|50 %|Memory|42 %|6.5 of 15.4 GiB|50 %|Temperature|
    Cool|40 °C|Storage|76 %|49.6 GiB free of 176.1", "Unknown" with no
    graph for -1, and no subscription once closed.
  - Pixels, read with ImageMagick from a full-scale `grabToImage`: the
    processor and temperature lines reach all ten vertical strips of their
    graphs at scales 1 and 1.25, and the 1.25 picture is the whole panel
    (850 × 471 for 680 × 377).
  - Arabic, mirrored: the strings, the processor card on the right, the
    line still crossing its graph.
  - The menu guard: shown with no `shell.json` and with the plugin on,
    hidden with it off.
- On rhi, by hand on luna (`DISPLAY=:0 QT_QUICK_BACKEND=rhi
  QSG_RHI_BACKEND=opengl`, `GraphicsInfo.api` not software): the same
  picture.
- Live against a real haseen-sidecar built from this tree, in a harness on
  luna's own `/proc`, twice: the frames carried `cpuTempC` (51.9 to 55.1 °C
  in the first run, "Cool"; 64.6 to 65.0 °C in the second, "Warm") and the
  disks `/` and `/boot`; the panel read "Uptime 1 d 0 h", "load 4.14 · 16
  threads" (luna has 16), "22.7 of 60.5 GiB" and, in the second run,
  "595 GiB free of 1861"; it grew its line by one point every 3 s, and the
  subscription went when it closed.

## Resource cost

- Closed: nothing. No object exists until the panel opens
  (`shell.qml:255-268`); the plugin adds its manifest to the registry scan
  every plugin has.
- Open: one subscriber to the stream the bar widget already holds, now with
  `system`, so the sidecar also reads the CPU temperature, each CPU's
  clock, the network counters and `statfs` for each disk every 3 s; two
  small file reads per sample; no timer, no process.
- RSS, measured in a qs harness on luna (software renderer, the theme's
  font already drawn so only the panel's own cost shows, a real sidecar):
  103 MiB with the panel closed, 125 MiB open (+22 MiB), 124 MiB after it
  closed. The same harness opening the existing haseen.sysusage panel:
  102 MiB, 125 MiB (+22 MiB), 121 MiB. The open cost is the first panel and
  sidecar connection a session pays anyway, and most of it stays allocated
  after close, as for any panel. The idle shell before the first open does
  not grow.

## Rejected options

- **Upgrading the sysusage panel** instead of a new one: the owner chose a
  new panel and left the default-on widget and panel alone.
- **Canvas for the graphs**: wrong at a fractional scale on the software
  renderer (plan 156), which IO uses.
- **A history in the sidecar** and **an always-on sampler**: above.
- **Count-based history** (30 slots): wrong as soon as another consumer
  shortens the merged interval.
- **A root menu row** beside About and System: the root is Omarchy's tree
  in Omarchy's order (plan 068, `tests/test-menu.sh`).
- **An accent-filled storage bar** of the panel's own: the shared
  `TrackBar` keeps Omarchy's read-only look.

## Residual unknowns

- Not yet opened in the owner's session. On luna (rhi, scale 1) and IO
  (software, scale 1.25): press SUPER + SHIFT + D, or open Trigger > Your
  Computer, check the readings against `btop`, leave it open for 90 s to see
  the line fill, and close it.
- A machine whose sensor the sidecar does not know shows "Unknown"; which
  sensors it knows is plan 032's table.
