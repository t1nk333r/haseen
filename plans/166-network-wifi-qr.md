# Plan 166: the Wi-Fi QR code in the network panel

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. A button and a card inside the default-on network panel.
  Nothing runs until the card opens; the password is read only on a click.
- **Depends on**: 093 (Omarchy's commands), 106 (the panel's portal row),
  109 (interface language), 156 (drawing at a fractional scale)
- **Category**: shell
- **Planned at**: 2026-11-13, from the owner
- **State**: DONE 2026-11-13 (`tests/test-network-panel.sh` 84/84, with a
  real `qrencode` matrix decoded back by `zbarimg`; the card's Shape drawn by
  Qt's software renderer at `QT_SCALE_FACTOR` 1 and 1.25 and both images
  decoded by `zbarimg`; the panel in the owner's session on luna and IO is an
  owner step).

## Problem

The owner, 2026-11-13: "bring back the qrcode in wifi". Omarchy's network
panel has a QR button in its header that opens a card with the code that
joins the connected Wi-Fi network (`/usr/share/omarchy/shell/plugins/panels/
network/Panel.qml:1113-1125`, which summons the `omarchy.wifiqr` panel,
`:456-469`). haseen's port left it out on purpose: the header of
`haseen.network/Panel.qml` said "no keyboard cursor, Wi-Fi QR card or router
ping" (origin/main, lines 4-5). What was left was the menu's Setup › Network
› QR Code row, which opens a terminal on `nmcli device wifi show-password`
(`share/haseen/default/menu.jsonc:186`).

Plan 093 had already ported the two commands the card needs,
`omarchy-network-qr` and `omarchy-network-password`
(`share/haseen/omarchy/bin/`), but nothing in haseen called them, and the QR
one escaped `;` with one backslash (`value=${value//;/\;}`, origin/main
line 67), which bash reads as a plain `;`: `escape_wifi_qr "Cafe;Net"`
printed `Cafe;Net`, so a network with a semicolon in its name or password
got a code that does not join.

## Decision

### `haseen network qr`

`bin/haseen-network-qr [--meta] [--password] [interface]` is the command,
adapted from Omarchy's `omarchy-network-qr` and `omarchy-network-password`
(MIT, notice in the header): the same interface choice (the default route's
device when it is Wi-Fi, else the first connected Wi-Fi device), the same
`WIFI:` payload with WPA, WEP, open and hidden handling, and the same output,
rows of 0 and 1 after an optional `meta<TAB>iface<TAB>security<TAB>ssid`
line. haseen changes:

- the escape: backslash, `;`, `,`, `:` and `"` each get one backslash
  (`bin/haseen-network-qr:102-110`), the special characters of the format as
  ZXing reads it;
- an open network's payload has no `P:` field;
- `--password` prints the password from the fields it already read
  (`:94-98`), so the card has one command; an open network says "This
  network has no password";
- each refusal is one plain line on stderr, which the panel recognises and
  translates (`Model.js:544`, `qrErrors`);
- `/sys` goes through `sysroot_path`, nmcli runs in the C locale, the
  payload reaches `qrencode` over stdin and the password only stdout.

`omarchy-network-qr` becomes a shim row (`commands.tsv:295`, a link to
`dispatch`) over it, so Omarchy plugins get the fixed escape too; plan 093's
inventory row says so. `omarchy-network-password` stays its own port.

### The card

On a personal Wi-Fi network (`canShareWifi`, `Panel.qml:110`: NetworkManager,
the Wi-Fi link is the active one, not WPA/WPA2 Enterprise) the hero gets a
QR button before the speed test (glyph U+F0432, the menu row's). It opens a
card under the hero: the code on a rounded square, "Scan with a phone's
camera to join %1", and on a secured network a "Show password" link that
reads the password on click and toggles it. The button again, another
network, losing Wi-Fi (`:531-533`) or closing the panel drops the code and
the password, and stops a run still in flight, whose partial matrix parses
empty: a card reopened on another network shows an error, never the old
code. The panel exists only while open, so its processes go with it.

The reason for a new on-screen element (CLAUDE.md, "No visual clutter"):
the owner asked for it, and it is a button shown only on Wi-Fi with the card
opened on demand.

Rendering: the dark modules are one `PathSvg` path in one `Shape`, one
rectangle per horizontal run (`Model.js:519`, `qrPath`). A Shape has a
software backend and draws right at a fractional scale where a Canvas or a
layer does not (plan 156); one path means no seams between neighbouring
modules. Modules are a whole number of logical pixels, `Theme.space(240)`
over the matrix size, at least 3, never wider than the panel (`:1095`).

Colours come from the theme: the lighter of `Theme.foreground` and
`Theme.background` is the paper, the darker the ink (`:128-130`), so the code
is always dark on light, which every scanner reads, in a dark theme and a
light one.

The debug hook (`settings.debugIpc`) gains `showQr()` and a `qr` object in
`state()`: it opens the card and reads the code, never the password.

Arabic: the 13 new strings are in `share/haseen/i18n/ar/shell.json`.

## Rejected

- **Omarchy's full-screen overlay** (`omarchy.wifiqr`, a layer-shell window
  over a 78 % black scrim): a second panel plugin and a new surface for what
  fits in the panel that is already open. haseen's host loads one panel at a
  time (architecture 5.2).
- **One `Rectangle` per module** (Omarchy's `Grid` and `Repeater`): about
  1,100 to 1,700 items for a version 3 to 5 code, and seams between dark
  neighbours at scale 1.25.
- **A fixed white and black**: CLAUDE.md allows theme tokens only in
  widgets; the lighter-of-two rule gives the same polarity from the theme.
- **Showing the command's stderr as is**: unknown text (a missing `qrencode`
  error) reads as "Could not make the QR code".
- **Changing the menu row**: it still opens the terminal QR; the owner asked
  for the panel.

## Evidence

- `tests/test-network-panel.sh` 84/84: 12 new unit cases for `parseQr`,
  `qrPath` and `qrError`; the panel's wiring; `haseen network qr` against a
  stubbed `nmcli` for WPA, WEP, open and hidden, the escapes, every refusal,
  `--password`, the usage error and the Omarchy shim; and a real `qrencode`
  matrix turned into a PBM and decoded by `zbarimg` to
  `WIFI:T:WPA;S:Cafe\;Net;P:pa\:ss\,w\\d;;`.
- The card's Rectangle and Shape in an offscreen harness under
  `QT_QUICK_BACKEND=software` at `QT_SCALE_FACTOR` 1 and 1.25 with Tokyo
  Night's colours: both grabs decode to `WIFI:T:WPA;S:Cafe\;Net;P:hunter2;;`.
