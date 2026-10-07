# Plan 077: `haseen brightness` and the display panel

## Status

- **Priority**: P2
- **Effort**: S + M
- **Risk**: LOW (brightnessctl through logind, no root; DDC and the panel are opt-in)
- **Depends on**: 010 019 064
- **Category**: CLI, shell, hardware
- **Planned at**: 2026-10-07, gap 2 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-brightness.sh`; nested screenshots with fixture devices)

## Change

- `bin/haseen-brightness`: `list [--kind K] [--rescan] | get [DEVICE] | set [DEVICE] VALUE | up [DEVICE] |
  down [DEVICE] [--step N] [--dry-run]`. VALUE is `N%`, `+N%`, `-N%` or a raw `N`.
  - Backends: `/sys/class/backlight/*` and `/sys/class/leds/*::kbd_backlight` read through `sysroot_path`
    and written by `brightnessctl --class=… --device=… set RAW` (logind, no root;
    `bin/haseen-brightness:255-256`); DDC/CI monitors through `ddcutil --bus N setvcp 10 RAW` when
    ddcutil is on PATH and `/dev/i2c-*` exists (`:151`, `:257`).
  - `ddcutil detect --brief` is parsed once (`:155-164`: "Invalid display" blocks skipped, connector and
    model kept, serial dropped) and cached in `$XDG_CACHE_HOME/haseen/ddc-displays.tsv`; a cached bus that
    stops answering triggers exactly one fresh detect.
  - The percent maths is in the command, so all kinds share it: absolute and relative percents are
    rounded to raw and clamped; a relative change moves at least one raw unit; `up`/`down` follow the
    4th-power curve the old binds used (`brightnessctl -e4`) for backlights and stay linear for keyboards
    and monitors; a backlight never goes below raw 2 (the old `-n2`). An unchanged value writes nothing.
  - One change at a time (`flock` on `$XDG_RUNTIME_DIR/haseen-brightness.lock`), so a held key cannot
    interleave DDC read-modify-writes.
  - `--dry-run` prints the brightnessctl/ddcutil call through `run` and changes nothing.
- `share/haseen/default/hypr/binds.lua`: `XF86MonBrightnessUp/Down` run `haseen brightness up|down`
  (the backlight, or every DDC monitor on a machine without one); new `XF86KbdBrightnessUp/Down` run
  `haseen brightness up|down kbd`. The haseen.osd backlight OSD is unchanged: it watches
  `actual_brightness`, which the kernel notifies for every write, whoever makes it (plan 010:45, :113).
- `brightnessctl` stays a hard dependency: `share/haseen/layers/desktop/packages.txt` and
  `nix/nixos.nix`. Tests stub it and `ddcutil` in `tests/lib.sh`.
- `bin/haseen-setup-ddc on|off|status` (off by default): `pkg_install ddcutil`, then `run_root modprobe
  i2c-dev` when the module is not loaded, or a `udevadm trigger` of the i2c-dev devices when it was
  (so the package's `uaccess` rule reaches them). Arch's ddcutil ships
  `/usr/lib/modules-load.d/ddcutil.conf` (i2c-dev at boot) and `60-ddcutil-i2c.rules` (`uaccess` for
  display adapters' buses), so no group membership is needed. `off` removes the package
  (`haseen remove package ddcutil`) and the bus cache. Menu: Setup › Monitor Brightness (DDC/CI).
  NixOS: `haseen.ddc.enable` (`hardware.i2c.enable` + ddcutil; the user joins `i2c`).
- Built-in panel `haseen.display` (off by default: `plugins."haseen.display".enabled` false in
  `share/haseen/default/shell.json`): one slider per backlight, keyboard backlight and DDC monitor, and a
  Night light row (the `nightlight` flag) when haseen.nightlight runs.
  - On open it runs `haseen brightness list` twice, sysfs kinds and DDC apart, so the slow DDC probe never
    holds back the backlights. Sysfs values then follow a `FileView` watch on the file the list names;
    DDC values are read on open only. No timer.
  - Writes go through `haseen brightness set ID N%`, one at a time; while one runs, each device keeps one
    waiting write, replaced by newer values (`Model.enqueue`). Sysfs sliders write while dragged, DDC on
    release only. A keyboard slider snaps to the device's levels.
  - Open: `haseen shell ipc panel toggle haseen.display`, or Setup › Display (shown once enabled).

## Evidence

- `tests/test-brightness.sh` (113 checks): list/get over a fixture sysroot (a caps-lock LED is not a
  keyboard backlight; the invalid display is skipped), the cache and the one re-detect for a moved monitor,
  the raw values set for every percent form, clamping, the floor, the curve, linear keyboard and DDC
  steps, usage errors, the dry run (nothing called, fixture unchanged), `haseen setup ddc` plans,
  manifest and default, 19 Model.js units under the real Qt JS engine, and the panel in the real
  Quickshell engine (devices, a firmware change through the watch, the write queue, the recorded
  brightnessctl/ddcutil argv, DDC read only on open and before its write).
- `tests/test-desktop.sh`: the Lua binds resolve to `haseen brightness up` / `down kbd`.

## Nested proof

Nest from `tools/nest-launch.sh`, scratch shell with `HASEEN_SYSROOT` pointing at a fixture (48000-step
`intel_backlight` at 31000, a 2-level `tpacpi::kbd_backlight`, `/dev/i2c-6`, `/dev/i2c-7`), stub
`brightnessctl` writing the fixture and stub `ddcutil` answering `detect` and VCP 0x10.

- `~/.cache/haseen-wt/scratch-brightness/shots/panel.png`: the panel from `panel toggle haseen.display`:
  Built-in display 65 %, Keyboard backlight 50 %, LG ULTRAGEAR (DP-1) 65 %, Night light Off.
- `…/shots/panel-moved.png`: after debug-IPC slides and a fixture write of 40000 (the watch): 83 %, 100 %, 90 %.
- `…/shots/panel-dragged.png`: a `tools/vptr` drag on the backlight slider: three live
  `brightnessctl … set` calls, none repeated on release. An earlier drag on the DDC slider sent one
  `setvcp 10 24` on release.

## Not verified

- No real brightness was changed: no backlight on the author's desktop, and the rules forbid touching
  the real monitors. Real brightnessctl through logind, real ddcutil writes and the OSD on a key press were
  not run (the OSD path is unchanged since plan 010's live check).
- `haseen setup ddc on` with real sudo; `haseen.ddc.enable` was not evaluated (no nix on the machine).
- The install picker does not offer `ddc` as a setup step.

## Rejected

- brightnessctl's own percent maths (`set 5%+`): DDC needs the same rules, and raw values make the
  calls testable.
- Polling DDC from the panel: each read is ~50 ms of i2c traffic per monitor; read on open only.
- An i2c group or a shipped udev rule: Arch's ddcutil already ships the `uaccess` rule.
- Turning `haseen.display` on: a new built-in stays off until the owner approves it (AGENTS.md).
