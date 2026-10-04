# Plan 010: Shell system surfaces

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. Notifications, OSD, launcher, lock preview and session panel were verified live on a scratch instance. Not verified live: the polkit dialog (omarchy-shell owns the agent on this session), the real session lock, and display power-off. Those belong to plan 014.

## Why this matters

Without a notification server, OSD, launcher, lock, idle handling and a polkit agent this is a bar, not a desktop.

## Scope

Built-in plugins: `haseen.notifications`, `haseen.osd`, `haseen.launcher`, `haseen.lock`, `haseen.idle`, `haseen.polkit` and `haseen.session`.

## Acceptance

- Each one is exercised live on the session.
- The lock is tested with a PAM stub service, never with the real login.

## Execution record

Executed 2026-10-04 against quickshell 0.3.1 and Hyprland 0.56.2 (Lua) on the live Omarchy session. No commit (integrator).

### What changed

- **Overlay decision: services own their windows.** No overlay host was added to `shell.qml`, so this plan has no shared-file edit.
  - Each service keeps its surface in a `LazyLoader` that is active only while the surface is shown: notification popups, the OSD card, the polkit dialog and the lock preview.
  - `haseen.lock` uses `WlSessionLock`, and Quickshell creates its surfaces only while locked.
  - The `overlay` kind is still validated and scaffolded, but nothing hosts it. A user plugin that needs an overlay pairs it with a `service` that owns the window, as the built-ins do. Main approved this choice.
- `haseen.notifications` (service + panel, `provides: ["notifications"]`):
  - It runs a Quickshell `NotificationServer` with actions, images, plain text bodies and no persistence. Markup is off because `StyledText` would fetch `<img>` sources from senders.
  - Popups appear top-right, at most `maxPopups` (capped at 3), newest first. A `ScriptModel` keeps the other popups and their timers alive when a new one arrives.
  - Each popup has a single-shot timeout taken from the sender's `expireTimeout`, or the `timeout` setting for "server default". Critical and resident notifications have no timeout. The timer pauses on hover and restarts when a notification is replaced.
  - A popup that times out stays in the panel. A transient one is expired instead. History is capped at `historySize` and lives in memory only.
  - `toggleDnd()` hides every popup except critical ones. `clear()` dismisses everything. Clicking a card runs the `default` action.
  - `Panel.qml` lists the notifications newest first, with a DND toggle and a clear button. It reads the service through `Plugins.roles.notifications`.
- `haseen.osd` (service):
  - Volume comes from `Pipewire.defaultAudioSink` signals (`volumeChanged`/`mutedChanged`). The first reading of each sink only sets the baseline, so startup and sink switches do not flash the OSD.
  - Brightness comes from a `FileView` watch on `/sys/class/backlight/<dev>/actual_brightness`, not on `brightness`. The kernel backlight class calls `sysfs_notify()` on `actual_brightness` for every change, firmware hotkeys included, while `brightness` only sees writes from userspace. The device is the first entry of a `FolderListModel` over `/sys/class/backlight`, or `settings.backlight`.
  - A 1500 ms single-shot timer hides the card. The window has an empty input `mask`, so clicks pass through it.
- `haseen.launcher` (panel, `provides: ["launcher"]`):
  - Fuzzy filtering is in `Fuzzy.js`. The scores rank exact > prefix > word start > substring > in-order subsequence, over the name, the generic name (×0.8) and the keywords (×0.6). `noDisplay` entries are skipped.
  - Launching calls `DesktopEntry.execute()`.
  - Keys: type to filter, Up/Down/Tab to move, Enter to launch. Escape is handled by the panel host.
  - Every enabled `launcher-provider` plugin is created when the launcher opens and destroyed when it closes. Input that starts with a provider's `prefix` goes to that provider's `query()`.
  - The `=` calculator was skipped: it is optional, and evaluating arbitrary input is not worth the risk.
  - After a launch the panel closes itself through `QsWindow.window.closeRequested()`, the `PanelPopup` signal (see requested core changes).
