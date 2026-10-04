# Plan 011: Omarchy and DMS plugin compat adapters

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (API surface)
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. Live, 6 of the owner's Omarchy plugins and 6 DMS examples render. 7 plugins that use APIs outside the adapter's scope fail individually and are listed in `Plugins.errors`. Not exercised: tooltips and clicks (no pointer injection was used).

## Why this matters

Requirement 4. The owner has about 29 `t1nk33r.*` Omarchy plugins in waydots, and the DMS plugin registry is large.

## Scope

`shell/Compat/`: the Omarchy plugin imports and the DMS `qs.Common`/`qs.Services`/`qs.Widgets` subset, plus manifest adapters in the registry.

## Acceptance

- At least three real Omarchy plugins from waydots and three DMS examples from `quickshell/PLUGINS/` load and render live.
- Unsupported APIs fail per plugin.

## Execution record

Executed 2026-10-04 against quickshell 0.3.1 / Qt 6.11.2 on the live Omarchy session (isolated second instances). No commit (integrator).

### Survey (plugins using each API; scripts and tests dirs excluded)

| source | plugins | imports | kinds |
|---|---|---|---|
| owner `t1nk33r.*` (waydots) | 29 | `qs.Commons` 29, `qs.Ui` 28 | bar-widget 26 (entry `BarWidget.qml` 14, `Panel.qml` 12), service 9, panel 4, overlay 2 |
| Omarchy built-in `shell/plugins` | 30 | `qs.Commons` 29, `qs.Ui` 27 | bar-widget 13, service 8, panel 5, overlay 4, bar 1, menu 1 |
| DMS `quickshell/PLUGINS` | 17 | `qs.Common` 17, `qs.Widgets` 15, `qs.Modules.Plugins` 14, `qs.Services` 10, `qs.Modules.DankDash` 3 | widget 9 (incl. composites), launcher 4, dash/dashCard 2, daemon 1, desktop 1 |

- Omarchy `qs.Commons` singletons (owner / built-in): Style 28/27, Color 27/24, Util 13/17, Border 10/13. Most used members: `Style.space()` 934 uses, `Style.font.caption` 328, `font.bodySmall` 137, `font.body` 111, `Util.alpha` 103, `font.family` 92, `Color.accent` 88, `Color.urgent` 61, `cornerRadius` 59, `Color.foreground` 50, then `spacing.*` and `bar.iconCanvas/iconSlot/iconFont/statusSlot`.
- Omarchy `qs.Ui` types (owner / built-in): PanelSeparator 20/10, PanelKeyCatcher 18/12, Button 17/7, PanelSectionHeader 17/9, BarWidget 16/5, KeyboardPanel 16/11, BarIconButton 15/11, Panel 15/11, TextField 15/7, PanelActionButton 12/7, WidgetButton 12/3, BorderSurface 10/13, PanelHero 10/3, OpticalGlyph 8/2, CursorSurface 8/9, PanelToolTip 8/9, ToggleSwitch 6/6, ButtonGroup 6/1, … BarIndicator 0/1.
- Bar facade in the owner's simple bar widgets: `setting()` 35, `bar.shell` 13 (`serviceFor`, `toggle`), `barForeground` 8, `iconCanvas` 7, `fontFamily` 7, `run` 5, `urgent` 5, `broadcast` 4, show/hideTooltip, request/releasePopout 2.
- DMS: StyledText 13, PluginComponent 11, DankIcon 7, PluginSettings 7 (settings UI), DankButton 4, DankTextField 4, SelectionSetting 4, PopoutComponent 3, StyledRect 3, DankGridView 2, Dash*/Desktop* 2 each. Singletons: Theme 16 (37 distinct tokens; top: `fontWeightMedium` 31, `spacingM` 30, `surfaceText` 28, `primary` 28, `spacingXS` 25, `surfaceVariantText` 21, `fontSizeSmall` 19), ToastService 9, I18n 8 (`trFor` 44), SettingsData 2, SessionData 2, PluginService 1. PluginComponent members: `pluginData` 25, `popoutService` 19, `horizontalBarPill` 10, `verticalBarPill` 9, `pluginService` 6.

