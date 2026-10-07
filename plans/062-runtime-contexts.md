# Plan 062: runtime contexts (focus, game, present)

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (every context is left by restoring a record; the watcher is off by default)
- **Depends on**: 018 019 050
- **Category**: shell, ambient
- **Planned at**: 2026-10-07, owner request (idea from aphotic-hypr, GPL: idea only, none of its code or text)
- **State**: DONE 2026-10-07 (tests in `tests/test-context.sh`, `test-indicators.sh`, `test-keybinds.sh`; nested-session proof of every context, the restore and the game watcher; the physical click on the indicator is an owner check)

## Problem and decision

Gaming, presenting and focused work each need several of haseen's switches
flipped together, and flipped back afterwards. Doing it by hand loses track of
what was on before (the night light that should come back after a talk).

- `bin/haseen-context <normal|focus|game|present|status>` (default `status`).
  A context is a set of haseen's existing switches:

  | context | switches |
  |---|---|
  | focus | `dnd` on (notification popups and pager toasts held) |
  | game | `dnd` on, `idle-off` on, Hyprland animations, blur and shadows off |
  | present | `dnd`, `idle-off`, `screensaver-off` on; `nightlight` off (paused) |

  The bar is not touched by any context.
- The flags change through the toggles that own them
  (`haseen toggle dnd|idle|screensaver|nightlight on|off`), only where they
  differ, so the shell sees the same flag files it always reads.
  `HASEEN_NO_NOTIFY=1` keeps `haseen toggle screensaver` from sending its own
  notification; the context indicator is the feedback.
- **Exact restore.** Entering from normal writes
  `~/.local/state/haseen/context/saved` (each flag 0/1, `auto`, and for game
  the live `animations:enabled`, `decoration:blur:enabled`,
  `decoration:shadow:enabled` read with `hyprctl getoption -j`) before
  changing anything. Leaving sets every flag back to the record (do not
  disturb last) and evals the recorded Hyprland values, so a value set live
  (no config file holds it) comes back too. If Hyprland did not answer at entry,
  leaving falls back to `hyprctl reload`.
