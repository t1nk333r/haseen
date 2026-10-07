# Plan 056: keyd — CapsLock as hyper, opt-in

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (opt-in; `off` gives CapsLock back)
- **Depends on**: —
- **Category**: input, setup
- **Planned at**: 2026-10-07, owner request (luna runs keyd 2.6.0)
- **State**: DONE 2026-10-07 (real key presses on io are an owner check)

## Problem and decision

On luna, keyd turns CapsLock into a hyper key: hold = Ctrl+Meta+Alt+Shift
(Hyprland `SUPER + SHIFT + ALT + CTRL`), tap = Escape, RightAlt+CapsLock =
CapsLock. Luna's waydots install it through `lib/keyd.sh`. io has no keyd.

- `bin/haseen-setup-keyd [on|off|status]` ships the mapping as
  `share/haseen/default/keyd/default.conf`. `on` installs `keyd` from `extra`
  (`pkg_install`), writes `/etc/keyd/default.conf`, runs
  `systemctl enable --now keyd.service` and `keyd reload`. A different existing
  config is copied to `default.conf.haseen-bak-<timestamp>` first, and the
  user is told where. If the package is installed, the config matches and the
  unit is enabled, it does nothing. `off` disables the unit and keeps the config.
  `status` (the default) prints installed / enabled / active / config state.
- **Off by default** (owner rule): nothing in install or the layers runs it.
  It is offered in the menu under Setup → CapsLock Hyper (keyd). haseen has no
  first-run optional-step list, so the menu is the only place it is offered.
- The default `binds.lua` has no `SUPER + SHIFT + ALT + CTRL` binds. There is
  no plan 043 snap layer in this tree. The Hyprland skill (`hyprland.md`) says
  hyper binds need keyd and belong in the user's `bindings.lua`.
- `input.lua` keeps `compose:caps`. With keyd on, CapsLock never reaches xkb
  as CapsLock except through RightAlt+CapsLock, which therefore becomes Compose.

## Verification

- `tests/run.sh tests/test-keyd.sh`: shipped mapping, dry-run plan on an empty
  sysroot, backup before replacing a differing config, nothing to do when it
  matches, status, off, usage error.
- Live on io: `haseen setup keyd on --yes`, then hold CapsLock + a key in
  `wev` shows all four modifiers; tap gives Escape.

## Not done

- No default hyper binds: the owner's snap layer is not in this tree.
