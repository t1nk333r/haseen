# Plan 104: Boot and logout from Omarchy 4.5

## Status

- **Priority**: P1 (the `root=` guard is boot safety), P2 (the rest)
- **Effort**: M
- **Risk**: MEDIUM. The `root=` guard and the boot menu decide what the next
  boot reads. The guard only ever adds a pin or refuses; the boot menu is
  opt-in, edits two header lines in a layout it recognises, keeps a copy,
  and enrolls the edited config again before it returns. Every new path is
  covered by dry runs on fixture sysroots and real runs on scratch files.
- **Depends on**: 002 (Secure Boot: `haseen secureboot sign`), 033
  (hibernation's `boot_cmdline_add` caller), 036 (Plymouth's caller), 093 and
  102 (the `omarchy-system*` answers), 100 (affected tests), 101 (owns
  Plymouth and `boot_hooks()`; untouched here)
- **Category**: boot, session
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; the live steps on IO and luna are
  owner steps)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs
  stay as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts", "1-second
  boot menu", "New binds".

This plan implements **"Faster boot & logout"** (survey B.2 #7, #10),
**"1-second boot menu"** (B.2 #28) and, from **"Security & bug fixes
(Recommended)"**, the Limine `root=` guard (B.2 #5). The boot menu is opt-in
and off by default: haseen had never edited `/boot/limine.conf`, so the owner's
choice of the feature is honoured as a command, not a default.

## Problem

1. **`root=` can drop out of the next boot image.** limine-entry-tool reads
   the kernel command line from `KERNEL_CMDLINE[...]` in its config layers and
   falls back to `/etc/kernel/cmdline` or `/proc/cmdline` only while no layer
   sets it; a `+=` "Ignores /etc/kernel/cmdline and /proc/cmdline"
   (`/usr/share/doc/limine-entry-tool/README.md:389-400`,
   limine-mkinitcpio-hook 1.40.0-2). haseen's `boot_cmdline_add` writes exactly
   such a `+=` drop-in (`share/haseen/lib/boot.sh:39-41` before this plan;
   callers `bin/haseen-plymouth-set:91`, `bin/haseen-hibernation-setup:133`,
   `share/haseen/omarchy/bin/omarchy-plymouth-set:96`) and never looked for
   `root=`. On a machine whose `root=` came from the fallback, the next image
   has none and the boot stops in an emergency shell. Omarchy hit it and
   fixed its upgrader in 393a43d46 (#6951; "Verified in a VM … booting that
   state landed in 'Failed to mount '' on real root'"). The same trap sat in
   the systemd-boot branch: with no `/etc/kernel/cmdline`, haseen wrote one
   holding only the new words, and kernel-install and mkinitcpio stop reading
   `/proc/cmdline` once that file exists (systemd 262
   `/usr/lib/kernel/install.d/90-loaderentry.install:88-93`, mkinitcpio 42.2
   `/usr/bin/mkinitcpio:590-606`).
2. **The boot waits for nothing.** Omarchy 4.5 mounts binfmt_misc before
   `systemd-binfmt` registers formats, so the boot does not stall on the
   automount (d10031418, #15175), and raises systemd's mount-event allowance
   from 5 to 30 a second (60e96ac0d, #15182). haseen had neither; IO and luna
   would get Omarchy's copies only once `omarchy-settings` 4.5 lands
   (`pacman -Ql omarchy-settings` on luna, 4.0.6-1: `/etc/systemd/system.conf.d/`
   holds only `10-faster-shutdown.conf` and `20-omarchy-nofile.conf`; the
   binfmt directories do not exist).
3. **Logout, reboot and shutdown cut browsers off.** `haseen system` acted at
   once (`bin/haseen-system:69-78` before this plan). Omarchy 4.5 closes every
   window and waits for the owning processes, 2 s at most, before it acts
   (4bf51ed1a, #15231: `bin/omarchy-system@v4.5.0-rc1:46-55`,
   `bin/omarchy-hyprland-window-close-all@v4.5.0-rc1:10-16,26-29`), "so browsers
   save their sessions".
4. **Limine's menu waits 3 to 5 s on every boot.** Omarchy 4.5 ships
   `timeout: 1` and `quiet: yes` (3b4c5d0da, #15301,
   `default/limine/limine.conf@v4.5.0-rc1:2-3`) and seds existing installs'
   `limine.conf` in place (`migrations/1791898365.sh@v4.5.0-rc1:32,34,40`)
   without enrolling the edited config again, which panics Limine under
   Secure Boot (`/usr/share/doc/limine/USAGE.md:24-37`). limine-entry-tool has
   no key for the wait: its binary carries only the header it writes into a
   new file, `#quiet: yes` and `timeout: 3` (`strings
   /usr/lib/limine/limine-entry-tool`, limine-mkinitcpio-hook 1.40.0), so the
   header has to be edited in place.

## What was built

### 1. The `root=` guard (`share/haseen/lib/boot.sh`)

Before `boot_cmdline_add` writes its Limine drop-in, `boot_limine_keep_root`
(`share/haseen/lib/boot.sh:281`) merges the config layers as limine-entry-tool
does, with the drop-in about to be written (`boot_limine_merge`, `:186`):
`/usr/share/limine-entry-tool.d/*.conf`, `/etc/limine-entry-tool.conf`,
`/etc/limine-entry-tool.d/*.conf`, `/etc/default/limine`
(`/usr/lib/limine/limine-common-functions:115-156`, the shell keys' order,
which the README's KERNEL_CMDLINE rules follow); `+=` appends, `=` replaces, a
pair of surrounding double quotes and trailing blanks go. The parameters are
split as the kernel splits them (`boot_cmdline_words`): at blanks outside
double quotes, an unmatched quote running to the end. `root=` counts only as a
word of its own (`boot_cmdline_states`). This is Omarchy's check
(`kernel_cmdline_root_pinned`, `bin/omarchy-upgrade-to-quattro@v4.5.0-rc1:531`)
rewritten, and every one of its fixture cases
(`test/shell.d/upgrade-to-quattro-test.sh@v4.5.0-rc1:298-322`) is a test here.

When the merge states no `root=`:

- **no layer set the key before** (limine-entry-tool used its fallback): the
  whole fallback line is pinned, `/etc/kernel/cmdline` if it exists, else
  `/proc/cmdline` without `BOOT_IMAGE=`, so nothing the machine boots with is
  lost;
- **a layer already set it** (an Omarchy `+=` drop-in, say): the running
  kernel's root parameters are pinned, Omarchy's list (`:595,599`) without
  `resume=`/`resume_offset=`, which haseen's hibernation drop-in states and
  must win.

The pin goes to `/etc/limine-entry-tool.d/haseen-cmdline.conf`, written
before the drop-in (`:306`, `:48`), and sorts before haseen's other drop-ins.
It refuses, writing nothing, when that line has no `root=`, when it is a
snapshot (`.snapshots/` in its `rootflags`) or live (archiso) boot, when a
layer that exists cannot be read, or when a later `=` would replace the pin
too (`:295`, `:300`). A drop-in that a later `=` replaces is written but
returns 2 with a warning to add its words to that line: the callers already
treat 2 as "add it yourself" (`bin/haseen-plymouth-set:91-92`).

On systemd-boot a new `/etc/kernel/cmdline` starts from the line the tools use
while it is absent: `/usr/lib/kernel/cmdline`, else `/proc/cmdline` without
`BOOT_IMAGE=` and `initrd=` (`boot_cmdline_seed`, `:91`), never from nothing.
An existing file is kept as before.

### 2. Boot drop-ins (base layer)

`share/haseen/default/systemd/` ships Omarchy's three files under haseen's
names, with the MIT notice: `system/systemd-binfmt.service.d/10-haseen-eager-mount.conf`
(`Wants=proc-sys-fs-binfmt_misc.mount`),
`system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf` (the
automount's two conditions, as in systemd 262's
`/usr/lib/systemd/system/proc-sys-fs-binfmt_misc.automount`) and
`system.conf.d/20-haseen-mount-events.conf`
(`ManagerEnvironment=SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST=30`; the variable is
read by systemd 262, `strings /usr/lib/systemd/libsystemd-core-262-1.so`).
`boot_dropins_apply` (`share/haseen/lib/boot.sh:355`), run by the base layer
(`base_boot_dropins`), installs each through `install_root_file` unless
Omarchy's copy (same directory, Omarchy's name) is there, and removes haseen's
where Omarchy's is, so each setting is stated once; `daemon-reload` follows a
unit drop-in change. `haseen layer status base` reports each (`warn` when
missing or stale: a speed-up, not a broken layer). They act at the next boot.

Which already reach IO and luna through Omarchy's package: none today
(`omarchy-settings` 4.0.6); all three except the conditions file's name
(`10-omarchy-conditions.conf`) once `omarchy-settings` 4.5 installs them. At
that point both copies exist until `haseen layer apply base` runs again and
removes haseen's (owner step); until then each setting is stated twice with the
same value, which systemd merges (a `Wants=` list, identical conditions, one
environment variable).

### 3. Close apps first (`bin/haseen-system`)

`haseen system logout|reboot|shutdown` now calls `close_apps`
(`bin/haseen-system:49`) first: every Hyprland window is asked to close
(`hl.dsp.window.close`, or `closewindow` on a non-Lua Hyprland, as
`share/haseen/omarchy/bin/omarchy-hyprland-window-close-all` already does),
then `timeout 2s pidwait --euid $UID --pid <pids>` waits for the owning
processes. Without a Hyprland session (a TTY, ssh, the tests' sandbox) there is
nothing to close. Omarchy re-runs itself in a transient user unit so that
closing the terminal that asked cannot kill it (`bin/omarchy-system@v4.5.0-rc1:75`);
haseen instead leaves open any window whose process is one of the command's
ancestors (`ancestor_pids`, from `/proc/<pid>/stat`), and the session's end
closes it. lock, suspend and hibernate close nothing.

Every way to log out, reboot or shut down reaches it:

- the system menu rows (`share/haseen/default/menu.jsonc:334-336`) and
  `omarchy-update-restart`'s offer (`haseen_exec system reboot`);
- SUPER + SHIFT + ESCAPE, which ran `uwsm stop` directly and now runs
  `haseen system logout` (`share/haseen/default/hypr/binds.lua:116`);
- the battery's critical action (`BatteryLogic.js` `actionCommand`, already
  `haseen-system`);
- plan 102's `omarchy-system logout|reboot|shutdown`: logout is the
  `omarchy-system-logout` shim to `haseen-system logout`
  (`share/haseen/omarchy/commands.tsv:433`); reboot is
  `omarchy-system-reboot`, which closes the windows itself and schedules
  `haseen-system reboot` two seconds later in a transient unit
  (`share/haseen/omarchy/bin/omarchy-system-reboot:28`), where the wait now
  runs for whatever is still open; shutdown's last stage execs
  `haseen-system shutdown` (`omarchy-system-shutdown:44`). The test runs the
  logout and shutdown paths through haseen's close and wait.

### 4. The 1-second boot menu, opt-in (`haseen setup boot-menu`)

`bin/haseen-setup-boot-menu fast|normal|status`, off by default, Limine only.

- **What it changes.** `fast` sets `timeout: 1` and `quiet: yes`, Omarchy's
  values; a key pressed during that second shows the menu
  (`/usr/share/doc/limine/CONFIG.md:87-102`, limine 12.9.3). `normal` puts back
  the two values `fast` replaced. `status` prints the wait, what `normal` would
  restore and whether the config hash enrolled in Limine matches the file.
- **Only a layout it understands** (`bootmenu_problems`,
  `share/haseen/lib/bootmenu.sh:57`): a regular file with at least one menu
  entry, no NUL or carriage return, at most one uncommented `timeout:` and one
  `quiet:` (option names are case-insensitive, CONFIG.md "Options"), both above
  the first entry, with values Limine documents; and no config Limine would
  read first (`sb_limine_shadows`). Anything else is refused with the reason.
- **Only those two lines change** (`bootmenu_render`, `:97`): an existing line
  is replaced, a missing `timeout:` goes on the first line and a missing
  `quiet:` right after it; comments such as limine-entry-tool's `#quiet: yes`
  stay. Rendering twice changes nothing; rendering with the recorded values
  gives the original bytes back for the layouts in the tests.
- **Safely written.** The command reruns itself as root when the ESP is 0700
  (`sb_reexec_as_root`, as `haseen secureboot sign` does) and refuses a real run
  under `HASEEN_SYSROOT`. It copies `limine.conf` to
  `/var/lib/haseen/boot-menu/limine.conf.<UTC time>` (`install_root_file`,
  `bin/haseen-setup-boot-menu:220`), records the replaced values once in
  `/var/lib/haseen/boot-menu/original` (`:222`), then runs the root helper
  `share/haseen/lib/limine-header.sh` through `sb_root` (`:224`). The helper
  takes limine's own boot-partition lock, the one limine-entry-tool and
  limine-snapper-sync hold while they write the ESP (`flock` on
  `/run/lock/boot-partition.lock`, `/usr/lib/limine/limine-mutex`), checks the
  layout again under it, and replaces the file through a temporary file and a
  rename, as `limine-hash-assets.sh` does. Every step prints under `--dry-run`.
- **Secure Boot.** Before anything changes, `reenroll_plan` decides how the
  enrolled hash follows the edit: with haseen's Secure Boot keys (sbctl and
  keys present), `haseen secureboot sign` (plan 002: re-enroll, refresh the
  fallback copy, sign, verify); without them and with Secure Boot off,
  `limine-enroll-config`, which limine-entry-tool itself runs after every update
  (`/etc/boot/hooks/post.d/90-limine-enroll-config`;
  `enroll_config` in `limine-common-functions` also signs with sbctl when it is
  set up); nothing when no hash is enrolled or wanted. It refuses when a hash is
  enrolled but `ENABLE_ENROLL_LIMINE_CONFIG` is not `yes`, when
  `limine-enroll-config` is missing, and when Secure Boot is on but sbctl holds
  no keys (someone else signed Limine). If re-enrolling fails after the edit,
  the copy is put back (`:227`), the record of a first `fast` is dropped, the
  restored file is enrolled again, and the command fails.
- **`normal` after a hand edit.** When the wait no longer reads `fast`, the
  owner changed it since: `normal` leaves it and drops haseen's record.

## Outside the brief's owned paths

- `share/haseen/layers/base/layer.sh`: sources `lib/boot.sh` and calls
  `boot_dropins_apply`/`boot_dropins_status` (the brief puts the drop-ins in
  the base layer).
- `share/haseen/default/hypr/binds.lua:116`: SUPER + SHIFT + ESCAPE runs
  `haseen system logout` instead of `uwsm stop`, so the log-out key closes apps
  too. Plan 103 (binds) may touch the same file.
- `share/haseen/layers/secureboot/secureboot.sh` and
  `bin/haseen-secureboot-setup`: `sudo_is_test_stub` moved from the command
  into the shared file, unchanged, so `haseen setup boot-menu` grants its test
  recorder the same narrow exception (a real run under `HASEEN_SYSROOT` only
  with `HASEEN_TEST_STUBBED_SUDO=1`, not as root, and a sudo inside
  `tests/.out`).
- `docs/architecture.md` (§2, §3, §9), `handoff.md`, `NOTICE.md`.

## Rejected options

- **Pin `root=` into `/etc/default/limine`, as Omarchy does.** haseen's rule
  is drop-ins, never editing system files (architecture §3); a drop-in works
  unless `/etc/default/limine` replaces the key with `=`, which the merge sees
  and refuses.
- **Pin only Omarchy's root parameters in every case.** Where no layer set the
  key, limine-entry-tool reads the whole fallback line; pinning a subset would
  drop every other parameter the machine boots with (a GPU option, `quiet`).
- **Ask `limine-entry-tool --get-cmdline`.** It answers from the fallback
  until the first `+=` lands, so it reads healthy on exactly the machines
  about to break (Omarchy's 393a43d46 message), and it is a binary the tests
  could not run on fixtures.
- **Copy `resume=` into the pin.** haseen's `haseen-resume.conf` states it and
  sorts after the pin; a stale copy from `/proc/cmdline` would only duplicate
  or shadow it.
- **Pin from a snapshot or live boot.** That would make every later boot one
  of the snapshot; refused.
- **Re-run `haseen system` in a transient unit (Omarchy's way).** It would
  hand the poweroff to a second unit after `omarchy-system-shutdown`'s
  inhibitor ended, and its result would no longer reach the caller; leaving
  the asking terminal open costs nothing at the end of a session.
- **Route the haseen.session panel through `haseen system` now.** No default
  bind or menu row opens it, and changing it selects every shell test; left
  as a follow-up (Not done).
- **Make `fast` the default, or apply it from a layer.** The owner chose the
  feature, but haseen never edited `limine.conf` and the edit needs Secure
  Boot care; an explicit command keeps it the owner's act.
- **A `--timeout N` option.** Omarchy's value is the feature; one more value
  to validate and restore, for no request.
- **sed in place, as Omarchy's migration does.** No lock, no layout check, no
  backup, no enrollment; Limine panics under Secure Boot after it.
- **Edit `limine.conf` with `write_root_file` or `install`.** Both chmod the
  destination, which vfat refuses after the content was written; a helper with
  a temporary file and a rename keeps the write whole.
- **Keep backups on the ESP.** The ESP is small and Limine's own territory;
  `/var/lib/haseen` is root's and backed up with the system.
- **Omarchy's "Reboot to Boot Menu".** Added in 3b4c5d0da and removed again
  before the tag (0c93f6142, #15795); `quiet: yes` already shows the menu on a
  key press.

## Tests

`tests/test-omarchy45-boot.sh` (new; `# haseen:covers` for every new file):

- the merge: Omarchy's 15 fixture cases plus two (a pin in an `/etc` drop-in;
  `/etc/default/limine` replacing a drop-in pin);
- the guard through `boot_cmdline_add`: stated `root=` (no pin), the whole
  fallback pinned (`/proc/cmdline` without `BOOT_IMAGE=`, and
  `/etc/kernel/cmdline`) before the drop-in, the root parameters after an
  Omarchy `+=` layer (no `resume=`), an existing pin kept, refusals (no `root=`
  anywhere, a later `=` without one, a snapshot boot, an unreadable layer) that
  write nothing, a replaced drop-in returning 2; `haseen plymouth set --dry-run`
  pinning before its drop-in;
- the systemd-boot seed: from `/proc/cmdline`, from `/usr/lib/kernel/cmdline`,
  an existing file kept, a live medium refused;
- the drop-ins: contents and notices, install, nothing when current, Omarchy's
  copies win and haseen's are removed once, a stale copy replaced, the base
  layer's status lines and apply step;
- `haseen system`: windows closed (Lua and legacy dispatchers), the asking
  terminal's window left open, one bounded `pidwait` per process before the
  action, nothing without Hyprland or for lock/suspend, a real run with stubs
  finishing within the 2 s bound when an app will not exit,
  `omarchy-system logout` and `omarchy-system-shutdown --inhibited` waiting
  too, the log-out bind;
- the boot menu: layout checks (refusals for no entry, duplicate keys, a key
  below the first entry, unknown values, carriage returns, a symbolic link),
  rendering on limine-entry-tool's and Omarchy 4.0.6's headers, idempotence
  and restore; the root helper on scratch files (rendered bytes, mode kept,
  lock taken, no temporary file left, unchanged on a second run, restore,
  refusals, waiting while another tool holds the lock); the command's status,
  `fast`, already fast, `normal` with and without a record and after a hand
  edit, a bad record, refusals (sysroot real run, layout, shadowing config,
  systemd-boot, usage), the unreadable-ESP dry run, and the four Secure Boot
  plans (refused without `ENABLE_ENROLL_LIMINE_CONFIG`, refused without
  `limine-enroll-config`, `limine-enroll-config` with Secure Boot off,
  refused with Secure Boot on and no sbctl keys, `haseen secureboot sign` with
  haseen's keys) and the stale-hash status; real runs through a recording sudo
  (the step order: backup, record, edit, enroll; enrolling that fails once puts
  the copy back, drops a first `fast`'s record and enrolls the restored file;
  failing twice says not to reboot; a failed edit enrolls nothing), and a sudo
  outside `tests/.out` refused before it is called.

Counts are in Evidence.

## Evidence

- Omarchy, cloned read-only (`v4.0.6` = 237f1b407, `v4.5.0-rc1` = 03ff1eff3,
  `quattro` at 7075b61c6). Verified in its code: 393a43d46
  (`bin/omarchy-upgrade-to-quattro@v4.5.0-rc1:531-553` the merge, `:555-649` the
  pin and its parameter list), d10031418 and 60e96ac0d (the three drop-ins,
  absent at `v4.0.6`), 4bf51ed1a (`bin/omarchy-system@v4.5.0-rc1:46-55,75`,
  `bin/omarchy-hyprland-window-close-all@v4.5.0-rc1:10-16,26-29`), 3b4c5d0da
  (`default/limine/limine.conf@v4.5.0-rc1:2-3`, and still at `quattro`;
  `migrations/1791898365.sh@v4.5.0-rc1:32,34,40`), 0c93f6142 (the menu item's
  removal), f03bf0674 (`etc/limine-entry-tool.d/omarchy-defaults.conf@v4.5.0-rc1:19`).
  After the tag, the only `quattro` commit on these paths is 3ac43659d (language
  and folders in the upgrader; `git diff v4.5.0-rc1 origin/quattro --
  bin/omarchy-upgrade-to-quattro | grep -ci 'cmdline\|root='` = 0).
- Taken from the survey without re-checking: B.2's ranking and the IO
  details it gives; that CachyOS's installer states `root=` in
  `/etc/default/limine` stays INFERRED (the guard passes silently there, and
  pins or refuses otherwise).
- Local reads on this laptop (read only): limine-mkinitcpio-hook 1.40.0-2
  (`README.md:389-400`, `limine-common-functions` `load_config`,
  `enroll_config`, `is_sb_installed`, `limine-mutex`), limine 12.9.3
  (`CONFIG.md:87-102`, `USAGE.md:24-43`), systemd 262-1 (the binfmt units,
  `90-loaderentry.install:88-93`), mkinitcpio 42.2 (`:590-606`), procps-ng
  4.0.7 (`pidwait --pid`, `--euid`).
- Tests (hermetic wrapper, at the commit of this plan):
  `tests/run.sh --affected origin/main` ran 40 of 157 test files, 6145/6145
  passed; `tests/test-omarchy45-boot.sh` alone 214/214; `tools/lint.sh` OK
  (886 shell, 33 Lua, 198 JSON, 334 QML, 41 Go files; affected-tests check:
  every one of 2594 files covered, global or exempt); `tools/check-docs.sh`
  OK.

## Owner steps

On IO and luna, after this lands and the tree is installed
(`./install.sh --tree-only --yes`, see handoff "Installing a checkout"):

1. `haseen layer apply base`: installs the three boot drop-ins (none of them
   is installed by `omarchy-settings` 4.0.6). After `omarchy-settings` 4.5
   lands, run it again: haseen's two copies whose Omarchy twins arrived are
   removed. Effective from the next boot.
2. Nothing to do for the `root=` guard: it runs inside `haseen plymouth set`
   and `haseen hibernation setup`. To see what it would do on a machine, run
   either with `--dry-run`: a `haseen-cmdline.conf` line in the output is the
   pin it would add.
3. Optional, the 1-second menu: `sudo haseen setup boot-menu status` (the ESP
   is root's), then `haseen setup boot-menu fast` if the layout is one haseen
   edits; on a Secure Boot machine it runs `haseen secureboot sign` itself.
   `haseen setup boot-menu normal` undoes it. Check `haseen secureboot status`
   is all ok before the next reboot if Secure Boot is on.
4. The log-out key (SUPER + SHIFT + ESCAPE) takes effect after `hyprctl
   reload`.

## Not done

- `systemd.tty.term.console=dumb` beside `quiet splash` (survey B.2 #7,
  f03bf0674): it belongs in `haseen plymouth set`, which plan 101 owns. IO and
  luna already boot with it through `omarchy-defaults.conf`; machines without
  Omarchy's package and with haseen's splash do not. A follow-up for the
  Plymouth owner.
- `initramfs_async=0`: the survey asks for an owner check that CachyOS's
  kernel shows the race first.
- The haseen.session panel still calls `systemctl` and Hyprland's exit
  dispatcher directly (`share/haseen/shell/plugins/haseen.session/Panel.qml:134-144`);
  it is reachable only through `haseen shell ipc panel toggle haseen.session`.
- mkinitcpio also reads `/etc/cmdline.d/*.conf` while `/etc/kernel/cmdline`
  is absent; a machine using it gets the seed's parameters once more in its
  UKI (duplicates, not a loss).
- Old backups in `/var/lib/haseen/boot-menu/` are kept (a few KiB each).
