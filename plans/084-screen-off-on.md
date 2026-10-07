# Plan 084: Screen off / Screen on

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (DPMS only; any key press or pointer motion wakes the displays)
- **Depends on**: 016, 019, 076, 082
- **Category**: shell, power
- **Planned at**: 2026-10-08, owner request
- **State**: DONE 2026-10-08 (`tests/test-screen.sh`, `tests/test-menu.sh`, `tests/test-battery.sh`,
  `tests/test-idle.sh`; nested dpmsStatus proof)

## Change

- `haseen screen off [--delay MS]` (`bin/haseen-screen-off`) and `haseen screen on` (`bin/haseen-screen-on`):
  two commands, never a toggle. Both send the dispatcher haseen.idle sends
  (`share/haseen/shell/plugins/haseen.idle/Service.qml:62-66`) through `hyprctl dispatch`:
  `hl.dsp.dpms({ action = "disable" | "enable" })` when Hyprland reads a Lua config, else `dpms off|on`
  (`share/haseen/lib/screen.sh:21` `screen_dpms`). The mode is the same question Quickshell asks for
  `Hyprland.usingLua`: `configProvider` of `hyprctl status -j` (`screen.sh:15` `screen_lua`; the request is
  `j/status` in the qs binary's strings; the nest answers `"configProvider": "lua"`). A Hyprland without the
  request answers no JSON and gets the legacy form. A reply other than `ok` fails the command.
- Off waits `--delay` first, **1000 ms by default** (0 = now, at most 60000), in the foreground
  (`bin/haseen-screen-off:59`). `misc.key_press_enables_dpms` and `mouse_move_enables_dpms` stay true
  (`share/haseen/default/hypr/input.lua:64-65`), so an off sent at once is undone by the release of the click,
  the motion after it or the release of Enter; the default covers every caller, a terminal's Enter included.
- Menu, System: **Screen off** (monitor-off glyph U+F0D90) and **Screen on** (monitor glyph U+F0379) after
  Lock (`share/haseen/default/menu.jsonc:320-321`). The menu closes, then runs the action in bash in its own
  scope (`haseen.menu/Panel.qml:524-537`, `Apps.launch`), so the wait outlives the menu and a shell restart.
- Battery panel: a **Screen** row with two `Choice` buttons, the panel's existing button style, Theme tokens
  only (`haseen.battery/Panel.qml:317-334`). Screen off closes the panel over IPC and then execs the command in
  the same detached `sh` (`Panel.qml:85-87`), so the close is sent before the wait starts; Screen on runs
  `haseen-screen-on` detached and leaves the panel open (`Panel.qml:89-91`). Both by absolute path from the
  checkout's `bin/`, like the panel's other commands.

## Idle interplay (haseen.idle, read for this plan)

`Service.qml:54` `_dpmsOff` is set only when the dpms monitor's own idle edge sends the off
(`Service.qml:87-90`); `IdleLogic.js:62-65` sends `dpms.on` on the active edge only when it is set. The manual
command never touches it. Hyprland's ext-idle-notify counts from the last input, and a DPMS dispatch is not
input. So:

1. **Manual off, then input**: Hyprland wakes the displays (the input options above); no monitor was idle, the
   service sends nothing.
2. **Manual off, idle continues**: the screensaver monitor still starts the screensaver (on a dark display),
   the **lock comes at `lockAfter`**, and at `dpmsAfter` the service sends its own (redundant) off and sets
   `_dpmsOff`. The next input wakes the displays and the service sends `dpms.on`, which is what it turned off.
3. **Manual off, Stay Awake or a context removes an idle monitor**: the delegate's destruction runs the active
   edge (`Service.qml:121-124`); with `_dpmsOff` false there is no `dpms.on`, so the service never undoes a
   manual off.
4. **Manual on while the service holds the displays off** (only from outside the seat, e.g. ssh; any local
   input wakes them first): the displays come on, `_dpmsOff` stays true; the next input sends a harmless
   `dpms.on` and clears it; the next idle cycle turns them off again as before.
5. **Manual on with the displays on**: a no-op dispatch; the service is unaffected.

## Evidence

- `tests/test-screen.sh` (38): `--help` and `haseen commands screen`; dry-run argv for off (default 1000 ms,
  `--delay 250`, `--delay=0`) and on, in Lua mode and legacy mode, nothing dispatched and no wait; a stub
  hyprctl stamping each dispatch: legacy off is two words `dpms off` and lands at ≥ 1000 ms; Lua off with
  `--delay 1500` has dispatched nothing at 1.2 s and lands at ≥ 1500 ms; `--delay 0` at once; refusals
  (bad, over-limit or missing delay, extra words) dispatch nothing; a dispatcher Hyprland refuses fails.
- `tests/test-menu.sh` (288): the System rows in order with the screen rows after Lock; each System row's
  `--dry-run` is pure; Screen off and Screen on run the way `haseen.menu` runs an action (bash, `bin/` first
  on PATH, eval) and reach a stub hyprctl as one disable then one enable, the disable ≥ 1000 ms after the row.
- `tests/test-battery.sh` (40): the panel in the real Quickshell engine; both buttons are found by
  `objectName`, shown, and clicked through their `clicked` signal; stub `qs` and `hyprctl` record
  `qs ipc --pid PID call panel close` within 500 ms of the click, the Lua disable ≥ 1000 ms after it, and the
  enable within 500 ms of the second click.
- `tests/test-idle.sh` (71): a model in Qt's JS engine of Hyprland's DPMS state with three writers (the
  commands, the service as in `Service.qml _run` driving `IdleLogic.actions`, and input), one assertion per
  case 1–5 above.
- Also passing, unchanged: `tests/test-ambient.sh` (242; `IdleLogic.js` is not changed), `test-menu-view` (27),
  `test-launcher-providers` (49), `test-trigger` (179), `test-core` (73), `test-widgets-a/b/c` (64, 42, 100),
  `test-surfaces` (89), `test-shell` (258).

## Nested proof

A nest from `tools/nest-launch.sh` under `flock ~/.cache/haseen-wt/nest.lock`, its window output disabled,
`key_press_enables_dpms` and `mouse_move_enables_dpms` set true as in haseen's `input.lua`, the worktree
shell with `tools/fake-upower.py` on a private system bus. `dpmsStatus` from the nest's `hyprctl monitors -j`;
times from the press. Logs in `~/.cache/haseen-wt/scratch-screen/`.

`proof.log`, the panel clicked with `tools/vptr`, the pointer moving three more times in the 600 ms after
the release:

| step | result |
|---|---|
| Screen off clicked | panel layer gone at +116 ms (dpms still true); `dpmsStatus` false at +1136 ms, false at ~3 s |
| Screen on (input wake turned off in the nest for this step only, so only the command can wake) | false after the click, true at +887 ms |
| Screen off, pointer motion 2.9 s later | false at 2.5 s, true after the motion |

`menu-proof.log`: System opened over IPC, `vkbd` Down, Down, Enter held 150 ms on Screen off, a Shift press
200 ms after the release: false at +1113 ms, still false at 3 s; a later Shift press wakes them.

`idle-proof.log`, haseen.idle with `lockAfter` 6, `dpmsAfter` 10 and haseen.lock on, the off from the CLI
with `--delay 0` 0.5 s after input:

| time | dpmsStatus | idle state |
|---|---|---|
| control: `--delay 0`, motion 100 ms later | false, then **true** (what the delay prevents) | |
| 3 s | false | no monitor idle, `dpmsOff` false |
| 6.8 s | false | lock idle (the session locked: `shots/locked.png`) |
| 10.8 s | false | dpms idle, `dpmsOff` true |
| 12 s, `haseen screen on` | true | `dpmsOff` still true |
| input at 13 s | true | both active, `dpmsOff` false |
| 24 s (11 s after the input) | false | the next cycle turned them off again |

Screenshots looked at: `shots/panel.png` (the Screen row under Power profile), `shots/menu-system.png` and
`shots/menu-screen-off-selected.png` (the two rows after Lock), `shots/locked.png`.

## Review fixes (2026-10-08)

- `--delay` takes at most 5 digits after leading zeros: `2^63` passed as a negative number and `2^64+1000` as
  1000, both dispatching at once (`tests/test-screen.sh` "off --delay … is refused").
- `bin/haseen-screen-off`'s header now says what runs it: the menu through Apps.launch, the power panel through
  `Quickshell.execDetached` (a shell restart within that second loses the off).

## Not verified

- A real panel or monitor going dark: the nest's headless output only reports `dpmsStatus`.
- Legacy (hyprlang) Hyprland against a real compositor: only the argv, through the stub.
- A shell restart during the one-second wait from the panel: the panel uses `Quickshell.execDetached`
  (the shell's cgroup), so that one off would be lost; the menu path runs in its own scope.

## Owner decisions

- **Keybinds**: haseen's defaults bind no DPMS key (`share/haseen/default/hypr/binds.lua:112-113` are the
  brightness keys only, left as they are). Your SUPER+XF86MonBrightnessDown/Up binds in `~/.config/hypr` stay
  yours. Should haseen ship default binds for `haseen screen off|on`? None were added.
- **Screen on closing the panel**: it leaves the panel open (no input reason to close it); say if it should close.

## Rejected

- **A QML Timer in a long-lived service**: the menu and the battery panel are lazily loaded and destroyed on
  close, so the timer would need a new service or singleton; a terminal or keybind could not share it; a shell
  restart in the window would lose the off.
- **`systemd-run --user --on-active=1s`**: a transient timer gets the user manager's environment, not the
  caller's, so `HYPRLAND_INSTANCE_SIGNATURE` and `PATH` would have to be passed by hand; `AccuracySec` defaults to 1 min and needs overriding; it leaves units to collect.
  The foreground wait in a process the caller detaches is the smaller thing.
- **Backgrounding inside the command** (`setsid` + `&` and exit): callers already detach it, and a waiting
  foreground process is what a terminal user expects and can Ctrl-C.
- **One `haseen screen toggle`**: the owner asked for two separate actions.
- **The Blackout overlay or `haseen hardware laptop display off`**: an overlay leaves the panel lit; disabling
  an output moves its workspaces. DPMS only.
- **Detecting Lua mode by trying the Lua dispatcher first** (`haseen keybinds list`): a dry run could not
  print the argv without dispatching.
