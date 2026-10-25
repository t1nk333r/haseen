# Themes, fonts and hooks

haseen themes use Omarchy's `colors.toml` format, so Omarchy themes work
unchanged.

```bash
haseen theme list                 # stock (in $HASEEN_PATH/themes) and user themes
haseen theme current
haseen theme set tokyo-night      # names are case-insensitive; spaces become dashes
haseen theme install https://github.com/<owner>/<repo>   # clone into ~/.config/haseen/themes/<name>, then set it
```

The default theme is `haseen`, haseen's own (HANCORE's Greek Noir with an
animated active border). Its old name `greek-noir-akane` still sets it, with a
notice. It ships no images: the user's own go in
`~/.config/haseen/backgrounds/haseen/` (the old `backgrounds/greek-noir-akane/`
is still read), and `haseen theme bg next` cycles them.

`haseen theme set` renders `$HASEEN_PATH/themed/*.tpl` (and the user's
`~/.config/haseen/themed/*.tpl`) into `~/.local/state/haseen/current/theme/`,
swaps it in, reloads Hyprland, terminals, btop and the GTK colour scheme, and
runs the `theme-set` hook. The shell follows `current/theme/shell.json` live.
Never edit `current/theme/` by hand: the next `theme set` replaces it.

GTK 3 and GTK 4 apps, libadwaita ones included, take their colours from
`current/theme/gtk.css` (libadwaita named colours such as `window_bg_color`
and `accent_bg_color`). `theme set` writes `~/.config/gtk-4.0/gtk.css` and
`~/.config/gtk-3.0/gtk.css` once with an `@import` of it; a gtk.css that
already exists is left alone, so add that import line yourself to keep your
own. Restart a running GTK app to see a new theme.

## Change colours

- **Tweak a stock theme**: put only the keys you change in
  `~/.config/haseen/themes/<same name>/colors.toml`; it is laid over the stock
  one. Then `haseen theme set <name>`.
  ```toml
  # ~/.config/haseen/themes/tokyo-night/colors.toml
  accent = "#ff9e64"
  ```
- **New theme**: `~/.config/haseen/themes/<new-name>/colors.toml` with the
  full key set; copy a stock one from `$HASEEN_PATH/themes/<name>/colors.toml`
  as the start. Never edit the stock files.

Keys: `mode` (`dark`/`light`), `accent`, `selection`, `muted`, `background`
and `foreground` (plus `dark_`, `darker_`, `lighter_`, `light_`, `bright_`
variants), and the ANSI names `red yellow orange green cyan blue magenta
brown` with `bright_` variants. Colours are `#rrggbb`.

## Fonts, radius, spacing (the shell's look)

The shell looks like Omarchy 4.5's (plan 115). Its sizes, spacing, state
fills and surface roles are Omarchy's, rendered from `colors.toml` into
`current/theme/shell.json` (`$HASEEN_PATH/themed/shell.json.tpl`): panels are
the theme's background with a 2 px border in the Hyprland active-border colour
(its gradient where the theme has one, `hyprland_active_border`), hover and
selection are the foreground at Omarchy's alphas.

- **Font**: the shell's text and icons use your monospace font, a Nerd Font:
  `haseen font set "<family>"` (see `haseen font list`), else the theme's
  `font_mono` (JetBrainsMono Nerd Font). Arabic falls back to Noto. A theme's
  `font_family` sets fontconfig's sans-serif for apps, not the shell. The base
  size is Omarchy's 12 px.
- **Corner radius and edge gap** follow Hyprland: the shell reads
  `decoration:rounding` and half of `general:gaps_out` when it starts and
  whenever Hyprland reloads its config, so whatever Hyprland applies (the
  rounding `haseen theme set` gives it, `haseen toggle gaps`, your own
  `~/.config/hypr/local.lua`) reaches the panels too.
- The same `colors.toml` may still set `radius` (the shell's radius until
  Hyprland answers), `gap` (a spacing step), `border_width`, `font_mono`
  and `font_size` (the terminal size `haseen font set` writes); numbers must
  be numbers.

These become `Theme.fontFamily`, `fontMono`, `fontSize`, `radius`, `gap`,
`borderWidth` in the shell (numbers must be numbers). The window corner
radius is not a colors.toml key: as in Omarchy, it is the theme's own
Hyprland `decoration.rounding`, set in the theme's `hyprland.lua` (0, square,
when it sets none), and the shell reads it back from Hyprland. `haseen toggle
gaps`, hyprmod and your own files still override it (plan 114). The screen
frame is off by default; `"frame": { "enabled": true }` in
`~/.config/haseen/shell.json` turns it on. Its inner radius is the windows'
unless `frame.radius` is set. The colour tokens the shell gets are derived in
`$HASEEN_PATH/themed/shell.json.tpl` (`surface` = background, `surfaceAlt` =
foreground 8 % over it, `border` 40 %, `selection` 18 %, `urgent` = red, …),
with Omarchy's `shellValues` beside them (plan 115).

## Theme another app

Add a template `~/.config/haseen/themed/<output-file>.tpl`. Placeholders:
`{{ accent }}`, `{{ accent_strip }}` (no `#`), `{{ accent_rgb }}` (`r,g,b`),
`{{ mix background foreground 12% }}`. A user template with the same name as
a stock one replaces it. After `haseen theme set <name>` the output is
`~/.local/state/haseen/current/theme/<output-file>`; point the app's config at
that path once (an include line), so it follows every theme change.

## Hooks

Scripts run on events: `theme-set`, `post-update`, `post-boot`,
`layer-applied`.

```bash
haseen hook install theme-set ./restart-my-app.sh   # copies to ~/.config/haseen/hooks/theme-set.d/
haseen hook run theme-set tokyo-night                # test it
```

Hooks run with bash, get the event's arguments, and a failing hook is
reported, never fatal. Files ending in `.sample` are skipped.
