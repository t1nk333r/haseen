# Plan 004: Theme pipeline compatible with Omarchy colors.toml

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001
- **Category**: theme
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 4: Omarchy themes have to install unchanged, and every app has to be themed from one source.

## Scope

- `layers/theme`.
- `bin/haseen-theme-{set,list,current,install}` and `bin/haseen-hook`.
- `share/haseen/themed/*.tpl` and stock themes.
- The renderer is adapted from omarchy `omarchy-theme-set-templates` (MIT).

## Acceptance

- Rendering every stock theme produces the expected files.
- Installing an Omarchy theme from a git URL works offline in tests (local repo).
- `shell.json` carries every key listed in architecture §7.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
