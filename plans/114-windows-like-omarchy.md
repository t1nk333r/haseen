# Plan 114: Windows look and move like Omarchy 4.5

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. Every haseen-owned Hyprland look value changes at the next
  reload, the theme now sets the window corners, and a theme yields to the
  toggles and hyprmod on every setting they hold, not only on rounding. The
  user's own files are never touched; every value and rule is checked by
  `Hyprland --verify-config` 0.56.2 for each of the 24 stock themes and a
  generated one, with negative controls. Seeing the windows on a live screen is
  an owner step.
- **Depends on**: 004 (Omarchy-parity theme renderer), 043 (hyprmod's place in
  the load order), 046 (window corners, reversed here), 066 (the `haseen`
  theme), 069 (the border wipe), 100 (affected tests), 105 (the console)
- **Category**: desktop
- **Planned at**: 2026-10-25, owner decision (below); batch 114–117, run in
  parallel with plan 115 (the shell foundation)
- **State**: DONE 2026-10-25 (pull request; the live look and the owner's
  overrides on IO are owner steps)

## Decision (owner, 2026-10-25)

On IO the owner wrote: "the feel looks off". Asked what felt off, the owner answered:
"everything about haseen i told you to make it look like omarchy feel whys and you made a diffrent thing alltogether".
Asked how to bring the Omarchy feel back, the owner chose **"Restyle to Omarchy (Recommended)"**: "Copy Omarchy 4.5's
look into every part of haseen: its style values and font, bar size and layout, panels, notifications, OSD, lock and
launcher, plus its window gaps, corners and animations. No frame by default. All of haseen's features and plugins
stay." Rejected: "Use Omarchy's shell" (take Omarchy 4.5's shell code itself as haseen's shell; closest, but the
biggest change and haseen features missing until re-added) and "Windows only" (window look only; bar and panels
unchanged).

This plan is the windows part: Hyprland's gaps, border, corners, groupbar,
curves and animations, and the window rules that change how windows look. The
shell (bar, panels, frame default) is plans 115–117.

## Reference

Omarchy v4.5.0-rc1 (`03ff1eff3812933f7088484533784d2f63eaf19a`), cloned
read-only for this plan and deleted afterwards. Every value below was read from
that tree, not from the batch brief; citations are `path@v4.5.0-rc1:line`. The
brief's "sixteen leaves" is fifteen `hl.animation` calls
(`default/hypr/looknfeel.lua:76-90`).

## Problem

haseen had drifted to a look of its own (`share/haseen/default/hypr/looknfeel.lua`
on `064e7d8`):

| Setting | haseen (main) | Omarchy 4.5 |
|---|---|---|
| `general.gaps_in` / `gaps_out` | 2 / 4 (`looknfeel.lua:10-11`) | 5 / 10 (`looknfeel.lua:8-9`) |
| `general.resize_on_border` | false (`:17`) | true (`:17`), with `extend_border_grab_area` 8 and `hover_icon_on_border` (`:18-19`) |
| `decoration.rounding` | 12 (`:25`), then the frame's radius from `rounding.lua` | 0 (`:25`); a theme may set its own |
| groupbar | font 11, height 18, no gradients (`:36-38`) | font 12 monospace, ultraheavy/normal, height 22, indicator 1/5, gaps 5/0, white text, 0x40/0x20 fills, gradients (`:42-61`) |
| curves | one, `haseenOut` (`:79`) | five: easeOutQuint, easeInOutCubic, linear, almostLinear, quick (`:70-74`) |
| animations | six leaves: global 4, windowsIn 2.5 popin 90 %, windowsOut 1.5, border off, workspaces off, layers fade 2 (`:80-85`) | fifteen: global 10, border 5.39, windows 3.79, windowsIn 4.1 popin 87 %, windowsOut 1.49 linear popin 87 %, fadeIn 1.73, fadeOut 1.46, fade 3.03, fadeSwitch off, layers 3.81, layersIn 4 fade, layersOut 1.5 linear fade, fadeLayersIn 1.79, fadeLayersOut 1.39, workspaces off (`:76-90`) |
| dwindle / scrolling / master | `preserve_split` only | `force_split` 2, `column_width` 0.49, `new_status` master (`:92-104`) |
| misc / cursor | — | `background_color` rgb(000000), `disable_scale_notification`, `anr_missed_pings` 3, `on_focus_under_fullscreen` 1, `initial_workspace_tracking` 0, `warp_on_change_workspace` 1 (`:106-123`) |

