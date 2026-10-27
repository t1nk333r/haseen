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
- **State**: DONE 2026-10-27 (`tests/test-idle.sh` 127/127,
  `tests/test-ambient.sh` 252/252). Round 1 of the review (DeepSeek V4.1
  Flash) asked for changes, and rounds 2 to 4 approved; all four are in
  "Review" below.

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
  calls `update()` on every notification that obeys inhibitors (`:121`),
  whether the state changed or not. `update()` (`:53`) is `update(0)`
  (`:38`), which sends `resumed` (`reset()`, `:65`) and re-arms the full
  timeout (`:46-48`), also when nothing inhibits.
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
  - The screensaver monitor going idle now also returns `cycle.start`,
    outside a cycle only. In one (its monitor replaced by a new
    `screensaverAfter`), a second start would take the cycle's timeouts
    again and restart the lock's count.
  - Its going active returns nothing. The screensaver ends itself on input:
    keys and clicks, its 1 s input-only monitor, and in ttfx a focus change.
  - In a cycle, no monitor's going active does anything, unless that monitor
    is being removed.
  - The new `presence` monitor going active returns `cycle.end`. Removed
    (the cycle ended without input, the plugin unloading), it returns
    nothing: that is nobody coming back.
- **`IdleLogic.cycleEnd`**: dismisses the screensaver. When input ended the
  cycle it also sends `dpms.on` for displays the service turned off. The
  monitors' own active edges were dropped during the cycle, so this does
  what they would have done. A cycle that ends without input (the
  screensaver monitor dropped: screensaver-off, the role gone, a plug event
  whose `lockAfter` is at or before `screensaverAfter`) leaves the displays
  off, as plan 082 does for a replaced monitor. idle-off removes the dpms
  monitor, and that removal still turns them on.
- **`IdleLogic.monitors(t, respect, cycle)`**: `cycle` is the timeouts in
  force when the cycle started. In a cycle, each lock and dpms monitor still
  counting then gets an input-only key for the time it had left
  (`lock:150:0`, `dpms:180:0` with the defaults; at least 1 s, so a
  `dpmsAfter` equal to `screensaverAfter` gives `dpms:1:0`). A 1 s
  input-only `presence:1:0` is added.
  - Input-only notifications are created with `obeyInhibitors` false
    (`get_input_idle_notification`, `IdleNotify.cpp:89`) and skipped by
    `setInhibit` (`:121`). The lock and dpms still go at `lockAfter` and
    `dpmsAfter`, through the map, and through the unmap when the lock
    closes the screensaver.
  - The time left comes from the cycle's timeouts, not the current ones. A
    settings change or a plug event during the cycle leaves those keys, so
    the monitors keep counting. A current value of 0 still removes a
    monitor, and one turned on during the cycle counts its full time on
    input only.
  - The keys change, so each monitor is replaced by a new one (plan 019's
    rule: never reconfigure in place), and its idle state is not undone.
  - A monitor already past the screensaver keeps its key, for example
    `dpmsAfter` below `screensaverAfter`. Suspend keeps its key and keeps
    honouring inhibitors.
- **`Service.qml`**:
  - `_cycle` holds the cycle, `_cycleTimeouts` a copy of the timeouts taken
    when it started, and `monitorKeys` passes that copy to the model.
  - `cycle.end` runs through `Qt.callLater`, because ending the cycle
    destroys the presence monitor whose signal is being handled; it ends the
    cycle as input (`_endCycle(true)`).
  - The cycle also ends, without input, when the timeouts lose their
    screensaver (idle-off, screensaver-off, the role gone, a plug event).
  - A replaced idle monitor's entry in `_idle` is cleared.
  - `screensaverStartedThisCycle`, which Omarchy plugins read through
    `Compat/Runtime.qml`, is now "a cycle is running and the lock has not
    come". It was the screensaver monitor's own state, which Hyprland resets
    at once.

Measured on IO with round 1's `Service.qml` and `IdleLogic.js` (c41bb5f;
the review's fixes do not change this path), against stub
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

- **A new `lockAfter` or `dpmsAfter` during a cycle**, for a monitor
  already counting, applies from the next cycle. The running cycle keeps the
  times it started with, so a lowered `lockAfter` (unplugging, with a
  shorter one on battery) does not lock sooner, and a raised one does not
  lock later. Before this plan, the new value counted again from the change,
  which could be later than either. A monitor that was 0 when the cycle
  started and is turned on during it counts its full current time from
  then. One set to 0 and back during the cycle starts again from the
  change, with its cycle key's time (`lockAfter` 300 to 0 and back, at the
  defaults, counts 150 s from the change).
