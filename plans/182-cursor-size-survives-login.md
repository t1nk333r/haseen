# Plan 182: the cursor size picked in the monitor panel survives a login

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. One more line in the file `haseen hardware monitor cursor`
  already writes; nothing else reads it.
- **Depends on**: 098 (monitor settings, the cursor command)
- **Category**: desktop
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-monitor-settings.sh` 78/78; luna's
  next login is an owner check)

## Problem

The owner, 2026-11-21: "on every reboot the cursor becomes at 34 px set it
to always be at 20".

luna had picked 20 in the monitor panel that evening, which wrote
`~/.config/uwsm/env.d/61-haseen-cursor` with `export XCURSOR_SIZE=20`
(`bin/haseen-hardware-monitor:261` before this plan). An earlier file of the
owner's, `55-cursor` (the OutLier v2 theme), exports `XCURSOR_SIZE=32` and
`HYPRCURSOR_SIZE=32`. After the next login `systemctl --user
show-environment` read `XCURSOR_SIZE=20` and `HYPRCURSOR_SIZE=32`: the
command overrode one of the two. Hyprland sizes its own cursor from
`HYPRCURSOR_SIZE` when it is set, and only falls back to `XCURSOR_SIZE`, so
the session came up at 32 whatever the panel had said.

## Decision

`cmd_cursor` writes both `XCURSOR_SIZE` and `HYPRCURSOR_SIZE` to
`61-haseen-cursor`, which uwsm sources after every lower-numbered env.d file,
so the panel's choice wins over a user's own cursor file at every login.
`tests/test-monitor-settings.sh` checks both lines. The comment beside it
named `60-haseen-defaults` as the source of the default 20; it is
`10-haseen` (`share/haseen/layers/desktop/layer.sh:192`).

## Rejected

- Making the autostart's `hyprctl setcursor` (`share/haseen/default/hypr/autostart.lua`)
  read `HYPRCURSOR_SIZE`: it already passes `XCURSOR_SIZE`, which was 20;
  the size Hyprland starts with and hands to its clients is the env's.
- Editing the user's `55-cursor` from haseen: haseen never edits a user's
  files after seeding them. On luna the owner's file was set to 20 by hand,
  at the owner's request, as a separate step.

## Notes

OutLier v2 ships 32/48/64/96/128 px images only. Clients that load XCursor
themselves (XWayland apps) pick the nearest image, 32, at a 20 px request;
Hyprland draws through the cursor-shape protocol for everything else.
