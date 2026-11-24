# Plan 188: hibernation and Secure Boot signing fixes from the 2026-11-24 audit

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. `omarchy-hibernation-remove` now does less (plain swap, and a
  /swap mount line someone else wrote, are left alone); `haseen hibernation
  setup` exits 1 where it used to print a false success; `haseen hibernation
  status` can say "not ready" on a machine it called ready before, when the
  `resume=` it found never reached the kernel; `haseen secureboot sign`
  refuses one more case; `limine-hash-assets.sh` can wait up to 30 s for
  Limine's lock.
- **Depends on**: 033 (hibernation), 093 (the Omarchy hibernation shims), 104
  (the Limine command-line merge, the boot-partition lock)
- **Category**: boot
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2f7f472a)
- **State**: DONE 2026-11-24 (`tests/test-hibernation.sh` 66/66,
  `tests/test-omarchy-hw.sh` 281/281, `tests/test-secureboot.sh` 280/280;
  every new check fails on 9a9e82ab)

## Why

The audit's boot group confirmed seven findings: two in
`omarchy-hibernation-remove`, three in `haseen hibernation setup` and
`status`, and two in the Secure Boot signing path. Each was re-checked on
main at 9a9e82ab, which has plans 182-184 on top of the audited 2f7f472a;
none of those touched these files, and every finding still held. Line
numbers below are 9a9e82ab's unless they say "now".

## 1. `omarchy-hibernation-remove` deleted the @swap subvolume under a kept fstab line (high)

