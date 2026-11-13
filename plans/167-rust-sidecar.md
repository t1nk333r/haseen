# Plan 167: the sidecar in Rust

Citations are `file:line` on `origin/main` at `87a14f5` unless they say
otherwise. "Measured" means a command run while planning, listed under
Verification.

## Status

- **Priority**: P2
- **Effort**: L (three pull requests; phase 1 is the large one)
- **Risk**: MEDIUM. The daemon feeds the bar's sysusage pill, the Your
  computer panel and the border wipe. The wire format is the contract, and
  two assertions already depend on how Go prints a float
  (`tests/test-sidecar.sh:132`, `bin/haseen-sidecar:52`). Phase 1 ships
  nothing to a user: the Rust binary is built and compared, not installed.
- **Depends on**: 032 (the sidecar), 058 (system stats), 069 (border wipe),
  099 (wootingd, the Rust precedent), 100 (affected tests), 127 (release
  binaries), 165 (PR #126, open while this was planned: it adds `sampleMu`
  and `core/internal/server/server_test.go`)
- **Category**: core
- **Planned at**: 2026-11-13, owner through the coordinator: port the Go
  daemon to Rust in three phases, each its own pull request
- **State**: phase 1 IMPLEMENTED 2026-11-13 (PR 1: `core/sidecar/`,
  `tests/test-sidecar-rs.sh`, `tools/sidecar-play.py`; nothing installed).
  Phases 2 and 3 are planned and wait on the owner's answers below.
