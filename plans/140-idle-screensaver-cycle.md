# Plan 140: The screensaver's own window is not input

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. Without a screensaver monitor (screensaver off, no
  provider, idle-off) the monitors and their keys are what they were. The
  cycle changes only what happens between the screensaver starting and the
  next input.
- **Depends on**: 019 (haseen.idle, haseen.screensaver), 082 (suspend,
  battery timeouts), 084 (manual screen off), 128 (one screensaver at a time)
- **Category**: shell
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27 (`tests/test-idle.sh` 108/108,
  `tests/test-ambient.sh` 252/252)

## Problem

Owner, 2026-10-27:

> screensavers still fails on IO

Plan 128 fixed one cause of "it flashes and exits" on luna: a second
screensaver plugin (the koi) taking focus. IO has no other screensaver
plugin. Its flags are clear (`~/.local/state/haseen/flags/` holds only
`gestures`; `~/.local/state/omarchy/toggles/` has no `screensaver-off`),
`ttfx` and `foot` are installed, and the shell's `TERMINAL` is `foot`.

Started by hand, it works. `haseen screensaver` on IO mapped
`org.haseen.screensaver` fullscreen on `special:screensaver-eDP-1` within
0.3 s. The terminal held focus for the 3 s it was watched, until
`haseen-screensaver --stop` closed it.

Started by idle, it does not stay. The difference is haseen.idle. Its
screensaver monitor going back to active dismissed the screensaver
(`IdleLogic.js` `actions("screensaver", false)` was
`["screensaver.dismiss"]`). Hyprland 0.56.2 reports that, with nobody at the
machine, as soon as the screensaver's terminal maps:

- `CInputManager::recheckIdleInhibitorStatus`
  (`src/managers/input/IdleInhibitor.cpp:35`, v0.56.2, efb5099) always ends
  in `PROTO::idle->setInhibit(true|false)`.
- `CIdleNotifyProtocol::setInhibit` (`src/protocols/IdleNotify.cpp:118`)
  calls `update()` on every notification that obeys inhibitors, whether the
  state changed or not. `update(0)` (`IdleNotify.cpp:38`) then sends
  `resumed` and restarts the count, also when nothing inhibits.
- The re-check runs:
  - on every window map and unmap (`src/desktop/view/Window.cpp:2494`,
    `:2704`);
  - on every focus change (`src/desktop/state/FocusState.cpp:146`, `:214`);
  - on every fullscreen change (`src/managers/fullscreen/FullscreenController.cpp:504`).

  The screensaver's terminal does all three.

Measured on IO, 2026-10-27, with a throwaway `qs` instance in its own
runtime directory and two 3 s monitors. Nothing was shown on screen:

