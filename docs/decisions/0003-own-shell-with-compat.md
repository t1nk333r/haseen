# ADR 0003: own minimal Quickshell shell; DMS as swap-in; Omarchy and DMS plugin compat

- **Status**: accepted 2026-10-04 (owner)

## Options considered

1. **Own minimal shell.** Chosen.
2. **DMS as the default, curated.** Rejected as the default. It runs a Go daemon next to `qs`, has a Material look, and our identity would only exist in plugins. It remains available as a swap-in (plan 008).
3. **Fork of the decoupled Omarchy shell.** Rejected. We would have to maintain a fork of a 72 KB `shell.qml` that changes quickly, and its `OMARCHY_PATH` coupling is baked in by policy (Omarchy AGENTS.md forbids fallbacks).

## Decision

haseen ships its own small shell with a plugin host (docs/architecture.md §5). Only one shell runs at a time, because DMS also claims `org.freedesktop.Notifications`, the polkit agent and the session lock (DMS `assets/systemd/dms.service`: `Type=dbus`, `BusName=org.freedesktop.Notifications`). The `haseen-shell.service` and `dms.service` units conflict. Omarchy and DMS plugins load through adapters that provide their import names on top of `qs.Haseen` (plan 011).

## Consequences

- We own a notification server, OSD, launcher, lock, idle handling and a polkit agent (plan 010).
- The compat surface is the riskiest part. Its scope is limited to what real plugins use (plan 011's acceptance list).