**Evidence.** `share/haseen/omarchy/bin/omarchy-hibernation-remove:109-110`
set `top_level` for any uncommented `/swap btrfs` fstab line with `subvol=`.
`fstab_without_hibernation` (`:62-81`, the test at `:68`) drops that mount line
only when `# haseen: hibernation image area` is the line above it. Step 3
(`:158`) then unmounted /swap and deleted the subvolume whatever step 2 kept,
the very outcome the comment at `:148-149` says the order prevents ("a mount
line for a deleted subvolume would stop the next boot"). `haseen hibernation
setup` reuses an existing /swap line without writing the comment
(`bin/haseen-hibernation-setup:94-97`), so this hit haseen's own setup on an
Arch-wiki layout. The new test below, run against 9a9e82ab's script, printed
`DRYRUN: sudo umount /swap` and `DRYRUN: sudo btrfs subvolume delete <a
temporary directory>/@swap` after a `write /etc/fstab` that still held
`UUID=abcd /swap btrfs subvol=/@swap,rw,noatime 0 0`.

**Fix.** The script reads the rewritten fstab back (`fstab_swap_mount -`,
which now takes a file argument) and sets `mount_kept` when a /swap mount line
survives. Step 3 then warns that it keeps that line and the subvolume it
mounts, and neither unmounts nor deletes anything. A line setup wrote, which
step 2 removes, goes with its subvolume as before. The header lists the rule.

**Test.** `tests/test-omarchy-hw.sh`, "an owner's mount line": an untagged
`/swap btrfs subvol=/@swap` line, a swapfile and a resume hook. The swapfile
goes, the fstab written keeps the mount line, the warning is printed, and no
`umount /swap` or `btrfs subvolume delete` appears.

**Rejected.** Removing the untagged mount line along with the subvolume: it is
the owner's line, and they may mount /swap for more than the swapfile.
Adding `nofail` to it: haseen still would have edited a line it did not write.

## 2. `omarchy-hibernation-remove` removed plain swap (medium)

**Evidence.** The early exit at `:128` gave up only when none of a /swap
mount, a `/swap/swapfile` swap line, the swapfile, a resume hook or the Limine
drop-in existed, so any btrfs /swap swapfile counted as hibernation. Omarchy's
own `/usr/bin/omarchy-hibernation-remove` (omarchy 4.5.0-3) exits with
"Hibernation is not set up" unless `omarchy_resume.conf` holds
`HOOKS+=(resume)`. The new test, against 9a9e82ab, printed swapoff and
subvolume-delete steps on a fixture with no hook, no drop-in and no `resume=`.

**Fix.** Now the script removes something only when it finds a sign of
hibernation: haseen's or Omarchy's resume hook, haseen's or Omarchy's Limine
drop-in, `resume=` or `resume_offset=` in `/etc/kernel/cmdline`, in an
uncommented `GRUB_CMDLINE_LINUX(_DEFAULT)` line or on the running kernel's
command line, or one of the fstab comments either setup writes
(`fstab_hibernation_comment`). The GRUB and `/etc/kernel/cmdline` checks are
now computed once and reused by step 5, so a commented-out GRUB line no longer
draws a warning. The `swap_entry` flag and `fstab_has_swapfile` went: once
the check moved to signs of hibernation, nothing read them.

**Test.** `tests/test-omarchy-hw.sh`, "plain swap": the same Arch-wiki fstab
and swapfile with no hook, no drop-in and no `resume=` prints "Hibernation is
not set up", with no `swapoff` and no `btrfs subvolume delete`.

**Rejected.** Gating on the hook alone, as Omarchy does: haseen's setup adds no
hook on a systemd initramfs, so such a machine's hibernation could never be
removed.

## 3. `status` said ready, and `setup` said done, when `resume=` never reached the kernel (medium)

**Evidence.** `hibernate_cmdline` (`share/haseen/lib/hibernate.sh:82-90`) ran
`cat` on `/etc/default/limine`, every `/etc/limine-entry-tool.d/*.conf`,
`/etc/kernel/cmdline`, `/etc/default/grub` and `/proc/cmdline`, comments
included, and `hibernate_cmdline_has_resume` (`:92`) grepped the lot. When
`/etc/default/limine` has `KERNEL_CMDLINE[default]="…"`, a later `=` replaces
haseen's drop-in, which `boot_cmdline_add` already reports as status 2
(`share/haseen/lib/boot.sh:51-54`), but `bin/haseen-hibernation-setup:133`
threw that away (`|| true`) and printed "hibernation is set up" at `:140`.
The new test, against 9a9e82ab, got `ready: systemctl hibernate will work`
and `cmdline: resume set, offset 123` for that machine.

**Fix.** `hibernate_cmdline` now returns the command line the next boot gets,
as far as the bootloader lets haseen tell. On Limine it is
`KERNEL_CMDLINE[default]` as `boot_limine_merge` folds the layers, or
`boot_limine_fallback` while no layer sets the key. If a layer cannot be read
it returns nothing, so the machine reads as not ready. On GRUB it reads only
the uncommented `GRUB_CMDLINE_LINUX(_DEFAULT)=` values, plus the running
kernel's. On systemd-boot it reads the uncommented `/etc/kernel/cmdline`,
where `boot_cmdline_add` writes, plus the running kernel's. Setup keeps
`boot_cmdline_add`'s status and still rebuilds the initramfs for the resume
hook. When the status is not 0 it warns "hibernation is not set up yet",
names the words to add, and exits 1. A rerun is not stopped by "already set
up" any more, because `hibernate_ready` is false. The status help and
`docs/architecture.md` ("Kernel command line") say so.

**Test.** `tests/test-hibernation.sh`: with a replacing `/etc/default/limine`
status exits 1 and prints "no resume= parameter", and the same words in `+=`
form exit 0 with "offset 123". A commented GRUB line does not count and an
uncommented one does. `setup --dry-run --yes` on the replacing machine exits
1, prints boot.sh's "replaces every drop-in" and "hibernation is not set up
yet", and never prints "hibernation is set up;".

**Limitations.** On systemd-boot with static Type 1 entries (the `options`
line), `/etc/kernel/cmdline` is not what the loader reads. Status still
trusts it, because it is where setup writes. Parsing loader entries is a
larger change, which the verifier did not trace, and setup cannot write
those entries either. The running kernel's line still counts on GRUB and
systemd-boot: a `resume=` it booted with is real for this boot.

**Rejected.** Reading only `/proc/cmdline`: right after setup, before the
reboot, status would say not ready although the next boot resumes.

## 4. `setup` looked for `swap` and created `@swap` (medium)

**Evidence.** `bin/haseen-hibernation-setup:88` checked `btrfs subvolume show
"$top/${SWAP_SUBVOL_NAME#@}"`, which is `$top/swap`, then created and mounted
`@swap` (`SWAP_SUBVOL_NAME`, `share/haseen/lib/hibernate.sh:34`). With an
existing `@swap` the create failed, and under `set -e` the script stopped
before `umount "$top"`, leaving the top-level tree mounted under `/tmp`.
With a top-level `swap` and no `@swap`, nothing was created, an fstab line for
`subvol=/@swap` with no `nofail` was appended, and `mount /swap` (`:98`) failed
after it, which leaves a line that stops the next boot. The test only ran
`--dry-run`, where `$DRY_RUN ||` skips the check.

**Fix.** The check names `$top/$SWAP_SUBVOL_NAME`. A failed create is caught
(`created`), the top level is unmounted and its directory removed, and then
setup dies with "could not create the @swap subvolume". When fstab has no
/swap line, setup mounts the subvolume by hand
(`mount -o subvol=/@swap,noatime /dev/disk/by-uuid/…`) and only then appends
the fstab line, so a line is written only for a subvolume that mounted. An
existing /swap line is mounted with `mount /swap` as before.

**Test.** `tests/test-hibernation.sh` runs setup for real with a `sudo` stub
that records and runs nothing. With `@swap` present it looks up `/@swap` and
creates nothing. With no `@swap` and a failing create it exits 1 with the
message, `umount` comes after the create, and there is no `tee -a` (fstab) and
no mount at /swap. The dry run checks that the manual mount precedes the
fstab append.

**Rejected.** An ERR/EXIT trap for the unmount: the one failing step is
handled in place, which keeps the dry-run output unchanged. Adding `nofail` to
the new line: it would hide a missing image area at boot instead of refusing
to write the line.

## 5. The status help compared swap with RAM (low)

**Evidence.** `bin/haseen-hibernation-status:18-20` said swap must be "at
least as large as RAM". `hibernate_ready` compares it with
`/sys/power/image_size` (`share/haseen/lib/hibernate.sh:130-132`), 2/5 of RAM
by default, on purpose, to match upstream.

**Fix.** The help now says swap must hold at least `/sys/power/image_size`
(2/5 of RAM by default), and that the command line checked is the one the
next boot gets (finding 3).

**Test.** `tests/test-hibernation.sh` checks that `--help` names
`/sys/power/image_size` and no longer says "as large as RAM".

## 6. `limine-hash-assets.sh` rewrote limine.conf without Limine's lock (low)

**Evidence.** `share/haseen/layers/secureboot/limine-hash-assets.sh:23` built
a plan of line numbers from one read. awk read the file again and the
temporary file was renamed over it (`:36`), and no lock was taken.
limine-entry-tool and limine-snapper-sync write limine.conf under
`/run/lock/boot-partition.lock` (`BOOTMENU_LOCK`,
`share/haseen/lib/bootmenu.sh:32`), and `share/haseen/lib/limine-header.sh`
takes it for this reason (plan 104). `sb_limine_assets` runs before
`limine-enroll-config`, so a config damaged in that window would be enrolled.

**Fix.** The helper sources `bootmenu.sh` for `BOOTMENU_LOCK` and takes the
lock with `flock -w 30` on fd 9 before it computes the plan. It holds the lock
through the rename, as limine-header.sh does. It also refuses a symbolic link
for CONF, as limine-header.sh does.

**Test.** `tests/test-secureboot.sh`: the lock file exists after a run, and no
temporary file is left. While a background shell holds the lock, `timeout 1`
on the helper ends with 124 and the config is byte-identical. A symlinked
config is refused, and its target is left alone.

**Rejected.** Planning and rewriting from a single in-memory read without the
lock: other writers could still rename over the file between the read and the
rename.

## 7. `haseen secureboot sign` ran real steps under HASEEN_SYSROOT (medium)

**Evidence.** `bin/haseen-secureboot-setup:70-78` and `bin/haseen-setup-boot-menu`
refuse a real run under `HASEEN_SYSROOT`, because the sysroot redirects reads
only. `bin/haseen-secureboot-sign` had no such check, and
`sb_reexec_as_root` returns early under a sysroot
(`share/haseen/layers/secureboot/secureboot.sh:840`). So `sb_root` would run
`sudo sbctl sign -s …`, `sbctl sign-all`, `limine-hash-assets.sh` and the
fallback `cp` on this machine, from the fixture's facts. The new test, against
9a9e82ab, reached the stub sudo (`STUB-CALLED: sudo …`).

**Fix.** After the hook's quiet exits (no UEFI, no sbctl or no keys, so a
pacman hook with a stray sysroot still exits 0), sign refuses a non-dry run
under a sysroot with setup's exact condition and exception: the tests'
recorder (`HASEEN_TEST_STUBBED_SUDO=1`, not root, `sudo_is_test_stub`). The
`sudo_is_test_stub` comment names sign among its callers.

**Test.** `tests/test-secureboot.sh`: with `HASEEN_TEST_STUBBED_SUDO` unset
and a stub sudo that fails loudly, `HASEEN_SYSROOT=<sd-on fixture> haseen
secureboot sign` and `… sign --hook` both exit 1, say "describes another
system" and never reach sudo.

**Rejected.** Refusing in `common.sh` for every command: other commands' tests
rely on the recorder, and the change would widen to the whole suite.

## Verification

- `tools/lint.sh`: lint OK.
- `tests/run.sh --affected 9a9e82ab62ed9c65083b56d6c9c488e62736d875`: 22
  files (the three above plus the suites that cover `hibernate.sh`,
  `secureboot.sh` and the Omarchy shims), 3817/3817 passed.
- `tools/check-docs.sh`: OK.
- Each new check fails on 9a9e82ab's sources. With this plan's tests copied
  onto a detached 9a9e82ab worktree: test-hibernation 53/66 (13 failures),
  test-omarchy-hw 275/281, test-secureboot 270/280.