| ms (epoch)    | event                                                         |
|---------------|---------------------------------------------------------------|
| 1793096142886 | both monitors idle                                            |
| 1793096143341 | a window maps on a hidden special workspace (`… silent`)      |
| 1793096143383 | the monitor that respects inhibitors goes **active** (42 ms)  |
| 1793096146801 | the input-only monitor goes active (the owner's next input)   |

haseen.idle's monitors all respect inhibitors by default, so at
`screensaverAfter` the chain ran: start, map, `resumed`, dismiss,
`haseen-screensaver --stop`. Nothing logs it: Hyprland's log has no line
for the exec or the class, and the shell logged no warning.

The same re-check restarts the lock and dpms counts. Every flash restarts all
three, and the screensaver monitor fires again after 150 s, before the 300 s
lock count can finish. So with the ttfx style, idle alone would never lock IO
or turn its display off. This follows from the code and the probe; it was
not observed on IO.

Omarchy met the same thing. Its idle service says so
(`shell/plugins/services/idle/Service.qml:177`, omarchy 03ff1ef: "Starting the
screensaver can make the compositor report activity"). It counts only up to
the first deadline with the compositor, and keeps the rest with shell timers
that only the screensaver's windows closing can cancel.

The same chain, end to end: the harness described under "What changed",
run on IO with `main`'s `Service.qml` and `IdleLogic.js`, logged
`screensaver.start` at 1793096833768 and `screensaver.dismiss` at
1793096833834, 66 ms later, when its window mapped.

## What changed

A **screensaver cycle** in haseen.idle, from the screensaver monitor going
idle until the next input (`share/haseen/shell/plugins/haseen.idle/`):

- **`IdleLogic.actions`**:
  - The screensaver monitor going idle now also returns `cycle.start`.
  - Its going active returns nothing. The screensaver ends itself on input:
    keys and clicks, its 1 s input-only monitor, and in ttfx a focus change.
  - In a cycle, no monitor's going active does anything, unless that monitor
    is being removed.
  - The new `presence` monitor going active returns `cycle.end`.
- **`IdleLogic.cycleEnd`**: dismisses the screensaver, and sends `dpms.on`
  for displays the service turned off. The monitors' own active edges were
  dropped during the cycle, so this does what they would have done.
- **`IdleLogic.monitors(t, respect, cycle)`**: in a cycle, each lock and dpms
  monitor still counting gets an input-only key for the time it has left
  (`lock:150:0`, `dpms:180:0` with the defaults). A 1 s input-only
  `presence:1:0` is added.
  - Input-only notifications ignore `setInhibit` (`IdleNotify.cpp:121`).
    The lock and dpms still go at `lockAfter` and `dpmsAfter`, through the
    map, and through the unmap when the lock closes the screensaver.
  - The keys change, so each monitor is replaced by a new one (plan 019's
    rule: never reconfigure in place), and its idle state is not undone.
  - A monitor already past the screensaver keeps its key, for example
    `dpmsAfter` below `screensaverAfter`. Suspend keeps its key and keeps
    honouring inhibitors.
- **`Service.qml`**:
  - `_cycle` holds the cycle, and `monitorKeys` passes it to the model.
  - `cycle.end` runs through `Qt.callLater`, because ending the cycle
    destroys the presence monitor whose signal is being handled.
  - The cycle also ends when the timeouts lose their screensaver (idle-off,
    screensaver-off, the role gone).
  - A replaced idle monitor's entry in `_idle` is cleared.
  - `screensaverStartedThisCycle`, which Omarchy plugins read through
    `Compat/Runtime.qml`, is now "a cycle is running and the lock has not
    come". It was the screensaver monitor's own state, which Hyprland resets
    at once.

Measured on IO with this `Service.qml` and `IdleLogic.js`, against stub
`Plugins`/`Flags`/`Paths` singletons. Their screensaver "start" maps a 2 s
window on a hidden special workspace; their lock only logs; dpms is off
(`screensaverAfter` 3, `lockAfter` 8, `dpmsAfter` 0):

```
CYCLE 1793096769823 keys ["screensaver:3:1","lock:8:1"] cycle=false
CYCLE 1793096772823 screensaver.start
CYCLE 1793096772823 keys ["screensaver:3:1","lock:5:0","presence:1:0"] cycle=true
CYCLE 1793096777826 screensaver.dismiss
CYCLE 1793096777826 lock.lock
```

- The hidden window mapped and closed in between, and neither ended the
  cycle.
- The lock came 8.003 s after the shell started.
- A second `screensaver.start` 16 ms later is the screensaver monitor counting
  again after the window closed. haseen.screensaver ignores it while it shows
  and while the session is locked (`show()`).

## What this does not do

- **A video that starts during the screensaver** does not hold off the lock
  or the dpms off. Their counts are input-only for that stretch. Omarchy's
  timers do the same. A video already playing still keeps the screensaver
  from starting, so no cycle begins.
- **Suspend** still honours inhibitors. Its count restarts at each of those
  window changes, the last one when the screensaver closes for the lock, so
  `suspendAfter` (off by default) can come up to `lockAfter` late.
- **Outside a screensaver cycle** a window mapping still restarts the
  inhibitor-aware counts. With the displays off, an application opening a
  window can still turn them back on. That is Hyprland's behaviour; it is
  not reproduced here, and nobody reported it.
- **A return within the first second.** The presence monitor reports a return
  only after one quiet second (ext-idle-notify sends `resumed` only after
  `idled`). Someone typing straight on keeps the cycle until their first
  pause, with the lock counting input only. haseen.screensaver's own
  monitor has the same first second.

## Rejected options

- **Drop the dismissal and nothing else.** The screensaver stays, but the lock
  and dpms counts restart when its window maps and when it closes for the
  lock. The lock would come at `screensaverAfter + lockAfter`, 450 s with
  the defaults.
- **Shell timers for the lock and dpms after the screensaver** (Omarchy's
  way). These work, but they put the counting in the shell; plan 019 left it
  to the compositor. Input-only monitors keep it there and reset on real
  input with no extra code.
- **Monitors that never respect inhibitors.** The screensaver would start
  over a playing video, which `respectInhibitors` exists to prevent.
- **Shortened monitors that respect inhibitors in the cycle.** The re-check
  on the lock's unmap would restart them, and dpms would come late again.

## Tests

`tests/test-idle.sh` (the IdleLogic block):
- **The decision table in a cycle**:
  - presence idle arms it;
  - presence active ends the cycle;
  - a dpms monitor that respects inhibitors going active does nothing;
  - removal still undoes;
  - the lock and suspend still fire.
- **`cycleEnd`** with and without displays off.
- **Cycle keys** with the defaults, with `respectInhibitors` off and a
  suspend, with dpms before the screensaver, with screensaver-off, with
  idle-off, and without lock or dpms. `presence` parses back as input-only.
  A cycle key replaces its monitor; presence is removed.
- **The service model**, extended with Hyprland's re-check (`map`: every
  idle monitor that respects inhibitors goes active):
  - the screensaver's own map dismisses nothing;
  - the lock and dpms keep their time through two maps;
  - input ends the cycle;
  - returning after the lock and dpms wakes the displays once, and the next
    idle starts a new cycle;
  - displays already off stay off through the map, then wake on input;
  - Stay Awake during a cycle wakes them and drops the screensaver;
  - a second screensaver idle in a cycle starts no second cycle.
- **Plan 084's manual screen off/on cases**, rerun through the new model
  with their expected sequences updated for the cycle.

`tests/test-ambient.sh`: the screensaver monitor going idle starts the
cycle; going active alone dismisses nothing.
