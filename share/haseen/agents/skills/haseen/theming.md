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

The same `colors.toml` may set the shell's non-colour tokens:

```toml
font_family = "Inter"
font_mono = "JetBrainsMono Nerd Font"
font_size = 11
radius = 6
gap = 6
border_width = 1
```

These become `Theme.fontFamily`, `fontMono`, `fontSize`, `radius`, `gap`,
`borderWidth` in the shell (numbers must be numbers). `Theme.windowRadius` is
not a colors.toml key: it is the frame's inner radius (shell.json
`frame.radius`, else twice `radius`), which the menu uses and which
`haseen theme set` also writes as Hyprland's `rounding` in
`current/theme/rounding.lua`, loaded with the defaults so `haseen toggle
gaps`, hyprmod and your own files still override it; a theme's own
`rounding` is ignored (plan 046). The colour tokens the
shell gets are derived in `$HASEEN_PATH/themed/shell.json.tpl`
(`surface` = background mixed 6 % toward foreground, `urgent` = red,
`warning` = yellow, `success` = green, …).

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
