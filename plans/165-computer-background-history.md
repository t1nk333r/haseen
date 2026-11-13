# Plan 165: Your computer keeps its history in the background

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One always-on service that only remembers: it adds the
  `system` readings to the sidecar sample the bar widget already asks for
  every 3 s, and holds at most 31 samples per graph. A one-line lock in the
  sidecar serialises samples that could already overlap.
- **Depends on**: 032 (haseen-sidecar), 075 (appending a default service to
  a user's own list), 162 (the Your computer panel)
- **Category**: shell, sidecar
- **Planned at**: 2026-11-13, from the owner
- **State**: DONE 2026-11-13 (`tests/test-computer.sh` 79/79; `go test
  -race ./internal/server/` ok; the panel in the owner's session on luna is
  an owner step).

## Problem

The owner, 2026-11-13, after plan 162 shipped: "when i open the 'your
computer' it starts a new session it should be working passively in the
background". Plan 162 built the panel to sample only while open: the panel
subscribed to the `sysusage` stream when it was created and its histories
were properties of the panel, which the host destroys on close (the panel is a
LazyLoader, `share/haseen/shell/shell.qml:255-268`). Each open therefore began
with an empty graph that took 90 s to fill, the "new session" the owner saw.
The owner's message is the approval for a background part, on by default
(owner, 2026-11-13), recorded in `AGENTS.md`'s defaults list.

An audit of plans 161-163 on 2026-11-13 also found that each panel open and
close made haseen-sidecar take an extra sample at once, beside its ticker,
and that two samples at the same moment crash the daemon (below).

## Approach

1. **A service keeps the histories.** `haseen.computer` gains a `service`
   entry, `Service.qml`, that answers the role `computer` (`provides` in
   `manifest.json`). It holds `cpuHistory`, `memHistory` and `tempHistory`,
   records every new `sysusage` frame with `Computer.push`, and keeps one
   `Sidecar.want` for the life of the shell: every 3 s, `gpu: "off"`,
   `system: true`, the parameters plan 162's panel used.
2. **The panel draws the service's history.** `Panel.qml` finds the service
   through `Plugins.roles.computer`, as the weather and prayers panels find
   theirs, and binds its three histories to it. With the service present it
   makes no subscription of its own. Without it (a user's own `services`
   list that the migration did not reach, or a test hosting the panel alone)
   it falls back to plan 162's behaviour: its own subscription while shown
   and a history that starts when it opens.
3. **On by default.** `share/haseen/default/shell.json` lists
   `haseen.computer` last in `services`. Migration
   `1794530533-computer-service.sh` appends it to a user's own `services`
   array, the way plan 163's migration appended `haseen.stage` (and plan
   075's `haseen.battery`). `plugins."haseen.computer".enabled: false`
   still turns the panel and the service off (`Config.isEnabled`, used by
   `Plugins.serviceIds`, `share/haseen/shell/Haseen/Plugins.qml:86-87`).
4. **A clock that steps back.** `Computer.push` now also drops samples
   stamped after the new one. A history that lives for the whole session
   would otherwise keep an hour of "future" samples after the clock stepped
   back an hour, all drawn at the right edge (the audit's probe kept 41
   samples, the first ten at x = 300 of 300).
5. **The sidecar samples one at a time.** `Server.sampleOnce`
   (`core/internal/server/server.go`) ran `Sampler.Sample` without a lock,
   from the ticker and from every subscribe (`go s.sampleOnce()`). The
   sampler keeps its previous counters in plain maps, so two samples at the
   same moment wrote them from two goroutines. A new `sampleMu` is held
   through the sample and the sends, so clients also get samples in the
   order they were taken.

## Cost

- **Sidecar.** The bar's haseen.sysusage widget already holds a 3 s
  subscription (`share/haseen/shell/plugins/haseen.sysusage/Sampler.qml:19`),
  and Sidecar merges consumers into one subscribe, the shortest interval and
  `system` when anyone asks (`share/haseen/shell/Haseen/Sidecar.qml:98-124`).
  So the service adds no sample, only the `system` readings (temperature,
  clock, network, disks) to the existing one. A benchmark on luna
  (`Sampler.Sample` against the live `/proc`, `go test -bench`, 2 s each)
  measured 30 486 ns per sample without `system` and 203 682 ns with it:
  about 0.17 ms more every 3 s, 0.006 % of one core. Where the bar widget is
  off, the service is the one subscriber and keeps the daemon running.
- **Shell.** Three arrays of at most 31 `{t, v}` objects each (90 s at 3 s,
  bounded by time in `Computer.push`), and one handler per sample. No Timer,
  no file read and no process in the service.
- **Panel.** Unchanged when open, minus its own subscription.

## Rejected

- **Keep the history in the panel and keep the panel alive.** Panels are
  LazyLoaders (architecture 6); keeping one loaded keeps its whole tree,
  Shapes included, for a few hundred bytes of numbers.
- **Have the sidecar keep the history.** It would need a new stream or
  request and a history per consumer setting; the shell already has the
  frames, and plan 162's arithmetic stays where its tests are.
- **Sample faster or longer while closed.** The owner asked for the panel to
  be ready, not for more data; the 90 s at 3 s the panel draws is all that is
  kept.

## Verification

- `tests/test-computer.sh` 79/79, run hermetically from a short bind
  mount. It runs the service with the panel closed (29 samples on a fake
  clock and a live frame: one consumer, 30 samples, no panel), opens the panel
  (30 samples drawn at once, still one consumer, `panel.service` is the
  service), and closes it (one consumer, 30 samples kept). Mutating the
  panel's service lookup to `return null` fails two of those checks (77/79).
  It also checks the migration (appended, re-run no-op, a user's own off
  kept, no own list or no shell.json left alone) and the clock-back case.
- `core/internal/server/server_test.go`: eight goroutines take 200 samples
  each against a fixture `/proc` with `system` on. Without `sampleMu` a plain
  `go test` dies with `fatal error: concurrent map iteration and map write`;
  with it, `go test -race` passes.
