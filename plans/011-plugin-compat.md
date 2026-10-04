# Plan 011: Omarchy and DMS plugin compat adapters

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (API surface)
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 4. The owner has about 29 `t1nk33r.*` Omarchy plugins in waydots, and the DMS plugin registry is large.

## Scope

`shell/Compat/`: the Omarchy plugin imports and the DMS `qs.Common`/`qs.Services`/`qs.Widgets` subset, plus manifest adapters in the registry.

## Acceptance

- At least three real Omarchy plugins from waydots and three DMS examples from `quickshell/PLUGINS/` load and render live.
- Unsupported APIs fail per plugin.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
