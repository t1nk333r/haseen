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
| Secure Boot | `share/haseen/layers/secureboot/`, `bin/haseen-secureboot-*` | 002 |
| Base, desktop, gaming, Hyprland Lua defaults | `share/haseen/layers/{base,desktop,gaming}/`, `share/haseen/default/hypr/` | 003 |
| Themes and hooks | `share/haseen/layers/theme/`, `share/haseen/themed/`, `share/haseen/themes/`, `bin/haseen-theme-*`, `bin/haseen-hook` | 004 |
| Shell core and plugin CLI | `share/haseen/shell/`, `bin/haseen-shell-*`, `bin/haseen-plugin-*` | 005 |
| Local AI | `share/haseen/layers/ai/`, `bin/haseen-ai-*` | 006 |
| DMS swap-in | `share/haseen/layers/dms/`, `bin/haseen-shell-use` | 008 |
| NixOS | `flake.nix`, `nix/` | 009 |
| Notifications, OSD, launcher, lock, idle, polkit, session | `share/haseen/shell/plugins/haseen.*` | 010 |
| Omarchy and DMS plugin compat | `share/haseen/shell/Compat/` + 6 root symlinks | 011 |
| AI panel and agent skill | `share/haseen/shell/plugins/haseen.ai/`, `share/haseen/agents/skills/haseen/` | 012 |
| Tests | `tests/run.sh`, `tests/test-*.sh`, `tests/fixtures/*` | each plan |

`plans/README.md` holds the live status of every plan. Plan 007 (security
tooling) was dropped by the owner and is out of scope.

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
tests/run.sh                                     # 1283/1283
tools/check-docs.sh                              # OK
```

shellcheck is not installed on the author's laptop; the static release binary
is used. nix is used through nix-portable (`/tmp/tools/np`; see plan 009 for
setup).

## Release gates (open)

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
- **Observed during the live smokes, not isolated.** Several agents ran
  parallel shell instances, and the desktop showed repeated "Process crashed:
  xdg-desktop-portal-hyprland" notifications. Each extra Quickshell instance
  also logs "Failed to register with host portal". Re-check this with a single
  instance in plan 014.

## Working rules learned the hard way

- Never inject keystrokes (`wtype`/`ydotool`) on the live session. One agent
  typed into the owner's terminal. Drive panels through IPC (`qs -p … ipc
  call`); `settings.debugIpc` exposes test hooks on the launcher and session
  panels.
- Give each scratch shell instance its own `XDG_RUNTIME_DIR` (and
  `dbus-run-session` for notifications). Otherwise IPC calls and D-Bus names
  cross into other instances.
- Disable `haseen.idle` and `haseen.lock` in scratch configs, or a smoke can
  lock the owner's session.
