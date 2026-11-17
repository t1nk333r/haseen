# Plan 173: CapsLock is Caps Lock again

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW–MEDIUM. A default every user types with changes: CapsLock
  toggles Caps Lock instead of starting a Compose sequence, and haseen's
  compose sequences have no key until a user binds one.
- **Depends on**: 003 (input defaults), 056 (keyd), 103 (greeter layout)
- **Category**: desktop
- **Planned at**: 2026-11-14, from the owner ("drop compose:caps", while
  reviewing plan 172)
- **State**: DONE 2026-11-14 (`tests/test-greeter.sh`; a live session after
  a re-login is an owner step)

## Problem

haseen's Hyprland input set `kb_options = "compose:caps"`
(`share/haseen/default/hypr/input.lua:30` before this plan), Omarchy's value
(`/usr/share/omarchy/default/hypr/input.lua:37`). The login screen copied it
(`bin/haseen-greeter:80`, plan 103). So the Caps key never turned Caps Lock
on: plan 079's lock-key OSD read "nothing changed" on it
(`plans/079-osd-kinds.md:44`), and plan 172's lock-screen warning would have
had nothing to warn about. The owner, 2026-11-14: "drop compose:caps".

## Decision

- `input.lua` starts from empty `kb_options`; a non-Latin first layout still
  gets `us` in front and `grp:alts_toggle` (both Alts switch), now as the only
  option. A comment points to `~/.config/hypr/local.lua` for a Compose key.
- `bin/haseen-greeter` follows, so the login screen and the desktop keep
  typing the same way (plan 103's rule; `tests/test-greeter.sh` compares the
  two and its four expectations lose `compose:caps`).
- Comments that named CapsLock as Compose say what is true now:
  `share/haseen/default/hypr/binds.lua` (the lock-key bind),
  `share/haseen/default/xcompose/compose`, the `~/.XCompose` seed template
  (`share/haseen/seeds/40-xcompose.sh`) and `share/haseen/default/fcitx5/conf/xcb.conf`.
- With keyd on nothing changes for a CapsLock tap (Escape) or hold (hyper);
  RightAlt + CapsLock, which plan 056 noted became Compose
  (`plans/056-keyd.md:33`), is a real Caps Lock again.
- No migration: `input.lua` is haseen's file, read by the user's config, so
  the change reaches everyone with the update and a Hyprland reload. A user
  `~/.XCompose` written before this plan keeps its old comment; haseen never
  edits a seeded file.

## Rejected

- **Moving Compose to another key** (`compose:ralt`, `compose:menu`):
  RightAlt is half of `grp:alts_toggle` on non-Latin layouts and AltGr on
  many Latin ones; most laptops have no Menu key. Not asked for; a user picks
  one in `local.lua`.
- **Keeping Omarchy's `shift:both_capslock_cancel`**: haseen never shipped it,
  and it only mattered beside a Compose CapsLock.
- **Dropping the XCompose seed and sequences**: they still work for anyone
  who binds a Compose key, and an unused include costs nothing.

## Evidence

- `tests/test-greeter.sh`: the desktop's `input.lua` and the greeter's
  generated config agree for every vconsole case, with `[]` options for a
  Latin layout and `[grp:alts_toggle]` for Arabic and Russian.
- `grep -rn 'compose:caps' bin share tests` finds nothing but the
  `hyprctl devices` fixtures under `tests/fixtures/keyboard/`, which are
  recorded output and say nothing about the default.
