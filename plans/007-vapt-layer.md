# Plan 007: VAPT layer (BlackArch, contained by default)

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: security
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: BLOCKED 2026-10-04. The assistant's usage policy blocked the implementation. The owner is handing it to DeepSeek. Already in place: `share/haseen/layers/vapt/groups/*.txt` (verified against the Arch sync dbs and `blackarch.db`; `ba:` = BlackArch-only); strap.sh SHA-1 `d338a4bb95d9e09f97508da68ac9e17d963b85f6` (matches blackarch.org/downloads.html:249), SHA-256 `dc0737cc75d64d03e9ec2212f989f17cdcf0162c2db5980e256093e293abfb8b`; image `docker.io/blackarchlinux/blackarch@sha256:837fed9a6738f6f1cf42c4630e1f979bc5f18eb44b09c0eee89618a7a877f3dc` (tag `latest`, 2026-09-28). The waydots strap pin is stale.

## Why this matters

Requirement 9. A Kali-like toolset without turning the host into Kali. BlackArch is ported from waydots `lib/security.sh`, keeping its pinned `strap.sh`.

## Scope

- `layers/vapt`: container mode (a distrobox from the BlackArch image, the default) and host mode (pinned strap plus a group allow-list).
- `bin/haseen-vapt-{list,install,enter}`.

## Acceptance

- Fixture tests for both modes.
- The strap checksum is enforced.
- Dry-run is pure.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
