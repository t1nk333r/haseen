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
- **State**: DONE 2026-11-12; fixed 2026-11-13 after the owner saw it live on
  luna ("only the first transition had the new [one], the other did not",
  see Verification), and again on 2026-11-13 for the audit's findings (owner:
  "do all", see Fixes after the audit). `tests/test-bg-transition.sh` passes
  176/176 with a GL display (`HASEEN_GL_DISPLAY=:0`) and 113/113 without
  one. IO (software, scale 1.25) is still an owner step.


After the merge review (DeepSeek Flash, approved with one should-fix): two
`theme set` runs at once deleted each other's kept picture, because
`theme_background_keep` began by removing every `.background-shown-*` and
`theme set` removed them all again after its reload. The kept file is now
`.background-shown-<pid>-<name>`, `theme_background_unkeep PATH` removes only
this run's, and `theme_background_prune` removes only those whose pid is no
longer running (a run killed halfway). The test keeps a live run's picture
and a dead run's beside a `theme set`: the live one stays, the dead one
goes; on the previous code both checks fail.

## Problem

A background change is a cut. `haseen theme bg set|next` and `haseen theme
set` move `current/background` and restart `haseen-background.service`
(`theme_background_reload`, `share/haseen/layers/theme/theme-lib.sh:1060`),
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

`theme_background_reload` (`theme-lib.sh:1060`) is the one place every
command goes through, so the hand-over lives there:

1. It reads the image swaybg shows from the service's main process
   (`systemctl --user show -p MainPID --value`, then `--image` in
   `/proc/<pid>/cmdline` through `sysroot_path`;
   `theme_background_shown`, `theme-lib.sh:982`; `haseen theme set` passes
   the file in instead, see Fixes after the audit). On luna that read
   `swaybg --mode fill --image ~/.local/state/haseen/current/theme/backgrounds/7-akane.jpg`
   (2026-11-12). This is what is on screen even when the link moved
   without a restart (a migration relinks without one).
2. `background begin OLD NEW` over `qs ipc call` with a 1 s `timeout`
   (`theme_background_ipc`, `theme-lib.sh:1035`), skipped under DMS
   (`active-shell`). The shell answers `loading` or `skip <reason>`.
