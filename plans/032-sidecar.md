# Plan 032: haseen-sidecar, the sampling daemon

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (a new language in the tree and a new process in the session)
- **Depends on**: 005 021 027
- **Category**: shell
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05

## Problem

Everything the shell knows about the machine was read from QML: a `Timer`, a
handful of `FileView`s and, for the process list, a `top -b -n 2` fork every
three seconds, per widget instance. That is the structural reason the shell
cannot be cheap: the work is in the UI process, repeated per screen, and in a
language that is bad at it.

## Decision

Take DankMaterialShell's shape (`core/cmd/dms`, `core/internal/{server,proto}`,
`Services/DMSService.qml`, `DgopService.qml:24`), not its scope:

- **One daemon**, `core/cmd/haseen-sidecar`, listening on
  `$XDG_RUNTIME_DIR/haseen/sidecar.sock` (mode 0600), one JSON object per line.
- **Started on demand** by the shell itself. It prints `ready <socket>` on
  stdout once bound, and the shell connects when it sees that line: Quickshell
  keeps a failed `QLocalSocket` around (`src/io/socket.cpp` `onSocketError`), so
  connecting blind to a socket that is not there yet poisons every later
  attempt. A second daemon finds the socket owned, prints `ready` and exits, so
  starting one is safe from any shell. It exits again five minutes after the
  last client leaves.
- **Capability negotiation.** The first frame is
  `{"type":"hello","protocol":1,"version":…,"capabilities":["sysusage"]}`, and
  `qs.Haseen.Sidecar.has("sysusage")` is what every consumer gates on, the way
  `DgopService.qml:24` gates on `capabilities.includes("dgop")`. No daemon, an
  older one, or one that was killed: the capability is absent and the feature
  hides instead of erroring.
- **One poller moved**, `haseen.sysusage`, as the proof case. Its `Sampler.qml`
  is now a subscription and nothing else: no `Timer`, no `FileView`, no
  `Process`. The daemon reads `/proc/stat`, `/proc/meminfo`, the GPU sysfs nodes
  (the old `gpu-probe.sh` is ported into Go) and `/proc/<pid>/stat`, which
  replaces the `top` fork. Subscribers are merged: two bars and the panel are
  one sampler at the shortest interval anyone asked for, and nothing is sampled
  while nobody is subscribed.
- **haseen's own IPC is untouched.** `DMSShellIPC.qml` (80 KB) is not ported;
  the socket carries sampling only.
- **Optional by construction.** `tools/build-sidecar.sh` builds it during
  `install.sh` when a Go toolchain is there and says so when not; the tree then
  ships without a daemon, and the capability gate does the rest.

## Verification

- `core/internal/sysusage` Go tests: CPU percentage including first sample and
  counter reset, memory with and without `MemAvailable`, the process list
  (sorting, limit, a comm with a space), and the GPU probe against fixture sysfs
  trees for i915 residency, i915 frequency fallback, xe gtidle, amdgpu and
  nvidia, plus `pickGPU` and the residency/frequency maths.
- `tests/test-sidecar.sh`: the Go tests, the build, then the wire protocol over
  a real socket — hello with the capability and protocol version, subscribe,
  the first sample arriving without waiting an interval, repeated samples, an
  unknown stream and method, garbage not killing the daemon, no sampling with
  nobody subscribed, a second daemon stepping aside, `haseen sidecar status`,
  and `shutdown` removing the socket.
- `tests/test-widgets-a.sh`: no widget has a `Timer` any more, and the sampler
  has no `Timer`, `FileView` or `Process` and gates on the capability.
- Live on the reference laptop: the shell started the daemon itself, the panel
  showed CPU 13 %, 12.5 GiB / 31.0 GiB (40 %), GPU card1 i915 15 % and the top
  processes; `kill -9` on the daemon left the shell running (`Sl`) and the bar
  readings disappeared.
- Where the work happens, over 30 s with the panel open (no `strace` on this
  machine; `/proc/<pid>/io` instead): daemon 21,864 read syscalls / 4.8 MB,
  shell 80 read syscalls / 16 KB.
- Idle CPU of a scratch shell whose only widget is `haseen.sysusage`, 60 s
  windows, `/proc/<pid>/stat` utime+stime:

  | path | before | after (shell + daemon) |
  |---|---|---|
  | bar widget only | 0.117 % | 0.083 % (0.050 + 0.033) |
  | widget + panel open | 0.633 % | 0.533 % (0.217 + 0.317) |

  The first version of the process sampler read `status` and `cmdline` for every
  task and measured 1.067 %, worse than `top`; reading `stat` for all and the
  other two only for the rows actually shown is what the table reports.

## Execution record

`core/` (module, `cmd/haseen-sidecar`, `internal/{proto,server,sysusage}`),
`share/haseen/shell/Haseen/Sidecar.qml`, the rewritten
`share/haseen/shell/plugins/haseen.sysusage/Sampler.qml` (and `Usage.js` cut to
formatting, `gpu-probe.sh` removed), `bin/haseen-sidecar`,
`tools/build-sidecar.sh`, the build step in `install.sh`, the Go section of
`tools/lint.sh`, `go`/`socat` in CI, and `tests/test-sidecar.sh`.

Known gap: the Nix package does not build the daemon (it would need
`buildGoModule` and a vendor hash), so a NixOS install has no `sysusage`
capability and the widget hides. Recorded in `handoff.md`.
