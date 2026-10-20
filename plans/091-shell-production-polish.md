# Plan 091: Shell production polish

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (touches the lock screen, the greeter, the notification daemon and the compat hosts; every fix is held by a test or a static check, and the lock still fails closed)
- **Depends on**: 005 010 011 025 026 027 036 048 061 074
- **Category**: shell
- **Planned at**: 2026-10-20, owner request: "go through the code, polish it, make it production ready, focus on the shell, then deploy it to IO"
- **State**: DONE 2026-10-20

## Method

1. Baseline on `9b6ec60`: `tools/lint.sh` OK, `tools/check-docs.sh` OK,
   `tests/run.sh` 14,237/14,239. The two failures (`test-menu-back.sh`,
   `test-themegen-keys.sh`) are the checkout path, not the code: their
   Quickshell IPC socket under `tests/.out/…/run/quickshell/by-id/…/ipc.sock`
   passes the 108-byte `sun_path` limit in a long checkout path. Both pass in
   a shorter one.
2. Runtime evidence: IO's journal (6 h of the installed shell) and a nested
   run of `main` (`tools/nest-launch.sh`, scratch HOME, every panel opened
   over IPC: 16 log lines, 200 MiB RSS).
3. Five read-only reviews in parallel (shell core; `Compat/`; menu, network,
   themegen, weather, security, clipboard, battery, tray, lock, gestures, ai;
   prayers and pager; the 31 small plugins), each finding checked against
   the code and the installed Quickshell qmltypes. No P0 was found: the lock
   fails closed, no launcher provider reaches a shell, and every Compat
   `sh -c` runs only the plugin's own command.
4. Fixes by file ownership, each with the test that holds it.

## Runtime findings

- **The lock marker locked new shells.** `haseen.lock` records "a lock is
  held" in `$XDG_RUNTIME_DIR/haseen-lock-held`, which outlives a compositor.
  luna held a stale `1` from 2026-10-08, and the nested run took the lock at
  start ("the previous shell died holding the lock"). The marker now names
  the Hyprland instance (`1 <HYPRLAND_INSTANCE_SIGNATURE>`); a marker from
  another instance is cleared, not obeyed. A bare legacy `1` is still obeyed
  (fail closed). Test: `test-lock.sh` "another instance's marker does not
  lock", "and is cleared", "this instance's marker takes the lock back".
- **IO's journal: 1,183 `QLocalSocket::ServerNotFoundError` in 6 h.** Not
  haseen code: the owner's `t1nk33r.wooting` and `io.github.rvcabc.logitech`
  plugins retry sockets of daemons IO does not run. Handled at deploy (both
  disabled on IO, where their devices are absent).
- **IO's journal: `KeyboardPanel.qml:196` "depends on non-bindable
  properties".** Fixed below (Compat).

## Fixes

### Shell core and shared widgets

