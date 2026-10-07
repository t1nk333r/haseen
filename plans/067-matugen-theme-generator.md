# Plan 067: theme generator on matugen, with a panel; Aether dropped

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a new command and a new panel that is off by default; the theme pipeline is unchanged)
- **Depends on**: 004 034 064
- **Category**: theme
- **Planned at**: 2026-10-07, owner decision (io round 9): build haseen's own theme generator on matugen with a GUI, and drop Aether
- **State**: DONE 2026-10-07 (`tests/test-themegen.sh`; nested-session screenshots of the panel previewing two wallpapers). The panel `haseen.themegen` is **awaiting the owner's approval** for the default set and ships disabled.

## Problem

haseen could turn a wallpaper into a theme (`haseen theme wallpaper`, plan 034)
but had no GUI for it. Plan 034 left the GUI to Aether: "a user who wants the
visual editor installs aether and haseen reads its output"
(`plans/034-wallpaper-palettes.md:50-52`). Plan 053, in luna's uncommitted work,
went further: a stand-in `omarchy` so Aether's theme apply reaches haseen. The
owner has decided against Aether. haseen gets its own generator, built on
matugen, with a panel.

## Aether: what is dropped

**On main (this worktree):** no Aether *app* support exists. `grep -rin aether`
finds four kinds of hit, and all of them stay:

- `core/internal/palette/*.go`, `bin/haseen-theme-wallpaper:6` and the
  `NOTICE.md` row: plan 034's extractor, code adapted from aether (MIT). This is
  haseen's own code with its notice, and Aether does not need to be installed.
- `aether.nvim` in `share/haseen/themed/neovim.lua.tpl`, `share/haseen/themes/*/neovim.lua`,
  `share/haseen/default/nvim/*.lua`, `tests/test-theme.sh:169` and plan 058:
  a Neovim colourscheme plugin, not the Aether app.
- `plans/054-io-round-7.md:13`: the note that plan number 053 is luna's.
- `plans/034-wallpaper-palettes.md:50-52`: the "install aether" GUI answer.
  It now carries a dated note that plan 067 supersedes it.

**In luna's uncommitted work** (read from the uncommitted tree in
`~/Projects/cachyos-quickshellarchy`, `git status`; not edited). This is for the
owner's other session to remove:

- New files:
  - `bin/haseen-aether`
  - `share/haseen/default/aether/bin/omarchy` (the stand-in `omarchy`)
  - `share/haseen/default/applications/aether.desktop`
  - `share/haseen/default/applications/li.oever.aether.url-handler.desktop`
  - `tests/test-aether.sh`
  - `plans/053-aether.md`
  - copies of that plan in `~/haseen-src-merged/plans/` and `~/.cache/haseen-wt/build/plans/`
- Hunks in modified files:
  - `README.md`: the `theme` layer row's "`haseen aether` (and the Aether launcher entry)…" clause;
  - `docs/architecture.md`: the two rows for the Aether desktop entries and the stand-in `omarchy`;
  - `install.sh`: the comment "The two Aether entries shadow…" and the two `applications/…aether…` entries in the shadow list;
  - `plans/README.md`: the 053 row.
- On io, outside the repo: the AUR package `aether 4.31.1-1` is installed
  (`pacman -Q aether`). Removing it is the owner's choice.

## matugen

- **Package**: `pacman -Si matugen` → `Repository : extra`, version 4.2.0-1,
  `Licenses : GPL-2.0-only`, depends on glibc and libgcc only. There is also
  `chaotic-aur/matugen-git`. Under the package order (AGENTS.md: official repos
  first, then Chaotic-AUR, then the AUR) the `extra` package is the one to use,
  installed with `haseen install package matugen`. It is an optional dependency
  and is not added to any layer's package list. Nothing was installed on io;
  the tests and the nested proof used the v4.2.0 release binary
  (`gh release download v4.2.0 -R InioX/matugen`) in scratch.
- **Licence**: GPL-2.0. haseen runs it as a separate program and reads its
  JSON. No code is taken, so there is no NOTICE row.
