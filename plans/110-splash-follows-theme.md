# Plan 110: The boot splash follows the applied theme

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM. A user action now leads to a root rebuild of the boot
  image without a password. The root side takes one input, the instance name
  of a template unit, parses it strictly, reads nothing in a home and runs only
  from a tree root owns; the polkit rule that allows the start is narrowed
  against a transient-unit bypass found while building it (below). Nothing is
  rebuilt in the background on a machine that checks its boot files.
- **Depends on**: 002 (Secure Boot facts: `sb_keys_exist`, `sb_limine_value`),
  036 (the splash: `haseen plymouth set`, `lib/plymouth.sh`), 059 (marks),
  100 (affected tests), 101 (`boot_hooks`, `root_trusted_haseen`), 104
  (`haseen system reboot|shutdown`; untouched)
- **Category**: boot, theme
- **Planned at**: 2026-10-22, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; a real boot, polkit on a live
  system and the owner steps on IO are owner steps)

## Decision (owner, 2026-10-22)

In the coordinating thread the owner asked: "i want also plymouth boot screen
that matches the color of the applied theme". Asked how it should follow theme
changes, the owner chose **"In the background"**: after a theme has stayed
applied for about 2 minutes, haseen rebuilds the boot image at low priority,
with no password prompt, so quick theme flicking does not rebuild; a shutdown
waits for a rebuild that is still running.

Not chosen:
- "Right away, with password": a terminal asks for sudo on every theme change.
- "At the next update": colours catch up only when the initramfs is rebuilt
  anyway.

## Problem

1. **The splash is coloured from the theme only when `haseen plymouth set`
   runs.** Its help said so: "the splash does not follow them by itself,
   because rewriting files under /usr needs root"
   (`bin/haseen-plymouth-set:23-24` at 439dcd3); the mark likewise
   (`bin/haseen-branding:30,49` at 439dcd3) and the contract
   (`docs/architecture.md:671` at 439dcd3). The colours come from
   `plymouth_theme_colors`, the script from `plymouth_script`, the mark from
   `plymouth_install_logo` (`share/haseen/lib/plymouth.sh`), and the image from
   `boot_initramfs_rebuild` (`share/haseen/lib/boot.sh:441`).
2. **Observed on IO, 2026-10-22** (coordinating thread): the installed splash
   dated from 2026-10-07 while a wallpaper-generated theme was applied;
   `haseen plymouth set` fixed it by hand, limine-mkinitcpio rebuilding the
   UKI in about 30 s.
3. **Omarchy does not follow either.** `omarchy-plymouth-set-by-theme` is
   called only from its menu (`default/omarchy/omarchy-menu.jsonc:156` at
   `v4.5.0-rc1`, the `style.unlock` entry, through a floating terminal);
   `bin/omarchy-theme-set` at `v4.5.0-rc1` does not mention plymouth (grep).

## What was built

### Two sides, one name between them

```
haseen theme set / haseen branding mark
  └─ haseen plymouth follow poke ── systemctl --user restart haseen-splash-follow.timer (OnActiveSec=2min)
                                       └─ 2 min after the last change: haseen-splash-follow.service
                                            └─ haseen plymouth follow request
                                                 compare current theme + mark with /var/lib/haseen/splash
                                                 └─ systemctl start --no-ask-password haseen-splash@BG-FG-ACCENT-MARK.service
                                                      (polkit: 50-haseen-splash.rules)
                                                      └─ root: haseen plymouth apply BG-FG-ACCENT-MARK
```

- **The request** is the instance name: background, text and accent as six
  lowercase hex digits each, then the mark, e.g. `13131a-e4e1ec-96d69a-kufic`
  (`plymouth_request`, `plymouth_request_parse`,
  `share/haseen/lib/plymouth.sh:174,183`). The parser refuses anything else:
  upper case, other lengths, an unknown mark, extra fields, shell or path
  characters, a newline; it never repairs.
- **The user's side.** `bin/haseen-theme-set:140` (`:113` under `--dry-run`)
  and `bin/haseen-branding:52-54` call `haseen plymouth follow poke`, which
  restarts `haseen-splash-follow.timer` only when following is on
  (`plymouth_follow_on` reads the enablement link, so with following off a
  theme change starts no systemctl at all, `:293-303`). Every way a theme
  becomes current goes through `bin/haseen-theme-set`: `haseen theme install`,
  `haseen theme wallpaper`, `haseen theme generate`, `haseen font set` and
  Omarchy's `omarchy-theme-set` and `omarchy-theme-refresh` answers
  (`share/haseen/omarchy/commands.tsv:458,460`) all run it. `theme-lib.sh`
  (plan 106's) is untouched. A headless theme set (`HASEEN_THEME_HEADLESS=1`:
  installer, chroot, tests) skips it with the reloads.
