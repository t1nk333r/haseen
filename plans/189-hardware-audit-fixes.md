# Plan 189: hardware fixes from the 2026-11-24 audit

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Each fix is a few lines in one command or quirk body. The
  only new behaviour at session start is one short shell script, run by
  Hyprland's config only while `laptop-display-off.lua` exists.
- **Depends on**: 028 (the ledger), 031 (hardware quirks), 093 (the Omarchy
  hardware commands)
- **Category**: hardware
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/test-hardware.sh` 51/51,
  `tests/test-powerprofile.sh` 39/39, `tests/test-omarchy-hw.sh` 276/276;
  the coordinator runs the independent review)

## Problem

The audit of 2026-11-24 ran on plan 182's review branch, one commit after
`b6d3a356` (plan 181). It confirmed four hardware findings. Each one was checked again on `9a9e82ab` (main after plans 182 to
184), and all four still applied there. Line numbers below are from
`9a9e82ab`.

### 1. nvidia-gsp requires NVIDIA modules that may not be installed

The `nvidia-gsp` quirk matches on the PCI id alone
(`share/haseen/hardware/quirks.tsv:20`, `probe:nvidia-gsp`;
`share/haseen/lib/hardware.sh:96` reads vendor, class and device id only).
The body checks two things: whether the conf already exists, and whether
mkinitcpio is in use (`share/haseen/hardware/nvidia-gsp.sh:13-20`). It does
not check that a driver is installed. It then writes
`MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)` (`:24`). On Arch,
haseen installs no NVIDIA driver; the desktop layer only warns
(`share/haseen/layers/desktop/layer.sh:146`, "haseen does not pick drivers
on Arch"). So on a Turing or newer card running nouveau, or with no driver
yet, every later `mkinitcpio -P` fails with `module not found: 'nvidia'`.
That includes the run from the kernel-upgrade hook. The ledger marks the
quirk applied, so haseen never looks at it again.

### 2. A wireless mouse puts a desktop on the battery profile

`on_ac` in `bin/haseen-powerprofile-set:37-55` sets `have_battery=true` for
every supply of type `Battery` (`:44-45`) and returns `! $have_battery`
(`:54`). The kernel also reports peripheral batteries as type `Battery`:
Logitech `hidpp_battery_N`, gamepads, Bluetooth headsets. These have
`scope` set to `Device`. A desktop usually exposes no Mains supply that reads
online. On a desktop with a wireless mouse, autodetect therefore picks
`battery`: at every login (`share/haseen/default/hypr/autostart.lua:24`,
`haseen powerprofile init`), and when the battery panel saves a choice
(`share/haseen/shell/plugins/haseen.battery/Panel.qml:70` passes `autodetect NAME`). The desktop
gets `balanced` instead of `performance`, and the user's choice is saved
under the wrong source. `bin/haseen-battery-status:59` already skips
`scope` `Device` supplies for this reason.

### 3. The clamshell toggle can boot a laptop with every display off

`install.sh:388` runs `hw apply`. The `clamshell` quirk matches every laptop
(`quirks.tsv:18`). It binds closing the lid to
`haseen hardware laptop-display off` and opening it to `... on`
(`share/haseen/hardware/clamshell.sh:23-24`). `off` writes
`hl.monitor({ output = "eDP-1", disabled = true })` to
`toggles/hypr/laptop-display-off.lua`
(`bin/haseen-hardware-laptop-display:52-53`). Its check that an external
monitor is active (`:49`) runs only when the file is written.
`share/haseen/default/hypr/init.lua:268-272` loads every toggle at each
start and reload. Only the lid-open event removes the file. A laptop shut
down while docked with the lid closed, then booted undocked with the lid
open, sends no lid event. Hyprland disables its only output and the screen
stays black. Closing and opening the lid recovers, but a user is unlikely to
know that. `share/haseen/omarchy/bin/omarchy-hw-recover-internal-monitor`
already does the recovery: it removes the toggle when no external connector
reads `connected` in sysfs. Nothing ran it, though (`:11`, "haseen starts
nothing by itself").

### 4. hw apply records a quirk whose root write failed

`bin/haseen-hw-apply:87` ran each body as
`(source "$(hw_body "$id")") || die ...`. Bash ignores `set -e` inside a
command whose status is tested, so a command that failed partway through a
body did not stop it. `write_root_file` runs `sudo install`, `sudo tee` and
`sudo chmod` without checking them (`share/haseen/lib/common.sh:329-331`).
If sudo is refused, the body carries on to its closing `warn` or `info`,
the subshell exits 0, and `ledger_record ... applied` (`:88`) marks the
quirk done. That breaks the comment's promise (`:84-85`, "A failure stops
the run with no marker written"). The scratch repro:

```
$ printf 'wr() { false; }\necho x | wr\necho "body continued"\n' >body.sh
$ bash -c 'set -Eeuo pipefail; (source ./body.sh) || { echo DIE; exit 1; }; echo RECORDED'
body continued
RECORDED
```

The test for this (`tests/test-hardware.sh:101-104`) put `false` on the
body's last line, so it never covered a failure in the middle of a body.
`nvidia-gsp.sh`, `fkeys.sh` and `wireless-regdom.sh` all end with a message
after their root write.

## Decision

### 1. Optional modules

`nvidia-gsp.sh` now writes
`MODULES+=('nvidia?' 'nvidia_modeset?' 'nvidia_uvm?' 'nvidia_drm?')`.
mkinitcpio treats a trailing `?` as optional: `add_module` sets
`ign_errors=1` for `*\?` (`/usr/lib/initcpio/functions:695-698`, mkinitcpio
42.2), and returns 0 when such a module is not found (`:738-739`). With no
driver installed, the file does nothing. Once `nvidia-open` or another
driver is installed, early KMS starts with the next build, and the ledger
does not need to revisit the quirk.

mkinitcpio sources its conf files as bash (`/usr/bin/mkinitcpio:1143`), so
an unquoted `nvidia?` is a glob:

```
$ touch nvidia1; bash -c 'MODULES+=(nvidia?); printf "%s\n" "${MODULES[@]}"'
nvidia1
```

So each name is quoted.

**Test**: `tests/test-hardware.sh` "the nvidia body writes early-KMS
modules, each optional" checks the quoted, optional line in the dry run. It
fails on the old body.

### 2. Skip peripheral batteries

`on_ac` skips a `Battery` whose `scope` reads `Device`, as
`haseen-battery-status` does. A battery with scope `System`, or with no
`scope` file, still counts.

**Test**: `tests/test-powerprofile.sh` builds a sysroot with only
`hidpp_battery_0` (type `Battery`, scope `Device`). Autodetect must say
`(ac)` and apply `performance`. Two checks failed before the fix (37/39).
The same sysroot with scope `System` must say `(battery)`.

### 3. Recover the panel before the toggles load

Before `init.lua` lists the toggles, it checks whether
`laptop-display-off.lua` exists. If it does, it runs
`omarchy-hw-recover-internal-monitor`, which removes the toggle (and the
clamshell mark) when no external connector is connected. This covers toggle
files written before this plan, and every start and reload. The script asks
the kernel, not Hyprland, so its answer is valid before the compositor has
any outputs. When the toggle does not exist, nothing is spawned. The script
header and the `laptop-display` usage now describe this.

**Test**: `tests/test-omarchy-hw.sh` runs the real `init.lua` under a stub
`hl` that prints each `hl.monitor` rule, against a sysroot with
`card1-HDMI-A-1`. When the connector reads connected, the toggle loads and
stays. When it reads disconnected, the toggle neither loads nor stays. The
two undocked checks failed before the fix (274/276).

### 4. Errexit inside the body

The body still runs sourced in a subshell, so it keeps `DRY_RUN`, `YES` and
the helpers. The subshell now runs outside any `||`, under `set +e`, with
`set -e` turned on inside it. Its status is read afterwards, and a non-zero
status dies with the old message. I read every shipped body (`clamshell`,
`fkeys`, `gestures`, `nvidia-gsp`, `vm`, `wireless-regdom`) and found no
command in the middle of a body whose failure is expected. `gestures_apply`
already runs under `set -e` in `haseen-gestures-apply`.

**Test**: `tests/test-hardware.sh` uses a body whose piped function fails
in the middle and then logs `continued`. The run must fail, name the quirk,
log only `ran`, and keep no marker. All four checks failed before the fix.
Run against the base sources with the new tests, `tests/test-hardware.sh`
passed 46/51: these four and the optional-modules check.

## Rejected

- **Gate nvidia-gsp on an installed driver and return early.** The body
  would return 0, the ledger would record it, and a driver installed later
  would never get early KMS. Failing instead would stop every quirk after
  it. Optional modules work in both cases.
- **A migration that rewrites existing `haseen-nvidia.conf` files.** A file
  written without a driver only errors until the driver is installed, and
  the error names the file. CachyOS installs a driver with chwd. Not worth a
  root migration.
- **Lid-close disables the panel live only (`hyprctl eval`, no file).** Any
  `hyprctl reload` while docked would then turn the closed panel back on.
  haseen's toggles reload often.
- **A pure-Lua sysfs check in `init.lua`.** Lua cannot list a directory
  without `io.popen` either, so it would still spawn a process, and it would
  repeat `omarchy-hw-external-monitors` without `sysroot_path`, which the
  test relies on.
- **Skip the toggle at load but keep the file.** A later reload while
  docked would turn the panel off with the lid open.
- **A separate `bash -Eeuo pipefail -c` process for each body**, as the
  audit suggested. The body would lose the parsed flags (`DRY_RUN`, `YES`)
  and every variable the dispatcher set, so each would have to be passed
  in.

## Limitations

- `haseen hardware monitor set eDP-1 --off` persists a disabled rule, keyed
  by the panel's EDID description, in the monitor tool's own file
  (`bin/haseen-hardware-monitor:202-207`). That rule can also outlive the
  external monitor. It is an explicit choice in the monitor tool, not the
  clamshell path, and the recovery here does not touch it.
- A dock whose external connector comes up after Hyprland reads its config
  makes the recovery remove the toggle, so the panel stays on. That is the
  safe direction.

## Verification

From the worktree's real path, through the hermetic wrapper:

- `tests/run.sh tests/test-hardware.sh`: 51/51
- `tests/run.sh tests/test-powerprofile.sh`: 39/39
- `tests/run.sh tests/test-omarchy-hw.sh`: 276/276
- `tools/lint.sh`: lint OK
- `tests/run.sh --affected 9a9e82ab62ed9c65083b56d6c9c488e62736d875`: 25
  test files selected (the changed commands select the menu, keybind and
  i18n suites, and `init.lua` the desktop, theme and seed suites), 5022/5022
- `tools/check-docs.sh`: check-docs OK
- The three new sets of checks, run against the base sources: 46/51, 37/39
  and 274/276, every new check failing as listed above
