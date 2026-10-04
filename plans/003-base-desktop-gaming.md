# Plan 003: Base, desktop and gaming layers

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: desktop
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. Fixture-tested, and `Hyprland --verify-config` passes. A real login on CachyOS is pending plan 014.

## Why this matters

The default install. CachyOS installs the OS and these layers turn it into the haseen desktop. They replace `omarchy-base.packages`, which pulls in libreoffice, kdenlive, obs, docker and chromium.

## Scope

- `layers/base`, `layers/desktop`, `layers/gaming`.
- Hyprland Lua defaults in `share/haseen/default/hypr/`.
- The seeded `~/.config/hypr/hyprland.lua` includes those defaults.
- uwsm session, with greetd + tuigreet only when no display manager is enabled.
- GPU session env ported from omacachy `gpu-*.sh`.

## Acceptance

- Fixture dry-run tests.
- `luac -p` passes on all Lua.
- `Hyprland --verify-config` passes on the generated config, when Hyprland is available.

## Execution record

Executed 2026-10-04 (agent Desktop). Uncommitted; the integrator commits.

### What changed

- `share/haseen/layers/base/`: `layer.sh`, `packages.txt` (12 packages, one reason each), and `lib.sh`. `lib.sh` holds the read-only probes shared by base, desktop and gaming: `unit_enabled`, `display_manager_unit`, `installed_packages_matching`, `root_fstype`, `pacman_repo_enabled`, `has_gpu`, `nvidia_device_id`. They read systemd symlinks, the pacman local db, fstab and sysfs through `sysroot_path`, and never call systemctl or pacman.
  - Network: if NetworkManager, systemd-networkd, connman, iwd or dhcpcd is enabled, it is left alone. Otherwise the layer installs NetworkManager and enables it.
  - Firewall: firewalld enabled → warn and skip. Otherwise, if `/etc/ufw/ufw.conf` already has `ENABLED=yes` and `/etc/default/ufw` has `DROP`/`REJECT`, nothing runs. Otherwise it runs `ufw default deny incoming`, `ufw default allow outgoing` and `ufw --force enable`. `ufw.service` is enabled only if it is not already.
  - `paccache.timer` is enabled if it is not already. pacman.conf, mirrors and repos are never touched.
  - Snapper: on a btrfs root without `/etc/snapper/configs/root`, warn only.
  - `--bluetooth` (layer arg) installs bluez + bluez-utils and enables bluetooth.service.
- `share/haseen/layers/desktop/`: `layer.sh` and `packages.txt` (22 packages).
  - Login: an enabled display manager other than greetd is kept. greetd with a config haseen did not write is also kept. Otherwise the layer installs greetd + greetd-tuigreet and writes `/etc/greetd/config.toml` (marker line; `tuigreet --cmd 'uwsm start hyprland.desktop'`). The packaged config is backed up once to `.haseen-orig`, and the file is skipped when already current. greetd is enabled but not started.
  - GPU (from `GPU_VENDORS`): the profiles are nvidia, amd, intel, hybrid-nvidia, hybrid-amd and none.
    - NVIDIA: the installed driver is kept. With no driver, `chwd -a 0300/0302` runs on CachyOS; on Arch the layer warns. It also warns when an open module sits on a pre-Turing card (from the sysfs device id).
    - `libva-nvidia-driver` is installed on NVIDIA-only Turing+.
    - `/etc/modprobe.d/haseen-nvidia.conf` is written only when nothing in /etc or /usr/lib modprobe.d sets nvidia_drm modeset.
    - `intel-media-driver` is installed when an Intel GPU is present, and `nvidia-prime` on hybrid-nvidia.
  - User side (`desktop_user_setup`, unprivileged):
    - seed `~/.config/hypr/hyprland.lua` and `~/.config/foot/foot.ini`;
    - seed a comment-only `$HASEEN_USER_STATE/current/theme/foot.ini` placeholder, only when absent;
    - write `~/.config/uwsm/env.d/10-haseen` (HASEEN_PATH, TERMINAL=foot, ELECTRON_OZONE_PLATFORM_HINT=auto, QT_QPA_PLATFORM) and `50-haseen-gpu`, both skipped when unchanged.
    - An existing hyprland.lua that does not load the haseen defaults gets a warning and is never overwritten.
