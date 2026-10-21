# UPSTREAM — haseen.wooting

`haseen.wooting` is a port of the owner's **t1nk33r.wooting** plugin, MIT,
Copyright (c) 2026 t1nk33r. `LICENSE` here is that licence, unchanged. The
owner wrote it; there is no third-party upstream.

| | |
|---|---|
| Source | the owner's repository `t1nk333r/haseen-wooting` (private), commit `184f6fabf7f9b54c9bd48870cfd64596f086cfc7`, the tree installed on luna as `~/.config/omarchy/plugins/t1nk33r.wooting` |
| Source file hashes (sha256, first 12) | `Panel.qml` `44932deca56f`, `LayoutPanel.qml` `cc2e822e2e15`, `Model.js` `b09d0648340e`, `bin/wooting` `6f0cc0cc8e21`, `bin/wooting-doctor` `2ea450c2cb30`, `lib/ipc.sh` `ad028059e3b6`, `install.sh` `907687846bde`, `daemon/src/main.rs` `f6bf9caf6ec7` |
| Ported | 2026-10-21, plan `plans/099-adopt-wooting.md` |

## Where each part went

| Original | haseen |
|---|---|
| `daemon/` (Rust crate `wootingd`) | `core/wootingd/`, built by `tools/build-sidecar.sh` into `share/haseen/sidecar/wootingd`; behaviour unchanged |
| `Model.js`, `tests/model.test.js` | `Model.js`, `tests/model.test.js` here; the logic is unchanged |
| `Panel.qml` (bar widget and its popup) | `Widget.qml` (bar), `Panel.qml` (the profile list, as haseen's lazy panel), `ProfileRow.qml` |
| `LayoutPanel.qml` (keyboard layout overlay) | `Board.qml`, shown inside the panel by its Keyboard layout pill |
| the socket lifecycle repeated in both QML files | `WootingLink.qml`, one copy |
| `lib/ipc.sh` | `share/haseen/lib/wooting.sh` |
| `bin/wooting`, `bin/wooting-doctor` | `bin/haseen-wooting`, `bin/haseen-wooting-doctor` |
| `install.sh`, `uninstall.sh`, `udev/70-wootingd.rules`, `wootingd.service` | `bin/haseen-setup-wooting`, `share/haseen/default/udev/70-wootingd.rules`, `share/haseen/default/systemd/wootingd.service` |
| `tests/fakedaemon.py` | `tools/fake-wootingd.py` |
| `tests/{cli,ipc,doctor,install,daemon}.test.sh` | `tests/test-wooting.sh`, `tests/test-wootingd.sh` |

Not taken: the original's agent and planning notes, its CI file, and its
`omarchy` manifest block (`entryPoints`, `barWidget.schema`); the settings
became haseen manifest settings with the same names and defaults.

## What changed

- **Theme.** Colours come from haseen's `Theme` tokens: no `qs.Commons` or
  `qs.Ui`, no colour literals; the layout view's translucent white key fills
  are `Theme.surfaceAlt`/`Theme.surface`, the key travel is the accent at the
  original's 0.15 + 0.85 × travel alpha.
- **Shape.** haseen gives a plugin one lazy panel opened under its bar
  widget. The original's popup card and its full-screen layout overlay became
  that panel: the profile list, and the board below it on demand. The panel's
  Settings row (`omarchy-menu toggle setup.plugin`) and the overlay's own
  scrim were dropped; Escape and a click outside close the panel as for every
  haseen panel.
- **Commands.** `haseen wooting` keeps every subcommand, output line and exit
  code; `set` takes `--dry-run`. The doctor reads the system through
  `sysroot_path`, names `haseen setup wooting on` as the fix, and adds one
  check: which `wootingd.service` the user manager runs.
- **Setup.** `haseen setup wooting on` installs the same rule and unit names
  through haseen's dry-run helpers, takes over a copy the plugin installed
  (saved to `~/.local/state/haseen/wooting/` first) and points the unit at the
  installed daemon. Packages are not installed and no CLI link is made: the
  commands are on PATH as haseen's.
- **Daemon.** Only comments, three messages and four command names changed
  (plan 099 lists them): the permission hint names `haseen setup wooting on`,
  the no-reply and empty active-profile errors are reworded, and commands 38,
  39, 48 and 55 are named `CMD_APPLY_PROFILE`, `CMD_SLOT_CONTENT`,
  `CMD_SLOT_KEYMAP` and `CMD_SLOT_NAME`; the protocol citations are pinned to commits, and the facts
  taken from the unlicensed wootswitch are stated without its text.
