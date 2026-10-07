# Handoff — haseen

Orientation for whoever picks this up next, human or agent. Updated 2026-10-04.

## What this repo is

haseen (حصين, "fortified") is the owner's own desktop base. It replaces Omarchy
as the foundation (ADR 0001). It installs on top of an existing CachyOS system
and adds opt-in layers. It lifts selected parts of Omarchy (themes, CLI
conventions, plugin API names for compat) and DankMaterialShell (an optional
runtime shell, plugin API names for compat). It takes design ideas from end-4
and caelestia, which are GPL and used as reference only.

The owner's other repos:
- `t1nk333r/omacachy`: Omarchy on CachyOS. Its helper conventions and ESP
  detection were adopted here.
- `gitlab.com/t1nk33r/waydots`: the owner's yadm overlay. It becomes the
  personal layer on top of haseen. Its `t1nk33r.*` Omarchy plugins load through
  the compat adapter (plan 011); 6 were verified live.

## Map

| Component | Where | Plan |
|---|---|---|
| Core: dry-run helpers, preflight, packages, layer runner | `share/haseen/lib/` | 001 |
| CLI router, layer commands, doctor, installer | `bin/haseen`, `bin/haseen-layer-*`, `bin/haseen-doctor`, `install.sh` | 001 |
| Install picker: layers and optional setup steps, `~/.config/haseen/install.toml`, reuse last choices | `share/haseen/lib/install-picker.sh`, `install.sh` | 063 |
| Secure Boot | `share/haseen/layers/secureboot/`, `bin/haseen-secureboot-*` | 002 |
| Base, desktop, gaming, Hyprland Lua defaults | `share/haseen/layers/{base,desktop,gaming}/`, `share/haseen/default/hypr/` | 003 |
| Themes and hooks | `share/haseen/layers/theme/`, `share/haseen/themed/`, `share/haseen/themes/`, `bin/haseen-theme-*`, `bin/haseen-hook` | 004 |
| Shell core and plugin CLI | `share/haseen/shell/`, `bin/haseen-shell-*`, `bin/haseen-plugin-*` | 005 |
| Local AI | `share/haseen/layers/ai/`, `bin/haseen-ai-*` | 006 |
| DMS swap-in | `share/haseen/layers/dms/`, `bin/haseen-shell-use` | 008 |
| NixOS | `flake.nix`, `nix/` | 009 |
| Notifications, OSD, launcher, lock, idle, polkit, session | `share/haseen/shell/plugins/haseen.*` | 010 |
| Omarchy and DMS plugin compat | `share/haseen/shell/Compat/` + 6 root symlinks | 011 |
| Extended luna-plugin compatibility | `share/haseen/shell/Compat/Omarchy/`, `share/haseen/shell/Compat/Runtime.qml`, `share/haseen/shell/Compat/ShellApi.qml`, `bin/haseen-plugin-settings` | 027 |
| AI panel and agent skill | `share/haseen/shell/plugins/haseen.ai/`, `share/haseen/agents/skills/haseen/` | 012 |
| Screen frame, transparent bar, tray | `share/haseen/shell/{Frame*,Bar}.qml`, `bin/haseen-bar-*`, `haseen.tray` | 015 |
| Menu (Omarchy 4's tree and look, haseen's commands and rows) | `share/haseen/shell/plugins/haseen.menu/`, `share/haseen/default/menu.jsonc`, `bin/haseen-{menu,about,system,setup-*,font-*,branding,config-*}` | 016 068 |
| Flatpak-first install/remove, update | `share/haseen/default/catalog.json`, `share/haseen/lib/{catalog,terminal}.sh`, `bin/haseen-{install,remove,update,time,password,restart,refresh}`, `share/haseen/layers/flatpak/` | 017 |
| Capture, recording, emoji, toggles, hardware, share, tests | `bin/haseen-{capture,reminder,toggle,hardware,share,test}-*`, `haseen.emoji` | 018 |
| Screensaver (ttfx + native), night light, stay awake, DND | `haseen.{screensaver,nightlight,idle,notifications}`, `share/haseen/shell/Haseen/Flags.qml` | 019 |
| 22 Omarchy themes, backgrounds, picker | `share/haseen/themes/`, `bin/haseen-theme-{fetch,bg}`, `haseen.themepicker`, `haseen-background.service` | 020 |
| Starter widgets | `haseen.{sysusage,privacy,workspaces,media,calendar,clipboard,weather,bluetooth,network}` | 021, 022 |
| Migration ledger | `bin/haseen-migrate*`, `share/haseen/lib/migrate.sh`, `share/haseen/migrations/`, `share/haseen/systemd/user/haseen-migrate-notify.service` | 028 |
| Dual boot (EFI BootNext) and drives | `bin/haseen-boot-*`, `bin/haseen-drive-*`, `share/haseen/shell/plugins/haseen.session/` | 029 |
| Keybind sheet; Learn's keybinding and tmux lists | `bin/haseen-keybinds`, `bin/haseen-keybinds-list`, `bin/haseen-tmux-keybinds`, `bin/haseen-menu-select`, `share/haseen/lib/keybinds-scan.lua`, `share/haseen/shell/plugins/haseen.keybinds/` | 030 071 |
| Hardware quirks (DMI table) | `share/haseen/lib/hardware.sh`, `share/haseen/hardware/`, `bin/haseen-hw-*` | 031 |
| Sampling daemon (Go) | `core/`, `share/haseen/shell/Haseen/Sidecar.qml`, `bin/haseen-sidecar`, `tools/build-sidecar.sh` | 032 |
| Wallpaper palettes | `core/internal/palette/`, `core/cmd/haseen-palette`, `bin/haseen-theme-wallpaper` | 034 |
| Hibernation | `bin/haseen-hibernation-*`, `share/haseen/lib/hibernate.sh` | 033 |
| Power profiles, speaker tuning, web apps, notifications, seeds | `bin/haseen-{powerprofile,audio-tuning,webapp,notification,seed}-*`, `share/haseen/{audio,default}/` | 033 |
| Plugin registry and lockfile | `share/haseen/shell/lib/registry.sh`, `bin/haseen-plugin-{registry,search,install,update,restore,uninstall,lock}` | 035 |
| Login: splash, greeter, autologin | `share/haseen/lib/{greeter,plymouth,boot}.sh`, `bin/haseen-{greeter,setup-greeter,plymouth-set,plymouth-status}`, `share/haseen/shell/greeter/` | 036 |
| Optional VAPT workstation provisioning | `share/haseen/layers/vapt/`, `share/haseen/default/vapt/`, `bin/haseen-vapt-*`, `docs/vapt.md` | 007, 083 |
| Omarchy import, gestures, lock recovery, crash watch | `bin/haseen-{import-omarchy,gestures-apply,lock-release,crash-watch}`, `share/haseen/lib/{omarchy-import,gestures}.sh`, `share/haseen/shell/plugins/haseen.gestures/` | 048 |
| Dotfiles (yadm): backup, then the repo wins | `bin/haseen-setup-dotfiles`, `tests/test-dotfiles.sh` | 055 |
| Shell recovery and safe mode | `bin/haseen-shell-recover`, `share/haseen/systemd/user/haseen-shell-recover.service`, `share/haseen/shell/Haseen/Plugins.qml` (`held`) | 061 |
| haseen.nvim: the owner's Neovim config, fetched at a pin; theme bridge | `bin/haseen-setup-nvim`, `share/haseen/default/nvim/`, `tests/test-haseen-nvim.sh` | 065 |
| Tests | `tests/run.sh`, `tests/test-*.sh`, `tests/fixtures/*` | each plan |

