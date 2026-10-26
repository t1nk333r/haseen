# Plan 128: One screensaver at a time

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. Two extra reads of a file that may not exist, and a mirrored
  flag write. Nothing changes on a machine with no Omarchy screensaver
  plugin: both files stay absent, as before.
- **Depends on**: 019, 093
- **Category**: shell
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, "the screensaver is broken … it flashes
  and exits").

## Why

haseen's screensaver ends on a focus change — that is Omarchy's behaviour,
and the ttfx loop enforces it (`bin/haseen-screensaver --ttfx-run` calls
`ttfx_stop` as soon as the terminal is not the active window). Two
screensavers opening at the same moment therefore fight: the second one takes
focus and the first closes at once. Measured on luna, 2026-10-26, with the
koi screensaver (`io.github.ejuro.koi-screensaver`, enabled here) started
next to haseen's:

```
$ /tmp/count-windows.sh            # org.haseen.screensaver / org.omarchy.screensaver
haseen=1 koi=0
$ /tmp/koi-dispatch.sh             # the koi's own kitty on its own class
$ sleep 1; /tmp/count-windows.sh
haseen=0 koi=0
```

The screen flashes and nothing stays. That is what the owner reported.

The koi does the right thing by Omarchy's rules: it switches Omarchy's own
screensaver off while it holds the slot, by touching
`~/.local/state/omarchy/toggles/screensaver-off`
(`bin/koi-screensaver`, `claim`). haseen never read that file — plan 093 moved
haseen's own toggles to `~/.local/state/haseen/flags/`, and
`omarchy-toggle` maps the name there — so a plugin's claim was invisible to
the shell, which started haseen's screensaver underneath it.

## What changed

- **`share/haseen/shell/Haseen/Flags.qml`** — `screensaverOff` is true when
  either haseen's `flags/screensaver-off` or Omarchy's
  `omarchy/toggles/screensaver-off` exists. `FlagFile` takes a directory, so
  the second store is watched exactly like the first (inotify, no polling),
  and the one-off `mkdir -p` creates both parents so the watch can be set
  before a plugin ever claims the file. `share/haseen/shell/Haseen/Paths.qml`
  gains `omarchyState` (`$XDG_STATE_HOME/omarchy`).
- **`bin/haseen-toggle-screensaver`** — keeps Omarchy's file in step: off
  creates both, on removes both. A plugin that claimed the file sees the
  change and steps aside; one still claiming it re-claims, so the plugin stays
  the screensaver until its own switch says otherwise.
- **`bin/haseen-screensaver`** and **`share/haseen/omarchy/bin/omarchy-launch-screensaver`**
  — "off" now means either file, so the CLI and Omarchy's command refuse on a
  plugin's claim as well. `--force` still shows haseen's screensaver.

## Evidence

- `tests/test-ambient.sh` → 252/252: the toggle mirrors into Omarchy's store,
  turning it on clears it, and a claim with no haseen flag turns
  `haseen screensaver` off while `--force` still starts it.
- `tests/test-omarchy-launch.sh` → 196/196.
- The clash above, and the same two windows after the change on a machine
  with the plugin enabled: only the plugin's screensaver opens.

## What this does not do

- It does not make haseen's screensaver survive a focus change; ending on any
  input is the point of it.
- It does not choose between the two: a plugin holding the claim is the
  screensaver. Turning `haseen toggle screensaver on` clears the file, but a
  plugin whose own switch is on re-claims it at once — disable the plugin's
  screensaver to get haseen's back.

## Rejected options

- **Refuse to open while any `org.omarchy.screensaver` window exists.** That
  is a `hyprctl clients` call on every show and a race with the plugin's own
  open; the flag is the signal the plugin already publishes for this.
- **Have haseen own the Omarchy toggle store** (move the koi's file). Plan 093
  deliberately moved haseen's own flags out of it; writing haseen's flags back
  in would undo that and collide with Omarchy tools that still use the store.
- **Kill the other screensaver's windows when haseen's starts.** Two programs
  closing each other's windows is a worse failure mode than one yielding, and
  the plugin also has to stop its own launcher.
