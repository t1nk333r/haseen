# Plan 164: a compact weather panel

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW. Layout only, in one file. The service, the bar pill, the
  city search's logic, the `haseen.weather.panel` test hook and every
  string are unchanged.
- **Depends on**: 022 (the weather panel), 052 (the Omarchy port), 109
  (mirrored panels), 141 (type roles)
- **Category**: shell
- **Planned at**: 2026-11-13, owner: "compact the weather module"; asked
  which kind, they chose "Smaller panel" (rejected: the temperature in the
  bar pill, and shrinking the code with no visual change)
- **State**: DONE 2026-11-13 (`tests/run.sh --affected` 801/801 over 6 files;
  the panel on luna and IO is an owner step).

## Problem

The panel was 34 em wide (`Panel.qml:119` on `2c0df5d`, 408 px at the
default 12 px font) for three numbers and three days. The hero put a
24 px icon and temperature on the left and a column of location over a
three-cell stats table on the right (`:143-378`), so the panel was as wide
as the widest side by side, and the stats took two lines (caption label
over title value). Rendered offscreen with a stub service (Verification),
the content measured 408 × 121 px.

## Decision

`share/haseen/shell/plugins/haseen.weather/Panel.qml`:

1. **Width 26 em** (312 px) and the column's spacing `Theme.gap` instead
   of 1.5 gaps.
2. **One hero row.** The condition icon (`Theme.font.iconLarge`, 18 px)
   and the temperature (`heading`, 16 px, bold; its unit `bodySmall` on the
   same baseline) on the left, the location (`bodySmall`, marker and name)
   at the row's end, elided to the room left. The hero shrinks from
   `display` (24 px): a visible size change, inside plan 141's roles.
3. **Stats on one line.** `FEELS 19°C  WIND 12 km/h  HUMID 60%`, each a
   caption label beside a `body` value on a shared baseline, in a `Flow`
   so a longer language wraps instead of overflowing. The labels are the
   same marked strings, so the catalogs need nothing.
4. **The city search takes the stats' line** while it is open, full width,
   with the same field, clear button and spinner; the stats hide, so the
   panel keeps its height while searching.
5. **The three days in equal columns** (a third of the width each, the
   content centred), the temperatures at `bodySmall`. Full day names stay:
   "WEDNESDAY" at caption fits a 104 px column.
6. No inner margins on the hero, so every line starts at the panel's
   content edge.

Measured the same way, the content is 312 × 100 px (−24% wide, −17%
tall); 312 × 106 px with the search open. Mirrored (`LayoutMirroring`
inherited, as the Arabic interface sets it), the location moves to the
left, the stats read right to left and the days run Monday on the right.

## Verification

- Render: a scratch Quickshell harness (not committed) loads `Panel.qml`
  with its `service` swapped for a stub object (Berlin, 21 °C, three
  days), inside a `FloatingWindow`, offscreen on the software renderer,
  and saves `grabToImage` of a frame padded by two gaps. Before (on
  `2c0df5d`): 432 × 145 frame. After: 336 × 124; with
  `startEditingLocation()`: 336 × 130; mirrored: 336 × 124, laid out as
  described. Nothing here draws through a layer, so plan 156's fractional
  scale problem does not apply.
- `python3 tools/fonts.py check`: "278 files, one family, one scale".
- Gates: `tools/lint.sh` OK (qmllint over 363 QML files), `tools/check-docs.sh`
  OK, `tests/run.sh --affected` 801/801 over its 6 files (`test-core`,
  `test-i18n`, `test-shell`, `test-surfaces`, `test-weather`,
  `test-widgets-b`).

## Rejected options

- **The temperature in the bar pill** (the owner's other choice): the pill
  stays icon-only.
- **Shrinking the code** with no visual change: not what was asked.
- **Short day names** (`ddd`): full names fit at 26 em.
- **Narrower than 26 em**: the hero row needs the icon, temperature and
  a city name such as "NEW YORK" without eliding, and three day columns
  need room for "WEDNESDAY".
- **Stats as a two-line table** (as before): the second line is where the
  height went.

## Residual unknowns

- How it looks in the owner's session at IO's 1.25 scale with
  BerkeleyMono: an owner step.