- **A cycle that ends without input with the displays off** replaces the
  dpms monitor with one that was never idle. The input that brings someone
  back turns the displays on through Hyprland (`key_press_enables_dpms`,
  `share/haseen/default/hypr/input.lua:64-65`), but no monitor reports it,
  so the service still counts them as off. The effect is a `dpms.on` when
  a later cycle ends with input. That is normally redundant, because
  Hyprland has just turned the displays on for the same input. If
  something else had them off at that moment (`haseen screen off --delay
  0`, or a `dpms off` from outside haseen), it turns them on, against
  plan 084's rule that the service undoes only its own off. haseen's own
  entry points (the menu's Screen off, the battery panel) use the 1 s
  default delay, so their off lands after that `dpms.on`. Every other
  `dpms.on` needs a dpms monitor that went idle first, and that edge sets
  the flag itself. Waking the displays at the cycle's end instead would
  turn them on for a plug event in an empty room, which is worse.
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
- **`cycleEnd`** without displays off, with them off and no input, with
  them off and input (the only case that sends `dpms.on`), and with input
  alone.
- **Cycle keys** with the defaults, with `respectInhibitors` off and a
  suspend, with dpms before the screensaver, with screensaver-off, with
  idle-off, without lock or dpms, and with `dpmsAfter` equal to
  `screensaverAfter`. `presence` parses back as input-only. A cycle key
  replaces its monitor; presence is removed.
- **The cycle's timeouts**: a new `screensaverAfter`, `lockAfter` or
  `dpmsAfter` leaves the lock and dpms keys; 0 removes a monitor; one turned
  on during the cycle counts on input only; without a screensaver there is
  no cycle.
- **The service model**, extended with Hyprland's re-check (`map`: every
  idle monitor that respects inhibitors goes active):
  - the screensaver's own map dismisses nothing;
  - the lock and dpms keep their time through two maps;
  - input ends the cycle;
  - returning after the lock and dpms wakes the displays once, and the next
    idle starts a new cycle;
  - displays already off stay off through the map, then wake on input;
  - Stay Awake during a cycle wakes them and drops the screensaver;
  - a second screensaver idle in a cycle starts no second cycle;
  - a settings change mid-cycle keeps the lock and dpms keys;
  - the screensaver monitor dropped with the displays off leaves them off;
  - `dpmsAfter` equal to `screensaverAfter` gives a 1 s input-only dpms
    monitor that a map does not restart.

  The model follows the service's order, which the next block measures: a
  removed monitor's `Component.onDestruction` runs at once with the new
  keys, `onTimeoutsChanged` runs before the keys change, and `Qt.callLater`
  runs after the event. That order is Qt 6's behaviour, not a documented
  guarantee, and the service does not depend on it (another order only
  reorders idempotent dispatches), so a Qt that changes it changes these
  expectations, not the service.
- **The service itself**: `Service.qml` under Qt's `qml`, on stand-ins for
  Quickshell (`IdleMonitor` with a settable `isIdle`, a `ScriptModel` that
  keeps unchanged rows) and `qs.Haseen`, with every role call and dispatch
  in one log. It covers:
  - a cycle and its keys;
  - the map;
  - a settings change mid-cycle (the same lock and dpms monitor objects
    afterwards);
  - the lock and dpms, and `screensaverStartedThisCycle` ending with the
    lock;
  - screensaver-off mid-cycle (no `dpms on`);
  - input (the end comes after the handler, then `dpms on`);
  - Stay Awake;
  - unloading mid-cycle (nothing sent);
  - no QML warnings.

  Against the round-1 `IdleLogic.js` and `Service.qml`, four of these fail:
  the same monitors, the keys after the change, the lock that follows, and
  the drop without input.
- **Plan 084's manual screen off/on cases**, rerun through the new model
  with their expected sequences updated for the cycle.

`tests/test-ambient.sh`: the screensaver monitor going idle starts the
cycle; going active alone dismisses nothing.

## Review

Round 1 (DeepSeek V4.1 Flash, head c41bb5f, REQUEST_CHANGES):

1. **A timeout change in a cycle re-based the lock and dpms counts.** The
   keys were `lockAfter - screensaverAfter` from the current values, so a
   plug event or a settings change recreated the monitors from that moment.
   For example, with a battery `screensaverAfter` of 30, the lock came 269 s
   after `lockAfter`. Fixed: the keys come from the timeouts taken when the
   cycle started (`_cycleTimeouts`).
2. **A cycle ending without input woke the displays.** For example, a plug
   event dropping the screensaver in a dark room. Fixed: `cycleEnd` sends
   `dpms.on` only for input.
3. **A `dpmsAfter` equal to `screensaverAfter` kept an inhibitor-aware
   key.** Fixed: `>=`, and the key is at least 1 s.
4. **The model ended the cycle after the removals, so its pinned sequences
   were artefacts.** Fixed: the order is measured on the real service,
   which the model now follows, and the service harness checks it.
5. **Citations.** `IdleNotify.cpp:121` is the `inhibitorsAreObeyed()`
   check in v0.56.2, not a closing brace, so it stays. `update(0)` is now
   cited as `update()` at `:53` calling `update(uint32_t)` at `:38`, and the
   input-only creation is cited at `:89`.
6. **Unloading mid-cycle could queue `_endCycle`.** Fixed: a removed
   presence monitor returns nothing, and the harness shows nothing is sent.

Round 2 (DeepSeek V4.1 Flash, head 9b808e2, APPROVE): every round-1
finding fixed or, for item 5, withdrawn, checked by running (1020/1020 on
the affected selection; the round-1 code ran 106/127, with exactly the four
service asserts among the failures), and five nits, all taken:

1. The index row still said 108/108; it says 127/127.
2. "A new value applies from the next cycle" did not hold for a monitor
   turned on mid-cycle; "What this does not do" now says both.
3. The `cycleEnd` test line listed two of its four cases.
4. The measured Qt order is not a documented guarantee; "Tests" says so.
5. A cycle ending without input with the displays off leaves the service
   counting them as off; recorded under "What this does not do", with why
   waking the displays at the end is worse.

Round 3 (DeepSeek V4.1 Flash, head 969edac, APPROVE), three nits, all
taken: the stale off flag's only path to `dpms.on` is a later cycle's end
with input (round 2 had a window re-check undoing a `haseen screen off`, but
that needs a monitor that went idle, which sets the flag itself); a flap of
a monitor already counting restarts at its cycle key's time, not its full
time; and round 2's summary now gives the 106/127.

Round 4 (DeepSeek V4.1 Flash, head dcb781c, APPROVE), one nit, taken: that
`dpms.on` is redundant only when nothing else turned the displays off, so a
`haseen screen off --delay 0` or an outside `dpms off` just before input
ends a cycle is undone. "What this does not do" says so.