And the corners ran the opposite way to Omarchy's. Plan 046 made Hyprland's
rounding the shell frame's radius: `haseen theme set` wrote
`current/theme/rounding.lua` (`theme-lib.sh:475-521` on main), `init.lua`
loaded it with the defaults (`init.lua:204-206`) and `haseen.theme_hl` dropped
a theme's own `decoration.rounding` (`init.lua:168-195`). In Omarchy the
theme's `hyprland.lua` owns `decoration.rounding` (only
`themes/solitude/hyprland.lua:18-19` sets one: 6, power 3) and the shell's
`Style.cornerRadius` mirrors Hyprland's value (`shell/Commons/Style.qml:13-33`,
`applyRoundingJson` at `:379-388`).

## Change

### `looknfeel.lua` is Omarchy's

`share/haseen/default/hypr/looknfeel.lua` now carries Omarchy's file value for
value, in its order: `general` (`looknfeel.lua@v4.5.0-rc1:7-22`), `decoration`
(`:24-34`), `group` and its groupbar (`:36-62`), `animations.enabled`
(`:64-66`), the five curves (`:70-74`), the fifteen animation calls (`:76-90`),
`dwindle`, `scrolling`, `master`, `misc`, `cursor` and `binds` (`:92-127`).
The fallback border colours are Omarchy's too, the 45° gradient
`rgba(33ccffee)`→`rgba(00ff99ee)` and `rgba(595959aa)` (`:3-4`); every theme
replaces them, its template rendering Omarchy's `hyprland_active_border`
(`share/haseen/themed/hyprland.lua.tpl`, identical to
`default/themed/hyprland.lua.tpl@v4.5.0-rc1`). `xwayland.force_zero_scaling`
and `ecosystem.no_update_news` stay; Omarchy sets them in
`default/hypr/envs.lua@v4.5.0-rc1:41-49`. The header carries Omarchy's MIT
notice and `NOTICE.md` a row.

Kept from haseen, with the reason:

- **`haseenOut`**, defined with easeOutQuint's points, so a user's `local.lua`
  or hyprmod file that names haseen's old curve keeps loading. Nothing of
  haseen's uses it any more.
- **`misc.allow_session_lock_restore`** and the binds/cursor keys were already
  Omarchy's (`:117`, `:121`, `:126`).
- `group.groupbar.render_titles = true` is dropped: it is Hyprland's default and
  Omarchy does not set it.

### Corners come from the theme (Omarchy's direction)

- `looknfeel.lua` sets `rounding = 0` (`looknfeel.lua@v4.5.0-rc1:25`).
- `haseen theme set` no longer writes `rounding.lua`; `_theme_window_radius`
  and `_theme_window_rounding` are retired. `_theme_hyprland_prefix`
  (`share/haseen/layers/theme/theme-lib.sh`) still puts
  `local hl = haseen and haseen.theme_hl and haseen.theme_hl(hl) or hl` first in
  the staged `hyprland.lua` (the line `THEME_HL_PREFIX` names), for the reason
  below. `init.lua` no longer loads `rounding.lua`; one left in an older render
  is ignored and goes at the next theme set. The dry run prints the prefix,
  not a radius.
- So a theme's own rounding applies: `solitude` 6 with power 3 (Omarchy's
  file, unchanged), `haseen` 4 again, the value its `UPSTREAM.md` gives and
  plan 046 had removed as dead (`9b6ec60`), and 0 for every other stock theme,
  for a theme of the user's that sets none and for a generated theme (plan 067
  writes only `colors.toml` and a background, so the template renders, which
  sets no corners).
- The shell reads Hyprland's value back: plan 115 reads
  `hyprctl getoption decoration:rounding` and `general:gaps_out` as Omarchy's
  Style does. This plan only makes Hyprland hold the theme's values.

