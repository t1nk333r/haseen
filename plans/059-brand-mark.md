# Plan 059: haseen's brand mark (kufic, shield, gate)

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (art and one setting; the splash change needs `haseen plymouth set`)
- **Depends on**: 019 036 048
- **Category**: shell, branding
- **Planned at**: 2026-10-07, owner request: ship the three marks, kufic by default, a setting to switch
- **State**: DONE 2026-10-07 (tests in `tests/test-branding.sh`, `test-plymouth.sh`, `test-ambient.sh`; nested-session screenshots of menu, About and `haseen.logo` for each mark; the real boot splash is an owner check)

## Problem

haseen showed no mark of its own. The menu header said "Menu", the About panel
printed the word "haseen", the screensaver's default text was a figlet
rendering (`share/haseen/default/screensaver/screensaver.txt`, removed here),
the boot splash had only a pulsing bar (`share/haseen/default/plymouth/haseen.script`
before this plan), and `notify-send -i haseen` found no icon. Omarchy shows its
logo in all of these places. Three original marks were drawn for haseen
(kufic: a square-Kufic حصين; shield; gate). The owner liked all three.

## Decision

- **All three ship; kufic is the default.** `share/haseen/branding/<mark>/` holds
  `mark.svg`, `symbolic.svg` (16 px grid), `symbolic-24.svg` and `wordmark.svg`,
  filled with `currentColor`. `share/haseen/branding/logo-<mark>.txt` is the
  terminal logo. The kufic logo uses full blocks, two columns per cell (80 columns).
  Shield and gate use half blocks for the mark, so the 16-cell drawings fit
  beside the same "haseen" letters (78 columns; the limit is 81). All of them
  come from the same bitmaps as the SVGs.
- **One setting.** `branding.mark` in `shell.json` (`share/haseen/default/shell.json`
  sets `kufic`). `haseen branding mark [name] [--dry-run]` reads or writes it
  through `shell_config_write`, and refuses unknown names. The existing
  `screensaver`/`about` subcommands of `bin/haseen-branding` are unchanged.
  `share/haseen/lib/branding.sh` and `share/haseen/shell/Haseen/Branding.qml`
  read the setting with one rule: anything but the three names is kufic. A
  broken user file does not stop `haseen about --logo` or the splash.
- **Colour from the theme.** The shell uses the software renderer, so it has no
  shader recolouring (the reason is noted in
  `share/haseen/shell/plugins/haseen.tray/TrayIcon.qml:3`).
  `Haseen/Widgets/BrandImage.qml` writes a `Theme` colour into the SVG text and
  loads it as a data URL.
- **Where it shows:**
  - the menu header (the symbolic mark in `Theme.accent` at the top level);
  - the About panel (the wordmark, unless `haseen branding about` set a text
    or an image);
  - `haseen about --logo` (logo, then facts);
  - the screensaver default, in both the ttfx and the native style;
  - the boot splash: `haseen plymouth set` renders `mark.svg` in the accent
    colour to `logo.png` with ImageMagick and installs it beside the script.
    The script draws it above the password prompt. Dry run prints the render
    and the install, and runs nothing;
  - the app icon: `install.sh` installs `hicolor/scalable/apps/haseen.svg`
    (accent baked in) and `hicolor/symbolic/apps/haseen-symbolic.svg` under
    `PREFIX`. `haseen branding mark` writes the same two files per user under
    `$XDG_DATA_HOME/icons/hicolor`.
- **The greeter is unchanged:** it shows no logo
  (`share/haseen/shell/greeter/GreeterCard.qml`).
- **Bar: no new default element.** `haseen.logo` is an optional bar widget
  (`share/haseen/shell/plugins/haseen.logo/`). It shows the symbolic mark in
  `Theme.barForeground`, and a click toggles the menu. It is
  `"enabled": false` in the default `shell.json` and in no section, per the
  no-clutter and default-plugin rules in `AGENTS.md`.

## Rejected

- **One mark only.** The owner asked for all three.
- **MultiEffect/ColorOverlay recolouring.** Needs shaders; the shell renders
  with `QT_QUICK_BACKEND=software`.
- **PNG assets in the repository.** The splash has shipped no binary assets
  since plan 036; the PNG is rendered at install time instead.
- **Full-block shield/gate logos.** At 16 cells × 2 columns plus the letters,
  they come to 94 columns, over the 81-column limit.
- **A bar logo on by default.** The owner's bar is full; the menu is on a key.

## Verification

- `tests/run.sh tests/test-branding.sh`:
  - the command (help, dry-run purity, it keeps the rest of `shell.json`,
    refuses unknown names, writes the icons);
  - `haseen about --logo` prints each mark's logo; a bad or broken setting
    falls back to kufic;
  - `Branding` in the real Quickshell engine: each mark's paths exist; bad
    and non-string values fall back to kufic.
- `tests/test-plymouth.sh`: the dry run renders the selected mark and installs `logo.png`.
- `tests/test-ambient.sh`: ttfx gets `logo-gate.txt` when the mark is gate.
- A nested Hyprland (workspace 5) showed the menu header, the About panel and
  `haseen.logo` in the bar for kufic, shield and gate (`grim -o IO`).

## Live apply

The shell follows `shell.json`, so `haseen branding mark <name>` shows at once.
The new files (the `Branding` singleton, `haseen.logo`) need the installed tree
(`./install.sh --tree-only`) and a shell restart. Then run
`haseen plymouth set` for the splash.
