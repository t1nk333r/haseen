# Plan 049: io, third round — popups, seam, icons, pickers, fingerprint, tray

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (lock screen and bar, the two surfaces always on screen)
- **Depends on**: 015 036 048
- **Category**: shell
- **Planned at**: 2026-10-06, owner requests while using io
- **State**: DONE 2026-10-06 (a real finger and a real click on io are owner checks)

## Problem

Seven owner reports from io, after plan 048 went live:

1. popups open "away from" the plugin icon;
2. a 2–3 px gap left of the workspace numbers where the frame meets the bar;
3. the prayer widget's icon shows as "U";
4. the theme and wallpaper selectors are not invoked;
5. no fingerprint on the lock screen;
6. the tray should be Omarchy's, pinned open by clicking its chevron;
7. no highlight when the mouse is over a plugin.

## Decision and evidence

**1. Panels under their icon.** Native panels were a layer-shell window
anchored only to the bar edge, so Hyprland centred them. Every native widget
opens its panel with a detached `qs ipc call panel toggle`, which carries no
item; rather than change ten widgets, each bar slot reports where a press
landed (a passive `PointHandler`, which never takes the press), and a toggle
within 1.5 s of a press is placed under it: anchors on the bar edge and the
bar's start, margin = widget centre − half the popup, clamped to `Theme.gap`
(`share/haseen/shell/PanelPlacement.js`). Without a press (key, CLI, menu) the
panel stays centred as before. Rejected: an xdg-popup (`PopupWindow`) — it
loses keyboard focus when a panel is opened by a key. Omarchy compat popups were
already anchored to their icon (`Compat/Omarchy/Ui/KeyboardPanel` `cardOrigin`).
`t1nk33r.vigil` draws its own centred modal, as upstream; the plugin is
read-only, so it stays.

**2. Seam.** Measured on io (eDP-1 at 1.25, frame 6 px, bar 28 px):
`hyprctl layers` put the frame strip at x 0–6 and the bar at x 6; physical
pixel 7 read (37,36,33) against (40,40,40) on both sides — 6 × 1.25 = 7.5, so
both layers half-cover it and the wallpaper shows through. Every frame piece
now reaches 1 px under the pieces it meets (bar margins −1 at its ends, strips
and corner rows +1); exclusive zones are unchanged and the overlaps are the
same colour. Measured in a nested Hyprland on a 1.25 output: the seam rows read
(23,23,23) across, before and after shown in the PR.

**3. "U" instead of the prayer icon.** `t1nk33r.omaprayers` draws U+EED3 in
`bar.fontFamily`. Omarchy's Style uses `monospace` (a Nerd Font on io);
haseen's compat used `Theme.fontFamily` (Inter), and `fc-list ':charset=eed3'`
shows Inter has its own glyph at U+EED3 — a small "u" — so fontconfig never
fell back. Compat now uses `Theme.fontMono`. `tests/test-compat-font.sh`.

**4. Pickers.** The wallpaper picker panel had no key and no menu entry:
SUPER + CTRL + SPACE ran `haseen theme bg next`, which shows nothing. It now
opens the picker (Omarchy's key, `utilities.lua:17`), "next background" moved
to SUPER + CTRL + ALT + SPACE, and Style › Background opens the picker. The
theme picker could not be reproduced as broken: the bind, registry and panel
all work on io and in a nested copy of the owner's setup, also with fcitx5
running (Hyprland runs binds before the input-method grab,
`InputManager.cpp::onKeyboardKey`). [INFERENCE] the report predates the
14:13/14:32 reinstalls. Tests pin every shipped key and menu entry that
toggles a panel to a shipped panel plugin.

**5. Fingerprint.** Ported from Omarchy's lock: a second `PamContext` on
`haseen-lock-fingerprint` (pam_fprintd) runs beside the password field once
the lock is confirmed, retries after a mismatch, backs off when the reader
fails instantly (lid shut), and shows a hint in the field. Offered only when
the PAM file exists and `fprintd-list` lists an enrolled finger — matched on
the list entry, because Omarchy's `grep -qi finger` also matches "has no
fingers enrolled". `haseen setup fingerprint` writes the PAM file. The
password path (plan 048's two fixes) is unchanged and re-tested.

**6. Tray.** Omarchy's tray widget ported over `haseen.tray` (id and
`pinned` setting kept): the chevron pins the drawer open and keeps it pinned
across restarts; hover-reveal is gone. Not ported: Omarchy's per-item
pin/hide lists (they would clash with the boolean `pinned`) and symbolic-icon
recolouring (needs a shader; the shell renders in software, architecture §6).

**7. Hover highlight** on every bar slot, native and compat: a `HoverHandler`
and a `Theme.surfaceAlt` rectangle behind the widget.

## Verification

Full suite, lint and docs on the branch (numbers in the PR). Nested Hyprland
runs for 1, 2, 3, 4, 5 and 6 with screenshots (clicks through a
wlr-virtual-pointer helper into the nested compositor only). Live on io after
install: see the PR.

Not verified: a real finger on io's reader; a physical click on io (the owner's
session is not driven by the agent).