- `haseen.lock` (service, `provides: ["lock"]`):
  - It uses `WlSessionLock` with one `LockView` per screen: clock, date, password field and status line.
  - Authentication goes through `PamContext`, `config: "login"` by default, with `pamConfig`/`pamConfigDirectory` settings. `login` exists on Arch, CachyOS and NixOS and is what hyprlock and swaylock use, so **no PAM file is shipped and the layer installs nothing into `/etc/pam.d`**.
  - It sends one answer per attempt. A second PAM prompt (OTP) aborts the attempt and shows the prompt.
  - `settings.preview` (debug, default `false`): `lock()` shows the same view in an overlay `PanelWindow` and never locks the session. Escape or a successful PAM answer closes it.
- `haseen.idle` (service):
  - Two `IdleMonitor`s, so the compositor counts and the shell holds no timer. After `lockAfter` (default 300 s) it calls the `lock` role. After `dpmsAfter` (default 330 s) it sends `hl.dsp.dpms({ action = "disable" })`, or `dpms off` outside Lua mode, and re-enables the displays on the next input. `0` disables either one.
  - `respectInhibitors` defaults to `true`.
- `haseen.polkit` (service): `Quickshell.Services.Polkit` exists in 0.3.1 (`/usr/lib/qt6/qml/Quickshell/Services/Polkit/`).
  - A `PolkitAgent` registers at `/org/haseen/PolkitAgent`.
  - During a request it shows a dialog with the message, the identity (click to cycle when there are several), the PAM prompt (echo follows `responseVisible`), the supplementary or error text, Cancel and Authenticate.
  - polkit accepts one agent per session. When another agent registered first, Quickshell logs `An authentication agent already exists for the given subject`, and that agent keeps answering.
- `haseen.session` (panel):
  - The actions are Lock, Log out, Suspend, Reboot and Shut down. With `settings.confirm` (default on), Log out, Reboot and Shut down need a second press.
  - Lock calls the `lock` role, falling back to `loginctl lock-session`. Log out is `Hyprland.dispatch("hl.dsp.exit()")`, the same dispatcher `hyprctl dispatch` sends, over the socket. Suspend, Reboot and Shut down are `systemctl suspend|reboot|poweroff` through `Quickshell.execDetached`.
- Debug IPC hooks, added after Main stopped key injection on the live session:
  - `haseen.launcher` (`settings.debugIpc`): `setQuery`, `down`, `accept`, `state`.
  - `haseen.session` (`settings.debugIpc`): `select`, `press`, `state`.
  - `haseen.lock`: `submit`, `close`, `state`. It is enabled only in preview mode, so a real lock never accepts passwords over IPC.
  - The hooks exist only while their panel or service is loaded.
- `default/shell.json` `services`: `haseen.notifications`, `haseen.osd`, `haseen.polkit`, `haseen.idle`, `haseen.lock`.
  - `haseen.lock` is added to the architecture §5.3 list because the `lock` role is only answered by a loaded service.
  - The panels (`haseen.launcher`, `haseen.session`, and the notifications panel) are not listed. They load on `launcher toggle` / `panel toggle`.
- `tests/test-surfaces.sh` (75 assertions) checks:
  - the manifests validate;
  - `provides` roles are unique, and every role `shell.qml` routes (`launcher`, `lock`, `notifications`) has exactly one built-in provider defining the routed functions;
  - every listed service id has a `service` entry, and every entry file declares `pluginId`/`settings`/`screen`;
  - no hex literals in the surfaces' QML and JS;
  - a Timer rule over the whole shell: an unmarked Timer needs a literal interval of at least 2000 ms, and a Timer whose previous line is `// haseen:ui-timeout` must be `repeat: false`. The checker is self-tested on five fixtures: three bad, two good;
  - each service `PanelWindow` sits in a `LazyLoader`, and the notifications plugin has no `FileView`/`Process`;
  - lock preview defaults to off and lock PAM to `login`;
  - the session commands.
- DMS coexistence: these are exactly the roles DMS claims. `haseen-shell.service` has `Conflicts=dms.service`, so only one shell runs.
  - Even side by side, the losing shell degrades without breaking. The D-Bus notification name and the polkit agent are first come, first served. Quickshell logs the failure, and the other services keep working.
  - This was observed: in the plain session (no scratch bus) the polkit agent failed to register against omarchy-shell's agent, and the rest ran normally.

### Evidence

- Static checks:
  - `/tmp/tools/shellcheck --severity=warning -x tests/test-surfaces.sh` and `bash -n`: clean.
  - `jq empty` on the 7 manifests and `default/shell.json`: clean.
  - qmllint with the `tools/lint.sh` flags over all shell QML: `Error-lines 0`. The remaining warnings on these plugins are the known artefacts: `[import]` of `qs.Haseen`, `PanelWindow` "not creatable", and Repeater `[required]`.
  - qmllint flagged `function move()` as shadowing `Positioner.move`; it was renamed to `shift()`.