- **CLI used** (v4.2.0 `--help`):
  - `matugen image IMG -t scheme-<type> -m dark|light --json hex --dry-run -q --source-color-index 0 -c FILE`
  - `matugen color hex SOURCE …`, with the same flags apart from the colour index.
  - Scheme types: content, expressive, fidelity, fruit-salad, monochrome,
    neutral, rainbow, tonal-spot, vibrant and smart.
  - `--dry-run` means no templates, reloads, wallpaper or commands. `-c` keeps
    the user's own `~/.config/matugen/config.toml` (with its templates and
    hooks) out of the run. `--source-color-index 0` stops the interactive
    prompt that matugen shows when an image has several candidate colours.
  - A config file needs a `[templates]` table, or matugen exits with
    "missing field `templates`" (observed).
  - In the scratch HOME, matugen wrote no file at all: no cache, no config.
- **Output**: `{base16, colors, image, is_dark_mode, mode, palettes}`. Each
  `colors.<role>` is `{dark, default, light}`, and `default` follows `-m`. The
  `palettes` hold the tonal palettes (primary … neutral) at tones 0–100.
- **Cost on io**: about 1.0 s for an image preview (`time` of the `--json` run,
  mostly the image decode). `matugen color` takes 0.05 s.

## Design

### `bin/haseen-theme-generate`

`haseen theme generate <image> [--name N] [--scheme S] [--mode dark|light] [--no-apply] [--json] [--dry-run]`

**Mapping.** The Material roles map onto `colors.toml` keys
(`share/haseen/themes/tokyo-night/colors.toml` is the reference shape):

| colors.toml | matugen |
|---|---|
| background | `surface` |
| foreground | `on_surface` |
| accent | `primary` |
| selection, selection_background | `secondary_container` (Material's selected row) |
| selection_foreground | `on_secondary_container` |
| muted | `outline` |
| dark_foreground | `on_surface_variant` |
| lighter_background | `surface_container_high` |
| bright_foreground | neutral palette tone 95 (dark) / tone 5 (light) |
| red yellow green cyan blue magenta | custom colours (below), Material tone 80 dark / 40 light |
| bright_* | halfway from the hue to its `on_<hue>_container` (tone 90 / 10), mixed with theme-lib's `_theme_mix` |

`dark_background` and `darker_background` are left to theme-lib's derived
shades.

**Terminal hues.** Material You has no terminal colours, so the six hues are
matugen custom colours (`share/haseen/layers/theme/matugen.toml`). Each is a
fixed seed with `blend = true`, which pulls it toward the wallpaper's source
colour. They are taken from a tonal-spot scheme of the source colour (the
second, `matugen color` run), whatever scheme the user picked. Under the
picked scheme they lose their meaning (observed on one wallpaper):

- expressive turned "red" into `#a8c8ff`, a blue;
- monochrome made every hue `#ffffff` (dark) or `#000000` (light);
- content gave `on_red_container` `#000000` in dark mode.

**Readability clamp.** The floors are plan 064's: foreground on background
4.5:1, accent on background 3:1, foreground on selection 4.5:1. Plan 064's Go
clamp (`palette.ClampAnchors`) has no command-line entry point. Its author
confirmed that none is planned: rewriting arbitrary `colors.toml` keys is out of
064's scope. So the clamp uses theme-lib's helpers:

- It measures with `_theme_contrast` (the same WCAG formula as the Go code).
- It mixes with `_theme_mix` in 5% steps toward white or black, whichever end
  contrasts more with the background. That is the direction `clampContrast`
  picks.
- The selection is mixed toward the background, as `_theme_shell_selection`
  does.
- A colour that already passes is kept, so the clamp is idempotent.
- A move is reported with both ratios. On the test's unreadable fixture:
  `foreground 1.45:1 -> 4.97:1`, `accent 1.17:1 -> 3.16:1`,
  `selection 2.12:1 -> 4.56:1`.

The one difference from 064: a mix toward white or black also lowers chroma,
where 064 moves OKLab lightness only. Material schemes rarely need the clamp,
since they are built to these contrasts. None of the fixture's colours moved.

**Output.**
- `--json` prints `{name, scheme, mode, image, source, target, clamped, colors}`
  and writes nothing. This is the panel's preview.
- `target` says whose the name is:
  - `new`;
  - `generated`, an earlier run of this command;
  - `stock`;
  - `taken`, a theme of the user's own.
- Otherwise the command writes `~/.config/haseen/themes/<name>/colors.toml`.
  The first line is `# Generated by \`haseen theme generate\`: …`.
- A copy of the image goes in as `backgrounds/<slug>.<ext>`:
  - A copy, so the theme keeps its background if the picture moves.
  - `theme_backgrounds` finds it through `current/theme/backgrounds`.
  - Older images in that folder are removed.
- Then it runs `haseen theme set <name>` unless `--no-apply` is given.

**Safety.**
- A stock theme's name, or a directory whose `colors.toml` lacks the mark, is
  refused. A user's own theme is never overwritten.
- An unchanged palette does not touch `colors.toml`, the same rule as plan 034.
- `flock` on the theme directory itself, so no lock file ends up inside the
  theme.
- The default name is the image's file name, slugged (`Blue_Hour (2).PNG` →
  `blue-hour-2`).
