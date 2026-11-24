# Plan 196: the shell answers when a role has no plugin, and eight more audit fixes

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. Two IPC functions now return a string, and their callers
  read it; an old answer (empty, or a PID) means what it meant before. The
  greeter refuses a tree it used to accept, which only a checkout trips.
- **Depends on**: 011 (DMS compat), 019 (screensaver), 025 (notifications),
  036 (greeter), 054 (the ydotool shim), 071 (menu select)
- **Category**: shell
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2026-11-24; this is its shell group)
- **State**: DONE 2026-11-24 (the tests named below; review and merge are
  the coordinator's)

The audit ran at `2f7f472a`. Every finding was checked again on `9a9e82ab`
(main after plans 182 to 184) and still held there. Line numbers below are
`9a9e82ab`'s. Two of the nine findings share a cause (1 and 2: a role with no
plugin is answered as if it had one).

## 1. `lock lock` succeeds when nothing locked

**Evidence.** `shell.qml:103-112` `routeRole` returned nothing; when
`Plugins.callRole` found no instance (`Haseen/Plugins.qml:257-263`) it only
wrote `console.info(... "() ignored")` (`:111`). The `lock` target's
`function lock(): void` (`:462`) called it, so `qs ipc call lock lock` exited
0 with haseen.lock off, failed or not loaded yet. Two callers decide on that
exit status: `bin/haseen-system:127` (`haseen shell ipc lock lock 2>/dev/null
|| loginctl lock-session`) and `bin/haseen-lock-before-sleep:68` (`|| warn`).
Neither fallback could run while the shell was up. The menu's Lock
(`system.lock`) and Omarchy's lid-close shim both go through
`haseen system lock`.

**Fix.** `routeRole` returns whether anything took the call. `lock()` returns
`ok` or `unavailable`. `haseen system lock` asks logind unless the answer is
something other than `unavailable` (an empty answer, which DMS's
`ipc-translate` gives, still counts as locked). The sleep lock warns
"no plugin provides the lock … sleeping unlocked". Architecture §5.5 lists the
answer.

**Tests.** The new `tests/test-shell-routes.sh` cuts `routeRole`, `lock()` and
`select()` out of `shell.qml` and runs them in Quickshell against a stand-in
`Plugins` singleton, called through `qs ipc call` the way the CLI calls them:
no plugin answers `unavailable`, a lock plugin answers `ok`. On `9a9e82ab`
6 of its 12 checks fail. `tests/test-omarchy-restart.sh` checks the four
answers `haseen system lock` can get (`unavailable`, `ok`, empty, no shell).
`tests/test-sleeplock.sh` checks the warning.

**Rejected.** Throwing from `lock()` so `qs` exits non-zero: the caller could
not tell "no plugin" from "no shell", and a throw is logged as a shell error.
Running `loginctl lock-session` from the shell itself: the shell would then
do the CLI's job.

## 2. `menu select` answers a PID when no menu took the request

