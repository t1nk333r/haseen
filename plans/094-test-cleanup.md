# Plan 094: Test hygiene: inherited signals, a foreign directory, Go's cache

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (tests only: the suite's start, four test files' setup and cleanup; no shipped file changes)
- **Depends on**: 032 034 041 075 089
- **Category**: tests
- **Planned at**: 2026-10-20, owner: "do the cleanup", after gating PRs #43 and #44 on luna
- **State**: DONE 2026-10-20

## Problem

Three defects found while gating #43 and #44 on luna:

1. A full run on luna (`/tmp/hq6-full.log`, 14416/14419) failed three checks
   that pass when their files run alone:
   - `test-battery.sh`: "countdown: the charger closes the countdown
     notification (no orphaned notify-send)" (missing `notify-send closed`)
     and "undelivered (hang): the countdown is called off" (expected `false
     true 1`, actual `true false 0`);
   - `test-trigger.sh`: "recorder finalised on SIGINT" (missing `finalised`,
     in `started`).
2. `tests/test-capture-upload.sh:728-735` (on `b0dd8fd`) makes
   `$XDG_RUNTIME_DIR/haseen-search-screen` owned by a subordinate uid and
   never removes it.
3. Whatever else a finished `tests/run.sh` leaves behind that a plain
   `rm -rf` of the checkout cannot remove.

## Findings

### The flakes are inherited ignored signals, not load

All three failing checks wait for a shell fake to trap SIGINT: the fake
`gpu-screen-recorder` (`tests/test-trigger.sh:115-121`, `trap … INT`) and
the fake `notify-send` (`tests/test-battery.sh:270-276`), which
`bin/haseen-notification-send` stops with `kill -INT` when the charger comes
or the notification was not shown. A shell cannot trap a signal that was
ignored when it started (POSIX `trap`; bash keeps it ignored without a
word), and a background job of a non-interactive shell starts with SIGINT
and SIGQUIT ignored:

```
$ bash -c 'sleep 5 & grep SigIgn /proc/$!/status'
SigIgn:	0000000000000006
```

Run that way, the suite reproduces exactly the three failures, every time:

```
$ bash -c 'trap "" INT; exec "$@"' _ rt.sh /tmp/h94a tests/test-trigger.sh tests/test-battery.sh
test-trigger.sh
  FAIL recorder finalised on SIGINT
       missing: finalised
       in: started
test-battery.sh
  FAIL countdown: the charger closes the countdown notification (no orphaned notify-send)
       missing: notify-send closed
  FAIL undelivered (hang): the countdown is called off
       expected: false true 1
       actual:   true false 0
229/232 passed
```

(`rt.sh` is the hermetic wrapper of the task brief: a private 0700
`XDG_RUNTIME_DIR` and `TMPDIR`, a dead session bus, offscreen Qt.) Each
signature follows from the ignored SIGINT:

- the fake recorder never finalises, so `stop_recording`
  (`bin/haseen-capture-screenrecord:133-141`) waits its 50 rounds, kills it
  and the file keeps only `started`; the flag is still removed and "saved"
  still notified, which is why only that check failed in `hq6-full.log`;
