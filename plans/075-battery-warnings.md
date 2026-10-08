# Plan 075: low-battery warnings

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM (an optional critical action can suspend, hibernate or power off; it ships `none`)
- **Depends on**: 010 060
- **Category**: shell, power
- **Planned at**: 2026-10-07, gap 1 of `docs/reference-shell-gaps.md`; the owner approved the warnings on by default
- **State**: DONE 2026-10-07 (`tests/test-battery.sh`; nested proof on a fake UPower)

## Change

- `haseen.battery` gains a `service` kind (`share/haseen/shell/plugins/haseen.battery/Service.qml`). It reads
  `UPower.displayDevice` property changes (Quickshell.Services.UPower), so nothing polls.
- The decisions live in `BatteryLogic.js` as pure functions: `config`, `reading`, `step`, `cancel`,
  `remaining`, `fire`, `message`.
  - Settings: `warnAt` (20), `criticalAt` (10, 0 = off, clamped to warnAt), `criticalAction`
    (`none` by default, also for unknown values; `suspend`, `hibernate`, `poweroff`).
  - One notification per threshold crossing while discharging. Nothing repeats while the charge stays
    below. A charger resets both levels. A threshold also re-arms when the charge climbs 3 points above
    it without a charger. Starting below both levels notifies once, as critical. UPower's Unknown
    state changes nothing.
  - The critical notification has urgency critical. With an action set, it says
    "Suspending in 60 s: plug in or press Cancel" and carries a Cancel button. `haseen system
    suspend|hibernate|shutdown` runs 60 s later, unless Cancel was pressed, a charger came, or the charge
    recovered. One countdown per crossing: once it ran, was cancelled, was called off by a charger or could
    not be shown, nothing comes back until the level resets (the charge rises on a charger, or climbs 3
    points above `criticalAt`). A timer that fires more than 30 s late (the machine slept through it)
    starts a fresh notification and countdown and does not act.
- Notifications go through `bin/haseen-notification-send`, so the shell's own server (haseen.pager)
  shows them and keeps them in history. The Cancel button is that command's `--exec echo cancel`. The service
  reads "cancel" from the process's stdout. Closing the notification is not a cancel.
- `settings.debugIpc` exposes the `haseen.battery` IPC target (`state`, `cancel`).
- The owner approved the warnings on by default. They are recorded in `AGENTS.md`, and `haseen.battery`
  is listed in `share/haseen/default/shell.json` `services`. The migration
  `share/haseen/migrations/1791397394-battery-service.sh` appends it to a user `services` array, because
  arrays replace the default.
- NixOS: Home Manager runs no haseen migrations. A user whose `shell.json` has its own `services` array
  adds `haseen.battery` to it once, by hand or with `haseen migrate` (which also runs any other pending
  migration; `haseen migrate --pending` lists them); `nix/README.md` says so. Running migrations from the
  activation was rejected: an existing Nix user's ledger is empty, so every older migration would run
  unattended, including the one that puts `haseen.logo` back into a bar the user may have trimmed.
  Moot since 2026-10-05: Nix support was dropped (plan 009), and `nix/README.md` was removed with it.
- `Compat/Dms/Services/BatteryService.qml` no longer claims that haseen covers DMS's battery alerts.
  haseen.battery's service now provides the alerts. DMS's sounds stay unprovided.
- `tools/fake-upower.py` is a fake UPower and power-profiles-daemon on a private bus
  (`DBUS_SYSTEM_BUS_ADDRESS`). Each stdin line is one property change; a `client` line holds the rest
  until a client has read the display device. It refuses the real system bus.

## Evidence

- `tests/test-battery.sh`: 65 JS units (crossings, hysteresis, charging reset, arm, cancel, disarm, fire,
  late fire, messages), the manifest, defaults and migration. Three scenarios run the real `qs` engine
  against the fake UPower, with notify-send and systemctl stubbed:
  - levels: warn, critical, warn again after charging;
  - countdown: a charger calls it off;
  - cancel: the button disarms it, and nothing repeats.
- A one-off 68 s run of the same harness, outside the suite: `criticalAction: suspend` at 10 % logged the
  Cancel notification and then `systemctl suspend` from the stub after 60 s.
- Read-only probe against the fake: Quickshell's `healthPercentage` is 0-100 and `percentage` is 0-1.

## Nested proof

The worktree shell ran in a nest (`tools/nest-launch.sh`) with a scratch HOME/XDG and a fake UPower. The
fake `tools/fake-upower.py` was on a private system bus. idle, lock, polkit, screensaver, nightlight and
prayers were off. `criticalAction` was `suspend`, and `systemctl`, `systemd-run` and `uwsm-app` were
logging stubs on the shell's PATH.

- 20 %: the low notification went out (`~/.cache/haseen-wt/scratch-battery/shots/notify-low.png`).
- 10 %: the critical card in the shell's pager: "10% left, about 40 min. Suspending in 60 s: plug in or
  press Cancel." (`~/.cache/haseen-wt/scratch-battery/shots/notify-critical.png`). The IPC state showed `armed: true`, 58 s
  remaining.