### The theme yields to `haseen toggle` and hyprmod

The seeded `~/.config/hypr/hyprland.lua` (never rewritten) loads `init.lua`,
then the theme, then the user's files
(`share/haseen/default/hypr/user/hyprland.lua:27-38`); `init.lua` loads the
toggles and hyprmod inside it, before the theme. A theme that sets its corners
would then beat `haseen toggle gaps on` (rounding 0), `omarchy-hyprland-corners`
and hyprmod's rounding. Plan 046 avoided that by dropping the theme's rounding;
now the theme keeps it, so `haseen.theme_hl` (`init.lua`) drops, from the
theme's `hl.config` and `hl.animation` calls, exactly what a toggle or hyprmod
set: `init.lua` records every key path and animation leaf those files set in
`haseen.held` while it includes them (`include_held`), a gradient or a list
counting as one value. Everything else the theme sets passes. The user's own
files load after the theme and still win over all three. Omarchy also puts
the theme below its toggles and the user's files (the theme loads with the
defaults, `default/hypr/omarchy.lua@v4.5.0-rc1:26-27`; the user files, then the
toggles, after them, `config/hypr/hyprland.lua@v4.5.0-rc1:16-26`), and this is
the order the owner set for hyprmod (plan 043: "the GUI wins over `haseen
toggle` and `haseen hw`; the user's hand-written Lua still wins over the GUI").
haseen keeps its own order between the toggles and the user's files.

It covers every key, not only the corners, because the `haseen` theme also sets
`gaps_in` 5, `gaps_out` 5, `border_size` 3 and shadows: before this plan
`haseen toggle gaps on` lost to them at the next reload. A hyprmod colour now
also wins over the theme's.

Existing renders need nothing: their first line already calls
`haseen.theme_hl`, which now behaves as above, and init.lua stops reading their
`rounding.lua`. The migration `1791466289-theme-rounding.sh` now only prefixes a
render from before plan 046 that lacks the line, and writes no `rounding.lua`.

### The console's slides

`qconsole.lua`'s two lent leaves use Omarchy's curves: drop on `easeOutQuint`,
retract on `easeInOutCubic` (`default/hypr/qconsole.lua@v4.5.0-rc1:195-196`),
both now defined by `looknfeel.lua`. Speeds, styles, the 0.6 dim
(`qconsole.lua@v4.5.0-rc1:30`), the borrow-and-hand-back of plans 105 and 111,
and the `hl.animation` recorder are unchanged; the recorder now also sees
Omarchy's `global` (speed 10, `default`).

### Window rules

Compared against `default/hypr/windows.lua` and `default/hypr/apps/*.lua`.
Adopted, in `share/haseen/default/hypr/windowrules.lua`:

| Rule | Omarchy source |
|---|---|
| `haseen.transparent_window(match, opacity)`: opacity `0.985 0.96`, tag `+transparent-window` | `helpers.lua:316-320` |
| terminals (the `terminal` tag), omawrite, 1Password and Nautilus see-through | `windows.lua:21-23` |
| kanagawa's terminals at `0.99 0.985` (`themes/kanagawa/hyprland.lua`, restored with the helper; it had been dropped for lack of one) | `themes/kanagawa/hyprland.lua:17-18` |
| the floating treatment: the `floating-window` tag floats, centres and sizes 875 × 600; NautilusPreviewer, Evince, imv, mpv, the GTK portal and file dialogs of Sublime, DesktopEditors and Nautilus get it | `apps/system.lua:1-20` |
| 1Password and Bitwarden float, out of screen shares | `apps/1password.lua:3`, `apps/bitwarden.lua:1-6` |
| LocalSend floats at 1100 × 700, its `Share` picker centred, see-through | `apps/localsend.lua:2-5` |
| Steam floats, main window 1100 × 700 centred, friends 460 × 800 | `apps/steam.lua:1-3` (its `idle_inhibit` is haseen's fullscreen rule already) |
| Battle.net launcher 1280 × 800; its installer undecorated | `apps/battlenet.lua:4-16` |
| Hermes HUD floats borderless | `apps/hermes.lua:2-5` |
| browser tags (`chromium-based-browser`, `firefox-based-browser`) | `apps/browser.lua:2-3` |
| PiP: tagged by title, borderless, pinned, 600 × 338 top right 40 px in; Meet's bottom right | `apps/pip.lua:1-20` (replaces haseen's untagged float + pin) |
| the screensaver slides in | `apps/system.lua:35` |
| haseen's webcam overlay at Omarchy's default (medium) size and corner, never dimmed | `apps/webcam-overlay.lua:7-10,18-23`; Omarchy's default is medium (`bin/omarchy-capture-screenrecording@v4.5.0-rc1:35`) |
| no layer animation for the bar, the OSD and the keyboard panel (`haseen-bar`, `haseen-osd`, `omarchy-keyboard-panel`), and `animation = "none"` on slurp's selection | `apps/omarchy-shell.lua:5,12`, `apps/screenshot-selection.lua:2` |

Not adopted (recorded):

- **Per-app fixes that are not the look**: DaVinci Resolve's focus rules,
  JetBrains' `no_follow_mouse`, Telegram's `focus_on_activate`, GeForce NOW,
  Moonlight and RetroArch fullscreen with idle inhibit; Chromium's forced tiling
  and the YouTube/Zoom untag (`apps/browser.lua:4-7`) and hiding "is sharing"
  windows (`:10`). They change behaviour, not the window look; the owner can
  ask for them.
- **Omarchy's own windows**: `org.omarchy.*`, `Omarchy`, `About`, `TUI.float`,
  `omacalc`, `org.codeberg.dnkl.foot` (`apps/system.lua:7,26-30`) and the
  dev-gallery rule (`apps/omarchy-shell.lua:21`). haseen's own floating
  terminals (`haseen.floating`) already float at 875 × 600 like them.
- **The `pop` tag's rounding 8 and the `noidle` tag** (`apps/system.lua:40-44`):
  haseen has no command that sets them.
- **The `transparent` tag** (`windows.lua:25-26`): set by Omarchy's
  transparency key, which haseen does not bind.
- **The background, dock and image-selector layer rules**
  (`apps/omarchy-shell.lua:12,17`): haseen has no dock; its wallpaper is swaybg,
  not a shell layer, and no theme intro hands over to it.
- **Omasnap's `no_screen_share`**: plan 107 removed it on purpose (scrolling
  capture), unchanged here.

### The `haseen` theme's border fade

Omarchy's `border` leaf (5.39) fades a window's border on focus changes. On
the `haseen` theme's sidecar wipe (`border_wipe_seconds` 36, plan 069) every
frame haseen-sidecar sends is a new active border, and Hyprland 0.56.2 restarts
the fade on each one (`src/desktop/view/Window.cpp:1901-1908`,
`setBorderColor`; drawn as a lerp while it runs, `CHyprBorderDecoration.cpp:62-96`).
At ten frames a second the fade would never end, so the border would redraw at
the full refresh rate while the wipe turns: against the resource rules
(`docs/architecture.md` §6). That theme's `hyprland.lua` turns `border` off on
that path only. Up to 10 s a turn (Hyprland's own loop) and without a wipe it
keeps Omarchy's fade.

## Conflicts with standing haseen rules

- **No blur, no shadows by default**: Omarchy's default has neither
  (`looknfeel.lua@v4.5.0-rc1:27-33`), so nothing to drop. A theme may still
  enable shadows (Omarchy's `lumon` does, `themes/lumon/hyprland.lua`; haseen's
  `haseen` theme does); blur stays off everywhere.
- **The default theme** is `haseen` (plan 066), not Omarchy's Tokyo Night
  (`install/user/theme.sh@v4.5.0-rc1:7-10`). Its own values from Greek Noir
  (gaps 5/5, border 3, rounding 4 with power 3, shadows) are a theme's, as any
  Omarchy theme's would be; on any of the 23 Omarchy themes haseen shows
  Omarchy's windows exactly (below). Whether the default theme should keep
  them is an owner question.
- **Never edit the user's files**: none are. Every changed file is
  haseen-owned and applies at the next `hyprctl reload`; no migration flips a
  user value.

## Rejected

- **Keeping the frame-radius rule with Omarchy's values** (rounding.lua at 0):
  the brief asks for Omarchy's direction, and `solitude` would still lose its
  corners.
- **Dropping only the theme's rounding when a toggle or hyprmod set it** (a
  narrow `theme_hl`): it leaves `haseen toggle gaps on` losing to the `haseen`
  theme's gaps and border, and keeps one key special for no reason Omarchy
  has.
- **Writing `rounding.lua` from the theme's own `decoration.rounding`**: the
  theme file is Lua and may compute it (the `haseen` theme reads its
  `colors.toml`); parsing it in bash is guessing, and running it twice has side
  effects.
- **Loading the toggles again after the theme**: they are loaded inside
  `init.lua`, before the theme, by the seeded file haseen never rewrites; a
  second load would also repeat their binds and `hyprctl` effects.
- **Removing `haseenOut`**: a user file naming it would stop loading for no
  gain.
- **Omarchy's border fade on the sidecar wipe** (above), and **a Go change to
  the sidecar** to pause the fade itself: the theme that asks for the wipe is
  the one place that knows which path runs.

## Verification

- `Hyprland --verify-config` 0.56.2 accepts the seeded config, defaults and
  rules included, for every stock theme and a generated one
  (`tests/test-theme.sh`, `hypr_verify`). Negative controls, run by hand: an
  unknown key in `looknfeel.lua` gave `unknown config key 'general.bogus_key'`,
  an unknown rule field `hl.window_rule: unknown field 'bogus_effect'`, an
  unknown key in a theme's `hyprland.lua` `unknown config key
  'general.not_a_key'`.
- `tests/test-desktop.sh` pins every looknfeel value, curve and animation
  above to its Omarchy line, that there are fifteen animation calls at load,
  and the transparency, PiP, floating and bar-layer rules.
- `tests/test-theme.sh`: no theme writes `rounding.lua`; each stock theme's
  windows end at its own corners (solitude 6 with power 3, haseen 4, others
  0); `frame.radius` 20 moves nothing; on solitude `haseen toggle gaps on`
  gives 0 and off 6, a corners toggle rounds tokyo-night (6) and squares
  solitude (0), hyprmod's 5 wins, the user's `local.lua` 9 wins; on haseen
  `toggle gaps on` zeroes its gaps, border and corners, hyprmod's `gaps_out` 14
  and shadow switch win while the theme keeps its shadow range and corners,
  `local.lua`'s `gaps_out` 2 wins; a generated theme is square at Omarchy's
  10 px; a stale `rounding.lua` is ignored; linked, dangling and
  `return`-ending theme files still load.
- `tests/test-theme-haseen.sh`: the `haseen` render carries `rounding = 4`,
  writes no `rounding.lua`; the 36 s wipe turns `border` off, the 10 s loop and
  no wipe leave it to looknfeel.
- `tests/test-omarchy45-workspaces.sh`: the console drops on easeOutQuint and
  retracts on easeInOutCubic; `looknfeel.lua` defines both, and every recorded
  leaf names a defined curve; the recorder remembers Omarchy's global leaf.
- `tests/test-migrate-defaults.sh`: the migration prefixes an old render and
  writes no `rounding.lua`; a prefixed render, a current render, a renamed
  theme and a render without `colors.toml` behave as described.
- Counts: `tests/run.sh --affected origin/main` selected 48 test files; run in
  four chunks and `test-capture-upload.sh` alone, 8068 of 8069 checks passed.
  The one failure, `test-omarchy-45.sh` "an upgrade runs as root in a PID 1
  scope", is the developer shell's: with `LC_ALL=en_US.UTF-8` exported it
  fails the same way on `origin/main` (267/268), and with `LC_ALL` unset it
  passes 268/268. `test-theme.sh` gained two checks after the chunked run (the
  verify with a toggle and hyprmod present, the stale `rounding.lua`) and
  passes 943/943 as committed.
  `tools/affected-tests.sh --check`, `tools/check-docs.sh`, `tools/lint.sh`
  and the secrets checks pass.

### Visual evidence

Hyprland 0.56.2 cannot be rendered offscreen here: it has no headless-only mode
(`src/Compositor.cpp:309-340`, "TODO: headless only"; `HYPRLAND_HEADLESS_ONLY=1`
aborts with `CBackend::create() failed!`), and its DRM and Wayland backends need
a seat or a parent session, which on this laptop is the owner's live one. So the
windows are compared by the values Hyprland ends up with, resolved by running
each config's whole load order under Lua (main, this branch, and Omarchy's
`looknfeel.lua` plus its theme file), and drawn as a model: two tiled windows on
1920 × 1080, placed as dwindle places them. Measured on those renders (outer gap,
gap between the windows, border, wallpaper pixels on the window's top row before
its border starts):

| Theme | main | branch | Omarchy 4.5 |
|---|---|---|---|
| tokyo-night | 4, 4, 2, 11 (rounding 12) | 10, 10, 2, 0 | 10, 10, 2, 0 |
| solitude | 4, 4, 2, 11 (rounding 12) | 10, 10, 2, 6 (rounding 6, power 3) | 10, 10, 2, 6 |
| haseen | 5, 10, 3, 12 (rounding 12) | 5, 10, 3, 5 (rounding 4) | — (not an Omarchy theme) |

Resolved animation leaves match Omarchy's on both Omarchy themes (global 10
`default`, border 5.39, windowsIn 4.1 popin 87 %, windowsOut 1.49 linear,
layers 3.81, workspaces off), groupbar height 22 and font 12, terminals at
0.985/0.96. The model's paths are listed in the pull request's final report, not
committed.

## Owner steps

1. Deploy; the deploy runs `hyprctl reload`.
2. On IO, these of the owner's own settings hide the new look; haseen does not
   edit them. Delete them to see Omarchy's windows (read from the batch
   coordinator's notes, not from IO):
   - `~/.config/hypr/local.lua`: `rounding = 7` and `rounding_power = 2`
     (Omarchy's windows are square on every theme but solitude), and blur and
     shadows on (`decoration.blur.enabled`, `decoration.shadow.enabled`;
     Omarchy has neither and haseen never ships blur). Its `gaps_out = 10` is
     Omarchy's value already and can stay.
   - `~/.config/hypr/hyprland-gui.lua` (HyprMod): `inactive_opacity 0.8`
     (Omarchy dims nothing; only terminals are see-through, at 0.96 inactive),
     `rounding 7`, `blur passes 3` and shadows on. HyprMod's settings now win
     over the theme's too, so turn them off in HyprMod itself.
3. Look at two tiled terminals on an Omarchy theme (`haseen theme set
   tokyo-night`): 10 px to the screen edge, 10 px between them, 2 px border,
   square corners, slightly see-through; open and close windows (pop-in from
   87 %, linear exit) and press SUPER + GRAVE (the console drops and retracts
   on Omarchy's curves).
4. Decide whether the default `haseen` theme keeps Greek Noir's own gaps 5,
   border 3, rounding 4 and shadows, or should show Omarchy's.

## Execution record

`share/haseen/default/hypr/{looknfeel,init,qconsole,windowrules}.lua`,
`share/haseen/layers/theme/theme-lib.sh` (`THEME_HL_PREFIX`,
`_theme_hyprland_prefix`), `bin/haseen-theme-set` (dry run),
`share/haseen/migrations/1791466289-theme-rounding.sh`,
`share/haseen/themes/{haseen,kanagawa}/hyprland.lua`,
`share/haseen/omarchy/bin/omarchy-hyprland-corners` (comment),
`share/haseen/lib/settings.sh` (comment), `docs/architecture.md`,
`share/haseen/agents/skills/haseen/{hyprland,theming}.md`, `NOTICE.md`,
`plans/046-window-corner-radius.md` (follow-up),
`tests/test-{desktop,theme,theme-haseen,migrate-defaults,omarchy45-workspaces}.sh`.