- Accepted image types are the ones `theme_backgrounds` finds.

### The panel `haseen.themegen`

`share/haseen/shell/plugins/haseen.themegen/`: `Panel.qml`, `Themegen.js` (the
pure model), `PaletteMock.qml`, `Swatches.qml` and `Choice.qml`.

- **Image strip.** The image list is haseen.imagepicker's own:
  - `Images.js` and `ImageCard.qml` are imported from `../haseen.imagepicker`,
    not copied;
  - the same `find` scan and the same `directories`/`depth`/`limit` settings;
  - one thumbnail-sized decode per card.
- **Controls.**
  - Nine scheme choices and Dark/Light. The mode starts at the current theme's.
  - A name field that follows the image until the user types a name.
  - Save (`--no-apply`) and Apply.
- **Preview.**
  - Swatch rows: the anchors, the six hues and their bright variants.
  - A mock desktop: a bar with the accent workspace and a clock, a window
    framed in the accent over the wallpaper, and a terminal with a prompt, a
    selected row, a comment and the six hues.
  - A note under the swatches: the source colour, what Save does to the name,
    and any clamp.
- **Colours.** All of them come from the CLI's `--json`. The panel computes no
  colour, so the mapping and the clamp have one home. The QML has no hex
  literals and no Timer.
- **Runs.** One run per change of image, scheme or mode. A change while a run
  is busy is queued, and runs once with the latest choice.
- **Keys.** Type to filter; Left/Right move through the images; Up/Down change
  the scheme; Tab flips dark/light; Enter applies; Ctrl+S saves; Escape
  closes. `debugIpc` exposes the IPC target `haseen.themegen` (`state`,
  `move`, `setScheme`, `setMode`, `setName`, `save`, `apply`).
- **Gate.** `requires.bins: ["matugen"]` uses plan 064's gate: without
  matugen, the shell refuses the plugin and names the missing command.
- **Off by default**: `share/haseen/default/shell.json` has
  `"haseen.themegen": { "enabled": false }`. AGENTS.md: a new built-in is off
  until the owner adds it to the approved list. It is listed here as
  **awaiting approval**.
- **Menu**: Style › Theme Generator (`style.theme-generator`, right after
  Theme). Its `when` reads `shell.json`, so the row shows only once the
  plugin is enabled (`haseen plugin enable haseen.themegen`).

### Resources

