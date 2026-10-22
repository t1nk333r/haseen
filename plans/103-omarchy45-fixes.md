# Plan 103: Bug and security fixes surfaced by Omarchy 4.5

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW-MEDIUM (one new `common.sh` helper that wraps sudo for code haseen did not write; `haseen update` now prompts again for each sudo an AUR build runs; the rest are small fixes behind existing tests: two binds, the pager, the calendar grid, the lock field, the greeter's config and one new seed that writes only when the user has no portal config)
- **Depends on**: 010 017 021 025 036 043 100
- **Category**: security, desktop, shell, update
- **Planned at**: 2026-10-22, owner decision (below)
- **State**: DONE 2026-10-22 (focused suites and `tests/run.sh --affected origin/main` in Evidence)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
and chose, verbatim:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs stay
  as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts", "1-second
  boot menu", "New binds".

This plan implements **"Security & bug fixes (Recommended)"**, the parts
outside Omarchy's commands (plan 101) and boot (plan 104): survey Part B.2
rows 1, 3, 4 and 6. Each fix is a port or reimplementation of an Omarchy
change under MIT; no new on-screen element, no new default plugin, and no
change to the owner's keys beyond what SUPER + C/V send.

## Sources

The survey (`~/.cache/haseen-wt/omarchy-45-survey.md`, Part B.2) and its notes
(`omarchy45-notes/features-*-findings.md`, `migrations-findings.md`). Every
fact used here was re-checked in a read-only clone of
github.com/basecamp/omarchy at tag `v4.5.0-rc1` (each commit below:
`git merge-base --is-ancestor <commit> v4.5.0-rc1` succeeds) and on branch
`quattro`, where `git log v4.5.0-rc1..origin/quattro` touches none of the
files ported here. Omarchy's code was read as data. The terminal defaults were
checked against the binaries and their documentation (below).

## Change

### 1. Terminal copy and paste (Omarchy 129c67e25, #12915)

`universal()` sent CTRL + Insert / SHIFT + Insert to terminals
(origin/main `share/haseen/default/hypr/binds.lua:98-99`). haseen's seeded
`share/haseen/default/foot/foot.ini` maps neither, and foot's defaults
(`man foot.ini`, foot 1.28.0) are `clipboard-copy` = Control+Shift+c,
`clipboard-paste` = Control+Shift+v and `primary-paste` = Shift+Insert. So in
foot SUPER + C copied nothing and SUPER + V pasted the primary selection.
Omarchy fixed its copy the same way at
`default/hypr/bindings/clipboard.lua@v4.5.0-rc1:46-47`; Omarchy's own
terminal configs also bind the Insert chords, haseen's do not.

Every terminal the "terminal" tag names
(`share/haseen/default/hypr/windowrules.lua:57-65`) binds the clipboard to
CTRL + SHIFT + C / V by default:

| terminal | CTRL + SHIFT + C / V | SHIFT + Insert | CTRL + Insert | checked with |
|---|---|---|---|---|
| foot 1.28.0 | clipboard copy / paste | primary paste | unbound | `man foot.ini` |
| kitty 0.49.2 | clipboard (`kitty_mod` = ctrl+shift) | `paste_from_selection` | unbound | `/usr/lib/kitty/kitty/options/definition.py:3650,3793,3811,3825` |
| Ghostty 1.3.1 | clipboard | `paste_from_selection` | `copy_to_clipboard` | `ghostty +list-keybinds --default` |
| Alacritty | Copy / Paste (Linux) | `PasteSelection` | unbound | `extra/man/alacritty-bindings.5.scd` (master) |
| WezTerm | CopyTo / PasteFrom Clipboard | PasteFrom PrimarySelection | CopyTo PrimarySelection | wezterm.org `config/default-keys` |

`share/haseen/default/hypr/binds.lua:102-103` now send CTRL SHIFT + C / V to a
terminal; other windows still get CTRL + C / V, and SUPER + X is unchanged.

### 2. `haseen update`: a cold AUR phase, and pacman in a scope (Omarchy e1614f2bd #13323, 93d9d0c85 #11651)

**Cold AUR phase.** `bin/haseen-update` (origin/main `:66,72`) ran
`paru -Sua` right after `sudo pacman -Syu`, with sudo's timestamp still warm,
so any PKGBUILD could run `sudo -n …` silently. Omarchy 4.5 ends the update's
authorization before AUR builds (`bin/omarchy-update@v4.5.0-rc1:44-71,151-153`)
and puts a wrapper first on `PATH` that adds `-N` (`--no-update`) to every
sudo (`default/omarchy/sudo-no-update/sudo@v4.5.0-rc1:13-20`), checking for
`-N` support in `sudo -h`'s usage lines
(`bin/omarchy-security-functions@v4.5.0-rc1:66-70`), and runs yay with
`--sudo <wrapper> --sudoloop=false` (`bin/omarchy-update-aur-pkgs@v4.5.0-rc1:5-15`).

haseen keeps every sudo in `common.sh`, so the wrapper is generated there:
`run_cold CMD…` (`share/haseen/lib/common.sh:230-287`) runs `sudo -k`, writes a
`sudo` that execs the real one with `-N` (the stand-alone `-k`/`-K`/`-h`/`-V`
modes alone, as Omarchy's does) into a fresh `mktemp -d`, runs CMD with that
directory first on `PATH`, removes it, and runs `sudo -k` again; CMD's exit
status comes back. The wrapper is run once with an argument only it knows
before the command; a sudo whose usage lines have no `-N` (sudo-rs, an old
sudo), or a temporary directory mounted `noexec`, gets the two `sudo -k` only,
with a warning that says which. Under `--dry-run` it prints
both drops and the command. `bin/haseen-update:82-97` runs the helper through
it as `paru --sudo sudo --nosudoloop -Sua` (yay: `--sudoloop=false`): `--sudo
sudo` makes the helper take the wrapper from `PATH` even if its config names
an absolute sudo, and the sudo loop is off because, with nothing cached, it
would only prompt again. sudo 1.9.17 on luna lists `-N` in its usage lines
(`LC_ALL=C sudo -h`: `usage: sudo [-ABbEHkNnPS] …`) but not in its option list,
which is why the check reads the usage lines. paru's flags are from its man
page (`man/paru.8`: `--sudo`, `--nosudoloop`), yay's from `man yay` (13.0.1:
`--sudo`, `--sudoloop`, and the `--<option>=false` form).

**pacman in a scope.** Upgrading systemd re-executes the system and user
managers mid-transaction, and a pacman in the session's cgroup can be killed by
that or by a logout. `bin/haseen-update:71-80` runs
`sudo [env OMARCHY_ALLOW_DIRECT_PACMAN=1] systemd-run --scope --quiet --collect
pacman -Syu` when `/run/systemd/system` (read through `sysroot_path`) is a
directory and not a link, as `bin/omarchy-update-pacman@v4.5.0-rc1:13-25`
does. `systemd-run --scope` runs pacman as its own child, so the guard's
variable still reaches the hooks.

### 3. haseen.pager: omapager's fixes since the port

Omarchy 4.5 replaced its notifications engine with omapager's (merge
03ff1eff3, #15932), the code haseen.pager is ported from (plan 025), and the
fixes now land there. Ported, each recorded in
`share/haseen/shell/plugins/haseen.pager/UPSTREAM.md`:

- **3f02f8cfc** numeric entities beyond the BMP decode whole:
  `String.fromCodePoint` (`Markup.js:40-50`; Omarchy
  `shell/plugins/notifications/Markup.js@v4.5.0-rc1:27,31`).
- **21bee67a4, security**: only a browser's leading anchor names a site as the
  sender, and only through an http(s) href whose host passes the URL policy;
  the label never stands in for the href (`Markup.js:97-115,168-207,224-233`,
  `isBrowser`, `isKdeConnect`). Before, any app's message that opened with
  `<a href="javascript:…">bank.example</a>` was filed and shown as from
  `bank.example` (origin/main `Markup.js:104-110`). The same commit's exact KDE
  Connect names (a substring match made any app named "…kdeconnect…" a phone
  multiplexer) and bounded snoozes (finite, positive, at most 366 days:
  `Service.qml:496-520,1928,2216,2227`) are ported with it. Its NUL check on
  click argv does not apply: haseen dropped the exec-argv hint (plan 025).
- **2952b1c00 + 773a1fd6c** a replaced notification (replaces_id) gets a fresh
  countdown even with the same duration, and its picture is read again
  (`Toast.qml:279-293,439,449`; Omarchy `Toast.qml@v4.5.0-rc1:213-220,395,404`).
  haseen's card reset only when the duration changed (origin/main
  `Toast.qml:279-284`). A sender's own `image://icon//` file is never cached,
  so new cover art at the same path shows.
