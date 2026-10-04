# Plan 008: DMS optional layer and shell switch

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. The live switch has not been run, because DMS is not installed on the author's machine.

## Why this matters

Requirement 4. DMS and the haseen shell both claim `org.freedesktop.Notifications`, the polkit agent and the lock, so only one of them can run at a time.

## Scope

- `layers/dms` installs `dms-shell` with `--assume-installed dms-shell-compositor`.
- Conflicts drop-in.
- `bin/haseen-shell-use`.
- `layers/dms/ipc-translate`.

## Acceptance

- `haseen shell use dms|haseen` switches units cleanly (fixture test plus a live check of the unit files).
- The binds keep working through `ipc-translate`.

## Execution record

### What changed

- `share/haseen/layers/dms/layer.sh`: `LAYER_REQUIRES=(desktop)`, distros cachyos/arch/omarchy.
  - **Apply:** runs `run_root pacman -S --needed [--noconfirm] --assume-installed dms-shell-compositor=1 dms-shell`, skipped when `dms-shell` or `dms-shell-git` is installed. It then writes the drop-in `PREFIX/lib/systemd/user/dms.service.d/haseen.conf`, skipping the write when the installed copy is byte-identical (`cmp`). `PREFIX` comes from `$HASEEN_PATH/../..`. Nothing is enabled, and dankinstall or `dms setup` never run.
  - **Status:** checks the package, the packaged unit `/usr/lib/systemd/user/dms.service`, whether the drop-in is current (an edited one reports degraded, exit 2), and the active shell.
  - **Remove:** when `active-shell` says `dms`, it first runs `PREFIX/bin/haseen-shell-use haseen --yes [--dry-run]`. If the shell layer is not applied, it instead runs `systemctl --user disable --now dms.service` and removes the state file. It then removes the drop-in, `rmdir --ignore-fail-on-non-empty`, and runs `daemon-reload`. Package removal is printed for the user (`pacman -Rns <pkg>`, run as root).
- `share/haseen/layers/dms/files/haseen.conf`: `[Unit] Conflicts=haseen-shell.service` plus `After=haseen-shell.service`. systemd.unit(5) says Conflicts= does not order the stop before the start, but any ordering dependency does. With it, `org.freedesktop.Notifications` is free before `dms.service` (`Type=dbus`, `BusName=org.freedesktop.Notifications`, upstream `assets/systemd/dms.service:7-8`) claims it.
- `bin/haseen-shell-use dms|haseen [--dry-run] [--yes]`:
  - Refuses (exit 1) unless the target's layer is applied (`dms`, or `shell` for haseen).
  - Prints that DMS claims notifications, polkit and lock, then asks to confirm.
  - Runs `systemctl --user daemon-reload`, then `disable --now <other>` (only when the other layer is applied, because disabling a missing unit file errors), `enable <chosen>`, and `start <chosen>`. A failed start only warns: `dms.service` is `Requisite=graphical-session.target`, and the enable still takes effect at the next login.
  - Writes `~/.local/state/haseen/active-shell`.
- `share/haseen/layers/dms/ipc-translate [--dry-run] <target> <fn> [args]`: unmapped calls print one line on stderr and exit 3. Usage errors exit 2. The dms exit code propagates. The mapping comes from DMS at `/tmp/ref/DankMaterialShell`:

| haseen call | DMS call | source |
|---|---|---|
| `launcher toggle` | `dms ipc call launcher toggle` | `quickshell/DMSShellIPC.qml:1508`, target `:1537` |
| `lock lock` | `dms ipc call lock lock` | `quickshell/Modules/Lock/Lock.qml:377` (target), `:379` |
| `notifications clear` | `dms ipc call notifications clearAll` | `quickshell/Modals/NotificationModal.qml:178`, target `:193` |
| `notifications toggleDnd` | `dms ipc call notifications toggleDoNotDisturb` | `NotificationModal.qml:130` |
| `panel toggle haseen.launcher` | `dms ipc call launcher toggle` | `DMSShellIPC.qml:1508` |
| `panel toggle haseen.notifications` | `dms ipc call notifications toggle` | `NotificationModal.qml:123` |
| `panel toggle haseen.session` | `dms ipc call powermenu toggle` | `DMSShellIPC.qml:184`, target `:197` |
| `shell reload` | `dms restart` | `quickshell/Services/SessionService.qml:656`; restarts `dms.service` when systemd manages it (`core/cmd/dms/systemd_restart.go:23-31`) |
| `panel toggle <other id>` (e.g. `haseen.ai`), `panel close`, `shell plugins`, any extra args | exit 3 | no DMS equivalent |

`lock` and `notifications` are not in `DMSShellIPC.qml`: DMS registers them in `Lock.qml` and `NotificationModal.qml`.

