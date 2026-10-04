# Plan 005: Quickshell shell core and plugin host

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. The budget risk is resolved by the integrator: architecture §6 now sets < 200 MiB RSS from these measurements, and `haseen doctor` prints shell RSS/PSS. The integrator re-ran it live and got 177 MiB RSS / 126 MiB PSS. The overlay host moves to plan 010.

## Why this matters

Requirements 1, 2, 3 and 5. A shell we own, small enough to read in one sitting.

## Scope

- `share/haseen/shell/`: `shell.qml`, `Haseen/` singletons, `Haseen/Widgets/`, the plugin registry, the bar, and built-in bar widgets.
- `plugin.schema.json`.
- `bin/haseen-shell-{run,restart,ipc}` and `bin/haseen-plugin-{list,new,validate,info,enable,disable}`.
- `layers/shell` and `haseen-shell.service`.

## Acceptance

- The shell runs under `qs -p` on the live session with no QML errors.
- A screenshot proves the bar renders.
- `haseen plugin new` → `haseen plugin validate` → the plugin appears after a hot reload.
- Idle RSS is measured and recorded.

## Execution record

Executed 2026-10-04 against quickshell 0.3.1 and Hyprland 0.56.2 (Lua) on the live Omarchy session. No commit (integrator).

### What changed

- `share/haseen/shell/shell.qml`: ShellRoot. It holds a per-screen `Bar` (`Variants` over `Quickshell.screens`). A service host (an `Instantiator` over a `ScriptModel` of `Config.services` → `ServiceHost`) diffs the list, so editing `shell.json` never restarts the other services. A panel host: one `LazyLoader` per panel plugin, `active` only while the panel is open, so nothing exists until first open and closing frees the window. It also holds the IpcHandlers for `shell`, `panel`, `launcher`, `lock` and `notifications`, exactly as in architecture §5.5. `launcher`, `lock` and `notifications` go through `routeRole()`: (1) a loaded instance registered for the role that has the function; (2) otherwise, for `toggle`, a panel plugin that `provides` the role; (3) otherwise one log line.
- Host components: `Bar.qml`, `BarSection.qml`, `PluginSlot.qml`, `ServiceHost.qml` and `PanelPopup.qml`.
  - `PluginSlot` is a `Loader` with `setSource(url, {pluginId, settings, screen})`. Afterwards `settings` is re-bound to `Plugins.settingsFor()`, so a change in `shell.json` updates the widget in place. A widget with `implicitWidth` 0 takes no slot.
  - `PanelPopup` is a `PanelWindow` centred on the bar edge, with `exclusiveZone: 0`, `WlrKeyboardFocus.OnDemand`, Escape handling and a `HyprlandFocusGrab` for outside clicks.
- `Haseen/` (`qs.Haseen` qmldir):
  - `Paths` honours `HASEEN_USER_CONFIG`/`HASEEN_USER_STATE` like `common.sh`.
  - `Theme`: a watched `FileView`. Every §7 key has a fallback, and values of the wrong type fall back too.
  - `Config`: deep merge (objects merge, arrays replace). It keeps the last good value when the file is invalid or empty in the middle of a write.
  - `Plugins`: the registry. It provides `componentUrl`, `settingsFor`, `provider`, `callRole`, `registerRole`, `describe`, the error list and `warnOnce`.
- `Haseen/Widgets/`: `BarButton` (glyph, label, hover, click and wheel; it exposes `contentWidth`), `Glyph` and `PanelSurface`.
- Built-in bar widgets (`plugins/haseen.*`): `workspaces` (`Quickshell.Hyprland`, Lua dispatcher when `Hyprland.usingLua`), `clock`, `tray`, `audio`, `network` and `battery`.
  - `clock` uses `SystemClock`, with `Minutes` precision, or `Seconds` only when the format (outside quoted literals) contains `s`. It is enabled only while visible.
  - `audio`: `Pipewire.defaultAudioSink` plus `PwObjectTracker`. Scroll changes the volume by `settings.step`; click toggles mute.
  - `network` uses `Quickshell.Networking`, which exists in 0.3.1 (`/usr/lib/qt6/qml/Quickshell/Networking/`): device and network property signals, `scannerEnabled` untouched, no `nmcli`.
  - `battery` uses `UPower.displayDevice` and gets `implicitWidth` 0 without a laptop battery.
  - All of them use Theme tokens only. A test greps for hex literals.