3. On `loading` it asks `background state` every 30 ms until the answer is
   no longer `loading`, for 1.2 s at most (`theme-lib.sh:1090`). A `qs ipc
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
  `PanelWindow` on `WlrLayer.Bottom` (line 38), above swaybg's Background
  layer and below every window, `ExclusionMode.Ignore`, an empty input
  mask, namespace `haseen-background-transition`. The default
  `windowrules.lua` gives that namespace `no_anim`, so the cover is whole on
  its first frame; with Hyprland's `layersIn` fade
  (`share/haseen/default/hypr/looknfeel.lua:100`) a half-faded cover would
  show swaybg's gap.
- Each cover (`TransitionCover.qml`) decodes both images asynchronously at
  the screen's pixel size with `PreserveAspectCrop`, which is swaybg's
  `fill` (cover, centred), through Qt's image cache, so screens of one size
  share a decode. Two frames after both are ready (`FrameAnimation`,
  `TransitionCover.qml:61`) the screen counts
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
  cover. A change during a change starts over in the covers already on
  screen.
- Skipped (instant): `transition: none`, the same image, Hyprland's
  `animations:enabled` off (`Theme.reduceMotion`,
  `share/haseen/shell/Haseen/Theme.qml:133`), the `game` context
  (`Flags.context`, `share/haseen/shell/Haseen/Flags.qml:46`), no screen.

### The shader, and the crossfade

`TransitionView.qml` draws one screen. On a GPU scene graph, contagion and
outline load `ShaderView.qml` through a `Loader` that is active only then
(`wantsShader`, `TransitionView.qml:34`, from `GraphicsInfo.api`). On the software renderer
(haseen's default, IO) and for `fade` it is a plain opacity crossfade of
the two images, and `ShaderView.qml` is never instantiated
(`tests/test-bg-transition.sh` checks `"loaded":false` at scales 1 and
1.25). A shader that fails to build falls back to the crossfade.

`transition.frag` (GLSL 440, compiled with `qsb --qt6` into
`transition-2.frag.qsb`; the number changes with the shader because Qt
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

Both images are decoded with mipmaps only when the shader draws them.

## What changed

- `share/haseen/shell/plugins/haseen.background/`: `manifest.json` (kind
  `service`, settings `transition`, `transitionDuration`, version 1.1.0);
  `Transition.qml` (the service and the `background` IPC target),
  `Transition.js` (pick, skip rules, cover math, cell size, the steps),
  `TransitionWindows.qml` (the covers), `TransitionCover.qml` (one
  screen's cover), `TransitionView.qml` (one screen's picture),
  `ShaderView.qml` (the one `ShaderEffect`), `transition.frag` and
  `transition-2.frag.qsb`.
- `share/haseen/layers/theme/theme-lib.sh`: `theme_background_shown`,
  `theme_background_keep`, `theme_background_ipc`, and the hand-over in
  `theme_background_reload`; `bin/haseen-theme-set` keeps the old image
  past the swap.
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
  pixel: 2 x 8.3 MB at 1920x1080 and 2 x 33 MB at 3840x2160, shared by
  screens of one size, each a third more with mipmaps on the GPU path
  (computed, not measured). The
  outline shader reads 38 texels a pixel (two images, 16 contrast samples
  of a tiny mip level, 12 for the coarse gradients, 8 for the line), the
  contagion one 2 plus arithmetic. All of it is freed when the cover goes.
- **CLI**: at most 1 + 40 + 1 `qs ipc call` processes of about 14 ms each,
  and only while a haseen shell answers `loading`.

## Verification

- `tests/test-bg-transition.sh`, at the first commit 103/103 with
  `HASEEN_GL_DISPLAY=:0` and 73/73 without (176/176 and 113/113 after the
  fixes below) (the shader draws need a GL context, which the sandbox and
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

Live on luna (2026-11-13). The first change after the shell started played;
every later one was cut, and `haseen shell ipc background status` read
`"last":"restarted before covered"`. A logging copy of the plugin, run as a
second `qs` on luna's display, showed the cause. In `ShaderEffect.Status`,
0 is Compiled and 1 is Uncompiled. The first cover's effect went from 1 to
0. Every later cover's effect, built from Qt's shader cache (the same
`.qsb` URL), drew correctly but stayed at 1 for good, so `TransitionView`'s
`ready`, which waited for Compiled, never came true. The service's 1.5 s
load bound fired ("too slow to load"), and the CLI restarted swaybg
uncovered. `ready` now waits for the effect to exist, not for Compiled;
`ShaderView` reports only Error, which a shader that fails to build reaches
on its first change. A new check in `tests/test-bg-transition.sh` makes two
covers one after the other in one engine, each in a new window. Before the
fix it failed (`[true]`: only the first became ready). With the fix both
become ready and draw the new image at progress 1 through the shader.

## Fixes after the audit

An audit of the branch in six slices (2026-11-13) found four medium
problems in the transition, a gap in its tests and several small ones. The
owner chose to fix them before merging ("do all", 2026-11-13). Each fix
below has a check in `tests/test-bg-transition.sh`. Each check was shown to
catch its problem by putting that one fix back in a copy of the tree and
running the test with a GL display: it failed, and the fixed tree passes
176/176.

- **`haseen theme set` had no old picture.** swaybg's `--image` is the copy
  inside `current/theme`, which `theme_swap` (`theme-lib.sh:716`) moves
  aside and deletes before `theme_background_reload` reads it. So the
  cover's old image was missing, and the change was cut ("image did not
  load"). Or it was the new theme's file of the same name: `BG1.png` and
  `omarchy.png` each exist in three of the owner's themes. Now
  `bin/haseen-theme-set:131` calls `theme_background_keep`
  (`theme-lib.sh:1008`) before the swap. That hard-links the shown file as
  `current/.background-shown-<name>`, falling back to a copy. The path goes
  to `theme_background_reload "$shown_before"` (`haseen-theme-set:144`),
  and `theme_background_unkeep` removes the file after `shown`. The reload
  also asks for no transition when the old file is missing (`-f $old`).
  Check: two user themes, each with a `BG1.png` holding different bytes.
  The `begin` must name the kept file, holding the first theme's bytes, and
  the file must still exist at `shown` and be gone afterwards. With the old
  call it named `current/theme/backgrounds/BG1.png`, which then held the
  second theme's bytes. Rejected: keeping the whole `old-theme` tree until
  after the reload, the audit's first suggestion. It would change
  `theme_swap`, which every theme set and the dry-run plan use, to protect
  one file.
- **The crossfade's fade-out showed the old image again.** The cover fades
  out as a whole, and the software renderer applies an item's opacity to
  each child. So at cover opacity c the screen was c·new + c(1−c)·old: up
  to a quarter of the old wallpaper came back for 160 ms (audit probe:
  red bleeding through at opacity 0.5). The old image is now hidden once
  progress reaches 1 (`TransitionView.qml`, both slots' `visible`). Check:
  a frame at progress 1 and opacity 0.5, grabbed through a parent item
  because a grab ignores its root's own opacity, is pure new image at
  scales 1 and 1.25. With the old `visible` both scales failed.
- **The outline drew a grid at scale 1.25 on rhi.** `luma()` sampled with a
  mip bias. The GPU derives the base level per 2x2 pixel quad, and the
  cell coordinate jumps at a cell's edge, so quads across the edge of an
  odd-sized cell (5 px at 1.25) read a much blurrier level. They turned at
  another time and left 1 px lines of the old image between cells.
  `textureLod` takes the level as given (`transition.frag`, `luma`).
  Rebuilt with `qsb --qt6` 6.12.0 as `transition-2.frag.qsb`. Two builds
  were byte-identical (`cmp`), and the test's freshness check compares it
  with a fresh build. Check: the shader draws now also run at scale 1.25,
  and the outline's 0.6 frame must have under 0.2 % of its pixels in
  old-image runs narrower than 3 px (an `Open Rectangle:3x1` morphology).
  With `texture(…, blur)` back it was 2.2 %. With `textureLod` it is 0 at
  both scales, and at scale 1 the old shader gave 0 as well.
- **Large wallpapers missed the CLI's 1.2 s.** Each screen decoded both
  images itself (`cache: false`), one after the other. Both images now go
  through Qt's image cache, so screens of one size share each decode. The
  cache keys on the URL, and a theme change can put other bytes at a path
  shown a moment ago. So `TransitionCover.qml` adds `?change=<generation>`
  to each URL. A probe showed both sides: the same URL, asked for again
  after its file changed, came back from the cache at once with the old
  bytes (status straight to Ready), while `?g=2` loaded the file again.
  Measured on luna with `qml` offscreen on the software renderer, 1920x1080
  windows showing a fade from the owner's 6000x4000 PNG to a 10456x3455
  JPEG (retro-82), three runs each, time until every screen was ready:

  | screens | before | after |
  | --- | --- | --- |
  | 1 | 520-657 ms | 540-563 ms |
  | 2 | 919-1051 ms | 544-553 ms |
  | 3 | 1346-1512 ms | 546-563 ms |

  Peak RSS of the three-screen run went from 363 MiB to 283 MiB. The cache
  does not keep the pictures after a change. In a probe that loaded the
  pair and then freed the view, RSS went from 125 MiB back to 71.4 MiB
  within 0.5 s before the change and to 71.7 MiB after it. Qt's cache keeps
  unreferenced pixmaps only under a small limit, and these are far larger.
  One screen still needs about 0.55 s on this desktop CPU, which leaves a
  laptop less margin. Rejected: one decode at a size covering every
  screen, which would make the software renderer scale a larger picture on
  every frame on the smaller screens; and raising the CLI's 1.2 s, which
  would leave the wallpaper unchanged for longer whenever the shell is
  slow.
- **Tests did not run the covers.** Before, `TransitionWindows.qml` never ran
  in a test, and the old image was solid red, so its crop went unchecked.
  The per-screen body (the picture, the two-frame wait, the report to the
  service) is now `TransitionCover.qml`, a plain Item. The test hosts the
  real file in a plain window per screen, in place of the layer surface,
  inside the real Quickshell engine with the real service. A change covers
  by itself (`frames 2`), then holds. A second change arrives while it
  holds and re-covers in the same window: made once, freed once. The
  second change opens on the picture the first ended on. Then `shown` ends
  it, played. The service check now also has two screens: one covered
  keeps it loading. The old image has a white block, and its edges at
  progress 0 must be where swaybg's fill puts them. Each of these was
  shown to catch its mistake: `frames >= 0`, `coveredScreens >= 1`, the
  old slot stretched instead of cropped, the abort on a change during a
  change, and no slot swap.

The small ones:

- **`bg next` twice kept no cover.** A change during a change used to abort,
  so the covers were destroyed and made again, empty, over swaybg's
  restart. Now `begin` re-enters loading in the same covers
  (`Transition.qml`, `dispatch`/`enter`), and `generation` resets each
  cover's count. `TransitionView` holds two image slots. The slot already
  showing the next old image keeps it, and the other loads the new one
  (`place()`). `retainWhileLoading` keeps a slot's last picture while it
  decodes. `theme_background_reload` now takes a lock
  (`current/.background-reload.lock`, 5 s at most), so a second command
  waits for the first one's `shown`, and that `shown` can no longer land on
  the second change. Checks: the covers sequence above, and a reload that
  waits while another holds the lock. Without the lock it returned after
  6 ms.
- **A late `begin` brought the old image back.** When `begin` timed out
  (`timeout` exit 124), the CLI restarted swaybg without saying `shown`. A
  busy shell could then cover the new wallpaper with the old one for 3 s.
  Now `shown` follows a timed-out `begin` too, and in loading it ends the
  change. Check: a `qs` stub that sleeps past the second.
- **The outline was a quarter darker than meant.** `pencil` (formerly `ink`)
  arrives premultiplied and was weighted by its alpha again. Probe: a white
  line at 75 % over black read 143 (0.5625 · 255) and now reads 191
  (0.75 · 255).
- **A race could kill the command.** swaybg exiting between the
  `cmdline` check and its read failed `theme_background_shown` under
  errexit. The read now ends quietly (`done 2>/dev/null <… || return 0`),
  and the caller adds `|| true`.
- **Came along with the slots:** `autoTransform` on both images, so a photo
  turns by its EXIF orientation as swaybg turns it. And a size that arrives
  late (fractional scale) no longer blanks the cover, because of
  `retainWhileLoading`.
- **Docs.** Architecture §6 now gives the shader's real lifetime: about
  2.3 s by default, and at most 9.7 s. Verification gives the test counts
  of each stage. `tests/test-bg-transition.sh` covers `bin/haseen-theme-set`
  and `docs/architecture.md`, which it reads.
- **Vocabulary taken from pocket-dots.** The shader's header comments were
  rewritten in new words, because the audit found them too close to
  pocket-dots' `wallfx.frag`. Its uniforms `ember` and `ink` are now `glow`
  and `pencil`. What the effects still share with pocket-dots is design,
  not code: the two effects, contagion and outline, square cells of 4
  logical pixels, and a tint on a cell that has just turned that fades
  quadratically.

Gates for these fixes, after merging `main` with plans 162-166:
`tools/lint.sh` printed "lint OK" and `tools/check-docs.sh` "check-docs
OK". The affected set against `origin/main` was 105 files, widened by
`theme-lib.sh` and the shared manifest glob. From a short bind mount,
12161/12162 passed. The one failure was `test-vapt-workflow.sh`
("explicit provisioning seeds exact defaults"), which fails the same way
from a bind mount on a clean `origin/main` and passes 167/167 from the
real path on both trees. VAPT's ownership checks do not accept the
mount.

Not done, and left to the owner: the audit's other small findings. Those
are the shell-wide shader guard (it matches only the word `ShaderEffect`),
running the shader checks in CI (no GL and no `qt6-shadertools` there), the
engine skips in this test that `HASEEN_REQUIRE_ENGINE` does not gate, and a
pipeline that fails without ever reporting Error, which leaves the cover
transparent rather than crossfading. The findings for Stage Manager (plan
163) and Your computer (plan 162) are outside this plan.

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
  (`transition-3.frag.qsb`) and the URL in `ShaderView.qml`.
- The 500 ms hold after `shown` is a margin, not a measurement: how long
  swaybg takes to paint a 5376x3584 JPEG after a restart was not measured
  on the live session. If a flash shows on the owner's machines, raise it.
- `HASEEN_GL_DISPLAY=:0 tests/run.sh tests/test-bg-transition.sh` runs the
  shader draws locally.
