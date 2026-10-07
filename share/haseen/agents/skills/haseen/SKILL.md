---
name: haseen
description: >
  REQUIRED for end-user customisation of a haseen desktop (Hyprland Lua +
  the haseen Quickshell shell on CachyOS, Arch or NixOS). Use when editing
  ~/.config/hypr/*.lua, ~/.config/haseen/ (shell.json, ai.json, plugins/,
  themes/, themed/, hooks/), writing or changing a shell plugin (bar widget,
  panel, service, launcher provider, overlay), changing keybindings, monitors,
  window rules, gaps, themes, fonts, the bar, the local AI setup, or running
  user-facing `haseen` commands. Not for developing haseen's own source tree.
---

<!--
Structure adapted from Omarchy's agent skill (default/agents/skills/omarchy),
MIT License, Copyright (c) David Heinemeier Hansson. Content rewritten for haseen.
-->

# haseen

haseen is a small desktop layered onto CachyOS or Arch (NixOS through the
flake): Hyprland with a Lua config, plus its own Quickshell shell (one thin
bar; everything else is a panel opened on demand). This skill lets you change
it for the user without breaking updates.

## When to use this skill

- Any edit under `~/.config/hypr/` or `~/.config/haseen/`.
- Bar layout, bar widgets, panels, a new shell plugin.
- Keybindings, monitors, window rules, gaps, borders, animations.
- Themes, colours, fonts, the shell's look.
- The local AI endpoint (`~/.config/haseen/ai.json`).
- Running `haseen …` commands for the user.

**About to edit a file under `~/.config/` on this machine? Read this skill
first.** Not for work on the haseen repository itself.

## Topic guides

Read the matching guide before you start:

- [`plugins.md`](plugins.md): shell plugins (create, validate, enable, reload), the manifest, Theme tokens, resource rules.
- [`hyprland.md`](hyprland.md): keybindings, monitors, window rules, look and feel in Lua.
- [`theming.md`](theming.md): themes, colours, fonts, templates, hooks.
- [`ai.md`](ai.md): the local AI endpoint, `ai.json`, the `local` policy, the AI panel.

## The one hard rule: never edit `$HASEEN_PATH`

`$HASEEN_PATH` is the installed haseen tree: `/usr/local/share/haseen`
(installer), `/usr/share/haseen` (package) or a `/nix/store/…/share/haseen`
path (NixOS). Updates replace it. **Never write there**, never `sudo` into it.
Reading it is safe and useful: it holds the defaults you build on.

```
$HASEEN_PATH/               READ-ONLY (reading is fine)
├── default/hypr/*.lua      Hyprland defaults (input, looknfeel, binds, windowrules, autostart)
├── default/shell.json      default bar layout
├── default/ai.json         default AI endpoints and policy
├── shell/                  the Quickshell shell, built-in plugins, plugin.schema.json, templates/
├── themes/  themed/        stock themes and the templates rendered from them
└── layers/                 what `haseen layer apply` installs
```

Where changes go instead:

| You want to change | Edit (user-owned) |
|---|---|
| Hyprland (binds, monitors, rules, anything) | `~/.config/hypr/bindings.lua`, `monitors.lua`, `local.lua` (create them; `hyprland.lua` loads them) |
| Bar layout, plugin settings, services | `~/.config/haseen/shell.json` |
| A shell plugin | `~/.config/haseen/plugins/<id>/` |
| A built-in plugin's behaviour | copy it to `~/.config/haseen/plugins/<same id>/`; the user copy wins |
| Theme colours | `~/.config/haseen/themes/<name>/colors.toml` |
| Extra themed app configs | `~/.config/haseen/themed/<file>.tpl` |
| AI endpoints, policy | `~/.config/haseen/ai.json` |
| Scripts on events | `~/.config/haseen/hooks/<event>.d/` (via `haseen hook install`) |

User files are seeded once and never rewritten by haseen. Anything in
`~/.local/state/haseen/` (rendered theme, `active-shell`) is generated: do
not hand-edit it, change the source and re-run the command that renders it.

Use `sudo` only for things the user asked for that need it (packages, system
services), in a terminal where they can type the password. haseen's own
commands call `sudo` themselves where needed; do not wrap them in `sudo`.

## Command discovery

One router, `haseen <group> <verb>`, dispatches to `haseen-<group>-<verb>`
scripts. Every command takes `--help`; every command that changes something
takes `--dry-run`, which prints the plan and touches nothing.

```bash
haseen commands             # every command with its arguments and summary
haseen commands plugin      # one group
haseen plugin new --help    # help for one command (does not run it)
cat "$(command -v haseen-plugin-new)"   # read the source (on NixOS the real script is in libexec/haseen/)
```

| Group | For | Example |
|---|---|---|
| `haseen plugin` | shell plugins | `haseen plugin new alice.uptime --kind bar-widget` |
| `haseen shell` | the running shell | `haseen shell ipc shell reload`, `haseen shell restart` |
| `haseen theme` | themes | `haseen theme list`, `haseen theme set tokyo-night` |
| `haseen hook` | event scripts | `haseen hook install theme-set ./notify.sh` |
| `haseen ai` | local AI | `haseen ai status`, `haseen ai models`, `haseen ai chat "hi"` |
| `haseen layer` | optional features (packages + config) | `haseen layer list`, `haseen layer apply ai --dry-run` |
| `haseen doctor` | what haseen detects, layer health, shell RSS | `haseen doctor` |

Prefer `--dry-run` first for anything that installs packages or touches
`/etc` (`haseen layer apply …`, `haseen secureboot …`), show the user the plan,
and run it for real only when they agree.

## Shell IPC

`haseen shell ipc <target> <function> [args]` talks to the running shell (or
to DankMaterialShell when the user switched to it with `haseen shell use dms`):

| Call | Effect |
|---|---|
| `shell reload` | reload the shell (needed after creating a plugin or editing plugin QML) |
| `shell plugins` | JSON: every plugin, valid/enabled/listed, roles, errors |
| `panel toggle <id>` / `panel close` | open or close a panel plugin |
| `launcher toggle`, `lock lock`, `notifications clear`, `notifications toggleDnd` | go to the plugin that `provides` that role |

## Workflow for any change

1. **Read first**: the user file you will edit, and the default it builds on
   (`$HASEEN_PATH/default/…`, a built-in plugin, `haseen <cmd> --help`).
2. **Back up** a user file before a non-trivial edit:
   `cp file file.bak.$(date +%s)`.
3. **Make the smallest change** in the user-owned location from the table above.
4. **Apply** it:
   - Hyprland: saving reloads it; then run `hyprctl reload` and check `hyprctl configerrors` (must be empty).
   - `shell.json`: applies live.
   - Plugin QML or a new plugin: `haseen shell ipc shell reload`.
   - Theme: `haseen theme set <name>`.
5. **Verify** (below). If it fails, fix it or restore the backup; never leave
   the user with a broken bar or config.

## Verification

- Hyprland: `hyprctl configerrors` prints nothing; `hyprctl binds -j | jq …`
  shows a new bind; `hyprctl monitors` shows a monitor change.
- Shell: `haseen shell ipc shell plugins | jq '.errors'` is `[]`, and your
  plugin shows `"valid": true, "enabled": true, "listed": true`.
- Plugin manifest: `haseen plugin validate <id>` prints `ok:`.
- Shell log: `journalctl --user -u haseen-shell -n 50` when it runs as the
  service, else `qs log -p "$HASEEN_PATH/shell" -t 50`. Look for `haseen:` and
  `WARN` lines naming your plugin.
- Look: a screenshot (`grim /tmp/check.png`) when the change is visual.
- Resources: `haseen doctor` prints the shell's RSS; the idle budget is under
  200 MiB. A plugin that adds more than ~10 MiB idle needs a reason.

## Troubleshooting

```bash
haseen doctor                         # machine facts, layer health, shell RSS
haseen layer status                   # health of applied layers
haseen shell restart                  # restart the shell (service or qs instance)
haseen plugin disable <id>            # take a broken plugin out of the bar
haseen shell recover status           # safe mode, the last failure and its suspect plugin
haseen shell recover safe-mode on     # built-in plugins only, live; `off` undoes it
hyprctl configerrors                  # Hyprland errors after an edit
```

A Hyprland user file that throws is caught: the error is printed and shown as
a notification, and the rest of the config still loads.

A shell that keeps failing opens a recovery terminal. It names the suspect
plugin and offers to disable it, safe mode, the last good `shell.json`
(`haseen shell recover restore-last`) or a plain restart.

## Decision framework

1. A `haseen` command does it? Use it (`haseen commands`).
2. A setting? Edit the user-owned file from the table above, never `$HASEEN_PATH`.
3. Something new on screen? Prefer a **panel** opened by a keybinding over an
   always-visible bar widget (haseen avoids clutter); follow `plugins.md`.
4. Colours or fonts? `theming.md`; a custom theme, never a patched stock one.
5. Automation on theme change, boot or update? `haseen hook install`.
6. Packages? Ask first; on CachyOS/Arch `sudo pacman -S …` in a terminal, on
   NixOS add them to the user's flake/configuration instead.

## Example requests

- "Add a bar widget showing uptime" → `plugins.md`: `haseen plugin new <user>.uptime --kind bar-widget`, edit, validate, enable, reload.
- "Move the clock to the right" → copy `bar.center`/`bar.right` from `haseen shell ipc shell plugins` or `$HASEEN_PATH/default/shell.json` into `~/.config/haseen/shell.json` and move `haseen.clock` (arrays replace, so write the whole section).
- "Use 24-hour time with seconds" → `~/.config/haseen/shell.json`: `"plugins": {"haseen.clock": {"settings": {"format": "HH:mm:ss"}}}`.
- "Hide the battery" → `haseen plugin disable haseen.battery`.
- "Dim the screen" / "keyboard light off" / "monitor brightness" → `haseen brightness set 30%`, `haseen brightness set kbd 0%`, `haseen brightness list` (ids; `ddc:DP-1` for a monitor). External monitors need `haseen setup ddc on` once. Sliders: `haseen plugin enable haseen.display`, then `haseen shell ipc panel toggle haseen.display` or Setup › Display.
- "Warn me earlier" / "suspend at 5%" → `~/.config/haseen/shell.json`: `"plugins": {"haseen.battery": {"settings": {"warnAt": 30, "criticalAt": 5, "criticalAction": "suspend"}}}` (`none` by default; `suspend`, `hibernate`, `poweroff` run 60 s after a critical notification with Cancel). The power panel (charge, profile, charge limit): click the bar battery or `haseen shell ipc panel toggle haseen.battery`.
- "Show the keyboard layout in the bar" → `haseen plugin enable haseen.kblayout` (EN/AR; no room with one layout; click switches). "Show Caps Lock on screen" → `~/.config/haseen/shell.json`: `"plugins": {"haseen.osd": {"settings": {"lockKeys": true}}}` (the default binds already call `haseen shell ipc osd lockkeys`); `mic` and `layout` OSD cards are on, set them to false to hide.
- "Show the player" / "skip this song" / "switch to Spotify" → right or middle click the bar's now-playing label, or `haseen shell ipc panel toggle haseen.media` (left click plays/pauses). "Show Spotify's album art" → `~/.config/haseen/shell.json`: `"plugins": {"haseen.media": {"settings": {"remoteArt": true}}}`; off by default because the https fetch tells the art server what is playing.
- "Switch windows / pick emoji / run menu commands / search the web from the launcher" → `haseen plugin enable haseen.windows` (`@`), `haseen.emojisearch` (`:`, Enter copies), `haseen.commands` (`/`, the menu's actions) or `haseen.websearch` (`?`, opens the browser; all off by default; Setup › Launcher Prefixes toggles them). Another search engine → `"plugins": {"haseen.websearch": {"settings": {"url": "https://www.startpage.com/do/search?q=%s"}}}` (http(s) only; `%s` is the encoded query). The empty launcher lists the prefixes in use.
- "Game mode" / "I'm presenting" / "Let me focus" → `haseen context game|present|focus`; `haseen context normal` puts every switch back as it was. "Game mode by itself for Steam games" → `haseen context auto-game on` (off by default; `set CLASS…` for other games). Do not flip `haseen toggle dnd|idle|…` by hand during a context: leaving it restores the record.
- "Three-finger swipe up opens the menu" → `haseen gestures apply --set '{"g3Up":"menu"}'` (the gestures panel in the bar does the same; `haseen gestures apply --help` lists every key). Never hand-edit `~/.local/state/haseen/toggles/hypr/gestures.lua`: every apply rewrites it.
- "Swipes stopped working" → `haseen gestures apply --print` says `Gestures are off` when `plugins."haseen.gestures".settings.enabled` is false (the first switch in the gestures panel; turning it off sends a notification). Turn them back on with `haseen gestures apply --set '{"enabled":true}'`.
- "Super+E opens the file manager" → `~/.config/hypr/bindings.lua` (see `hyprland.md`).
- "Smaller gaps" → `~/.config/hypr/local.lua` with `hl.config({ general = { gaps_out = 2 } })`.
- "Switch to gruvbox" → `haseen theme set gruvbox`.
- "Use the shield logo" → `haseen branding mark shield` (or `kufic`, the default, or `gate`): menu, About, screensaver and app icon follow at once; run `haseen plymouth set` for the boot splash. The bar logo `haseen.logo` (first in `bar.left`, on by default since plan 070) opens the menu on a click; put it back after removing it with `haseen bar add haseen.logo left --before haseen.workspaces`.
- "Add a widget to the bar" → `haseen bar add <id> <left|center|right> [--before <id>] [--dry-run]` (a widget not in the bar yet; turns it on if it was off; a widget already there is refused, use `haseen bar move`).
- "Default browser" → `haseen setup default browser zen|chromium|helium|firefox|chrome|brave`. haseen's default browsers, in order: Zen and Chromium (Flathub), Helium (`helium-browser-bin`, Chaotic-AUR; not on Flathub), all via `haseen install app <id>`; Zen is the one to make the system handler.
- "Cairn is missing from Helium" / "Update Cairn" → the shell layer installs Helium with Cairn, the extensions and bookmarks backup (plan 073). `haseen setup cairn status` says whether Helium has it, `haseen setup cairn` hands the pinned release over again, `haseen setup cairn update` moves to the latest release; Helium picks either up on its next start. Never delete `~/.config/net.imput.helium/External Extensions/bddeidknhkokohcgdkpgdmlppgfkblig.json`: Helium then uninstalls Cairn and its settings. Removing Cairn in chrome://extensions is the user's choice and haseen keeps it removed.
- "Make the accent orange in tokyo-night" → `~/.config/haseen/themes/tokyo-night/colors.toml` with `accent = "#ff9e64"`, then `haseen theme set tokyo-night`.
- "Make a theme from this wallpaper" → `haseen theme generate <image>` (matugen; `--scheme`, `--mode light`, `--no-apply`; needs `haseen install package matugen`). The panel is `haseen.themegen` (off by default: `haseen plugin enable haseen.themegen`). `haseen theme wallpaper <image>` is the extractor without matugen.
- "Get me a wallpaper from Wallhaven" / "make a theme from a Wallhaven picture" → `haseen wallhaven search [query] [--sort toplist|date_added|random|…]`, `haseen wallhaven get <id>` (saves `~/.config/haseen/backgrounds/wallhaven/<id>.<ext>`), `haseen wallhaven random`; then `haseen theme generate <that path>`. SFW only unless the user keeps an API key in `~/.config/haseen/wallhaven.key` (mode 600; never print it). The `haseen.themegen` panel has a Wallhaven source with search, sort chips and a paged grid.
- "Chat with my local model" → SUPER+A opens the AI panel; `ai.md` for endpoints.
