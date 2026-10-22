# Plan 105: Workspaces, the console and new binds from Omarchy 4.5

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MEDIUM. Per-monitor workspaces change what SUPER + 1..0 reach,
  so they ship off and change nothing until the owner turns them on. The
  console, the floating step and the four new keys are new behaviour on keys
  that were free; the floating mode subscribes to Hyprland events only while
  a workspace floats. All Hyprland code runs in the compositor's Lua, which
  no test here can drive live: it is proven against models of the `hl` calls
  it makes, not against a running Hyprland (Not verified, below).
- **Depends on**: 003 (Hyprland Lua defaults), 018 (the toggles), 021 (the
  haseen.workspaces widget), 030 and 071 (the keybind sheet), 043 (the
  owner's keys), 045 (the settings index), 100 (affected tests), 102
  (Omarchy's workspace-layout and full-screen answers), 103 (`binds.lua`'s
  SUPER + C/V), 107 (`haseen capture screenshot` hands captures to Omasnap)
- **Category**: desktop, keybinds, shell
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; a live Hyprland session and a
  monitor hot-plug are owner steps)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose,
verbatim:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs
  stay as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts", "1-second
  boot menu", "New binds".

Earlier standing decisions: adopt all Omarchy commands except Apple-hardware
ones (plan 093); a new built-in plugin or optional behaviour is off by default
unless the owner approved it on; no dock, titlebars, video wallpapers, theme
intros or blur.

This plan is **"Per-monitor workspaces"**, **"Floating layout step"**,
**"Quake console"** and **"New binds"**: survey Part B.2 rows 8, 14, 23, 24
and 30, with Part C item 11's window-to-monitor keys.

### The console's dim and slide (owner, 2026-10-22)

The first version set the console's dim and slide at load, which Hyprland
applies to every special workspace, so SUPER + S's scratchpad and the
screensaver's workspaces dimmed and slid too. The review raised it, and the
owner was asked "Console only / Everywhere, like Omarchy / No dim or slide"
and chose, as relayed by the coordinator, **"Console only"**: haseen switches
the dim and slide on when the console opens and back off when it closes, so
the scratchpad and screensaver look exactly as they do on main.

## Sources

The survey (Part B.2 rows 8, 14, 23, 24, 30; Part C items 5, 6, 11) and its
notes in `~/.cache/haseen-wt/omarchy45-notes/` pointed at the code. Every fact
used here was re-read in a read-only clone of `github.com/basecamp/omarchy`
(deleted afterwards): `v4.5.0-rc1` = 03ff1eff3, `quattro` at c39fd2afd
(`git describe --tags`: `v4.5.0-rc1-33-gc39fd2afd`), and the commits named
below. Omarchy is MIT (Copyright (c) David Heinemeier Hansson); every adapted
file keeps the notice in its header and `NOTICE.md` has the rows. No Omarchy
file, commit message or manual asked the reader to run, install, fetch or
send anything.

