# Plan 016: Omarchy-style menu with the owner's item selection

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. The menu is the owner's selection, with no Learn and no web apps. Navigation was verified live over the debug IPC. Root-only setup steps were tested as dry runs only.

## Why this matters

The owner picked menu items from Omarchy's menu on 2026-10-04 (recorded in this plan). The menu engine (JSONC tree, providers, `when`/`checked`/`disabled` guards) is ported from Omarchy (MIT). Web apps are excluded.

## Execution record

**Changed**
- `share/haseen/shell/plugins/haseen.menu/`: `manifest.json` (panel, `provides: ["menu"]`, settings `width`/`maxRows`/`debugIpc`); `MenuModel.js`, a port of Omarchy's MenuModel.js (MIT) with the overlay merge done per key per item, `hidden`, `when` hiding a row until its guard answers true, haseen guard helpers (`haseen-pkg-present`, `haseen-cmd-present`, `haseen-flag`) and readers, and catalog rows; `Panel.qml`, the engine (routes and aliases, a provider queue, one async bash guard batch per load, search, nav stack, the About view, the debug IPC target `haseen.menu` with select/back/accept/search/state). It registers the `menu` role while it exists. `About.qml` shows the `haseen about --facts` output plus `branding/about.{png,txt}`.
- Providers: `apps` (DesktopEntries, refilled on `valuesChanged`), `fonts`, `backgrounds`, `plugins-enable`/`-disable`/`-remove`, and `catalog-install`/`-remove`, which read Catalog's `default/catalog.json` plus `haseen install app --installed`. A route into provider rows such as `haseen menu install.browser` waits for the provider.
- `share/haseen/default/menu.jsonc`: the owner's selection. It has no Learn group, no web apps, no crash-capture/herdr/XCompose/direct-boot/reset/channels.
- Commands: `haseen menu`, `about` (`--facts`), `system`, `setup dns|default|fingerprint|fido2|sshd|ssh-agent|passwordless-sudo`, `font list|set|current`, `branding`, `config edit|terminal|plugin`. Root steps go through `run_root`/`write_root_file`. Interactive ones use Catalog's `lib/terminal.sh`. `config plugin remove` only deletes real directories under `~/.config/haseen/plugins` and refuses symlinks into the omarchy/DMS plugin dirs.
- shell.qml `menu` IPC target: added by Frame from my snippet.

**Evidence**
- `tests/run.sh tests/test-menu.sh`: 199/199. `test-shell.sh`: 162/162. shellcheck (warning) and `bash -n` are clean; qmllint shows 0 errors; `jq` passes on the manifest.
- Every `haseen …` named in menu.jsonc actions and guards resolves in `bin/` once all slices landed: the test's missing list is empty.
- Live smoke on a scratch instance with its own XDG dirs, `dbus-run-session`, `QT_NO_XDG_DESKTOP_PORTAL=1`, idle and lock disabled, `debugIpc` on. I opened the menu at the root and at `trigger.capture`, navigated into Screenrecord and back with the hooks, searched (`dns` → DNS), and checked fonts, plugins-disable, the install/remove catalog, `install.browser` (Zen disabled ✓), Apps and About. Screenshots are in `/tmp/menu-smoke/{capture,root,rootmenu,about}.png`.
- RSS: 164 MiB idle with the menu registered and never opened (the panel is lazy). It rose to 203 MiB after opening it, Apps (DesktopEntries scan) included, and stayed there after close. The QML/JS heap is not returned to the OS.

**Rejected**
- A bar widget for the menu (Omarchy has one): visual clutter, the menu opens from a bind.
- A `menu` IPC handler inside the plugin: panels are lazy, so the target would not exist while the menu is closed. shell.qml routes it instead.
- Editing `foot.ini` and other configs for `haseen font set`: user files are never edited after seeding. The font goes through `~/.config/haseen/font`, which the theme render reads (Themes).