- **Planned by**: Claude Fable 5.2; implemented by Claude Opus 5.5; reviewed
  by Claude Sonnet, and that review checked by Fable 5.2 ("Review" below)
  (owner, 2026-11-13: "Ask
  fable 5.2 to plan it then you opus to implement and sonnet to review it and
  then fable 5.2 to review the review").

## Problem

haseen has two compiled languages for three small programs. `core/` is a Go
module (`core/go.mod`: go 1.26.0, one dependency, `golang.org/x/image`) that
builds `haseen-sidecar` and `haseen-palette`; `core/wootingd/` is a Rust
crate (`docs/architecture.md:604`, "two compiled languages"). The cost today:

- Two toolchains in CI (`.github/workflows/ci.yml`, `ARCH_PACKAGES` holds
  `go` and `rust`), two lint paths (`tools/lint.sh:86-98` is Go only), two
  build functions and two skip paths in `tools/build-sidecar.sh`.
- The resident daemon carries Go's runtime. Measured on the planning
  machine with the `origin/main` build: 11.7 MiB RSS and 8 threads idle;
  16.9 MiB and 14 threads after 60 s of sampling at 3 s with `processes`
  and `system`; a 3.9 MB stripped binary. `docs/architecture.md` §6
  (`:723`) records 12 MiB for it, and it is the largest fixed cost haseen
  adds outside the shell.
- The Go server needed a mutex after the fact to stop two samples running at
  once (PR #126). A design in which one thread owns the sampler cannot have
  that bug.

## Decision

Port in three phases, one pull request each. The Rust daemon is
**wire-compatible**: same socket, same frames, same field names, order, types
and units, same flags and messages. `Sidecar.qml`, `BorderWipe.qml`, every
plugin and `bin/haseen-sidecar`'s protocol code do not change.

| Phase | Pull request | Ships to users |
|---|---|---|
| 1 | New crate `core/sidecar/`, its tests, a parity test against the Go daemon | nothing |
| 2 | Build, fetch, release, docs and tests switch to Rust; the Go sidecar is deleted | the Rust daemon |
| 3 | `haseen-palette` to Rust as `core/palette/`; Go leaves the repository | the Rust palette |

### D1. A crate of its own, not a workspace with wootingd

`core/sidecar/` with its own `Cargo.toml` and `Cargo.lock`.

- wootingd is vendored with "behaviour unchanged" and has its own lock file
  and `[profile.release]` (`core/wootingd/Cargo.toml`). A workspace moves
  profiles and the lock to the workspace root, which rewrites both.
- `tests/test-wootingd.sh:52-56` asserts wootingd's exact tracked files and
  its single dependency. A shared lock adds `libc` as a workspace member's
  dependency and breaks or weakens that assertion.
- `# haseen:covers core/wootingd/**` (`tests/test-wootingd.sh:2`) keeps the
  two selections apart: a sidecar change must not run the wootingd suite and
  the reverse.
- The only thing a workspace would share is `libc`'s compile, about a second.

Phase 3's palette is also its own crate (`core/palette/`): it needs image
decoders and SHA-256, and the resident daemon must not inherit that closure.

### D2. Standard threads and blocking I/O, one dependency

No async runtime. The daemon has at most a handful of clients (the shell and
`haseen sidecar status`), two timers and one event socket.

Dependencies: **`libc`** only (MIT OR Apache-2.0; already in wootingd's lock
closure through `parking_lot`). It is used for `statvfs`, `signal`,
`sysconf(_SC_PAGESIZE)` and `_exit`. JSON is hand-written: an encoder, and a
parser of about 200 lines for requests and Hyprland's answers. wootingd is the
precedent for both hand-written JSON and a raw signal handler
(`core/wootingd/src/main.rs:683-733`).

`Cargo.toml`: `edition = "2021"`, `license = "MIT"`, `rust-version` set to
the oldest toolchain the implementer actually builds with (see Open
questions), and wootingd's release profile (`opt-level = "s"`, `lto = true`,
`panic = "abort"`, `strip = true`). The version string comes from
`option_env!("HASEEN_VERSION")`, default `dev`, which replaces Go's
`-X main.version` (`tools/build-sidecar.sh`, Go build flags).

### D3. Module map

```
core/sidecar/
  Cargo.toml  Cargo.lock
  src/main.rs          flags, ready/failed lines, signals      <- cmd/haseen-sidecar/main.go
  src/proto.rs         frame names and encoders                <- internal/proto/proto.go
  src/json.rs          encoder (Go's number and string text), parser
  src/server.rs        listener, clients, dispatch, idle exit  <- internal/server/server.go
  src/sysusage/mod.rs  cpu, mem, processes                     <- sysusage/sysusage.go
  src/sysusage/gpu.rs                                          <- sysusage/gpu.go
  src/sysusage/nvidia.rs                                       <- sysusage/nvidia.go
  src/sysusage/system.rs  temperature, frequency, net, disks   <- sysusage/system.go
  src/borderwipe/mod.rs   the loop                             <- borderwipe/borderwipe.go
  src/borderwipe/frame.rs                                      <- borderwipe/frame.go
  src/borderwipe/hypr.rs                                       <- borderwipe/hypr.go
  src/borderwipe/theme.rs                                      <- borderwipe/theme.go
  tests/               integration tests (fake Hyprland, protocol)
```

`proto.rs` keeps the DMS attribution header from `proto.go` (Avenge Media
LLC, MIT), and `NOTICE.md:36` changes its path in phase 2.

The behaviour each module must keep follows. Where a rule looks odd it is
still the rule: the parity test compares against Go.

#### main.rs (`cmd/haseen-sidecar/main.go`, 108 lines)

- Flags, each accepted as `-name` and `--name`, with `=value` or a following
  argument, as Go's `flag` does. The shell tests and the CLI use one dash
  (`bin/haseen-sidecar` calls `-version` and `-capabilities`;
  `tests/test-sidecar.sh` uses `-idle-timeout 0` and `-state`).
  - `socket`: default `$XDG_RUNTIME_DIR/haseen/sidecar.sock`, with the
    temporary directory when the variable is unset.
  - `idle-timeout`: a Go duration. Parse a sequence of decimal numbers with
    units `ns us µs ms s m h`, and bare `0`. Default `5m`; `0` never exits.
  - `root`: prefix for `/proc` and `/sys` reads.
  - `state`: default `$HASEEN_USER_STATE`, else `$XDG_STATE_HOME/haseen`,
    else `~/.local/state/haseen`.
  - `capabilities`: print `sysusage borderwipe` and exit 0.
  - `version`: print the version and exit 0.
  - An unknown flag exits 2 with a usage message on stderr.
- A live daemon on the socket: print `ready <socket>` and exit 0. Any other
  listen error: print `failed <error>` on stdout, log it, exit non-zero.
- On success print `ready <socket>` and flush before serving:
  `Sidecar.qml` waits for a stdout line that starts with `ready ` or
  `failed`.
- Log lines go to stderr with the prefix `haseen-sidecar: `.
- SIGINT and SIGTERM: remove the socket and `_exit(0)` from the handler
  (unlink is async-signal-safe), as wootingd does. SIGPIPE is ignored so a
  write to a closed client returns an error.

#### json.rs

Go's `encoding/json` output is the wire format. The encoder must reproduce:

- **Field order** is struct order, listed per frame below.
- **Floats**: shortest text that round-trips; an integral value prints with
  no fraction (`50`, `-1`, `36`). Rust's `{}` for `f64` already does both.
  Outside `1e-6 <= |x| < 1e21` Go switches to exponent form with a trimmed
  exponent: `7.6e-7`, `1e+21`. Rust's `{}` does not, so format those with
  `{:e}` and insert `+` for a positive exponent. This range is reachable: a
  process's `mem` is `100 * rss / total`, and one 4 KiB page on a machine
  with 512 GiB is 7.6e-7. NaN and infinity cannot be encoded by Go (the
  encoder errors and the connection closes); no computation here produces
  them, so encode them as `-1` and say so in a comment.
- **Strings**: escape `"`, `\`, control characters as `\u00XX` except
  `\n`, `\r`, `\t`; and also `<`, `>`, `&` as `<`, `>`, `&`,
  and U+2028, U+2029 as ` `, ` `. Go replaces each invalid UTF-8
  byte with U+FFFD; `String::from_utf8_lossy` replaces a truncated sequence
  with one U+FFFD. That difference in a process's command line is accepted.
- **null against empty**: `"gpus":null` when no card was found,
  `"mem":null`, `"gpuInfo":null`; `processes`, `disks` and a GPU's `args`
  are always arrays (`[]`).
- **Omitted when empty**: a reply's `error`, `capabilities`, `data`; a
  status's `reason`, `secondsPerTurn`. The system fields appear at the top
  level of a sample only when a subscriber asked for `system`.

The parser accepts any JSON value. Request decoding:

- Not an object, or a field of the wrong type (`"id":"1"`, `"id":1.5`):
  reply `{"type":"reply","id":0,"ok":false,"error":"bad json"}` and keep the
  connection.
- A `null` line decodes to an empty request, so the answer is
  `unknown method: `.
- Empty lines are skipped. A line may be 1 MiB. Unknown fields are ignored;
  a repeated key keeps the last value.
- Go matches field names without regard to case. Rust matches them exactly.
  Accepted difference: every client in the tree sends lower case.

#### proto.rs and server.rs (`proto.go` 81, `server.go` 389)

Frames, in field order:

- hello: `type`, `protocol` (1), `version`, `pid`, `capabilities`
- reply: `type`, `id`, `ok`, `error`?, `capabilities`?, `data`?
- event: `type`, `stream`, `data`

Listen: create the parent directory 0700; connect first to detect a live
owner; remove a stale socket; bind; chmod 0600
(`tests/test-sidecar.sh` asserts `srw-------`). A Unix socket path is at
most 107 bytes; the tests must use a short one (measured: the Go daemon fails
with `bind: invalid argument` on a 118-byte path).

Dispatch (`server.go:226-271`):

- `subscribe` with stream `sysusage` (`:273-293`): `intervalMs` is a number
  above 0, truncated to milliseconds and raised to 500 ms; `gpu` a
  non-empty string, default `auto`; `processes` and `system` must be
  booleans. Reschedule, then take one sample at once. **Every** subscribe
  does this, including a repeated one: `Sidecar.qml` re-sends a merged
  subscribe on every want and drop, and each must produce one event. Do not
  coalesce.
- `subscribe` with stream `borderwipe`: record the signature and a rising
  sequence number; the subscriber with the highest sequence decides the
  signature; announce the current status to the new subscriber.
- `unsubscribe` with a stream drops that one; without, both.
- `capabilities`, `status` (data is `{"borderwipe": <status>}`),
  `shutdown` (always replies, then stops).
- Errors, verbatim: `unknown stream: X`, `unknown method: X`, `bad json`.
- A request with `id` 0 gets no reply unless it failed.
- Default interval 3 s, minimum 500 ms. The schedule is the shortest
  interval of all subscribers and restarts on every subscribe, unsubscribe
  and disconnect.
- One sample serves everyone (`sampleOnce`): `gpu` is any subscriber's
  value that is not `off` (when several differ Go takes the last one its
  map yields, which is unordered; Rust takes the highest client id, and the
  parity test does not exercise two different named cards); `processes` and
  `system` are OR-ed.
- A border wipe status change is logged as `border wipe <state>: <reason>`
  in the form `server.go`'s `wipeChanged` uses, and sent to every wipe
  subscriber.
- Idle exit: with no client connected for longer than the timeout, remove
  the socket and exit 0.

`docs/architecture.md` §6's 2 s floor is for the shell's Timers. The
daemon's 500 ms minimum stays for wire compatibility
(`tests/test-sidecar.sh` subscribes at 500 ms); no shipped plugin asks for
less than 2 s, and this plan does not change what they ask for.

#### sysusage/mod.rs (`sysusage.go`, 354)

Sample field order: `cpu`, `mem`, `gpu`, `gpus`, `gpuInfo`, `processes`,
then when asked `cpuTempC`, `cpuFreqMHz`, `net` {`rxBps`, `txBps`}, `disks`.

- **cpu**: the first `cpu` line of `/proc/stat` with at least five fields;
  the first eight values summed; idle is idle + iowait. `-1` on the first
  call, on a parse error, when the total did not move, or when idle went
  backwards. Clamp to 0..100.
- **mem** {`totalKiB`, `availableKiB`, `usedKiB`, `percent`,
  `swapTotalKiB`, `swapUsedKiB`}: `null` when `MemTotal` is not positive.
  Without `MemAvailable`, use `MemFree + Buffers + Cached`. `usedKiB` and
  `swapUsedKiB` do not go below 0. The KiB fields are integers.
- **processes** (top 8) {`pid`, `user`, `cpu`, `mem`, `command`}: read
  `/proc/<pid>/stat` for every numeric directory. The command name lies
  between the first `(` and the last `)`; at least 22 fields must follow;
  utime is index 11 after it, stime 12, resident pages 21.
  `cpu = 100 * Δjiffies / 100 / elapsed seconds` with HZ fixed at 100. A
  process seen for the first time and a negative delta are skipped; the
  first call returns `[]`. Sort by `cpu` descending, then `mem` descending.
  Only the top 8 get a `user` (the `Uid:` line of `status`, looked up in
  the live `/etc/passwd` and cached, falling back to the number) and a
  command line (`cmdline` with NULs as spaces, when not empty).
- When no subscriber wants `system`, forget the network counters, so the
  next system sample reports `-1` rates instead of a rate over a long gap.
- `--root` prefixes `/proc` and `/sys` paths only. `/etc/passwd`, the page
  size and the search for `nvidia-smi` on `PATH` stay live. Keep that.

Every function that uses time takes `now` as a parameter so tests can step
the clock. Reads reuse one buffer; the process table swaps two maps instead
of allocating a new one per sample.

#### sysusage/gpu.rs and nvidia.rs (`gpu.go` 199, `nvidia.go` 70)

GPU {`card`, `driver`, `bootVga`, `method`, `args`}.

- Probe once per daemon: `/sys/class/drm/card[0-9]+` entries that have
  `device/uevent`. Defaults: driver `unknown`, method `none`, args `[]`.
- `amdgpu`: method `busy` when `device/gpu_busy_percent` is readable.
- `nvidia`: method `nvidia` with the PCI slot when `nvidia-smi` is on
  `PATH`.
- `i915` and `xe`: method `rc6` from the first readable of
  `gt/gt0/rc6_residency_ms`, `power/rc6_residency_ms`,
  `device/tile0/gt0/gtidle/idle_residency_ms`; else method `freq` from
  `gt_act_freq_mhz` with `gt_max_freq_mhz`, or
  `device/tile0/gt0/freq0/act_freq` with `max_freq`.
- "Readable" means it opens and a one-byte read succeeds or reaches the end.
- Choice: `off` gives none; a name gives that card or none; `auto` gives the
  `boot_vga` card, else the first.
- Values: `busy` clamped to 0..100. `rc6` is `100 * (1 - Δidle / wall ms)`,
  `-1` on the first sample, on an error, when no wall time passed or when
  the counter went backwards; the previous value moves only after a good
  read. `freq` is `100 * act / max`.
- nvidia: one long-running `nvidia-smi --query-gpu=utilization.gpu
  --format=csv,noheader,nounits -i <slot> -l 3`; a reader thread keeps the
  last clamped value, `-1` until the first line. Restart it when the slot
  changes; kill and wait for it whenever the chosen card is not nvidia.

#### sysusage/system.rs (`system.go`, 472)

- **cpuTempC**: hwmon drivers in order `coretemp` (label `Package id 0`),
  `k10temp` (`Tdie`, then `Tctl`), `zenpower` (`Tdie`, then `Tctl`); a
  listed driver with no labels uses `temp1_input`; then a thermal zone of
  type `x86_pkg_temp`. Probed once and probed again after a failed read.
  Millidegrees / 1000. `-1` when unknown.
- **cpuFreqMHz**: the mean of the positive
  `cpuN/cpufreq/scaling_cur_freq` values (kHz / 1000), the file list probed
  once; else the mean of `cpu MHz` in `/proc/cpuinfo`; else `-1`.
- **net**: per-interface counters, `lo` excluded; received bytes are field
  0 and sent bytes field 8 after the colon. A new interface and a counter
  that went backwards contribute 0; a vanished interface is forgotten.
  `-1` and `-1` with no previous sample or an unreadable file. Bytes per
  second of elapsed time.
- **disks** {`mount`, `device`, `fstype`, `totalKiB`, `usedKiB`,
  `availKiB`, `percent`}: lines of `/proc/self/mounts` that start with
  `/dev/`; skip `squashfs`, `erofs`, `iso9660` and `/dev/loop`, `/dev/ram`,
  `/dev/zram`. One row per device, keeping the shortest mount point, then
  the smallest by byte order. Undo octal escapes (`\040`). Sizes use the
  fragment size, else the block size: total is blocks, available is
  `bavail`, used is `blocks - bfree`. Drop a mount whose stat fails or whose
  total is not positive. `percent = used / (used + avail)`, clamped. Sorted
  by mount. The stat call is on `root + mount`, and is a function pointer
  on the sampler so tests can replace it, as Go's `Sampler.Statfs` is.

#### borderwipe (`borderwipe.go` 445, `frame.go` 88, `hypr.go` 211, `theme.go` 78)

Status {`state`, `reason`?, `secondsPerTurn`?, `angle`, `frames`}. States:
`off`, `waiting`, `native`, `paused`, `running`. The first status is `off`
with reason `nobody subscribed`. Gate 2 s; shortest frame 100 ms. Both are
fields of an options struct so tests shorten them
(`borderwipe_test.go:318` uses 20 ms and 10 ms).

Reasons, verbatim: `nobody subscribed`, `the theme asks for no wipe`,
`colors.toml: <error>`, `Hyprland is not answering`,
`hyprctl animations: <error>`, `hyprctl getoption: <error>`,
`Hyprland's borderangle animation turns it`, `game context`,
`animations are off`, `no window has focus`,
`Hyprland refused the frame: <first line>`.

- **theme.rs**: read `<state>/current/theme/colors.toml`; keys
  `border_wipe` (colours separated by spaces) and `border_wipe_seconds`;
  values trimmed of spaces and quotes; a missing file is an empty theme. A
  colour is `rgba(` + 8 hex + `)`, `rgb(` + 6 hex + `)` or `0x` + 8 hex,
  else the error `border_wipe: a colour is not rgba(RRGGBBAA), rgb(RRGGBB)
  or 0xAARRGGBB`. The theme wants a wipe with two or more colours and
  seconds above 0. Both patterns are matched by hand; no regex crate.
- **frame.rs**: frames per turn = min(360, turn / shortest frame), at least
  1; interval = turn / frames; the angle in tenths of a degree is
  `(i % frames) * 3600 / frames`. The request is the `eval hl.config({...})`
  text of `frame.go`, with the angle as an integer or with one decimal,
  written into a buffer that is reused (no allocation per frame). At the
  default 36 s a turn that is 360 frames, 100 ms apart: §6's limit of 10
  frames a second.
- **hypr.rs**: sockets `<runtime>/hypr/<signature>/.socket.sock` (requests)
  and `.socket2.sock` (events). A request connects (2 s limit), sends,
  reads to the end and closes, with 2 s send and receive timeouts and the
  error `hyprland did not answer within 2 s`. Requests: `j/animations`,
  `j/getoption animations:enabled`, `j/activewindow`, `reload`.
  - Native loop: the answer is `[[leaves],[curves]]` or a flat list of
    leaves. Take the leaf `borderangle`; if it is not overridden and
    `global` exists, take `global`. True when it is enabled and its style
    starts with `loop`. No leaf means false.
  - Animations on: `{"bool":true}` or `{"int":1}`; neither field is the
    error `animations:enabled: no value in the answer`.
  - Focus: the answer contains `"address"`.
  - Events: `configreloaded>>`, and `activewindowv2>>data` where focus is
    data that is neither empty nor `,`. A closed socket is the event
    "gone". Lines up to 64 KiB.
- **mod.rs**, the loop:
  - `full()`: read the theme (a changed theme resets the frame index and
    the pace); connect to the event socket; a theme with no wipe is `off`,
    and the gate runs only while not connected; a native loop is `native`,
    with no gate and no frames; otherwise check focus, then `light()`.
  - `light()`: `<state>/flags/context` equal to `game`, then
    `j/getoption animations:enabled`.
  - `decide()`: gate on. Pause order: game, animations off, no focus.
    Otherwise `running` with a frame deadline every pace interval.
  - On the gate (every 2 s): `light()` when connected and the border is
    ours (`running` or `paused`), else `full()`. This is the 2 s retry
    while Hyprland is away.
  - `frame()`: send the request; an answer that starts with `error` moves
    to `waiting`. Advance the index modulo the frame count, note that a
    frame was sent since the last reload, store the tenths, count the frame.
  - Events: gone disconnects and runs `full()`; a reload runs `full()`, and
    **if frames were sent since the last reload and the state is now `off`
    or `native`, send one more `reload`** so Hyprland's own configuration
    takes the border back; focus runs `decide()` when the border is ours.
  - Publish only when state, reason or seconds change; an announce to a
    new subscriber always sends. A control message with the same activity
    and signature does nothing; a changed signature disconnects first.
  - The signature comes from the subscriber, else the daemon's own
    `HYPRLAND_INSTANCE_SIGNATURE`; with neither, not connected.

### D4. Concurrency

- **Accept thread**: one thread per client reads lines and dispatches. Each
  client's socket is written under that client's mutex, so a reply and an
  event never interleave. Go sets no write deadline
  (`server.go` has no `SetWriteDeadline`), so neither does Rust.
- **Sampler thread** owns the `Sampler`: it is moved into the thread, so two
  samples cannot overlap by construction. PR #126's `sampleMu` has no
  counterpart. It waits on a channel with `recv_timeout(deadline)`;
  messages are `Reschedule`, `SampleNow`, `Shutdown`. With no subscriber
  there is no deadline and the thread blocks.
- **Wipe thread** owns the loop state. One channel carries control messages
  and Hyprland's events; the gate and frame deadlines are `recv_timeout`.
  A deadline that was missed is not made up: the next one is `now +
  interval`, which is what Go's ticker does. A reader thread per event
  connection forwards lines tagged with a connection number; disconnecting
  shuts the socket down to unblock it, and events from an old number are
  ignored.
- **Shared state** (clients, subscriptions, the wipe sequence, the time the
  last client left) sits behind one `Mutex`. Order: state, then a client's
  writer. The state lock is never held while sampling or while talking to
  Hyprland.
- **Idle exit**: a `Condvar` wait until `last leave + timeout`, woken on
  connect and disconnect. Go polls once a second (`idleWatch`). Accepted
  difference: Rust exits up to 1 s sooner and wakes zero times while idle.
- Thread stacks are set to 128 KiB with `thread::Builder`.

### D5. Resource budget

| | Go, measured | Rust, budget |
|---|---|---|
| RSS, idle, no client | 11.7 MiB | 2 MiB |
| RSS after 60 s at 3 s, `processes` + `system` | 16.9 MiB | 4 MiB |
| Threads, idle / sampling | 8 / 14 | 2 / 4 |
| CPU over 60 s at 3 s, `processes` + `system` | 11 jiffies (0.18 % of a core) | no more than Go on the same machine in the same minute |
| Wakeups, idle, no client | 1 a second (`idleWatch`) | 0 |
| Reads with no subscriber | `syscr` delta under 20 in 2 s (`tests/test-sidecar.sh`) | same assertion |
| Binary, stripped | 3.9 MB | 1 MB |

How to measure, for both binaries on the same machine, in the pull request's
description and in this plan's Verification when it lands:

```sh
d=$(mktemp -d) && cd "$d"            # a short path: the socket limit is 107 bytes
"$BIN" -socket s.sock -idle-timeout 0 >log 2>&1 & pid=$!
grep -E 'VmRSS|Threads' /proc/$pid/status
cat /proc/$pid/task/*/status | awk '/^voluntary/{n+=$2} END{print n}'   # twice, 60 s apart
( printf '{"id":1,"method":"subscribe","stream":"sysusage","params":{"intervalMs":3000,"processes":true,"system":true}}\n'; sleep 61 ) \
    | socat - UNIX-CONNECT:s.sock >events &
a=$(awk '{print $14+$15}' /proc/$pid/stat); sleep 60
b=$(awk '{print $14+$15}' /proc/$pid/stat); echo $((b-a)) jiffies
grep -E 'VmRSS|Threads' /proc/$pid/status
```

The border wipe row of plan 069's table (`plans/069-border-wipe.md:219-224`:
0.27 % of a core at 36 s a turn, 0.07 % paused) is measured again in phase 2
on a machine running Hyprland, which is an owner step.

