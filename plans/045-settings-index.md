# Plan 045: The settings index — one map over six stores

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (reads everything, owns nothing)
- **Depends on**: 005 019 033
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (ranked gap: "fold the touch-file/state toggles the 131 commands mutate into the actual settings document")
- **State**: DONE 2026-10-05

## Problem

"What is my desktop set to?" had no answer. `share/haseen/default/shell.json`
has four top-level keys (`bar`, `frame`, `plugins`, `services`), while the
commands mutate settings in four other places: flag files under
`~/.local/state/haseen/flags/`, Lua toggle files under
`~/.local/state/haseen/toggles/hypr/`, other state files (`active-shell`,
`current/theme.name`, `powerprofile/`), and the uwsm env file for the default
browser/terminal/editor/agent. Nothing lists them; `haseen commands` lists
*verbs*, not values.

## Decision

**Index them, do not move them.** `share/haseen/lib/settings.sh` is a table of
`key | store | path | value | setter`; `haseen settings list` prints it (or
`--json`), and `haseen settings set <key> [value]` looks the key up and `exec`s
the command that already owns it. The new code owns no state and duplicates no
write path, so there is still exactly one implementation of every change.

The owner's framing was to fold the touch-file and state toggles **into**
`shell.json`. That was rejected, with reasons, because each store exists for a
reason the fold would break:

- **Flags** (`dnd`, `idle-off`, `screensaver-off`, `nightlight`, `recording`)
  are *session state*, not configuration. Folding them in would make a CLI
  toggle rewrite a file the user hand-edits — losing its shape and comments —
  several times an hour, and the shell watches each flag file individually
  through `qs.Haseen.Flags` (`docs/architecture.md` §5.3).
- **Hyprland toggles** are Lua because Hyprland reads Lua. Stored as JSON they
  would have to be re-emitted as Lua on every change, adding a generator and a
  second source of truth for gaps, animations and workspace layout.
- **The env file** is read by uwsm before the session starts, i.e. before
  anything could read `shell.json`.

What was genuinely missing was discoverability, and that is what landed.

## Rejected

- **A settings GUI.** `docs/architecture.md` §1 requirement 3 (no visual
  clutter) and the existing posture — CLI plus `menu.jsonc` — rule it out. DMS
  ships ~600 keys and a 20-page hub; haseen deliberately does not.
- **A sixth store** (`~/.config/haseen/settings.json`) that mirrors the others:
  a cache to keep in sync with the thing it caches.
- **Writing values directly** in `settings set` instead of routing: it would
  duplicate the dry-run handling, the live reloads and the validation each
  owning command already does.

## Verification

- `tests/test-settings.sh` (31): every row complete (no empty tab field — bash
  collapses runs of whitespace delimiters, so an empty value would shift every
  later column), keys unique, every store one of the five, every setter a
  `haseen` command; values read from the real stores, including the two
  inversions that are easy to get backwards (`idle-off` means idle is *on*
  elsewhere, `no-gaps.lua` means gaps are *off*); the user's `shell.json`
  beating the shipped default; routing proven by `settings set nightlight
  --dry-run` producing the flag command's own plan; unknown key → exit 1,
  missing key → exit 2.
- Smoke in a scratch home: the table above rendered with real values, `--json`
  parsed by `jq`, and `settings set theme tokyo-night --dry-run` reaching
  `haseen theme set`.

## Open

`haseen settings set` for the `shell.json`-backed rows opens the file in
`$EDITOR` rather than editing the key, because no command owns those keys today.
Giving `bar.height` and `frame.*` a real setter means a `shell.json` write path
with the lock from `share/haseen/shell/lib/plugin.sh`; it is a separate change.

## Addendum: landing on main (2026-10-08)

Re-checked against main's plans 075–085 before landing:

- **Six stores, not five.** `font.mono` already read `~/.config/haseen/font`,
  which is none of the five; it was labelled `file` and the test allowed it.
  It is now the documented `config` store (other one-value files under
  `~/.config/haseen`, each owned by one command).
- **A bug in the shell.json read.** `jq '… // empty'` treats `false` as absent,
  so a user's `"frame": {"enabled": false}` showed the shipped `true`. Values
  are now picked with `select(. != null)`, and objects print as compact JSON.
- **Plugin settings from 075–085**, read from the user's `shell.json`, else the
  plugin manifest's default: `haseen.battery.{warnAt,criticalAt,criticalAction}`
  (075), `haseen.osd.lockKeys` (079), `haseen.idle.{suspendAfter,onBattery}`
  (082), `haseen.clock.showDayName` (085), plus `haseen.clipboard.preview` (042)
  and `haseen.screensaver.style`, whose setter is `haseen screensaver style`.
  The others open `shell.json` (`haseen plugin settings` takes JSON on stdin,
  so it cannot take a value appended). Every other plugin key stays in its
  manifest (`haseen plugin info <id>`); the built-in plugins 080/081 add are
  enabled per plugin, not through this index.
- The `gestures` flag (written by a hardware quirk) is not a user setting and
  stays out.
- `tests/test-settings.sh`: 40 checks.

## Addendum: landing review (2026-10-08)

- **`settings set gaps off` turned the gaps on.** The row reports gaps in the
  user's terms, but `haseen toggle gaps` names the no-gaps mode (its `on`
  removes them). Each row now carries a sixth column, `takes`: `value`
  (appended as is), `on-off`, `inverted` (on/off swapped before the owner
  runs; only `gaps`) or `none`. `animations`, `idle`, `screensaver`, `dnd`,
  `nightlight` and `one-window-ratio` already agreed with their commands, and
  a set→list round trip for all seven now pins that. A word other than on/off
  is refused for those rows.
- **Editor-owned keys exited 2 with a value.** `bar.height`, `frame.*`, the
  plugin rows that open `shell.json`, and `recording` (one command starts and
  stops it) are `none`: a value is refused with the command to run instead;
  bare, they still open the file.
- **A broken user `shell.json` was listed as the shipped defaults** without a
  word. The list now warns on stderr that the values are the defaults.
- **A tab in a value shifted the row** (the setter column then held the tail
  of the value). A string with a control character prints as its JSON form,
  and `_settings_row` escapes a tab or newline from any other store.
- `tests/test-settings.sh`: 104 checks.

## Execution record

`share/haseen/lib/settings.sh`, `bin/haseen-settings-list`,
`bin/haseen-settings-set`, `tests/test-settings.sh`.
