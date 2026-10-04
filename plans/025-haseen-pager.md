# Plan 025: haseen.pager, the default notification daemon (port of omapager)

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 019
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (bring luna's Omarchy plugins in as built-ins)
- **State**: DONE 2026-10-04 (default notification daemon; live single-owner check of org.freedesktop.Notifications)

## Why this matters

The owner runs njpatel's omapager on luna instead of Omarchy's own
notification service: cards stack per source, codes and links become buttons,
sources can be snoozed, and what quiet held back stays readable. haseen's own
`haseen.notifications` is a plain popup list. The owner wants omapager as a
haseen built-in, under haseen names, as the default daemon.

## Design

- **Plugin** `haseen.pager` (`share/haseen/shell/plugins/haseen.pager/`), kinds
  `service` + `bar-widget` + `panel`, `provides: ["notifications"]`.
  Upstream's panel lived inside its bar widget; haseen hosts panels itself
  (lazy `PanelPopup`, one at a time), exactly as `haseen.notifications` does, so
  the panel half became `Panel.qml`. The bar widget opens it with
  `panel toggle haseen.pager`.
- **Do Not Disturb** is the shared `dnd` flag: `doNotDisturb: Flags.dnd`,
  writes only through `Flags.set("dnd", …)`. `notifications toggleDnd` and
  `notifications clear` reach `toggleDnd()`/`clear()` through the role
  (shell.qml `routeRole`); the plugin registers no `notifications` IpcHandler.
- **No Python** (architecture section 6): upstream's helpers are replaced, not
  carried.
  - Store: `Store.js` holds the rules, `Service.qml` writes
    `$HASEEN_USER_STATE/pager/{live,history,quiet}.json` with `FileView`
    (directory created `0700`).
  - Icons: resolved in QML (override files, icon theme, desktop entries).
  - KDE Connect replies: `kdeconnect.sh` (bash, `busctl`, `jq`; it writes no
    local state, so common.sh does not apply).
  - The Bubblewrap sandbox and `requireSandbox` go, because no helpers are left.
- **`fetchRemoteIcons` defaults to `false`** (upstream `true`). haseen is
  local-first, and the repo is published. When on, it fetches only
  `https://<host>/favicon.ico` with curl (HTTPS only, TLS 1.2+, 256 KiB, 8 s,
  no IP literals) into `$XDG_CACHE_HOME/haseen/pager/icons/`.
  `UPSTREAM.md` lists what upstream's Python fetcher did that this does not.
- **haseen.notifications becomes the fallback.** It is the least invasive
  change: default `services` lists `haseen.pager` instead (Main edits
  `default/shell.json`). It also steps aside on its own: while
  `haseen.pager` is in `services`, enabled and valid, its `NotificationServer`
  is not instantiated (an `Instantiator` with `model: superseded ? 0 : 1`; not
  a `LazyLoader`, because `test-surfaces.sh` pairs those with PanelWindows), and it unregisters the
  `notifications` role. haseen.pager reclaims the role if it is empty. So the two
  never claim `org.freedesktop.Notifications` at once, whatever the order.
- **Resources:**
  - The deck's layer surface exists only while cards are on screen, plus
    800 ms for the exit animation. Upstream kept a canvas mapped all the time.
  - Two `haseen:sample` timers (20 s): snooze expiry, gated on `anySnooze`, and
    the cards' relative time, gated on cards being shown.
  - Every other timer is a single-shot `haseen:ui-timeout`. The card's 100 ms
    countdown ticker became a single-shot expiry that banks paused time.
  - No `MultiEffect`.
- **Visual clutter:** the bar bell appears only while something is quiet or a
  screen-share offer waits (`alwaysShow` keeps it), as `haseen.notifications`'
  DND indicator does today.

Rejected:
- Keeping the Python helpers. That breaks the "no Python in the shell path"
  rule, and Pillow becomes a dependency.
- `haseen.notifications` deleted or emptied. The owner may want the plain
  daemon back, and DMS users' `panel toggle haseen.notifications` mapping
  (layers/dms) still names it.
- An always-on `notifications` IpcHandler in the plugin. That would collide with
  shell.qml's target.
- The in-panel preferences view (upstream `Picker.qml`). haseen has no plugin
  settings writer. Settings live in `shell.json` like every other plugin's.

## Execution record

### What changed

- **New `share/haseen/shell/plugins/haseen.pager/`:**
  - Upstream files:
    - `Detect.js`, `Layout.js`, `Markup.js`: notice header only.
    - `Security.js`: the Omarchy exec-argv policy is removed.
    - `Store.js`: the Omarchy exec-argv and the Python writer queue are removed; the disk-store rules are added.
  - Ported QML (Omarchy's `qs.Commons`/`qs.Ui` replaced by `qs.Haseen`): `Service.qml`, `Toast.qml`, `DeedButton.qml`, `Widget.qml`, `Panel.qml`.
  - New QML: `PagerButton.qml`, `SectionHeader.qml`, `TextCard.qml`, `IconDir.qml`.
  - Also `kdeconnect.sh`, `manifest.json`, `LICENSE` (upstream MIT, verbatim) and `UPSTREAM.md` (source, every change, everything dropped).
  - Tests: `tests/js-loader.cjs`, `baseline.cjs`, `security.cjs`, `tst_security.qml`, `tests/corpus/*.json`.
- **Renames:**
  - plugin id `njpatel.omapager` → `haseen.pager`
  - IPC target `omapager` → `pager`, debug target `omapager.panel` → `haseen.pager`
  - layer namespace `omapager` → `haseen-pager`
  - state `~/.local/state/omarchy/omapager/` → `$HASEEN_USER_STATE/pager/`
  - icon overrides → `$HASEEN_USER_CONFIG/pager/icons/`
  - setting `fullscreenOverlay` → `avoidFullscreen`
- **IPC target `pager`** (always on; every verb returns a string): `count()`,
  `probe()`, `cards()`, `clear()`, `dnd()`, `expand()`, `snooze(minutes)`,
  `snoozeAll(minutes)`, `unsnooze(key)`, `snoozes()`, `codes(state)`,
  `open(deckKey)`, `act(identifier)`, `offer(kind)`, `align(side)`,
  `stack(mode)`, `reply(text)`, `dismissOne()`, `dismissAll()`,
  `dismissShown()`, `invokeLast()`, `showHistory()`, `forgetHistory()`,
  `dismiss(summary)`, `recent(action)`, `refreshFullscreen()`.
  The debug target `haseen.pager` exists only with `settings.debugIpc` and while the panel is open: `state()`, `expand(key)`, `fold(section, open)`.
- **`haseen.notifications/Service.qml`:**
  - `superseded` (haseen.pager listed in `services`, enabled and valid);
  - the server is the delegate of an `Instantiator` with `model: root.superseded ? 0 : 1`;
  - `history` reads `serverHost.object`;
  - `_syncRole()` drops the role while superseded and takes it back afterwards.

  Nothing else changed. The strings `test-ambient.sh` and `test-surfaces.sh` check are intact.
- **`tests/test-pager.sh`** (new, 55 checks):
  - manifest validation, kinds, `provides`, the two providers of `notifications`;
  - defaults: `fetchRemoteIcons` and `debugIpc` false, `historyHours` 24;
  - the LICENSE notice, the entry contract, no hex colours, `Theme.barForeground`;
  - no Omarchy modules or `oma*` names in code, no Python, no shaders;
  - the timer rule (with single-shot ui-timeouts), DND through Flags, role functions;
  - the fallback guard and the kdeconnect.sh refusals;
  - `node baseline.cjs`, `node security.cjs`, and `qmltestrunner tst_security.qml`.

### Verification

- `tests/run.sh tests/test-pager.sh` → 55/55. Node is resolved before `sandbox` narrows PATH.
  - `node tests/baseline.cjs` → `baseline: passed`; `node tests/security.cjs` → `security: passed`.
  - `qmltestrunner -input tst_security.qml` (offscreen) → 6 passed, 0 failed.
- `/tmp/tools/shellcheck --severity=warning -x` and `bash -n` on `kdeconnect.sh` and `tests/test-pager.sh`: clean. `jq empty` on the manifest and corpus files: clean.
- qmllint with tools/lint.sh flags over haseen.pager, its tests and haseen.notifications: 0 `Error:` lines.
- `haseen plugin validate haseen.pager` → ok, plus the expected `network` warning (it applies only with `fetchRemoteIcons`).
- **Live smoke**: isolated scratch instances. The command was `dbus-run-session --config-file=tools/smoke-session.conf -- env XDG_CONFIG_HOME/XDG_STATE_HOME/XDG_CACHE_HOME=/tmp/pager-smoke/<v>/… QT_NO_XDG_DESKTOP_PORTAL=1 qs -p share/haseen/shell`, with the real `XDG_RUNTIME_DIR`. idle/lock/polkit/screensaver/nightlight/weather were disabled. Everything was driven by `qs ipc --pid <mine>` and `notify-send` on the private bus. I killed only my own PIDs, and I viewed every screenshot (`/tmp/pager-smoke/shots/`).
  - **The bus**: `busctl list` showed `org.freedesktop.Notifications` owned by my qs PID. `pager probe` → `role: haseen.pager`, `storeReady: true`.
  - **Grouping** (`01-collapsed.png`): Chat ×2, Builder with `-A build=Rebuild -A logs="Open logs"`, and Bank `-u critical` with "Your code is 938271". `cards` showed `app:chat` twice, `app:builder` with actions `["build","logs"]`, and `app:bank` with urgency 2. The screenshot shows three decks with the Chat card peeking behind, a red-bordered critical card with the key mark, "Clear all 4", and countdown lines.
  - **Expanded** (`02-expanded.png`): `pager expand` opened the front deck: Copy code and ✕.
  - **Actions** (`03-actions.png`): after `dismissOne`, Rebuild and Open logs show on the card. `pager act logs` → the sender printed `logs` (the action reached notify-send).
  - **Restart**: the critical card from `live.json` came back after a restart, redacted ("Verification notification"). The state dir is mode 700, and `live.json` never held the code.
  - **Snooze**: `pager snooze 30` → `Chat until 18:55`, and the on-screen Chat card closed as `snoozed`. A later Chat notification was held and showed no card. The panel state was `sources ["Chat=1"]`, `heldCount 1`, `line "1 source snoozed"` (`04-panel-snoozed.png`).
  - **DND on**: `notifications toggleDnd` created `flags/dnd`, and `probe` reported `doNotDisturb: true`.
    - A Mail notification was held. A "Your verification code is 482913" notification still showed (code exception, `06-dnd-code-bypass.png`; the bar shows the red bell).
    - The panel showed Held Back with Chat and Mail (`05-panel-dnd.png`). `quiet.json` recorded `dnd: true` and `silencedSince`.
  - **DND off and back**: `haseen toggle dnd off` (CLI on the scratch state) → `doNotDisturb: false`. `pager dnd` → `on` (flag file present), then `notifications toggleDnd` → flag removed.
  - **Clear**: with 2 cards, `notifications clear` → 0 cards and `pager recent ""` → `[]`. History kept the closed entries (17).
  - **Both daemons listed**: `services: [haseen.notifications, haseen.pager, …]` and the reverse order. In both, `role: haseen.pager`, one card per notify-send, `toggleDnd` wrote the flag, and the log had no warnings.
  - **Re-check after the last edits** (explicit `repeat: false` on every pager ui-timeout, and the `Instantiator` in haseen.notifications):
    - haseen.notifications alone owned the bus name and drew its popup (`07-fallback-notif.png`), and `toggleDnd` wrote the flag;
    - with both listed, `role: haseen.pager`, one pager card, and no warnings.
  - `tests/run.sh tests/test-pager.sh tests/test-surfaces.sh`: the pager checks all pass. The four failures left in test-surfaces are outside this plan:
    - default provider `haseen.pager`, and the launcher/menu default providers: these wait for Main's `default/shell.json`;
    - `haseen.prayers` timers: plan 026.
  - The log stayed clean apart from the expected portal/AT-SPI lines on the no-activation bus. An earlier build logged "Cannot open" for missing icon override files; `IconDir.qml` (only existing files become candidates) removed that.
- **RSS** (`/proc/<pid>/status`, idle 30 s after start, same scratch config except the daemon, two runs each):

  | daemon | VmRSS | Pss |
  |---|---|---|
  | haseen.pager | 177 524 / 172 900 kB | 124 482 / 119 983 kB |
  | haseen.notifications | 176 936 / 172 728 kB | 123 885 / 119 740 kB |

  The idle difference is under 1 MiB, within run-to-run noise (about 4.5 MiB). After the whole smoke (cards, panel opened and closed, about 20 notifications), the pager instance was at 204 504 kB RSS / 145 750 kB Pss.

### Integration for Main

- `default/shell.json`:
  - `bar.right`: replace `"haseen.notifications"` with `"haseen.pager"`;
  - `services`: replace `"haseen.notifications"` with `"haseen.pager"`.
- NOTICE row: `share/haseen/shell/plugins/haseen.pager/` | omapager,
  https://github.com/njpatel/omapager (now redirects to ryanrhughes/omapager),
  luna copy recorded as `5cf5fec` = upstream `c389e73` + the owner's local commits |
  MIT, Copyright (c) 2026 Neil Jagdish Patel | ported.
- architecture §5.5 table: rows for `pager` (verbs above) and the debug target
  `haseen.pager`.
- `layers/dms/ipc-translate` maps `panel toggle haseen.notifications` only; a
  `haseen.pager` row (→ DMS `notifications toggle`) is Main's call.
- `bin/haseen-toggle-dnd` help text names haseen.notifications (lines 7, 18).
