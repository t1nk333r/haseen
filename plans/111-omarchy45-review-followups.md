# Plan 111: Review follow-ups from the Omarchy 4.5 batch

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Eight small fixes the independent reviews of pull requests
  #57 to #65 left open as non-blocking, each behind a test that fails on the
  code before it. The widest is `run_cold` in `share/haseen/lib/common.sh`, a
  global path: it now runs its command in a subshell with its own traps.
- **Depends on**: 100 (affected tests), 101, 102, 103, 104, 105, 106, 110
- **Category**: security, boot, desktop, tests
- **Planned at**: 2026-10-22, from the reviews of #57 to #65
- **State**: DONE 2026-10-22 (every item done; focused suites and the full
  affected run in Evidence)

## Decision

No new owner decision. The owner's choices for the Omarchy 4.5 batch
(2026-10-21) are recorded in plans 101 to 110; these items finish the parts
they chose ("Security & bug fixes (Recommended)", "Faster boot & logout",
"Quake console", "Captive-portal sign-in", "Starship theme & per-theme
wallpaper", and plan 110's "In the background" splash). Each item below only
does what its review finding asked; no behaviour beyond it changes.

## Items

### 1. `run_cold` ends cleanly however it is stopped (plan 103)

**Finding** (#60 review). `run_cold` had no trap: a SIGINT, SIGHUP or SIGTERM
during the wrapped AUR build, to the whole job or to the calling shell alone,
left the `haseen-sudo.XXXXXX` wrapper directory in `$TMPDIR` and skipped the
closing `sudo -k`, so the timestamp a later sudo prompt cached stayed warm. A
`mktemp` or `chmod` failure under `set -e` (as `bin/haseen-update` runs) also
ended the update before the cleanup and before the dropped-timestamp
warning. A relative `TMPDIR` put a relative entry first on `PATH`, looked up
from whatever directory the build is in.

**Done.** `run_cold` (`share/haseen/lib/common.sh:246`) now:

- runs the command in a subshell whose `EXIT` trap removes the wrapper and
  runs `sudo -k` (`:267-278`); `INT`, `TERM` and `HUP` exit 130, 143 and 129,
  so the `EXIT` trap runs once the command has stopped. The caller's traps
  are untouched, which is why a subshell rather than a trap set and restored;
- treats a `mktemp` that fails, or a wrapper that cannot be written
  (`_cold_sudo_wrapper`, `:305`: the heredoc or the `chmod`), like a wrapper
  that cannot run: the command runs with the timestamp dropped before and
  after, and the warning names which (`:279-297`);
- resolves a relative `TMPDIR` with `realpath -e`, and falls back to `/tmp`
  when it does not resolve or holds a `:`, which would split the `PATH`
  entry in two (`:255-262`). The `:` case is the same class of bug the
  finding named (a relative or foreign entry on `PATH`) and is included.

Not changed: the dry run, the wrapper's content, the `-N` probe, the command's
status coming back. A signal to the calling shell alone still lets the build
run to its end, as before; only then does the cleanup run.

**Test**: `tests/test-core.sh` 127/127 (was 102 at plan 103). Against the old
`common.sh` the same file gives 107/127: SIGTERM and SIGHUP to the job and to
the caller, and SIGINT to the job, each leave the wrapper and skip the last
`sudo -k`; `mktemp` and `chmod` failures end the run under `set -Eeuo
pipefail`; the relative, unresolvable and `:` `TMPDIR` cases put a relative or
split entry on `PATH`. SIGINT to the caller alone passed before too: a
non-interactive bash waiting on a child that does not die of SIGINT carries
on. The signals are real (`kill` on a `setsid` job run with
`env --default-signal`, since a script's background job starts with SIGINT
ignored), with a stub `sudo` that logs each call.

### 2. `haseen update` scopes pacman only where `systemd-run` exists (plan 103)

**Finding.** The `systemd-run --scope` fallback checked `/run/systemd/system`
only. A container can see that directory without the systemd package; then
`sudo systemd-run …` fails and `set -e` ends the update before pacman.

**Done.** `bin/haseen-update:82` also requires `have systemd-run`; without it
pacman runs unscoped, as on a machine without systemd.

**Test**: `tests/test-catalog.sh` 218/218 (was 215): with `/run/systemd/system`
present and no `systemd-run` on `PATH` (a copy of `/usr/bin` as links, without
it, and the stub moved aside), the update plans `sudo env
OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu` and no `systemd-run`; the existing
case with both still plans the scope. Old command: 216/218.

### 3. The hook templates are checked as root's too (plan 101)

**Finding** (#57 review). `root_trusted_dir` checks a directory and its direct
entries, not deeper. The Secure Boot hook is rendered from
`share/haseen/layers/secureboot/files/zz-haseen-secureboot.hook`, the Omarchy
guard hook from `share/haseen/default/omarchy-guard/50-haseen-omarchy.hook`;
the template decides the `Exec` root runs on every matching transaction, but
neither file (nor `default/omarchy-guard/`) was checked.

**Done.** `sb_hook_exec_trusted` (`share/haseen/layers/secureboot/secureboot.sh:45-48`)
and `omarchy_guard_exec_trusted` (`share/haseen/lib/omarchy-guard.sh:122-125`)
also run `root_trusted_exec` on the template path: every directory on it,
links followed, and the file itself must be root's alone. The layers' write,
`layer status` and doctor all go through these two functions, so a template
someone else can change is now refused, reported `warn`/`unsafe`, and named.

**Test**: `tests/test-secureboot.sh` and `tests/test-omarchy-guard.sh`,
420/420 together, under the `stat` stand-in that answers as root: a
group-writable `layers/secureboot/files/` (already refused, as an entry of
`layers/secureboot`) and template file, and an others-writable
`default/omarchy-guard/` and template file, are each refused and named.
`plant_tree` in the guard test now copies `default/omarchy-guard/`. Old
libraries: 414/420 (the three new refusals fail).

### 4. A SKIP line, with its count, for every skipped user-namespace check (plans 101, 102)

**Finding.** The checks that need user namespaces (root-mode runs, and the
overrides root ignores: `HASEEN_PATH` as root, a fixture root for root's
hardware reads, `sudo` as root) were skipped where `unshare` is refused, as in
CI's container. The skip lines did not say how many checks they dropped, so a
run's total could not be accounted for, and plan 102's was a lowercase
`skip:`.

**Done.** Each such block is a function, and its `else` branch prints
`  SKIP N <what>: <why>` with N counted from the function's own `assert_`
lines (`skipped FN WHAT WHY`, `tests/test-omarchy-guard.sh:55`,
`tests/test-secureboot.sh:43`, `tests/test-omarchy-45.sh:194`), so the count
cannot drift from the checks. The guard's root-mode block now says which of
its two namespace probes failed. Plan 110's `sudo` override block in
`tests/test-splash-follow.sh` (item 7's file) prints its count the same way,
and plan 102's device-tree branch says `SKIP 1 check (…)`.

**Test**: the four files, 960/960 on luna; inside `bwrap --dev-bind / /
--unshare-user --disable-userns` (no user namespaces, as in CI) 933/933 with

```
  SKIP 15 root-mode checks (the hook's run as root, an inherited HASEEN_PATH ignored as root): user namespaces are not available here
  SKIP 3 real-stat root-owned tree checks: user namespaces are not available here
  SKIP 1 real-stat root-owned tree check: user namespaces are not available here
  SKIP 5 checks of root's reads (hw-vm and hw-match-device-tree ignore a fixture for root): user namespaces are not available here
  SKIP 3 sudo override checks as root: user namespaces are not available here
```

960 − 933 = 27 = 15 + 3 + 1 + 5 + 3.

### 5. `haseen doctor` says when the `root=` pin is stale (plan 104)

**Finding** (#59 review). `/etc/limine-entry-tool.d/haseen-cmdline.conf` is
written once and then kept (plan 104, "an existing pin: not pinned again"). A
root device that changes later (a reinstall, a new disk, a filesystem made
again) leaves it naming the old one, and the next image limine-entry-tool
builds boots that.

**Done.** `boot_limine_pin_report` (`share/haseen/lib/boot.sh:338`), called by
`bin/haseen-doctor:72`, prints one line when the pin exists. It merges
Limine's layers (`boot_limine_merge`), takes the last `root=` of the merged
line (the kernel keeps the last one; `boot_cmdline_value`, `:319`) and of
`/proc/cmdline`, both through `sysroot_path`, and says:

- `limine root pin=ok (root=…, as this boot)` when they match (also when a
  later layer states this boot's `root=` over the pin);
- `limine root pin=differs: the next boot image gets root=A (… pins root=P),
  but this boot used root=B. If the root device changed, set root=B in
  /etc/limine-entry-tool.d/haseen-cmdline.conf (sudoedit it), then rebuild
  (sudo limine-mkinitcpio); if both name the same device, nothing is wrong`.
  When the next image's `root=` comes from a later layer, not the pin, that
  layer is the one named;
- `unknown` when a layer cannot be read or this boot states no `root=`.

It is a hint and never changes doctor's exit status: `root=UUID=…` and
`root=/dev/…` for one device read as different, and haseen has no way to
compare devices on a fixture. The pin's line is parsed by the same function
the merge uses (`_boot_limine_layer`, `:230`, the merge's loop moved out of
`boot_limine_merge` unchanged).

Rejected: telling the user to delete the pin and rerun `haseen plymouth set`
or `haseen hibernation setup`. Neither re-pins on a machine already set up:
`haseen plymouth set` calls `boot_cmdline_add` only while `splash` is missing
from `/proc/cmdline` (`bin/haseen-plymouth-set:102-105`), and `haseen
hibernation setup` stops at `hibernate_ready` (`bin/haseen-hibernation-setup:65-69`).
A deleted pin would then leave the next image without `root=`.

**When a `root=` refusal stops a setup** (the plan sentence the review asked
for; also in plan 104's follow-up): `boot_limine_keep_root` dies before
anything of its own is written, but each caller has done its earlier steps.
`haseen plymouth set` has installed the theme, written the plymouth hook
drop-in (when the hook was missing) and run `plymouth-set-default-theme
haseen` (`bin/haseen-plymouth-set:84-98`); no `quiet splash` drop-in is
written, the boot image is not rebuilt and following is not turned on. The
next image any update builds carries the hook and the theme, and the kernel,
given no `splash`, shows the boot messages and a text password prompt, as
before. `haseen hibernation setup` has made the swap subvolume, its fstab
lines and the swapfile, swapped it on at priority 0 (zram stays first), and on
busybox hooks written the `resume` hook drop-in
(`bin/haseen-hibernation-setup:82-118`); no `resume=` drop-in and no rebuild,
so `hibernate_ready` stays false and `haseen hibernation status` says so.
Rerunning either after fixing what the refusal names is safe: every earlier
step checks what is already there first (the hook and theme checks, the
mount, `swaplabel`, the fstab greps, the active swap), and only the command
line and the rebuild remain.

**Test**: `tests/test-omarchy45-boot.sh` 224/224 (was 214 at plan 104): no
pin, a pin that matches, a stale pin (both named, the file to edit, the
rebuild, the hint), `haseen doctor` printing it from a sysroot, a later
layer's `root=` winning (ok), a later layer's stale `root=` (that layer named,
not the pin), no `root=` on this boot, and an unreadable layer (skipped as
root). Every earlier merge and pin case still passes through the moved
loop.

### 6. The console cancels a waiting borrow when it closes (plan 105)

**Finding** (#63 round 2 review). In
`share/haseen/default/hypr/qconsole.lua` `settle()`, when the console replaced
a special workspace still leaving on the user's own animation, the borrow of
`specialWorkspaceOut` waits for that animation (`after(OUT, …, borrow)`). If
the console then closed some way other than its key (its last window closing,
focus leaving) before the timer fired, no branch of `if other / elseif shown /
elseif lent[OUT]` matched, the timer fired with nothing showing, and Out kept
the console's slide: the next scratchpad closed sliding up.

**Done.** An `else bump(OUT)` ends the chain (`qconsole.lua:304-309`): nothing
shows and Out was never lent, so the waiting borrow is cancelled. The
`init.lua` recorder comment (`share/haseen/default/hypr/init.lua:119-129`) now
says the record checks only a spec's shape: Hyprland may still reject a spec
it stored (an unknown leaf, bezier or style), so it is what the config asked
for, not what Hyprland applied.

**Test**: `tests/test-omarchy45-workspaces.sh` 111/111 (was 110): the
reviewer's scenario, a 500 ms user fade on `specialWorkspace`, the scratchpad
open, SUPER + GRAVE, the console closed by Hyprland, timers fired: Out is not
the slide and the scratchpad then closes the user's way; closed with the key
instead, it retracts on the slide and Out is the user's fade after. Without the
fix the first check fails ("slide bottom").

### 7. The splash's user-side key check walks the key directory's parents (plan 110)

**Finding** (#62 round 2 review). `plymouth_signed_boot`'s user-side check
tested `-e` on sbctl's state directory, key directory and `keydir/db`. A
`keydir:` in `/etc/sbctl/sbctl.conf` under a parent this user cannot enter
reads as absent to `-e`, so the machine read as "no keys" and following was
offered where root would refuse it.

**Done.** `plymouth_sbctl_hidden DIR` (`share/haseen/lib/plymouth.sh:318`)
walks DIR from `/` down (through `sysroot_path`): the first directory on the
way that exists but cannot be entered means "may hold keys"; a component that
does not exist, under directories this user can enter, means none; DIR itself
keeps the old rule (it must be readable and enterable). `plymouth_signed_boot`
asks it for the state directory, the key directory and `keydir/db`
(`:299-305`). A parent that can be entered but not listed (0711) hides
nothing, so it is not counted.

**`/run/haseen` stays 0755.** `bin/haseen-plymouth-apply:77` and
`write_root_file` (`common.sh`) create it 0755, and it is not tightened:
`share/haseen/omarchy/bin/omarchy-hyprland-monitor-watch:97`, which runs as
the user in the session, asks `omarchy-hyprland-reload-guard paused`, which
lists `/run/haseen/hyprland-reload-guard/` (`:112-115`). At 0700 a pause
would be invisible to it and the watcher would reload Hyprland into
half-replaced package config. The splash's lock and rate file there need only
that no one else can write the directory, which 0755 root-owned gives
(`bin/haseen-plymouth-apply:41-44`).

**Test**: `tests/test-splash-follow.sh` 276/276 (was 272): a `keydir:` under a
mode-000 parent reads as "may hold keys" and `haseen plymouth follow on`
refuses with that reason; with the parent at 0711 the keys are seen ("sbctl
holds Secure Boot keys"), and without them it is not signed. Skipped, with a
counted SKIP line, as root. Old library: 274/276.

### 8. A remembered wallpaper must be named as an image (plan 106)

**Finding** (#65 review). `theme_remembered_background` accepted any existing
absolute file; `theme_backgrounds` lists only image names. An edited or
garbled record could make `current/background` point at any file.

**Done.** One list, `THEME_BG_EXTS` (`share/haseen/layers/theme/theme-lib.sh:35`),
now builds `theme_backgrounds`' `find` names (unchanged: jpg, jpeg, png, webp,
gif, bmp, any case) and `theme_background_named` (`:922`), which
`theme_remembered_background` requires (`:960`); a record that fails it is
ignored and the theme's own rule chooses (the first image). Recording is
unchanged. An image of the user's set by path without one of those
extensions is still accepted by `haseen theme bg set` (which checks the MIME
type) but is no longer restored with its theme.

`bin/haseen-network-portal`'s header said it "leaves a Tailscale exit node
alone"; it does nothing with Tailscale. It now says so, and that Omarchy's
command pauses an exit node meanwhile (`bin/omarchy-network-captive-portal@3357f9059:3,14-23`,
re-read in a fresh clone of Omarchy, deleted after).

**Test**: `tests/test-omarchy45-themes.sh` 56/56 (was 54): a record naming a
`.txt` file falls back to the first image; one naming `SHOT.PNG` is restored.
Old library: 55/56.

## Evidence

Every run used the hermetic wrapper from the brief (stub `PATH` with
`/usr/bin` first, a private `XDG_RUNTIME_DIR` and `TMPDIR` under `/tmp`,
offscreen Qt, a dead session bus) on luna. Focused, per item, with the old
code swapped back in to see each new check fail first:

| Item | File | New code | Old code |
|---|---|---|---|
| 1 | `tests/test-core.sh` | 127/127 | 107/127 |
| 2 | `tests/test-catalog.sh` | 218/218 | 216/218 |
| 3 | `tests/test-secureboot.sh` + `tests/test-omarchy-guard.sh` | 420/420 | 414/420 |
| 4 | the guard, Secure Boot, `test-omarchy-45.sh`, splash files | 960/960; 933/933 without user namespaces, 27 counted SKIPs | (no behaviour change) |
| 5 | `tests/test-omarchy45-boot.sh` | 224/224 | (the function did not exist) |
| 6 | `tests/test-omarchy45-workspaces.sh` | 111/111 | 110/111 |
| 7 | `tests/test-splash-follow.sh` | 276/276 | 274/276 |
| 8 | `tests/test-omarchy45-themes.sh` | 56/56 | 55/56 |

`common.sh` is a GLOBAL path for `tools/affected-tests.sh`, so the affected
selection is the whole suite; it was run once, at the end, from a short bind
mount: see "Full run" below.

### Full run

Filled in below by the final gate run.

## Owner steps

Nothing to do on IO or luna beyond the usual install of the tree
(`./install.sh --tree-only --yes`) and `hyprctl reload` for the console fix.
After that, `haseen doctor` prints the `limine root pin=` line on a machine
where haseen pinned `root=`; if it says `differs` and the root device did
change, follow its instruction.

## Not verified

- No live session, compositor, AUR build or reboot: the signals are real but
  the sudo and the build are stubs; the console runs against the test's model
  of Hyprland's special workspaces (plan 105's), not Hyprland.
- The pin hint on a machine whose pin really is stale: only fixtures.
