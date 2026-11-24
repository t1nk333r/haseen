# Plan 185: the package and root helpers keep their promises

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. `common.sh` is sourced by every command; an unknown
  `DRY_RUN` or `ASSUME_YES` value in the environment now stops a command that
  used to run on. AUR builds now ask for sudo afresh, and under `--yes` a
  build whose dependencies cannot be read is refused.
- **Depends on**: 023 (Chaotic-AUR), 024 (`[omarchy]`), 037 (the closure
  guard), 093 (setup commands), 101 (polkit faillock), 103 and 111
  (`run_cold`)
- **Category**: install, security
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor read-only audit of 2026-11-24)
- **State**: DONE 2026-11-24 (`tests/test-core.sh` 159/159 after the
  review round,
  `tests/test-menu.sh` 334/334, `tests/test-omarchy-remove.sh` 169/169,
  `tests/test-catalog.sh` 220/220, `tests/test-desktop.sh` 230/230; the
  affected selection is the whole suite, because `share/haseen/lib/common.sh`
  is a global path: 20823/20848, every other failure the same on 9a9e82ab
  here, see Notes)

## Problem

The audit ran before pull requests #140-#142 (plans 182-184) merged. Every
finding below was re-checked on 9a9e82ab, main with them: they change none
of these lines (plan 183 adds only its self-update helpers to `common.sh`).
Line numbers are 9a9e82ab's. Several findings are one defect seen by two or
more auditors; each group below says how many.

### 1. A dry run plans `aur:` entries as AUR builds after the chaotic layer

`pkg_source` (`share/haseen/lib/packages.sh:221-235`) asks `chaotic_enabled`,
which reads pacman.conf. In a dry run the chaotic layer only prints its
stanza (`chaotic/layer.sh:56`, `append_root_file`), so desktop's `aur:ttfx`
and `aur:bibata-cursor-theme` went to the AUR list, and on Arch with no paru
or yay `pkg_install_aur` reached `die "AUR packages needed ... neither paru
nor yay is installed"` (`packages.sh:274-281`): `./install.sh --dry-run`, the
README's "print the full plan; change nothing", aborted. On CachyOS it
printed a paru build the real run never does. `pkg_install_omarchy` already
handles this for omarchy-repo with `_omarchy_repo_applied_before`
(`packages.sh:324`); nothing did it for chaotic.

### 2. AUR builds ran with sudo's timestamp warm (two findings)

`pkg_install_aur` runs `run_root pacman -S` for the repo part
(`packages.sh:264-266`) and then `run "$helper" -S` (`:284`). A PKGBUILD's
`sudo` in `build()` found the cached authorization and ran as root without a
prompt. `run_cold` exists for exactly this (plan 103), but only
`bin/haseen-update` used it; `docs/architecture.md:97` claimed it for "an AUR
helper's PKGBUILDs", and plan 103's "Remaining" recorded the gap.

### 3. `DRY_RUN=1` ran the real commands

`common.sh:19` took `DRY_RUN` from the environment and every helper runs it
(`if $DRY_RUN`). `DRY_RUN=1` runs the command `1`, which is not found; the
`if` takes the else branch, and the helper mutates. Reproduced with 9a9e82ab's
`common.sh` copied to a scratch directory:

```
$ DRY_RUN=1 bash -Eeuo pipefail -c 'source ./common.sh; run touch "$PWD/mutated"'; echo rc=$?
./common.sh: line 205: 1: command not found
rc=0
$ ls mutated
mutated
```

`DRY_RUN=yes` is worse: `yes` never ends.

### 4. AUR builds skipped the omarchy closure guard

`pkg_guard_closure` ran on the binary part only (`packages.sh:258-261`); the
helper then installed an AUR build's dependencies itself, `--noconfirm` under
`--yes`. A build depending on `omarchy-settings` with `[omarchy]` enabled
would install it unasked, against the CLAUDE.md rule, and
`share/haseen/omarchy/bin/omarchy-pkg-aur-add:6-9`, which always passes
`--yes`, claimed the opposite. Plan 037's "Open" recorded the gap.