Scope: the bar-widget kind and each shell's bar-widget API. Provided: Omarchy `qs.Commons` {Style, Color, Util}, `qs.Ui` {BarWidget, WidgetButton, BarIconButton, BarIndicator, OpticalGlyph} and the PluginBarApi facade; DMS `qs.Common` {Theme, I18n, SettingsData}, `qs.Services` {PluginService, ToastService}, `qs.Widgets` {StyledText, StyledRect, DankIcon}, `qs.Modules.Plugins` {PluginComponent}.
Left out (a plugin using them fails alone): the Omarchy panel/popout kit (Panel, KeyboardPanel, PanelKeyCatcher, PanelHero, PanelSection*, Button, TextField, Toggle*, Dropdown, PopupCard, BorderSurface, CursorSurface, …), `Commons.Border`, IpcRegistry/ShellIpc, the Omarchy `service`/`panel`/`overlay`/`menu`/`bar` kinds and the plugin shell API (`bar.shell` is null, which is Omarchy's value when no shell API is bound); DMS popouts (PopoutComponent, popoutContent), DankButton/DankTextField/DankGridView/DankActionButton, settings UIs (PluginSettings, *Setting), control-center, dash, desktop, launcher and daemon surfaces, variants, translations, `visibilityInterval` polling (no timers) and vertical bars.

### What changed

- **Module resolution.** quickshell maps `import qs.X.Y` only to `<shell dir>/X/Y` (`src/core/qsintercept.cpp`: `qs:@/qs/…` → configRoot; the only import path is `qs:@/`; a qmldir on disk is read even for directories the scanner never saw). A probe confirmed that a plugin outside the shell dir resolves `qs.Commons` through a symlinked directory, singletons included. All code lives in `share/haseen/shell/Compat/`. Six relative symlinks at the shell root give the upstream names: `Commons`, `Ui` → `Compat/Omarchy/…`; `Common`, `Services`, `Widgets`, `Modules` → `Compat/Dms/…`. Each target holds a real `qmldir` with the upstream module name. Native code never imports them (tested).
- `Compat/Manifest.js` (`.pragma library`): `adapt(dirName, manifestText, pluginText)` → `{compat, upstreamId, id, manifest, problems, unsupported}`.
  - Omarchy is a `manifest.json` with an `entryPoints` object and no `entry`. `kinds` is filtered to bar-widget, and `entryPoints.barWidget` becomes `entry["bar-widget"]`. `barWidget.defaults` and `schema` become native `settings`. Other kinds go to `unsupported`; with no supported kind the plugin is refused.
  - DMS is a `plugin.json`. The id must match `^[a-zA-Z][a-zA-Z0-9]*$`, and the registry id is `dms.<kebab>` (e.g. `dms.example-startup-check`). The widget surface comes from `components.widget`, or from a single `component` whose `type` implies a widget (DMS's `_deriveLegacySurface`), with `./` stripped. Permissions map `process` → `exec` and `network` → `network`. Other surfaces go to `unsupported`; with no widget the plugin is refused.
  - The adapted manifest then goes through the native `validate()`.
- `Haseen/Plugins.qml` (compat additions):
  - It imports the adapter and scans `~/.config/omarchy/plugins` and `~/.config/DankMaterialShell/plugins` read-only, after the user and built-in dirs. An `OptionalDir` inline component replaces the user-dir probe and serves all three optional dirs.
  - Each directory reads `manifest.json` and/or `plugin.json`: the user dir both, built-in and omarchy dirs the manifest only, the dms dir `plugin.json` only.
  - Records gain `compat`, `upstreamId` and `unsupported`, and the registry is keyed by the adapted id (first wins, `overrides` set).
  - `componentUrl()` returns `Compat/OmarchyHost.qml` or `Compat/DmsHost.qml` for compat records; the new `entryUrl()` returns the plugin file. `describe()` shows `compat` and `unsupported`.
  - `reportError()` dedupes (one entry per bar/screen) and logs through `warnOnce` with the same key as the ready-time log, so every failure is exactly one log line.
- `Compat/OmarchyHost.qml`:
  - It creates the barWidget entry via `Compat/Host.js` (`Qt.createComponent` + `createObject`). A compile error yields its first error line, e.g. `Panel.qml:290:5: PanelKeyCatcher is not a type`. The report is deferred so it never re-enters PluginSlot's url binding.
  - It injects `bar`, `moduleName` and `settings` (bound). `bar` is the PluginBarApi facade: Theme colours, fontFamily, position, barSize = `Config.barHeight`, tooltips, the click-target list, `moduleWidgets` across screens via `Host.js`, and `run()` through `bash -lc` like Omarchy. Popouts log once, and `shell` is null.
  - `Compat/Tooltip.qml` is a lazy PopupWindow for `bar.showTooltip`.
- `Compat/DmsHost.qml` creates the widget component and sets `pluginId` (the DMS id, which plugins pass to `savePluginData`), `pluginService`, `section`, `parentScreen`, `barConfig` and the bar thickness. It re-runs `loadPluginData()` when shell.json settings change.
- Omarchy modules (MIT notice in each header):
  - `Commons/Style.qml`: rem scaling of `Theme.fontSize`, spacing/font/bar tokens, state fills, `space()` and `duration()`. Nothing is polled.
  - `Commons/Color.qml` maps palette roles and surface groups to Theme tokens; `Commons/Util.qml` holds pure helpers.
  - `Ui/BarWidget`, `WidgetButton`, `BarIconButton`, `BarIndicator` and `OpticalGlyph`, with the hex-coloured debug outlines removed.
- DMS modules (MIT notice in each header):
  - `Common/Theme.qml` maps 37 Material tokens onto Theme and provides `barIconSize`/`barTextSize`. `I18n.qml` is the identity.
  - `Common/SettingsData.qml`: pluginData is shell.json `plugins.<id>.settings` plus the values saved this session (in memory only).
  - `Services/PluginService.qml` saves and loads data and emits `pluginDataChanged`; variants log once. `Services/ToastService.qml` uses `notify-send`.
  - `Widgets/StyledText`, `StyledRect` and `DankIcon`. `icons.js` renders a ligature when Material Symbols Rounded is installed; otherwise it maps 66 Material names to Nerd Font MD codepoints (from nerd-fonts `glyphnames.json`), with a puzzle glyph for unknown names.
  - `Modules/Plugins/PluginComponent.qml` draws the horizontal pill in a hover cell, runs `pillClickAction`/`pillRightClickAction` with DMS's calling convention and runs `visibilityCommand` once per change. The cc*, popout and variant properties are declared only.
- `shell/lib/plugin.sh`:
  - New: `plugin_compat`, `PLUGIN_ADAPT_JQ` + `plugin_adapt` (the jq twin of Manifest.js), `plugin_manifest`, `plugin_id_of` and `plugin_index`.
  - `plugin_dir`, `plugin_ids` and `plugin_resolve` search the Omarchy and DMS dirs (jq only for `dms.*` ids). `plugin_origin` returns `omarchy` | `dms` | `user:<compat>`.
  - `plugin_check` validates the adapted manifest, adapter problems first. `plugin_field` and `plugin_permissions` read the adapted manifest.
- Core changes approved by Main:
  - `bin/haseen-plugin-info` and `bin/haseen-plugin-enable` read the adapted manifest (`plugin_manifest`/`plugin_field`).
  - `PluginSlot.qml`: a loaded slot is always visible. Hiding it left widgets that use `implicitWidth: visible ? w : 0` (e.g. t1nk33r.window-title) stuck at 0 forever. It also loads exactly once per distinct url, only after `Component.onCompleted` and never for an empty pluginId (this fixes the double build Surfaces found).
  - `BarSection.qml`: bar slots get `width = item.implicitWidth`. Row neither positions nor spaces zero-width children, so a 0-width widget adds no gap.
- `tests/test-compat.sh` (new).

### Evidence

- `tests/run.sh tests/test-shell.sh tests/test-compat.sh` → `270/270 passed`; `tests/run.sh tests/test-core.sh` → `32/32 passed`.
  - One earlier run showed 13 test-shell failures because another agent was running the same suite into the shared `tests/.out/shell-*` dirs. Rerun alone, everything passes.
  - test-compat covers:
    - the six symlinks and qmldir module names, no native import of the six names, no hex in Compat, and the upstream notices;
    - Omarchy and DMS adaptation in the CLI: ids, kinds, entry, settings conversion, unsupported lists and permissions;
    - refusal of Omarchy manifests without kinds, service-only, with an escaping entry, an id/dir mismatch, a missing entry file or a missing name;
    - refusal of DMS plugins that are launcher-only or daemon-only, or have a bad id, a missing name or invalid JSON;
    - `plugin list` origins (`omarchy`, `dms`, `user:dms`, invalid), the adapted entry/settings in `plugin info`, `plugin enable dms.…`, and a user copy beating the Omarchy dir;
    - Manifest.js run headless (`/usr/lib/qt6/bin/qml`, offscreen, `QT_FORCE_STDERR_LOGGING=1`) over the same 17 fixtures, with results equal to the jq adapter.
- `/tmp/tools/shellcheck --severity=warning -x` on plugin.sh, test-compat.sh and haseen-plugin-{list,info,enable} → rc 0, and `bash -n` is clean. qmllint (tools/lint.sh flags) over all Compat QML and Plugins.qml gave 0 `Error:` lines; only unresolved-import and qmltypes warnings remain. No JSON files were added.
- Nix: the first `np build`, run while two symlink targets were still empty dirs, failed in `noBrokenSymlinks`, which showed that `lib.fileset` keeps the symlinks. With files in place, `/tmp/tools/np build "path:$PWD#haseen"` succeeds. In the result, `share/haseen/shell/{Commons,Ui,Common,Services,Widgets,Modules}` are relative symlinks resolving to the Compat dirs (`Ui/` lists BarIconButton … qmldir). No change to `nix/package.nix` is needed.
- Live smoke:
  - Setup: a second instance with scratch `XDG_CONFIG_HOME`/`XDG_STATE_HOME` and a scratch `XDG_RUNTIME_DIR` that symlinks the Wayland, Hyprland and PipeWire sockets, so IPC never crosses instances. No keyboard or pointer injection. 10 owner plugins were copied into scratch `omarchy/plugins`, 9 DMS examples into scratch `DankMaterialShell/plugins`, and DashCounterExample into scratch `haseen/plugins`.
  - Screenshot (grim, viewed). The bar sat at the bottom because Omarchy crash notifications covered the top right. 6 Omarchy and 6 DMS plugins render.
    - Left: `1 2 3 4 · foot` (**t1nk33r.window-title**), `boregard` (dms.example-startup-check), `Control Center` (dms.popout-control-example).
    - Right, DMS: `toggle 0` (dms.control-center-example); a magenta swatch `#ff00ff` (dms.color-demo, colour taken from shell.json settings via pluginData); `Default Text` (dms.example-variants); `counter 0` (dms.dash-counter-example from the user dir).
    - Right, Omarchy: `↓ 190K ↑ 3.9K` (**t1nk33r.nettraf**); a pacman glyph with `3` (**t1nk33r.updates**, `alwaysShow` from shell.json); a shield (**t1nk33r.omavet**); gears (**t1nk33r.settings**); a layout thumbnail (**t1nk33r.workspace-layout**).
    - Then the native tray, audio, network and battery.
  - `ipc call shell plugins` → `ready: true`, every compat record with `compat`, `origin` and `unsupported` (e.g. `dms.dash-counter-example` has origin user and unsupported `["dms:dash","dms:dashCard"]`; `t1nk33r.omavet` has unsupported `["service","panel"]`).
    - There were exactly 7 errors, each logged once:
      - `t1nk33r.lock: omarchy: no supported kind (has service; …)`
      - `dms.launcher-example: dms: no bar widget surface (has launcher; …)`
      - `t1nk33r.agents: omarchy: Panel.qml:290:5: PanelKeyCatcher is not a type`
      - `t1nk33r.tailscale: omarchy: Panel.qml:10:1: Panel is instantiated recursively`
      - `dms.attached-panel-example: … DankButton is not a type`
      - `dms.example-composite: … DankGridView is not a type`
      - `dms.example-emoji-plugin: … DankGridView is not a type`
    - The shell stayed up. The missing type reported varies between runs, because Qt names one of several.
  - Native bar unchanged: a scratch config with `haseen plugin disable haseen.battery`, then a scratch `smoke.zero` widget (implicitWidth 0) placed between audio and network. The before and after screenshots are byte-identical (md5 `897802fa…`), so no gap appears.
  - Panel loads once: a scratch panel plugin logs its creation and owns an IpcHandler. `panel toggle smoke.probe` twice (with a close between) logged `PROBE … created`, `destroyed`, `created`, `destroyed`. `smokeprobe ping` → `pong`, and there was no duplicate-IpcHandler warning.
  - `haseen plugin list` on the scratch config shows the `omarchy`, `dms` and `user:dms` origins, and `invalid` for t1nk33r.lock and dms.launcher-example.
- Idle RSS (software backend, 35 s idle then a 30 s CPU sample, two rounds, same tree):

| config | RSS | PSS | CPU ticks / 30 s |
|---|---|---|---|
| default bar, no plugin dirs | 184 MiB (188660 / 189036 kB) | 133 MiB | 0–1 |
| + user dir with 1 plugin, nothing listed | 196 MiB (201124 kB) | 145 MiB | 0 |
| + Omarchy dir (10 plugins), nothing listed | 189 MiB (193992 kB) | 138 MiB | 1 |
| + user, Omarchy and DMS dirs, nothing listed | 199 MiB (203440 / 203660 kB) | 147 MiB | 0–8 |
| + 13 compat widgets rendered, 7 failing | 212–217 MiB (217044 / 222164 kB) | 158–163 MiB | 3 |

  - Scanning the compat dirs costs about 5 MiB. The 13 adapted widgets cost about 13–18 MiB, which is over the §6 10 MiB note threshold; the full scratch config also goes past the 200 MiB budget.
  - The ~12 MiB for an existing user plugin dir comes from the pre-existing user-dir scan, not from compat.
  - The CPU ticks come from the plugins' own timers (nettraf 3 s, updates); haseen itself adds none.

### Rejected

- **Module dirs at the shell root holding the code.** The root would mix native and compat files; symlinks keep all code in `Compat/`.
- **qmldir redirects (`Style 1.0 ../Compat/…`).** The type URLs would point into Compat, where a sibling's implicit directory import sees singletons as plain types.
- **An extra QML import path (`QML_IMPORT_PATH`).** It needs an absolute path in the environment before the engine starts; `//@ pragma` cannot compute it, and bin/haseen-shell-run is core.
- **Rewriting plugin imports at load** (`Qt.createQmlObject` on patched text). Plugins have many files and local types that Qt loads itself.
- **Gating the host width on `widget.visible`.** The slot hid the widget, so the width stayed 0; the first live run rendered no compat widget.
- **Persisting DMS `savePluginData` into shell.json.** The running shell never writes shell.json (the CLI owns it), so saved values last for the session.
- **A `Timer` for DMS `visibilityInterval`.** Not allowed by §6; the command runs once per change.

### Open risks

- **Runtime-only API gaps.** For example, omaprayers and workspace-layout lazily load a `Panel.qml` that uses KeyboardPanel. The plugin's own Loader prints a QML warning and the bar widget still renders, but these gaps are not in `Plugins.errors`.
- **Tooltip popups and pill clicks are not exercised**, because pointer injection is forbidden. `run()` and the pill actions were only reviewed.
- **Owner plugins not copied into the smoke** (deepseek, todoist, omarr, privacy, nook, …). By the survey, the ones whose entry only uses the provided types should load, and the Panel-entry ones should fail cleanly. Not verified live.
- **Portal crashes on the host.** The live instances coincided with repeated "Process crashed: xdg-desktop-portal-hyprland" notifications (each qs logs "Failed to register with host portal"). Several agents' instances were running, so the cause is not isolated.