- **The timer** (`share/haseen/systemd/user/haseen-splash-follow.timer`):
  `OnActiveSec=2min`, `AccuracySec=10s`. A restart re-activates it, so each
  change starts the 2 minutes again; flicking themes rebuilds nothing.
  Enabled (`WantedBy=timers.target`), it also fires 2 minutes after the user
  manager starts, which catches a change made just before a shutdown at the
  cost of one comparison per login. No process waits during the 2 minutes.
- **The request** (`bin/haseen-plymouth-follow:95-134`): nothing when
  following is off or haseen's splash is not the one plymouthd shows; the
  record `ok` when `/var/lib/haseen/splash` already holds the request;
  otherwise `systemctl start --no-ask-password haseen-splash@REQUEST.service`,
  waiting for it. Success is silent. A refused or failed start records
  `failed` and sends one critical notification with systemctl's first line.
  When the theme changed while root was rebuilding, the timer's firing found
  this service still running and was lost, so the request restarts the timer
  afterwards (`:129-133`).
- **Root's side** (`bin/haseen-plymouth-apply`, hidden from `haseen
  commands`): refuses unless root or `--dry-run`; holds SIGTERM from the start
  (`:56`); parses the name without echoing a malformed one back (`:59-62`);
  requires haseen's splash to be the one plymouthd shows, a machine that does
  not check its boot files (`:66-68`) and an mkinitcpio configuration that
  evaluates; takes `/run/lock/haseen-splash.lock`, so concurrent instances
  of different colours run one after the other (`:71-77`); does nothing when
  the image already carries the request; allows 6 rebuilds an hour across all
  instances, because `StartLimit*` counts per instance (`:83-100`); installs
  through `plymouth_install_theme` exactly what `haseen plymouth set` installs
  and runs `boot_initramfs_rebuild` (`:107-112`); writes the record only
  after the rebuild (`:113`). As root, the helpers' `sudo` is a function that
  runs its arguments, as `bin/haseen-battery-limit:46-48` does for its unit.
- **The root unit** (`share/haseen/default/systemd/haseen-splash@.service`,
  rendered with this tree's router and the ESP into
  `/etc/systemd/system/haseen-splash@.service`): `Type=oneshot`, `Nice=19`,
  `IOSchedulingClass=idle`, `ProtectHome=tmpfs` (the kernel enforces that no
  home is visible), `PrivateTmp=yes`, `NoNewPrivileges=yes`,
  `StartLimitIntervalSec=10min`/`StartLimitBurst=3`, `TimeoutStartSec=30min`,
  `KillMode=mixed`, `TimeoutStopSec=5min`, `RequiresMountsFor=ESP /usr
  /var/lib`, no `[Install]`.
- **One rebuild path.** `plymouth_install_theme`
  (`share/haseen/lib/plymouth.sh:127`) is what both `haseen plymouth set` and
  the root side install, `boot_initramfs_rebuild` what both run;
  `plymouth_install_logo` takes the mark as an argument so the root side
  never reads `shell.json`. `haseen plymouth set` now records the request it
  built (`bin/haseen-plymouth-set:109`).

### Enabling

- `haseen plymouth set` turns following on after it installs the splash
  (`bin/haseen-plymouth-set:121`). `--no-follow` leaves it as it is;
  `--theme NAME` does not turn it on and, when following is on, warns that
  NAME's colours last until the next theme change or login.
- `haseen plymouth follow on|off|status` (`bin/haseen-plymouth-follow`).
  `plymouth_follow_enable` (`share/haseen/lib/plymouth.sh:310`): refuses (3)
  on a machine that checks its boot files and (4) for a tree root does not
  own, each said; warns when the user is not in `wheel` (the rule's group);
  writes the rendered unit when it is missing or stale,
  reloads systemd, checks the unit is there, then installs the polkit rule,
  then `systemctl --user enable --now` the timer. `off` disables the timer,
  removes the rule, then the unit. Every step is checked by hand because the
  callers run it as `|| rc=$?`, where `set -e` does not apply.
- The rule sits in `/etc/polkit-1/rules.d`, which is `drwxr-x--- root
  polkitd` (`stat` on this laptop), so a user cannot see it: the root state
  that status and the request read is the unit's alone, `on` writes the rule
  every time, and a missing rule shows as a refused start.
- Migration `share/haseen/migrations/1792669390-splash-follows-theme.sh`:
  nothing without plymouth or when haseen's splash is not shown; nothing when
  following is on with a current unit; otherwise `plymouth_follow_enable`.
  On a machine that checks its boot files, or from a tree root does not own,
  it says why and completes (it has done what it can; `haseen plymouth follow
  on` is there later). Any other failure fails the migration, which retries.
- `haseen plymouth status` adds `follows:` and `matches: yes / pending / no
  (why)` (`plymouth_matches`, `:378`).

### The transient-unit bypass, and how the rule closes it

The brief's preferred rule matched the unit name pattern and the `start`
verb. Reading systemd's source showed that this alone would give every wheel
member passwordless root code execution:

- `method_start_transient_unit` (`src/core/dbus-manager.c` at `v262`, also
  `v257` and `v258`) calls `bus_verify_manage_units_async_impl(m, name,
  "start", N_("Authentication is required to start transient unit
  '$(unit)'."), …)`: the same `unit` and `verb` details as starting a unit
  from a file, for a unit whose `ExecStart` the client chooses
  (`systemd-run --unit=haseen-splash@….service -- …`). Up to `v256` it called
  `bus_verify_manage_units_async`, with no details.
- Starting a unit from a file passes `polkit_message_for_job[JOB_START]` =
  "Authentication is required to start '$(unit)'."
  (`src/core/dbus-unit.c`, the same text at `v254` through `v262`).
- polkit hands every detail to the rules, `polkit.message` included
  (`push_action_and_details`, `src/polkitbackend/polkitbackendduktapeauthority.c`
  at polkit `127`; `Action.lookup` in `init.js`), and systemd, as uid 0, may
  pass details (`polkitbackendinteractiveauthority.c:1048-1084`).

So the rule (`share/haseen/default/polkit/50-haseen-splash.rules`) requires,
besides the action, `verb == "start"`, the anchored name pattern and wheel,
the exact message for a start from a file. A transient start carries the other
message (257 and later) or no unit at all (256 and earlier). A future systemd
that rewords the message makes the rule allow nothing: closed, with the
failure notified. Second layer: `manager_setup_transient_unit` refuses a name
that is not pristine, and a template instance has a fragment
(`unit_is_pristine`, `src/core/unit.c:5419-5436` at `v262`), so while the
template is installed no transient unit of such a name can be created even
if polkit allowed it; enabling installs and loads the unit before the rule,
and disabling removes the rule before the unit. A test drops the message
check from a copy of the rule and the transient case turns to `yes`.

The unit and the rule are also written only when the router, `haseen
plymouth apply` and every directory it sources or reads as root (`lib`,
`layers/secureboot`, `default/plymouth`, `branding` and each mark) are
root's alone (`plymouth_follow_trusted`, `root_trusted_haseen`): from a
checkout a user owns, the next edit would be root's code for every wheel
member without a password.

### Secure Boot

Following is never set up, and a request never rebuilds, on a machine that
checks its boot files (`plymouth_signed_boot`, `:226`): Secure Boot on, or its
state unreadable on UEFI; sbctl keys (`sb_keys_exist`); or
`ENABLE_ENROLL_LIMINE_CONFIG=yes` (`sb_limine_value`). The request records
`skipped` and notifies once (not after every theme change); `follow on`
refuses; root's side refuses again; status says `no (…: run haseen plymouth
set after a theme change (then haseen secureboot sign, with haseen's Secure
Boot keys))`.

Why not rebuild there: outside a pacman transaction haseen's
`zz-haseen-secureboot.hook` does not run. limine-mkinitcpio's own post hook
re-enrolls the config and signs the Limine binary
(`/etc/boot/hooks/post.d/90-limine-enroll-config`, `enroll_config` in
`/usr/lib/limine/limine-common-functions:361-377`, limine-mkinitcpio-hook
1.40.0-2 on this laptop), but the fallback copy haseen keeps
(`sb_limine_refresh_fallback`) is not refreshed, and whether a new UKI is
signed depends on limine-entry-tool, a native binary this plan could not
read. So it could not be shown that a background rebuild leaves the machine
bootable there, and the brief says to skip it then. `haseen plymouth set`
itself is unchanged in this respect; the hint names `haseen secureboot sign`
after it.

### Shutdown and power loss

- The unit's stop signals only the main process (`KillMode=mixed`).
  `plymouth_guard_stops` traps TERM and INT, and bash runs a trap only after
  the foreground command returns, so a stop that arrives during
  `limine-mkinitcpio`/`mkinitcpio -P` lets it finish; the record is then
  written and the unit stops. A stop before the rebuild exits having changed
  nothing that boots (the theme files under `/usr` are read only by the next
  build). `TimeoutStopSec=5min` bounds the wait; then systemd kills the rest.
- Ordering: a service's default dependencies conflict with and order before
  `shutdown.target`, so no rebuild starts once a shutdown has begun;
  `RequiresMountsFor=` the ESP, `/usr` and `/var/lib` stops the unit before
  those are unmounted.
- `haseen system reboot|shutdown` (plan 104) ends in `systemctl
  reboot|poweroff` (`bin/haseen-system:131,135`), the normal shutdown
  transaction, so it waits like any shutdown. It is not changed.
- Power loss during the write (about 30 s at normal priority on IO) can leave
  the image incomplete, as during any kernel update pacman runs; nothing in
  software prevents that. The record stays the old one, so the next request
  rebuilds. Recovery is the same as after a failed kernel update: another
  boot entry (a fallback image or a Limine snapshot entry, where configured)
  or a live medium, then `haseen plymouth set`.

## Outside the brief's owned paths

- `share/haseen/systemd/user/haseen-splash-follow.{timer,service}`: user
  units go where `install.sh` installs them for everyone
  (`install.sh:245-246`); the brief named `share/haseen/default/systemd/`,
  where the root template is.
- Docs: `docs/architecture.md` (§2 rows, §9, §11), `handoff.md` (map row),
  `share/haseen/agents/skills/haseen/SKILL.md` (the theme and mark answers).

## Rejected options

- **A rule matching only the unit name and `start`** (the brief's preferred
  shape as written): the transient-unit bypass above.
- **pkexec with a custom action**: the root process would be the user's
  child, in the user's slice, which a shutdown stops before system units, so
  a rebuild could be cut off; also a password unless the action is
  `allow_active=yes` for everything pkexec'd through it.
- **A spool directory and a path unit** (`DirectoryNotEmpty=` on a
  wheel-writable `/run` directory): no polkit, but root reads a file a user
  wrote (symlink and FIFO tricks need `O_NOFOLLOW`/`O_NONBLOCK` reads), and the
  user cannot wait for the result to notify a failure without polling.
- **A socket-activated root service**: no dependency-free client (bash has no
  Unix-socket redirection; socat and nc are not installed by default).
- **A sleeping user service as the debounce** (`restart` on a service that
  sleeps 120 s): works, but a process waits for every change; the timer
  holds none.
- **Rebuild on a Secure Boot machine and run `haseen secureboot sign`
  afterwards**: it could not be shown bootable in the background (above), and
  a missed failure notification there means a machine Secure Boot refuses.
- **Installing the rule in `/usr/share/polkit-1/rules.d`** so users can see
  it: that is the packages' directory; a locally added rule belongs in
  `/etc`.
- **Requiring `subject.active`/`subject.local` in the rule**: the request
  runs in the user manager, outside any logind session, so the subject's
  session properties are not reliable there.

## Tests

`tests/test-splash-follow.sh` (new, 224/224), all hermetic, on fixture
sysroots with recording `systemctl` and `notify-send` fakes:

- the request from the current theme and mark; the parser with 16 malformed
  or injected names (upper case, 5 and 7 digits, unknown mark, extra and
  missing fields, `;id`, `$(id)`, a newline, `../`, a trailing space, `#`,
  `g`, underscores);
