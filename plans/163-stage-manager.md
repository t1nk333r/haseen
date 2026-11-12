# Plan 163: Stage Manager on the screen's edge

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. At rest the only new thing is one transparent strip two
  pixels wide per screen, which draws nothing, reserves nothing, moves
  aside for the bar and lets every click through whenever the stage may not
  open. The stage itself exists only while it is out.
- **Depends on**: 019 (the context flags), 062 (the game context), 105
  (Hyprland's Lua dispatch), 115 (Theme), 156 (layers at a fractional scale)
- **Category**: shell
- **Planned at**: 2026-11-12, from the owner
- **State**: DONE 2026-11-12 (`tests/test-stage.sh` 73/73, the affected
  set below). The live edge push on luna (rhi) and on IO (software renderer,
  scale 1.25) are owner steps.

## Problem

The owner, 2026-11-12, sent pocket-dots
(https://github.com/diegoMalagrida/pocket-dots) and asked: "implement from
this: 1. the wallpaper transitions 2. the widget 'your computer' 3. stage
manager". This plan is the third. In pocket-dots, pushing the pointer
against the left edge slides the other workspaces in as stacks of their real
windows, turned towards the middle of the screen; a click goes there.

Asked about defaults the same day, the owner approved "Stage Manager edge"
on by default (owner, 2026-11-12). No key was approved, so none is bound.

Behaviour taken from pocket-dots (GPL-3.0, reference only, nothing copied):
its README's "Stage Manager" section and the behaviour of its
`StageWindow.qml`, `StageWorkspace.qml` and `StageThumbnail.qml`, and the
demo frames. haseen's plugin is written from scratch; no NOTICE row.

## Decision

A new built-in `service` plugin, `haseen.stage`
(`share/haseen/shell/plugins/haseen.stage/`), on by default: last in the
default `services` (`share/haseen/default/shell.json`) and in `AGENTS.md`'s
approved list.

### What exists when

| state | objects | timers |
|---|---|---|
| at rest | `Service.qml` and one `EdgeStrip.qml` per screen | none |
| pointer resting on a strip | the same | the dwell, one single shot (`EdgeStrip.qml:70-80`, `// haseen:ui-timeout`) |
| stage out | `StageWindow.qml` with `StageView`, a `StageStack` per workspace and a `StageCard` per window, each card one `ScreencopyView` | the 350 ms leave grace (`StageView.qml`), single shot |
| stage slid out | back to rest: the window is a `LazyLoader` keyed on `stageScreen !== null` (`Service.qml:211-218`), so its pictures go with it | none |

Every window is its own file loaded by URL, as `haseen.osd` does
(`plugins/haseen.osd/CardWindow.qml:8-11`), so `Service.qml` compiles in
the offscreen engine of the tests, where qs reports "No PanelWindow backend
loaded." for an inline `PanelWindow` (measured with a scratch config).

### The hot edge

`EdgeStrip.qml`: a `PanelWindow` anchored to the top, the bottom and the
chosen edge (`edge`, `left` or `right`, default `left`), 2 px wide
(`EdgeStrip.qml:38`), transparent, `ExclusionMode.Normal` with no zone of
its own (`:39`), on the Top layer (`:48`), never the keyboard (`:49`). Its
input mask is the whole strip while the stage may open and empty otherwise
(`:43-46`), so a quiet strip lets every click through.

The pointer must rest on the strip for `dwell` ms (default 200, 100-1000)
with no button held. A press stops the dwell (`:62`): a click there was
meant for something else, or a window or a file is being dragged to the
edge. During a drag that started elsewhere Wayland's implicit grab keeps the
pointer's focus on the surface where the drag began, so the strip gets no
enter at all; the check catches a press made on the strip itself.

The edge stays quiet (`Stage.suppressed`, `Stage.js:45-58`), in this order:

1. the screen is locked (`haseen.lock`'s `locked`,
   `plugins/haseen.lock/Service.qml:71`, through `Plugins.roles.lock`);
2. the game context is on (`Flags.context`, `Haseen/Flags.qml:46`);
3. that monitor's active workspace has a fullscreen window
   (`HyprlandWorkspace.hasFullscreen`); the Top layer also puts the strip
   under a fullscreen window, which Hyprland draws above that layer;
4. a mouse button is held;
5. there is nothing to show (checked when opening).

Becoming locked or entering the game context closes an open stage
(`Service.qml:175-178`); so does a window going fullscreen on its monitor
and any change of that monitor's workspace (`StageWindow.qml`).

**The bar.** The bar is a Top-layer surface anchored to its whole edge with
`ExclusionMode.Normal` and `exclusiveZone: thickness` (`Bar.qml:88-103`,
`:109`). A strip with an exclusive zone of 0 is one the compositor moves to
avoid any surface that reserves an edge (the layer-shell protocol's meaning
of zero, which `haseen.pager` relies on for its deck, plan 157). So:

- bar on top (the default): the left strip starts under the bar and never
  covers the logo or the workspaces in the bar's corner;
- bar on the left with the left edge chosen: the strip runs along the bar's
  inner side. Pushing against the screen's edge lands on the bar, which
  keeps every click and its drag; the stage opens when the pointer rests
  just inside the bar instead. Recorded as the decision: the bar's input
  is never taken, and the stage stays reachable.

`tests/test-stage.sh` checks that the strip keeps Normal exclusion, sets no
`exclusiveZone`, uses the Top layer, never takes the keyboard and empties
its mask when quiet.

### The stage

`StageWindow.qml`: an Overlay-layer `PanelWindow` on the opened screen,
anchored like the strip and as wide as the column of stacks, Normal
exclusion (beside the bar too). Its input mask is the column and the edge
(`StageWindow.qml:38-44`), so the rest of the screen stays usable; leaving
both closes it after a 350 ms grace, a click on a stack switches to that
workspace, Escape closes it. The keyboard is taken when the window appears
and then held on demand (`StageWindow.qml:47-56`), the pattern
`PanelPopup.qml:53-70` uses: with plain on-demand focus Hyprland gives a
layer the keyboard only after a click inside it (`PanelPopup.qml:55-56`),
and a click on a stack closes the stage, so Escape would never arrive. The
cost: while the stage is out, typing goes to it, not to the window in
focus; it is out only while the pointer is on it. An
IPC open stays out until the pointer has entered and left, Escape, another
toggle or a workspace change.

What it shows, from Quickshell's Hyprland objects (`Service.stacksFor`) and
`Stage.stacks` (`Stage.js:83-101`): that monitor's workspaces with a window,
not the special ones (scratchpads: negative ids or a `special:` name) and not
the one on screen, by number. Each stack holds up to `maxWindows` (default
3, 1-4) windows, the most recently focused in front, by Hyprland's
`focusHistoryID` (`Stage.stackWindows`, `Stage.js:69-73`; 0 is the focused
window, larger is older, as `hyprctl -j clients` showed on luna:
`"focusHistoryID":0` for the window in focus). A window Hyprland hides (a
group's background tabs) is not drawn. Quickshell 0.3.2's
`HyprlandToplevel` exposes the field only through `lastIpcObject`
(`/usr/lib/qt6/qml/Quickshell/Hyprland/_Ipc/quickshell-hyprland-ipc.qmltypes`:
`address`, `wayland`, `title`, `lastIpcObject`, `workspace`, `monitor`), and
`lastIpcObject` is filled by a request, so each open calls
`Hyprland.refreshToplevels()` once (`Service.qml:136`), as `haseen.windows`
does on its first query. The stacks follow the objects through bindings
while the stage is out; a `ScriptModel` keyed on the workspace id and on the
window address keeps the delegates, and so the pictures, when a refresh
lands. While the column slides out the stacks are frozen
(`StageView.qml`), so a switch does not reshuffle them on the way.

The switch is `Stage.focusCommand` (`Stage.js:197-202`): Hyprland 0.56's Lua
expression `hl.dsp.focus({ workspace = "N" })` under Lua config, else
`workspace N`, as `haseen.workspaces` builds it
(`plugins/haseen.workspaces/Workspaces.js:38-40`); anything that is not a
positive integer gives "" and nothing is dispatched.

Icons: a window's desktop entry's icon (`DesktopEntries.heuristicLookup`),
else its class as an icon-theme name, never a path or a URL a client chose
(`Stage.themeIcon`, the rule of `haseen.windows`'s `Windows.themeIcon`,
plan 081), resolved with `Quickshell.iconPath(name, true)`; a window glyph
when the theme has neither.

### The pictures

Each card is a `ScreencopyView` of the window's `HyprlandToplevel.wayland`
with `live: false` (`StageCard.qml:44-52`): Hyprland sends one frame, nothing
streams, and the view dies with the stage. Where there is no picture (no
toplevel handle, the capture failed or has not arrived) the card is a tile
of `Theme.surface` with the app's icon.

The software renderer can show a capture. `/usr/bin/quickshell` (0.3.2)
carries the strings "Failed to query render formats: No EGL context." and
"Render format initialization failed. All buffers will fall back to SHM."
(`strings /usr/bin/quickshell`), and the headless draws on the software
renderer log exactly that ("Failed to query render formats: No GL context.
… All buffers will fall back to SHM."): without a GL context Quickshell
asks the compositor for shared-memory buffers, which an image texture can
draw on any renderer. On rhi it takes dmabufs. A capture was not taken in
this work (no compositor may be touched); that is in the owner steps.

### The turn

A 3D `Rotation` about the vertical axis through the stack's edge side
(`StageStack.qml:64-82`): `Stage.tilt` (`Stage.js:176-180`) gives `tilt`
degrees (default 50, 0-60) on the left edge and its negative on the right,
turning the far side away so the stack faces the middle of the screen;
under the pointer it turns part of the way back (0.55 of it) and the cards
spread (1.5 times their step).

What each renderer does with it, from headless draws at scales 1 and 1.25
(a 240×160 rectangle and a three-card stack of pictures turned 40°, then the
stage itself):

- **Software** (`GraphicsInfo.api` 1): the projection is drawn, pictures
  included, at both scales, and the cards overlap in order. The affine-only
  fallback the plan expected was not needed. A layer is not used there: a
  software layer loses part of its picture at a fractional scale (plan 156).
- **rhi** (`DISPLAY=:0 QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl
  QT_QPA_PLATFORM=offscreen`, `GraphicsInfo.api` 3): cards turned each on
  their own lie in planes that cross, and the depth test cuts them where
  they meet (dashed and scalloped edges on the cards behind, worse at 1.25).
  So on rhi the whole stack is drawn flat into a layer and the layer is
  turned (`StageStack.qml:60-61`), one quad, clean at both scales.

`tilt: 0` draws a flat fan, the same cards stepped away from the edge and
up, smaller and dimmer; `tests/test-stage.sh` checks it.

### Look

Followed from pocket-dots' frames (`sgrid.png`): stacks hugging the edge,
centred down the screen, the front window bottom-left and the ones behind
stepping up and away (`Stage.fan`, `Stage.js:155-165`: 0.08 of the plane's
width across, 0.07 up, 6 % smaller and 15 % dimmer a card), the app icon and
the workspace's number facing the viewer at the stack's corner on the edge
side, a soft shade of `Theme.background` from the edge while it is out. The
plane is 13 % of the screen's width, between 160 and 260 px; many stacks
shrink to half size, then the stage shows the first that fit by number
(`Stage.metrics`, `Stage.js:106-136`). A drop shadow would need a blur
(architecture §6); a flat shade one step down and to the side stands in.
Slide in 220 ms (OutCubic), out 160 ms (InCubic), through `Theme.duration`,
so nothing moves while Hyprland's animations are off.

Draws, in the scratchpad of the session that built this plan (not
committed): `out/final-left-{software,rhi}-{1,1.25}.png`,
`out/final-right-{software,rhi}-{1,1.25}.png`, `out/final-flat-left-software-{1,1.25}.png`.

### No visual clutter

Nothing shows until the pointer rests against the edge: the strips are
transparent and draw no pixel (no hint mark, unlike pocket-dots' accent
tick), and the stage is gone as soon as the pointer leaves.

### Defaults reach existing users

`share/haseen/migrations/1794512737-stage-service.sh` appends
`haseen.stage` to a user `shell.json` that has its own `services` array
(arrays replace the default), as plan 075 did for `haseen.battery`; a user's
`plugins."haseen.stage".enabled: false` still wins.

## Resource cost

Measured with a scratch qs config on the offscreen platform and the
software renderer (`measure.sh` in the session scratchpad): one bar-sized
window, plus 0, 1 or 2 strip windows built as `EdgeStrip.qml` builds its
content (a hovering `MouseArea` and a single-shot timer). The offscreen
platform has no layer shell, so the strips are `FloatingWindow`s there.

| strips | RSS after 5 s (KiB), rounds 1-3 | CPU ticks over the next 10 s |
|---|---|---|
| 0 | 86956, 86772, 87028 | 0, 0, 0 |
| 1 | 86968, 87008, 87196 | 0, 0, 0 |
| 2 | 86988, 86780, 86820 | 0, 0, 0 |

The difference is inside the run-to-run noise (±250 KiB): well under 1 MiB
for the strips, and no CPU at rest. On Wayland each strip's buffer is
2 × height × 4 bytes at scale 1 (11.5 KiB on a 1440 px screen).

While the stage is out it holds one window picture per card, at most
`maxWindows` per workspace: on the software renderer a shared-memory buffer
of the window's size (a 1264×690 window is 3.3 MiB), dropped when the stage
closes. On rhi the buffers are dmabufs. The idle budget is untouched.

## Verification

- `tests/test-stage.sh`: the manifest, the default and the migration; the
  strip's contract with the bar and the rule that nothing is bound; 61
  checks of `Stage.js` under Qt's JS engine; the service in the real
  Quickshell engine (no compositor: a toggle is refused as `empty`; the game
  context and a held button keep the edge quiet); the stage drawn headless on
  the software renderer at scales 1 and 1.25 on both edges (nothing before it
  slides in, nothing past its column, the front card's near side taller than
  its far side, a close before it slid in closes at once, one while it is out
  closes after the slide) and flat at tilt 0: 73/73.
- Gates: `tools/lint.sh` ("lint OK"); `tests/run.sh --affected origin/main`,
  96 files (the default `shell.json` and a new manifest select most of the
  shell's tests): 10658/10659 from a short bind mount, the one failure
  `test-vapt-workflow.sh`'s seed check, a path doubled under the bind
  mount's `/tmp`; that file passes 167/167 from the real path with `TMPDIR`
  outside `/tmp`; `tools/check-docs.sh` ("check-docs OK").

Not verified here (owner steps): the live edge push and dwell, a real
capture, the click switch and Escape, on luna (rhi) and on IO (software,
scale 1.25), and the strip beside a left bar.

## Rejected

- **No dwell, open on contact.** Passing the pointer over the edge on the
  way to a window's border would open it.
- **A strip on the Overlay layer over the bar's outer pixels**
  (pocket-dots ignores exclusive zones). It would take the clicks and drags
  meant for the bar's edge, and with the bar on top the clicks on its corner.
- **Disabling the edge when the bar is on the same edge**, or moving it to
  the other edge by itself. The stage would vanish or move without the user
  asking; resting beside the bar keeps it where the setting says.
- **Plain on-demand keyboard focus.** Escape would not reach the stage
  (`PanelPopup.qml:55-56`).
- **Turning each card on its own on rhi.** The depth test cuts crossing
  planes (above).
- **A flat fan as the software renderer's only look.** The software
  renderer draws the projection correctly; `tilt: 0` keeps the flat fan for
  anyone who wants it.
- **Live pictures.** A stream per window while the stage is out costs a
  frame per window per refresh for nothing a still does not show.
- **A drop shadow through MultiEffect** (pocket-dots does): a blur, against
  architecture §6.
- **Showing empty workspaces as numbered chips** (pocket-dots does): the
  workspaces widget in the bar already shows them, and it is clutter here.
- **A default key.** None was approved; `haseen shell ipc stage toggle`
  is there for a user's own bind.
