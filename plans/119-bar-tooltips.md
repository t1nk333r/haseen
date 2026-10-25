# Plan 119: A native bar widget can explain itself on hover

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One tooltip window per hovered slot, created only while it
  shows; widgets opt in by declaring `barTooltip`.
- **Depends on**: 011 (compat tooltip), 095 (haseen.updates), 112 (slots)
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (pull request; the live hover on IO is an owner step)

## Why

The owner, on IO, 2026-10-25: "the tooltip not showing for the update plugin".
The Omarchy widget this port replaced (`t1nk33r.updates/BarWidget.qml:49`,
`tooltipText` at 149) listed the summary and the first `tooltipLines`
packages on hover. Haseen's port kept the panel (the click's list) and dropped
the hover text, and haseen's own bar had no tooltip path at all: only adapted
Omarchy/DMS widgets had one (`Compat/OmarchyHost.qml:147`). Every native
widget therefore stayed silent on hover.

## What changed

- `BarSlot.qml`: `readonly property string tooltipText` from the loaded
  item's `barTooltip`, and one `Compat.Tooltip` bound to `hover.hovered`. The
  window, the 400 ms delay and the placement are the adapted widgets' own
  (`Compat/Tooltip.qml`), so the two kinds cannot drift.
- `haseen.updates/Widget.qml`: `barTooltip` is the panel's summary line plus
  `Model.listed(result, listLines, I18n.tr)` — the same text the Omarchy
  widget showed, in the interface's language, capped by the existing
  `listLines` setting (default 20, clamped to 100).
- `tests/test-bar-basics.sh`: the widget declares `barTooltip`, and the bar
  binds the tooltip to the hover.

## Evidence

- `tests/test-bar-basics.sh` (the two new assertions; full suite in the PR).
- `Compat/Tooltip.qml` is the window the adapted widgets already use; nothing
  new is drawn or polled.

## Rejected options

- **Tooltips for every native widget at once**: the text is each widget's own
  decision (a count, a network name, a battery time). This plan gives the
  mechanism and the widget the owner asked about; others adopt it as they need
  it.
- **A second tooltip implementation in `BarSlot`**: the compat one already
  handles delay, wrapping, placement and the bar's edge.
