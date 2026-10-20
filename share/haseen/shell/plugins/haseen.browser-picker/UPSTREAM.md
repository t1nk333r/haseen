# UPSTREAM — haseen.browser-picker

`haseen.browser-picker` is a port of **omarchy-browser-picker**, MIT,
Copyright (c) 2026 K53N0. `LICENSE` here is the upstream licence, unchanged.

| | |
|---|---|
| Upstream | https://github.com/K53N0/omarchy-browser-picker (`k53n0.browser-picker`), base `680ad11780f5ff7488ebaec6cccc5429f5e0e956` |
| Ported from | the owner's fork `t1nk33r.browser-picker` 1.0.0-t1nk33r.1 (desktop-entry discovery, default-profile resolution, ranking by use, manage-profile rows removed), luna yadm last `88c47f7`; the IO copies are identical |
| Fork file hashes (sha256, first 12) | `Model.js` `d349e9a97c05`, `Picker.qml` `95137aa1b257`, `BarWidget.qml` `9de540a19311`, `bin/browser-picker` `2323a6af3c2f`, `bin/browser-picker-scan` `75bb6553ee7e` |
| Ported | 2026-10-20, plan `plans/096-adopt-tools-forks.md` |

## What changed

- **Shape.** A service (role `browser-picker`) answers IPC
  `haseen.browser-picker pick <request.json>` from `bin/haseen-browser-picker`;
  the card (`Overlay.qml`) is loaded from a URL only while a link waits; the
  fork's bar popup and rules window are one lazy panel (`Panel.qml`).
- **Handshake.** The answer comes back through the caller's FIFO, as
  `haseen menu select` does, instead of a 20 ms poll of a done file; the wait
  gives up when the shell dies.
- **Files.** Rules in `~/.config/haseen/browser-picker.json` (rules only),
  rankings in `~/.local/state/haseen/browser-picker.json`; the four settings
  are the manifest's, in `shell.json`.
- **Default browser.** `haseen setup default browser browser-picker`, with
  the vendor entry `share/haseen/default/applications/haseen-browser-picker.desktop`;
  Helium stays haseen's default.
- **Commands.** `bin/haseen-browser-scan` (the scanner, which also skips the
  fork's own entry), launches in their own scope; `--help` prints usage.
- **Tests.** `tests/model.test.js` and `tests/scan.test.sh` are the fork's,
  adapted to the new names.