- the fake `notify-send` ignores the charger's SIGINT, so no `notify-send
  closed`;
- with `NOTE_FAIL=hang` the sender's `stop_note` and `wait`
  (`bin/haseen-notification-send`, the not-shown branch) wait out the fake's
  10 s loop, longer than the scenario's 4000 ms, so the shell still has the
  countdown armed, not cancelled, nothing undelivered: `true false 0`.

CPU load does not cause them. Before the fix, with SIGINT at its default
and the CPU saturated, the same files passed every run (counts under
Evidence), and `stop_recording` took at most 340 ms under load average 60
(`rec-loop.sh`, 4 × 25 start/stop cycles), far from its 5 s limit.

Shipped code is not affected: the real recorder and `notify-send` install
their own handlers, which a C program may do over an inherited ignore
(`nm -D /usr/bin/gpu-screen-recorder`: `signal@GLIBC_2.2.5`;
`nm -D /usr/bin/notify-send`: `g_unix_signal_add`, libnotify 0.8.8).

CI runs each step of its `container: archlinux:latest` jobs through `docker
exec` (`.github/workflows/ci.yml:36,53`), where every disposition is the
default:

```
$ docker exec "$c" sh -c 'grep SigIgn /proc/self/status'
SigIgn:	0000000000000000
```

### The foreign capture directory

`tests/test-capture-upload.sh` creates the directory with `unshare
--map-auto --map-root-user sh -c 'mkdir -m 700 -- "$1" && chown 1:1 --
"$1"'`, so it belongs to the first subordinate uid (`stat`: `100000 700
…/search-store-foreign/run/haseen-search-screen`), and only that uid can
read it. The main checkout still had one from 09:53. On it:

```
du: cannot read directory 'tests/.out/search-store-foreign/run/haseen-search-screen': Permission denied
find: '…/haseen-search-screen': Permission denied
cp: cannot access '…/haseen-search-screen': Permission denied
chmod: changing permissions of '…/haseen-search-screen': Operation not permitted
warning: could not open directory '…/haseen-search-screen/': Permission denied   (git clean -fdx)
```

With coreutils 9.11 and git 2.55 a plain `rm -rf` and `git worktree remove
--force` do remove it on btrfs and tmpfs, because it is empty; anything
that has to read the tree does not.

### Go's module cache

`tests/test-sidecar.sh` and `tests/test-wallpaper.sh` keep `GOPATH` in
`tests/.out/gopath`, and Go writes its module cache read-only: 47 directories
mode 555 under `gopath/pkg/mod/golang.org/x/image@v0.46.0` in the main
checkout. `rm -rf` of a copy fails (`rm: cannot remove
'…/x/image@v0.46.0/go.sum': Permission denied`) until `chmod -R u+w`. This
is what makes `rm -rf` of a checkout that ran the full suite fail.
`test-sidecar.sh`'s `go test` also replaced `GOFLAGS` with `-count=1`,
dropping the file's own flags.

### Other state

`grep -rn 'unshare\|chmod 000\|chattr' tests tools`: the two `chmod 000` are
files (`tests/test-secureboot.sh:182`, `tests/test-desktop.sh:339`), which
`rm -rf` removes whatever their mode, and both are restored at once.

A full run of `dfbcf66` (the change below without the next fix) passed
14422/14422 and left one directory in its `TMPDIR`, which the wrapper lists
before removing it:

```
rt: left in TMPDIR:
/tmp/hc.qIYx/haseen-compat-runtime.6LviDt
/tmp/hc.qIYx/haseen-compat-runtime.6LviDt/quickshell
```

`tests/test-compat-runtime.sh:14-16` made it with `mktemp -d` and set
`trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT`, expanded at exit; `sandbox
compat-panel` at line 165 then moves `XDG_RUNTIME_DIR` into the sandbox, so
the trap removed that instead. The six other files with the same trap
(`test-compat-{font,lifetime,dms,tooltip}.sh`, `test-apps.sh`,
`test-branding.sh`) call `sandbox` before it and never after.

## Change

- `tests/run.sh`: when any signal is ignored at start (`SigIgn` in
  `/proc/$$/status`), re-exec once under `env --default-signal` (coreutils
  ≥ 8.31), so every test starts from default dispositions, as a terminal and
  CI's container exec do. A marker variable stops a loop.
- `tests/test-run-harness.sh`: a run started with SIGINT and SIGQUIT ignored
  still lets a test's shell fake trap both.
- `tests/test-capture-upload.sh`: `remove_foreign` removes the directory
  through the same namespace (`unshare --map-auto --map-root-user rm -rf`,
  10 s limit, no inherited descriptor, only when it exists and is not
  ours): after the check (and a new check that it is gone), from an `EXIT`
  trap when the file fails or is interrupted, and before the sandbox when an
  older run left one.
- `tests/test-sidecar.sh`, `tests/test-wallpaper.sh`: `GOFLAGS="-mod=mod
  -modcacherw"`, a stale read-only cache made writable, and `go test` adds
  `-count=1` to `GOFLAGS` instead of replacing it.
- `tests/test-compat-runtime.sh`: the trap removes the directory it made,
  held in its own variable.

