# Plan 069: the border wipe, native and in haseen-sidecar

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (the theme writes only its own border config. The loop writes the border gradient through Hyprland's socket and nothing else, only while the shell subscribes)
- **Depends on**: 032 062 066
- **Category**: theme, sidecar, resources
- **Planned at**: 2026-10-07, owner decision on io: "both: the native Hyprland loop is the default; port the Python loop into the Go sidecar as a fallback". Amended the same day: the theme's declared pace decides. 36 s, the owner's pace, is the sidecar's; native only up to 10 s.
- **State**: DONE 2026-10-07 (Go unit tests with a fake Hyprland; sidecar and theme shell tests; nested-session frames for both paths; the switch on io is an integrator step)

## Problem

The `haseen` theme (plan 066) has a gradient active border. Its
`hyprland.lua` header said that Hyprland's `borderangle` animation turns it.
Nothing defined that animation, though, and Hyprland 0.56.2 ships the leaf
disabled: in a bare nested session `hyprctl -j animations` gave
`{"name":"borderangle","overridden":true,"bezier":"default","enabled":false,"speed":1.00,"style":""}`.
So the border stood still, and the faded stop stayed parked in one place.
On luna the owner runs a Python loop instead (`hypr-border-wipe.py` with a user
service). Every ~0.1 s it sends
`eval hl.config({general={col={active_border={colors=…, angle=N}}}, group=…})`
to `$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock`, one degree a frame, about 36 s a
turn.

Four facts found in a nested Hyprland 0.56.2:

- **Hyprland caps the speed.** `speed = 360` (36 s) is refused with
  `hl.animation("borderangle"): field "speed": value 360 is more than the maximum of 100.00`
  (`hyprctl configerrors`). Natively, 10 s a turn is as slow as it goes.
- **The speed is in deciseconds per turn.** At `speed = 100`, frames taken
  2.5 s apart moved a quarter turn each, and the frames at 0 s and 10 s were
  byte-identical (md5 prefix 4000f3672f70 for both).
- **`borderangle` is not under `border`.** It sits under `global`, beside
  `border`. looknfeel.lua's `hl.animation({ leaf = "border", enabled = false })`
  leaves it running. `linear` is a built-in curve: the bare session lists
  `{"name":"linear","X0":0.00,"Y0":0.00,"X1":1.00,"Y1":1.00}`. So the theme
  does not define one.
- **The native loop starts when a window maps.** After a reload into the
  10 s pace, the already-open window stayed still: the dim stop sat at the same
  place in three frames. A window opened after it turned. Toggling
  `animations:enabled` off and on did not stop a running loop.

## Change

**The declaration.** The theme's `colors.toml` holds both the gradient and the
pace, so the two paths cannot disagree:

```toml
border_wipe = "rgba(F25623ff) rgba(F25623cc) rgba(F2562311) rgba(F25623cc)"
border_wipe_seconds = 36
```

**Native** (`share/haseen/themes/haseen/hyprland.lua`). The theme reads the two
keys from the `colors.toml` beside it, found through `debug.getinfo`, with
`haseen.paths.state_home` as the fallback. Up to 10 s a turn it calls
`hl.animation({ leaf = "borderangle", enabled = true, speed = seconds * 10, bezier = "linear", style = "loop" })`.
Slower than that it calls `hl.animation({ leaf = "borderangle", enabled = false })`.
Both borders take the declared stops. Without a `colors.toml` the border is
the accent and does not turn.

**Fallback** (`core/internal/borderwipe`, stream `borderwipe` in
haseen-sidecar). This is a port of the Python loop:

- Each frame is one `eval hl.config(...)` on the request socket: connect,
  send, receive, close. It uses raw syscalls, one reused address, one reused
  request buffer and one reused reply buffer. `TestFrameIsTheEvalTheLoopOnLunaSent`
  asserts 0 allocations per frame. No process is started.
- The pace is whole frames of at least 100 ms, at most one per degree. 36 s
  is 360 frames of 1° every 100 ms. 10 s is 100 frames of 3.6°. Each frame's
  angle is computed from its number, so the turn never drifts.
- The colours come from `colors.toml`. They go into Lua source, so only
  `rgba(RRGGBBAA)`, `rgb(RRGGBB)` and `0xAARRGGBB` are accepted.
- It runs only when the theme asks and `hyprctl -j animations` shows
  `borderangle` enabled with a `loop` style. A leaf that is not overridden
  takes `global`'s settings. A build without the leaf has no native path.
  When the leaf loops, the loop stands aside (`native`), so the two never run
  together.
- It pauses (`paused`) in the `game` context (`flags/context`), when
  `animations:enabled` is false, or when no window has focus. The first two
  are re-read every 2 s while the loop is the sidecar's. Focus and
  `configreloaded` come from the event socket `.socket2.sock`. Pausing sends
  nothing, and resuming continues from the angle where it stopped.
- When Hyprland stops answering, the state is `waiting`. It retries every 2 s
  and resumes when the socket comes back. The shell subscribes with its own
  `HYPRLAND_INSTANCE_SIGNATURE`, and the latest subscriber's instance wins, so
  a shell started after a Hyprland restart points the loop at the new
  instance. Unlike the Python loop, it never guesses the newest
  `hypr/*/.socket.sock`: on io that could be a nested test session.
- After a `configreloaded`, it re-reads everything. A reload can hand the
  border back after frames went out: the new theme asks for no wipe, or
  borderangle now turns it. In that case the loop asks for one more `reload`,
  so a frame that landed after the first reload cannot keep the old theme's
  gradient. That second reload finds nothing sent and stops there
  (`TestReloadHandsTheBorderBack`). One gap is left. `haseen theme set`
  swaps the files and then reloads, and the shell's watch drops the
  subscription when the file changes. If the drop reaches the daemon after
  the reload but before the reload's event, the extra reload is not sent, and
  a frame that landed in that window keeps the old gradient until the next
  reload. When the drop comes first, as it did in the nested proof, frames
  stop before the reload.

**Lifetime.** `qs.Haseen.BorderWipe` (`share/haseen/shell/Haseen/BorderWipe.qml`)
watches `current/theme/colors.toml`. While the file has `border_wipe`, it holds
`Sidecar.want("border-wipe", "borderwipe", { signature })`. `shell.qml` reads
`BorderWipe.wanted`, which creates the singleton. The daemon is therefore not
started for a theme that asks for nothing. It runs the loop only while a
client subscribes, and when the shell goes, the loop goes. `Sidecar._sync`
merges params per stream, so `borderwipe` passes its own through.

Memory: on the default theme the subscription keeps haseen-sidecar running
for the whole session, at 12 MiB RSS. The default bar's sysusage widget
(on by default) already keeps it running, so the default setup gains no idle
memory. Without that widget, the wipe theme adds those 12 MiB.

**Status.** The daemon sends `borderwipe` events with `{state, reason, secondsPerTurn}`
when the state changes, and once to each new subscriber. `status` answers
with the angle and the frame count as well. `haseen sidecar status` prints
`border wipe:  running, 36 s a turn, angle 183, 184 frames`.

**luna.** `~/.local/bin/hypr-border-wipe` and its user service become
redundant once luna runs this: the shell's subscription does what they did.
The owner removes them. Running both would push two angles.

## Rejected

- **Native at 36 s.** Hyprland refuses a speed above 100. A slower bezier
  cannot help either: the loop is one turn per `speed` ds, whatever the curve.
- **Native at 10 s as the default.** The owner's reference is the 36 s he
  lives with. The 10 s native path stays one key away
  (`border_wipe_seconds = 10`), with the CPU numbers below to choose by.
- **Colours from the live config** (`getoption general:col.active_border`).
  After a theme switch, a late frame can leave the old colours in the live
  config. The loop would then read those back and keep turning the wrong
  gradient. `colors.toml` is the theme's own record.
- **A colour list only in `hyprland.lua`.** The sidecar cannot read Lua
  values, and `hyprctl eval` answers only `ok` or an error. Two copies would
  drift, so the theme reads `colors.toml` instead.
- **The daemon deciding alone, with the shell always subscribed.** That would
  keep haseen-sidecar alive for every theme. The shell subscribes only when
  `border_wipe` is declared.
- **Polling focus.** The event socket is free while idle. Polling every 2 s
  would also make resuming up to 2 s late.

## Tests

- `core/internal/borderwipe` (`go test ./...`):
  - the pace and angle sequence for 36, 10, 1 and 72 s;
  - the exact eval string from the colours, with zero allocations per frame;
  - `colors.toml` parsing and the refusal of code;
  - `NativeLoop` on Hyprland 0.56.2's JSON (loop, off, inherited, missing);
  - `getoption` and `activewindow` answers.

  Against a fake Hyprland, with unix request and event sockets that answer
  one request per connection:
  - it never runs beside a native loop;
  - one degree a frame with the theme's colours;
  - pause and resume for the game context, animations off and focus lost,
    each continuing the angle;
  - reconnection after the socket files vanish and come back;
  - the hand-back reload, sent once;
  - off without a subscriber.
- `tests/test-sidecar.sh` (39 checks): the build announces
  `sysusage borderwipe`. Over a real socket, with no Hyprland and
  `HYPRLAND_INSTANCE_SIGNATURE` unset, it covers:
  - `off (nobody subscribed)`;
  - a subscriber on the haseen theme sees `waiting`, 36 s a turn, no frames;
  - `haseen sidecar status` shows the same, then `off` once the subscriber
    leaves;
  - a theme without `border_wipe` gives `off (the theme asks for no wipe)`;
  - `status` over the protocol.
- `tests/test-theme-haseen.sh` (75 checks) runs the installed `hyprland.lua`
  under Lua with a recording `hl`:
  - at 36 s, borderangle is off and both borders take the `colors.toml` stops;
  - 10 s gives speed 100, loop;
  - 4 s gives speed 40;
  - no declaration gives the accent, still.

  `Hyprland --verify-config` accepts the theme at 36 s and at 10 s.

## Verification (nested Hyprland 0.56.2, headless output IO 1536×864@60)

The nested config was looknfeel.lua plus the theme, with `current/theme`
pointed at a scratch copy. The dim stop's position on the border ring was
measured as a clockwise polar angle from the window centre, in screen
coordinates.

- **Native, `border_wipe_seconds = 10`.** Frames 2.5 s apart:
  - dim stop at 292.5°, 352.5°, 112.5°, 172.5°, 292.5°, 352.5°: it increases,
    so the turn is clockwise;
  - frames 0 and 4 (10 s apart) are identical, md5 prefix 4000f3672f70.
- **Without a loop, `border_wipe_seconds = 36` and no sidecar.** Two frames
  2.5 s apart are byte-identical (md5 prefix 7cc8ec9fdf16): the border stands still.
- **Sidecar, 36 s.** `running, secondsPerTurn 36`. Frames 2.5 s apart all
  differ, and `status` read angle 75, 102, 129, 156, 183 at frames 76, 103,
  130, 157, 184: 27 frames and 27° per 2.7 s. Pausing, in the same session:
  - `game` in the flag gives `paused game context`, with the frame count held
    at 283;
  - removing the flag gives `running`;
  - `animations = { enabled = false }` gives `paused animations are off`;
  - focusing an empty workspace gives `paused no window has focus`;
  - each one resumes.
- **Forced fallback.** The theme at 10 s plus
  `hl.animation({ leaf = "borderangle", enabled = false })` after it. The
  sidecar went from `native` to `running, 10 s a turn`: angle 57.6, 162,
  255.6, 349.2, 86.4 at 2.6 s steps (3.6° a frame), and every frame differed.
- **Shell end to end.** `qs` ran the repo's shell tree in the nest, with only
  `shell.qml` cut down to `BorderWipe.wanted` and a logger. The singleton
  read `wanted: true`, started the daemon, subscribed, and got
  `{"state":"running","secondsPerTurn":36,…}`. Rewriting `colors.toml`
  without `border_wipe` and reloading gave `wanted: false`, and the daemon
  answered `off (nobody subscribed)` at frame 57.

CPU over 30 s, from `/proc/PID/stat` utime+stime at 100 ticks/s (Iris Xe):

| path | haseen-sidecar | nested Hyprland |
|---|---|---|
| sidecar loop, 36 s, 10 frames/s | 8 ticks = 0.27 % of a core | 50 ticks = 1.67 % |
| sidecar paused (game context) | 2 ticks = 0.07 % | 1 tick = 0.03 % |
| native borderangle loop, 10 s | 0 (standing aside) | 207 ticks = 6.90 % |

The native loop redraws at the output's refresh rate (60 Hz here). The sidecar
redraws at 10 frames a second. haseen-sidecar's RSS was 12 MiB.

## Live apply (integrator, io)

1. `./install.sh` from the worktree builds the new haseen-sidecar into
   `share/haseen/sidecar/` (`tools/build-sidecar.sh`).
2. `haseen sidecar stop`, so the shell starts the new binary on demand.
   `haseen shell restart` then loads `BorderWipe.qml`.
3. `haseen theme set haseen` re-renders `current/theme` with the two new keys
   and the new `hyprland.lua`, and reloads Hyprland.
4. Check: `haseen sidecar status` shows `border wipe:  running, 36 s a turn, …`.
   The angle advances between two runs, and the border turns clockwise.
5. To try native instead: set `border_wipe_seconds = 10` in
   `~/.local/state/haseen/current/theme/colors.toml` (or in a user copy of
   the theme), then run `hyprctl reload` and reopen the windows. The status
   then reads `native`.