- `Haseen/Widgets/BarButton.qml`: labels are plain text (they carry SSIDs,
  model ids and titles; a tag must not render or fetch an image); an optional
  `maxTextWidth` elides; the wheel accumulates `angleDelta`, so touchpads and
  hi-res wheels scroll (Qt's `QWheelEvent` contract).
- `Bar.qml`: a right click that falls through a widget no longer toggles
  arrange mode; only empty bar space does (architecture §5.3).
- `Haseen/Sidecar.qml`: a daemon that cannot start resets `_starting`, so a
  later consumer retries; unsubscribe goes by what this connection
  subscribed, so a consumer that leaves before the first frame stops the
  sampler (§5.6).
- `FrameTextColor.qml`: a helper that cannot start falls back to the theme
  foreground, as a failing one already did.

### Greeter and plugin CLI

- `greeter/GreeterSession.qml`: the password typed before greetd asks is
  queued and answered, not dropped (every keyboard login needed it twice);
  switching user cancels the open greetd session; the pending-login Timer is
  marked and drops the password after use. `tests/test-shell.sh`'s Timer
  check now also matches `property Timer x: Timer {` and refuses a `{` on
  the next line. Tests: `test-greeter.sh` (one Enter answers; a user switch
  cancels), `test-shell.sh`.
- `bin/haseen-plugin-restore`: `--prune` removes only symlinks into
  `.repos/` and asks for each; a real directory is replaced only after a
  `confirm`. It used to `rm -rf` plugins scaffolded by `haseen plugin new`.
  Test: `test-registry.sh`.
- `bin/haseen-plugin-update`: every installed plugin pinned to the moved
  repository is validated; one failure rolls the checkout back. Snapshotting
  the old pins (the review's suggestion) was rejected: it covered only
  `--all`, while `update one-id` also moves its siblings. Test:
  `test-registry.sh`.
- `shell/lib/registry.sh`: a lockfile `path` of `.`, `./x` or any `..` is
  refused, as `plugin install` refuses it. Test: `test-registry.sh`.
- `templates/bar-widget.qml`: no `color: Theme.foreground`, so scaffolded
  widgets keep `barForeground` on a transparent bar.

### Large plugins

- `bin/haseen-ai-chat`: the conversation goes to jq on stdin and the prompt
  through `--rawfile`, never argv (world-readable in `/proc`, and one
  argument is capped at 128 KiB, so long chats failed every send). Test:
  `test-ai.sh` "a conversation past 128 KiB is sent" (fails on the old
  script).
- `haseen.ai/Panel.qml`: Escape closes the model picker or stops the reply
  before it closes the panel (`Keys.onShortcutOverride`, as weather and
  themegen do); a reply still streaming when the panel closes is kept as
  "stopped" and saved synchronously; long model ids elide and the picker
  scrolls past half the panel; notices and placeholders are plain text.
- `bin/haseen-network-band`: the SSID from `iw` is decoded (`\xNN` for
  non-ASCII bytes, edge spaces and backslashes) before it is compared with
  nmcli's raw name, so "Café" or an Arabic SSID keeps its band picker. Test:
  `test-network-panel.sh` "an escaped non-ASCII SSID still finds its bands".
- `haseen.network/Panel.qml`: Suite-B, LEAP and dynamic-WEP networks say to
  use nm-connection-editor instead of opening a passphrase prompt that
  NetworkManager would refuse.
- `haseen.lock`: Escape cancels a password check that never answers (a hung
  PAM module held the field until `haseen lock release` from a TTY). PAM's
  `completed` counts only while an attempt is in flight, so a late `Success`
  after a cancel keeps the lock, and a late `Error` no longer overwrites
  "Unsupported PAM prompt". Test: `test-lock.sh` "a hung password check can
  be cancelled".
- `haseen.tray/TrayItem.qml`: tooltips wrap at 30 em.
- `haseen.menu/About.qml`: `about.png` is no longer read into memory on every
  menu open, only on entering About (`preload: false`).

### Prayers and pager

- `haseen.pager`: links, "Open link", "Join" and web cards open through
  `Apps.launch(["xdg-open", url])`, not `Qt.openUrlExternally`, which started
  the browser in the shell's cgroup (plan 074). A card opens
  `https://<source>/` only for web rows; a reverse-DNS app id used to pass as
  a host. Under DND or snooze the newest 16 muted notifications stay tracked,
  so a `replaces_id` update keeps its key, and `Store.closeInto` replaces a
  held row with the same key: a progress notification is one history row,
  not one per update evicting real ones. RTL titles keep their marks clear.
  Tests: `test-pager.sh` (`security.cjs`, `tst_security.qml`, static checks).
- `haseen.prayers`: the Horizon hero takes Friday's Jumu'ah offset and label
  from `Model.iqamaFor`, as the table and bar do; the wheel over a slider
  scrolls the panel unless the slider is held; settings writes wait 400 ms
  and carry each key's last value (one writer instead of several racing on
  `flock`), flushed when the plugin unloads; a stale city search is
  discarded. Tests: `test-prayers.sh`.

### Compat

- `Host.js`: a plugin rooted at a QtQuick or Layouts type (Row, RowLayout,
  MouseArea…) loads; only a missing base file counts as built-in, a broken
  one or a cycle is still refused.
- `OmarchyServiceHost.qml`, `DmsHost.qml`: the instance is destroyed before
  its component is released; DMS bar hosts release their components (they
  leaked one per bar rebuild).
- `Omarchy/Ui/KeyboardPanel.qml`, `PanelInput.js`: the input-mask binding no
  longer reads `PendingRegion.regions` (no notify signal); a tracked child
  count replaces it. This was IO's journal warning.
- `Runtime.qml`: plugin `close()`/`hide()` calls are guarded, so one throwing
  plugin cannot leave two popups open or skip cleanup; Omarchy click targets
  are shared per bar window, so with one Omarchy panel open a click on
  another bar widget reaches it.
- `Dms/Common/Proc.qml` (overlapping same-id runs each reach their callback),
  `Dms/Common/SettingsData.qml` (a stored write stops shadowing later
  shell.json edits), `Omarchy/Ui/ScreenMoveRemap.qml` (`geometryChanged`;
  `xChanged` does not exist), `Dms/Services/PluginService.qml` (warn once),
  `Tooltip.qml` (wraps), `DmsStartupGate.qml` (a check that never calls
  `done` is refused after 30 s), `bin/ydotool` (delays and leading-zero key
  codes read in base 10).
- `bin/haseen-plugin-settings`: the mirrored entry reaches jq on stdin, not
  argv.
- Tests: `test-compat-host.sh`, `test-compat.sh`, `test-compat-runtime.sh`,
  `test-compat-lifetime.sh`, `test-compat-tooltip.sh`, `test-compat-mirror.sh`,
  `test-compat-dms.sh`, `test-dms.sh`.

### Small plugins

- `haseen.session/Panel.qml`: "Reboot into <OS>" never rebooted: closing
  the panel freed it and killed its own `pkexec haseen-boot-next` Process.
  The row now runs detached (`bash -c 'pkexec "$0" "$@" && exec systemctl
  reboot'`, id and label as argv). `bin/haseen-boot-next` calls
  `haseen-boot-list` by its own directory, since pkexec resets PATH and the
  default prefix is `/usr/local`. Test: `test-boot.sh` (system PATH only).
- `haseen.calendar/Panel.qml`: takes focus on open, so its keys work.
- `haseen.screensaver/Service.qml`: dismiss keeps the launcher watching, so a
  terminal Hyprland opens after the dismiss is still closed.
- `haseen.polkit/Service.qml`: Escape cancels from a window `Shortcut`
  (the field is disabled while no answer is required); panel buttons use
  `Theme.foreground`, as do the notifications panel's.
- `haseen.keybinds/Overlay.qml`: Escape is a window `Shortcut` (`Keys` on a
  `PanelWindow` never attached); the `columns` setting now lays sections out
  in balanced columns, a section never split; clicks on the card's margins
  no longer close it. Test: `test-keybinds.sh`.
- `Haseen/Paths.qml`: `fileUrl` percent-encodes each segment (a `#`, `?` or
  `%` in a file name broke thumbnails), as `Compat/Omarchy/Commons/Util.qml`
  already did; `haseen.themepicker/ThemeCard.qml` uses it.
- `haseen.osd` (first volume change after a default-device switch),
  `haseen.emojisearch` (a missing or empty `emojis.json` says so instead of
  "Loading emoji…" forever), `haseen.agents` (a scan that cannot start ends
  the "Looking…"), `haseen.themepicker` (notice width; `printErrors: false`
  on `theme.name`, which a fresh install lacks), `haseen.background`
  (`sourceSize.height`; `printErrors: false`), `haseen.sysusage` (`warnAt`
  honoured; the sampler stops while the cell is parked in the overflow;
  `qs ipc --pid`), `haseen.bluetooth` (`ScriptModel`, so discovery updates no
  longer rebuild rows mid-click; long device names elide),
  `haseen.imagepicker` (a user-configured command goes through
  `Apps.launch`). Tests: `test-widgets-a.sh`, `-b`, `-c`, `test-surfaces.sh`,
  `test-launcher-providers.sh`, `test-indicators.sh`.
- Skipped: one shared `gdbus monitor` for the privacy widget across screens
  needs a service plugin and a manifest change, not a polish fix.

## Not changed

- The two path-length test failures: the tests are right; a long checkout
  path is the cause. Recorded here, not worked around.
- Hijri dates change at civil midnight, matching AlAdhan and Umm al-Qura
  civil dates (`test-prayers.sh`); the review flagged it and withdrew it.
- The greeter's `authenticate()` cancel-then-create race and the doubled
  `Greetd.respond("")` for informational messages: pre-existing, harmless
  in tests, left for a greeter plan.
- The owner's `~/.config/omarchy/plugins/` and the third-party plugins in
  `~/.config/haseen/plugins/` are untouched; their socket retries are
  theirs to fix.
