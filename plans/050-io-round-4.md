# Plan 050: io, fourth round — overflow panel, keyboard in panels, audio, indicators, luna plugins

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (the bar's layout and every panel's keyboard handling change)
- **Depends on**: 048 049
- **Category**: shell
- **Planned at**: 2026-10-06, owner requests while using io
- **State**: DONE 2026-10-06 (physical clicks and keys on io are owner checks)

## Problem

Owner reports from io: audio "just mutes"; agents "does nothing"; workspace
layout does nothing; no notification bell, DND, recording or Omarchy
indicators; plugins must close on Escape; Enter does not apply a theme or a
wallpaper; the tray is the left anchor of the right section; and, with luna's
plugins added, the bar no longer fits a laptop screen — "one slide panel to
house plugins on a small screen".

## Decision and evidence

**Keyboard in panels.** Native panels used `WlrKeyboardFocus.OnDemand`, so a
panel opened by a key or the bar never had the keyboard: Escape and Enter went
to the window underneath. Plain `Exclusive` fixed keys but stopped an outside
click from clearing the focus grab (seen in a nested session). PanelPopup now
does what Omarchy's KeyboardPanel does: Exclusive until the window is active,
then OnDemand. In the pickers the focused grid cell took the key *press* before
it propagated (instrumented: releases reached the surface, presses did not), so
Escape and Enter are window `Shortcut`s. Nested proof: Escape closes, an
outside click closes, Enter applies a theme and a background.

**Overflow slide panel** (`Overflow.js`, `BarOverflowPanel.qml`,
`BarOverflowCell.qml`, `bin/haseen-bar-overflow`). A chevron at the bar's end
appears when something does not fit. "Does not fit" = a side section comes
within `Theme.gap` of the centred centre section. Order: `bar.overflow` ids,
then the right section from its innermost widget (just after the tray), then
the left section if it still collides. Never moved: the tray, `bar.pinned` ids.
Hysteresis of 2 × gap. Event-driven, no timer. Widgets move by reparenting
their slot, so state and IPC targets stay single. Arrange mode (footer button
or right-click on the chevron) moves widgets between bar and panel and writes
`bar.overflow` / `bar.pinned`. Rejected: Shift+right-click — a bar never has
keyboard focus on Wayland, so Shift is never reported; middle-click — several
widgets already use it.

**Tray anchor.** `haseen.tray` always renders first in the right section and
never overflows (owner rule); the import puts it first too.

**Audio** — port of Omarchy's audio panel: left click opens it (output and
input volume, mute, device choice, per-app volume), middle click mutes.

**Indicators and bell** — `haseen.indicators` ports Omarchy's indicators
(recording, night light, DND, stay awake, screensaver); the import maps
`omarchy.indicators` to it and `njpatel.omapager` to `haseen.pager`, and adds
the bell when the Omarchy bar had none. `--merge` now adds imported widgets
the user's bar lacks. The workspace-layout loader block from the old
`hyprland.lua` is carried into `local.lua`.

**Agents** — the click works (nested); the empty tabs are credentials only the
owner has: `claude auth login` for the Claude limits, a DeepSeek key in
`~/.config/deepspend/config.json`. The compat tooltip now waits 400 ms and
never covers the widget's open panel. The usage updater is still Omarchy's
(three Python collectors, 2,019 lines); porting it is open.

**Luna plugins** — the owner chose 17; they are copied to
`~/.config/haseen/plugins/` on io (never into `~/.config/omarchy/plugins/`)
and placed at luna's positions. Several call `omarchy-*` commands and work only
while the omarchy package is installed: updates, vpn, omarr, screen-search,
nothing-glass, settings, logitech, hey-im-gaming-here.

## Verification

Full suite, lint and docs on the branch (numbers in the PR). Nested Hyprland
for overflow (top and left bar, two screens), panel keys, audio panel, indicators,
agents click.

Not verified: physical clicks and keys on io; a real outside click on an empty
desktop in a nested session (no surface there).
