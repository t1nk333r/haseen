# Plan 076: power and battery panel

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (lazy panel; changes go through existing commands)
- **Depends on**: 060 075
- **Category**: shell, power
- **Planned at**: 2026-10-07, gap 4 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-battery.sh` model units; nested screenshots)

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
  - Screen off / Screen on buttons (plan 084);
  - a "Setup" row, which opens the menu at `setup`.
- Formatting lives in `Model.js` (glyph, state, duration, rate, energy, health, profiles, status parse,
  limit choices). The bar widget shares the glyph and charging rules.
- Theme tokens only, no timers. The pills are the shared `qs.Haseen.Widgets` `Pill`
  (`share/haseen/shell/Haseen/Widgets/Pill.qml`, also used by the media and display panels); only
  `SectionLabel` stays inline. Status and profile list run on open and when the state changes.

## Evidence

- `tests/test-battery.sh` model units (duration, time line, labels, rate, energy, health, glyphs,
  profiles, status parse, limit choices and args).

## Nested proof

Same nest and fake UPower as plan 075. A scratch sysroot with charge thresholds 75-80 % and 120 cycles was
set through `HASEEN_SYSROOT`.

- `~/.cache/haseen-wt/scratch-battery/shots/panel.png`: the panel, opened with `panel toggle haseen.battery`. It shows 25 %, "3 h left", "On battery",
  8.4 W, 25 / 50 Wh, health 88 %, 120 cycles, profiles with Balanced active, the limit with 80 % active,
  and System settings.
- `~/.cache/haseen-wt/scratch-battery/shots/panel-performance.png`: a virtual-pointer click (`tools/vptr`) on Performance. It ran
  `haseen powerprofile set` through powerprofilesctl against the fake. Performance became active from
  the PowerProfiles signal, and `powerprofile/battery` in the scratch state holds `performance`.
- A click on 60 % logged `systemd-run --user --scope … -- bin/haseen-battery-limit set 60` in the stub
  (Apps.launch), and the panel closed.

## Not verified

- A virtual-pointer click on the bar battery did not show the panel in the nest. The first IPC toggle had
  opened it while the nest's window output was still enabled (a "dangling screen object" warning), so
  the click probably closed that one. The click path was not shown working.
- The real `haseen battery limit` sudo terminal and a real power-profiles-daemon were not run.
- The "Setup" row was not clicked.
- The menu's Setup › Power and Battery row only where a battery exists, and the panel in a light theme,
  were not shot.

## Final shape (2026-10-08)

The review round replaced the panel's inline `Choice` with the shared `Pill`, made the secondary text
readable (`Theme.subtle`), added the Screen row (plan 084) and renamed "System settings" to "Setup".
`~/.cache/haseen-wt/scratch-design/shots/2-battery-panel.png` is the final panel in a nest on the fake
UPower: 9 %, "15 min left", On battery, 8.4 W, 25 / 50 Wh, health 88 %, 120 cycles, Balanced and 80 %
active, Screen off / Screen on, Setup. `tests/test-battery.sh` clicks Screen off and Screen on in the real
engine (the panel closes, then the DPMS off 1000 ms or more after the click; on within 500 ms).

## Rejected

- Writing the profile over D-Bus (`PowerProfiles.profile = …`): `haseen powerprofile set` also
  remembers it per power source.
- A sudo-free limit path: the kernel thresholds need root; plan 060's command already handles it.
