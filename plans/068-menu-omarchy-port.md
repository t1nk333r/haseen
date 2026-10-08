# Plan 068: the menu, ported from Omarchy's; readable secondary text

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM (the menu is rebuilt; the data side, routes and IPC stay)
- **Depends on**: 016 049
- **Category**: shell
- **Planned at**: 2026-10-07, owner report on io ("the menu indicator is wonky", "menu refresh is janky", "the subscript of apps is not aligning to the colour scheme"), then owner decision: "make the menu exactly like Omarchy"; then "Merge between haseen and Omarchy menus", answered as both a merged entry tree and haseen's header back (section "Merged tree")
- **State**: DONE 2026-10-07 (`tests/test-menu-view.sh`, `tests/test-panel-placement.sh`, `tests/test-menu.sh`; nested-session frame captures before/after and next to Omarchy 4's own shell in a second nest, in `~/.cache/haseen-wt/MenuPolish/shots/`; the merged tree in `~/.cache/haseen-wt/MenuMerge/shots/{root,learn,search}.png`)

## Problem, with evidence (nested Hyprland, theme `haseen`)

1. **Janky refresh.** The menu was a PanelPopup with placement "center": a
   layer surface sized to its content, which the compositor centres. Every row
   count change (each search keystroke, each `when` answer) resized the window,
   and Hyprland re-centred it: the card jumped up and down, and one frame per
   resize showed the old buffer stretched (frame `b-search-04`: a cut row at
   the bottom). The guard batch takes about 0.8 s on io (`bash -c "$(guardScript)"`
   timed), and the panel is destroyed on close, so every open re-ran it and
   `when` rows popped in late (`b-guard-*`: the card first drawn at a different
   size and place). The rows model was a JS array replaced on every answer,
   which rebuilt every delegate, and `settle()` kept the cursor by index, so a
   row appearing above moved the cursor to another row.
2. **Wonky indicator.** Rows took the selection on `onEntered`, so rows passing
   under a still pointer (keyboard scrolling, a narrowing search, rows landing
   late) took the cursor whenever the pointer jittered; Omarchy filters this
   with `PointerMoveGate`. The cursor row parked flush with the list edge
   (`ListView.Contain`), hiding what follows (`b-scroll-*`).
3. **Subtitle colours.** Descriptions and launcher subtitles were `Theme.muted`:
   #525252 on the panel #222222 is 1.9:1 and on the selection #864313 1.05:1 in
   `haseen` (`b-launcher-down-crop`: "Markdown Writer" invisible). Across the 23
   stock themes muted on selection is below 1.5:1 in 13.
4. **Translucent launcher in the owner's screenshot.** The `layers` animation
   (`default/hypr/looknfeel.lua:83`, fade, speed 2) caught mid-way: frames
   `b-launcher-open-*` go from translucent to opaque in about 150 ms and the
   launcher at rest is opaque. Not a colour problem; the launcher keeps its fade.

## Change

- `haseen.menu` is a port of Omarchy 4's `shell/plugins/menu/Menu.qml` on
  haseen's data (menu.jsonc and its overlay, providers, `when`/`checked`/
  `disabled`, routes, the About view, IPC `menu toggle`, the `menu` role and
  the debugIpc hooks): a 300 px card (520 for Capture › Screenrecord and Style ›
  Font) centred over a dimmed screen, no fade, "Go…"/title header that shows
  the query, Omarchy's row size, icon column, fonts and colours mapped onto
  Theme (`MenuStyle.js`), the foreground-tint cursor with accent text and no
  moving highlight, the frozen top edge and height after the first step, the
  folded list with a peeking row and scroll scrims, the search ranking with a
  divider before deeper rows, descriptions only while searching, the keys
  (Up/Down, PageUp/PageDown, Enter/Right, Left/Backspace back, Ctrl+U,
  Ctrl+Backspace, Escape clears then closes) and the pointer gate
  (`PointerGate.qml`).
- Beyond Omarchy, for the reported jank: rows update in place by itemId
  (`MenuModel.syncRows`), the cursor follows its row (`selectionAfter`,
  `selectedId`), late answers freeze only the card's top edge so rows grow
  downward, and guard answers, provider rows and the menu files are kept for
  the shell's lifetime (`MenuModel.memory`), so a reopened menu draws its final
  rows at once.
