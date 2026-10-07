# Plan 060: the update button and the charge limit on io

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM (the opt-in limit restore writes sysfs as root at boot and after resume; everything else is read-only or a banner line)
- **Depends on**: 052 057 059
- **Category**: compat, update, power
- **Planned at**: 2026-10-07, owner report: "the updater is not working", "battery charge limiter not working"
- **State**: DONE 2026-10-07 (tests in `tests/test-catalog.sh`, `test-battery-status.sh`, `test-battery-limit.sh`, `test-shell.sh`; the update chain proven in a nested session with stubbed root; the first real pkexec write is an owner check)

## Problem

### The update button

The owner's `t1nk33r.updates` bar widget runs
`omarchy-launch-floating-terminal-with-presentation omarchy-update` on a click.
The shell's PATH starts with the debrand shims (plan 057), and `bash -lc` keeps
them, so the click reaches `haseen config terminal -- bash -c omarchy-update`
and then `haseen update` in a foot window with a TTY. The count side
(`updates.sh`: checkupdates on a private database, `yay -Qua`) works under
haseen: it reported 2 repo updates and no errors.

`haseen update` then died before pacman. Its banner printed
`share/haseen/default/screensaver/screensaver.txt` whenever stdout was a
terminal, and plan 059 deleted that file. Under `set -e`, `cat` failing ended
the update:

```
cat: /usr/local/share/haseen/default/screensaver/screensaver.txt: No such file or directory
[failed: exit 1] press Enter to close
```

The dry-run tests never saw it, because the banner is skipped in a dry run and
when stdout is not a terminal.

Before the shims (journal 08:16 and 08:21), the widget opened Omarchy's own
updater. `/tmp/omarchy-update.log` stops at Omarchy's "Continue with update?"
prompt, and no `sudo pacman -Syu` was ever logged.

### The charge limit

The owner's `t1nk33r.power` panel shows the limit using
`omarchy-battery-status --shell`. That script takes the window from UPower's
`charge-start/end-threshold`. On ThinkPads, UPower reports a fixed 75-80%
there while its own `ChargeThresholdEnabled` is false, whatever the hardware
holds (omacom/omarchy#9586). On io, sysfs said 0/100 and UPower said 75/80.
The panel therefore showed "80%" as the active limit while the battery charged
to 97%.

Setting a limit works:
- `charge-limit.sh` writes start and end in a safe order (thinkpad_acpi
  refuses start > end).
- It escalates with pkexec only when the write fails.
- On 2026-10-01 it ran `charge-limit.sh 80 75` as root via pkexec, after
  fingerprint authentication.
- The kernel logged `start 75, stop 80` at the next boot.

The window was lost on 2026-10-06. The battery ran down far enough that
upowerd requested suspend-then-hibernate (19:09), and every boot since then
registers `start 0, stop 100` [inference: the EC dropped the thresholds when
the battery was drained]. Nothing re-applies a limit at boot, and with the
false "80%" in the panel, nothing showed that the limit had gone.

polkit itself is healthy:
- `haseen.polkit` is registered.
- An authorization request whose subject is the shell's own process reached
  it, and `polkit-agent-helper-1` authenticated in 3 s (09:46:50).
- `pkaction` gives `auth_admin` for `org.freedesktop.policykit.exec`.
- The plugin keeps no charge-limit settings, so shell.json mirroring
  (plan 052) plays no part.

## Decision

- `haseen update`: the banner prints the selected mark's terminal logo
  (`branding_file logo`, the one `haseen about` and the screensaver use), and
  only when that file is readable. The logo is decoration and never stops an
  update.
- New read-only command `haseen battery status [--shell]`. It reads the system
  battery (type Battery, not a `scope=Device` peripheral) from
  `/sys/class/power_supply`: charge, state, draw, capacity, time and cycles.
  The window comes from `charge_control_start/end_threshold`. Its output has
  the same shape as Omarchy's script, so plugins keep parsing it.
- New shim `omarchy-battery-status` → `haseen battery status`. Omarchy power
  panels now show the limit the hardware really holds ("Off" on io today).
- Persistence (integrator follow-up, same plan):
  - `haseen battery limit [status|set END [START]|off|save|restore]` writes
    the thresholds through common.sh's root helpers, in the order the kernel
    accepts (floor first when the window moves down, ceiling first when it
    moves up).
  - It records the window in `/etc/haseen/charge-limit` (`start=`/`end=`,
    root-owned, 0644).
  - `save` records what the battery holds, so a limit a power panel set
    through its own pkexec is kept.
  - `restore` applies the record. It is a silent no-op without a record,
    without thresholds, or when the battery already holds the window.
  - Run as root (by the unit or the hook), the root helpers call the
    command directly instead of through sudo.
  - `haseen setup battery-limit [on|off|status]` is opt-in and off by
    default. `on` installs `haseen-charge-limit.service` (oneshot,
    RemainAfterExit; ExecStart restore, ExecStop save) to
    `/etc/systemd/system`, and the system-sleep hook (`post` → restore) to
    `/usr/lib/systemd/system-sleep/haseen-charge-limit`. It then records the
    current window and enables the unit. `off` disables the unit and removes
    the unit and the hook; the record stays.
  - It refuses without `charge_control_*` files.
  - Menu: Setup → Battery Charge Limit (shown only when a battery has the
    thresholds). Entries: Status, Limit to 80%, No Limit, Keep the Current
    Limit, Restore at Boot and Resume, Stop Restoring.
  - Known limit: the shutdown save records whatever the battery holds. If the
    controller forgot the window while the machine was running, with no
    resume in between to restore it, a clean reboot keeps 0-100.

## Plugin-side notes (read-only here)

- `t1nk33r.power` sets the floor to end − 5 and refreshes from
  `omarchy-battery-status` after the write, so with the shim the panel
  confirms what was written.
- `t1nk33r.updates` is correct as written.

## Verification

- `tests/test-catalog.sh`: a real (not dry) `haseen update` on a TTY
  (`script`), with recording `sudo`/`paru`/`flatpak`, completes. It shows the
  kufic logo and reaches `sudo pacman -Syu` and `paru -Sua`. Before this fix
  it exited 1 at the banner.
- `tests/test-battery-status.sh`: windows 0-100, 75-80 and a single value;
  holding, charging and discharging; time to full and to empty; a mouse
  battery ignored; no battery; a UPower stub that reports 75-80 is never read.
- `tests/test-shell.sh`: the shell's child reaches `haseen-battery-status
  --shell` through `omarchy-battery-status`.
- `tests/test-battery-limit.sh` (fake sysfs under HASEEN_SYSROOT, sudo
  running the command inside the sandbox):
  - set / off / save / restore round trips, and the write order in both
    directions;
  - a bad window is refused, and restore writes nothing when nothing changed;
  - the sleep hook restores on `post` and ignores `pre`;
  - dry runs touch nothing;
  - a desktop: restore and the hook are no-ops, set and setup are refused;
  - setup is off by default, with a dry-run plan.
- Nested Hyprland: the widget's exact command, run with the live shell's
  environment, opened a `haseen.floating` foot. Once with `--dry-run` it showed
  the plan; once with stub root/AUR/flatpak it showed the missing-file failure
  that this plan fixes.