- `tests/run.sh tests/test-surfaces.sh` → `75/75 passed`.
  - `tests/run.sh tests/test-surfaces.sh tests/test-shell.sh` → `237/237 passed` (75 + 162). The first run gave 234/237 on test-shell: three hard-coded `services` expectations (`'["me.svc"]'`, `'[]'`) assumed the old empty default. Main changed them to derive the list from `default/shell.json`.
  - Main changed `test-shell.sh:40` to accept `// haseen:ui-timeout` Timers.
- Live smoke: a second instance with scratch `XDG_CONFIG_HOME`/`XDG_STATE_HOME`, inside `dbus-run-session`.
  - `busctl --user status org.freedesktop.Notifications` showed `quickshell -n -p /usr/share/omarchy/shell` owning the name, so a scratch bus was required.
  - `PATH` started with fake `systemctl`/`loginctl` that only log, so no session action ever ran for real.
  - Final pass: own `XDG_RUNTIME_DIR` (symlinks to the `hypr`, `pipewire-0` and `wayland-1` sockets, `WAYLAND_DISPLAY` absolute), so `qs ipc` reached only this instance.
  - `shell plugins` → `roles: {"lock":"haseen.lock","notifications":"haseen.notifications"}`, `errors: []`.
  - Notifications:
    - Four `notify-send` calls (normal; critical; `-A yes=Yes -A no=No`; normal). Screenshot (viewed): 3 popups top-right, newest first, the action buttons, the critical card with the urgent border, and the first popup pushed out.
    - After 6 s only the critical popup remained (`haseen-notifications 360x245` → `360x70`).
    - `panel toggle haseen.notifications` showed all 4, newest first.
    - `notifications toggleDnd` and then a `notify-send` gave no new popup, while the panel listed it.
    - `notifications clear` → popup gone, and the panel read "No notifications".
  - OSD:
    - `wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+` → `haseen-osd 634,746 269x46`. Screenshot: speaker glyph, bar and `41%`. Then `1%-` restored `Volume: 0.40`, and the layer was gone after 1.9 s.
    - `brightnessctl set 5%-` → screenshot with the sun glyph and `95%`, so the `actual_brightness` inotify watch fires. Brightness was restored to 19393.
  - Launcher:
    - First pass, with keys: open listed the apps A–Z with icons; `firef` gave "No matches" (Firefox is not installed); `brow` plus Down moved the selection to the second row; `smoke.echo hello` routed to a scratch `launcher-provider` (`haseen plugin new smoke.echo --kind launcher-provider`); Enter logged `smoke.echo: picked hello` and the panel closed; Escape closed it.
    - Final pass, IPC only: `haseen.launcher setQuery chro` → `{"results":["Chromium"]}` (screenshot), and `setQuery brow` + `down` → `current: 1`. `panel close` removed the layer.
  - Session:
    - With keys: Down×3 + Enter armed "Reboot? Press again" (screenshot), and a second Enter logged `FAKE systemctl reboot`. Suspend logged `FAKE systemctl suspend` with no confirmation. Shut down needed 2 presses, then logged `FAKE systemctl poweroff`. Lock went to the `lock` role, which opened the preview.
    - IPC only: `select 4` + `press` → `{"armed":"poweroff"}` (screenshot), and a second `press` → `FAKE systemctl poweroff`, with the panel closed.
  - Lock preview with PAM stubs: `/tmp/haseen-surf/pam/haseen-stub-deny` (`auth required pam_deny.so`) and `haseen-stub-permit` (`pam_permit.so`), via `pamConfigDirectory`. The real `login` service was never used.
    - `lock lock` → `haseen-lock-preview 0,0 1536x864`. Screenshot: clock, date, password field and the preview notice.
    - Submitting with deny → "Wrong password" and the field cleared. Log: `Starting pam session … config "haseen-stub-deny" in dir "/tmp/haseen-surf/pam"` / `Failed to authenticate.`
    - Switching `pamConfig` live to permit and submitting → `Authenticated successfully.`, the preview closed, and the state was `{"preview":false,"sessionLocked":false}`.
    - Escape (first pass) and `haseen.lock close` both close the preview.
  - Idle: with `lockAfter: 3` (preview on), the lock preview appeared after 5 s of no input. Two earlier tries saw continuous user input and did not fire.
    - A standalone probe confirmed that `IdleMonitor` reports idle after its timeout, also when it is enabled and its timeout set after creation.
    - DPMS was not exercised: it would blank the user's display.
  - Polkit: the component loads. Registration on the live session failed with `An authentication agent already exists for the given subject` (omarchy-shell's agent), as designed. **The dialog is unverified live** (see open risks).
  - The instance log had no QML warnings from these plugins, apart from the PluginSlot double-load warning below.
- Idle RSS (software backend, scratch bus and runtime dir, 30 s idle, then 30 s CPU sample), two rounds each:

| config | RSS | PSS | CPU ticks / 30 s |
|---|---|---|---|
| `services: []` | 165940 / 166340 kB | 104929 / 108187 kB | 0 / 1 |
| default (5 services) | 171184 / 171376 kB | 109834 / 109904 kB | 1 / 1 |

  The delta is **+5.0 MiB RSS** (+1.7 to +4.8 MiB PSS), under the 10 MiB reporting threshold. The default shell is 167 MiB RSS, within the 200 MiB budget.

### Rejected

- **An overlay host in `shell.qml`.** Overlay plugins would need their own enable semantics in `shell.json`, and every surface here also needs service state (a D-Bus server, a PAM context, PipeWire signals). Services that own lazy windows need no core change.
- **Shipping `default/pam.d/haseen-lock`.** `login` already provides the right stack on all three targets. A haseen file would need root to install and would add an `/etc` file to keep in sync.
- **Watching `brightness`.** It misses changes made by firmware or the kernel; `actual_brightness` gets `sysfs_notify()`.
- **The `=` calculator provider.** Optional; evaluating arbitrary input is not worth the risk for v1 of the launcher.
- **`StyledText` notification bodies.** Remote `<img>` fetches would make every notification a tracking pixel.
- **`TapHandler` on notification cards.** Its passive grab also fired under the close and action buttons. A background `MouseArea` below the content fixes it.
- **Key injection for live tests.** After a stray `wtype` reached the user's terminal, every re-verification switched to the IPC debug hooks.

### Requested core changes

- **`PluginSlot.qml` loaded every entry twice (fixed by Compat during this plan).** Evidence before the fix: `qs log` showed `PROBE session panel created / destroyed / created` for one `panel toggle`, plus `IpcHandler … will not be used because another handler is registered for target haseen.session`. The cause was an `onUrlChanged` → `load()` that fired when the required `pluginId` landed, followed by `Component.onCompleted` → `load()`. After the fix, a scratch instance (IPC only: `panel toggle haseen.session`, `launcher toggle` + `setQuery chro`) logged no duplicate-handler warning, and the hooks answered (`{"current":"lock","armed":""}`, `{"results":["Chromium"]}`).
- **A documented panel close contract.** Launcher and session close through `QsWindow.window.closeRequested()`, the `PanelPopup` signal. Architecture §5.2 should name it, or the host should pass a `close()` callback.
- **`docs/architecture.md`:**
  - §5.3 should add `haseen.lock` to the default `services`.
  - §5.2 should say that `overlay` plugins pair with a service owning the window (no host).
  - §5.2 should say that `launcher-provider` plugins are instantiated by the launcher while it is open.
- **Desktop layer: polkit.** `haseen.polkit` is the agent in the haseen shell, so the desktop layer must not also autostart `hyprpolkitagent` while `active-shell` is haseen; the first one to register wins. With DMS, DMS's agent applies.

### Open risks

- **The polkit dialog is not exercised live.** omarchy-shell's agent owns this session, and polkit agents live on the system bus, so a scratch bus cannot isolate them. Verifying it needs a session without another agent, followed by `pkexec true`.
- **The real session lock is never engaged** (by design). Only the preview path and PAM stubs ran. The `WlSessionLockSurface` view is the same `LockView` component.
- **DPMS off/on is not exercised live.**
- **Locking before suspend** (logind `PrepareForSleep`) is not implemented. Suspend from the session panel does not lock first.
- **Outside-click close of panels** relies on the core `HyprlandFocusGrab`, and remains unverified without pointer injection.
