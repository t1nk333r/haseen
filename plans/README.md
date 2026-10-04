# Plans

The numbered engineering record. Every change of substance has a plan file;
this table is the index, and `tools/check-docs.sh` keeps the two in sync.
Read `handoff.md` first.

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001 | Foundation: layer runner, CLI router, dry-run contract, fixtures | P1 | M | — | DONE 2026-10-04 |
| 002 | Secure Boot layer for Windows dual boot | P1 | L | 001 | PLANNED |
| 003 | Base, desktop and gaming layers | P1 | L | 001 | PLANNED |
| 004 | Theme pipeline compatible with Omarchy colors.toml | P1 | M | 001 | PLANNED |
| 005 | Quickshell shell core and plugin host | P1 | L | 001 | PLANNED |
| 006 | Local AI layer | P2 | M | 001 | PLANNED |
| 007 | VAPT layer (BlackArch, contained by default) | P2 | M | 001 | PLANNED |
| 008 | DMS optional layer and shell switch | P2 | S | 005 | PLANNED |
| 009 | NixOS flake | P2 | L | 003 004 005 002 | PLANNED |
| 010 | Shell system surfaces | P1 | L | 005 | PLANNED |
| 011 | Omarchy and DMS plugin compat adapters | P2 | L | 005 | PLANNED |
| 012 | AI panel plugin and the haseen agent skill | P2 | M | 005 006 | PLANNED |
| 013 | PKGBUILDs for the stable layers | P3 | M | 001-012 | PLANNED (later phase, owner decision 2026-10-04) |
| 014 | End-to-end acceptance on a real CachyOS guest | P1 | M | 001-012 | BLOCKED: no qemu, no sudo and no docker access on the author's laptop session (2026-10-04) |