- `plugin.schema.json` (draft 2020-12): the §5.2 fields, `provides`, `additionalProperties: false` and `if/then` rules for an entry per kind. It was cross-checked with python-jsonschema 4.26 in a throwaway venv (dev evidence only; python never enters the shell path): the six built-ins pass, and broken manifests fail on the same fields that `haseen plugin validate` reports.
- `share/haseen/shell/lib/plugin.sh` holds the jq/bash validator and the `shell.json` helpers. It sits in `shell/` because `lib/` is core-owned. The scaffold templates are in `share/haseen/shell/templates/<kind>.qml`.
- Commands:
  - `haseen shell run` and `haseen shell restart`.
  - `haseen shell ipc` reads the first word of `active-shell`. For `dms` it runs `layers/dms/ipc-translate`.
  - `haseen plugin list/info/validate/new/enable/disable`.
  - `new` stages the plugin in a hidden `.<id>.new/` and renames it into place. `enable` and `disable` write `shell.json.new` and then rename it. Either way the running shell never reads a half-written file.
- `haseen-shell.service`, and `layers/shell`, which needs `desktop` and `theme`:
  - It installs `quickshell`, `jq`, `upower` and `ttf-nerd-fonts-symbols`.
  - It seeds `shell.json` (`{}`) and `shell.example.json`, and enables the unit (skipped when the wants symlink exists).
  - Its status checks the packages, `shell.json` and the wants symlink, without calling `systemctl`.
- `default/shell.json`: the §5.3 bar with `"services": []`. The §5.3 service ids belong to plan 010; listing them now would only log "unknown plugin" lines.
- `tests/test-shell.sh` (157 assertions) and a new fixture, `tests/fixtures/shell-quickshell-installed/`.
- `shell.qml` pragmas:
  - `UseQApplication`: tray menus are platform menus.
  - `DefaultEnv QT_QUICK_BACKEND = software`: measured below.
  - `DefaultEnv QS_NO_RELOAD_POPUP = 1`: package updates touch the shell dir, and the reload toast would be clutter.

### Evidence

- `tests/run.sh tests/test-shell.sh` → `157/157 passed`; `tests/run.sh tests/test-core.sh` → `32/32 passed`.
  - Mutation check: making `enable` start from the user's `bar.right`, and disabling the dms branch of `shell ipc`, gave `150/157 passed`, with failures `bar.right = default right + id`, `active-shell=dms routes to ipc-translate` and others. Both mutations were reverted.
- `/tmp/tools/shellcheck --severity=warning -x` on all 12 shell files → rc 0. `bash -n` was clean. `jq empty` passed on the schema, the defaults, the manifests and the layer files. `systemd-analyze --user verify haseen-shell.service` → rc 0.
- qmllint, with the `tools/lint.sh` flags, over 24 QML files: rc 0, `Error-lines=0`.
  - It also flagged `function focus()` in the workspaces widget as shadowing `Item.focus`. Renamed to `activate()`.
  - The remaining warnings are qmltypes artefacts: `PanelWindow` "not creatable" and Repeater `required modelData`.
  - Note: in the agent harness shell, `mapfile < <(find …)` hangs; `tools/lint.sh` runs in its own bash and is unaffected.
- Live smoke: `HASEEN_PATH=$PWD/share/haseen XDG_CONFIG_HOME=/tmp/haseen-smoke/config XDG_STATE_HOME=/tmp/haseen-smoke/state qs -p share/haseen/shell`, a second instance beside omarchy-shell.
  - Log: `Configuration Loaded`, no QML warnings. The only lines are a portal app-id warning and `Could not load icon "org.remmina.Remmina-status"`; the scratch `XDG_CONFIG_HOME` hides the user's icon-theme settings.
  - The `hyprctl layers` output shows `haseen-bar 0,24 1536x28` (stacked below `omarchy-bar 0,0 1536x24`).
  - Screenshot (grim, viewed): `1 2 3 4` with the focused workspace in the accent colour, a centred clock, then tray icons, `40%`, the wifi glyph and `64%` battery on the right.
  - `haseen shell ipc shell plugins` → `{"ready":true,"roles":{},"errors":[], plugins: haseen.audio…haseen.workspaces builtin valid listed, smoke.hello user valid unlisted}`.
  - Panels:
    - `panel toggle smoke.hello` (a scratch user plugin importing `qs.Haseen`) gave `haseen-panel@666,58 204x40`. The screenshot shows "hello from smoke.hello (user)", which proves the singleton is shared with plugins outside the shell dir.
    - `wtype -k Escape` closed it.
    - `launcher toggle` opened it, because the plugin declares `"provides": ["launcher"]`.
    - `panel close` closed it.
  - Role and service routing: `lock lock` → `INFO qml: haseen: no plugin provides 'lock', lock.lock() ignored`. With a scratch service providing `lock`: `INFO qml: smoke.svc: lock() reached the service`, and `roles` = `{"lock":"smoke.svc"}`. The service started without a reload.
  - `haseen plugin new smoke.greet --kind bar-widget` → `validate` (`ok`) → `enable` → `shell ipc shell reload` → `{"id":"smoke.greet","valid":true,"enabled":true,"listed":true}`, and the screenshot shows "Greet" at the end of the right section.
  - `haseen plugin disable haseen.battery` hid the battery live with no reload. 0 "not valid JSON" log lines (atomic rename).
  - A clock format change to `HH:mm:ss` showed `13:43:11` live.
  - Theme: a tokens file `{"accent":"#ff5555","background":"#000000","radius":"bogus"}` rendered a red focused workspace on black, and the bad radius fell back silently. A directory swap (the `theme_swap` pattern from plan 004) to `{"accent":"#55ff55"}` re-rendered green, with the background back to the fallback.
