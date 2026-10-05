# Plans

The numbered engineering record. Every change of substance has a plan file;
this table is the index, and `tools/check-docs.sh` keeps the two in sync.
Read `handoff.md` first.

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001 | Foundation: layer runner, CLI router, dry-run contract, fixtures | P1 | M | — | DONE 2026-10-04 |
| 002 | Secure Boot layer for Windows dual boot | P1 | L | 001 | DONE 2026-10-04 (205 tests; read-only live `status` ok; firmware enrollment = owner step, plan 014) |
| 003 | Base, desktop and gaming layers | P1 | L | 001 | DONE 2026-10-04 (128 tests; `Hyprland --verify-config` ok; real login pending 014) |
| 004 | Theme pipeline compatible with Omarchy colors.toml | P1 | M | 001 | DONE 2026-10-04 (215 tests; byte-parity with Omarchy renderer) |
| 005 | Quickshell shell core and plugin host | P1 | L | 001 | DONE 2026-10-04 (157 tests; live bar screenshot; 178 MiB RSS idle vs omarchy-shell 630) |
| 006 | Local AI layer | P2 | M | 001 | DONE 2026-10-04 (164 tests; live streamed chat vs stub server) |
| 007 | VAPT tooling layer | — | — | 001 | DROPPED 2026-10-04 (owner decision; out of scope) |
| 008 | DMS optional layer and shell switch | P2 | S | 005 | DONE 2026-10-04 (99 tests; `systemd-analyze verify` ok; live switch pending, DMS not installed) |
| 009 | NixOS flake | P2 | L | 003 004 005 002 | DONE 2026-10-04 (`nix flake check` + toplevel eval + package build via nix-portable; no boot) |
| 010 | Shell system surfaces | P1 | L | 005 | DONE 2026-10-04 (75 tests; live notifications/OSD/launcher/session/lock-preview; polkit + real lock pending 014) |
| 011 | Omarchy and DMS plugin compat adapters | P2 | L | 005 | DONE 2026-10-04 (live: 6 Omarchy + 6 DMS widgets render; 7 out-of-scope fail in isolation) |
| 012 | AI panel plugin and the haseen agent skill | P2 | M | 005 006 | DONE 2026-10-04 (75 tests; live streamed chat over IPC; skill followed end to end) |
| 013 | PKGBUILDs for the stable layers | P3 | M | 001-012 | PLANNED (later phase, owner decision 2026-10-04) |
| 014 | End-to-end acceptance on a real CachyOS guest | P1 | M | 001-012 | BLOCKED: no qemu, no sudo and no docker access on the author's laptop session (2026-10-04) |
| 015 | Screen frame, adaptive transparent bar, hover tray | P1 | L | 005 010 011 | DONE 2026-10-04 (127 tests; frame zones live; double-click/hover need pointer = unverified) |
| 016 | Omarchy-style menu with the owner's item selection | P1 | L | 005 010 011 | DONE 2026-10-04 (199 tests; live navigation over IPC) |
| 017 | Install/Remove (Flatpak-first) and Update | P1 | L | 005 010 011 | DONE 2026-10-04 (125 tests; 30/30 Flathub refs verified) |
| 018 | Trigger: capture, screen recording, emoji, reminders, toggles, hardware, share, tests | P1 | L | 005 010 011 | DONE 2026-10-04 (179 tests; live screenshot, 2 s recording, emoji panel) |
| 019 | Screensaver (Omarchy ttfx + native), nightlight, idle prevention, DND | P1 | L | 005 010 011 | DONE 2026-10-04 (ttfx default; tests pass; idle lock/hyprsunset live pending 014) |
| 020 | All 22 Omarchy themes, fetched backgrounds, theme picker | P1 | L | 005 010 011 | DONE 2026-10-04 (22 themes = all of Omarchy's; real pinned fetch; picker live) |
| 021 | Starter widgets A: system usage, privacy dots, Omarchy workspaces, media, calendar | P1 | L | 005 010 011 | DONE 2026-10-04 (65 tests; live sysusage/privacy/workspaces/media/calendar) |
| 022 | Starter widgets B: clipboard history, weather, Bluetooth and Wi-Fi panels | P1 | L | 005 010 011 | DONE 2026-10-04 (59 tests; live panels; no real connects) |
| 023 | Package source order: repos, Chaotic-AUR, AUR last | P1 | S | 001 003 017 | DONE 2026-10-04 (source-order + chaotic layer tests) |
| 024 | Omarchy repo as a package source (after Chaotic-AUR, never Omarchy itself) | P2 | S | 023 | DONE 2026-10-04 (source-order + layer tests) |
| 025 | haseen.pager: omapager port as the default notification daemon | P1 | L | 010 | DONE 2026-10-04 |
| 026 | haseen.prayers: omaprayers port (Riyadh defaults, city-level) | P2 | M | 005 | DONE 2026-10-04 |
| 027 | Luna plugins: panels, controls, scoped host APIs and service lifecycle | P1 | L | 005 011 025 026 | DONE 2026-10-05 (3,060+ tests; 29 imported widgets in a protected sandbox) |
| 028 | Migration ledger: one-off upgrade steps, run once per user | P1 | S | 001 | DONE 2026-10-05 (30 tests; live apply + retry) |
| 029 | Dual-boot control (EFI BootNext) and drive helpers | P1 | M | 001 002 010 | DONE 2026-10-05 (43 tests; BootNext set and cleared live) |
| 030 | Keybind registry and searchable cheat sheet | P2 | M | 003 005 010 | DONE 2026-10-05 (17 tests; 234 live binds on screen) |
| 031 | Hardware quirk table and dispatcher (DMI matching, ledger-backed) | P1 | M | 001 003 028 | DONE 2026-10-05 (47 tests; real DMI matched live) |