- the polkit rule in a fake polkitd (`tests/fixtures/polkit-harness.js`,
  `vm` with only `polkit` in scope): allowed for a wheel member starting a
  well-formed instance with any mark; not for a transient start (systemd 257+
  and 256-), no message, not wheel, 8 other verbs, 10 other unit names, other
  actions; ES5 only; its marks are `BRANDING_MARKS`;
- the units' keys, the rendered router and ESP, and `systemd-analyze verify`
  of all three (skipped where it is not installed);
- the trigger: poke and `theme set`/`branding mark` restart the timer only
  when following is on, never start the root unit themselves, not when
  headless, and plan it under `--dry-run`;
- the request: off, matching, differing (exactly one `systemctl start
  --no-ask-password haseen-splash@….service`), refused (critical
  notification, `failed`), a theme change during the rebuild (the timer
  restarted), no root unit, an out-of-date unit (still tried; status says
  so), another splash chosen, Secure Boot on (skipped,
  notified once), and each signal of a machine that checks its boot files;
- root's side under `env -i` with an unreadable HOME and a different mark in
  the user's `shell.json`: the colours and mark from the name only, the lock,
  the hourly count, the rebuild, the record after the rebuild; refused when
  malformed (not echoed), not root, another splash, Secure Boot on, an
  mkinitcpio configuration that does not evaluate; nothing when the image
  already matches; hidden from `haseen commands`;
