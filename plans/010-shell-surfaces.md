# Plan 010: Shell system surfaces

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Without a notification server, OSD, launcher, lock, idle handling and a polkit agent this is a bar, not a desktop.

## Scope

Built-in plugins: `haseen.notifications`, `haseen.osd`, `haseen.launcher`, `haseen.lock`, `haseen.idle`, `haseen.polkit` and `haseen.session`.

## Acceptance

- Each one is exercised live on the session.
- The lock is tested with a PAM stub service, never with the real login.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
