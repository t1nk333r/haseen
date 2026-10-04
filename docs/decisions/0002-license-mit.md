# ADR 0002: MIT license; GPL projects are reference only

- **Status**: accepted 2026-10-04 (owner)

## Context

| Source | License | Evidence |
|---|---|---|
| Omarchy | MIT | `/tmp/ref/omarchy/LICENSE` |
| DankMaterialShell | MIT, relicensed from GPL-3.0 | `quickshell/LICENSE_CHANGE_12_11_2025.md` |
| end-4 dots-hyprland | GPL-3.0 | `LICENSE` |
| caelestia shell | GPL-3.0 | `LICENSE` |

## Decision

haseen is MIT. Adapted Omarchy and DMS code keeps its notice in the file header and gets a row in `NOTICE.md`. From end-4 and caelestia we re-implement only the documented ideas: the AI provider adapter split, ref-counted polling and PAM lock contexts. We copy no code from them.

## Consequences

Plugin authors may use any license. Reviewers reject diffs that paste GPL code.