- the stop guard: SIGTERM to the main process during a 1 s foreground
  command; the command finishes and the stop is seen afterwards;
- `follow on` refused from this checkout (a tree a user owns), planned from a
  planted root-owned tree (unit, daemon-reload, rule, timer, in that order),
  refused when any sourced file or mark is writable by others; a current unit
  not rewritten; refused with Secure Boot on; `off` in reverse order; status;
- `haseen plymouth set`: records the request, turns following on, not with
  `--no-follow` or `--theme`, warns with `--theme` while following is on;
- the migration under `DRY_RUN=true`: enables, idempotent, nothing for
  another splash or without plymouth, completes saying why with Secure Boot
  on and from a tree root does not own;
- help texts of `plymouth set`, `plymouth follow`, `theme set`, `branding`.

`tests/test-plymouth.sh` is unchanged and passes 79/79.

`tests/run.sh --affected origin/main` with the hermetic wrapper selects 34
files: 5532/5532 from a short bind mount of this checkout (`bwrap --bind`
to `/tmp/s110`, as the gate notes advise for T3 worktrees). From the long T3
worktree path the same run was 5528/5529: `tests/test-nvim-theme.sh` "one
line per spec" fails there because headless nvim joins its long printed
lines; it passes 108/108 from the short path, and the same from a `main`
checkout at a short path. Under bwrap, `tests/test-capture-upload.sh` skips
its subordinate-uid check (no `unshare --map-auto` inside the mount
namespace); it ran in the long-path run. `tools/lint.sh` (shellcheck 0.11.0
at `/usr/bin/shellcheck`) OK; `tools/check-docs.sh` OK; gitleaks 8.30.1
over the branch range and the privacy patterns: nothing found.

