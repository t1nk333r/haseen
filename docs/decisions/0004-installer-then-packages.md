# ADR 0004: installer now, PKGBUILDs later; PREFIX /usr/local

- **Status**: accepted 2026-10-04 (owner)

## Decision

`install.sh` copies `bin/` and `share/haseen/` to `/usr/local`, the FHS location for files no package owns, and applies layers. The layers are written so that a later PKGBUILD can move `PREFIX` to `/usr` without code changes: everything resolves `$HASEEN_PATH` or `bin/../share/haseen`. Plan 013 tracks the packaging work.

## Rejected

- **A clone in `~/.local/share/haseen`** (the Omarchy 3 approach): system layers would run code from a directory the user can write to.
- **Writing into `/usr` without a package**: pacman would not track the files.
