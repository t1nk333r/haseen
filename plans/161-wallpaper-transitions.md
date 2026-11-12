# Plan 161: wallpaper transitions

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MEDIUM. The wallpaper itself still comes from swaybg and
  always changes: the CLI restarts it whatever the shell answers. The new
  parts are a service in `haseen.background` that is idle (nothing loaded)
  between changes, the shell's first and only shader, and a bounded wait in
  `theme_background_reload` of at most 1.2 s, only while a haseen shell
  answers.
- **Depends on**: 020 (themes and backgrounds), 106 (per-theme
  backgrounds), 115 (Theme's `reduceMotion`), 152 (the background picker)
- **Category**: shell, themes
- **Planned at**: 2026-11-12, owner: "implement from this: 1. the wallpaper
  transitions ...", pointing at pocket-dots; asked in the same session the
  owner chose "Shader, GPU only" and approved "Wallpaper transition" on by
  default (owner, 2026-11-12)
- **State**: DONE 2026-11-12. `tests/test-bg-transition.sh` passed 103/103
  with a GL display (`HASEEN_GL_DISPLAY=:0`) and 73/73 without one. Seeing
  it live on luna (GPU scene graph) and IO (software, scale 1.25) is an
  owner step.

## Problem

A background change is a cut. `haseen theme bg set|next` and `haseen theme
set` move `current/background` and restart `haseen-background.service`
(`theme_background_reload`, `share/haseen/layers/theme/theme-lib.sh:1020`),
and the restarted swaybg paints the new image (`bin/haseen-theme-bg-run:34`,
`:50`). Between the old process going and the new one painting, the
compositor shows whatever is under the Background layer.

The owner sent pocket-dots (GPL-3.0) and asked for its wallpaper
transitions: colonies that eat through the old wallpaper in crisp square
cells with a lit edge ("contagio"), and a quiet line that traces the new
image's outline and fills in from it ("perfil"). Its demo frames are the
reference for the look. Behaviour taken from pocket-dots (GPL-3.0,
reference only, nothing copied): its effect maps come from a Python
pre-pass with an ML segmentation model (`wallfx elige`); haseen computes
everything in the shader, per pixel, with no prepared map, no Python and
no model.

## Decisions

### On by default, in haseen.background, as a service

The owner approved "Wallpaper transition" on by default (owner,
2026-11-12). It is a `service` entry of `haseen.background`
(`manifest.json` `kinds: ["panel", "service"]`, entry `Transition.qml`),
listed last in `share/haseen/default/shell.json` `services`. A user
`shell.json` with its own `services` array gets it from migration
`1794511775-background-transition.sh`, as plan 075 did for the battery
service. Its settings sit beside the picker's in the manifest:

- `transition`: `auto` (default; contagion and outline in turn), `contagion`,
  `outline`, `fade` or `none`;
- `transitionDuration`: 1800 ms, held to 400-5000.

`haseen.background` is part of the desktop that is never optional, so the
way to turn the effect off is `transition: "none"`, not disabling the
plugin.

### The CLI asks the shell around the restart

`theme_background_reload` (`theme-lib.sh:1020`) is the one place every
command goes through, so the hand-over lives there:

1. It reads the image swaybg shows from the service's main process
   (`systemctl --user show -p MainPID --value`, then `--image` in
   `/proc/<pid>/cmdline` through `sysroot_path`;
   `theme_background_shown`, `theme-lib.sh:982`). On luna that read
   `swaybg --mode fill --image ~/.local/state/haseen/current/theme/backgrounds/7-akane.jpg`
   (2026-11-12). This is what is on screen even when the link moved
   without a restart (a migration relinks without one).
2. `background begin OLD NEW` over `qs ipc call` with a 1 s `timeout`
   (`theme_background_ipc`, `theme-lib.sh:1001`), skipped under DMS
   (`active-shell`). The shell answers `loading` or `skip <reason>`.
3. On `loading` it asks `background state` every 30 ms until the answer is
   no longer `loading`, for 1.2 s at most (`theme-lib.sh:1036`). A `qs ipc
   call` took 14 ms against the live shell and 11 ms when no instance
   answered (measured 2026-11-12), so the poll is cheap and short.
4. It restarts swaybg as before, whatever the answers were.
5. `background shown`, best effort.

Under `--dry-run` it prints the three steps and calls nothing. With no
haseen shell, DMS active, the same image, a colour instead of an image, or
any answer but `loading`, swaybg restarts at once: the wallpaper always
changes.

### The shell covers, plays, then hands back

`Transition.qml` keeps the steps in `Transition.js` (`reduce`): idle,
loading, playing, holding, leaving.

- `begin` opens one cover per screen (`TransitionWindows.qml`): a
  `PanelWindow` on `WlrLayer.Bottom` (line 40), above swaybg's Background
  layer and below every window, `ExclusionMode.Ignore`, an empty input
  mask, namespace `haseen-background-transition`. The default
  `windowrules.lua` gives that namespace `no_anim`, so the cover is whole on
  its first frame; with Hyprland's `layersIn` fade
  (`share/haseen/default/hypr/looknfeel.lua:100`) a half-faded cover would
  show swaybg's gap.
- Each cover decodes both images asynchronously at the screen's pixel size
  with `PreserveAspectCrop`, which is swaybg's `fill` (cover, centred). Two
  frames after both are ready (`FrameAnimation`, line 77) the screen counts
  as covered; when every screen is, the effect starts and the CLI's poll
  sees `playing`.
- The effect runs from the old image to the new one; swaybg restarts
  underneath while it does. `shown` arms a 500 ms hold for the new swaybg
  to paint. The cover leaves once the effect has ended and the hold has
  passed, or 3 s after the effect ended without a `shown`, by fading out
  over 160 ms between two renders of the same picture. Leaving frees the
  windows, both images and the shader.
- Bounds: images that do not draw in 1.5 s, or a `shown` that arrives while
  still loading (the CLI gave up waiting), end the change at once with no
  cover. A change during a change starts over.
- Skipped (instant): `transition: none`, the same image, Hyprland's
  `animations:enabled` off (`Theme.reduceMotion`,
  `share/haseen/shell/Haseen/Theme.qml:133`), the `game` context
  (`Flags.context`, `share/haseen/shell/Haseen/Flags.qml:46`), no screen.

### The shader, and the crossfade

`TransitionView.qml` draws one screen. On a GPU scene graph, contagion and
outline load `ShaderView.qml` through a `Loader` that is active only then
(`wantsShader`, line 29, from `GraphicsInfo.api`). On the software renderer
(haseen's default, IO) and for `fade` it is a plain opacity crossfade of
the two images, and `ShaderView.qml` is never instantiated
(`tests/test-bg-transition.sh` checks `"loaded":false` at scales 1 and
1.25). A shader that fails to build falls back to the crossfade.

`transition.frag` (GLSL 440, compiled with `qsb --qt6` into
`transition-1.frag.qsb`; the number changes with the shader because Qt
caches a compiled shader by URL):

- Both images are sampled through a cover transform (`Transition.js`
  `coverScale`), so the shader shows each exactly as swaybg's fill does.
  Progress 0 returns the old image and 1 the new one, untouched.
- **contagion**: six colonies, one in each sixth of the screen, start at
  random moments in the first half (one at once). A cell of 4 logical
  pixels turns when the nearest colony reaches it through a space bent by
  value noise and roughened by a finer one, so fronts wander and finger
  instead of growing as circles. A turning cell is lit in `Theme.accent`
  for 4 % of the change and cools into the new image. A monotonic squeeze
  makes the last cells turn by 0.93 without breaking the fronts up.
- **outline**: a Sobel filter on the new image's luminance, read from its
  first mip level so fine texture does not count, gives a 1-2 px line in
  the theme's foreground a fifth of the way to the accent at 75 %, drawn in
  along a slow noise over the first 40 % and faded out from 72 %. Cells
  turn by how much structure lies near them (gradients of blurred copies,
  mip levels 3.5, 5 and 6.5) mixed with a slow noise, so the image fills
  from its lines outwards in the same cells. The edge strength is scaled up
  for a soft picture by the spread of 16 samples of a heavily blurred copy.

The new image is decoded with mipmaps only when the shader draws it.

## What changed

- `share/haseen/shell/plugins/haseen.background/`: `manifest.json` (kind
  `service`, settings `transition`, `transitionDuration`, version 1.1.0);
  `Transition.qml` (the service and the `background` IPC target),
  `Transition.js` (pick, skip rules, cover math, cell size, the steps),
  `TransitionWindows.qml` (the covers), `TransitionView.qml` (one screen),
  `ShaderView.qml` (the one `ShaderEffect`), `transition.frag` and
  `transition-1.frag.qsb`.
- `share/haseen/layers/theme/theme-lib.sh`: `theme_background_shown`,
  `theme_background_ipc`, and the hand-over in `theme_background_reload`.
- `share/haseen/default/shell.json`: `haseen.background` in `services`.
- `share/haseen/default/hypr/windowrules.lua`: `no_anim` for the covers.
- `share/haseen/migrations/1794511775-background-transition.sh`.
- `docs/architecture.md`: §6's one shader exception, the `background` IPC
  target in §5.5, the transition in §7's backgrounds.
- `AGENTS.md` (`CLAUDE.md`): the approval in the default list.
- Tests: `tests/test-bg-transition.sh` (new); `tests/test-widgets-c.sh`
  (the picker still paints no wallpaper, the service is the plugin's one
  Timer owner and starts no daemon), `tests/test-carousel.sh` (the picker
  has no shader; `ShaderView.qml` is excluded by name),
  `tests/test-themes2.sh` (the `show` query before the restart).

## Resource cost

- **Idle**: nothing is loaded. The service is a `Scope` with an
  `IpcHandler`, three stopped single-shot timers, two stopped animations
  and an inactive `LazyLoader`; no window, image, texture or shader exists
  until `begin`. Measured with `qs` offscreen on the software renderer,
  seven runs each of a harness with the same imports and singletons with
  and without the service (2026-11-12): median RSS 80136 KiB without,
  80472 KiB with (+0.3 MiB), against a run-to-run spread of 76040-88760
  KiB. No timer runs at idle and nothing polls.
- **During a change** (about 2.3 s with the hand-over): one layer surface
  per screen and two decoded images at that screen's pixel size, 4 bytes a
  pixel: 2 x 8.3 MB at 1920x1080 and 2 x 33 MB at 3840x2160, the new one a
  third more with mipmaps on the GPU path (computed, not measured). The
  outline shader reads 38 texels a pixel (two images, 16 contrast samples
  of a tiny mip level, 12 for the coarse gradients, 8 for the line), the
  contagion one 2 plus arithmetic. All of it is freed when the cover goes.
- **CLI**: at most 1 + 40 + 1 `qs ipc call` processes of about 14 ms each,
  and only while a haseen shell answers `loading`.

## Verification

- `tests/test-bg-transition.sh`, 103/103 with `HASEEN_GL_DISPLAY=:0` and
  73/73 without (the shader draws need a GL context, which the sandbox and
  CI do not have; they skip with a message):
  - manifest, defaults, `ShaderEffect` only in `ShaderView.qml`, no other
    shader file in the shell, the covers' layer, input and exclusion, the
    layer rule, no hex colour;
  - the committed `.qsb` equals a fresh `qsb --qt6` compile when qsb 6.12
    is present (two compiles were byte-identical, `cmp`, 2026-11-12); CI's
    `ARCH_PACKAGES` (`.github/workflows/ci.yml:40`) has no
    `qt6-shadertools`, so there it skips;
  - the migration;
  - the CLI against stubs: begin, two state polls, restart, shown, in that
    order; a skip, the same image, DMS, no shell and swaybg stopped each
    restart without the rest; `--dry-run` calls nothing;
  - `Transition.js` under Qt's JS engine: settings, duration bounds, auto
    taking turns, the shader only for contagion and outline off the
    software renderer, every skip reason, cover scales, cell sizes, and
    seven event sequences of the steps;
  - the service in the real Quickshell engine (offscreen, no layer shell):
    skips answer `skip same image`, `skip not a path`, `skip off`; a real
    change answers `loading` and is back to idle at the 1.5 s bound; with
    the screens reported covered by hand, a 0.4 s fade plays, holds for
    `shown`, holds 0.5 s more, fades out and ends idle with `played`;
  - drawing with a red 16:10 old image and a blue 2:1 new one with a white
    block: the software crossfade at scales 1 and 1.25 (no shader
    instantiated; t=0 old, t=1 the block exactly where swaybg's fill puts
    it, mid half of each), and on the GPU scene graph contagion and
    outline (t=0 old, t=1 the same block geometry, mid more than 5 % of
    each image).
- The look, judged by eye against the pocket-dots demo frames on two pairs
  of Omarchy backgrounds rendered on the GPU scene graph offscreen. The
  first tries grew round blobs with a wide orange halo and finished at
  0.6; the outline drew every texture edge and filled as confetti. The
  committed shader grows ragged colonies with a thin lit edge, and the
  outline draws a quiet line round the main shapes, then fills from them.
- `tools/lint.sh` printed "lint OK" and `tools/check-docs.sh` "check-docs
  OK". The affected set against `origin/main` was 102 files (the shared
  manifest glob and `theme-lib.sh` widen it): 11466/11470 in the worktree.
  The four failures were in `test-media.sh`, `test-menu-back.sh` and
  `test-wooting.sh`, whose Unix socket paths overflow under the worktree's
  long path ("AF_UNIX path too long"), and in `test-surfaces.sh`, which
  requires `repeat: false` on a ui-timeout Timer and so caught the
  service's three bounds. With that fixed, those four and every file that
  covers the plugin's QML (`test-bg-transition.sh`, `test-widgets-c.sh`,
  `test-carousel.sh`, `test-shell.sh`, `test-i18n.sh`) passed from a short
  bind mount: 1070/1070 and 108/108.