**Evidence.** `shell.qml:383-389` returned `Quickshell.processId` every time,
whether or not `Plugins.callRole("menu", "pick", …)` reached a menu, now or in
its `Qt.callLater` retry. `bin/haseen-menu-select:92-99` takes a live PID to
mean "still choosing" and waits on its FIFO until the shell exits. With
haseen.menu disabled (`haseen plugin disable` has no core-plugin guard) or its
panel failing to load, every picker built on it (the browser picker, the
keybind list, Omarchy's `omarchy-menu-file` and others) hung.

**Fix.** `select()` answers `unavailable` when `Plugins.provider("menu")` is
empty. When a menu is on but its panel still does not take the request after
the toggle, the shell writes the caller's FIFO the same `x` line a closed menu
writes (`haseen.menu/Panel.qml` `finishPick`), so the caller ends with
nothing chosen. `haseen-menu-select` stops with "no menu to show the list in"
when the answer has no PID in it.

**Tests.** `tests/test-shell-routes.sh`: no menu answers `unavailable`, a menu
answers the PID and has the request, a menu that never takes it answers the
PID and the FIFO gets `x` within 5 s. `tests/test-learn-keys.sh`: an
`unavailable` answer ends `haseen menu select` with status 1 (before the fix
it waited until `timeout`).

**Rejected.** Making the pick synchronous after the toggle: whether the panel
has loaded by then is the Loader's business, and the retry already covers the
normal case.

## 3. greetd could be pointed at a user-owned checkout

**Evidence.** `lib/greeter.sh:73` built the command from
`readlink -f "$HASEEN_PATH/../../bin"` with no ownership check.
`bin/haseen-setup-greeter:92-94` checked only Hyprland, qs and
`-d shell/greeter`, as the invoking user. `layers/desktop/layer.sh:234-262`
rewrote the config whenever its text differed, path included. The greeter
account runs that script, `common.sh` and the greeter QML; from a checkout
its owner can edit them (and capture other users' passwords), and from a
0700 home the greeter cannot reach them at all (no login screen). The same
kind of root-run wiring is refused elsewhere through `root_trusted_haseen`
(`lib/plymouth.sh:366-371`, `lib/omarchy-guard.sh:118-124`,
`layers/secureboot/secureboot.sh:42-47`).

**Fix.** `greeter_trusted` in `lib/greeter.sh`: `bin/haseen-greeter`
(`root_trusted_exec`) and `share/haseen`, `share/haseen/lib` and
`share/haseen/shell/greeter` (`root_trusted_dir`) must be root's alone,
every directory on the way included. `haseen setup greeter haseen` refuses
otherwise, and so does `setup greeter autologin` while the haseen greeter is
the choice (it rewrites the whole config). The desktop layer applied from a
checkout with the haseen greeter chosen keeps the config greetd has (an
installed greeter keeps its path) and writes tuigreet's where there is none.
Architecture's greeter section says so.

**Tests.** `tests/test-greeter.sh`: the checkout is refused and nothing is
planned; the same tree planted in the sysroot with root answering for its
owner (the `root_stat` stand-in of `tests/test-omarchy-guard.sh`) is
accepted; a group-writable `shell/greeter` is refused and named; autologin
keeps an installed greeter and refuses a checkout's. On `9a9e82ab` 7 of its
checks fail. `tests/test-desktop.sh`: the layer from a checkout keeps the
installed greeter's config, and with none writes tuigreet's.

**Rejected.** `root_trusted_haseen` itself: it checks a router
(`bin/haseen`) and `haseen-ROUTE` next to it, and greetd runs
`haseen-greeter` directly. Checking only that the `greeter` user can reach
the tree: that fixes the lock-out but not the password capture.

## 4. haseen.lock and haseen.idle declare no permissions

**Evidence.** `permissions` is what `haseen plugin info` and `validate` show a
reviewer (architecture §5.2; `agents/skills/haseen/plugins.md:139`).
haseen.lock declared `[]` (`manifest.json:45`) but runs `fprintd-list`
through a `Process` and writes its held marker with `FileView.setText`;
haseen.idle declared `[]` but runs `haseen-system suspend`
(`Service.qml:167`); haseen.osd declared `exec, files:read` but creates and
removes its lock-keys flag file (`Service.qml:245`). The verifier also found
haseen.audio, haseen.bluetooth and haseen.media running `qs ipc` through
`execDetached` with no `exec`.

**Fix.** haseen.lock: `exec`, `files:write`. haseen.idle, haseen.audio,
haseen.bluetooth: `exec`. haseen.media: `exec` added to `network`.
haseen.osd: `files:write` added.

**Tests.** `tests/test-shell.sh`: every built-in whose QML has a `Process`,
`execDetached(` or `Apps.launch(` declares `exec`, and every one that calls
`.setText(` declares `files:write`. On `9a9e82ab` it lists five plugins.
haseen.osd writes through a shell command, which a grep cannot see, so its
`files:write` is by hand.

## 5. The ttfx screensaver polled focus once a second

**Evidence.** `bin/haseen-screensaver:162-166` ran
`read -rsn1 -t 1 || ! screensaver_in_focus` in every terminal, and
`screensaver_in_focus` (`:136-138`) is `hyprctl activewindow -j | jq`: a
hyprctl and a jq per monitor every second for as long as the screensaver
showed. Architecture §6 allows no polling under 2 s, and no exception was
recorded (plan 019).

**Fix.** The terminal loop reads keys only. The service, which already follows
Hyprland's raw events while terminals exist (`Service.qml` `Connections`),
handles `activewindow` too: once the launcher has finished (it moves focus
between monitors while it works), focus on any other class runs
`haseen-screensaver --stop-unfocused`. That mode asks Hyprland once and closes
the terminals only if none has focus, so an event read late cannot close a
screensaver that has focus again.

**Tests.** `tests/test-ambient.sh`: `--ttfx-run` with focus elsewhere keeps
running and never calls `hyprctl activewindow`; `--stop-unfocused` keeps a
focused screensaver, plans the kill in a dry run, and closes only the
screensaver's terminals when focus is elsewhere. Service.qml cannot load
without a layer-shell backend (`No PanelWindow backend loaded`), so its
`_windowEvent` is cut out of the file and run in Quickshell against
stand-ins: a focus change while the launcher runs, and focus on a
screensaver terminal, send nothing; focus elsewhere after it sends one
`--stop-unfocused`; nothing once dismissed.

**Rejected.** Raising the poll to 2 s and recording an exception: still a
process pair per monitor every 2 s for hours. A `socat` event stream in each
terminal (Omarchy's old way): another dependency, and one stream per monitor
where the shell already has one.

## 6. The sleep lock exited 0 when dbus-monitor ended

**Evidence.** `bin/haseen-lock-before-sleep:64-77` ends in a `while read`
loop fed by `< <(dbus-monitor …)`. When the monitor ends, `read` gets EOF and
the script exits 0; bash does not check a process substitution's status.
`haseen-sleep-lock.service:9` has `Restart=on-failure`, so a `pkill
dbus-monitor` or a bus disconnect left the unit dead and every later sleep
unlocked. `tests/test-sleeplock.sh:22` asserted that exit 0.

**Fix.** After the loop the script dies ("dbus-monitor ended; the screen will
not be locked before sleep until this restarts"), so systemd restarts it. A
`systemctl stop` still ends it by signal, not through that line.

**Tests.** `tests/test-sleeplock.sh` expects status 1 and the message when the
stub monitor ends, and checks the unit keeps `Restart=on-failure`.

**Rejected.** `Restart=always`: it would also restart a script that exited on
purpose (a usage error).

## 7. haseen.notifications rendered a sender's app name and action labels as rich text

**Evidence.** `haseen.notifications/Service.qml:150` turns body markup off
because StyledText would fetch `<img>` sources, and the summary and body are
`Text.PlainText` (`NotificationCard.qml:163`, `:177`), but the app name
(`:101-112`) and the action label (`:205-212`) set no `textFormat`, so Qt's
AutoText rendered a sender's markup. `iconSource` (`:23-28`) passed any
`appIcon` containing `://` to the image, `https` included. haseen.pager, the
default daemon, already sets `PlainText` everywhere; this card only runs when
the user takes the pager out of `services`.

**Fix.** `textFormat: Text.PlainText` on both. `iconSource` takes an absolute
path (as a `file://` URL) or a `file://` URL, and resolves anything else as an
icon theme name. While testing, a bare path turned out never to load:
`IconImage` resolved it inside `qrc:` ("Cannot open:
qrc:/usr/share/icons/x.png"), hence the `file://` prefix. After review, the
card's `Image` reads `imageSource`, which applies the same rule to
`notification.image` and also lets through Quickshell's own `image://` URL.
Quickshell reads the `image-path` and `image_path` hints (both strings are in
`/usr/bin/quickshell`, next to `qsimage`, the provider it serves `image-data`
from), and a sender writes that string.

**Tests.** `tests/test-ambient.sh` creates the real card in Quickshell with a
stand-in notification: the app name and an action label carrying `<img>`
markup are plain text, an `https` icon is never the source, a `file://` icon
and a bare path are (as `file:///usr/share/icons/x.png`). For the image, an
`https` hint gives no source, an absolute path becomes a `file://` URL and an
`image://qsimage/` URL stays as it is.

## 8. The ydotool shim's dry run created files

**Evidence.** `Compat/bin/ydotool:84-87` ran `mkdir -p "$dir"`,
`exec {lock}>>"$held_file.lock"` and `flock` before any `DRY_RUN` check, so
`--dry-run` created `$XDG_RUNTIME_DIR/haseen/` and an empty lock.
Architecture §5.4 says the shim takes `--dry-run`, and `bin/haseen-context`
guards the same pattern with `if ! $DRY_RUN`.

**Fix.** The same guard: a dry run reads the held keys a real run left,
unlocked, and creates nothing. Architecture §5.4 says so.

**Tests.** `tests/test-compat-desktop.sh`: a dry run in an empty runtime
directory leaves it empty.

## 9. A toast that starts with `-` was read as a notify-send option

**Evidence.** `Compat/Dms/Services/ToastService.qml:17`, `Compat/bin/dms:77`
and `Compat/DmsStartupGate.qml:104` put the text straight after the options.
notify-send parses with GOption, which takes "-3°C outside" or "--- connection
lost ---" as an unknown option and shows nothing (the verifier reproduced this
with a GOption program of the same entries); `execDetached` drops the error.
`Haseen/Plugins.qml:221` builds the refused-plugin notice the same way, its
summary starting with the plugin's name.

**Fix.** `--` before the summary in all four.

**Tests.** `tests/test-compat.sh` and `tests/test-compat-desktop.sh` stand in
a notify-send that, like GOption, fails on an unknown option before `--`:
`dms ipc call toast warn "--- connection lost ---"` shows, and so does
`ToastService.showInfo("-3 C outside", "--- connection lost ---")` in
Quickshell; the startup gate's title follows `--`.

## Review

An independent Sonnet review of the first head approved it with three nits.

- The card's `Image` still took `notification.image` unchecked. Quickshell
  passes the `image-path` hint through, so a sender could name a remote
  image. Fixed: `imageSource` applies the `iconSource` rule (finding 7).
- Other notify-send callers still put user text first with no `--`
  (`bin/haseen-reminder-set:51`, `share/haseen/lib/gestures.sh:324`, the
  toggle scripts). Deferred. These callers are outside this group's
  findings, and about 36 files call notify-send, many of them owned by groups
  fixing in parallel. A follow-up should add `--` everywhere and lint for it.
- With the haseen greeter chosen, `autologin off` from a checkout is refused,
  and the error only talked about installing. The refusal stays, because the
  rewrite names the greeter command. The error now adds that
  `haseen setup greeter tuigreet` works from a checkout, and
  `tests/test-greeter.sh` checks for that text.
