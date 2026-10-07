# Plan 076: power and battery panel

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (lazy panel; changes go through existing commands)
- **Depends on**: 060 075
- **Category**: shell, power
- **Planned at**: 2026-10-07, gap 4 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-battery.sh` model units; nested screenshot not taken, see below)

## Change

- `haseen.battery` gains a `panel` kind (`Panel.qml`). A left click on the bar battery opens it, and so do
  `haseen shell ipc panel toggle haseen.battery` and Setup › Power and Battery in the menu. The host loads
  it lazily.
- Contents:
  - percentage and state ("Plugged in, holding at 75-80%" when `haseen battery status --shell` says
    `holding`);
  - time to empty or full, power draw (W), energy, health (UPower Capacity) and cycles;
  - power profile pills from `haseen powerprofile list`. The active one comes live from Quickshell
    `PowerProfiles`, and a click runs `haseen powerprofile set autodetect <profile>`;
  - charge limit pills (60 %, 80 %, Full, plus the current one) from the status `threshold`. A click
    starts `haseen battery limit set N|off` through `Apps.launch`, which asks for the password in its
    floating terminal, then closes the panel;
  - a "System settings" row, which opens the menu at `setup`.
- Formatting lives in `Model.js` (glyph, state, duration, rate, energy, health, profiles, status parse,
  limit choices). The bar widget shares the glyph and charging rules.
- Theme tokens only, inline components (`Choice`, `SectionLabel`), no timers. Status and profile list
  run on open and when the state changes.

## Evidence

- `tests/test-battery.sh` model units (duration, time line, labels, rate, energy, health, glyphs,
  profiles, status parse, limit choices and args).

## Not verified

- No nested screenshot. `tools/nest-launch.sh` fails on luna (plan 075). The panel was not rendered.
- The charge limit and profile clicks were not exercised in a shell.

## Rejected

- Writing the profile over D-Bus (`PowerProfiles.profile = …`): `haseen powerprofile set` also
  remembers it per power source.
- A sudo-free limit path: the kernel thresholds need root; plan 060's command already handles it.
