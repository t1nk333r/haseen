# Plan 115: The shell's foundation looks like Omarchy 4.5 (tokens, font, panels' chrome, no frame)

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. Every native panel, the menu and every Omarchy plugin
  read the changed tokens: text grows from 11 to 12 px and turns monospace,
  cards become the theme's background with a 2 px active-border ring, corners
  follow Hyprland's rounding (0 for most Omarchy themes once plan 114 lands).
  The token names plugins use all keep working; their values change on
  purpose. Panel contents are reworked in plan 117, the bar in plan 116.
- **Depends on**: 004 (themes and the renderer), 015 (the frame), 046 and 068
  (one corner radius), 047 (fonts and Arabic), 092 (compat palette), 100
  (affected tests), 109 (Arabic and right to left), 114 (Hyprland holds the
  theme's rounding and Omarchy's gaps; in parallel)
- **Category**: shell, theme
- **Planned at**: 2026-10-25, owner decisions (below)
- **State**: DONE 2026-10-25 (pull request; the live shell on IO and luna is
  an owner step)

## Decision (owner, 2026-10-25)

On IO the owner wrote: "the feel looks off". Asked what felt off, the owner
answered: "everything about haseen i told you to make it look like omarchy
feel whys and you made a diffrent thing alltogether". Asked how to bring the
Omarchy feel back, the owner chose **"Restyle to Omarchy (Recommended)"**:
"Copy Omarchy 4.5's look into every part of haseen: its style values and
font, bar size and layout, panels, notifications, OSD, lock and launcher, plus
its window gaps, corners and animations. No frame by default. All of haseen's
features and plugins stay." Rejected: "Use Omarchy's shell" (take Omarchy
4.5's shell code itself as haseen's shell; closest, but the biggest change and
haseen features missing until re-added) and "Windows only" (window look only;
bar and panels unchanged).

The font (owner, 2026-10-25, "font will be berkely font nerd the one setup
right now"): the shell's font is the Berkeley Mono Nerd Font, the font set up
on the owner's machine now, not Inter and not an invented default. On luna
`fc-match monospace` is "BerkeleyMono Nerd Font"; the user's font choice
already reaches the theme as `THEME_COLORS[font_mono]` through `haseen font
set` and shell.json's `fontMono`. So: `Theme.fontFamily` follows the user's
chosen monospace font (what `haseen font set` stored), the way Omarchy's
`Style.fontFamily` follows the system monospace; the built-in fallback when
none is chosen stays what haseen ships for fresh installs ("JetBrainsMono Nerd
Font"); Berkeley is never hard-coded, vendored or named as a dependency (it is
a licensed font the owner installed); Inter stays out of the shell's default
text; plan 047's Arabic fallback keeps Arabic rendering (Noto); the evidence
is rendered with the font installed on luna; IO currently has 0xProto Nerd
Font set, which the owner may switch with `haseen font set`.

This plan is the foundation: tokens, font, the panel card and shared controls,
the frame default. Plan 114 (windows) runs beside it; plans 116 (bar) and 117
(panel contents, notifications, OSD, lock, launcher) build on the token API
below.

## Today (before this plan, `064e7d8`)

- `share/haseen/shell/Haseen/Theme.qml:34-70` (at 064e7d8): haseen's own
  tokens: `fontFamily: "Inter"`, `fontSize: 11`, `radius: 6`, `gap: 6`,
  `borderWidth: 1`; `surface` = background mixed 6 % toward foreground,
  `surfaceAlt` 12 %, `border` 20 %, `selection` the terminal's
  selection_background darkened to 4.5:1 (`share/haseen/themed/shell.json.tpl`
  at 064e7d8, `share/haseen/layers/theme/theme-lib.sh:323-345`).
- `share/haseen/shell/Haseen/Config.qml:35-39` (at 064e7d8): the frame on
  unless `frame.enabled` is `false`, its radius twice the theme radius;
  `share/haseen/default/shell.json:25` `"frame": { "enabled": true, ... }`.
- `share/haseen/shell/Haseen/Widgets/PanelSurface.qml` (at 064e7d8): the card
  is `Theme.surface`, a 1 px `Theme.border`, `Theme.radius`, `Theme.gap * 2`
  padding; `PanelPopup.qml:27` places it `Theme.gap` off the bar.
- The compat `Commons/Style.qml` and `Color.qml` mapped Omarchy's names onto
  those haseen values (popups = `Theme.surface` with `Theme.border`).

Rendered at 064e7d8 with the Berkeley font (Evidence): a 310x244 card with a
1 px `#373949` border on a `#232431` surface, radius 6, Inter text at 11 px;
pills 23 px high with an accent fill; a slider knob 10 px.

## Omarchy 4.5, verified in its code (v4.5.0-rc1, `03ff1eff3812933f7088484533784d2f63eaf19a`)

Everything below was read in a fresh clone; nothing was taken from the survey
alone.

- `shell/Commons/Style.qml`:
  - `cornerRadius` mirrors Hyprland's `decoration:rounding` (13-19, 33,
    379-387); `gapsOut` is half of `general:gaps_out`, 5 by default (13-19,
    34, 389-399); both re-read with `hyprctl -j getoption` on start (557-560)
    and on Hyprland's `configreloaded` (488-495); `reduceMotion` follows
    `animations:enabled` and makes `duration(ms)` 0 (360-367, 473-486).
  - State tokens normal / hover-cursor / focus / selected / pressed /
    selection with colours, fill and border alphas and widths (36-201).
  - Spacing `space(px)` and the scale (203-263); type: family `monospace`
    (271), base size 12 (281), caption 10 … display-large 28, icons 11 / 14 /
    18 (323-341); bar metrics 26 / 28, icon slot 27, canvas 16, font 13,
    size 12, status slot 21 (343-358).
