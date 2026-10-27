# Plan 139: The OSD card is a whole number of pixels

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. The card grows by under one pixel on each side it rounds;
  its padding, font, colours and position do not change.
- **Depends on**: 079 (haseen.osd), 117 (Omarchy's OSD card)
- **Category**: shell
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27 (`tests/test-keyboard.sh` 44/44)

## Problem

Owner, 2026-10-27:

> fix the OSD for the english keyboard the right borade is cutoff.

On IO (eDP-1, 1536 × 864 logical at scale 1.25, `hyprctl monitors`), switching
a keyboard to English shows a card whose right border is missing. The rounded
corners still draw; only the straight vertical edge between them is gone. The
Arabic card draws its right border. This was reproduced three times out of three in
the running shell: the power-button device's layout was switched with
`hyprctl switchxkblayout power-button 1` and then `0`, which shows the card
without changing the layout anyone types with. Luna, at scale 1, draws both
cards.

The card's size is text plus padding (`CardWindow.qml`, `implicitWidth:
row.implicitWidth + padding * 2`), and text is fractional. Measured in IO's
installed shell (JetBrains Mono 12, `Theme.space(16)` = 16):

| card          | row          | card          | layer surface (`hyprctl layers`) |
|---------------|--------------|---------------|----------------------------------|
| English (US)  | 133.0625     | 165.0625      | 165 × 60                         |
| Arabic        | 82.71875     | 114.71875     | 114 × 60                         |

The window is a whole number of pixels, so the card overhangs it by a
fraction. Under the shell's software renderer (`shell.qml`: `DefaultEnv
QT_QUICK_BACKEND = software`, plan 005) at a fractional scale, that overhang
loses the right edge of the border, either entirely (English) or partly
(Arabic, whose border is thinner on the right than on the left).

The renderer is the condition. A test shell using the same `CardWindow.qml`
and the GPU scene graph drew every border, centred or not, fresh or resized.
With the `QT_QUICK_BACKEND = software` pragma added, the current file lost
the English right border again.

## What changed

- `Osd.js` `extent(content, minimum, padding)`: the content, at least the
  minimum, rounded **up** to a whole pixel, plus the padding on both sides.
- `CardWindow.qml` sizes the card with it, both ways: width from the row,
  height from the row or the display-large line height. The window binds to
  the card, so the window is exactly the card.

Measured on IO under the software renderer, with fake layout events sent to
the real `Service.qml` in a test shell:

| card                             | surface |
|----------------------------------|---------|
| Arabic                           | 115 × 60 |
| English, fresh                   | 166 × 60 |
| English, straight after Arabic   | 166 × 60 |
| volume                           | 260 × 60 |

All four draw both borders. The volume card was already whole and is
unchanged.

The bar's tooltips already do this: `Math.ceil(label.implicitWidth)` in
haseen.privacy (plan 021), haseen.prayers (026), haseen.tray (049) and
haseen.indicators (050). The OSD was the bordered surface sized from text
without it.

Rejected:
- **A transparent inset around the card.** The window is larger than the card,
  so a fractional edge never meets the surface. It also fixes the border, but
  it adds a margin that the 67 px bottom offset would have to subtract, and it
  hides the fractional size rather than removing it.
- **Mapping the window only once its card is set** (`visible: service !==
  null`). A new card window does start as an empty level card, 260 px wide, and
  then resizes (logged: 32, then 260, then 0, then 260, then 165). With whole
  sizes that churn draws correctly, and without them gating alone does not fix
  the border.
- **Switching the shell to the GPU scene graph.** Plan 005 measured about
  85 MiB RSS more for it, with nothing gained without blur.

## Tests

`tests/test-keyboard.sh` (the haseen.osd unit block):
- `extent` rounds IO's English and Arabic rows up, to 166 and 115.
- The minimum wins over a shorter row and is rounded too.
- A whole row is unchanged.
