# Plan 004: Theme pipeline compatible with Omarchy colors.toml

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001
- **Category**: theme
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04.

## Why this matters

Requirement 4: Omarchy themes have to install unchanged, and every app has to be themed from one source.

## Scope

- `layers/theme`.
- `bin/haseen-theme-{set,list,current,install}` and `bin/haseen-hook`.
- `share/haseen/themed/*.tpl` and stock themes.
- The renderer is adapted from omarchy `omarchy-theme-set-templates` (MIT).

## Acceptance

- Rendering every stock theme produces the expected files.
- Installing an Omarchy theme from a git URL works offline in tests (local repo).
- `shell.json` carries every key listed in architecture §7.

## Execution record

### What changed

- `share/haseen/layers/theme/theme-lib.sh`: the pipeline, ported from Omarchy
  (MIT; notice in the header): the colors.toml parser and alias/derive cascade
  (`omarchy-theme-color`), the one-pass awk renderer with `{{ key }}`,
  `{{ key_strip }}`, `{{ key_rgb }}`, `mix`/`mix_strip`/`mix_rgb`,
  `hypr_gradient`/`gradient_start`/`shell_gradient`
  (`omarchy-theme-set-templates`), staging + swap and the installed-theme
  denylist (`omarchy-theme-set`), foot OSC retint (`omarchy-theme-osc`) and
  the git URL refusals (`omarchy-git-url-check`). Derived shades use integer
  parts-per-million maths in bash instead of an awk process per mix.
- Commands: `bin/haseen-theme-{set,list,current,install}`, `bin/haseen-hook`
  (`run <event> [args]`, `install <event> <script>`).
- `share/haseen/layers/theme/layer.sh`: no packages (bash + awk only).
  `layer_apply` runs `haseen theme set tokyo-night` only when the user has no
  theme; `layer_status` reports theme count and the current theme.
- Templates `share/haseen/themed/`: `hyprland.lua foot.ini kitty.conf
  ghostty.conf alacritty.toml btop.theme neovim.lua` verbatim from Omarchy,
  plus new `shell.json.tpl` and `gtk.css.tpl` (libadwaita `@define-color`).