- `shell/Commons/Color.qml`: the flat `shellValues` dictionary, `pick`,
  `pickAlpha`, `flatColor`, `composed` (25-77), the surface groups bar,
  popups, tooltip, notifications, menu, polkit, lock, image picker (79-137),
  the palette from colors.toml (139-169).
- `default/themed/shell.toml.tpl` lines 7-235: every value below.
- The card: `shell/Ui/KeyboardPanel.qml` (margin and gap `Style.gapsOut`
  44, 51; padding `popupPadding` 45; border `Border.surfaceSpec("popups",
  "border", Color.popups.border, max(1, Style.space(2)))` 48; the card 391-403:
  `Color.popups.background`, `radius: Style.cornerRadius`, opacity 140 ms
  OutCubic), the same in `PopupCard.qml:13-18,151-162`;
  `BorderSurface.qml`/`BorderOverlay.qml` (flat borders on `Rectangle.border`,
  gradients as a Shape ring).
- Controls: `Ui/Button.qml` (state order 6-17, reserved border 71-107, fills
  121-126, borders 115-119), `Ui/ToggleSwitch.qml` (62-104),
  `Ui/PanelSlider.qml` (14-19, 38-39, 51-109), `Ui/PanelSectionHeader.qml`
  (12-30), `Ui/PanelSeparator.qml` (12, 18), `Ui/CursorSurface.qml` (15-42),
  the network panel's band and DNS pills (`plugins/panels/network/Panel.qml:
  1711-1768`), the audio panel (`plugins/panels/audio/Panel.qml:757-1186`).
- `default/hypr/looknfeel.lua:9,25`: gaps_out 10, rounding 0 (plan 114 adopts
  them); `default/hypr/apps/omarchy-shell.lua:12`: keyboard panels have no
  compositor layer animation, only their own QML fade.
- Icons: Omarchy's bar draws its icons in `Style.font.family`
  (`plugins/bar/Bar.qml:75-78`, `Ui/BarIconButton.qml:49`).

## What changed

### Tokens: `shell.json` and `Theme` (the token API, for plans 116 and 117)

- `share/haseen/themed/shell.json.tpl` adds `shellValues`: Omarchy's
  `shell.toml.tpl`, all 100 uncommented keys in file order, as
  `"section.key": "value"` strings rendered with the same template expressions
  (`{{ background }}`, `{{ shell_gradient hyprland_active_border accent }}`,
  `{{ mix foreground background 34% }}`, …); haseen's renderer is
  byte-compatible with Omarchy's (plan 004), so no `theme-lib.sh` change was
  needed. The legacy keys keep their names and take Omarchy's values:
  `surface` = background (`[popups]` background), `surfaceAlt` = foreground 8 %
  over it (hover-cursor fill alpha, `shell.toml.tpl:42`), `border` = 40 %
  (normal border alpha, 38), `selection` = 18 % (selected fill alpha, 58),
  `fontFamily` = `fontMono` = the user's monospace, `fontSize` = 12 (base size,
  106). `radius`, `gap`, `borderWidth` keep their tokens.
- `Theme.qml` carries Omarchy's `Style` and `Color` vocabulary, derived from
  `shellValues` exactly as Omarchy derives it: the surface groups
  (`Theme.popups.background`, `Theme.menu.selectedBackground`, …, with
  `borderSpec` for bordered surfaces), the state tokens and their functions,
  `Theme.spacing.*`/`space()`, `Theme.font.*`, `Theme.barMetrics.*`,
  `Theme.separator`. `Theme.radius` (= `cornerRadius`) is Hyprland's
  rounding, `Theme.gapsOut` half its gaps_out, `Theme.reduceMotion`/
  `duration()` follow its animations. The full list is
  `docs/architecture.md` §7, "Shell token API".
- Radius and gap follow Hyprland as Omarchy's do: three `hyprctl -j
  getoption` reads on start and on `configreloaded` (which `haseen theme set`
  causes with `hyprctl reload`, `theme-lib.sh:1098-1099`); no timer, no file
  watch of Hyprland's config. Outside a Hyprland session (no
  `HYPRLAND_INSTANCE_SIGNATURE`) nothing runs and the fallbacks stay: the
  theme's radius token and Omarchy's 5 px edge gap.
- `Theme.gap` stays a 6 px spacing step (Omarchy's `spacing.md`): it is
  used for spacing inside panels in 614 places
  (`grep -rn 'Theme\.gap' share/haseen/shell --include='*.qml' | wc -l`), and
  following Hyprland there would collapse every panel when window gaps are
  toggled off. The edge gap is the new `Theme.gapsOut`.
- No token was retired; no caller had to move. Callers that changed value
  only: every `Theme.fontFamily` (368), `Theme.fontSize` (673), `Theme.radius`
  (129), `Theme.surface` (70), `surfaceAlt` (93), `border` (85), `selection`
  (51).

### The font (owner, 2026-10-25)

`Theme.fontFamily` is `Theme.fontMono`: `haseen font set` writes
`~/.config/haseen/font`, `theme_font_override` puts it in
`THEME_COLORS[font_mono]` (`theme-lib.sh:646-665`), and `shell.json` renders
it as both `fontFamily` and `fontMono`; without one it is the shipped
"JetBrainsMono Nerd Font" (`theme-lib.sh:78`). Theme reads `fontMono` for both,
so a `shell.json` rendered before this plan (fontFamily Inter) still draws the
monospace. A theme's `font_family` still sets fontconfig's `sans-serif`
(`share/haseen/themed/fonts.conf.tpl`), for apps, not the shell. No font name
is added to the repo.

Icons: yes, the shell's icon glyphs use the same family. Omarchy's bar draws
icons and text in one `Style.font.family` (above), and a Nerd Font monospace
carries the glyphs; `Glyph` keeps `Theme.fontMono`, which is the same family,
at Omarchy's icon size (`Style.font.icon`, 14 px).

Arabic: the fontconfig rules of plan 047 match on `lang`
(`share/haseen/default/fontconfig/arabic.conf`), so an Arabic run in the
monospace family still falls through to Noto Naskh / Noto Sans Arabic; the
Arabic render below shows it.

### Panels' chrome

- `Widgets/PanelSurface.qml` is Omarchy's card: `Theme.popups.background`,
  the `[popups]` border (the Hyprland active border, 2 px), `Theme.radius`,
  `popupPadding` 14 px inside the border; a gradient border (hackerman,
  last-horizon, solitude) draws through the new `Widgets/BorderRing.qml`
  (Omarchy's `BorderOverlay`, a Shape ring), flat ones on `Rectangle.border`.
- `PanelPopup.qml` places the card `Theme.gapsOut` off the bar and the
  screen's edges (Omarchy's KeyboardPanel gap and margin) and fades it in over
  140 ms OutCubic (0 with animations off). The popup is destroyed on close, so
  there is no fade out.
- `Pill` is Omarchy's bordered `Button` as the network panel's band pills use
  it (body-small text, padding 10 / 8, the normal border, hover-cursor fill
  and border, the selected fill for `active` and `selected`, bold when
  selected); `TrackBar` is `PanelSlider` (4 px selected-fill track, the filled
  part foreground, a 14 px foreground knob ringed 2 px in the card's colour,
  1.15 × while hovered or dragged, 22 px tall).
- New for plan 117, on Theme tokens: `PanelButton`, `PanelSwitch`,
  `PanelSectionHeader`, `PanelSeparator`, `CursorSurface` (Omarchy's
  `Button`, `ToggleSwitch`, `PanelSectionHeader`, `PanelSeparator`,
  `CursorSurface`). They are named with a `Panel` prefix because an explicit
  module import outranks a plugin directory's own file: with `ToggleSwitch` in
  `qs.Haseen.Widgets`, `haseen.network`'s `ToggleSwitch.qml` would have been
  shadowed (checked with Qt's `qml` runner: a local `Thing.qml` loses to
  `import Foo`'s `Thing`).

### Compat

`Compat/Omarchy/Commons/Style.qml` and `Color.qml` are facades over Theme
(same `shellValues`, state tokens, spacing, type, surfaces, radius, edge gap);
one source of truth, and Omarchy plugins now get Omarchy's own values (their
popups were `Theme.surface` with `Theme.border` before). The plugin's bar size
stays the host bar's `Config.barHeight`. `BorderGeometry.js` has a native copy
in `share/haseen/shell/Haseen/` for Theme and BorderRing; compat keeps its own
(its Ui files import it relative to the compat module, and a relative import
out of the module breaks through the `Ui`/`Commons` root symlinks), and
`tests/test-shell-tokens.sh` holds the two bodies identical.

### No frame by default

`share/haseen/default/shell.json` has `"frame": { "enabled": false }` and
`Config.frameEnabled` is `frame.enabled === true`. The frame stays available
(`"frame": { "enabled": true }` in `~/.config/haseen/shell.json`); its inner
radius is the windows' (`Theme.radius`) unless `frame.radius` is set, so the
menu, which binds `Config.frameRadius`, rounds like the windows. With the
frame off the bar keeps its background and its hairline (`Bar.qml:175-177`,
plan 116's) and panels sit `Theme.gapsOut` off it.

**No migration (deviation from the brief).** The old default lived only in
haseen's tree: the seeded `~/.config/haseen/shell.json` is `{}`
(`share/haseen/layers/shell/files/shell.json`, unchanged since plan 005), and
no haseen command ever writes `frame.enabled` (`git log -S'frame' -- bin/
share/haseen/layers/shell/ share/haseen/seeds/ share/haseen/migrations/` and
`grep -rn frame bin/haseen-bar-* share/haseen/lib/omarchy-import.sh`: the bar
commands, the seed and the Omarchy import never set it; `haseen settings`
only opens the file in an editor). So every install that still has haseen's
old default turns the frame off with the new `default/shell.json`, and a
`frame.enabled: true` in a user's file can only be the user's own, which the
brief says must stay. A migration would have nothing to change. Tested:
`tests/test-shell-tokens.sh` checks the default, Config's rule and that a
user's `frame.enabled: true` and `frame.radius` win.

## Deliberate differences from Omarchy, with their reasons

- No blur, glass or shaders (architecture §6): Omarchy's default has none.
  The gradient ring is a Shape fill (as Omarchy's), drawn only for a gradient
  border and only while a panel is open.
- The bar's thickness stays `Config.barHeight` (28) here: the bar is plan
  116's. `Theme.barMetrics` carries Omarchy's 26 / 28 for it.
- `Theme.gap` is a spacing step, not the edge gap (reason above).
- `Pill`'s `pending` (accent border, bold label) is a haseen state Omarchy's
  Button has no equivalent for (the network panel's portal sign-in, plan 106).
- `PanelButton` has no tooltip: haseen panels show hints in their own text.
- The panel fades in but not out: haseen destroys a closed panel (lazy
  panels, architecture §6).
- A theme-shipped `shell.toml` or `shell.<section>.toml` (Omarchy's
  `omarchy-theme-set-templates:255-317`) is not read: no stock haseen theme
  ships one; Omarchy's only one, Tokyo Night's `shell.lock.toml`, is the lock
  screen's (plan 117).
- Compositor fade: Omarchy turns off Hyprland's layer animation for its
  keyboard panels (`apps/omarchy-shell.lua:12`); haseen's `haseen-panel`
  namespace joins `haseen_popped_layers` in
  `share/haseen/default/hypr/windowrules.lua` (added in this plan's rebase
  onto plan 114), so the QML fade is the only one.

## Coordination with plan 114

Agreed interface (plan 114's brief and this one): the shell reads
`hyprctl -j getoption decoration:rounding` and `general:gaps_out` as Omarchy's
Style does; plan 114 makes Hyprland hold the theme's rounding and Omarchy's
gaps. This plan touches neither `share/haseen/default/hypr/` nor the rounding
part of `theme-lib.sh` (`_theme_window_radius`, `_theme_window_rounding`).
Until plan 114 lands, Hyprland's rounding is still haseen's `rounding.lua`
(twice the radius token, 12 for `haseen`) and the shell follows that; after
it, the theme's own. `Config.frameRadius` no longer doubles the token (it
follows the windows), and `theme-lib.sh`'s `_theme_window_radius` still reads
"frame.radius, else twice radius" for Hyprland: plan 114 retires that rule.

## Evidence (renders)

Rendered offscreen in the real engine (Quickshell 0.3.1, Qt 6.12,
`QT_QUICK_BACKEND=software`, `grabToImage`) from a scratch HOME with
`~/.config/haseen/font` = "BerkeleyMono Nerd Font" and a fontconfig file
adding the owner's font directory, the theme's `fonts.conf` and haseen's
`arabic.conf`. "Before" is `064e7d8` (main), "after" this branch with
Hyprland answering rounding 0 and gaps_out 10 (Omarchy's looknfeel, what plan
114 sets; solitude: rounding 6, its own `hyprland.lua:18`). "Omarchy" is
Omarchy's own `qs.Commons`/`qs.Ui` from the clone with its `shell.toml`
rendered from its template for the same theme, in its audio panel's layout.
Renders and their scripts stay out of the repo (paths in the pull request).

- Panel card (a scene of the audio panel's rows):
  - tokyo-night: before 310x244, 1 px `#373949` border on `#232431`, corners
    6; after 344x268, 2 px `#7aa2f7` (accent) border on `#1a1b26`
    (background), square corners; Omarchy 412x290 with the same 2 px
    `#7aa2f7` on `#1a1b26`, square.
  - catppuccin-latte (light): before 1 px `#ced1d9` on `#e5e7ed`; after and
    Omarchy 2 px `#1e66f5` on `#eff1f5`.
  - solitude (gradient active border): after and Omarchy draw the same
    anti-aliased gradient ring at radius 6.
  - The after card is wider and taller only from the 2 px border, the 14 px
    padding (was 12) and the 12 px base font; its rows are still haseen's
    (plan 117).
