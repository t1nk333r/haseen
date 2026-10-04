# Handoff — haseen

Orientation for whoever picks this up next, human or agent. Updated 2026-10-04.

## What this repo is

haseen (حصين, "fortified") is the owner's own desktop base, replacing
Omarchy as the foundation (ADR 0001). It installs on top of an existing
CachyOS system and adds opt-in layers. It lifts selected parts of Omarchy
(themes, CLI conventions) and DankMaterialShell (an optional runtime shell,
plus plugin compat), and takes design ideas from end-4 and caelestia
(reference only, because they are GPL).

The owner's other repos:
- `t1nk333r/omacachy`: Omarchy on CachyOS. Its helper conventions and ESP
  detection were adopted here.
- `gitlab.com/t1nk33r/waydots`: the owner's yadm overlay. It becomes the
  personal layer on top of haseen; its Omarchy plugins are the first users of
  the compat adapter (plan 011).

## Map

| Component | Where | State |
|---|---|---|
| Core: dry-run helpers, preflight, packages, layer runner | `share/haseen/lib/` | plan 001 |
| CLI router and layer commands | `bin/haseen`, `bin/haseen-layer-*`, `bin/haseen-doctor` | plan 001 |
| Installer | `install.sh` | plan 001 |
| Layers | `share/haseen/layers/*` | plans 002–008 |
| Shell | `share/haseen/shell/` | plans 005, 010–012 |
| NixOS | `flake.nix`, `nix/` | plan 009 |
| Tests | `tests/run.sh`, `tests/fixtures/*` | grows with each plan |

`plans/README.md` holds the live status of every plan.

## Decisions

`docs/decisions/` (ADRs). The owner chose these on 2026-10-04:
- ADR 0001: haseen replaces Omarchy rather than layering on it.
- ADR 0002: MIT license; GPL projects are reference only.
- ADR 0003: own minimal Quickshell shell, with DMS as a swap-in and Omarchy/DMS
  plugin compat.
- ADR 0004: installer now, PKGBUILDs later; PREFIX /usr/local.

## Release gates (open)

- No end-to-end run on a real CachyOS guest yet (plan 014). The author's
  session has no qemu, no passwordless sudo and no docker group, so
  everything so far is fixture-tested and live-tested only for user-level
  parts (the shell).
- Secure Boot key enrollment has not run on real firmware. The author's
  laptop is in Setup Mode, so it is the natural first target, but only with
  the owner at the keyboard.
