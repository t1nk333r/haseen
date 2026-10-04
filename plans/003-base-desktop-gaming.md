# Plan 003: Base, desktop and gaming layers

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: desktop
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

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

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