- Omarchy's card rebuilt with haseen's native widgets (PanelSurface,
  PanelSwitch, PanelSectionHeader, PanelSeparator, CursorSurface, TrackBar,
  PanelButton) against Omarchy's own components in the same layout:
  **0 differing pixels** in all four renders (card 412x290, buttons 257x32,
  slider 260x40, toggles 194x34) for tokyo-night, catppuccin-latte and
  solitude (the two PNGs of solitude's card have the same md5).
- Button (`Pill`): 23 px high with an accent fill for `active` before; 32 px
  with the selected fill, as Omarchy's band pill (32 px), after.
- Slider (`TrackBar`): before a 10 px knob, 10.04 % of pixels differing from
  Omarchy's PanelSlider; after a 14 px knob, 0 differing pixels.
- Toggle: haseen.network's own switch (panel content, plan 117) grows from
  76x16 to 80x17 with the font; the shared `PanelSwitch` is Omarchy's 42x22
  track (54x34 with its cursor ring) to the pixel.
- Menu-style card (the real `haseen.menu`, placement center): before 300x603,
  radius 12, 11 px; after 327x636, radius 0 (Hyprland's), 12 px Berkeley.
- Arabic (tokyo-night, `haseen language ar`): the card mirrors, the Arabic
  headings (الصوت, المخرج, المدخل) render through the Noto fallback beside
  the Berkeley Latin text; after 344x278 (before 310x254).

## Tests

- New `tests/test-shell-tokens.sh` (covers Theme, Config, Widgets,
  PanelPopup, PanelPlacement, compat Style/Color/BorderGeometry, the template,
  the default shell.json): `shellValues` key for key and value for value
  against Omarchy's `shell.toml.tpl` (pinned in the test); rendered values for
  tokyo-night, catppuccin-latte, solitude and hackerman (flat and gradient
  borders); the user's font reaching `fontFamily`; in the engine, with a fake
  Hyprland event socket and a stub `hyprctl`: radius 7 and edge gap 5 from
  rounding 7 and gaps_out 10, no change while Hyprland has not announced a
  reload (no polling), rounding 3 and gaps 2 after `configreloaded`,
  `duration(140)` 0 with animations off, Omarchy's type scale, spacing scale,
  state alphas and widths, fills, popups/menu/lock surfaces, bar metrics, the
  card's geometry, the controls' sizes, compat Style/Color agreeing with Theme
  on eleven values, the frame off by default and following the windows'
  radius; a gradient theme drawing through BorderRing; a shell.json from
  before this plan; the two BorderGeometry bodies identical; no Timer in Theme.
- Updated: `test-theme.sh`, `test-themes2.sh` (the `shellValues` key, the new
  mixes, `shellValues` all strings), `test-theme-haseen.sh` (fallbacks skip the
  object, selection), `test-compat-font.sh` (the text family is the
  monospace), `test-compat.sh` (Border resolves the tooltip's value reference),
  `test-i18n.sh` (the knob is centred on the value as in Omarchy's slider).
- Counts: in the pull request description (affected set, lint, docs,
  secrets).

## Rebased onto plans 113 and 114 (2026-10-25)

- `Theme.qml`'s `frameRadius` fallback is `Theme.radius` (this plan), and
  plan 114 makes `Theme.radius` mirror Hyprland's `decoration:rounding`, so
  the frame defaults to the windows' radius without a second multiplier
  (`share/haseen/shell/Haseen/Config.qml:40-43`).
- `current/theme/rounding.lua` stays retired (plan 114): `haseen theme set`
  writes neither it nor a frame-derived radius. `test-theme-haseen.sh` keeps
  114's assertions (`rounding = 4,` in the theme's `hyprland.lua`, no
  `rounding.lua`) beside this plan's `selection` (`#383838`, the 18 % fill;
  plan 114's readable orange `shell_selection` is no longer the shell's
  `selection` token).
- The `haseen-panel` namespace joins `haseen_popped_layers` in
  `share/haseen/default/hypr/windowrules.lua`, closing this plan's follow-up:
  the QML fade is the only one.
- `tests/test-themegen-keys.sh` puts its `XDG_RUNTIME_DIR` in a short
  `mktemp` dir: Quickshell's IPC socket under a deep worktree path passes the
  108-byte `sun_path` limit (the suite failed with
  `QLocalSocket::ServerNotFoundError`; the same suite passes at a short path).

## Rejected options

- **Render a real `shell.toml` and parse TOML in the shell**, as Omarchy does.
  It would also read theme-shipped `shell.toml` files, but adds a second token
  file and a parser beside `shell.json`, which the shell, the tests and the
  compat host already read; the brief names `shell.json.tpl`. The same keys and
  values now live in `shell.json`.
- **Compat derives from Theme or both from the file** — both from the same
  `shellValues`, with compat as a facade over Theme: one implementation of
  Omarchy's derivations, so the two cannot drift.
- **`Theme.gap` follows Hyprland** (the brief's "edge gap from half of
  gaps_out" read onto `gap`): rejected for the 614 internal spacings above;
  `gapsOut` is the edge gap.
- **Name the new widgets as Omarchy does** (`Button`, `ToggleSwitch`, …):
  rejected for the shadowing measured above.
- **A frame migration**: nothing to migrate (above).
- **Theme.fontFamily = "monospace"** (Omarchy's literal alias): rejected by
  the owner's font decision, which makes it the stored choice; through
  haseen's `fonts.conf` the alias resolves to the same family anyway.

## Follow-ups

- Plan 116: the bar's size (`Theme.barMetrics`), layout and hairline.
- Plan 117: panel contents on the new controls (`PanelButton`, `PanelSwitch`,
  `CursorSurface`, `PanelSectionHeader`, `PanelSeparator`), notifications,
  OSD, lock (Tokyo Night's `shell.lock.toml`), launcher (`Theme.launcher`).

## Owner steps

After deploy (the deploy restarts the shell; no migration is needed for the
frame):

1. Open a few panels (audio, network, calendar) and the menu; switch to a
   light theme and back (`haseen theme set catppuccin-latte`, then your own);
   try `haseen language ar` and back with `haseen language en`.
2. The font: luna already uses Berkeley Mono through `haseen font set`. IO has
   0xProto Nerd Font: `haseen font set "BerkeleyMono Nerd Font"` there once the
   font is installed (`haseen font list` shows the exact family name).
3. To see Omarchy's look on IO, these overrides (read by the coordinator, not
   by this plan) hide it and are yours to remove; haseen never edits them:
   - `~/.config/hypr/local.lua`: `rounding 7` and `rounding_power 2` (the
     panels follow Hyprland's rounding, so they round at 7 instead of the
     theme's), `gaps_out 10` (already Omarchy's; keeps the 5 px panel gap),
     blur on and shadows on (Omarchy's default has neither).
   - `~/.config/hypr/hyprland-gui.lua` (HyprMod): `rounding 7` (same effect),
     `inactive_opacity 0.8`, blur passes 3 and shadows on.
4. The frame can be turned on again with `"frame": { "enabled": true }` in
   `~/.config/haseen/shell.json`.
