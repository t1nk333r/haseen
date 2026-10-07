# Handoff — haseen

Orientation for whoever picks this up next, human or agent. Updated 2026-10-07.

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
| Brightness command, DDC setup, display panel | `bin/haseen-brightness`, `bin/haseen-setup-ddc`, `share/haseen/shell/plugins/haseen.display/` | 077 |
| Media panel (cover art, seek, switcher) | `share/haseen/shell/plugins/haseen.media/`, `tools/fake-mpris.py` | 078 |
| Idle suspend, AC/battery timeouts | `share/haseen/shell/plugins/haseen.idle/`, `bin/haseen-setup-idle`, `tests/test-idle.sh` | 019 082 |
| Hardware quirks (DMI table) | `share/haseen/lib/hardware.sh`, `share/haseen/hardware/`, `bin/haseen-hw-*` | 031 |
| Sampling daemon (Go) | `core/`, `share/haseen/shell/Haseen/Sidecar.qml`, `bin/haseen-sidecar`, `tools/build-sidecar.sh` | 032 |
| Wallpaper palettes | `core/internal/palette/`, `core/cmd/haseen-palette`, `bin/haseen-theme-wallpaper` | 034 |
| Hibernation | `bin/haseen-hibernation-*`, `share/haseen/lib/hibernate.sh` | 033 |
| Power profiles, speaker tuning, web apps, notifications, seeds | `bin/haseen-{powerprofile,audio-tuning,webapp,notification,seed}-*`, `share/haseen/{audio,default}/` | 033 |
| Plugin registry and lockfile | `share/haseen/shell/lib/registry.sh`, `bin/haseen-plugin-{registry,search,install,update,restore,uninstall,lock}` | 035 |
| Login: splash, greeter, autologin | `share/haseen/lib/{greeter,plymouth,boot}.sh`, `bin/haseen-{greeter,setup-greeter,plymouth-set,plymouth-status}`, `share/haseen/shell/greeter/` | 036 |
| Omarchy import, gestures, lock recovery, crash watch | `bin/haseen-{import-omarchy,gestures-apply,lock-release,crash-watch}`, `share/haseen/lib/{omarchy-import,gestures}.sh`, `share/haseen/shell/plugins/haseen.gestures/` | 048 |
| Dotfiles (yadm): backup, then the repo wins | `bin/haseen-setup-dotfiles`, `tests/test-dotfiles.sh` | 055 |
| Shell recovery and safe mode | `bin/haseen-shell-recover`, `share/haseen/systemd/user/haseen-shell-recover.service`, `share/haseen/shell/Haseen/Plugins.qml` (`held`) | 061 |
| haseen.nvim: the owner's Neovim config, fetched at a pin; theme bridge | `bin/haseen-setup-nvim`, `share/haseen/default/nvim/`, `tests/test-haseen-nvim.sh` | 065 |
| Tests | `tests/run.sh`, `tests/test-*.sh`, `tests/fixtures/*` | each plan |

`plans/README.md` holds the live status of every plan. Plan 007 (security
tooling) was dropped by the owner and is out of scope.

## Decisions

`docs/decisions/` holds the ADRs, all chosen by the owner on 2026-10-04:
- 0001: replace Omarchy
- 0002: MIT
- 0003: own shell, DMS swap-in, plugin compat
- 0004: installer now, PKGBUILDs later

## State and queue (2026-10-07)

