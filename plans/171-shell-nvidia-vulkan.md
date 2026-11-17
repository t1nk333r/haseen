# Plan 171: Vulkan for a GPU-rendered shell on NVIDIA

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW. Changes nothing on the default software renderer. Applies
  only when the user has chosen the GPU scene graph, the proprietary NVIDIA
  driver (555 or newer) drives the compositor's card, and no
  `QSG_RHI_BACKEND` is set.
- **Depends on**: 005 (software renderer default), 031 (hardware probes)
- **Category**: shell
- **Planned at**: 2026-11-14, from the owner (sent lucid's repository, "what
  could be good to take", then "go")
- **State**: PLANNED 2026-11-14

## Problem

haseen's shell defaults to Qt's software renderer
(`share/haseen/shell/shell.qml:2,9-11`, plan 005: the GL scene graph cost
~85 MiB RSS and bought nothing, `plans/005-shell-core.md:97-102,120`). A
user may still set `QT_QUICK_BACKEND`; luna runs the shell on the GPU
renderer through a user drop-in (`plans/156-skew-slice-fractional-scale.md:104-105`),
and plans 161 and 163 draw differently there (`plans/161-wallpaper-transitions.md:142-146`,
`plans/163-stage-manager.md:16`).

On the proprietary NVIDIA driver, Qt's wayland-egl integration refuses the
threaded render loop (QTBUG-95817), so the GPU scene graph falls back to
the basic loop, which drives animations from a fixed ~16 ms timer: about
60 fps on any monitor. Qt's Vulkan RHI backend has no such check. Lucid
(MIT, Sn3akyy1/lucid at d1bcf8a) handles it in
`support/lucid/launch-shell.sh`: it finds the card the compositor renders on
(`AQ_DRM_DEVICES`, else the only card, else the boot VGA), reads the loaded
driver's version from `/proc/driver/nvidia/version`, and exports
`QSG_RHI_BACKEND=vulkan` only for NVIDIA ≥ 555 (explicit sync), never
overriding an existing value, with every probe path overridable.

haseen sets no Qt variable at start (`bin/haseen-shell-run:30-35`,
`share/haseen/systemd/user/haseen-shell.service:12-19`), and nothing reads
the running NVIDIA driver: `hw_probe_nvidia` only finds an NVIDIA PCI
device (`share/haseen/lib/hardware.sh:97`); `bin/haseen-about:83-86` is the
only reader of a card's kernel driver.

## Decision

- `share/haseen/lib/hardware.sh` gains `hw_render_card` (lucid's order,
  through `sysroot_path /sys/class/drm`) and `hw_nvidia_driver_major`
  (`sysroot_path /proc/driver/nvidia/version`), adapted from
  `launch-shell.sh` with lucid's MIT notice in the function header and a
  `NOTICE.md` row.
- `bin/haseen-shell-run`, before the `exec qs` (`:35`): when
  `QT_QUICK_BACKEND` is set to something other than `software`, and
  `QSG_RHI_BACKEND` is unset, and the render card's driver is `nvidia` at
  major ≥ 555, export `QSG_RHI_BACKEND=vulkan`. `HASEEN_RHI_BACKEND`
  overrides the choice; `haseen shell run --explain` prints it and exits.
- `bin/haseen-doctor` prints the running shell's renderer, read from
  `/proc/<pid>/environ` next to its RSS line (`:20-33`): `software`, or
  `rhi (vulkan)` and so on.
- Tests: new fixtures with `sys/class/drm/card0/device/{vendor,driver}` and
  `proc/driver/nvidia/version` (none exist; `tests/fixtures/desk-cachyos-nvidia-dm`
  has the PCI files only), cases in `tests/test-hardware.sh` and a stub `qs`
  in `tests/test-shell.sh` (`:442-449`) asserting the exported environment.

## Rejected

- **Switching the default to the GPU renderer**: plan 005's +85 MiB, recorded
  again in plan 139 (`plans/139-osd-card-whole-pixels.md:85-86`).
- **Vulkan on Mesa too**: Mesa already gets the threaded loop; nothing gained.
- **Setting it in the uwsm GPU env file** (`share/haseen/layers/desktop/layer.sh:60-121`):
  it would reach every Qt app, not only the shell, and be stale after a
  driver change.
- **Deciding from installed packages** (`nvidia_driver_packages`,
  `layer.sh:58`): a hybrid laptop has the package but may render on Intel.

## Evidence (to collect)

- `tests/test-hardware.sh` and `tests/test-shell.sh` against the new
  fixtures: NVIDIA 610 on the render card exports vulkan; NVIDIA 470, Intel,
  a hybrid with the boot VGA on Intel, the software default, and a preset
  `QSG_RHI_BACKEND` export nothing.
- On an NVIDIA machine with the GPU renderer: `haseen doctor` names
  `rhi (vulkan)`, and an animation's frame rate follows the monitor
  (`QSG_RENDER_LOOP` reported as threaded with `QSG_INFO=1`).