`plans/README.md` holds the live status of every plan. Plan 007 (security
tooling), dropped by the owner on 2026-10-04, was reinstated on 2026-10-07 as
the optional `vapt` layer; plan 083 extends its inventory.

## Decisions

`docs/decisions/` holds the ADRs, all chosen by the owner on 2026-10-04:
- 0001: replace Omarchy
- 0002: MIT
- 0003: own shell, DMS swap-in, plugin compat
- 0004: installer now, PKGBUILDs later

## Gates

All three passed at the last integration (2026-10-04):

```sh
SHELLCHECK=/tmp/tools/shellcheck tools/lint.sh   # lint OK
tests/run.sh                                     # 2890/2890
tools/check-docs.sh                              # OK
```

shellcheck is not installed on the author's laptop; the static release binary
is used. nix is used through nix-portable (`/tmp/tools/np`; see plan 009 for
setup).

## Release gates (open)

- **Plan 032 (sidecar).** The Nix package does not build `haseen-sidecar`
  (it would need `buildGoModule` and a vendor hash), so a NixOS install has no
  `sysusage` capability and the widget hides. The NVIDIA branch of the daemon
  (`nvidia-smi -l` stream) has no hardware here and is unverified; the amdgpu,
  i915 and xe branches were exercised against fixtures, i915 also live. There is
  no `strace` on the author's machine, so "who does the work" was measured with
  `/proc/<pid>/io` read counters.
