# Plan 075: low-battery warnings

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM (an optional critical action can suspend, hibernate or power off; it ships `none`)
- **Depends on**: 010 060
- **Category**: shell, power
- **Planned at**: 2026-10-07, gap 1 of `docs/reference-shell-gaps.md`; the owner approved the warnings on by default
- **State**: DONE 2026-10-07 (`tests/test-battery.sh`; nested proof not run, see below)

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
    recovered. After a cancel nothing comes back until a charger resets the level. A timer that fires more
    than 30 s late (the machine slept through it) starts a fresh notification and countdown and does not act.
- Notifications go through `bin/haseen-notification-send`, so the shell's own server (haseen.pager)
  shows them and keeps them in history. The Cancel button is that command's `--exec echo cancel`. The service
  reads "cancel" from the process's stdout. Closing the notification is not a cancel.
- `settings.debugIpc` exposes the `haseen.battery` IPC target (`state`, `cancel`).
- The owner approved the warnings on by default. They are recorded in `AGENTS.md`, and `haseen.battery`
  is listed in `share/haseen/default/shell.json` `services`. The migration
  `share/haseen/migrations/1791397394-battery-service.sh` appends it to a user `services` array, because
  arrays replace the default.
- `Compat/Dms/Services/BatteryService.qml` no longer claims that haseen covers DMS's battery alerts.
  haseen.battery's service now provides the alerts. DMS's sounds stay unprovided.
- `tools/fake-upower.py` is a fake UPower and power-profiles-daemon on a private bus
  (`DBUS_SYSTEM_BUS_ADDRESS`). Each stdin line is one property change. It refuses the real system bus.

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

## Not verified

- No nested screenshot of the notification. On luna, `tools/nest-launch.sh` exits at
  `before=$(wayland_sockets)`: under `pipefail`, the last glob entry (`wayland-1.lock`) makes the loop
  status 1. Not fixed here.
- No real laptop: luna is a desktop. Hardware suspend was not exercised.

## Rejected

- A second timer that updates the notification every second: a static "in 60 s" text is enough, and
  a live count would need replace ids, which `--exec` cannot print.
- Treating a dismissed notification as Cancel: dismissing means "seen", and the action is opt-in anyway.
