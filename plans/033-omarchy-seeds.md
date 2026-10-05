# Plan 033: Omarchy config and script seeds

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (hibernation touches fstab, the initramfs and the kernel command line)
- **Depends on**: 001 003 010 025 031
- **Category**: system
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05 (hibernation unverified on real hardware, see below)

## Problem

Omarchy carries a long tail of small, finished pieces that haseen simply did not
have: no hibernation, no power profile that follows the power source, no speaker
tuning, no way to turn a web page into an app, no notification CLI for scripts,
no IME or XCompose seeds, and no picker for wallpapers or images.

## Decision

Port them as **config and script seeds**: the behaviour, in haseen's existing
shapes, with no new abstractions. One `NOTICE.md` row per item. Each lands
independently.

- **Hibernation** (`bin/haseen-hibernation-{status,setup}`,
  `share/haseen/lib/hibernate.sh`) is the one item that is a **rewrite**, not a
  copy: upstream assumes neither LUKS nor a CachyOS btrfs layout.
  - The swapfile lives in a **top-level `@swap`** subvolume mounted at `/swap`,
    not a nested one inside the root subvolume, so a snapper rollback of `@`
    does not take the hibernation area with it.
  - The resume device is whatever holds the swapfile, which on a LUKS install is
    the opened mapper device. The initramfs must open the container first:
    busybox hooks need `resume` **after** `encrypt` (appending it in a drop-in
    does that), and systemd hooks need **no** `resume` hook at all, because
    systemd-hibernate-resume acts on `resume=` itself and the busybox hook would
    fail the build. The effective HOOKS are evaluated the way mkinitcpio
    evaluates them (later `HOOKS=` replaces, `HOOKS+=` appends), not by grepping
    every file.
  - The command line is written where this machine's bootloader reads it:
    a limine-entry-tool drop-in, `/etc/kernel/cmdline`, or an instruction for
    GRUB. s2idle machines also get `rtc_cmos.use_acpi_alarm=1`.
  - Readiness is measured against `/sys/power/image_size`, the largest image the
    kernel will write, and zram is never counted as hibernation swap.
- **Power profile** (`bin/haseen-powerprofile-{init,list,set}`): the remembered
  profile per power source, in `$HASEEN_USER_STATE`. AC/battery is read from
  `/sys/class/power_supply` through `sysroot_path` (upstream asks UPower over
  D-Bus), so it works at login time and from a fixture.
- **Speaker tuning** (`bin/haseen-audio-tuning`, `share/haseen/audio/`): the
  filter-chain graph and the Dell XPS 2026 measurements, matched with plan 031's
  DMI matcher instead of a second one, hosted as a WirePlumber fragment instead
  of a private systemd unit, and rolled back when the tuned sink does not appear.
- **Web apps** (`bin/haseen-webapp-{install,remove}`): a page becomes a
  `.desktop` running the default browser in app mode, with its icon fetched. A
  browser without app mode is refused instead of silently opening a tab.
- **Notifications** (`bin/haseen-notification-{send,wait,dismiss}`): `wait`
  blocks until something owns `org.freedesktop.Notifications`, which is how a
  script that fires early stops losing its toast; `send` builds one argv, never
  a shell string, and a click is a real freedesktop action; `dismiss` calls the
  pager IPC that already existed.
- **Config seeds** (`bin/haseen-seed-{user,system}`, `share/haseen/default/*`):
  btop, fcitx5 (Arabic ↔ English on one key, which the owner actually needs),
  XCompose (with Arabic punctuation added), `environment.d`, the Framework QMK
  udev rule and the snapper policy. User files are seeded once and never
  overwritten; root-owned ones go through the privileged helpers.
- **Plugins** (`haseen.imagepicker`, `haseen.background`, `haseen.agents`): all
  three are panels, none polls, and `background` is a **picker over haseen's
  existing background state** (`haseen theme bg …`), not a second wallpaper
  daemon. `agents` answers the local question (which agent processes are
  running, where, for how long) rather than porting upstream's provider
  accounts and usage meters.
- **`agent-crash`**: the one command taken from the 16 `omarchy-agent*`; it
  hands a core dump to whichever agent command the user configured, consistent
  with this machine's `diagnose-crash` skill.

## Verification

- `tests/test-hibernation.sh` (35), `tests/test-powerprofile.sh` (35),
  `tests/test-audio.sh` (64), `tests/test-webapp.sh` (49),
  `tests/test-notification.sh` (47), `tests/test-seeds.sh` (68),
  `tests/test-widgets-c.sh` (100). Every slice is dry-run pure and matched
  against fixture machines (AC, battery, desktop; busybox vs systemd initramfs;
  a machine that matches no tuning).
- Live on the reference laptop: `haseen hibernation status` reads the real
  machine correctly (31.0 GiB RAM, 31.0 GiB swapfile, 12.4 GiB image limit,
  busybox hooks with the resume hook present, `resume=` with offset 1929459 →
  ready) and `haseen hibernation setup` is a no-op on it. The fresh-machine plan
  was exercised against a fixture.

## Open

**Hibernation has not been proved by an actual suspend-to-disk on this machine.**
It cannot be: the resume test requires powering the laptop back on by hand, and
the machine has no passwordless sudo, so the privileged steps were only planned.
What is proved is the state this machine is already in (ready) and the plan for a
machine that is not. The owner's one-command check, with nothing else running:

```
haseen hibernation status && systemctl hibernate   # then power the laptop back on
```

If it resumes, hibernation is verified; if it boots cold instead, the resume
offset is stale — `haseen hibernation setup` rewrites it.

## Execution record

`bin/haseen-{hibernation-status,hibernation-setup,powerprofile-init,powerprofile-list,powerprofile-set,audio-tuning,webapp-install,webapp-remove,agent-crash,notification-send,notification-wait,notification-dismiss,seed-user,seed-system}`,
`share/haseen/lib/hibernate.sh`, `share/haseen/audio/`,
`share/haseen/default/{btop,fcitx5,xcompose,environment.d,udev,snapper,wireplumber}/`,
`share/haseen/shell/plugins/haseen.{imagepicker,background,agents}/`, the
`powerprofile init` line in `share/haseen/default/hypr/autostart.lua`, six
packages in `share/haseen/layers/desktop/packages.txt`, and seven test files.