- Historical nest interaction: Cancel was pressed through pager IPC (act). The state then showed
  `armed: false`, `lastAction: ""`, and the systemctl stub logged nothing.
- The nest showed the first warning as "about 3 h": the reading was evaluated before
  `TimeToEmpty` from the same PropertiesChanged arrived. Evaluation is now deferred with
  `Qt.callLater`. That fix was not re-shot in the nest.

## Final visual evidence

- Cancel is directly visible on the critical card, not hidden behind an action affordance
  (`scratch-design/shots/1a-critical-card.png`).
- The after-cancel screenshot has no critical card (`scratch-design/shots/1b-after-cancel.png`); its
  state records `armed: false, cancelled: true, lastAction: ""`
  (`scratch-design/shots/1c-battery-state-after-cancel.json`).

## Not verified

- No pointer click was exercised; the historical pager IPC (act) interaction and these screenshots/state
  do not establish pointer-click use.
- No real laptop: luna is a desktop. Hardware suspend was not exercised (the 60 s path ran against a
  systemctl stub only).

## Rejected

- A second timer that updates the notification every second: a static "in 60 s" text is enough, and
  a live count would need replace ids, which `--exec` cannot print.
- Treating a dismissed notification as Cancel: dismissing means "seen", and the action is opt-in anyway.

## Review fixes (2026-10-08)

- **Fail closed when the Cancel notification is not shown.** `haseen notification send --exec` now asks
  notify-send for the id (`-p`), and fails (exit 1, runs nothing) when the id is 0 or missing (no server,
  daemon error). `Service.qml` starts the countdown only when the id arrives, re-based to that moment
  (`Logic.shown`); a sender that exits without one cancels the countdown (`undelivered` in the debug state).
- **No orphaned notify-send.** Stopping the sender (disarm, re-arm, the action running) used to TERM only
  bash; notify-send kept waiting and the toast, with a dead Cancel, stayed up. The sender now runs
  notify-send beside itself with SIGINT restored and, on TERM/HUP/INT, sends it SIGINT, notify-send's own
  "close the notification and quit" (libnotify 0.8.8 `tools/notify-send.c` `on_sigint`).
- **Charger flaps, Unknown, action turned off.** A charger resets the levels and a Cancel only once the
  charge rises on it (`low`), so a flap never re-warns. `fire` acts only on `discharging` and retries in
  2 s on Unknown. `criticalAction: none` while armed disarms. (This round also let a flap re-arm the
  countdown; that sent a second critical notification and was replaced, see below.)
- Evidence: `tests/test-battery.sh` (47; 76 units, incl. flap, Cancel kept, Unknown retry, `shown`; engine:
  the charger closes the notification, an unshown notification (id 0, or notify-send failing) leaves the
  countdown called off); `tests/test-notification.sh` (50: `-p` with `--exec`, unshown fails, TERM closes).
- Rejected: a fixed replace-id for the countdown toast (still orphans the waiting notify-send); closing by
  id over D-Bus from the sender (a test or dry run could close a live notification on the owner's bus).
- Known limit: on a shell restart systemd TERMs notify-send and the sender together; the sender's SIGINT may
  arrive after notify-send has died, leaving a toast on a non-haseen notification daemon.

## Final review fixes (2026-10-08)

- **A completed action no longer re-arms.** `fire` cleared `armed` but left the crossing unspent, so the
  first discharging reading after a resume below `criticalAt` started another countdown and could
  suspend the machine again. `fire` now sets `acted`; `step` arms again only after the level resets.
- **A charger flap sends one critical notification per crossing.** The model re-armed after a flap
  without a `critical` event, but every arm sends the Cancel notification, so each unplug sent another
  one. A charger that arrives while armed, without the charge rising, now calls the countdown off for
  the crossing (`cancelled`, one "called off" notice). Re-arming would need a fresh Cancel
  notification (fail closed), which is the repeat the contract rules out. Rejected: keeping the old
  toast up while on the charger and resuming under it, which leaves "plug in or press Cancel" on screen
  indefinitely on a charge-limited battery that never rises.
- **Engine scenarios are timed from the shell.** The fake applied its script from its own start, so a
  shell that took more than ~3.5 s to start (the full suite) saw the charger before the 10 % reading and
  three countdown checks failed. Reproduced by a `QS_BIN` wrapper that sleeps 4 s before `qs`
  (44/47); the fake's `client` gate fixes it (47/47 with the same wrapper).
- Evidence: `tests/test-battery.sh` 53/53 (81 JS units). New: fire then readings below `criticalAt`
  start nothing, also with the action turned off and on; a risen charge or `criticalAt + 3` resets and
  the next crossing arms; a flap gives `critical+arm, disarm` and nothing more; the engine `flap`
  scenario counts one critical and one called-off notify-send call across two flaps. Before the fix:
  47/59 (critical 3, called-off 2).