## Evidence

- systemd `v254`–`v262` sources (`src/core/dbus-manager.c`,
  `src/core/dbus-unit.c`, `src/core/dbus-util.c:161-210`,
  `src/core/unit.c` at `v262`), read from a temporary clone, deleted after.
- polkit `127` (`src/polkitbackend/`), read from a temporary clone, deleted
  after.
- Omarchy `v4.5.0-rc1`: `bin/omarchy-plymouth-set-by-theme`,
  `default/omarchy/omarchy-menu.jsonc:156`, `bin/omarchy-theme-set`.
- This laptop, read only: systemd 262-1, polkit 127-3,
  `/etc/polkit-1/rules.d` is `drwxr-x--- root polkitd`;
  limine-mkinitcpio-hook 1.40.0-2 (`/usr/bin/limine-mkinitcpio`,
  `/etc/boot/hooks/post.d/90-limine-enroll-config`,
  `/usr/lib/limine/limine-common-functions:282-377`,
  `/usr/share/doc/limine-entry-tool/README.md:461-463,569-573`).

## Owner steps

On IO (and luna, where haseen's splash is installed), after deploying with
`install.sh` (which installs the two user units):

1. `haseen migrate` turns following on (it asks for sudo once to install the
   root unit and the polkit rule). Where Secure Boot is on or sbctl holds
   keys it says so and leaves the splash to `haseen plymouth set`.
2. Change the theme and wait about 2 minutes; `haseen plymouth status` shows
   `matches:   yes` (`pending` until then). `journalctl -b -u
   'haseen-splash@*'` shows the rebuild.
3. Reboot to see it.

## Not done

- Not run on a live system: the polkit rule against a real polkitd and
  systemd (the details and message are read from their sources, and the rule
  is tested in a fake polkitd), the timer's restart semantics in a real user
  manager, `ProtectHome=tmpfs` with limine-mkinitcpio, the stop held across a
  real shutdown, and a real boot of the rebuilt image.
- Background rebuilds on Secure Boot machines (above).