- `main` = 96193cf: plans up to 074 are merged (PRs #13–#34).
- Queued: the 8 gaps from `docs/reference-shell-gaps.md`, approved by the
  owner ("tackle all 8"). They land as one unit: one branch, luna/gaps, built
  gap after gap, one PR. Plan numbers are fixed:

  | Gap | Plan | Default |
  |---|---|---|
  | 1 low-battery warnings | 075 | ON (owner-approved; record in AGENTS.md) |
  | 4 power/battery panel | 076 | panel kind on `haseen.battery` |
  | 2 `haseen brightness` + `haseen.display` panel | 077 | panel OFF; `haseen setup ddc` OFF |
  | 3 media panel | 078 | panel kind on `haseen.media` |
  | 5 OSD mic/layout/lock keys | 079 | lock keys OFF |
  | 6 `haseen.kblayout` widget | 080 | OFF |
  | 7 launcher providers: windows, emoji, commands, web | 081 | each OFF |
  | 8 idle suspend + AC/battery timeouts | 082 | `suspendAfter` 0 (never) |

  The next free plan number after them is 083.

## Gates

Run before every PR, all from the repo root:

```sh
SHELLCHECK=$(command -v shellcheck) GO=<go ≥ 1.26> tools/lint.sh
QT_QPA_PLATFORM=offscreen tests/run.sh   # ≈ 6100 checks, 8–11 min: run it in tmux
tools/check-docs.sh
tools/secrets.sh                          # before every push
```

`core/go.mod` needs Go ≥ 1.26; pass a mise-installed Go as `GO=` when the
system one is older. nix is used through nix-portable (plan 009). Tests are
behavioural only and run only through `tests/run.sh`; since plan 074
`tests/lib.sh` `sandbox()` cuts every test off the live session.

Every change lands by PR (AGENTS.md). Parallel PRs conflict only in
`plans/README.md`: keep every row, in number order. A PR that is BEHIND gets
`gh pr update-branch N`; one that is CLEAN but stuck is merged by hand.

## Developer tools (`tools/`)

- `tools/nest-launch.sh DIR [MODE]`: the only way to run UI proofs next to a
  live session. It starts a nested Hyprland on workspace 5, silently, through
  the owner's exec rule, and needs the owner session's
  `HYPRLAND_INSTANCE_SIGNATURE`. Wrap it in `flock ~/.cache/haseen-wt/nest.lock`.
  Screenshot with `WAYLAND_DISPLAY=$(cat DIR/socket) grim -o IO shot.png`.
  Stop with `kill -- -$(cat DIR/pid)`, then remove
  `$XDG_RUNTIME_DIR/hypr/$(cat DIR/sig)` and any `at-spi-bus-launcher` whose
  `DBUS_SESSION_BUS_ADDRESS` is a `/tmp/dbus-*` path (nest orphans take over
  the session's at-spi bus).
- `tools/vptr/`: a virtual pointer for drag and hover tests (`build.sh` builds
  it; `d`/`u` left, `rd`/`ru` right, `md`/`mu` middle button). Point it only at
  a nest, never at the live session.
- `tools/fake-upower.py`: a fake UPower and power-profiles-daemon for tests and
  nests (plan 075). Start it on a private `dbus-daemon` and give the shell the same
  `DBUS_SYSTEM_BUS_ADDRESS`. Each stdin line is a property change
  (`sleep=1 Percentage=10 State=2`). It refuses the real system bus.
- `tools/fake-mpris.py NAME [KEY=VALUE…]`: a fake MPRIS player for tests and
  nests (plan 078): capabilities, metadata, `omit=Shuffle,Volume` for properties
  a player lacks; every call and write is logged. Start it on a private
  `dbus-daemon` and give the shell the same `DBUS_SESSION_BUS_ADDRESS`. It
  refuses the login session's bus, where the owner's players are.
- `tools/sync-apply.sh REPO STAGE_TAR EXPECT_TSV DELETE_TSV`: moves a checkout
  that carries uncommitted WIP onto a new `main`. Per file changed between the
  last synced main and the new one: main's version where the checkout still
  has the old one, a 3-way `git merge-file` where it was edited, and a write
  only if the file still has the expected blob. Snapshot the WIP first with a
  temporary `GIT_INDEX_FILE` commit to `refs/sync/<host>-before-rN`.

## Installing a checkout with WIP on a machine

Build tree = checkout files (`git ls-files -co --exclude-standard`, so WIP is
included) plus `git diff <last-installed-main> origin/main` for code paths
(not docs, plans, nix, NOTICE, AGENTS, handoff, README) applied with
`patch -p1`. Then `./install.sh --tree-only --yes` with Go on `PATH`,
`systemctl --user daemon-reload`, `hyprctl reload`, `haseen migrate`, and
re-apply the theme.

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
- Work in worktrees under `~/.cache/haseen-wt/<dir>` created from
  origin/main, never in a checkout that holds WIP, and always with absolute
  paths: relative paths in agent edits corrupted a checkout twice. Never
  `git reset/stash/checkout --/restore/clean` in a shared worktree.
- No `qs ipc`, panel opens, shell restarts or `hyprctl dispatch/eval` against
  the owner's live shell. A menu opened live grabbed the keyboard while the
  owner typed and launched an app. UI proofs go in a nest (`tools/nest-launch.sh`).
- A shell restart used to kill apps it had launched (they sat in
  `haseen-shell.service`'s cgroup; plan 074 fixed it for new launches). Apps
  started by an older shell still die on restart: close them first.
