# Plan 199: the sidecar, wootingd and recorder findings of the 2026-11-24 audit

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Each fix is local to one command, daemon or panel. The
  sidecar now reports -1 for one tick after a gap where it reported an
  average over the gap, and the recorder pid files gain a second line.
- **Depends on**: 032 (sidecar), 069 (border wipe), 098 (haseen.syncthing),
  099 (haseen.wooting and wootingd), 150 (recording clock), 153 (wooting
  profile settings), 167 (the Rust sidecar)
- **Category**: core
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/run.sh --affected 9a9e82ab`: 19 files,
  2736/2736 after the review round below, which also fixed the border wipe
  golden transcript's flaky grouping; reviewed: one Sonnet round, APPROVE
  with two nits)

The audit ran at `2f7f472a`. Every finding was re-checked on `9a9e82ab`
(main with plans 182-184) before it was fixed; every one still applied, at
the same lines. Line numbers below are at `9a9e82ab`.

## 1. nvidia-smi kept polling after the last sysusage subscriber left

**Evidence.** `nvidia-smi ... -l 3` is started by `nvidia_value`
(`core/sidecar/src/sysusage/nvidia.rs:19-27`) and stopped only from
`gpu_sample` (`gpu.rs:215,219,256`), which only `Sampler::sample` calls.
When the last client unsubscribes or hangs up, the server sends
`Reschedule`; `schedule()` returns None and the sampler thread waits in
`rx.recv()` (`server.rs:226-243`), and `sample_once` returns before
sampling anyway (`server.rs:499`). The child went on polling the GPU (and
kept a hybrid laptop's dGPU awake) until the daemon exited, which the
shell's open connection prevents. That breaks `docs/architecture.md:589`:
the daemon "runs a stream only while some client subscribes to it".

**Fix.** A new `Sampler::idle()` stops nvidia-smi (and forgets the
baselines, section 3). The sampler thread calls it whenever its next
deadline is None, that is whenever no client is subscribed
(`server.rs`, after the `match msg`).

**Test.** `core/sidecar/tests/protocol.rs`
`nvidia_smi_stops_with_the_last_subscriber`: a fixture root with an nvidia
boot VGA card and a fake `nvidia-smi` on the daemon's PATH that writes its
pid. Subscribing starts it; unsubscribing must stop it; subscribing again
starts a second one, and hanging up stops that. On `9a9e82ab` it fails:
"timed out waiting for nvidia-smi to stop after unsubscribe". The protocol
count in `tests/test-sidecar.sh` goes from 10 to 11.

**Rejected.** Stopping nvidia-smi inside `sample_once`'s early return: that
return is only reached by a timer or `Now`, and neither fires once nobody is
subscribed. A stop on every unsubscribe in the server thread: the sampler
is owned by its thread, and two owners is what the Go daemon's crash (pull
request #126) came from.

## 2. `haseen sidecar` without socat: stale sockets read as running, stop failed

**Evidence.** `bin/haseen-sidecar:40-44` returned success whenever the
socket file existed and socat was missing, so `status` printed "(running)"
for the socket a SIGKILLed or aborted daemon leaves (panic = abort), and
`wipe_status` returned silently (`:48`). `stop` passed that check and died
in `require_cmds socat` (`:100`). Only the vapt layer lists socat:
`grep -rln socat share/haseen/layers` matches only
`layers/vapt/packages/...`.

**Fix.** `socket_state` answers running, not running or unknown. With socat
it connects, as before. Without socat it asks `ss -xlnpH src SOCKET`, which
lists a socket only while something listens on it; `ss` is iproute2, which
Arch's `base` depends on (`pacman -Qi base`). Status prints the state, and a
running daemon's border wipe line says "unknown (asking the daemon needs
socat and jq)" instead of disappearing. `stop` without socat sends SIGTERM
to the pid `ss -p` names; the daemon removes its socket on SIGTERM
(`protocol.rs` `sigterm_removes_the_socket`). `start` treats only
"running" as running: a second daemon steps aside on its own.

**Test.** `tests/test-sidecar.sh`, "the CLI without socat": a PATH of
`/usr/bin` without socat. A live daemon is "(running)" with the unknown wipe
line; after `kill -9` its socket file stays and reads "(not running)", with
and without socat; `stop` on it says "not running"; `stop --dry-run` asks
nothing; `stop` ends a live daemon and its socket goes. On `9a9e82ab` the
stale socket read "(running)" and `stop` exited 1 (the base run below).

**Rejected.** Adding socat to the base layer: a new default package needs
the owner. A `-call` client mode in the daemon: an installed binary fetched
from an older `sidecar-v*` release would not have it, so the CLI would need
the fallback anyway. python3: not guaranteed on a default install.

## 3. The first sample after a gap averaged over the whole gap

**Evidence.** `prev_proc`/`prev_proc_at`, the rc6 baseline and `prev_cpu`
were kept while nobody asked for them (`sysusage/mod.rs:115-127`; only
`sys.net` was reset, at `:125`, with a comment saying why). The panel's
first process list after reopening divided each task's jiffies by the time
since the last list (`mod.rs:232-234,267`); the rc6 busy share likewise
(`gpu.rs:224-237`), and the CPU share after a time with no subscriber.

**Fix.** A sample that does not ask for processes clears the process
baseline; a sample whose chosen card is not rc6 (or no card) clears the rc6
baseline; `idle()` clears all of them, the CPU's included. The first sample
after a gap is then -1 or an empty list, as the very first one is.

**Test.** Unit tests `processes_forget_a_gap`,
`gpu_sample_residency_forgets_a_gap` and `idle_forgets_the_cpu_baseline`;
the first two (without their `idle()` part, which does not exist there)
fail on `9a9e82ab`: "the first list after the gap has nothing to compare
with" and "after the gap". The unit count in `tests/test-sidecar.sh` goes
from 57 to 60. The golden transcripts recorded from the Go daemon still
match, and `docs/architecture.md` lists this among the Rust daemon's
differences.

**Rejected.** Keeping the baseline and showing nothing until a second
sample: the panel would still show the averaged list for one tick.

## 4. `haseen wooting status` printed a slot "of" a count

**Evidence.** `bin/haseen-wooting:160-161` printed `.active` (a slot number)
"of" `.count` (how many profiles are stored). Slots are not 0..count-1
(`core/wootingd/src/main.rs:54-57`), so profiles in slots 0 and 3 with 3
active printed "3 of 2".

**Fix.** The line is the slot and the active profile's place among the
stored ones: `active slot:    3 (profile 2 of 2)`.

**Test.** `tests/test-wooting.sh` starts the fake daemon with `--active 3`
(slots 0 and 3) and expects that line; the two contiguous cases now read
"0 (profile 1 of 1)" and "0 (profile 1 of 4)". On `9a9e82ab` the new
check fails (it printed "3 of 2").

**Rejected.** Dropping the count: it is how status says how many profiles
the keyboard holds, and the per-slot list follows anyway.

## 5. The doctor's hint pointed at the wrong checks

**Evidence.** Every `head_line` runs unconditionally and numbers itself
(`bin/haseen-wooting-doctor:77-79`): 4 is the unit, 5 the command
interface, 6 access, 7 the conflicting owner. A daemon reporting no
keyboard hinted "see checks 4-6 above" (`:296`), leaving out 7, the usual
cause. The section comments still had the old numbers.

**Fix.** The hint is built from the step counter, saved after the command
interface and the conflicting owner headings ("see checks 5-7 above"), and
the section comments lost their numbers.

**Test.** `tests/test-wooting.sh`, "the hint names those checks", with the
fake daemon's `--absent`; on `9a9e82ab` it printed "4-6".

## 6. wootingd could pair two keyboards' interfaces

**Evidence.** `find()` and `find_analog()` each took the first node with
the wanted usage page in bytewise path order (`core/wootingd/src/device.rs:132,186-213`),
so hidraw10 came before hidraw9 and, with two boards attached, the command
side could bind to one board and the analog stream (`analog.rs:153`) to the
other.

**Fix.** Each node keeps its USB device, from `HID_PHYS` without the
`/inputN` suffix (`usb-0000:00:14.0-2/input2` is `usb-0000:00:14.0-2`), the
same for every interface of one keyboard. `find_analog` takes the analog
node of the keyboard `find` picks, and only without a command interface any
analog node. A node without `HID_PHYS` matches another without it, as all
nodes did before.

**Test.** Unit test `pairs_the_analog_stream_with_the_command_interface`:
two boards numbered 9-12; the command interface is hidraw11 and the analog
stream must be hidraw12, and nothing once that node is gone. On `9a9e82ab`
it got hidraw10. The count in `tests/test-wootingd.sh` goes from 57 to 58.

**Rejected.** Matching `HID_UNIQ`: a board may report an empty or shared
serial. Resolving the canonical `device` link's USB parent: fixture trees
have plain directories there, and `HID_PHYS` names the same thing.

## 7. A refused profile switch from the panel was never shown

**Evidence.** `Panel.qml:35-43` closed the panel as soon as `profile set`
was written. Closing frees the panel's connection (`shell.qml`'s
LazyLoader), and wootingd sends a refusal only to the connection that asked
(`core/wootingd/src/main.rs:820-833`; it broadcasts only on success), so
the error Text at `Panel.qml:118-125` could never show a refused switch.

**Fix.** The panel remembers the slot it asked for and closes when
wootingd confirms it (`{"ok":true,"active":N}`); on `{"ok":false,...}` it
stays open and shows the daemon's words. `Model.switchOutcome` decides,
so the rule is tested in `model.test.js`. A dropped connection clears the
pending slot.

**Test.** `model.test.js` (six cases; the suite count goes from 284 to 290)
and the engine scenario in `tests/test-wooting.sh`: after the confirmed
switch nothing is pending, and `choose(9)` stays pending until the fake
daemon refuses it, then shows "slot 9 out of range ..." with the active
slot unchanged.

**Rejected.** Having wootingd broadcast failures: every client would see
another client's refusal, and the bar has nowhere to show one.

## 8. The recorder toggles trusted a reused supervisor PID

**Evidence.** `active()` was `alive "$(cat pid)"`
(`bin/haseen-capture-screenrecord:62-69`, `bin/haseen-capture-audiorecord:53-60`).
After a SIGKILLed supervisor, a later process of the same user with that
PID made the toggle `stop_recording` and `kill -TERM` it
(`screenrecord:137`).

**Fix.** The supervisor and the recorder each record their PID and their
start time (field 22 of `/proc/PID/stat`) on two lines; `recorded FILE`
names the PID only while the process with that start time runs. A one-line
file from before this plan has the supervisor's command line checked for
`--supervise` instead. Otherwise the files are stale, `clear_stale` removes
them, and the toggle starts a recording.

**Test.** `tests/test-trigger.sh` (screen) and
`tests/test-capture-toolbar.sh` (sound): the pid file names a `sleep 30`
started by the test, with a wrong start time, and for the screen recorder
also as a one-line file. `--stop` must report the stale flag cleared and
exit 1, and the `sleep` must still run. On `9a9e82ab` the one-line case
SIGTERMed it. The tests' own reads of the pid files take the first line.

**Rejected.** Checking the command line alone: a PID can go to another
instance of the same script. Comparing the process start with the pid
file's modification time: that needs the boot time, which suspend and clock
changes make unreliable.

## 9. Syncthing peer strings read as `--dry-run` or `-h`

**Evidence.** `bin/haseen-syncthing:240` passed its whole argv to
`parse_common_flags` (`share/haseen/lib/common.sh:522`), which takes
`--dry-run`, `--yes`/`-y` and `-h`/`--help` wherever they appear. The panel
passed a peer's folder label and device name as arguments
(`Service.qml:101,114`), so a label "--dry-run" made the accept a dry run
and a name "-h" printed the usage; both exited 0, and the panel showed
"Folder accepted" or "Device added".

**Fix.** `haseen syncthing` stops reading options at `--` and passes
everything after it on unchanged; the panel puts `--` after the verb of
`accept-device` and `accept-folder`. The usage says so.

**Test.** `tests/test-syncthing.sh`: `accept-folder -- newfolder PEER
/srv/sync/x --dry-run` posts the folder with the label `--dry-run`, and
`accept-device -- ID -h` posts the device named `-h`; two greps check the
panel passes `--`. On `9a9e82ab` both fail (`--` was taken as the folder
id, exit 64).

**Rejected.** Teaching `parse_common_flags` itself to stop at `--`: it is
global (it would run the whole suite), 207 commands call it, and two of
them (`haseen-ai-chat`, `haseen-mobile-mirror`) read a `--` from `REST`
themselves; the same issue there is left for a separate change.

## Gates

`tools/lint.sh` (lint OK), `tests/run.sh --affected 9a9e82ab` (above),
`tools/check-docs.sh` (OK). Each new check was also run against
`9a9e82ab`'s code in a detached worktree, where every one of them failed:
the protocol test timed out waiting for nvidia-smi to stop, the two gap
unit tests and the pairing test failed their assertions, and the shell
tests failed 26 checks across `test-sidecar`, `test-syncthing`,
`test-trigger`, `test-capture-toolbar` and `test-wooting`.

## Review

One round, by an independent Sonnet reviewer: APPROVE, with two nits.

1. *The status line said review pending and recorded one failure in the
   border wipe golden transcript that the reviewer could not reproduce
   (`tests/test-sidecar.sh` passed 77/77 for them); is that transcript
   flaky?* It is, and the cause is the harness, not this plan's code. A
   border wipe subscribe queues an announce for the wipe's own thread
   (`core/sidecar/src/server.rs:393`, `borderwipe/mod.rs:182-183`) and then
   sends its reply from the connection's thread (`server.rs:434`). Under
   load the wipe thread can send both events before the reply goes out.
   `tools/sidecar-play.py` stopped the subscribe's group after two events,
   so the late reply opened the next group, which stops at the first reply
   it sees; the status reply then fell into the group after, where sorting
   put it after the next subscribe's events. That is the reorder the
   affected run showed. **Fixed:** a wait can name a second frame type
   (`"and": "reply"`) and reads until it has seen that too; the three
   border wipe subscribes in `wipe.script` use it. The golden output is
   unchanged, since in it every subscribe's reply already sat with its
   events. A new check in `tests/test-sidecar.sh` ("a late reply stays with
   its subscribe's events") plays that script shape against a fake socket
   that sends the reply 300 ms after both events; the base harness prints
   the status reply after the next event and fails it. The status line
   above now records this review and the final run.
2. *Without socat, `stop` takes the pid from `ss -p`; if `ss` lists no pid,
   `stop` dies and leaves the daemon running. Fall back to `pgrep -f`?*
   **Not taken.** The socket sits under `XDG_RUNTIME_DIR` (`bin/haseen-sidecar:14`;
   systemd makes it 0700 and per user), so its listener is the user's own process,
   and `ss -p` names the pid of every socket the caller's processes hold.
   `ss` can omit it only for another user's process or one in another pid
   namespace, and SIGTERM could not reach either. A `pgrep -f` fallback
   would match by binary, not by socket, and could stop a daemon serving a
   different socket (a test's `-socket`, a second session's). `stop` then
   says "no process listens on" the socket, which is true from the caller's
   view.
