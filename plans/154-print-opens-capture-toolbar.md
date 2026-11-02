# Plan 154: PRINT opens the capture toolbar

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. Nothing changes for anyone who has not turned haseen.capture
  on: PRINT still takes Omasnap's screenshot. Every other capture key keeps
  its command.
- **Depends on**: 043 (the default keybinds), 107 (Omasnap on PRINT), 150 and
  151 (haseen.capture)
- **Category**: shell, keybinds
- **Planned at**: 2026-11-02, owner, after turning haseen.capture on: "bind
  the printscreen button"
- **State**: DONE 2026-11-02 (`tests/test-trigger.sh` 221/221, the affected
  set 26 files 4971/4971; the live key is an owner step)

## Problem

Plan 150 shipped the capture toolbar with no key: binds are the owner's to
approve (plan 043), and the toolbar opened only with `haseen shell ipc panel
toggle haseen.capture`. With the plugin on, the owner asked for PRINT.

PRINT was Omasnap's screenshot (`share/haseen/default/hypr/binds.lua:157` on
547119a), and the toolbar is a plugin that ships off. Binding PRINT straight
to the panel would leave the key dead for everyone without the plugin, since
the shell ignores a toggle for a disabled panel (`share/haseen/shell/shell.qml`,
`togglePanel`: "plugin '…' is disabled").

## What changed

- **`bin/haseen-capture-toolbar`** (new) asks the running shell whether
  haseen.capture is valid and enabled (`haseen shell ipc shell plugins`), and
  toggles its panel if so. Otherwise it runs `haseen capture screenshot`, what
  PRINT did before: when the plugin is off, failed to load or is not
  installed, when safe mode holds it back, when no haseen shell runs, and
  under DMS, whose IPC translation has no `shell plugins`. It reads the
  answer, not the exit status: `qs ipc call` exits 0 even for a missing
  target ("Target not found."). It takes `--dry-run`.
- **`share/haseen/default/hypr/binds.lua`**: PRINT runs it, described as
  "Capture toolbar or screenshot" (English and Arabic in the shell catalog,
  for the keybind sheet). Pressed again, it closes the toolbar, as Omasnap
  dismisses itself. SHIFT, CTRL, ALT and SUPER + PRINT and Omarchy's
  SUPER + CTRL + ALT + C keep their one-key captures.
- **`AGENTS.md`** records the bind under the owner's default keybinds.

## Verification

- `tests/test-trigger.sh` 221/221:
  - with the plugin on, the dry run plans the toggle and a real run reaches
    the shell's `panel toggle haseen.capture`;
  - with the plugin off, invalid, missing, no shell running, a shell without
    the plugin list, or DMS active, PRINT plans Omasnap's pick
    (`omasnap smart`) and nothing else reaches the shell;
  - a mode argument is a usage error.
- `tests/test-desktop.sh`, `tests/test-omasnap.sh` and
  `tests/test-omarchy45-workspaces.sh` now expect PRINT's new command and
  description.
- `tests/run.sh --affected`: 26 files, 4971/4971 passed. `binds.lua` and
  the shell catalog widen the selection.
- `tools/lint.sh` lint OK (shellcheck, i18n "catalogs fresh and complete for
  en, ar", coverage). `tools/check-docs.sh` OK.
- Timed on luna: one `haseen shell ipc shell plugins` round trip takes about
  30 ms, so the extra query does not slow the key.

## Rejected options

- **Bind PRINT to `haseen shell ipc panel toggle haseen.capture`.** The key
  would do nothing for everyone with the plugin off, which is its default.
- **Decide when Hyprland loads the config.** `binds.lua` would have to parse
  `shell.json`, and `haseen plugin enable` does not reload Hyprland, so the
  key would be wrong until the next reload.
- **Make `panel toggle` answer whether it opened.** Its callers ignore output
  today, and a change to the IPC contract (architecture §5.5) and its DMS
  translation is more than one key needs.
- **Move SUPER + CTRL + ALT + C to the toolbar too.** The owner asked for the
  PRINT key; the chord stays Omarchy's screenshot (plan 105).
