# Plan 012: AI panel plugin and the haseen agent skill

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 005 006
- **Category**: ai
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 2 (an agent can extend the desktop safely) and requirement 6 (local AI in the UI).

## Scope

- `haseen.ai` panel plugin: OpenAI-compatible streaming chat, local-only policy by default.
- `share/haseen/agents/skills/haseen/SKILL.md` and its topic files.
- `haseen ai skill install` symlinks the skill into agent skill directories.

## Acceptance

- A live chat against Ollama, or a stub endpoint.
- An agent following only the skill creates a working plugin.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