- `tests/test-dms.sh`: 99 assertions. The fixture sysroots are copies of `cachyos-grub-plain` with `/var/lib/haseen/layers/*` markers. A synthetic `HASEEN_LAYERS_DIR` holds the real `dms` layer plus inert stand-ins for `base`/`desktop`/`shell`. The suite covers:
  - the plan (the assume-installed flag, the drop-in content, no `systemctl`);
  - `--noconfirm` under `--yes`;
  - convergence (an installed package and an identical drop-in produce no writes, and `dms-shell-git` counts as installed);
  - the degraded status of an edited drop-in;
  - refusals (with no state written);
  - the exact dry-run and live switch sequences in both directions, using a recording `systemctl` stub and the `active-shell` contents;
  - a start failure outside a session;
  - the remove ordering (switch back, then drop-in, then marker);
  - the translate table and the unmapped/usage/propagated exit codes;
  - dry-run purity.

### Evidence

```
$ tests/run.sh tests/test-dms.sh
test-dms.sh
----
99/99 passed
$ /tmp/tools/shellcheck --severity=warning -x bin/haseen-shell-use share/haseen/layers/dms/layer.sh share/haseen/layers/dms/ipc-translate tests/test-dms.sh
shellcheck rc=0
$ bash -n (each file)  -> ok
```

For the real smoke, the upstream unit went into `$T/usr-lib/` with only `ExecStart` pointed at `/usr/bin/true`, because `dms` is not installed here. The unmodified unit fails solely with `dms.service: Command /usr/bin/dms is not executable`. The drop-in went into `$T/usr-local/dms.service.d/`, a different unit path, the way `/usr/local` and `/usr/lib` differ on a host:

```
$ SYSTEMD_UNIT_PATH="$T/usr-local:$T/usr-lib:" systemd-analyze --user verify $T/usr-lib/dms.service
rc=0
# planted Bogus=1 in the drop-in (proves the cross-path drop-in is merged):
.../usr-local/dms.service.d/haseen.conf:10: Unknown key 'Bogus' in section [Unit], ignoring.
# Conflicts=not a unit (proves the Conflicts= line itself is parsed):
.../usr-local/dms.service.d/haseen.conf:6: Failed to add dependency on not, ignoring: Invalid argument
```

`pacman -Si dms-shell` (extra, 1.6.0-2) shows `Depends On: accountsservice quickshell dms-shell-compositor`, with `matugen` listed under Optional Deps ("Dynamic wallpaper-based theming"). Hyprland provides only `wayland-compositor`, so the assume-installed flag is required.

### Rejected

- **Installing `matugen`.** It is optional in the Arch package, and it does runtime wallpaper colour generation, which is against §6. Apply prints a hint pointing at `pacman -Si dms-shell` instead.
- **Enabling DMS DMS's way** (`systemctl --user add-wants hyprland-session.target dms`, `core/internal/distros/base.go:571-584`). haseen uses the unit's own `WantedBy=graphical-session.target` through `enable`. `disable` removes every symlink to the unit, so a user's earlier `add-wants` is cleaned up too.
- **A `packages.txt`.** The runner's `pkg_install` cannot pass `--assume-installed`.
- **Putting the drop-in in `/etc/systemd/user/`.** That is admin territory. The architecture places haseen's user units under `PREFIX/lib/systemd/user`, and systemd merges `dms.service.d/` across unit paths, as the smoke above verifies.
- **Shipping the drop-in under `share/haseen/systemd/user/`.** `install.sh` installs that directory's entries as files, one by one, and would not handle a `.d/` subdirectory.
- **Mapping `panel close` to "close every DMS popout"** and **mapping `shell plugins` to `dms ipc call plugins list`.** The semantics and output differ, so both exit 3.

### Open risks

- `dms run` moves a stray `~/.config/hypr/hyprland.conf` (and `~/.config/hypr/dms/*.conf`) into a backup dir whenever `hyprland.lua` exists (`core/internal/config/hyprland_lua.go:144-190`, called from `bootBackend`). haseen's config is Lua, so this only touches leftovers, but it still edits the user's directory. [INFERENCE] It is harmless for a haseen install.
- [UNVERIFIED] `dms restart` lives in the external `dankgo/shellapp` module, which is not in the clone. The evidence for it is DMS's own call `["dms", "restart"]` (`SessionService.qml:656`).
- [UNVERIFIED] No live switch was run: DMS is not installed on this machine and there is no sudo.
- `haseen-shell.service` (shell slice) should carry an ordering against `dms.service` (`After=` or `Before=`) as well as `Conflicts=dms.service`, so the bus name is released before the haseen shell starts.
