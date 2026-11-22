# Plan 184: a screenshot keeps the panel, menu or stage it was taken for

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Every focus grab in the shell now goes through one wrapper
  that only differs from Hyprland's while a capture tool is on screen; a
  click outside closes a panel 100 ms later than before.
- **Depends on**: 107 (Omasnap), 150 (haseen.capture's toolbar), 154 (PRINT
  opens the toolbar), 163 (the stage)
- **Category**: desktop
- **Planned at**: 2026-11-22, from the owner
- **State**: DONE 2026-11-22 (`tests/test-capture-hold.sh` 34/34 after a Sonnet
  review; IO's PRINT over the stage and a tray menu is an owner check)

## Problem

The owner, 2026-11-22: "when trying to take screenshot with something like
the expose feture the screenshot would dismiss it then freazes the screen
below the shell or the context menu", "this behivior was noticed mainly on
IO".

Two paths close what PRINT was pressed to capture.

- **Omasnap and the other capture tools** (luna, where haseen.capture is
  off, so PRINT is `haseen capture screenshot`). With the menu open and
  `omasnap smart` started, `hyprctl layers` listed `haseen-overlay` before
  and only `omasnap` 0.25 s after. Omasnap's overlay is a full-screen layer
  that takes the keyboard. Hyprland clears every focus grab when that
  happens, and each panel, the menu, a tray menu and the compat popups
  closed on `HyprlandFocusGrab.cleared` (`PanelPopup.qml:73-77` before this
  plan, `TrayMenu.qml:116-120`, `BarOverflowPanel.qml:155-163`,
  `PluginPopout.qml:108-112`, `PopupCard.qml:106-110`). The stage has no
  grab, but the layer takes the pointer, and the stage closes 350 ms after
  the pointer leaves (`StageView.qml` `grace`). Omasnap had already copied
  the screen, so its frozen picture still showed the menu, but the menu was
  gone underneath it and stayed gone afterwards.
- **haseen.capture's toolbar** (IO, where it is on, so PRINT opens it). The
  shell keeps one panel open at a time (`shell.qml` `togglePanel`:
  `openPanels = [id]`), so opening the toolbar closed the open panel. The
  toolbar also covers the screen as an overlay that takes the keyboard and
  the pointer, which closed a tray menu or the stage the same way. The
  capture runs only after the toolbar has gone (`Service.qml` `capture()`,
  at least 300 ms), so the tool froze a screen that no longer had any of
  them: the screen "below the shell".

## Decision

- **`Capture`** (`qs.Haseen`) counts the capture tools' layers from
  Hyprland's `openlayer` and `closelayer` events (`Hyprland.rawEvent`), by
  the namespace each tool gives its layer: `omasnap`, slurp's `selection`,
  `hyprpicker` and `wayfreeze` (`Capture.js`). It needs no polling and
  catches a capture however it was started (PRINT, the capture menu, the
  owner's `screen-search`). Omasnap's preview after a capture is a window
  (`omasnap-pin` in `hyprctl clients`, seen on luna), not a layer, so a
  capture ends when its overlay goes. `active` is also true while
  haseen.capture's toolbar is open or a capture waits out its delay
  (`toolbar`, bound by the service), and for 2 s after the service starts
  the capture command (`expect()`), until that command's layer appears.
- **`CaptureFocusGrab`** (`qs.Haseen.Widgets`) wraps `HyprlandFocusGrab`.
  A clear while a capture is on holds the grab instead of reporting it. A
  clear with no capture yet waits 100 ms (`settle`): Hyprland reports the
  new layer on its event socket and clears the grab on the Wayland one, in
  either order. When the capture ends, the wrapper emits `resumed`, so the
  surface asks for the keyboard again (`focusPrimed = false`, as when it
  appeared). The grab restarts 100 ms later (`rearm`). Restarted at once, it was
  cleared again as Hyprland handed the keyboard back to the window that had
  it before the capture; a throwaway shell on luna closed its popup after
  Escape that way, and stayed open with the delay.
- All five grabs use it. `tests/test-capture-hold.sh` checks that no other
  file uses `HyprlandFocusGrab` directly. The toolbar's own panel sets
  `ignoresCapture`, so a click outside a non-overlay toolbar still closes
  it.
- **The stage** does not count a capture as the pointer leaving
  (`grace` checks `Capture.active`). It stays open afterwards until the
  pointer comes back and leaves, Escape, or another workspace. When the
  capture ends it takes the keyboard back if the capture took it
  (`StageWindow.qml`). A capture that never did (the toolbar's delay, a
  whole-screen recording) leaves the stage's keyboard as it was:
  Exclusive again on a window that stayed active would never be primed
  back to OnDemand.
- **The toolbar opens over the open panel** and on its screen, instead of
  in its place. This applies only to the panel of the plugin with the
  `capture` role. Any other panel still replaces whatever is open.

## Rejected

- **Telling the shell from `haseen capture` over IPC before Omasnap
  starts.** It has no race, but it misses every capture started another way
  (the owner's `screen-search` binds, Omarchy's commands), and each
  screenshot would cost an IPC round trip.
- **Ignoring every grab clear for a moment.** A click outside would then
  sometimes do nothing.
- **Polling `hyprctl layers` from the grab.** It is a process per clear,
  and polling is against architecture §6.
- **Making the capture tools skip the shell's layers.** Omasnap and slurp
  are not haseen's, and the point is to capture the shell.

## Review

A Sonnet review found no fault in the grab's states and raised these:

- The stage asked for the keyboard after every capture, even one that
  never took it; it now asks only when its window is not active.
- Omasnap's preview window might take the keyboard after a completed
  capture and close the panel once the grab was back. It does not: a full
  capture on luna (`--capture-fullscreen`, Enter) left the test popup
  mapped, the preview at `focusHistoryID` 1 and the previous window
  active.
- The clear handler is a function (`grabCleared`), so the test drives the
  hold, the settle and a capture reported after the clear without a
  compositor. The re-arm delay is its own property.
- Accepted as is:
  - **The re-arm delay is measured.** It is not tied to an event: a
    Hyprland slower than 100 ms to hand the keyboard back would close the
    panel after the capture, as before this plan.
  - **A lost `closelayer` would hold every grab.** Escape still closes
    each panel. Hyprland sends `closelayer` on every unmap.
  - **The toolbar opens where the open panel is.** It uses that panel's
    screen and, with a bar placement, its opener, even if the focus has
    moved to another monitor since.
  - **A recording swallows outside clicks for 2 s.** For the 2 s of
    `expect()` after a whole-screen recording starts, which opens no
    layer, an outside click does not close a panel.

## Notes

The live check on luna ran a throwaway Quickshell instance with its own
runtime directory. It had one overlay `PanelWindow` with the new grab.
`omasnap smart` opened over it: both layers were listed. After Escape the
test layer was still mapped, and the log read `capture true`, `resumed`,
`capture false`. IO's full path (PRINT, the toolbar, Space) needs the
installed tree.
