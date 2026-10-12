# Plan 089: desktop fixture isolation

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW, test fixtures only
- **Depends on**: 027 036 074 081 086
- **Category**: tests, shell
- **Planned at**: 2026-10-12, owner request to fix the 17 local gate failures
- **State**: DONE 2026-10-12, full local gate 12,545/12,545; final review of PR #40 remains pending

## Goals and changes

The complete run at `4577c27` reported **12,494/12,511**. The 17 counted
failures also reproduced on unchanged `main` at `da73029`, as recorded in
plan 088. This follow-up makes those fixtures independent of the caller's
session, installed ydotool and capacity-limited `/tmp`.

- Clock and greeter IPC fixtures honor `TMPDIR`, retaining their short,
  private runtime directories and existing cleanup. The caller can select a
  disk-backed scratch location. See `tests/test-clock-dayname.sh:208` and
  `tests/test-greeter.sh:245`.
- The ydotool passthrough cases use an isolated PATH containing the shim,
  the positive case's inert fake, and only bash/dirname/readlink. The
  missing-program case checks the shim's own refusal, so an installed
  ydotool failure cannot masquerade as the intended absence. See
  `tests/test-compat-desktop.sh:43`.
- `sandbox()` clears both uwsm launch markers with compositor/session
  state. Individual launch scenarios can set them afterward. Two new core
  checks seed inherited markers and require their removal. See
  `tests/lib.sh:52` and `tests/test-core.sh:7`. Existing Apps tests still
  exercise uwsm, systemd scope and bare-command launch paths.

Success requires the four original failing suites and the new isolation
checks to pass with inherited uwsm markers present, while preserving all
original behavioral assertions. The full lint/test/docs/secrets gates must
also pass. Runtime shell and desktop behavior are unchanged.

## Diagnosis evidence

- `TMPDIR=<disk-backed scratch> QT_QPA_PLATFORM=offscreen tests/run.sh
  tests/test-clock-dayname.sh tests/test-greeter.sh
  tests/test-compat-desktop.sh tests/test-launcher-providers.sh` at `4577c27`:
  **132/149**, exit 1, reproducing all 17 failure counts. An aborted clock
  suite contributes one count rather than its complete assertion total.
- Disposable copies of only the clock/greeter suites, changing only their
  `mktemp` location to honor `TMPDIR`: **90/90**, exit 0. No source or
  production configuration change was needed to restore IPC.
- The minimized ydotool scenario with the fake before system PATH entries:
  **12/12**. Its final isolated-PATH variant with a refusal-message assertion:
  **13/13**. The previous positive case instead selected `/usr/bin/ydotool`
  and returned its missing-daemon-socket error.
- `env -u UWSM_FINALIZE_VARNAMES -u UWSM_WAIT_VARNAMES tests/run.sh
  tests/test-launcher-providers.sh`: **56/56**. Both markers were inherited
  from the caller. `Apps.qml` correctly selected the uwsm branch, while
  this fixture expected and recorded only systemd scope launches.
- New core sandbox regressions before the shared-helper fix:
  **73/75**, exit 1. Both markers remained set. This tests the actual
  boundary that leaked the launch mode, rather than a copy of its logic.

## Rejected options

- Deleting unrelated `/tmp` files would change the owner's environment and
  leave the fixtures dependent on its capacity. Honoring `TMPDIR` solves
  the test problem directly.
- Accepting installed ydotool's exit code would hide the wrong executable
  selection. Removing the system PATH entries proves both presence and
  absence without any live input injection.
- Changing `Apps.launch` would break its intended behavior in a real uwsm
  session. The shared test sandbox owns isolation; explicit launch-path
  scenarios retain their markers.
- Removing assertions, skipping engine tests, or increasing timing delays
  would conceal the failures. All behavioral checks remain active.

## Final verification

- `TMPDIR=<disk-backed scratch> QT_QPA_PLATFORM=offscreen
  UWSM_FINALIZE_VARNAMES=fixture-finalize UWSM_WAIT_VARNAMES=fixture-wait
  tests/run.sh tests/test-core.sh tests/test-clock-dayname.sh
  tests/test-greeter.sh tests/test-compat-desktop.sh
  tests/test-launcher-providers.sh tests/test-apps.sh`: **279/279**, exit 0.
  All original failed cases pass, and the app-launch matrix still covers
  uwsm, systemd scope and bare commands. No engine scenario was skipped.
- `tools/check-docs.sh` and `git diff --check`: passed.
- `TMPDIR=<disk-backed scratch> GO=<installed Go 1.27.1>
  SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: **lint OK**, 402 shell,
  33 Lua, 180 JSON, 256 QML and 41 Go files.
- `TMPDIR=<disk-backed scratch> QT_QPA_PLATFORM=offscreen
  GO=<installed Go 1.27.1> UWSM_FINALIZE_VARNAMES=fixture-finalize
  UWSM_WAIT_VARNAMES=fixture-wait tests/run.sh`: **12,545/12,545**, 123 suites,
  exit 0. All 33 VAPT suites ran without prerequisite skips. No suite aborted
  and no failure line was reported.
- `TMPDIR=<disk-backed scratch> GITLEAKS=<verified upstream 8.30.1>
  tools/secrets.sh`: **secrets OK**, no leaks found. The secrets gate is
  repeated on the committed history before pushing.
- Disposable probe scripts were removed. No debug instrumentation or
  production source change remains.

The owner's final review from another model family for PR #40 remains
pending. These fixture fixes do not approve or merge either PR in the stack.