Nothing runs until the panel opens: one `find`, then one matugen run (about
1 s) per change. The panel does no polling. Architecture §6 ("no
wallpaper-derived colour generation at runtime") holds: generation is an
explicit user action, as with `haseen theme wallpaper`.

## Rejected options

- **Keep Aether** (plan 053's stand-in `omarchy`): the owner dropped it. It is
  also an AUR-only app (the last resort in AGENTS.md), and it needs a fake
  `omarchy` command on its PATH.
- **Write colors.toml with a matugen template** (`{{colors.primary.default.hex}}`):
  the clamp, the hue mixing and the overwrite rule would then sit outside
  haseen. Templates are also the part of matugen that runs hooks. JSON plus
  bash keeps matugen a pure function.
- **Hues from the picked scheme**: expressive rotates them and monochrome
  removes them (see Design).
- **matugen's `base16` output**: its light variant is not a light scheme
  (`base00` light was `#fcba61`, observed).
- **A `haseen-palette --clamp FILE` entry point for 064's Go clamp**: out of
  064's scope (its author's answer). The theme-lib helpers apply the same
  floors.
- **`scheme-smart`**: it picks one of the other schemes itself (on the test
  wallpaper it equalled vibrant exactly), which a picker that names the
  schemes would only hide.
- **A link instead of a copy for the background**: the theme would lose its
  background when the picture is moved.
- **A private copy of the image list in the panel**: imported from
  haseen.imagepicker instead.
- **On by default**: not without the owner's approval.

## Verification

- `tests/test-themegen.sh` (131 checks, `QT_QPA_PLATFORM=offscreen tests/run.sh
  tests/test-themegen.sh`; matugen is a stub printing JSON recorded from
  matugen 4.2.0 in `tests/fixtures/matugen/`):
  - **Mapping**: every key against its fixture role, the hues against the
    tonal-spot run, `bright_red` = `#ffc7c3`, and the light-mode tones.
  - **matugen's argv**: `--dry-run`, haseen's `-c`, `--source-color-index 0`,
    the picked scheme on the image run and tonal-spot on the hue run.
  - **Clamp**, on a fixture made unreadable:
    - foreground, accent and selection move and reach 4.5:1, 3:1 and 4.5:1,
      measured with theme-lib;
    - the background stays;
    - a readable palette has no move.
  - **Dry run**: no stub called, no file written, the plan printed.
  - **Writing**:
    - the mark, the keys, the copied background, and nothing else in the
      directory;
    - an unchanged palette is not rewritten;
    - regenerating from another image replaces the background.
  - **Refusals**: a stock name and a user's own theme (left untouched), a
    missing or non-image file, an unknown scheme or mode, a bad name, a
    matugen error (its cause shown), and no matugen (the install hint).
  - **Apply**: `haseen theme set` renders it, the shell tokens come from the
    image, and the background link points at the copy.
  - **Panel**:
    - the plugin validates as a built-in, with exec and files:read only;
    - every setting it reads is declared;
    - no hex literals, timers or shell strings;
    - off in the default `shell.json`;
    - the menu row's `when` is false until `haseen plugin enable`.
  - **Model** (`Themegen.js` under `/usr/lib/qt6/bin/qml`):
    - the schemes equal the CLI's;
    - default names equal the CLI's slug;
    - the argv for preview, Save and Apply;
    - parsing the CLI's real `--json`, including the clamp report;
    - half a palette is refused;
    - name notes, swatch rows and captions, error lines.
- Real matugen 4.2.0 (scratch HOME, `--no-apply`) on a wallpaper: `--json` in
  1.0 s, `colors.toml` and the background written, and a second run reported
  "palette unchanged".
- Nested Hyprland (`nest-launch.sh`; the worktree shell; scratch
  `XDG_*`/`HASEEN_USER_*`; a private D-Bus; a PATH guard over `systemctl`,
  `pkill`, `gsettings`, `swaybg` and the rest, whose log stayed empty; the
  plugin enabled with `debugIpc` and a two-image directory). Screenshots in
  `~/.cache/haseen-wt/Matugen/shots/`:
  - `1-akane-tonal-spot-dark.png`: a red wallpaper, source `#d13e47`, accent
    `#ffb3b1` on `#1a1111`.
  - `2-violet-tonal-spot-dark.png`: after `move 1`, a violet wallpaper, source
    `#623294`, accent `#dabaf9` on `#151218`.
  - `3-violet-vibrant-light.png`: vibrant, light: accent `#8700ec` on
    `#fff7ff`.
  - `4-violet-saved.png`: after `save`, the header says "saved violet", the
    note says "replaces your generated theme violet", and
    `cfg/haseen/themes/violet/` holds the marked `colors.toml` and `violet.png`.
  - After the last reload the shell log has no QML warning.
- `tools/lint.sh` (shellcheck at warning level, qmllint, jq): OK.
  `tests/test-menu.sh` still passes.

## Live apply

1. `./install.sh --tree-only` installs `bin/haseen-theme-generate`,
   `share/haseen/layers/theme/matugen.toml`, the panel, the menu row and the
   default `shell.json`.
2. Optional, the owner's call: `haseen install package matugen` (`extra`).
3. Only after the owner approves: `haseen plugin enable haseen.themegen`, then
   `haseen shell ipc shell reload`. Menu Style › Theme Generator then appears.
   `haseen theme generate <image>` works from a terminal without the panel.
4. Owner checks:
   - Apply in the real session switches the whole desktop, which the nested
     proof did not do (its PATH guard blocked the reloads);
   - adding `haseen.themegen` to the approved list in AGENTS.md, if wanted.