- **Per-monitor workspaces**: `default/hypr/monitor-workspaces.lua@v4.5.0-rc1`
  (701 lines; f2bd3cef6 "Give each monitor its own workspaces (#15655)" and
  f61be3fd4 "Keep per-monitor workspaces on the right monitor after unplugs";
  the file is the same at `quattro`: `git log v4.5.0-rc1..quattro --
  default/hypr/monitor-workspaces.lua` is empty). Read whole: blocks of ten
  keyed by make, model and serial with the laptop panel first (`:147-172`), the
  state file `block<TAB>connector<TAB>identity` (`:110-145`), the merge file
  (`:62-101`), `reconcile` on `hyprland.start`, `config.reloaded`,
  `monitor.added`, `monitor.removed` (`:524-697`), the bind actions
  `o.workspaces.focus/move_window/move_to_monitor/move_window_to_monitor`
  with replay expressions on `o.bind_expressions` (`:417-522`). Its binds:
  `default/hypr/bindings/tiling.lua@v4.5.0-rc1:22-48` (Super + 1..0, Super +
  Shift + 1..0 follows and Super + Shift + Alt + 1..0 is silent, the reverse
  of the owner's; Super + Shift + Ctrl + arrows move a window to a monitor;
  Super + Tab is `m+1`). Its bar: `shell/plugins/bar/widgets/Workspaces.qml@v4.5.0-rc1`
  (reads the state file with a FileView, the first five of its own block then
  guests after a gap, refreshes monitors and workspaces on `moveworkspacev2`,
  `changeworkspaceid` and a switch on its own monitor). Its test:
  `test/shell.d/hyprland-monitor-workspaces-test.sh@v4.5.0-rc1` (a Lua model
  of Hyprland's workspace handling; adapted here).
- **Floating step**: `default/hypr/workspace-modes.lua` at 149871896 "Add a
  floating mode with titlebars to the workspace layout cycle (#14482)" (385
  lines) and `bin/omarchy-hyprland-workspace-layout-toggle` at the same
  commit. Its commit message records two bugs in the old toggle that haseen's
  had too: a named workspace's negative id passed `^-?[0-9]+$` and Hyprland
  reads a leading `-` as relative, reconfiguring workspace 1; and the mode was
  saved before it was applied. Later commits add only the dock and its open
  rule (124328fd8 #15263), titlebars on the first float (cffdaa6cc #15271), a
  comment (c4803d7d7), menu moves (6bee248a3) and float-rule refreshes for
  the open rule (2e7c1fe43 #16143, after the tag).
- **Console**: `default/hypr/qconsole.lua@quattro` (196 lines; 0b5111702
  "Give scratchpad a Quake-style console presentation (#7409)", 83987718c
  #7420, 692c02cad merging #9140, d377569ed "Count only tiled windows and
  refit when apps move or float"; unchanged since the tag). It styles Omarchy's
  `special:scratchpad` and seeds it with `omarchy-agent`; Super + grave and
  Super + S both toggle it (`tiling.lua@v4.5.0-rc1:30-34`).
- **Full-screen desktop**: `bin/omarchy-toggle-fullscreen-desktop@quattro`
  (a7486beb6 #10672), bound to Super + Ctrl + Alt + F
  (`default/hypr/bindings/utilities.lua@quattro:21`).
- **Screenshot chord**: rc1 had Super + Shift + S
  (`utilities.lua@v4.5.0-rc1:39`); 0a7beb7d6 (#16048, after the tag) moves it
  to Super + Ctrl + Alt + C (`utilities.lua@quattro:40`) and gives Super +
  Shift + S back to a web app.
- **haseen** at origin/main eb89999: the global workspace keys
  (`share/haseen/default/hypr/binds.lua@eb89999:213-226`), the scratchpad on
  Super + S (`:228-229`), workspace switches without animation
  (`share/haseen/default/hypr/looknfeel.lua@eb89999:84`), the toggle's guard
  `[[ $id =~ ^-?[0-9]+$ ]]` (`bin/haseen-toggle-workspace-layout@eb89999:31`)
  and its save-then-apply order (`:42-44`), and no layout indicator anywhere
  in the shell (`grep -rn tiledLayout share/haseen/shell` finds none).
  Plan 102's answers already translated Omarchy's full-screen desktop
  (`share/haseen/omarchy/bin/omarchy-toggle-fullscreen-desktop@eb89999`) and
  refused a floating layout as needing the dock and titlebars.
- **Keys free before this plan**: none of Super + grave (or `code:49`),
  Super + Shift + grave, Super + Ctrl + Alt + F, Super + Ctrl + Alt + C or
  Super + Shift + Ctrl + arrows is bound in `binds.lua@eb89999` (Super + Ctrl
  + C is the capture menu, Super + Alt + C the calendar, Super + Alt + F
  maximise; the HYPER layer is all four modifiers, so Super + Shift + Ctrl is
  distinct); `share/haseen/default/hypr/user/hyprland.lua` binds nothing; and
  `haseen import omarchy` turns the owner's imported `o.bind` lines into
  `haseen.rebind` (`share/haseen/lib/omarchy-import.sh:285`), which unbinds
  first, in a file that loads after haseen's, so an imported bind on any of
  these keys still wins. `tests/test-omarchy45-workspaces.sh` checks that no
  key is bound twice, with and without per-monitor workspaces.
- **Hyprland 0.56.2** (`pacman -Q hyprland`: 0.56.2-4, the version Omarchy's
  console comment measured on): `hl.on` subscriptions are dropped and made
  again on every reload ("Destroyed (and recreated) on every config reload
  so callbacks never double-up",
  `/usr/include/hyprland/src/config/lua/LuaEventHandler.hpp`), which is why
  each module registers its events on each load.

## Problem

1. SUPER + 1..0 address Hyprland's global numbers: on two monitors, SUPER + 3
   pulls workspace 3 to whichever monitor it lives on, and a re-plugged
   monitor comes back on whatever numbers are free.
2. `haseen toggle workspace-layout` (ALT + L) cycles dwindle and scrolling only;
   Omarchy 4.5 adds floating, where every window on the workspace floats.
3. No drop-down console.
4. The keys Omarchy 4.5 added for the full-screen desktop, a screenshot and
   moving a window to a monitor are missing.

## What was built

### Per-monitor workspaces, off by default

- **`share/haseen/default/hypr/monitor-workspaces.lua`** (new): the port.
  Unchanged logic: blocks keyed by identity with the laptop panel first,
  `reconcile` (`:543`), merging an unplugged monitor's workspaces after another
  monitor's own and restoring them when it returns, the bind actions
  (`:448-538`). Changes: state in `$XDG_STATE_HOME/haseen/` (`:38`); replay
  expressions on `haseen.bind_expressions` as `haseen.workspaces.focus(3)`
  (`:433`); lists from `hl.get_*` guarded (`:45`) so a stub cannot loop; and
  **nothing subscribes or rebinds until `M.enable()`** (`:692`), which a
  toggle file calls. `enable()` registers the five events and rebinds, with
  `haseen.rebind`, SUPER + 1..0 (focus), SUPER + SHIFT + 1..0 (**silent**,
  the owner's layout, where Omarchy's is the following move), SUPER + SHIFT +
  ALT + 1..0 (follow), SUPER + SHIFT + ALT + LEFT/RIGHT (move a workspace,
  joining the target's block) and SUPER + TAB, SUPER + SHIFT + TAB and SUPER +
  wheel on `m+1`/`m-1`, so a walk stays on the monitor. The HYPER layer is
  untouched.
- **`bin/haseen-toggle-monitor-workspaces [on|off|toggle|status]`** (new):
  writes or removes `toggles/hypr/monitor-workspaces.lua` (the file calls
  `haseen.workspaces.enable()`) and reloads Hyprland, the only way to swap
  binds; the reload's `config.reloaded` puts each monitor on its own block.
  `haseen settings list` shows it (`share/haseen/lib/settings.sh`, one row).
- **haseen.workspaces** (`Workspaces.js`, `Widget.qml`, manifest 2.1.0): while
  the toggle file exists, each bar shows its monitor's block, `persistent` of
  its own first, then existing ones of the block, then guests from an
  unplugged monitor after a half-cell gap; labels are the slot keys 1-0; a
  click on its own runs `haseen.workspaces.focus(<slot>, "<monitor>")`, which
  brings the workspace home first; the wheel walks the row and stops at the
  ends. Two FileViews, never a Timer: the toggle (read again on Hyprland's
  `configreloaded`, since its directory may not exist to be watched) and the
  blocks file. With per-monitor workspaces, a monitor and workspace refresh on
  `moveworkspacev2`, `changeworkspaceid` and a switch on the bar's own monitor,
  as Omarchy's widget does, because Quickshell does not learn a new number or
  a fallback workspace by itself. Off, the widget is what it was.
- **SUPER + SHIFT + CTRL + arrows** (both modes, `binds.lua:248-250`):
  `haseen.workspaces.move_window_to_monitor`, which does nothing when no
  monitor is that way instead of showing Hyprland's error.

### The floating step

- **`share/haseen/default/hypr/workspace-modes.lua`** (new): the core of
  149871896. `haseen.workspace_mode({ workspace, mode })` (`:235`): dwindle and
  scrolling are workspace rules as before; floating floats the workspace's
  tiled windows (`:123`), tagged `haseen-mode-floated`, sized min(1100, 64 %)
  by min(760, 68 %) of the usable area, centred and stepped (`:87`); leaving
  floating tiles only what the tag claims, never a pinned window (`:141`);
  windows opening, carried in or out, or leaving fullscreen follow the mode
  (`:197`); a floating workspace focuses on click (`:175`). Dropped: the
  titlebars (a compiled plugin), the shadows and full opacity it turned on,
  the dock, the window rule that floats a window from its first frame (it
  needs Omarchy's registry of float rules, `o.floating_apps`), and a user
  default mode. Changed: `input.follow_mouse` is read when a floating
  workspace comes into view, not when the first mode loads, so the user's own
  value (set in files that load after haseen's) is the one given back. Bad
  ids and modes raise. Nothing subscribes until a workspace floats or a
  claimed window remains, so a session that never floats pays nothing.
- **`init.lua`** loads it, then after every toggle file calls
  `haseen.workspace_modes.apply()` under `pcall` (`:199`), which tiles back
  whatever a mode floated before a reload if the mode is gone.
- **`bin/haseen-toggle-workspace-layout`**: `toggle` steps dwindle ->
  scrolling -> floating -> dwindle, `back` the other way, `current [ID]`
  prints the mode (the saved floating mode wins, else Hyprland's
  `tiledLayout`). It applies first and saves only what Hyprland accepted, and
  refuses a named or special workspace (`^[1-9][0-9]*$`), both from
  149871896. Saved files now call `haseen.workspace_mode(...)`; a file from
  before this plan (`hl.workspace_rule(...)`) still loads and reads as its
  layout.
- **Omarchy's answers** (plan 102's files): `omarchy-hyprland-workspace-layout-current`
  asks `haseen toggle workspace-layout current`; `-toggle back` is now
  haseen's `back`; `-default floating` is refused with the per-workspace way.
  The bar shows no layout indicator, because haseen had none for two layouts
  (the brief's condition); Omarchy's glyph is not adopted.

### The console

- **`share/haseen/default/hypr/qconsole.lua`** (new): the port, on a special
  workspace of its own, `special:console` (`:15`), toggled with **SUPER +
  GRAVE** through `haseen.console.toggle()` and fed with SUPER + SHIFT +
  GRAVE (`binds.lua:242-243`; `code:49`, the key left of 1, so it works on the
  Arabic layout as the number row does). The first open starts `$TERMINAL`
  (foot unset) as SUPER + RETURN does, through an exec rule that pins the
  workspace (`:29`). Half the usable height, flush with the top, boxed 2:1
  while it holds one tiled window and full width with more, refitted on
  monitor and window events only while it is shown (`:98-158`, `:355-396`). A
  monitor that cannot be read at load is skipped under `pcall` (`:156`).
- **The dim and the slide, the console's only** (owner, above). Hyprland has
  one `decoration.dim_special` and one pair of `specialWorkspaceIn/Out` leaves
  for every special workspace and no per-workspace style for special ones (a
  regular workspace's style is passed to its animation, a special workspace's
  never is: Hyprland v0.56.2 `src/output/Monitor.cpp:1470-1475` against
  `:1566`, `:1604`, `:1654`). So the console borrows them at runtime. Read
  from Hyprland v0.56.2's and hyprutils v0.14.2's source (both tags, read in
  a scratch clone and deleted):
  - the dim is read once, when a special workspace opens, into the monitor's
    animated dim (`Monitor.cpp:1537-1550`, `setSpecialWorkspaceVisualState`).
    `M.toggle` (`qconsole.lua:322-350`) reads the user's value with
    `hl.get_config`, sets 0.6, dispatches, and sets the user's value back at
    once (`:339`, `:343`): the console keeps its 0.6 and anything opened next
    reads the user's. Each write schedules one deferred window-state refresh
    (`src/config/supplementary/propRefresher/PropRefresher.cpp:29-41, 89-113`),
    the kind the console's own refit already causes;
  - a slide reads its leaf's style when it starts
    (`src/animation/WorkspaceAnimationController.cpp:20-36`) and its speed and
    on/off on every frame until it lands (hyprutils
    `src/animation/AnimatedVariable.cpp:53-58, 74-78`; Hyprland
    `src/animation/AnimationManager.cpp:284`), and `hl.animation` overwrites
    the leaf in place (hyprutils `src/animation/AnimationConfig.cpp:35-51`).
    So a leaf handed back too early would make a running slide jump to its
    end. The toggle lends `specialWorkspaceIn` before it dispatches and takes
    it back 350 ms later (speed 3 is 300 ms: the speed is in tenths of a
    second, `AnimatedVariable.cpp:78`). `specialWorkspaceOut` is lent while
    the console is the only special workspace shown and taken back 250 ms
    after it closes;
  - every way a special workspace opens or closes (a key, focus moving off
    it, its last window closing, a workspace switch, the ext-workspace
    protocol) goes through `CMonitor::setSpecialWorkspace`, which starts the
    animations and then emits `workspace.special_active` (`Monitor.cpp:1552-1700`;
    callers `src/desktop/state/FocusState.cpp:184-185`,
    `src/desktop/view/Window.cpp:590-593, 730-733`). `settle`
    (`qconsole.lua:280-305`) runs on it: another special workspace shown
    anywhere gets both leaves back at once, so it closes the way the user set
    and, if it opened within the console's 300 ms drop, it lands a frame
    later rather than sliding; a console shown alone borrows Out, after the
    user's own Out has run if it replaced an animated special workspace;
  - the leaf handed back is what the config gave it: Hyprland has no getter
    for animations, so `init.lua:119-143` wraps `hl.animation` once per Lua
    state and remembers the last spec per leaf (from haseen's defaults to the
    user's files), and `configured` (`qconsole.lua:203-215`) walks
    specialWorkspaceIn/Out → specialWorkspace → workspaces → global as
    Hyprland inherits them (`src/config/shared/animation/AnimationTree.cpp:14-66`),
    falling back to Hyprland's own default for global;
  - a reload resets the animation tree, every setting, the timers and the Lua
    state before running the config again (`src/config/lua/ConfigManager.cpp:698-735`),
    so nothing borrowed survives one; `config.reloaded` lets a console still
    shown borrow Out again (`qconsole.lua:370`).
  With haseen's defaults (the `workspaces` leaf off, `looknfeel.lua:84`) the
  scratchpad and the screensaver's workspaces open and close at once, as on
  main. `qconsole` now loads before `binds` (`init.lua:197`), which binds its
  toggle.

### The binds

- **SUPER + CTRL + ALT + F**: `haseen toggle fullscreen-desktop [on|off|toggle]`
  (`bin/haseen-toggle-fullscreen-desktop`, new): the bar (session) and `haseen
  toggle gaps` together; toggle leaves only when both are off, as Omarchy's;
  a shell that does not answer (none, or DMS) leaves the bar alone and
  changes the gaps, with a warning. `omarchy-toggle-fullscreen-desktop` now
  calls it.
- **SUPER + CTRL + ALT + C**: `haseen capture screenshot`, the Omasnap capture
  PRINT runs (plan 107), for keyboards without PRINT.
- **SUPER + SHIFT + CTRL + arrows**: above.
- **The keybind sheet** (`share/haseen/lib/keybinds-scan.lua`): a Lua-function
  bind with a `haseen.bind_expressions` entry is listed with that expression
  (`kind` lua), so the sheet and Learn's list can replay SUPER + 3 with
  per-monitor workspaces on; a bind made inside a function (the toggle's
  rebinds) takes the section above that function when its file's main chunk
  has none; and the stub `hl` answers no number index, so a module walking an
  `hl.get_*` list during the scan ends instead of looping.

## On by default, and why

| What | Default | Why |
|---|---|---|
| Per-monitor workspaces | **off** | The brief: a change to SUPER + 1..0 is the default only if one monitor behaves exactly as before. It does not. A monitor's block is fixed by its identity, so a single monitor that was not the first ever seen keeps a block above 0: the external monitor of a laptop docked with its lid closed (the laptop panel owns 1-10), a desktop monitor replaced by a new one, or the third monitor of an old session used alone (`tests/test-omarchy45-workspaces.sh` "blocks": a monitor alone starts on 21 and SUPER + 1 reaches 21). Its keys then reach 11-20, so window rules, `hyprctl dispatch workspace 3` and scripts that name a number see other ids than the keys. And a reload or monitor event renumbers an occupied workspace above 10 into the monitor's block ("single": workspace 12 becomes 2). On one monitor that has always been the first, SUPER + 1..0 reach the same 1..10 as before, and SUPER + TAB's `m+1` is the same step as `e+1`. |
| Floating step on ALT + L | on | The owner chose the step; ALT + L already cycles the layout, and a workspace floats only when the user steps it there. A session that never floats subscribes to nothing. |
| Console on SUPER + GRAVE | on | The owner chose "Quake console" and the key was free; nothing runs until the first press (the workspace and its terminal are created then). |
| The console's dim (0.6) and drop/retract slide | on, the console only | The owner chose "Console only" (2026-10-22): lent while the console shows and handed back, so the scratchpad and the screensaver's workspaces keep the user's dim and animations (none with haseen's defaults), as on main. |
| SUPER + CTRL + ALT + F, SUPER + CTRL + ALT + C, SUPER + SHIFT + CTRL + arrows | on | "New binds"; free keys; no on-screen element. |

No new on-screen element: the console appears only when pressed, and the bar
shows the same row of numbers, per monitor when that is on.

## Rejected options

- **Per-monitor workspaces on by default**: rejected by the brief's own test
  (table above).
- **A first block reserved for "whatever monitor is alone"**, so one monitor
  always gets 1-10: it breaks the point of the feature (a monitor gets the same
  workspaces back when replugged) for the docked laptop, where the panel and
  the external monitor would swap blocks with the lid.
- **The console as the scratchpad, as Omarchy has it**: SUPER + S is the
  owner's scratchpad and holds whatever SUPER + ALT + S sends there; boxing it
  to half the screen and starting a terminal on its first open would change
  that. A workspace of its own keeps SUPER + S's size.
- **The dim and the slide everywhere, like Omarchy** (the first version of
  this plan) and **no dim or slide**: the owner's other two answers
  (2026-10-22); the owner chose the console only.
- **Handing the leaves back as soon as the console has opened or closed**:
  a slide reads its speed and on/off on every frame, so the console's drop
  and retract would jump to their end; they go back once they have run.
- **Lending Out only on the key that closes the console**: its last window
  closing, focus moving off it or a workspace switch would make it vanish
  instead of retracting; Hyprland reports all of them, so `settle` covers
  them.
- **Routing SUPER + S through haseen to set the leaves first**: the
  screensaver and `hyprctl dispatch` open special workspaces without it;
  handing the leaves back whenever another special workspace shows covers
  every path.
- **Seeding the console with the default AI agent** (Omarchy's
  `omarchy-agent`): the brief asks for a terminal; an agent can still be run
  in it.
- **No slide, to keep special workspaces instant like regular ones**: the
  drop-down is what makes it a Quake console; regular switches stay instant.
- **Omarchy's per-workspace layout glyph in the bar**: haseen shows no layout
  today, and the brief adds one only if it did for two modes.
- **Omarchy's open rule** (floats a window from its first frame on a floating
  workspace, 124328fd8): it is built on the dock commit's registry of float
  rules; without it a new window opens tiled and floats a frame later.
- **Titlebars, shadows and full opacity on floating workspaces**: no titlebars
  or shadows in haseen (architecture §1, the owner's standing decision).
- **A Trigger › Toggle menu row for per-monitor workspaces**: the settings
  index lists it; `menu.jsonc` is shared by other plans and its tests.
- **Renumbering workspaces back to 1..10 when per-monitor workspaces are
  turned off**: the next workspace close does it; SUPER + TAB reaches the rest.

## Tests

- `tests/test-omarchy45-workspaces.sh` (new, 110 checks): per-monitor
  workspaces against a Lua model adapted from Omarchy's test (off subscribes
  and rebinds nothing; enable's events, keys, the silent move and replay
  expressions; blocks across sessions and connectors; reclaim without a swap;
  hot-plug with the merge file; merge order and moves by hand; one monitor;
  window to monitor with and without a neighbour); the floating mode against a
  fake of its `hl` calls (tiled modes subscribe to nothing; only claimed
  windows tile again; dialogs, fullscreen and pinned windows; opening and
  carrying windows; focus on click and the user's value back; a reload's
  apply; bad specs); the console against a model of Hyprland's special
  workspaces that records what each open and close reads (its own workspace
  and terminal seed, nothing set at load, the 0.6 dim and the drop read when
  it opens and the user's dim back at once, In and Out lent until their
  slides have run, the scratchpad alone untouched, another special workspace
  on the same or another monitor taking the leaves back, its last window
  closing, a replaced animated special workspace finishing first, a reload,
  pulling it over to another monitor, the 2:1 box and full width, no refit
  while hidden, an unreadable monitor); the real `init.lua` under a stub for
  the `hl.animation` record (defaults and user specs kept, refused specs and
  `haseen.set_animation` not, a fresh record per load, one wrapper per
  state); the real config through the keybind sheet's scan (the new keys,
  no key twice, the HYPER layer, the toggle's rebinds and the user's bind
  winning, a floating workspace file not hanging the scan); the three
  commands and Omarchy's answers against stubbed hyprctl and qs; the bar's
  per-monitor functions under Qt's JS engine (17 units) and the widget in the
  real Quickshell engine following the toggle off and on and reading the
  blocks. Five mutations (follow instead of silent, tiling unclaimed windows,
  the console on the scratchpad, the scan's number index, the old id guard)
  each fail it, and so do five on the console's dim and slide (the dim not
  handed back: 107/110; In handed back at once: 108/110; Out kept while
  another special workspace shows: 109/110; the dim set at load: 4 failures;
  `hl.animation` wrapped on every load: 109/110).
- Updated: `tests/test-trigger.sh` (the saved layout's new form),
  `tests/test-omarchy-45.sh` (`back` passes through; the full-screen answer
  calls haseen's command), `tests/test-settings.sh` (the index lists the new
  toggle and round-trips it), `tests/test-keyboard.sh` (its stub of
  `binds.lua` provides `haseen.workspaces` and `haseen.console`).
- `tests/run.sh --affected origin/main` and the gates: see Evidence.

## Evidence

All runs hermetic (the stub PATH, a private `XDG_RUNTIME_DIR` and `TMPDIR`
under `/tmp`, offscreen Qt, no Hyprland or session bus), on luna with
Hyprland 0.56.2-4, Lua 5.5.1 and Quickshell from the system packages.

After the review (the console's dim and slide made the console's only, the
settings row, origin/main at 4786acb merged in), from a short bind mount of
the worktree:

- `tests/run.sh tests/test-omarchy45-workspaces.sh`: **110/110**.
- `tests/run.sh --affected origin/main` (78 of 160 test files): **9287/9287**.
- Five mutations on the console's dim and slide, each reverted: see Tests.
- `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: lint OK (897 shell, 36 Lua,
  198 JSON, 334 QML and 41 Go files; 2616 files, 160 tests: every file
  covered). `tools/check-docs.sh`: OK.
- Secrets on the branch range (merge base 4786acb): gitleaks "3 commits
  scanned … no leaks found", and the tailnet/home-path grep over `git log -p`
  printed nothing.

Before the review:

- `tests/run.sh tests/test-omarchy45-workspaces.sh`: **101/101**.
- `tests/run.sh --affected origin/main` (77 of 159 test files; the manifest's
  description edit selects every plugin-manifest test): **9021/9025**. The
  four: `test-keyboard.sh` "binds.lua loads" (its stub loads `binds.lua`
  without `monitor-workspaces.lua`; the stub now provides
  `haseen.workspaces`), two in `test-menu-back.sh` and `test-themegen-keys.sh`
  ("Failed to start IPC server": the worktree path pushes Quickshell's socket
  past 108 bytes), and `test-nvim-theme.sh` "one line per spec" (15 of 17
  under load). Re-run from a short bind mount after the stub fix:
  `test-keyboard`, `test-menu-back`, `test-themegen-keys`, `test-nvim-theme`
  **258/258**; `test-omarchy45-workspaces` with `test-keyboard` **145/145**;
  `test-frame.sh` (selected by the later `NOTICE.md` row) **148/148**.
- After the bar widget's guest-gap expression was corrected (it read the
  previous id's block wrongly), the tests that load the widget were re-run:
  `test-omarchy45-workspaces`, `test-widgets-a`, `test-shell`,
  `test-recovery` and `test-surfaces` **613/613**; `qmllint` on `Widget.qml`
  reports no errors.
- Five mutations, each reverted: SUPER + SHIFT + n following instead of
  silent (99/101), tiling windows the mode did not float (100/101), the
  console on the scratchpad (100/101), the scan's number index answering
  (93/101: the scan loops and times out), the old `^-?[0-9]+$` guard (98/101).
- `tools/affected-tests.sh --check`: every file covered.
- `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: lint OK (893 shell, 36 Lua,
  198 JSON, 334 QML and 41 Go files; every file covered).
- `tools/check-docs.sh`: OK.
- Secrets on the branch range (merge base eb89999): gitleaks "1 commits
  scanned … no leaks found", and the tailnet/home-path grep over
  `git log -p` printed nothing.

## Not verified

- **A live Hyprland session.** No compositor was driven: the owner's session
  is off limits and a nest would run on it. So these rest on Omarchy's use of
  the same calls on Hyprland 0.56.2 and on the models: the event names
  (`monitor.added`, `workspace.special_active`, `window.update_rules`, …), the
  `hl.dsp.workspace.change_id`, `monitor:set_workspace`, `hl.get_config`,
  `hl.timer` and `hl.exec_scheduled_prop_refresh_immediately` calls, whether
  `hyprctl eval` exits non-zero when the Lua fails (the toggle relies on it to
  save nothing), whether the console's exec rule still pins the window when
  the terminal starts through `uwsm-app`, and whether the explicit
  `specialWorkspaceIn/Out` leaves animate while their `workspaces` parent is
  disabled.
- **The console's borrowed dim and slide on screen.** That `hl.config` and
  `hl.animation` take effect when called from a key and a timer at runtime,
  and that the slide lands smoothly before its leaf goes back, rest on
  reading Hyprland v0.56.2's and hyprutils v0.14.2's source (above) and on the
  model, not on a session. A special workspace opened within the console's
  300 ms drop starts on the borrowed slide and lands a frame later; a user who
  enables special-workspace animations sees one opened in that window take
  the slide's direction.
- **Hot-plugging a monitor, a docked laptop with the lid closed, replacing a
  monitor**: modelled, not done.
- **The widget on a real bar with Hyprland**: it was loaded in the real
  Quickshell engine without Hyprland (its file watches), not on a bar with
  monitors.

## Owner steps

On IO and luna, after the pull request merges and the tree is installed:

1. `hyprctl reload` (or log out and in) to load the new Hyprland files. Then
   try SUPER + GRAVE (a terminal drops down over a dimmed screen; again to
   retract it), then SUPER + S: the scratchpad should open and close at once
   with the light dim it had before, also right after closing the console and
   while the console is open. Then ALT + L three times on a workspace with
   two windows (dwindle, scrolling, floating, and back to tiled), SUPER + CTRL
   + ALT + F twice, and SUPER + CTRL + ALT + C.
2. On a machine with two monitors, if wanted: `haseen toggle monitor-workspaces on`
   (or `haseen settings set monitor-workspaces on`). Check SUPER + 1..0 on each
   monitor, each bar's numbers, and unplug and replug one monitor. It is off
   until then; `haseen toggle monitor-workspaces off` returns to global
   numbers.
3. If the console's first open puts the terminal on the current workspace
   instead of in the console, say so: the seed would then start the terminal
   without `uwsm-app`.

## Files outside the brief's owned paths

The brief owns `share/haseen/default/hypr/` (not the terminal copy/paste
lines), `bin/haseen-toggle-*`, haseen.workspaces and their tests. Also
touched, each because a change above made it stale or wrong:
`share/haseen/lib/keybinds-scan.lua` (the sheet data, which the brief names),
`share/haseen/lib/settings.sh` (one row), plan 102's
`share/haseen/omarchy/bin/omarchy-hyprland-workspace-layout-{current,default,toggle}`,
`omarchy-toggle-fullscreen-desktop` and their `commands.tsv` rows, and
`tests/test-{trigger,omarchy-45,settings}.sh`, and `tests/test-keyboard.sh`
(its stub of `binds.lua` needs `haseen.workspaces`); plus `AGENTS.md` (the default
keys line), `docs/architecture.md`, `handoff.md` and `NOTICE.md`.