- **329fd1a9b** the desktop-entry hint names the icon when the sender gave
  none (`Store.js:64-67`); `normalise()` already drops a path there.

### 4. Small correctness

- **Calendar in UTC (d74d6ea24, #10476).** `haseen.calendar/Calendar.js`
  built each cell at local midnight (origin/main `:43-47`), which Qt's V4
  resolves backwards where a zone starts DST at 00:00. Reproduced with
  `/usr/lib/qt6/bin/qml`: `TZ=America/Santiago` drew September 2026 as
  `30 31 1 2 3 4 5 5 7 …` and `TZ=Pacific/Apia` drew December 2011 as
  `… 29 31 31 1`. The grid now walks `Date.UTC` (`Calendar.js:44-68`), as
  Omarchy's `shell/plugins/panels/clock/Model.js@v4.5.0-rc1:243-244`. The
  heading names the month with `standaloneMonthName(month)` and `shiftMonth`
  is arithmetic, so the commit's other two halves (a noon `viewDate`, a UTC
  `stepMonth`) have nothing to fix here.
- **Lock field drops key repeat (6e15d76a6, #7806).** A wake from DPMS can
  deliver a key's release seconds late and fill the password field.
  `haseen.lock/LockView.qml:37-49,104-107`: `dropsAutoRepeat(event)` swallows
  a repeated key except Backspace and Delete, from the field's
  `Keys.onPressed` (Omarchy `shell/plugins/lock/LockView.qml@v4.5.0-rc1:69,212`).
- **Greeter keyboard layout (75b327bc2, #6896).** haseen's greeter config set
  no `kb_layout` (origin/main `bin/haseen-greeter:47-62`), so a non-US user
  typed their password in US. `bin/haseen-greeter:46-105` reads
  `/etc/vconsole.conf` through `sysroot_path` the way
  `share/haseen/default/hypr/input.lua:11-43` does and applies its rule (its
  Latin list, `us` first otherwise, `compose:caps`), so the login screen
  types exactly as the desktop does; values are quoted for Lua, so a stray
  quote cannot break the login screen's config. Omarchy did the same for SDDM
  (`default/sddm/hyprland.lua@v4.5.0-rc1:9-50`, its own non-Latin list).
- **Secret portal (6520ac7d2, #9594).** The hyprland package's
  `/usr/share/xdg-desktop-portal/hyprland-portals.conf` says
  `default=hyprland;gtk` (luna, hyprland 0.56.2-4), and neither backend
  implements the Secret portal, which gnome-keyring provides
  (`/usr/share/xdg-desktop-portal/portals/gnome-keyring.portal`, `UseIn=gnome`)
  and haseen installs (`share/haseen/layers/desktop/packages.txt:20`). So
  Flatpak apps had no keyring. Following Omarchy
  (`config/xdg-desktop-portal/hyprland-portals.conf@v4.5.0-rc1`, migration
  1788261467), the new seed `share/haseen/seeds/70-portals.sh` copies
  `share/haseen/default/xdg-desktop-portal/hyprland-portals.conf` once, and not
  at all when the user has a `portals.conf` (`man portals.conf`: the first file
  found wins, the desktop-named one first in each directory).

## Evidence

Focused suites, each run alone with the brief's hermetic wrapper:

- `tests/test-catalog.sh` 215/215 (the dry-run plan; the scope with the guard;
  no scope on a linked `/run/systemd/system`; yay's flags; a real run with a
  sudo that has `-N`: `SUDO: pacman -Syu|SUDO: -k|SUDO: -h|PARU: --sudo sudo
  --nosudoloop -Sua|SUDO: -N pacman -U …|SUDO: -N -n true|SUDO: -k|SUDO: -k`,
  the wrapper removed; one without `-N`: the warning and both drops)
- `tests/test-core.sh` 102/102 (`run_cold`: order, status, cleanup after a
  failure, a sudo path with a quote and a space, a wrapper that cannot run,
  the dry run)
- `tests/test-keybinds.sh` 123/123 (the shipped SUPER + C/V/X under a stub
  `hl`: CTRL SHIFT C/V in a tagged terminal, CTRL C/V elsewhere and with no
  window)
- `tests/test-pager.sh` 69/69 (node `security.cjs` and `baseline.cjs`,
  `qmltestrunner tst_security.qml`, and a Toast in `qs`: banked 4598 ms,
  5000 after the update, the picture dropped for one turn and read again,
  `cache` false)
- `tests/test-widgets-a.sh` 88/88 (the grid under V4 in six zones,
  2011-2027, three week starts; the old grid broke 46, 51, 34, 34, 18 and 8
  cells in Santiago, Havana, Beirut, the Azores, Cairo and Apia)
- `tests/test-lock.sh` 41/41, `tests/test-greeter.sh` 112/112 (the greeter's
  generated `input` equals `input.lua`'s for 43 `vconsole.conf` cases,
  including all 25 of `input.lua`'s Latin layouts), `tests/test-seeds.sh`
  97/97

`common.sh` is a GLOBAL path (plan 100), so `tests/run.sh --affected
origin/main` selected every test (154 files): 17444/17448 on this
branch before the comment fix below. Four files failed:

- `test-surfaces.sh`: the colour-literal check read `#7806` in a
  `LockView.qml` comment. Fixed ("pull request 7806"); the file then passes.
- `test-menu-back.sh`, `test-themegen-keys.sh` ("Failed to start IPC
  server": the socket path under this worktree's `tests/.out` passes 108
  bytes) and `test-nvim-theme.sh` (with these long absolute paths headless
  `nvim -l` drops the newline between its first three `print` lines; the same
  test passes 108/108 on origin/main from a shorter checkout path). All three
  pass from a short bind mount (`bwrap --bind <worktree>
  ~/.cache/haseen-wt/s`): 344/344 together with `test-surfaces.sh` and
  `test-lock.sh`.

After the comment fix, and rebased onto plans 101 and 102 (`a4ad91b`,
`d3624f0`), the affected set (all 156 files) was run again from the short bind
mount: 15753/16154. Every non-VAPT file passed. The 401 failures are all in
19 `test-vapt-*.sh` files, whose real ancestry checks require root-owned
directories: inside bwrap's unprivileged user namespace `/` and `/usr` show
uid 65534 (`bwrap --dev-bind / / -- stat -c %u /` prints 65534). All 33 VAPT
files outside bwrap, from the worktree: 5746/5746.

Rebased once more onto plan 104 (`3fd2c5c`, which changed another line of
`binds.lua`): the 20 files that cover `binds.lua`, this plan's tests and
plan 104's `test-omarchy45-boot.sh`, outside bwrap: 3312/3312.

`SHELLCHECK=/usr/bin/shellcheck tools/lint.sh` OK on the final tree (887
shell, 33 Lua, 198 JSON, 334 QML, 41 Go files; `affected-tests --check`: 2597
files, 157 tests, every file covered); `tools/check-docs.sh` OK; gitleaks over
the branch range: no leaks; the privacy pattern over `git log -p`: nothing.

## Rejected

- **Bind the Insert chords in haseen's terminal configs** (Omarchy's
  `config/foot/foot.ini@v4.5.0-rc1:18-20` does). The configs are seeded and
  then the user's, kitty, Alacritty and WezTerm users would need the same, and
  SHIFT + Insert is primary paste in all five by default.
- **Ship a static `sudo -N` wrapper, as Omarchy does.** It would put a sudo
  call outside `common.sh`. The generated wrapper lives in a user-owned
  directory, so a PKGBUILD could rewrite it while the helper runs; Omarchy's
  sits in a root-owned tree when installed. The boundary is the same either
  way against what it is for: no build silently reuses the password the
  update asked for. Code that runs as the user can also capture the next
  password through the user's shell, which no wrapper prevents.
- **Refuse the AUR phase when sudo has no `-N`** (Omarchy refuses the whole
  update). haseen still drops the timestamp before and after and says what it
  could not do; refusing would stop AUR updates for sudo-rs users.
- **Keep sudo warm with a keepalive, as Omarchy 4.5's single authorization
  does.** haseen's update asks once for pacman and runs no other privileged
  phase before the AUR one.
- **Greeter: Omarchy's non-Latin list and no `compose:caps`.** The desktop's
  rule (`input.lua`) is the one the user types the password with once the
  session locks; the greeter follows it, and the test keeps the two the same.
- **Portal file in `/etc/xdg/xdg-desktop-portal/`.** A system file would be
  haseen's to update, but it would also override what the hyprland package
  ships for every user, and Omarchy's fix is a user file; the seed follows it.

## Owner steps

- On IO and luna, after deploying: `haseen seed user` (part of every upgrade)
  writes `~/.config/xdg-desktop-portal/hyprland-portals.conf` only if neither
  that file nor `portals.conf` exists there. luna already has a `portals.conf`,
  so nothing is written on luna; check its `[preferred]` names
  `org.freedesktop.impl.portal.Secret=gnome-keyring` if Flatpak apps should
  reach the keyring. The portal reads its config at start: log out and back in.
- The next `haseen update` with AUR updates asks for the password again before
  the builds, and for each sudo the helper runs; that is the point. With
  `haseen setup passwordless-sudo` on, nothing prompts.

## Remaining

- `pkg_install_aur` (`share/haseen/lib/packages.sh:243`, used by `haseen
  layer apply` and `haseen install`) still runs the AUR helper with the
  timestamp warm. The survey suggests the same `run_cold` there; it is outside
  this plan's paths and changes many dry-run expectations.

## Follow-up (plan 111)

Two review findings closed in plan 111. `run_cold` now runs its command in a
subshell whose `EXIT` trap removes the wrapper and drops the timestamp, so a
SIGINT, SIGHUP or SIGTERM, to the job or to the calling shell alone, no longer
leaves either behind; a `mktemp` or `chmod` failure runs the command cold with
the warning instead of ending the update; a relative `TMPDIR` is resolved, and
one that does not resolve or holds a `:` falls back to `/tmp`. `haseen update`
scopes pacman only when `systemd-run` is on `PATH` as well as
`/run/systemd/system` being a directory.
