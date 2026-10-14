# Plan 089: desktop fixture isolation

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW, test fixtures only
- **Depends on**: 027 036 074 081 086
- **Category**: tests, shell
- **Planned at**: 2026-10-12, owner request to fix the 17 local gate failures
- **State**: DONE 2026-10-12 (landed with PR #40; full local gate 12,545/12,545)

## Problem

The full local run on the PR #40 branch reported 12,494/12,511. The same 17
failure counts reproduced on unchanged `main` at `da73029`: the fixtures
depended on the caller's session, an installed ydotool and a
capacity-limited `/tmp`.

## Changes

- Clock and greeter IPC fixtures create their short private runtime
  directories under `${TMPDIR:-/tmp}` (`tests/test-clock-dayname.sh:208`,
  `tests/test-greeter.sh:245`), so the caller can choose a disk-backed
  scratch location.
- The ydotool passthrough cases run on an isolated PATH holding only the
  shim, the positive case's inert fake and bash/dirname/readlink; the
  missing-program case checks the shim's own refusal, so an installed
  ydotool cannot stand in for the intended absence
  (`tests/test-compat-desktop.sh:42`).
- `sandbox()` clears both uwsm launch markers with the compositor and session
  state (`tests/lib.sh:53-54`); launch scenarios set them explicitly. Two core
  checks seed inherited markers and require their removal
  (`tests/test-core.sh:7-11`). The Apps tests still cover uwsm, systemd scope
  and bare-command launches.

Runtime shell and desktop behaviour are unchanged.

## Diagnosis

- `tests/run.sh tests/test-clock-dayname.sh tests/test-greeter.sh
  tests/test-compat-desktop.sh tests/test-launcher-providers.sh` with a
  disk-backed `TMPDIR`: 132/149, all 17 failure counts (the aborted clock
  suite counts once).
- Copies of only the clock and greeter suites with `mktemp` under `TMPDIR`:
  90/90; no source change was needed to restore IPC.
- The ydotool scenario with the fake ahead of system PATH entries: 12/12;
  the isolated-PATH variant with the refusal assertion: 13/13. Before, the
  positive case ran `/usr/bin/ydotool` and got its missing-daemon-socket
  error.
- `env -u UWSM_FINALIZE_VARNAMES -u UWSM_WAIT_VARNAMES tests/run.sh
  tests/test-launcher-providers.sh`: 56/56. Both markers were inherited from
  the caller, so `Apps.qml` correctly took the uwsm branch while the fixture
  expected systemd scope launches.
- The new core checks before the `sandbox()` fix: 73/75.

## Rejected options

- Deleting unrelated `/tmp` files: it changes the owner's environment and
  leaves the fixtures dependent on its capacity.
- Accepting installed ydotool's exit code: it hides the wrong executable.
- Changing `Apps.launch`: it would break real uwsm sessions; isolation
  belongs to the test sandbox.
- Removing assertions, skipping engine tests or lengthening delays.

## Verification

- With inherited markers set (`UWSM_FINALIZE_VARNAMES=fixture-finalize
  UWSM_WAIT_VARNAMES=fixture-wait`) and a disk-backed `TMPDIR`:
  `tests/run.sh tests/test-core.sh tests/test-clock-dayname.sh
  tests/test-greeter.sh tests/test-compat-desktop.sh
  tests/test-launcher-providers.sh tests/test-apps.sh` 279/279.
- Full run, same environment: 12,545/12,545, 123 suites, all 33 VAPT suites
  without prerequisite skips. `tools/lint.sh`, `tools/check-docs.sh` and
  `tools/secrets.sh` OK.