- PanelPopup placement "overlay" (`PanelPlacement.js`): every edge anchored,
  overlay layer, exclusive zones ignored, no PanelSurface chrome, namespace
  `haseen-overlay` with a `no_anim` layer rule (`default/hypr/windowrules.lua`),
  as Omarchy's `omarchy-menu` rule. The menu's `placement` defaults to it.
- Corner radius: Omarchy rounds the menu like the windows (`Style.cornerRadius`
  is `hyprctl getoption decoration:rounding`). A new shell.json token
  `windowRadius` carries the theme's window rounding (the theme's
  `hyprland.lua`, else `default/hypr/looknfeel.lua`; `_theme_window_radius` in
  theme-lib.sh), read as `Theme.windowRadius` (fallback 4); `haseen` gives 4.
- `Theme.subtle(bg)` (`Haseen/Ink.js`): secondary text is the foreground at
  Omarchy's description alpha 0.52, raised in 0.01 steps until it reads at 3:1
  on its row. Used by the menu descriptions and the launcher subtitles; in
  `haseen` the menu keeps exactly 0.52.

## Merged tree

The owner asked to merge haseen's and Omarchy's menus: Omarchy 4's tree
(`/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`, 368 lines; the
extension file `config/omarchy/extensions/omarchy-menu.jsonc` adds nothing,
every line is a comment) on haseen's commands, with haseen's own rows kept,
and haseen's header back. This replaces plan 016's selection ("no Learn, no
web apps, no crash-capture/herdr/XCompose/direct-boot/reset/channels").

- **Root**: Omarchy's order, `apps learn trigger style setup install remove
  update about system` (`test-menu.sh` pins it).
- **Ids**: every id and alias of the previous tree still resolves
  (`test-menu.sh`, "previous routes and aliases still resolve"). One id
  moved: `install.theme` is `install.style.theme`, with the old id as alias.
  Where both trees had a row, haseen's id and command stay and Omarchy's
  label wins (Notifications, Menu Bar, AUR, QR Code, Fido2, Hyprsunset); a few
  Omarchy ids are aliases where haseen's id differs
  (`setup.default.editor.neovim`, `…vscode`, `setup.config.hyprsunset`,
  `update.config.hyprsunset`, `install.style.font`, `update.omarchy`).
- **Install/Remove**: the category submenus are declared in `menu.jsonc` in
  Omarchy's order; the catalogue providers fill them (a static row wins over
  a provider row of the same id, `MenuModel.swapProviderRows`). The
  catalogue's Font category sits under Install › Style (`"parent"`), as
  Omarchy's `install.style.font`.
- **Header**: haseen's mark (`Branding.symbolicPath` through `BrandImage`, in
  `Theme.accent`, `headingSize` high) centred in the rows' icon column; the
  "Go…"/title/query text starts where the row labels do. No search field.

Mapping, Omarchy row → haseen (`h` = `haseen`):

| Section | Omarchy rows | haseen |
| --- | --- | --- |
| Learn | Keybindings | `h shell ipc keybinds toggle` (the keybind sheet) |
| | Hyprland, Arch, Neovim, Bash (`omarchy-launch-webapp URL`) | `xdg-open` on the same URLs |
| | Omarchy (manual) | replaced by "haseen", `xdg-open` on the repository README |
| | Tmux, Herdr keybindings | `tmux list-keys -N` in `h config terminal`; herdr's `config.toml` in `h config edit` (Omarchy's script annotates that file) |
| Trigger | Emoji, Reminder, Capture (all), Transcode, Share, Speed Tests | `h shell ipc panel toggle haseen.emoji`, `h reminder`, `h capture`, `h transcode`, `h share`, `h test` (existing rows) |
| | Toggle: Stay Awake, Notifications, Screensaver, Nightlight, Menu Bar, Workspace Layout, Window Gaps, 1-Window Ratio | `h toggle` idle, dnd, screensaver, nightlight, bar, workspace-layout, gaps, one-window-ratio |
| | Hardware: Laptop/Mirror Display, Hybrid GPU, Touchpad, Touchscreen | `h hardware …` |
| | Hardware: Touchpad Haptics low/mid/high | `dell-xps-touchpad-haptics set …` directly, shown when the tool is present |
| Style | Theme, Background, Font, Menu Bar (position, transparency), Screensaver, About | haseen's pickers and `h bar`, `h branding` |
| | Unlock (Plymouth theme) | `h plymouth set` (the splash in the current theme's colours) |
| | Hyprland (`looknfeel.lua`) | `h config edit ~/.config/hypr/local.lua` (haseen's user file for look and input) |
| Setup | Monitors, Keybindings, Input, Network (DNS, QR), Plugins (enable, disable, add, remove), Security (fingerprint, FIDO2, SSHD, passwordless sudo), Config › Hyprland | existing `h setup`, `h config` rows |
| | Defaults: agent, browser, terminal, editor | `h setup default …`; Copilot, Cursor CLI, Grok, Hermes, Muse Code, OpenClaw, Pi agents, Brave Origin and Edge browsers, Cursor and Sublime Text editors added to `bin/haseen-setup-default`, each row shown when its command is installed |
| | Config › Hyprsunset, XCompose | `h config edit` on haseen's nightlight settings, on `~/.XCompose` |
| Install | Package, AUR | `h install package`, `h install aur` |
| | Web App | `h webapp install NAME URL [ICON]` after prompts |
| | Style › Theme, Background, Font | `h theme install GIT-URL`; `h theme bg set FILE`; the catalogue's Font category |
| | Service, Editor, Terminal, Browser, AI, Gaming, Development | the catalogue (`h install app ID`). Added to `catalog.json`: Brave Origin, Ollama, ChatGPT Desktop, Grok Bot, T3 Code, Hermes Desktop, OpenClaw, Perplexity, ONCE (packages from the repos or `[omarchy]`/AUR through `pkg_install_aur`'s order) |
| | Development: PHP, Symfony, OCaml, Laravel, Phoenix | `h install package php composer`, `h install aur symfony-cli`, `h install package ocaml opam`; `composer global require laravel/installer` and `mix archive.install hex phx_new` in `h config terminal` |
| | Gaming: Xbox Cloud Gaming | `h webapp install` with Omarchy's URL and icon |
| Remove | Package, Web App, Development, Browser, Gaming, Services, AI, Dictation | `h remove package`, `h webapp remove`, the catalogue (Dictation is in AI), the same static Development and Xbox rows |
| Update | Omarchy | `update.system`, `h update system` |
| | Config › Hyprland, Hyprsunset, Shell, Plymouth | `h refresh` hyprland, nightlight, shell; `h plymouth set` |
| | Extra Themes | `h theme fetch --all` |
| | Process › Hyprsunset, Shell; Hardware; Firmware; Password; Timezone; Time | `h shell ipc nightlight refresh`, `h restart …`, `h update firmware`, `h password …`, `h time …` |
| About, System | all | `h about`, `h system …`, `h screensaver --force` (unchanged) |

haseen's own rows and where they went: Trigger › Context and Toggle ›
Animations; Style › Theme Generator, Next background, Arrange widgets,
Screensaver style and preview, and a new Style › Mark (`h branding mark
kufic|shield|gate`, checked from `h branding mark`); Setup › keyd (after
Input), Secure Boot (after Security), Dotfiles, Battery Charge Limit, Local
AI, SSH Agent; Update › Shell Recovery (after Process).

Left out (`test-menu.sh` checks each is absent):

| Omarchy row | Why |
| --- | --- |
| Learn › Omarchy, Community | Omarchy's manual and Discord |
| Toggle › Crash Capture | haseen's crash watch also keeps the last good shell.json for Shell Recovery (`bin/haseen-crash-watch`); a toggle would switch recovery off |
| Toggle › Battery Percentage | haseen's battery widget always shows the percentage (`haseen.battery/Widget.qml:26`); nothing to toggle |
| Setup › Plugins › Clone Plugin | copies one of Omarchy's first-party plugins; haseen has no clone, Add Plugin scaffolds a new one |
| Setup › Security › Sudoless Docker; Remove › Security (fingerprint, FIDO2, SSHD, sudoless Docker) | root changes with no haseen command; a menu row may not run root steps outside `common.sh` (dry-run contract) |
| Setup › Direct Boot | an EFI entry for Omarchy's UKI |
| Setup › Reset Computer | Omarchy's factory reset |
| Install/Remove › TUI | Omarchy's TUI launcher (`omarchy-tui-install`); haseen has none (plan 057, `haseen launch tui` gap) |
| Install/Remove › Windows, Preinstalls | Omarchy's Windows VM and its preinstall set |
| Install › Service › Chromium Account | edits Omarchy's `chromium-flags.conf` with its OAuth ids |
| Install/Remove › Gaming › NVIDIA GeForce NOW | NVIDIA's own Flatpak remote, which Omarchy's installer adds; haseen installs Flatpaks from Flathub only (`com.nvidia.geforcenow` is not on Flathub: the Flathub API answers 404) |
| Install/Remove › Gaming › Battle.net, RetroArch Game Launcher | Omarchy's Wine prefix and retro launcher scripts |
| Install › Development › Ruby on Rails, Docker DB, JavaScript/PHP/Elixir submenus | the catalogue's flat Ruby, per-database Docker rows and toolchains do the same; the catalogue has no nesting |
| Remove › Theme | no haseen theme removal command |
| Update › Channel | Omarchy's release channels |
| Update › Config › Tmux | resets to Omarchy's tmux config |

## Rejected

- A ListView highlight with a move animation: Omarchy has none, and an
  animated highlight lags behind a list that changes under it.
- Showing the menu only once the guard batch answered: 0.8 s on io.
- `when` showing rows until a false answer (Omarchy's rule): a "Stop
  recording" row would flash up; haseen keeps hiding until true.
- Hiding the jank by delaying layout changes: the card would still move.
- Matching Omarchy's 0.52 everywhere: four stock themes (catppuccin-latte,
  everforest, rose-pine, tokyo-night) fall below 3:1 on the selected row.
- Omarchy's Delete-to-uninstall on app rows: haseen's menu has no app removal.
- Merged tree: Omarchy's ids for rows haseen already had (`trigger.toggle.idle-lock`
  for `trigger.toggle.idle`): routes in binds.lua, the overlay and tests use
  haseen's; only renamed haseen ids get aliases.
- Merged tree: the mark only on the root menu (haseen's header before the
  port): the header is the same on every level in Omarchy's card.
- Merged tree: PHP, Symfony and OCaml as catalogue entries: the catalogue's
  development rule is mise or Docker toolchains (`test-catalog.sh`); they are
  menu rows on `haseen install package`/`aur` instead.

## Review notes

- Back selects the submenu just left when visible and leaves a valid selection after a search-only drilldown; covered by `tests/test-menu-back.sh`.

## Verification

- `tests/test-menu-view.sh`: a real ListModel and ListView under the Qt engine;
  a guard answer inserting a row above the cursor keeps the cursor and every
  delegate; an unchanged answer writes nothing; descriptions and subtitles read
  at 3:1 on normal and selected rows for all 23 rendered stock themes.
- `tests/test-panel-placement.sh`: the overlay placement.
- Nested session: frame sequences before (`b-*`) and after (`a-*`), Omarchy's
  shell in a second nest at the same colours (`o-*`), side by side (`cmp-*`).
- Merged tree, `tests/test-menu.sh`: root order; the listed Omarchy and
  haseen rows exist and the left-out ones do not; every action runs
  `haseen …` (each command resolving in `bin/`), `xdg-open 'https://…'` or
  `dell-xps-touchpad-haptics set`; URLs only through `xdg-open` or
  `haseen webapp install`; no `omarchy-` in actions or guards; the previous
  tree's aliases, binds.lua's routes and `install.theme` resolve
  (`MenuModel.resolveRoute`). `tests/test-catalog.sh` takes Brave Origin as
  the second non-Flathub browser.
- Merged tree, nested session (theme `haseen`, `MenuMerge/shots/`): `root.png`
  (the mark in the accent left of "Go…", the ten sections in Omarchy's order),
  `learn.png`, `search.png` ("theme": Style › Theme, Install › Style › Theme,
  Update › Extra Themes, an app). Over the debug IPC: Install lists Package,
  AUR, Web App, Style, Service, Development, Editor, Terminal, Browser, AI,
  Gaming; Install › Style lists Theme, Background, Font.
