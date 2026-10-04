# Plan 006: Local AI layer

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001
- **Category**: ai
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 6. Bind to loopback only: waydots plan 020 found Ollama exposed on the LAN.

## Scope

- `layers/ai`: Ollama with the GPU-matched package, or llama.cpp.
- `share/haseen/default/ai.json`.
- `bin/haseen-ai-{status,models,pull,chat}`.

## Acceptance

- Fixture tests choose the right backend package for intel, amd and nvidia.
- The service drop-in binds to 127.0.0.1.
- `haseen ai chat` talks to any OpenAI-compatible endpoint, verified against a local stub server.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