## Rejected options

- **The shell watches `current/background`** (a `FileView` on the link)
  instead of the CLI asking. The CLI relinks and restarts swaybg in the
  same breath (`bin/haseen-theme-bg` `apply`), so the restart would race
  the cover's decode and show the gap the transition exists to hide; the
  shell would also have to remember the old image itself, and a watch is
  a standing cost at idle. Asking from `theme_background_reload` orders the
  steps and costs nothing when no shell answers.
- **The shell restarts swaybg** once covered, as pocket-dots switches its
  daemon. A shell that fails or is not running would then leave the old
  wallpaper; the restart stays in the CLI so the wallpaper always changes.
- **A new plugin id** (`haseen.transition`). The transition is part of how
  the background changes, its settings belong next to the picker's, and
  `haseen.background` is already the never-optional desktop piece; a
  separate id would be one more thing to enable and could be disabled
  away from the picker.
- **No shader, crossfade only** ("No shaders, plainer"): rejected by the
  owner (owner, 2026-11-12).
- **Precomputed maps** (pocket-dots' segmentation and distance fields): need
  Python or a model at runtime, against architecture §6 and the owner's
  "no ML model".
- **A two-pass shader** (an edge-distance field rendered to a small texture
  first): a second effect and texture for little gain; mip levels give the
  blurred copies for free.
- **Reading the old image from the link before relinking**: cheaper, but
  wrong when the link moved without a restart; swaybg's own argument is
  what is on screen.
- **Adding `qt6-shadertools` to CI** so the `.qsb` check runs there: the
  package list is shared by every job; left to the owner.

## Notes for later changes

- A change to `transition.frag` needs a new `.qsb` under a new number
  (`transition-2.frag.qsb`) and the URL in `ShaderView.qml`.
- The 500 ms hold after `shown` is a margin, not a measurement: how long
  swaybg takes to paint a 5376x3584 JPEG after a restart was not measured
  on the live session. If a flash shows on the owner's machines, raise it.
- `HASEEN_GL_DISPLAY=:0 tests/run.sh tests/test-bg-transition.sh` runs the
  shader draws locally.