## Evidence

Repeated runs of `tests/test-trigger.sh tests/test-battery.sh` on luna (16
CPUs), each through the hermetic wrapper, in separate detached worktrees run
in parallel; "before" is `b0dd8fd`, "after" this change:

| run | signals at start | load | runs | clean | failed checks |
| --- | --- | --- | --- | --- | --- |
| before | SIGINT, SIGQUIT ignored | 4 runs in parallel | 2 × 10 | 0 | the three named checks in all 20; "start and stop notified" in 15 |
| after | SIGINT, SIGQUIT ignored | 4 runs in parallel | 2 × 10 | 20 | none |
| before | default | 4 runs + 16 busy loops (load average 25) | 2 × 5 | 10 | none |
| after | SIGINT, SIGQUIT ignored | same | 2 × 5 | 10 | none |

("start and stop notified" fails too when the stop's forced kill wins the
race with the supervisor's "saved" notification.) Before that, under load
average 60 with default signals, `rec-loop.sh` ran 4 × 25 start/stop cycles
of `haseen capture screenrecord` against the test's fake recorder: 0 files
without `finalised`, 0 forced kills, slowest stop 340 ms.

- `tests/test-run-harness.sh`: 8/8 with the new `tests/run.sh`, 6/8 with
  `b0dd8fd`'s (both "a fake can trap SIG…" checks: `actual: ignored`).
- `tests/test-capture-upload.sh`: 364/364; a checkout holding an older
  run's 100000-owned directory is cleaned at the start of the next run, and
  `find tests/.out ! -user $USER` is empty after it. With a `false` added
  after the check the file aborts and the directory is still removed; with a
  `sleep 30` there and SIGINT sent to the run's process group, likewise.
- `tests/test-sidecar.sh tests/test-wallpaper.sh`: 63/63 over a copy of the
  main checkout's read-only cache (47 read-only directories before, 0
  after), and 39/39 for the sidecar file from an empty `GOPATH`.
- `tests/test-compat-runtime.sh`: 33/33, nothing left in `TMPDIR`; with the
  old file, 33/33 and `haseen-compat-runtime.*/quickshell` left.
- Full suite of this change (`8619433`, the same tests before this Evidence
  was written), from a detached worktree at
  `/tmp/h94`, under `flock ~/.cache/haseen-wt/suite.lock` and `env
  --default-signal`: 133 files, **14422/14422 passed**, nothing left in the
  run's `TMPDIR`. The earlier full run of `dfbcf66` (before the
  compat-runtime fix) was also 14422/14422 and left the one directory
  above.
- `tools/lint.sh` (shellcheck `/usr/bin/shellcheck`): lint OK;
  `tools/check-docs.sh`: OK; `tools/secrets.sh`: no leaks found.

## Rejected

- **Waits instead of fixed windows in `test-battery.sh` and
  `test-trigger.sh`.** The brief suspected timing. The fixed windows remain
  (the battery scenarios' `BATTERY_RUN_MS`, the recorder's 5 s stop grace),
  but they were not the cause: the checks never failed under load with
  default signals, and failed every time with SIGINT ignored, load or not.
  Replacing them would change what the scenarios observe without fixing
  anything found.
- **Make each fake robust to an ignored SIGINT.** A shell fake cannot undo
  the inherited ignore, and fixing each fake leaves the next one exposed;
  one reset in `tests/run.sh` covers every test.
- **Reset only SIGINT and SIGQUIT.** CI starts with every disposition at its
  default; resetting all matches it (an agent's shell here also ignored
  SIGPIPE, `SigIgn: 0000000000001000`).
- **A trap that `chmod`s the foreign directory.** This user cannot change
  it (`Operation not permitted`); only the namespace's root can.
- **Move `GOPATH` into each sandbox.** Every run would download and extract
  the module again; `-modcacherw` keeps one removable cache.

## Remaining

- The engine scenarios in `test-battery.sh` still observe fixed windows from
  the shell's start; a machine stalled for seconds could still miss a step.
- A test run with SIGINT ignored and no `env --default-signal` (coreutils
  older than 8.31) keeps the old behaviour.