### 5. Four setup commands bypassed `pkg_install` (three findings)

`bin/haseen-setup-ssh-agent:25`, `bin/haseen-setup-sshd:33`,
`bin/haseen-setup-fingerprint:71` and `bin/haseen-setup-fido2:44` ran
`run_root pacman -S --needed --noconfirm` directly: no `PKG_DENY` check, no
closure guard, and pacman's prompt suppressed without `--yes`.

### 6. `write_root_file` widened `/etc/sudoers.d` to 0755

`common.sh:329` always ran `sudo install -d -m 0755 "$(dirname "$dest")"`,
and GNU install chmods a directory that exists: `mkdir d && chmod 0750 d &&
install -d -m 0755 d && stat -c %a d` prints `755`. `haseen setup
passwordless-sudo` writes `/etc/sudoers.d/90-haseen-$user`, so Arch's 0750
directory became 0755 and pacman reports the mismatch on the next sudo
upgrade.

### 7. `sudo` called directly in two layers (four findings)

`chaotic/layer.sh:48` and `omarchy-repo/layer.sh:55` ran `sudo pacman-key
--finger` outside `common.sh`; they were the only command-position `sudo`
outside it, and no test enforced the rule.

### 8. `[chaotic-aur]` went after `[omarchy]`

`resolve_layers base omarchy-repo desktop` gives `base omarchy-repo chaotic
desktop`, and the chaotic layer appended its stanza after `[omarchy]`, so
`[omarchy]` stopped being last and `haseen layer status omarchy-repo` warned
with nothing to fix it.

### 9. `haseen install aur --dry-run` described a direct paru build

`bin/haseen-install:84` printed `then: paru -S --needed <picked>`; the real
path is `pkg_install_aur`, with the source order and the guards.

### 10. `haseen setup fido2` never configured polkit on current Arch

`pam_prepend` read only `/etc/pam.d/polkit-1` and returned 0 when it was
missing (`bin/haseen-setup-fido2:30-31`). polkit 128 ships its stack in
`/usr/lib/pam.d/polkit-1` only, so the command changed sudo, said "FIDO2 key
set up" and left polkit on the password. `bin/haseen-setup-fingerprint:46`
had the same flaw, and `tests/test-menu.sh:443` asserted the skip.

### 11. The sshd drop-in lost to every earlier drop-in

sshd keeps the first value it reads, and Arch's `sshd_config` includes
`sshd_config.d/*.conf` in name order at its top. `90-haseen.conf`
(`bin/haseen-setup-sshd:10`) therefore lost to a `50-cloud-init.conf` with
`PasswordAuthentication yes`, while the command reported key-only logins.

## Decision

1. `pkg_source` returns `chaotic` for every entry no official repo carries
   when a dry run applies the chaotic layer before the current one
   (`_layer_applied_before chaotic`, the old `_omarchy_repo_applied_before`
   generalised). Chaotic's database cannot be read before it exists, so
   `pkg_install_aur` says so: "planned from Chaotic-AUR, which this run
   enables first: ... (a package it does not carry goes on to [omarchy] or
   the AUR)".
2. The helper runs through `run_cold`, with `--sudo sudo` and no sudo loop
   (`--nosudoloop` for paru, `--sudoloop=false` for yay), as
   `bin/haseen-update` does. The options go after the targets, so the plan
   still reads `paru -S --needed NAME`. The architecture contract now names
   both callers.
3. `common.sh` reads `DRY_RUN` and `ASSUME_YES` once: `true`, `1`, `yes`,
   `on` become `true`; `false`, `0`, `no`, `off` and empty become `false`;
   anything else stops with `Error: DRY_RUN=maybe is neither true nor false`.
