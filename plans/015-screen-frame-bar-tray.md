# Plan 015: Screen frame, adaptive transparent bar, hover tray

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. Frame exclusive zones were proven with `hyprctl layers`/`monitors`. The text colour script and screenshots cover the transparent bar. Not exercised live: double-click and tray hover, because no pointer injection is used.

## Why this matters

The owner wants three things: the screen-edge frame that grows out of the top bar (seen in end-4 and caelestia; GPL, so ideas only); Omarchy's double-click-for-transparent bar, which picks its text colour from the wallpaper (MIT, port it); and a tray that appears on hover and can be pinned.

## Execution record

Executed 2026-10-04 against quickshell 0.3.1 and Hyprland 0.56.2 on the live Omarchy session (scratch instances only). No commit (integrator).

### What changed

- **Frame** (`share/haseen/shell/Frame.qml`, `FrameEdge.qml`, `FrameCorners.qml`, `FrameCorner.qml`; wired per screen in `shell.qml` next to `Bar`).
  - The bar is the frame's thick edge. Three `FrameEdge` strips close the other edges. Each strip is a layer surface anchored to one edge with `exclusionMode: Normal`, `exclusiveZone: thickness` and `mask: Region {}`, so windows never sit under it and it takes no input. Only the bar takes input.
  - Inner corners: two `FrameCorners` rows (top and bottom, `radius` tall, full width) with `exclusiveZone: 0`. Hyprland places exclusive-0 surfaces inside the area the exclusive ones leave free, whatever order those were arranged in. So the corners always meet the frame's inner edge, and no corner position depends on surface order. Each corner is a clipped `Rectangle` border (outer radius 2r, border r, inner arc centred on the window-side corner). No Canvas buffer and no shader.
  - The edges and corners live on `WlrLayer.Bottom`, behind windows. A fullscreen window covers the frame. This matches the owner's own `t1nk33r.screen-frame` (in `/tmp/ref/luna-plugins/`).
  - Settings: `frame.enabled` (default true), `frame.thickness` (default 6, clamped to 1..64), and `frame.radius` (default `Theme.radius * 2` = 12 with the fallback theme, which equals the owner's `innerRadius: 12`). The colour is `Theme.background`, the bar's colour. When the frame is enabled the bar drops its hairline. When the frame is disabled the hairline stays on the inner edge.
  - Transparency: the strips and corners fade to alpha 0 of the same hue, using the owner's 420 ms InOutCubic cross-fade. The strips keep their exclusive zones, so windows do not jump.
- **Bar** (`Bar.qml`, `BarSection.qml`):
  - It follows `bar.position` top, bottom, left or right. `Config.barPosition` now accepts all four. A vertical bar is `max(bar.height, 3 × fontSize)` wide (`Config.barThickness`).
  - Sections are a `Grid` (one row, or one column). In vertical mode a widget that declares `property bool vertical` gets it set and sizes its own height. Any other widget gets a square clipped cell. `implicitWidth: 0` still means "hidden" in both orientations.
  - `BarButton` stacks the glyph over a label that shrinks to fit (`fontSizeMode: HorizontalFit`).
  - `bar toggle` hides the bar for the session. A hidden bar shrinks to a frame-thick strip, so the frame stays closed.
  - `surfaceFormat.opaque: false` on the bar and the strips. Without it, Quickshell picked an opaque buffer from the first (opaque) colour, and the transparent bar rendered black. This was measured: the pixel under the bar was `srgb(0,0,0)` before the fix and the wallpaper colour after it.
- **Transparent bar** (`FrameTextColor.qml`, `bin/haseen-bar-text-color`, `Theme.barForeground`):
  - This is a port of Omarchy's `toggleTransparency` / `refreshTransparentForeground` (`shell/plugins/bar/Bar.qml` ~847-1110) and `bin/omarchy-bar-text-color`.
  - Omarchy samples `~/.local/state/omarchy/current/background`, the symlink its background switcher points at the wallpaper: `readlink -f`, first frame only. haseen samples `$HASEEN_USER_STATE/current/background`. The Themes slice (plan 020) keeps that link, swapping it atomically with `ln -sfn` + `mv -T`, and removes it when there is no image (in that case the script falls back to the theme text).
  - The script scales the wallpaper to cover the screen, crops the strip under the bar, averages it to one pixel, and answers whichever of the theme foreground and background has the higher WCAG contrast against that pixel.
  - Changes from Omarchy: a portable awk hex parser instead of gawk's `strtonum`, `--help`, `# haseen:hidden`, and haseen paths.
  - The answer goes to `Theme.barForeground`, which every bar widget uses for normal-state text. Panels keep `Theme.foreground`. The bar turns transparent only once an answer has landed, as Omarchy does, so the text never flashes unreadable.
  - Recompute is event-driven, with no timer:
    - a change of transparency, position, bar thickness, theme foreground or background, or screen size (one `_inputs` key, coalesced with `Qt.callLater`);
    - a `FileView` watch on the `current/` directory. It sees the link swaps; it was tested in a throwaway qs config, where three swaps fired three events. The watch exists only while the bar is transparent.
    - It does not watch the image file itself, because `FileView` would read the whole wallpaper into memory.
    - A run that is requested while one is in flight is queued, not dropped (Omarchy drops it).
  - Double-clicking empty bar space (a `MouseArea` under the sections) calls `shell.setTransparent("toggle")`.
- **Persistence and IPC** (`shell.qml`, `Haseen/Config.qml`, `bin/haseen-bar-{transparent,position,tray,toggle}`):
  - IPC target `bar`: `toggle()`, `transparent(mode)`, `position(pos)`, `tray(mode)`, and a `status()` test hook.
  - A change from the shell (double-click, chevron, IPC) applies at once through a new `Config.runtime` layer that is merged on top of the files. When the files disagree, it persists by running `haseen bar … --no-apply`.
  - The CLI writes `shell.json` (through the existing `shell_config_write`) and then calls `haseen shell ipc bar …` with the explicit value. The shell then sees no disagreement and does not echo, so the two never loop.
  - The next load of the user file clears the runtime layer, so the file stays the truth. The runtime layer also covers a first-time `shell.json` that `FileView` cannot see.
  - `bar.transparent`, `bar.position` and `plugins."haseen.tray".settings.pinned` persist. `bar toggle` does not.
  - The CLI reads the user file at top level first, so an invalid `shell.json` stops it with exit 1 and leaves the file untouched (`shell_merged_json` alone let `jq` fail with exit 2).
- **Tray** (`plugins/haseen.tray/`):
  - Collapsed by default to one chevron. Hovering (`HoverHandler`) reveals the icons, and they collapse 1.5 s after the pointer leaves (a single-shot `// haseen:ui-timeout` Timer).
  - Clicking the chevron pins the tray open. The chevron turns `Theme.accent`, and the setting is saved through `haseen bar tray --no-apply`. Clicking again unpins.
  - The width (or height, when the bar is vertical) animates for 180 ms. Icons open away from the rest of the section.
  - With no tray items, the widget reports width 0. The manifest gains the setting `pinned` and the permission `exec`.
- Bar-widget colour lines: `haseen.audio` and `haseen.battery` use `Theme.barForeground`, and so does `BarButton`'s default. `Glyph` keeps `Theme.foreground`, because panels use it bare.
- Menu's `menu` IpcHandler was applied verbatim in `shell.qml` (single editor).

### Evidence

- `tests/run.sh tests/test-frame.sh`: 127/127. The suite covers:
  - help and headers;
  - dry-run purity, and no file written by any dry run;
  - persistence that keeps the other keys;
  - toggle semantics;
  - IPC calls (logged qs stub), and `--no-apply` making none;
  - the no-shell path;
  - invalid `shell.json` left untouched;
  - usage errors;
  - text-colour decisions on PPM fixtures: dark keeps the light text; light takes the contrast; the top/bottom/left/right strips of split images are each sampled; a light theme inverts; the default `current/background` link is followed and re-followed after a swap;
  - fallbacks: no wallpaper, missing file, bad position or colour, no screen, a bar taller than the screen, failing ImageMagick;
  - CLI↔QML contracts: every `bar <fn>` the CLI sends exists in `shell.qml`; the positions agree; the strips and corners have empty masks and their zones; the alpha surfaces are set; the timer is marked.
- `tests/run.sh tests/test-shell.sh tests/test-surfaces.sh tests/test-compat.sh tests/test-dms.sh`: all pass. `haseen plugin validate haseen.tray` returns `ok`.
- Lint: `bash -n` and `shellcheck --severity=warning -x` are clean on `bin/haseen-bar-*` and `tests/test-frame.sh`. `jq empty` passes on the tray manifest. qmllint with the `tools/lint.sh` flags gives 0 errors on every QML file touched.
- Live, on a scratch instance (own `XDG_CONFIG_HOME`/`XDG_STATE_HOME`/`XDG_RUNTIME_DIR`, `services: []`, idle and lock disabled; the final round under `dbus-run-session --config-file=tools/smoke-session.conf`). Several sibling instances of the same repo shell were running at the same time, so the screenshots show stacked bars.
  - `hyprctl layers` showed the strips as `haseen-frame` `0 858 1536 6`, `0 0 6 858` and `1530 0 6 858`. Corner rows `haseen-frame-corners` sat at `12 80 1512 12` and `12 840 1512 12`, inside the free area.
  - Exclusive zones: `hyprctl monitors -j | .reserved` grew by 6 per side for each instance (`[12,80,12,12]` with two instances, `[24,136,24,24]` with four), and `omarchy-bar` was pushed to `x=12`, then `x=24`.
  - Position `left`: a 39 px wide bar at `6 30 39 822`, the strips on the other three edges, and the corner rows starting at `x=45`. Bottom and right were also exercised via IPC.
  - Screenshots (grim, viewed):
    - frame on top: the inner corners are rounded against the wallpaper at top-left and bottom-right;
    - transparent over a scratch dark wallpaper (a background-layer qs surface standing in for swaybg, killed afterwards; the owner's wallpaper was not changed): the pixel under the bar was `srgb(19,19,27)` (the wallpaper) and the text was light `#dcd7ba`;
    - transparent over a light wallpaper: the pixel was `srgb(242,239,229)` and the text was dark `#16161d`;
    - swapping the `current/background` link alone (no IPC) flipped `bar status` from `#dcd7ba` to `#16161d` within 1.5 s;
    - tray collapsed (a chevron only), then pinned via `bar tray pin`: Bitwarden and Remmina icons and an accent chevron, and the setting landed in the scratch `shell.json`;
    - a vertical bar with a stacked clock, the tray, volume, network and battery.
  - `bar toggle` turned the bar into a 6 px strip (`24 58 1488 6`), and toggling again showed it.
- Idle RSS (35 s idle, then CPU ticks over 20 s, two rounds each). The baseline is `git archive HEAD` (`8829df3`) in `/tmp/frame-base`, run with the same scratch config:

  | round | before | after | CPU ticks/20 s (before / after) |
  |---|---|---|---|
  | 1 | 184160 kB | 186148 kB | 3 / 3 |
  | 2 | 184136 kB | 186240 kB | 1 / 2 |

  That is about +2 MiB for 5 extra small surfaces per screen. The "after" tree also contains siblings' in-progress widget changes.

### Rejected

- **One full-screen frame window** (caelestia's drawers approach, and the owner's Canvas frame). Under the software backend it is a screen-sized buffer, and it reserves no space. Thin strips with exclusive zones meet the "windows never under the frame" requirement for a few kilobytes.
- **Corners drawn inside the strips** (strip `thickness + radius` deep). The corner positions would depend on Hyprland's arrangement order: bottom-layer exclusive surfaces were arranged before the top-layer bar, so the bar starts at `x = thickness`. Exclusive-0 rows avoid that.
- **The shell writing `shell.json` itself.** That would mean a second writer next to `shell_config_write`. The CLI stays the only writer, and the shell only applies.
- **A per-screen text colour.** One sample serves every screen, as in Omarchy. `current/background` is a single image.
- **Animating to the colour `"transparent"`.** It cross-fades through black. The fade goes to alpha 0 of the theme background instead.

### Not verified

- Double-click on the bar and hover-to-expand with the 1.5 s collapse: both need pointer events, and injecting them is forbidden. Double-click runs the same `setTransparent("toggle")` that IPC exercised. Hover uses `HoverHandler` plus the marked single-shot Timer.
- Multi-monitor: there is one screen on this machine.
- In a vertical bar, `haseen.audio` logs one `implicitHeight` binding-loop warning when the bar loads. `BarButton`'s horizontal `implicitHeight: parent.height` is evaluated once before `vertical` lands, and the layout is correct afterwards. The same pattern in the tray was removed by not reading the parent. `BarButton` keeps the parent binding because panels rely on it.
- Panels and Compat tooltips still treat `left` and `right` as "top" when placing popups (`PanelPopup.qml`, `Compat/Tooltip.qml` are outside this plan).
