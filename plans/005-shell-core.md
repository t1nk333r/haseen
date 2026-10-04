# Plan 005: Quickshell shell core and plugin host

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirements 1, 2, 3 and 5. A shell we own, small enough to read in one sitting.

## Scope

- `share/haseen/shell/`: `shell.qml`, `Haseen/` singletons, `Haseen/Widgets/`, the plugin registry, the bar, and built-in bar widgets.
- `plugin.schema.json`.
- `bin/haseen-shell-{run,restart,ipc}` and `bin/haseen-plugin-{list,new,validate,info,enable,disable}`.
- `layers/shell` and `haseen-shell.service`.

## Acceptance

- The shell runs under `qs -p` on the live session with no QML errors.
- A screenshot proves the bar renders.
- `haseen plugin new` → `haseen plugin validate` → the plugin appears after a hot reload.
- Idle RSS is measured and recorded.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
