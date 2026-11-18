# Plan 177: a pending theme change reaches the boot image before a reboot

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. A reboot or shutdown right after a theme change waits for
  the rebuild that following would have run 2 minutes later. Any other
  reboot is unchanged, and a failure only warns.
- **Depends on**: 104 (`haseen system`), 110 (the splash follows the theme),
  175 (the menu colours ride on following)
- **Category**: boot
- **Planned at**: 2026-11-18, from the owner
- **State**: DONE 2026-11-18 (`tests/test-splash-follow.sh` 304/304; a
  reboot on IO right after a theme change is the owner's check)

## Problem

Following (plan 110) rebuilds the boot image once a theme has stayed
applied for 2 minutes: `haseen-splash-follow.timer` has `OnActiveSec=2min`
(`share/haseen/systemd/user/haseen-splash-follow.timer`), and
`haseen theme set` restarts it. Since plan 175, Limine's menu colours are
rewritten in that same root run (`limine_colours` in
`bin/haseen-plymouth-apply`). A reboot inside those 2 minutes therefore
boots with the previous theme's splash and menu. The timer also fires 2
minutes after the user manager starts, so the boot after that one catches
up, but the first one is wrong.

The owner asked, 2026-11-18: "can hassen plymouth set and hassen setup
bootmanu colors be invoked after the theme selection and applied ?". Three
options were offered: a shorter wait, a `follow now` command, and applying
a pending change at reboot. The owner chose the third: "go for the 3rd".

## Decision

- `haseen plymouth follow now` (`bin/haseen-plymouth-follow`). When
  following is on, haseen's splash is the one chosen, and the current
  theme's request differs from `/var/lib/haseen/splash`, it sends a
  notification ("Updating the boot splash") and starts the user's
  `haseen-splash-follow.service` with `systemctl --user start`, waiting for
  it under `timeout 5m`.
  - It goes through the user's service instead of asking root itself. The
    oneshot then runs once: a rebuild the timer has already begun is waited
    for, not begun a second time. A failure is notified by the service's own
    `request`, as the timer's would be.
  - The 5 minutes match root's `TimeoutStopSec=5min` in
    `haseen-splash@.service`. Past that, the shutdown still waits for a
    rebuild that has begun (`KillMode=mixed` and its TERM trap).
  - It does nothing, and starts no systemctl, when the image matches, when
    following is off, when another splash is chosen, or on a machine that
    checks its boot files (`plymouth_signed_boot`), where following never
    rebuilds.
- `haseen system reboot` and `haseen system shutdown` (`bin/haseen-system`)
  run it first (`follow_now`), before the apps are asked to close. The
  session stays usable during a long rebuild, and nothing is lost if it
  fails. A failure warns and the reboot goes on. `--dry-run` passes
  through. The session menu, SUPER + SHIFT + ESCAPE and Omarchy's
  `omarchy-system` all reach this command (plan 104).
- Suspend, hibernate and logout are unchanged: none of them boots the
  image.
- `now` is also documented in `--help`, for someone about to reboot by
  another route.

## Rejected

- **A shorter wait** (for example 20 s). Browsing themes in the picker
  would rebuild once per theme held for 20 s, and a reboot inside the
  shorter wait would still miss it.
- **Only a `follow now` command.** It works only when someone remembers to
  run it before rebooting, which is no better than `haseen plymouth set`.
  It is kept as the mechanism, and reboot runs it.
- **A systemd shutdown hook** (a unit ordered before `shutdown.target`). It
  would cover `systemctl reboot` too, but at that point the user's manager
  and session are being torn down. The request needs the user's theme, which
  root never reads (plan 110: `ProtectHome=tmpfs`, the colours travel in the
  unit's name), so it has to be made from the session, before the session
  ends.
- **Running the rebuild after the apps close.** The machine would sit with
  an empty session through the rebuild, and a failure would leave nothing
  open to report it in.

## Limitations

- A reboot started outside haseen (`systemctl reboot`, a power key that
  logind handles) skips this. The timer's firing 2 minutes after the next
  login still brings the image up to date, one boot late.
- A reboot right after a theme change takes as long as the rebuild, at
  idle priority (`Nice=19`, `IOSchedulingClass=idle`), at most 5 minutes
  before the session ends.

## Verification

`tests/test-splash-follow.sh` (304/304; the new checks):

- `now` with the image behind: the notification, then
  `systemctl --user start haseen-splash-follow.service`;
- `--dry-run`: dry-pure, the bounded `timeout 5m` wait planned, nothing
  started;
- a failing service fails `now`;
- `haseen system reboot`: the rebuild and then `systemctl reboot`. `shutdown`
  with a failing service warns and still powers off. A dry reboot plans the
  rebuild before the reboot and starts nothing. Suspend does not wait;
- nothing at all with the image up to date (a reboot only reboots), with
  following off, or with Secure Boot on.