- **Plan 014.** No end-to-end run on a real CachyOS machine or VM yet. The
  author's session has no qemu, no passwordless sudo and no docker group.
  Everything was fixture-tested, and only the user-level parts were run live.
  Still unproven:
  - greetd login
  - the uwsm session
  - Secure Boot enrollment on real firmware (the author's laptop is in Setup Mode, so it is the natural first target, with the owner at the keyboard)
  - the polkit dialog
  - the real session lock
  - display power-off
  - Ollama on hardware
  - the live DMS switch
- **Plan 013.** PKGBUILDs are a later phase.
- **Resolved: portal crash notifications.** The "Process crashed:
  xdg-desktop-portal-hyprland" notifications came from scratch shells run
  under `dbus-run-session`. qs activated the portal and xdph on the private
  bus, and xdph segfaulted when that bus was torn down. `tools/smoke-session.conf`
  defines a bus with no service directories, so nothing can be activated, and
  the final integrated smoke left 0 coredumps.
- **Not verified live (would need pointer events):** double-click
  transparency on the bar (the IPC path was verified), tray hover, workspace and
  media clicks.
- **Legacy source limits (plan 027):** whole-bar clones require the original
  Omarchy bar host; original direct IpcHandler children can duplicate on
  multiple screens. Nearby Share, Nook and several original helpers read or
  write the old Omarchy config directly; the host does not reinterpret or
  modify that source. Backends, device access and credentials were not tested
  by importing a widget alone. Keep native defaults and opt in deliberately.
- **Protected smoke:** all 54 original entries were compiled without
  activation (53 ready; whole-bar clone failed). A read-only offline namespace
  then constructed 29 widgets/companions and showed the original agents,
  Tailscale and KDE Connect panels. No original plugin bytes changed. That
  29-widget configuration measured 278 MiB RSS before opening panels and
  291 MiB after; it is not the default low-resource layout.

## Working rules learned the hard way

- Never inject keystrokes (`wtype`/`ydotool`) on the live session. One agent
  typed into the owner's terminal. Drive panels through IPC (`qs -p … ipc
  call`); `settings.debugIpc` exposes test hooks on the launcher and session
  panels.
- Run scratch shells as `dbus-run-session --config-file=$PWD/tools/smoke-session.conf -- env XDG_CONFIG_HOME=… XDG_STATE_HOME=… XDG_CACHE_HOME=… QT_NO_XDG_DESKTOP_PORTAL=1 qs -p share/haseen/shell`.
  Keep the real `XDG_RUNTIME_DIR`: moving it hides the Hyprland and PipeWire
  sockets. Only run one scratch instance at a time, so IPC cannot cross into
  another instance.
- Kill only the PIDs you started (record `$!`). Two agents killed each other's
  instances with `pkill -f`/`pgrep | head`.
- Disable `haseen.idle`, `haseen.lock`, `haseen.polkit`, `haseen.screensaver`
  and `haseen.nightlight` in scratch configs, or a smoke can lock, blank or
  tint the owner's session.
- Never remove or rewrite the owner's Omarchy/DMS plugin dirs (AGENTS.md).
  A backup of luna's set is at `~/Backups/luna/omarchy-plugins-20261004/`.