- Game also writes `toggles/hypr/context-game.lua`, which `default/hypr/init.lua`
  already loads, so a Hyprland reload during a game keeps the override (the
  user's own files still load after it, as for every toggle).
- **Nested contexts are replaced**, not stacked and not refused: switching
  from one context to another keeps the first record, undoes what the first
  changed that the second does not want (present → focus brings the night light
  back; leaving game restores Hyprland), then applies the second. focus → game →
  present → normal ends exactly where it began. The same context twice does
  nothing. A change made by hand during a context is undone on leaving: the
  record wins.
- A lock (`context/lock`, `flock`) serialises switches: the watcher and a menu
  click can race, and two records taken at once would restore the wrong state.
- The night light's schedule waits during present: `haseen.nightlight` skips a
  sunset/sunrise crossing while `Flags.context` is `present`, and applies it at
  the first 60 s check afterwards.
- **State for the shell.** The flag file `flags/context` holds the name while a
  context other than normal is active. `qs.Haseen.Flags` gained `context`
  (string, "" = normal); `FlagFile` keeps the file's first line in `value`.
  It is not in `Flags.names`: only the command writes it, because leaving must
  restore the record.
- **Indicator.** `haseen.indicators` has a `Context` entry (in the default
  list, last). It is `activeOnly`: shown only while a context is active, never
  in the hover strip. Its glyph names the context (focus `md-bullseye_arrow`,
  game `md-gamepad_variant`, present `md-presentation`), the tooltip says
  "Game context: back to normal", and a click runs `haseen context normal`.
  No new always-visible element: it takes no room in normal.
- **Menu.** Trigger > Context: Normal, Focus, Game, Present (✓ on the active
  one; `haseen context status` is a guard reader, asked once per menu build),
  and "Game for Fullscreen Steam Games" (`haseen context auto-game toggle`).
- **Key.** `SUPER + CTRL + M` opens Trigger > Context. M was free in haseen's
  `binds.lua`, in Omarchy's `SUPER + CTRL` row
  (`/usr/share/omarchy/default/hypr/bindings*`: A B C D E F H I K L N O P Q R S
  T V W X Z are taken) and in the owner's live binds (`hyprctl binds`). The
  keybind test checks it is bound once.
- **Auto game, off by default** (owner rule). `haseen context auto-game
  [status|on|off|toggle|set CLASS…]` writes
  `plugins."haseen.indicators".settings.gameClasses` and lists
  `haseen.indicators` in `services` while there are patterns (removed again
  when there are none; the merged default services are kept). `on` uses
  `steam_app_\d+`, the class Steam gives every game and the one
  `haseen.pager` already treats as a game. The watcher (`haseen.indicators`
  `Service.qml`) follows Hyprland events (`fullscreen`, `activewindowv2`,
  `closewindow`, `workspacev2`, `focusedmonv2`; no polling): a focused window
  in real fullscreen (mode bit 2) whose class matches a pattern as a whole
  runs `haseen context game --auto`; when that stops, `normal --auto`.
  `--auto` never replaces a context picked by hand and leaves only a game it
  entered itself; picking game by hand during an automatic one makes it the
  user's. `auto-game off` leaves an automatic game itself, since the watcher
  goes away with the setting.

## Rejected

- **Stacking contexts** (focus inside game, unwound in order): more state for
  no case the owner named; replacement against one record is predictable.
- **Refusing a second context**: makes the menu awkward (leave first, then
  enter); replacing is what a click on another row means.
- **Leaving game with `hyprctl reload`**: loses values set live and reruns the
  whole config; the recorded `getoption` values are exact.
- **Reusing `haseen toggle animations` for game**: its `no-animations.lua`
  belongs to the user's own toggle; a separate `context-game.lua` leaves the
  user's toggle untouched either way.
- **The watcher in the bar widget**: it runs once per screen, so every screen
  would switch; a service runs once.
- **A new `haseen.context` plugin**: a new built-in plugin starts off (owner
  rule), and the indicator was asked for in `haseen.indicators` anyway.

## Verification

- `tests/run.sh tests/test-context.sh` (85 tests): what each context sets; focus,
  game and present each entered and left from four starting flag sets, ending
  exactly where they began; mixed live Hyprland values restored as they were;
  present → focus → game → present → normal back to the first state; the same
  context twice; a hand change undone on leaving; `--auto` refused against a
  hand-picked context and leaving only its own game; dry runs change nothing
  and call no Hyprland; `auto-game on|set|toggle|off`, its services entry and
  that `off` leaves an automatic game; no screensaver notification.
- `tests/test-indicators.sh`: the Context entry's split (never in the strip),
  glyphs and tooltips per context, its click leaving the context, the game
  patterns (whole match, real fullscreen only, bad patterns dropped); in the
  real Quickshell engine, writing `flags/context` shows the cell and widens the
  widget, removing it gives the room back.
- `tests/test-keybinds.sh`: `SUPER + CTRL + M` opens the context menu; no key is
  bound twice.
- Nested Hyprland (`nest-launch.sh`, worktree shell, scratch HOME, guarded
  PATH), screenshots `grim -o IO` under `~/.cache/haseen-wt/Contexts/shots/`:
  - focus: the bullseye beside do-not-disturb and the night light;
  - game (replacing focus): the gamepad and the stay-awake cup;
    `hyprctl getoption` false for all three options, then after normal back to
    animations true, blur true, shadow false (set live before entering);
  - present: the presentation glyph, the night light gone; after normal it is back;
  - auto game: `foot --app-id steam_app_42` made fullscreen entered game with
    `auto=1`; leaving fullscreen went back to normal with the options restored;
    under a hand-picked focus, the same fullscreen left focus alone;
  - the Trigger > Context menu with ✓ on Present and on the auto-game row.

## Live apply

Install the tree (`./install.sh --tree-only`) and restart the shell (the
`Flags` singleton and the indicators service are new QML). The owner's bar
already lists `haseen.indicators`, so the Context cell appears with the first
context. `SUPER + CTRL + M` needs a Hyprland reload. Auto game stays off until
`haseen context auto-game on`.