- Resources, measured with the full default bar after 30 s idle:

| backend | RSS | PSS | CPU over 60 s |
|---|---|---|---|
| GL (Qt default) | 263 MiB (269564 kB) | 160 MiB | 2 ticks = 0.02 s (0.03 %) |
| software (shipped default) | 178 MiB (181816 kB) | 126 MiB (129517 kB) | 1 tick = 0.01 s (0.017 %) |

  - A bare Quickshell (one `PanelWindow` and a `Text`) measures 212 MiB RSS on GL and 122 MiB on software, so the haseen host plus the widgets cost about 55 MiB above the Quickshell floor.
  - Per-feature RSS on software:
    - empty bar: 139 MiB
    - clock only: 142 MiB
    - default bar without the tray: 156 MiB
    - full default bar: 170–178 MiB
    - without `UseQApplication`: −5 MiB
  - For comparison, omarchy-shell is 610 MiB RSS on the same machine.
  - Software rendering maps no Mesa DRI libraries (checked in `/proc/<pid>/maps`), and the screenshots are identical at 1.25 scaling.
- `hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })'` → `ok` (the dispatcher string the workspaces widget sends in Lua mode).
- `FileView` behaviour, from a standalone probe: watching survives in-place writes, rename-over and parent-directory swaps. It does not see a file created after the shell started, and it keeps reading the old target after a symlink swap. That is why `enable` prints a reload hint the first time it creates `shell.json`, and why the shell layer seeds `shell.json`.

### Rejected

- **`nmcli monitor` stream for `haseen.network`.** Rejected because `Quickshell.Networking` exists in 0.3.1 and speaks NetworkManager D-Bus directly, so no subprocess is needed.
- **A `Timer` for the clock.** `SystemClock` already aligns to the minute (or second) boundary, and it can be switched off while hidden.
- **Custom QML tray menus** (Omarchy's `QsMenuOpener` popup). That is a lot of code; `UseQApplication` costs about 5 MiB and gives native menus.
- **`FolderListModel` on a missing directory.** It falls back to the working directory (observed: the registry listed `bin docs nix …`). The user plugin dir is now probed first: a `FileView` load error of `NotAFile` means the path is a directory. The model is created only when the directory exists.
- **The GL scene graph.** Without blur or shaders (§6) it buys nothing and costs about 85 MiB RSS. Users can still set `QT_QUICK_BACKEND`.
- **`DropExpensiveFonts`.** No measurable gain (178 MiB with it vs 173 MiB without, within noise).
- **Shipping the §5.3 service ids in `default/shell.json` now.** They would log "unknown plugin" until plan 010 lands.

### Open risks

- **Over the §6 budget.** Idle RSS of 178 MiB exceeds the < 150 MB budget; even a bare Quickshell is 122 MiB here. PSS is 126 MiB. Either the contract measures PSS, or it raises the budget, or the tray (about 20 MiB) leaves the default bar. That is an owner decision.
- **Outside-click close is unverified live.** No pointer injection tool is installed (`ydotool`/`wlrctl` are absent). It relies on `HyprlandFocusGrab.cleared`.
- **Workspace click dispatch is not exercised by a real click.** Only the dispatcher string was verified.
- **Overlay plugins have no host here.** The `overlay` kind is validated and scaffolded, but nothing instantiates overlay plugins in this slice. Plan 010 (OSD, lock) needs that host, or must pair `overlay` with a `service` that owns the window.
- **Late-created files.** A `shell.json` or theme file created after the shell started is only picked up by `haseen shell ipc shell reload` (a FileView limitation).
- **The scratch `XDG_CONFIG_HOME` used in the smoke** hid the icon theme, so one tray icon rendered as the missing-icon checkerboard. Not checked with the real config.