### D6. Tests

**Go unit tests become Rust tests with the same names in snake case**, in
the module they test. Fixtures are built in a temporary directory by the
test, as the Go tests do (there is no shared `testdata`).

| Go file | Tests |
|---|---|
| `sysusage_test.go` | CPUPercent, CPUPercentGarbage, Mem, MemFallback, MemGarbage, Processes, ProcessLimit |
| `gpu_test.go` | ProbeIntelResidency, ProbeIntelFrequencyFallback, ProbeXeGtidle, ProbeAmdAndNvidia, ProbeEmpty, PickGPU, GPUSampleBusyAndFreq, GPUSampleResidency, GPUSampleOff |
| `system_test.go` | CPUTempPrecedence, CPUTempUnlabelled, CPUFreq, CPUFreqFallback, NetRate, Disks, SystemFieldsOnRequest |
| `borderwipe_test.go` | PaceCutsATurnIntoFrames, FrameIsTheEvalTheLoopOnLunaSent, ReadTheme, NativeLoop, OptionAndFocusAnswers; and against a fake Hyprland on two sockets in a temporary directory: NeverRunsBesideTheNativeLoop, TurnsTheBorderOneDegreeAFrame, PausesAndResumes, ReconnectsWhenHyprlandComesBack, ReloadHandsTheBorderBack, OffWithoutASubscriber |
| `server_test.go` (PR #126) | ConcurrentSamplesAreSerialised becomes a test that eight clients subscribing 200 times each get well-formed events and the daemon survives |

New Rust tests with no Go counterpart: number text (`50`, `-1`, `0.1`,
`7.6e-7`, `1e+21`), string escapes, `null` against `[]`, omitted fields, the
request decoding table of D3, the duration parser, both flag spellings.

**The parity test**, `tests/test-sidecar-rs.sh` (phase 1), is the acceptance
gate. It builds both daemons, then for each case starts each daemon on its
own short socket with the same `-root` fixture and `-state` directory, plays
the same lines and compares what comes back.

- Replies, hello and status frames are compared **byte for byte** after
  replacing `pid` and `version`.
- Sysusage: subscribe with `intervalMs` of 3600000, so the only events are
  the one each subscribe triggers. Between subscribes the test rewrites the
  fixture (`proc/stat`, `proc/meminfo`, `proc/net/dev`, a process's
  `stat`). Deterministic fields are compared byte for byte: `cpu`, `mem`,
  `gpus`, `gpuInfo`, `cpuTempC`, `cpuFreqMHz`, `disks`, and `gpu` for
  `busy` and `freq` cards. Fields divided by wall time (`net`, a process's
  `cpu`, `gpu` for `rc6`) are compared for presence and sign there, and
  their exact arithmetic is covered by the unit tests with a stepped clock.
- Fixtures cover: an empty root (`cpu` -1, `mem` null, `gpus` null); an AMD
  card; Intel `rc6`; Intel `freq`; `xe`; two cards with `boot_vga`; a mount
  with an escaped space; a process whose command holds `<`, `&` and a
  parenthesis in its name; an unlabelled hwmon driver.
- Protocol cases: bad JSON, a wrong-typed id, `null`, an empty line,
  unknown method and stream, id 0, unsubscribe with and without a stream,
  `intervalMs` of 0, negative and a string, `processes` as a string,
  `capabilities`, `status`, `shutdown`.
- Border wipe without Hyprland: no theme (`off`), a theme with two colours
  and 36 s (`waiting`, `secondsPerTurn` printed as `36`), a bad colour
  (`colors.toml: …`). The loop itself against a fake Hyprland is the Rust
  integration tests' job.
- Flags and exits: `-capabilities`, `--capabilities`, `-version`, a second
  daemon on a live socket, an unwritable socket directory (`failed …`).

It skips without `cargo`, and skips only the comparison without `go` or
`socat`; under `HASEEN_REQUIRE_ENGINE=1` (CI) a missing tool is a failure,
as in `tests/test-wootingd.sh`. It uses a private `CARGO_HOME` and
`CARGO_TARGET_DIR` under `$OUT` and carries `RUSTUP_HOME`, as that test
does. It also runs every assertion block of `tests/test-sidecar.sh` (hello,
events within 2 s at 500 ms, `syscr`, second daemon, the three status lines,
shutdown) against the Rust binary through `bin/haseen-sidecar` with the
binary path overridden; if `bin/haseen-sidecar` has no override today the
test copies the tree's `bin/` and `share/` into `$OUT` and puts the Rust
binary at `share/haseen/sidecar/haseen-sidecar` there.

**Selection.** The new file declares

```
# haseen:covers core/sidecar/** core/{go.mod,go.sum}
# haseen:covers core/cmd/haseen-sidecar/** core/internal/{proto,server,sysusage,borderwipe}/**
```

so a change to either daemon runs the parity test, and a change to the
crate runs nothing else. `tools/affected-tests.sh` fails lint on a tracked
file no test covers, so the crate's files and this glob land in the same
commit. Check with `tools/affected-tests.sh` that every new path selects
only this file.

**Shell tests that must pass with no edit in phase 1**:
`tests/test-sidecar.sh`, `tests/test-sidecar-fetch.sh`,
`tests/test-sidecar-release.sh`, `tests/test-wallpaper.sh`,
`tests/test-wootingd.sh`, `tests/test-computer.sh`,
`tests/test-widgets-a.sh`, `tests/test-omarchy-commands.sh`. In phase 2
`tests/test-sidecar.sh` changes only above its first protocol assertion
(the toolchain check, `go test` to `cargo test`, the covers lines); every
assertion from `-capabilities` down stays as it is.

### D7. Build, CI and release

Phase 1 changes no build script. Phase 2:

- `tools/build-sidecar.sh`: a `build_sidecar` function beside
  `build_wootingd`: `HASEEN_VERSION=$VERSION cargo build --release --locked
  --quiet --manifest-path core/sidecar/Cargo.toml`, target directory
  `${CARGO_TARGET_DIR:-$XDG_CACHE_HOME/haseen/sidecar-target}`, the binary
  copied to `share/haseen/sidecar/haseen-sidecar` (already ignored,
  `.gitignore:5-7`). Without `cargo`, or with a compiler older than
  `rust-version`, fetch the release binary exactly as `fetch_go` does now:
  same URL, same asset names, same `SHA256SUMS` check, same environment
  variables (`HASEEN_FETCH_SIDECAR`, `HASEEN_SIDECAR_URL`,
  `HASEEN_SIDECAR_TIMEOUT`, `HASEEN_BUILD_SIDECAR`). `build_go` shrinks to
  the palette until phase 3. The offline rule of plan 127 holds: no
  toolchain and no network leaves the tree without a sidecar, with a
  warning, and the shell runs without it.
- `tools/release-sidecar.sh`: build `x86_64-unknown-linux-musl` and
  `aarch64-unknown-linux-musl`, static, and upload under the same four
  asset names with `SHA256SUMS`. Static keeps plan 127's promise of one
  file per architecture that runs on any distribution. The daemon uses no
  NSS and no DNS (it reads `/etc/passwd` itself), so a static musl build
  loses nothing. Arch packages both targets (`rust-musl`,
  `rust-aarch64-musl`, measured with `pacman -Si`). The arm64 link uses
  `rust-lld` with the target's self-contained runtime; the script runs the
  arm64 binary's `-version` under `qemu-aarch64-static` when it is
  installed. This link step is **not yet verified** (Risks).
- `share/haseen/VERSION` is bumped in phase 2, so the fetch path can never
  hand a tree that expects Rust a Go binary of the same version or the
  reverse. (Either would work, since they are wire-compatible; the bump
  keeps `haseen sidecar status` honest.)
- `tools/lint.sh`: beside the Go block (`:86-98`), `cargo fmt --check
  --manifest-path core/sidecar/Cargo.toml` when `cargo` exists. wootingd is
  not formatted or linted: it is vendored unchanged. `cargo clippy --locked
  -- -D warnings` runs inside the test file, where the crate is already
  built.
- CI: `.github/workflows/ci.yml` is **not edited in phases 1 and 2**. It
  already installs `rust`, `go` and `socat`, and any edit to it selects
  every test (`tools/affected-tests.sh`, GLOBAL). `go` leaves
  `ARCH_PACKAGES` in phase 3, which pays for that full run once.
- Docs in phase 2: `docs/architecture.md` §5.6 (`:583`) and §5.7 (`:604`),
  §6's sidecar figures (`:723`) with the new measurements, `README.md:12`
  ("one small Go daemon"), `NOTICE.md:36`, `handoff.md`,
  `bin/haseen-sidecar`'s help ("needs go"), and the end-user skill if it
  names Go.

## Pull requests

Gates for every one, run from the branch, in this order:

```sh
SHELLCHECK=/path/to/shellcheck tools/lint.sh
tests/run.sh --affected
tools/check-docs.sh
tools/secrets.sh
```

Say in the description which test files `--affected` selected. Do not run
the whole suite by hand.

### PR 1: `sidecar: add the rust daemon beside the go one`

Rebase on `main` after PR #126 merges; if it has not merged, proceed and
port its test when it does.

1. `core/sidecar/Cargo.toml`, `Cargo.lock`, `src/json.rs` with its tests.
2. `proto.rs`, `main.rs` flags, `server.rs` with listen, hello, dispatch,
   idle exit and shutdown, no streams yet. Protocol cases of the parity
   test pass.
3. `sysusage/` with the ported unit tests; the sampler thread; the fixture
   cases pass.
4. `borderwipe/` with the ported unit tests and the fake Hyprland tests;
   the wipe thread; the status cases pass.
5. `tests/test-sidecar-rs.sh` complete; this plan as
   `plans/167-rust-sidecar.md` and its row in `plans/README.md`;
   `NOTICE.md` row for `core/sidecar/src/proto.rs`.
6. Measure D5 for both binaries and write the numbers into the plan.

Acceptance:

- `cargo test --locked` passes; every Go test in D6's table has its Rust
  counterpart, named in the description.
- The parity test passes with both toolchains present, and CI ran it (not
  skipped) under `HASEEN_REQUIRE_ENGINE=1`.
- `--affected` selected `tests/test-sidecar-rs.sh` and no other file.
- No file outside `core/sidecar/`, `tests/test-sidecar-rs.sh`, `plans/`,
  `NOTICE.md` and `handoff.md` changed. No build script, no QML, no CI.
- `cargo tree` shows `libc` and nothing else.
- D5's budgets are met, with the commands' output in the description.

### PR 2: `sidecar: build and ship the rust daemon, remove the go one`

1. Record the Go daemon's answers for every deterministic parity case as
   files under `core/sidecar/tests/golden/`, and make the Rust integration
   tests compare against them. This keeps the comparison after Go is gone.
2. `tools/build-sidecar.sh`, `tools/release-sidecar.sh`, `tools/lint.sh`,
   `bin/haseen-sidecar` (help and `build`), as D7.
3. Delete `core/cmd/haseen-sidecar/`, `core/internal/{proto,server,
   sysusage,borderwipe}/`. `core/go.mod` stays for the palette.
4. Fold `tests/test-sidecar-rs.sh` into `tests/test-sidecar.sh` (covers:
   `bin/haseen-sidecar core/sidecar/**` and its other lines unchanged);
   update `tests/test-sidecar-fetch.sh` (no `cargo` in place of no `go`,
   the new message) and `tests/test-sidecar-release.sh` (a `cargo` stub in
   place of the `go` stub; the four asset names unchanged). Remove the Go
   globs that no longer match a file from every `# haseen:covers` line.
5. Bump `share/haseen/VERSION`; docs as D7; plan 167's State.
6. After merge, an owner step: `tools/release-sidecar.sh`, then install on
   one machine and read `haseen sidecar status`, the sysusage pill, the
   Your computer panel and the border wipe.

Acceptance: the assertion body of `tests/test-sidecar.sh` is unchanged and
passes against the Rust binary; `--affected` selects the tests that cover
`tools/build-sidecar.sh` (sidecar, sidecar-fetch, sidecar-release,
wallpaper, wootingd, omarchy-commands) and they pass;
`grep -rn 'sudo ' bin share | grep -v common.sh` is still empty; a tree
with neither `cargo` nor network installs with the warning and no sidecar;
`go build ./...` in `core/` still builds the palette.

### PR 3: `palette: port the generator to rust, remove go`

Recommended, with the trade-off stated for the owner (Open questions, Q6).

1. Before any port: a corpus of small images in the test (PNG, GIF, JPEG,
   WebP; a few hundred bytes each, generated, no personal pictures) and the
   Go generator's JSON for each mode, dark and light, committed as golden
   files.
2. `core/palette/` with its own lock: decoders for the four formats and
   SHA-256 from crates under MIT or Apache-2.0, default features off, the
   closure listed in the plan with each licence and a `NOTICE.md` row for
   the omacom/aether port (`NOTICE.md:39`). Same flags (`--light`,
   `--mode`, `--json`, `--version`), the same header limits (20000 px a
   side, 200 M pixels), the same cache path and atomic write.
3. PNG and GIF decode exactly, so those goldens must match byte for byte.
   JPEG and lossy WebP decoders may differ by one level a channel between
   Go and Rust, and `powf`/`cbrt` may differ in the last bit; those goldens
   allow one step a channel. Bump `cacheVersion` to 3 so no cached Go
   palette is read as Rust's.
4. Delete `core/go.mod`, `core/go.sum`, `core/cmd/`, `core/internal/`, the
   Go block of `tools/lint.sh`, `build_go`, the Go half of the release
   script; take `go` out of `ARCH_PACKAGES` (this edit runs the full suite
   in CI, once); remove the Go globs from `tests/test-wallpaper.sh`;
   `docs/architecture.md` §5.7 says one compiled language.

Acceptance: `tests/test-wallpaper.sh` passes with its assertions unchanged
(`:69-82`: 16 ANSI slots, `accent`, `palette unchanged` on a second run);
the goldens pass within the stated tolerance; `git ls-files '*.go'` is
empty; `grep -rn '\bgo\b' tools .github` finds no toolchain use.

## Phase 1, as built

Where the code departs from the text above, the code is right and this says
why. Every point is checked by a test named here.

- **Two of D3's accepted differences are gone.** Request fields are matched
  without regard to ASCII case, as Go's decoder matched them
  (`core/sidecar/src/proto.rs`, `decode_request`; test
  `request_decoding_is_gos`). Invalid UTF-8 becomes one U+FFFD per byte:
  that is what Go 1.27's encoder writes, raw, not the `\ufffd` escape older
  Go wrote, so `json::go_lossy` matches it (test
  `invalid_utf8_is_one_replacement_per_byte`, against Go's own output for
  `E2 82 41 FF`). The two left: the idle exit may come up to 1 s sooner, and
  two subscribers naming different GPU cards get the later client's.
- **One new difference: nesting.** Go accepts 10000 levels of arrays and
  objects on a growing stack. A client thread here has 256 KiB, which a debug
  build fills at about 400 levels, so a line nested deeper than 100 is
  `bad json` (`json::MAX_DEPTH`; test `the_deepest_line_fits_a_client_thread`).
  Requests and Hyprland's answers nest three deep.
- **Go's `float64` decoding** refuses a number out of range anywhere in
  `params` (`1e400`, also inside an array), and the whole line is `bad json`;
  `1e-400` reads as 0. Both are kept (`proto::floats_fit`).
- **Go writes `\b` and `\f`** as such (Go 1.22 and later), not `\u0008`;
  the encoder does the same (test `string_escapes_are_gos`).
- **Frame timing follows Go's ticker**, not "now + interval" (D4): frames sit
  on a fixed grid, and the ticks missed while the loop was busy fire once, at
  once, the next on the first slot after (`borderwipe::Ticker`; tests
  `ticker_drops_missed_slots_like_gos` and `TurnsTheBorderOneDegreeAFrame`).
- **The reply to a sysusage subscribe comes before its first event.** Go
  sampled on a goroutine, so either could come first; the Rust server asks
  for the sample after writing the reply (`Inner::dispatch`). The parity test
  sorts the frames between two waits, so it holds both daemons to the same
  set.
- **Only `waiting` is logged** for the border wipe (`server.go`'s
  `wipeChanged`), not every state as D3 said.
- **`mkdir` errors read as Go's:** `os.MkdirAll` reports "not a directory"
  for a file in the way, where Rust's `create_dir_all` says "File exists"
  (`server::mkdir_all`; the parity test's `blocked` case compares the line).
- **No `rust-version`.** The lock file is format 4, which needs cargo 1.78
  or later, and the code uses `Option::is_none_or` (1.82) and
  `u64::is_multiple_of` (1.87); the only older toolchain at hand (1.77)
  cannot read the lock file, so nothing older than 1.99 was verified, and
  the crate declares none, as wootingd does (open question 5). Without one,
  clippy suggests the newest API: it asked for `is_multiple_of` on the first
  run. So the test's `clippy -D warnings` can fail after an Arch rust update
  that adds a lint, with no change in haseen; the fix is then the lint's.
- **Two files outside PR 1's list.** `tools/sidecar-play.py` plays one
  script to a daemon and prints the frames, masked where wall time enters;
  the parity test calls it for both daemons. And `--affected` selects
  `tests/test-core.sh` beside `tests/test-sidecar-rs.sh`, because
  test-core checks every new test file's header.
- **Threads**: accept (the main thread), the sampler, the border wipe, one
  per client, the idle exit when it is on, and an event reader while
  Hyprland is connected. Idle with no client that is three.

Results, on this laptop, the Go daemon built from `origin/main` (`87a14f5`)
with `CGO_ENABLED=0 go build -trimpath -ldflags "-s -w"` and the Rust one
with `cargo build --release --locked`, both measured by D5's commands in the
same minute (the Go figures differ from the planning machine's):

| | Go | Rust | D5 budget |
|---|---|---|---|
| RSS idle, no client | 7.8 MiB, 7 threads | 2.7 MiB, 3 threads | 2 MiB, 2 threads (missed by 0.7 MiB and one thread) |
| after 60 s at 3 s, `processes` + `system` | 10 jiffies, 12.1 MiB, 14 threads | 8 jiffies, 3.2 MiB, 4 threads | 4 MiB, no more CPU than Go |
| events in that minute | 23 | 23 | |
| voluntary wakeups idle, 10 s, `-idle-timeout 0` | 0 | 0 | 0 |
| binary, stripped | 3.9 MB | 613 KB | 1 MB |

Tests: `cargo test --locked` runs 56 unit tests (every Go test of D6's table
under its snake-case name, plus the encoder, decoder, duration and flag
cases) and 10 protocol tests against the built binary
(`core/sidecar/tests/protocol.rs`, including
`concurrent_subscribers_are_served`, the counterpart of PR #126's
`TestConcurrentSamplesAreSerialised`). `tests/test-sidecar-rs.sh` runs them,
clippy with `-D warnings` and `cargo fmt --check`, then plays the same
scripts to both daemons (`tools/sidecar-play.py`) over the same fixture:
the protocol cases, two samples of every reader with the fixture moved
between them, an empty root, the border wipe's states without a Hyprland,
and every flag and exit; then test-sidecar.sh's socket checks against the
Rust binary.

## Review

Claude Sonnet reviewed 410ecac against the Go daemon, with probes of its
own: a fake Hyprland, 44 hostile request lines and four extra fixture
families through both daemons, and 400 clients at once. Fable 5.2 then
checked that review and probed what it missed. Fixed before the merge:

- **Connect with no timeout** (Sonnet 1, medium). A Hyprland alive but not
  accepting (a full backlog) blocked the wipe thread in `connect(2)` for
  good, so it handled no subscribe, unsubscribe or event. Go set the send
  timeout before connecting and dialled the event socket with a 2 s limit.
  `hypr::connect_within` now does the same for both sockets (test
  `a_full_backlog_times_out`).
- **The ticker fired twice after a stall** (Sonnet 2). Now one step to the
  first slot after the late tick; Fable 5.2 replaced the suggested loop,
  which a 1 ns interval would have run billions of times.
- **A value Go could not encode** (Sonnet 3: `border_wipe_seconds = inf`)
  produced invalid JSON in `status` and dropped the wipe event silently; Go
  closed the connection, and now so does this daemon.
- **A stuck client stopped every other client's samples** (Fable 5.2, missed
  by the first review). The reader's cleanup waited for the writer lock that
  the sampler held while blocked writing to that client. Each client now has
  one fd, writers take a separate lock and closing takes none (test
  `a_stuck_client_does_not_stop_the_others`, which fails on 410ecac). This
  also halves the fds per client: with 1024 fds the reviewed build served
  510 clients where Go served 1014.
- **The default `-socket` and `-state`** are cleaned as Go's filepath.Join
  cleaned them, and without HOME the state default is relative, as Go's
  (Sonnet 4; the usage text of both daemons compared under three
  environments).
- **The parity test** asserts that each transcript starts with a hello, so
  two daemons that both failed to start cannot compare equal; it adds an
  empty line, a CRLF line and `intervalMs` 0 and -5; its covers globs add
  what it uses (`tools/build-sidecar.sh`, `share/haseen/VERSION`,
  `bin/haseen-sidecar`, the haseen theme's colors.toml). The test scratch
  directory stays short enough for a socket under a long TMPDIR.

Recorded, not changed:

- **Number text both daemons parse differently** (Sonnet 5): Go's
  ParseFloat takes `1_0` and hex floats and refuses `1e400`; Rust's parse
  refuses the first two and reads `1e400` as infinity, so a sysfs node
  holding `1e400` reads 100 here and -1 in Go. Request keys fold ASCII case
  only, where Go also folds `ſ` to `s`. `parse_duration` takes
  `9223372036854775808ns` and rounds `0.5ns` up. `nvidia-smi` is found by
  its mode bits, not by access(2). A complete line over 1 MiB that arrives
  in one read with the line before it is still read. None is reachable from
  a real file or client.
- **A theme's seconds** are not clamped in either daemon: under 0.1 s a turn
  is one frame per turn with no minimum (1000 requests a second at 0.001),
  `inf` panicked Go's NewTicker and gives this daemon a 296-day frame. A
  clamp is a follow-up for phase 2.
- **A client that never reads** still stops the sampler once its buffer is
  full, until it closes: Go's timer was not re-armed either (Sonnet 6).
- **An accept error ends the daemon** (`EMFILE`), exit 1, socket left, as in
  Go.
- **Masked fields** in the parity test (rates, a process's cpu, a chosen rc6
  card's gpu, disk sizes) are checked only for being -1 or not; their
  arithmetic is covered by the unit tests. PR 2's golden files can pin more.
- **D5's idle budget** is missed by 0.7 MiB and one thread (2.7 MiB, 3
  threads); the owner decides whether that matters.

## Rejected options

- **A cargo workspace with wootingd.** D1.
- **`serde` + `serde_json`.** It prints an integral float as `50.0`, which
  breaks `tests/test-sidecar.sh:132` and the status line
  (`bin/haseen-sidecar:52`), so a custom float serializer would be needed
  anyway; and it adds proc-macro compilation to a CI test job that already
  has a 150-minute limit (`.github/workflows/ci.yml`).
- **`tokio`, `async-std`, `smol`.** A runtime for three sockets and two
  timers; more RSS and more threads than the design in D4.
- **`mio` or `polling` with one thread.** Fewer threads, but the sampler's
  file reads and Hyprland's 2 s request timeouts would block the loop, or
  need the same threads back.
- **`regex`** for two fixed patterns; **`nix`, `rustix`, `signal-hook`**
  for four libc calls; **`parking_lot`** when `std::sync` is enough;
  **`ryu`** when `{}` already prints the shortest round-trip text.
- **Declaring `statvfs` by hand without `libc`.** The struct layout differs
  by architecture and C library; `libc` is the place that knows it.
- **glibc release binaries.** They tie the released file to the build
  machine's glibc version, which plan 127's static Go binaries never did.
- **Coalescing the immediate samples of rapid subscribes.** Better numbers
  (a sample over a millisecond is noise), but it changes how many events a
  subscribe produces. Left as a follow-up to decide on its own (Q8).
- **One pull request for everything.** No point at which the two daemons
  can be compared, and no small revert.
- **Switching users to Rust in phase 1.** The comparison has to be seen
  passing in CI before anything installs it.
- **Changing the protocol while porting** (protocol 2, dropping the 500 ms
  minimum, renaming fields). A port that also changes behaviour cannot be
  checked against its original.

## Verification

Commands run while planning, on `origin/main` at `87a14f5`:

- `git rev-parse --short HEAD` in a detached worktree: `87a14f5`.
- `wc -l core/internal/*/*.go core/cmd/*/*.go`: the line counts quoted in
  D3.
- `go build -trimpath -buildvcs=false -ldflags "-s -w -X
  main.version=baseline" ./cmd/haseen-sidecar`: a 3,907,847-byte binary.
- The commands of D5 against that binary: `VmRSS: 11692 kB`, `Threads: 8`
  idle; after 60 s at 3 s with `processes` and `system`, 11 jiffies,
  `VmRSS: 16932 kB`, `Threads: 14`; 21 events in 60 s (one at once, then
  one every 3 s).
- A 118-byte socket path: `failed listen unix …: bind: invalid argument`.
- `grep -n SetWriteDeadline core/internal/server/server.go`: no match.
- `gh pr view 126 --json state`: `OPEN`.
- `cargo --version`, `rustc --version`: 1.99.0. `pacman -Si rust-musl
  rust-aarch64-musl`: both in `extra`.

Phase 1, on the branch `sidecar/rust`:

- `cargo test --locked` (Arch rust 1.99.0): `test result: ok. 56 passed`,
  `test result: ok. 10 passed`.
- `cargo clippy --all-targets -- -D warnings`: no finding.
- `tests/run.sh tests/test-sidecar-rs.sh`: 41/41, every comparison empty.
- D5's table: "Phase 1, as built" above.

## Risks

- **Float and string text.** The largest source of silent drift. Contained
  by the encoder's unit tests and the byte-for-byte parity cases, including
  the exponent range.
- **The arm64 static link is unverified.** `rust-lld` with the musl
  target's self-contained runtime should link a crate with no C code, but
  it was not run. If it fails, the fallback is a release job on a native
  arm64 runner (Q3). Phase 2 must not merge before one arm64 binary has
  answered `-version`.
- **Timing differences in the wipe loop.** Deadlines from `recv_timeout`
  drift differently from Go's ticker under load. The frame count per turn
  is what is checked (`TurnsTheBorderOneDegreeAFrame`), not the instant.
- **The border wipe on a real compositor is not covered by CI.** The fake
  Hyprland covers the protocol; the look is an owner step in phase 2.
- **A stuck client blocks the sampler's send**, in Go and in Rust alike.
  Not changed here.
- **CI time.** `cargo test` plus a release build of a one-dependency crate
  is expected to take under a minute; if the parity test passes two
  minutes, say so in the pull request.
- **Phase 3 can shift a generated theme by one level a channel** for JPEG
  and lossy WebP wallpapers. The `cacheVersion` bump makes that happen once,
  visibly, on the next generation.
- **PR #126** touches `server.go` and adds a Go test. Phase 1 reads the Go
  code, so a late merge means re-reading one function, not a conflict.

## Open questions for the owner

1. ~~**Plan number.**~~ Answered by the coordinator: 167, since the branch
   `network-wifi-qr` already committed a plan 166 (`d030fec`).
2. **Static musl release binaries** (recommended) or glibc?
3. **Where releases are built.** Keep `tools/release-sidecar.sh` as a local
   script (recommended; plan 127's shape), or move to a tag-triggered CI job
   with a native arm64 runner? The second is the fallback if the local
   arm64 link fails.
4. **`libc` as the one dependency.** Accept it, or require zero
   dependencies at the cost of hand-declared `statvfs` layouts?
5. **MSRV.** wootingd declares none. Proposal: set `rust-version` to the
   oldest toolchain the implementer verifies with
   `cargo +<version> build --locked`, and have `tools/build-sidecar.sh`
   fall back to the release binary below it. Or declare none, as wootingd?
6. **Phase 3.** Port the palette (recommended: it is the only way Go leaves
   CI, lint and the release script) or leave it in Go? Leaving it is
   defensible: it is a one-shot tool with no resident cost, about three
   thousand lines of colour arithmetic, and the port brings decoder crates
   and a possible one-level colour shift. If it stays, phases 1 and 2 still
   stand and the toolchain count stays at two.
7. **Accepted wire differences.** Two are left after phase 1 (the other two
   were removed, "Phase 1, as built"): idle exit up to 1 s sooner, and with
   two subscribers naming two different GPU cards the later client wins
   where Go's choice is unordered. One is new: a request nested deeper than
   100 levels is `bad json`. All three fine?
8. **Coalescing** the samples of subscribes that arrive within a few
   milliseconds: keep Go's behaviour for good (one event each), or allow a
   follow-up plan to change it?
9. **The 500 ms minimum interval** stays for compatibility, below §6's 2 s
   floor for shell Timers. Keep, or raise it in a later plan?
10. **Ordering against PR #126.** Wait for it to merge before phase 1
    starts, or start now and port its test afterwards (recommended)?