- `share/haseen/layers/gaming/layer.sh` (no manifest: the package set depends on repos and GPU).
  - `[cachyos]` repo enabled → `cachyos-gaming-meta`, plus `cachyos-gaming-applications` only with `--apps`.
  - Always: steam, gamemode, lib32-gamemode, mangohud, lib32-mangohud, gamescope, plus the lib32 drivers for each GPU. NVIDIA lib32 matches the installed driver branch, and legacy branches come from the AUR on Arch.
  - Refuses when `[multilib]` is off (pacman.conf stays the user's).
  - Adds the user to the `gamemode` group.
  - Prints the `haseen secureboot setup` note when Secure Boot is not enabled.
- `share/haseen/default/hypr/`:
  - `init.lua`: the entry point. It defines the global `haseen` table (`path`, `paths`, `include_optional`, `bind`, `ipc`, `launch`) and dofile()s its siblings.
  - siblings: `input.lua`, `looknfeel.lua` (no blur or shadow, gaps 2/4, few fast animations, workspaces instant), `binds.lua`, `windowrules.lua`, `autostart.lua` (inside `hl.on("hyprland.start")`: a guarded `uwsm finalize` and `haseen hook run post-boot`; no bar).
  - `user/hyprland.lua`: the seed source.
- `share/haseen/default/foot/foot.ini` (seed) and `theme-fallback.ini` (placeholder).
- `tests/test-desktop.sh` (128 assertions) and fixtures `tests/fixtures/desk-{cachyos-nvidia-dm,cachyos-amd,arch-intel,arch-hybrid}` (no `expected.preflight`, so test-core ignores them).

### Runtime contract decided here

- **Finding haseen at runtime.** The seed runs `dofile($HASEEN_PATH/default/hypr/init.lua)`. If `HASEEN_PATH` is unset it falls back to `/usr/local/share/haseen`, then `/usr/share/haseen`, and errors clearly if neither exists. `HASEEN_PATH` comes from `~/.config/uwsm/env.d/10-haseen`; uwsm 0.26.7 sources `uwsm/env.d/*` (`man uwsm`, lines 32-35). `init.lua` then takes `haseen.path` from its own file location (`debug.getinfo(1,"S")`), so a Nix store path works with the env unset (agreed with agent Nix).
- **Modules load with dofile, not require.** Hyprland keeps one Lua VM across reloads, and Omarchy's bootstrap has to clear `package.loaded` to cope with that (`/usr/share/omarchy/default/hypr/bootstrap.lua`).
- **Theme files (agreed with agent Theme).**
  - `~/.local/state/haseen/current/theme/hyprland.lua` has the Omarchy `hyprland.lua.tpl` shape: it calls `hl.config` and returns nothing. It is loaded after the defaults and before the user files.
  - `current/theme/foot.ini` holds a `[colors-dark]` section and is included from the seeded `foot.ini`.
- **Load order:** defaults, then theme, then `~/.config/hypr/{monitors,bindings,local}.lua`. Each optional file is loaded under pcall. A failure is printed and shown with `hl.notification.create`, and the files after it still load.

### Evidence

```
$ /tmp/tools/shellcheck --severity=warning -x <5 shell files>   → clean
$ bash -n (5 files)                                             → ok
$ luac -p share/haseen/default/hypr/*.lua user/hyprland.lua     → ok (7 files)
$ tests/run.sh tests/test-desktop.sh                            → 128/128 passed
$ tests/run.sh tests/test-core.sh                               → 28/28 passed
```

Real smoke on Hyprland 0.56.2 (`efb5099`):

- **Setup.** Run in a scratch HOME. `desktop_user_setup` seeded the files from the `desk-cachyos-nvidia-dm` fixture. Then `HASEEN_PATH=<repo>/share/haseen Hyprland --verify-config -c <scratch>/.config/hypr/hyprland.lua`. The live session was never touched: `--verify-config` does not start a compositor.
- **Results:**
  - seed only → `config ok`
  - seed + Omarchy-shape gradient theme file + `monitors.lua` (`hl.monitor`) + `bindings.lua` (`hl.unbind` + `haseen.bind`) → `config ok`
- **Negative controls: verify-config really checks the dofile'd defaults.**
  - Bad key injected into a copy of `looknfeel.lua`: `looknfeel.lua:84: unknown config key 'decoration.blurx'`.
  - Bogus dispatcher in `binds.lua`: `binds.lua:97: attempt to call a nil value (field 'nonexistent')`.
  - Unknown rule effect: `hl.window_rule: unknown field 'bogus_effect'`.
- **API cross-check.** The `hl` API was cross-checked by enumerating `hl`/`hl.dsp` through `--verify-config` with a probe file, and against `/usr/share/hypr/stubs/hl.meta.lua`, which ships with hyprland 0.56.2.
- **foot.** `foot --check-config` on the seeded `foot.ini`: before the placeholder existed, `[main].include: … failed to open` with rc 230, which is why the placeholder was added. With the placeholder, or with an Omarchy `foot.ini.tpl`-shaped theme, rc 0. `tests/test-desktop.sh` now asserts this.
- **Gaming package names.** `cachyos-gaming-meta` and `cachyos-gaming-applications` were checked against CachyOS-PKGBUILDS master (raw PKGBUILDs fetched 2026-10-04). Neither is in this Arch/Omarchy host's repos (`pacman -Si`: not found). `lib32-nvidia-580xx-utils` is on packages.cachyos.org (HTTP 200) and in the AUR (RPC). Every other package was confirmed in extra/core/multilib with `pacman -Si`.

### Rejected

- **`require()` + package.path for the defaults** (Omarchy's approach): a reload serves cached modules unless package.loaded is purged, and dofile has no such state.
- **cachyos-gaming-applications by default:** it pulls Lutris, Heroic, Faugus and GOverlay, which is clutter for a Steam-only user. It is behind `--apps`.
- **ROCm in desktop** (omacachy amd-rocm.sh): the AI layer owns it (`ollama-rocm`/`ggml-hip`), and ROCm is multi-GB.
- **`CUDA_DISABLE_PERF_BOOST=1`** (omacachy nvidia.sh): it would slow local-AI inference on the same machine.
- **NVIDIA-wide env on hybrid laptops:** GBM_BACKEND, __GLX_VENDOR_LIBRARY_NAME and LIBVA=nvidia would route every app to the sleeping dGPU. Hybrid machines get `prime-run` instead.
- **`LIBVA_DRIVER_NAME=iHD` on Intel:** it breaks pre-Broadwell iGPUs, and libva auto-detects anyway.
- **keepassxc as the keyring:** it is a GUI app, not a PAM-unlocked Secret Service. gnome-keyring is the choice.
- **Relying on Hyprland alone to put WAYLAND_DISPLAY into the systemd activation env:** unverified here. Omarchy runs `systemctl --user import-environment` from autostart instead. The defaults therefore run `uwsm check is-active && uwsm finalize` once in `hyprland.start` (`man uwsm`: finalize exports the variables and sends the readiness notification). [INFERENCE: repeating it after Hyprland's own export is harmless; not observed in a uwsm-started session here.]
- **Starting greetd with `--now`:** it would take the VT from under the running install.
- **Running mkinitcpio after writing the modeset drop-in:** it is heavy and interacts with Secure Boot signing. The layer warns instead, and drivers ≥560 default to modeset=1 anyway.
- **Editing pacman.conf to enable multilib:** pacman has no drop-in directory, so haseen refuses with instructions instead.

### Open risks

- Not run on a real CachyOS install (no VM; plan 014). greetd + tuigreet + `uwsm start hyprland.desktop` was never started end-to-end, so login is untested.
- [INFERENCE] When both `hyprland.lua` and an old `hyprland.conf` exist, Hyprland 0.56 prefers the Lua file. The live host uses only Lua.
- `foot.ini`'s include is the literal `~/.local/state/...`, so a user with a non-default `XDG_STATE_HOME` gets the placeholder/theme path mismatch.
- The status labels print `~/.config/...` even when `XDG_CONFIG_HOME` differs.
- `gamemode` group membership is read from `/etc/group` only (no NSS/LDAP).
