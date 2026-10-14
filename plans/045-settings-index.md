# Plan 045: The settings index — one map over six stores

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (reads everything, owns nothing)
- **Depends on**: 005 019 033
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (ranked gap: "fold the touch-file/state toggles the 131 commands mutate into the actual settings document")
- **State**: DONE 2026-10-05; plugin rows and the `takes` column 2026-10-08; bar rows routed through the bar commands 2026-10-13

## Problem

"What is my desktop set to?" had no answer. `share/haseen/default/shell.json`
has four top-level keys (`bar`, `frame`, `plugins`, `services`), while the
commands keep settings in five other places: flag files under
`~/.local/state/haseen/flags/`, Lua toggle files under
`~/.local/state/haseen/toggles/hypr/`, other state files (`active-shell`,
`current/theme.name`, `powerprofile/`), one-value files under
`~/.config/haseen` (`font`), and the uwsm env file for the default
browser/terminal/editor/agent. `haseen commands` lists verbs, not values.

## Decision

**Index the stores, do not move them.** `share/haseen/lib/settings.sh` is a
table of `key | store | path | value | setter | takes`. `haseen settings list`
prints it (or `--json`); `haseen settings set <key> [value]` looks the key up
and `exec`s the command that already owns it, adding `--dry-run` when given
(`bin/haseen-settings-set:77`). The index owns no state and duplicates no
write path.

The owner asked to fold the touch-file and state toggles **into**
`shell.json`. That was rejected, because each store exists for a reason the
fold would break:

- **Flags** (`dnd`, `idle-off`, `screensaver-off`, `nightlight`, `recording`)
  are session state. Folded in, a CLI toggle would rewrite the file the user
  hand-edits, several times an hour, and the shell watches each flag file on
  its own through `qs.Haseen.Flags` (`docs/architecture.md` §5.3).
- **Hyprland toggles** are Lua because Hyprland reads Lua. As JSON they would
  need a generator and a second source of truth.
- **The env file** is read by uwsm before anything could read `shell.json`.

The table:

- **Values** are read in the user's terms. A shell.json value comes from the
  user's file, else the shipped default; `false` and `0` are values
  (`select(. != null)`, `settings.sh:65`), objects print as compact JSON, and
  a string with a control character prints as its JSON form so a tab cannot
  shift the row. A plugin setting falls back to its manifest's default. The
  inverted stores read as the feature: `idle-off` present means idle is off,
  `no-gaps.lua` present means gaps are off. A user `shell.json` that does not
  parse is named on stderr, because the values listed are then the defaults.
- **`takes`** says what `settings set` passes the owner: `value` (as typed),
  `on-off`, `inverted` (on/off swapped before the owner runs: only `gaps`,
  because `haseen toggle gaps on` is the no-gaps mode, `settings.sh:176`) or
  `none`. A word other than on/off is refused for the on/off rows, and a
  value is refused for a `none` row with the command to run instead.
- **Setters honour `--dry-run`.** `bar.position` and `bar.transparent` route
  to `haseen bar position` and `haseen bar transparent`, which save
  `shell.json` and then call the running shell, and under `--dry-run` only
  print both steps (`bin/haseen-bar-position:46`,
  `bin/haseen-bar-transparent:59`). `haseen shell ipc` has no dry run, so it
  is never a setter. `bar.transparent` lists as on/off, the words its owner
  takes.
- **Rows**: theme, `font.mono`, active shell, `bar.position`, `bar.height`,
  `bar.transparent`, `frame.enabled`, `frame.thickness`, `frame.radius`, the
  flags, the three Hyprland toggles, the four defaults, and the plugin
  settings a user looks for: `haseen.battery.{warnAt,criticalAt,criticalAction}`
  (plan 075), `haseen.osd.lockKeys` (079), `haseen.idle.{suspendAfter,onBattery}`
  (082), `haseen.clock.showDayName` (085), `haseen.clipboard.preview` (042)
  and `haseen.screensaver.style`, whose setter is `haseen screensaver style`.
  Every other plugin key stays in its manifest (`haseen plugin info <id>`).
  The `gestures` flag is written by a hardware quirk, not the user, and is
  not listed.
- `bar.height`, `frame.*`, the plugin rows other than the screensaver style,
  and `recording` (one command starts and stops it) are `none`: bare, they
  open `shell.json` or run the command. `haseen plugin settings` takes JSON
  on stdin, so it cannot take an appended value.

## Rejected

- **A settings GUI.** `docs/architecture.md` §1 requirement 3 (no visual
  clutter) and the CLI-plus-menu posture rule it out. DMS ships ~600 keys and
  a 20-page hub.
- **A seventh store** (`~/.config/haseen/settings.json`) mirroring the others:
  a cache to keep in sync with what it caches.
- **Writing values directly** in `settings set`: it would duplicate each
  owner's dry-run handling, live reload and validation.
- **`haseen shell ipc bar …` as the bar setters**: it has no `--dry-run` and
  passed the flag on to the live shell, so `settings set bar.position bottom
  --dry-run` moved the bar.

## Verification

- `tests/test-settings.sh` (203 checks): every row complete, keys unique,
  every store one of the six, every `takes` known, every setter a `haseen`
  command; values from the real stores including both inversions, the user's
  `shell.json` over the default, `false` as a value, manifest defaults, an
  object as compact JSON, a tab kept inside its value; routing
  (`settings set nightlight --dry-run` prints the flag command's own plan);
  a `settings set <key> <value> --dry-run` sweep over every listed key that
  runs no stubbed binary (`qs`, `hyprctl`, `systemctl`, `notify-send`) and
  changes nothing under `$HOME` (with the old `haseen shell ipc` setters it
  failed on `STUB-CALLED: qs … ipc call bar position left --dry-run`); a
  set→list round trip for the seven toggles and `bar.transparent`;
  `settings set bar.position left` landing in `shell.json`; unknown key →
  exit 1, missing key → exit 2.

## Open

`bar.height` and `frame.*` open `shell.json` in `$EDITOR` because no command
owns those keys. A real setter needs a `shell.json` write path with the lock
in `share/haseen/shell/lib/plugin.sh`, as `haseen bar position` has.

## Execution record

`share/haseen/lib/settings.sh`, `bin/haseen-settings-list`,
`bin/haseen-settings-set`, `tests/test-settings.sh`.