4. `pkg_guard_aur_closure` runs the same guard over what building the AUR
   targets would install: each target's `Depends On`, `Make Deps` and `Check
   Deps` from `$helper -Si --aur` (the AUR's RPC, `LC_ALL=C`), each
   dependency not installed yet expanded by `pkg_closure` when a sync repo
   has it and followed through the AUR when only the AUR has it. The guard
   body is shared (`_pkg_guard`). Under `--yes`, a closure that cannot be
   read (no helper, the AUR unreachable) is refused, since nothing would
   check it; without `--yes` the helper lists the dependencies and asks. A
   live dry run does not ask the network and says what it would check; a
   fixture's `var/lib/pacman/sync/NAME.deps` answers under a sysroot, the
   `pkg_closure` convention. Checked live, read-only: `pkg_aur_closure
   hyprmod` with yay listed `hyprmod`, its AUR-only `python-hyprland-*`
   dependencies and the uninstalled repo build tools.
5. The four setup commands source `lib/packages.sh` and call `pkg_install`;
   pacman asks unless `--yes`. `haseen setup ssh-agent` gains `--yes` in its
   usage.
6. `write_root_file` creates the parent only when it is missing.
7. Both layers call `run_root pacman-key --finger`. `tests/test-core.sh` now
   fails on any shell line outside `common.sh` with `sudo` in command
   position, after leaving out quoted text, comments and heredocs; on
   9a9e82ab it prints exactly the two layer lines.
8. When `[omarchy]` is already in pacman.conf, the chaotic layer writes
   pacman.conf with the `[chaotic-aur]` stanza before the `[omarchy]`
   section (read whole first, because the write truncates the file). A dry
   run that applies omarchy-repo first says it would do the same. When pacman
   lists `[omarchy]` but the file has no plain `[omarchy]` line to put the
   stanza before (an `Include`d file, or a header with more on the line), the
   layer warns and appends the stanza, as it does without `[omarchy]`.
9. The picker's dry-run line reads `then: haseen install aur <picked> (an
   official repo, Chaotic-AUR, [omarchy], the AUR last)`.
10. `pam_prepend`, in both commands, falls back to the vendor stack in
    `/usr/lib/pam.d/NAME` and writes it, with the line first, to
    `/etc/pam.d/NAME`, which PAM reads instead. The vendor stack includes
    `system-auth`, so faillock stays (the stack plan 101's migration
    repairs is never written). `haseen setup fido2` warns when a service has
    neither file; fingerprint keeps skipping a missing hyprlock stack.
11. The drop-in is `01-haseen.conf`; `haseen setup sshd` removes
    `90-haseen.conf` and reloads a running sshd (`enable --now` leaves one on
    its old settings). The migration `1795510988-sshd-dropin-first.sh`
    renames the old drop-in on machines set up before, only when its first
    line is the command's own, and runs `systemctl try-reload-or-restart`.
    `omarchy-remove-security-sshd` removes both names.

## Tests

Every new assertion below failed on 9a9e82ab (the tests copied into a
detached worktree of it): 20 in `tests/test-core.sh`, 15 in
`tests/test-menu.sh`, 1 in `tests/test-omarchy-remove.sh`, 2 in
`tests/test-catalog.sh`.

- `tests/test-core.sh`: the cold run (`DRYRUN: sudo -k`, then the helper with
  `--sudo sudo --nosudoloop`); a fixture build depending on
  `omarchy-settings` refused under `--yes`, with the closure listed, and
  warned about without it; a dry run with `HASEEN_APPLY_LAYERS="base chaotic
  desktop"` planning `chaotic-aur/ttfx` and no build, and still the AUR when
  chaotic comes after the layer; the `[chaotic-aur]` stanza written before
  `[omarchy]`, and the dry-run line for `omarchy-repo chaotic`; the stanza
  appended, with a warning and no rewrite, when `omarchy_repo_enabled` holds
  but pacman.conf has no `[omarchy]` line (the review round's case);
  `DRY_RUN=1`
  planning without touching anything, `DRY_RUN=maybe` stopping, `0` and
  `yes` read as false and true; a real `write_root_file` (sudo stubbed to run
  the command) keeping a 0750 parent and creating missing ones; the sudo
  scan.
- `tests/test-menu.sh`: each setup command plans `pacman -S --needed` without
  `--noconfirm` (and with it under `--yes`); fido2 and fingerprint write
  `/etc/pam.d/polkit-1` from a vendor fixture stack, line first, and fido2
  names a service with neither file; sshd writes `01-haseen.conf`, removes
  the old name and reloads; the migration renames the command's file, leaves
  a foreign one and does nothing without one.
- `tests/test-omarchy-remove.sh`: both drop-in names are removed.
- `tests/test-catalog.sh`: the picker's dry-run line.
- `tests/test-desktop.sh`: the gaming layer on Arch (apply order `base
  chaotic desktop gaming`) now plans `chaotic-aur/lib32-nvidia-580xx-utils`
  where it planned a paru build; the expectation follows decision 1.

## Review

An independent Sonnet review of the first head approved it with three nits.

- The chaotic layer put the stanza only before a line that is exactly
  `[omarchy]`, while `omarchy_repo_enabled` reads `pacman-conf --repo-list`
  on a live system, which also counts a repo from an `Include`d file. The awk
  then inserted nothing, `write_root_file` rewrote pacman.conf unchanged and
  the layer went on without Chaotic-AUR. Fixed as decision 8 now says: the
  layer checks that the rewritten text has a `[chaotic-aur]` line and
  otherwise warns and appends. Run against the first head's layer, the new
  `tests/test-core.sh` case printed `DRYRUN: write /etc/pacman.conf` with no
  stanza; it now prints the append.
- `pkg_aur_closure` cannot read a dependency that only an AUR package
  provides under another name, so `--yes` refuses that build. Kept: it fails
  safe and the message says to run without `--yes`. An AUR provides lookup
  is the fix if it shows up in practice.
- After `setup fido2` or `fingerprint` wrote `/etc/pam.d/polkit-1` from the
  vendor stack, the remove commands take the line out and leave an `/etc`
  copy that later polkit updates no longer change. Kept: the copy includes
  `system-auth` and behaves like the vendor file, and the remove commands
  cannot tell a copy haseen wrote from one the user made with the same
  bytes, so deleting it is not theirs to decide.

## Rejected

- **Dropping `--noconfirm` for AUR builds under `--yes`** (the finding's
  fallback): an unattended `install.sh --yes` would stop at the helper's
  prompt.
- **Checking only an AUR build's direct dependencies**: the helper installs
  the whole closure, and an AUR-only dependency can bring `omarchy-settings`
  in one level down.
- **Running the AUR guard before every pacman step**: reading the closure
  needs a helper, and on Arch the helper itself comes from Chaotic-AUR in the
  same call; the binary part has its own guard first.
- **A read-only root helper in `common.sh` for `pacman-key --finger`**:
  `run_root` already passes stdout through, and the call sits in the
  non-dry-run branch.
- **Making omarchy-repo require chaotic, or reordering `resolve_layers`**:
  omarchy-repo is a source on its own (Arch without Chaotic-AUR); the
  stanza's place is what matters.
- **Warning about earlier sshd drop-ins instead of renaming**: the command
  would still report key-only logins it does not enforce. `01-` still loses
  to a `00-` drop-in, which nothing ships.
- **Writing `/etc/pam.d/polkit-1` from scratch** (what Omarchy's old command
  did): it dropped `system-auth` and with it faillock (plan 101).
- **Treating unknown `DRY_RUN` values as true**: a typo would then hide a
  real run the user asked for; stopping says what is wrong.

## Notes

- Plan 103's "Remaining" item and plan 037's "Open" item on AUR builds are
  closed by this plan.
- The affected selection for this change is the whole suite: `common.sh` is
  a global path (plan 100). Run on this laptop it passed 20823 of 20848
  checks. One failure was `tests/test-desktop.sh`'s gaming expectation,
  updated above. The rest fail the same way on 9a9e82ab here:
  `test-idle.sh`, `test-pager.sh` (`tst_security.qml`),
  `test-vapt-security-ui.sh`, `test-vapt-ui-adversarial.sh` and
  `test-vapt-panel-conformance.sh` (Qt cannot create an OpenGL context
  offscreen, "QRhiGles2: Failed to create context", exit 134), and
  `test-agent-accounts.sh` "and says where a plain CLI follows it" (this
  host's mise shims change the message). `test-menu-back.sh` failed only on
  the worktree's long socket path and passes, 34/34, from a short bind mount.
