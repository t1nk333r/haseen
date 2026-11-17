# Plan 168: quiet hours in the notification pager

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Two string settings on the default-on pager, empty by
  default, so nothing changes until a user sets them. No timer and no process.
- **Depends on**: 019 (DND), 109 (interface language), the pager port
- **Category**: shell
- **Planned at**: 2026-11-14, from the owner (sent lucid's repository, "what
  could be good to take", then "go")
- **State**: PLANNED 2026-11-14

## Problem

haseen silences notifications only by hand: Do Not Disturb is the `dnd`
flag, which `haseen toggle dnd`, the bar bell and the pager's panel write
(`haseen.pager/Service.qml:150-164`, `Widget.qml:66-70`, `Panel.qml:141,286`).
Nothing turns it on for the night. Lucid (MIT, Sn3akyy1/lucid at d1bcf8a)
has quiet hours: a `from`–`to` window, checked against the clock, that
silences popups the same way DND does (`Notifs.qml:43-56`,
`Prefs.qml:2273-2282`).

The rest of what lucid's notification rules offer, haseen's pager already
has. It is the default daemon (first in `services`,
`share/haseen/default/shell.json:44`; haseen.notifications builds its server
only when the pager is absent, `haseen.notifications/Service.qml:45,145`):

- a critical notification gets through DND and snooze
  (`haseen.pager/Service.qml:1431`);
- `avoidFullscreen` (`off|all|steam`) keeps cards off a fullscreen window
  (`manifest.json:108-112`, `Service.qml:93-94`);
- cards stack and group per source, with per-source snooze
  (`manifest.json:6`, `Service.qml:44`).

## Decision

Two pager settings, the nightlight's shape (`haseen.nightlight/manifest.json:19-28`):

```json
"quietFrom":  {"type": "string", "default": "", "description": "Quiet hours start, HH:MM; empty = no quiet hours"},
"quietUntil": {"type": "string", "default": "", "description": "Quiet hours end, HH:MM; may be past midnight"}
```

- `quietNow` is `Logic.scheduled(minutes, quietFrom, quietUntil) === true`,
  reusing `haseen.nightlight/NightlightLogic.js:13-21` (which already
  handles a window past midnight and returns `null` for a bad or empty pair).
  The pager imports that file rather than copying it.
- The minutes come from a `SystemClock { precision: SystemClock.Minutes }`,
  as the lock and the clock do (`haseen.lock/LockView.qml:81-84`): no
  `Timer`, so architecture §6 is untouched.
- The mute gate becomes `doNotDisturb || quietNow ? "silenced" : …`
  (`Service.qml:1428`). Everything DND already does then applies unchanged:
  silenced cards go to history, critical ones and (with `codesBypassQuiet`)
  verification codes still show, Held Back lists what was swallowed.
- The panel's state line (`Panel.qml:111-125`) gains "Quiet hours until %1"
  between snooze and DND, and the bell shows silenced. The panel's DND button
  while quiet hours run says "Let everything through" and suspends quiet
  hours until their next start (a session property; it does not write the
  `dnd` flag).
- `haseen toggle dnd status` keeps reporting only the flag; quiet hours are
  the pager's own state, shown in its panel and its `state()` IPC.
- New strings go into `share/haseen/i18n/ar/shell.json` (`tests/test-i18n.sh`).

The reason for a new on-screen element (CLAUDE.md, "No visual clutter"):
none is added; one line of the existing panel changes its text.

## Rejected

- **Writing the `dnd` flag at the window's edges** (on at `quietFrom`, off at
  `quietUntil`): two writers of one flag, a manual "off" at 23:00 undone by
  nothing, and a manual "on" switched off at 07:00 the user never asked for.
  It also needs a process or a timer at each edge.
- **A minute `Timer` as lucid has** (`Notifs.qml:562-568`, every 20 s): a
  `SystemClock` gives the same minute without one.
- **Quiet hours in haseen.notifications as well**: it is the fallback, it is
  memory-only by test (`tests/test-surfaces.sh:182-183`), and nobody runs it
  by default. If the owner wants parity, it is the same three lines there.
- **A days-of-week mask**: not asked for; the settings can grow one later.

## Evidence (to collect)

- `tests/test-pager.sh` (covers `haseen.{notifications,pager}/**`, line 5):
  unit cases for the gate with `quietNow` true and false, critical and codes
  bypass, the state line text, and the manifest defaults being empty.
- `tests/test-nightlight*.sh` unchanged: the shared logic file is only read.
- A real-engine run of the pager with `quietFrom`/`quietUntil` spanning the
  current minute: `notify-send` goes to history, `notify-send -u critical`
  shows.
