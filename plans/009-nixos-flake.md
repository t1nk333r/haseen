# Plan 009: NixOS flake

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 003 004 005 002
- **Category**: nix
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 7. NixOS gets the same desktop, with lanzaboote handling Secure Boot.

## Scope

- `flake.nix` exposing `nixosModules.haseen`, `homeManagerModules.haseen` and `packages.haseen`.
- lanzaboote wiring.
- `nix/README.md`.

## Acceptance

- `nix flake check` passes.
- A NixOS VM configuration evaluates, i.e. `nix eval` of `config.system.build.toplevel.drvPath` succeeds.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
