# Plan 029: Dual-boot control and drive helpers

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (firmware variables and a LUKS key slot)
- **Depends on**: 001 002 010
- **Category**: system
- **Planned at**: 2026-10-05, owner request (Windows dual boot is a project goal)
- **State**: DONE 2026-10-05

## Problem

haseen enrols Secure Boot keys for a Windows dual boot but had no way to start
Windows: the user reboots, catches the firmware menu, and picks an entry by hand.
It also had nothing to describe or re-key the encrypted disks it installs onto.

## Decision

Port DankMaterialShell's `quickshell/Services/BootEntryService.qml` and
`BootEntries.js` (MIT), and Omarchy's `drive-{info,select,password}` (MIT):

- `haseen boot list` enumerates with `efibootmgr`, keeping upstream's parsing
  rules: only active entries (`*`), the label stops at the tab efibootmgr 18+
  writes before the device path, and `BootCurrent` marks the running one.
- The four states are exit codes, so no caller parses prose: `0 ready`,
  `3 noEfi`, `4 noTool`, `1 error` (the tool's own stderr is kept). `--json`
  carries the same `status` plus `error`.
- `haseen boot next <id|label>` lists again before writing, refuses an entry
  whose label no longer matches `--label`, and sets `BootNext` only. The firmware
  clears it after that one boot, so `BootOrder` and Secure Boot are untouched.
  `--reboot` is a separate opt-in.
- The session panel gains one row per other installed system. It writes through
  `pkexec haseen-boot-next` and reboots only once that returned 0, the same split
  upstream uses. `settings.bootEntries` is `"auto"` (drop firmware and removable
  entries by label), `false`, or an explicit list of ids/labels.
- The drive helpers keep Omarchy's behaviour, with fzf instead of gum (every
  other haseen picker uses fzf), `--luks` to list containers, and the new key
  reaching `cryptsetup` as a keyfile through `<(cat)` so the terminal stays free
  for the current-passphrase prompt.

## Verification

- `tests/test-boot.sh` (29) and `tests/test-drive.sh` (14): the four states
  including noTool against a `/usr/bin` mirror without the binary, label and id
  resolution, the ambiguous-label and renumbered-entry refusals, an inactive
  entry, dry-run purity, and the LUKS type check.
- Live on the reference laptop: entries listed (Windows Boot Manager, Limine,
  kali); `haseen-boot-next 0000` under `pkexec` set `BootNext: 0000`, confirmed
  with `efibootmgr -v`, then cleared with `--delete-bootnext`; `bootctl status`
  still reads `Secure Boot: disabled (setup)`, unchanged. Drive info, both
  pickers and the passphrase dry run were run against the real disk.

## Execution record

`bin/haseen-boot-list`, `bin/haseen-boot-next`, `bin/haseen-drive-info`,
`bin/haseen-drive-select`, `bin/haseen-drive-password`, the boot rows in
`share/haseen/shell/plugins/haseen.session/`, `tests/test-boot.sh` and
`tests/test-drive.sh`.