- Stock themes `share/haseen/themes/`: tokyo-night, catppuccin, gruvbox,
  rose-pine (Omarchy's is Dawn, i.e. light) and catppuccin-latte, text files
  only (88 KB total). Omarchy's `shell.lock.toml` was dropped: it overrides a
  section of Omarchy's `shell.toml`, which haseen does not generate.
- `tests/test-theme.sh` + fixture `tests/fixtures/theme-omarchy-nord/` (the
  text files of Omarchy's nord, so the install test is hermetic).

Paths: output `~/.local/state/haseen/current/theme/`, name
`current/theme.name`, background link `current/background`, staging
`current/next-theme` (moved aside as `old-theme` during the swap), user
templates `~/.config/haseen/themed/`, user themes `~/.config/haseen/themes/`,
user backgrounds `~/.config/haseen/backgrounds/<name>/`, hooks
`~/.config/haseen/hooks/<event>` + `<event>.d/*`.

### shell.json mapping (architecture §7)

| key | source |
|---|---|
| mode | `mode` (→ `theme_type` → `light.mode` → background luminance → dark), normalised to light/dark |
| background | `background` |
| surface | `mix background foreground 6%` |
| surfaceAlt | `mix background foreground 12%` |
| foreground | `foreground` |
| muted | `muted` (Omarchy: falls back to color8 / dark_foreground) |
| accent | `accent` (new fallback: `blue` when a theme predates `accent`) |
| accentFg | `background` |
| urgent | `red` (Omarchy's shell maps urgent to red too) |
| warning | `yellow` |
| success | `green` |
| border | `mix background foreground 20%` |
| selection | `selection` |
| fontFamily / fontMono / fontSize | `font_family` / `font_mono` / `font_size`, default `Inter` / `JetBrainsMono Nerd Font` / 11 (agreed with Desktop, which installs inter-font and ttf-jetbrains-mono-nerd) |
| radius / gap / borderWidth | `radius` / `gap` / `border_width`, default 6 / 6 / 1 |

The non-colour tokens are new optional colors.toml keys; a non-numeric number
token falls back to its default with a warning so shell.json stays valid JSON.

### Installed-theme denylist

A user theme with a `.git` directory (what `haseen theme install` creates) is
staged through a filter: any `*.lua`, `*.sh`, file with an exec bit, symlink
(any depth), and `alacritty.toml foot.ini ghostty.conf kitty.conf
vscode.json` are dropped and named on stderr; templates fill the gap. A theme
the user wrote (no `.git`, or a symlink to their working copy) stages in full.
Install refuses: git options / `ext::` helpers / unknown schemes, names
outside `[a-z0-9_][a-z0-9._+-]*`, repos without a colors.toml with hex
background+foreground (the clone goes to `.install-XXXXXX` first, so nothing is
left behind), and replacing a theme the user wrote. colors.toml values outside
Omarchy's charset (quotes, backslash, `;`, …) are skipped with a warning.

### Post-set

Only for what runs, each through `run`: `hyprctl reload` when
`HYPRLAND_INSTANCE_SIGNATURE` is set; foot retint via OSC to the ptys of foot's
children (foot never re-reads its config); `pkill -USR1 -x kitty`,
`pkill -USR2 -x ghostty`, `pkill -USR2 -x btop`; `gsettings` color-scheme
prefer-light/dark (+ icon theme when `/usr/share/icons/<icons.theme>` exists)
when a session bus exists; then `haseen-hook run theme-set <name>`.
`HASEEN_THEME_HEADLESS=1` skips all of it (installer/chroot/smoke).

### Evidence

- Parity with Omarchy's own scripts (`/tmp/ref/omarchy`), on tokyo-night,
  catppuccin, gruvbox, rose-pine, catppuccin-latte, nord and everforest: the
  seven shared template outputs are byte-identical (`cmp`), and the resolved
  palette equals `omarchy-theme-color --all` (`diff` empty apart from the new
  token keys). A probe template exercising every helper renders identically:
  `mix=#2f3240 strip=3c4a6f rgb=98,102,126 hg={ colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 } sg=rgba(33ccffee) rgba(00ff99ee) 45deg gs=#33ccff hf="rgba(595959aa)" a=122,162,247 s=7aa2f7 u={{ unknown_key }}`
  (pinned in the test).
- `tests/run.sh tests/test-theme.sh` → `215/215 passed`. Mutation check (each
  reverted): removing the `*.lua` deny → 8 failures; the exec-bit deny → 2;
  the symlink deny → 2; user-before-stock template order → 1; mix rounding → 3.
- `/tmp/tools/shellcheck --severity=warning -x` on all seven shell files → clean;
  `bash -n` clean; `luac -p` + `jq empty` on stock `neovim.lua`/`vscode.json`
  and on rendered `hyprland.lua`/`neovim.lua`/`shell.json` of every stock theme
  (in the test).
- `foot --check-config -c current/theme/foot.ini` (foot 1.28.0) → exit 0.
- Rendered `hyprland.lua` for tokyo-night is byte-identical to the one the live
  Omarchy 4.0.4 / Hyprland 0.56.2 session loads
  (`~/.local/state/omarchy/current/theme/hyprland.lua`).
- Smoke: `env -i HOME=$scratch HASEEN_THEME_HEADLESS=1 haseen theme set tokyo-night`
  → `[*] theme: tokyo-night`; shell.json `"surface": "#232431"`,
  `"accent": "#7aa2f7"`, …; foot.ini starts `[colors-dark]`,
  `foreground=a9b1d6`, `background=1a1b26`.

### Rejected

- **Shipping Omarchy backgrounds.** Several are third-party artwork (e.g.
  `1-totoro.webp`) whose licence is not Omarchy's MIT, and most are over
  500 KB. No images are shipped; with no image the `current/background` link is
  removed and the shell paints the theme background. Users drop images in
  `~/.config/haseen/backgrounds/<theme>/`, or take them from
  https://github.com/basecamp/omarchy/tree/master/themes.
- **Omarchy previews/unlock images** (`preview*.png`, `unlock.png`): consumers
  are Omarchy's picker and lock screen; not shipped.
- **Converting legacy alacritty-only themes** (`omarchy-theme-colors-from-alacritty`):
  extra code for pre-colors.toml themes; such themes are refused at install and
  at set with a clear message instead.
- **Filtering at install time only**: Omarchy filters at staging so a later
  `git pull` in the theme dir is covered too; kept that.
- **gawk `RT`** to preserve a template's missing final newline: not portable
  to mawk; every output line ends with a newline.
- **Detecting Hyprland with `pgrep Hyprland`**: matches other users'/nested
  sessions; `HYPRLAND_INSTANCE_SIGNATURE` is what `hyprctl` itself needs.
- **`pkill -USR1 foot`**: foot's USR1/USR2 switch between its dark/light
  palettes and never re-read the config, so it would not apply a new theme.

### Open risks

- The renderer lives in `layers/theme/theme-lib.sh` because `lib/` is core;
  it could move to `lib/theme.sh` (the commands source one path).
- Nothing seeds app configs to include the rendered files except foot
  (Desktop) and Hyprland (Desktop). kitty/ghostty/alacritty/btop/GTK/neovim
  need an include line or symlink seeded by whoever owns those apps; the
  outputs are ready.
- `tests/lib.sh` does not stub `pkill`, `pgrep` or `gsettings`; the theme test
  stubs them itself so it never signals the developer's session.
- `theme set` mutates `~/.local/state/haseen` directly (not through `run`):
  the dry-run branch prints the plan and exits before any write, which the
  tests check with a full `find $HOME` before/after.
