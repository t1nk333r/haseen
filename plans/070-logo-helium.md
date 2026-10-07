# Plan 070: the bar logo on by default, `haseen bar add`, and Helium among the default browsers

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (one more widget in the default bar, a new command, a migration that only adds the logo to a user's own bar sections, and catalogue/menu ordering)
- **Depends on**: 017 059
- **Category**: shell, apps
- **Planned at**: 2026-10-07, owner requests (io): "Add the haseen icon to the bar, left of the workspaces, and make it open the menu." and "https://helium.computer/ is one of the three default browsers: 1. Zen, 2. Chromium, 3. Helium."
- **State**: DONE 2026-10-07 (`tests/test-logo-helium.sh`; `tests/test-catalog.sh` updated)

## The logo

Plan 059 shipped `haseen.logo` off and in no bar section. The owner's request
approves it for the default set (AGENTS.md, "Never ship optional plugins by
default"):

- `share/haseen/default/shell.json`: `bar.left` is
  `["haseen.logo", "haseen.workspaces"]`; the `plugins."haseen.logo".enabled:
  false` default is gone.
- `haseen.logo/Widget.qml`: a left click calls the IPC `menu toggle` with
  `settings.menu` (empty: the top of the menu; when the menu is closed,
  `shell.qml` opens it). It now addresses its own shell by pid
  (`qs ipc --pid`), as the other bar widgets do. The mark is drawn with the
  bar button's colour (`Theme` via `BarButton`).
- Migration `1791365994-bar-logo.sh`: a user `shell.json` with its own bar
  sections hides the new default, so the logo goes at the start of their
  `bar.left`, unless it is already in `bar.left`, `bar.center`, `bar.right` or
  `bar.overflow`. Without a user file, or with one that keeps the default
  sections, it does nothing. A plugin entry the user set to `enabled: false`
  stays theirs.

## `haseen bar add`

`haseen bar move` refuses a widget that is not in the bar. `haseen bar add
<id> <left|center|right> [--before <id>] [--dry-run]` places one: under the
shell.json transaction lock, the section is read from the merged config and
written whole, nothing goes in front of the tray, an off plugin is turned on,
and a widget already in the bar (or the overflow panel) is refused with a
pointer to `haseen bar move`. The running shell picks the file up through its
watch, as with `haseen plugin enable`.

## The default browsers: Zen, Chromium, Helium

- Catalogue (`haseen install app`, menu Install › Browser): the browser
  entries start `zen`, `chromium`, `helium`. Zen and Chromium are Flathub
  apps. Helium is not on Flathub (Flathub search API, 2026-10-07), so it is
  `helium-browser-bin` with source `aur`: `pkg_install_aur` takes it from
  Chaotic-AUR when that repo is on (0.18.3.1-1 there), else builds it. Its
  desktop id is `helium.desktop` and its command `helium-browser`.
- `haseen setup default browser`: knows helium and lists zen, chromium, helium first.
  A browser lists its desktop ids, native package first and then the Flathub
  app id (`app.zen_browser.zen.desktop`, `org.chromium.Chromium.desktop`), and
  setting it picks the first installed one, so the Flathub installs the
  catalogue makes can be the default handler.
- Menu Setup › Defaults › Browser lists Zen, Chromium, Helium first; Zen and
  Chromium show for the Flathub installs too.

haseen ships no `mimeapps.list` and no install step installs a browser (the
install picker offers layers and setup steps only), so nothing installs or
sets a browser on its own. Zen as the system handler is
`haseen setup default browser zen` after `haseen install app zen`. The owner's
live default is not touched.
