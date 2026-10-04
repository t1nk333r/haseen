# haseen.pager upstream record

- **Upstream:** omapager by Neil Jagdish Patel, <https://github.com/njpatel/omapager>
  (GitHub now redirects it to `ryanrhughes/omapager`), MIT (see `LICENSE`,
  kept verbatim). Plugin id upstream: `njpatel.omapager`, version 1.1.1.
- **Source:** the owner's read-only copy from the machine luna, recorded for
  this port as commit `5cf5fec`. That commit is not in the upstream
  repository (the GitHub API answers "No commit found for SHA: 5cf5fec" on
  2026-10-04), so it is the owner's local head: upstream `main` at
  `c389e73` ("fix: allow rapid SUPER+, notification dismissal (#42)",
  2026-09-27, still upstream's newest commit on 2026-10-04) plus the owner's
  six local commits, as luna's own record says. Those commits' behaviours are
  kept here: Recent dismiss/clear, the Held Back Clear, left click opens the
  panel and right click silences, right click dismisses a card and middle
  click opens its snooze menu, the bell's size and colour, and Clear all N on
  the front card.
- **Ported:** 2026-10-04, haseen plan 025 (`plans/025-haseen-pager.md`).

## Files

| haseen | upstream | change |
|---|---|---|
| `Detect.js`, `Layout.js`, `Markup.js` | same | notice header only |
| `Security.js` | same | `parseOmarchyExecArgv` and `safeLocalFilePath` removed (Omarchy-only click actions) |
| `Store.js` | same | `execArgv` / `omarchy-action` dropped; the Python store's writer queue replaced by pure disk-store rules (`forDisk`, `closeInto`, `trimHistory`, `newest`, `forgetHeld`, `putLive`, `parseFile`) |
| `Service.qml` | `Service.qml` | rewritten against `qs.Haseen` (below) |
| `Toast.qml`, `DeedButton.qml` | same | Theme tokens instead of Omarchy's Style/Color/Border/Button; no `MultiEffect`; single-shot expiry |
| `PagerButton.qml`, `SectionHeader.qml`, `TextCard.qml` | parts of `Toast.qml`/`Widget.qml` | haseen has no shared kit control, so the small pieces are their own files |
| `IconDir.qml` | (new) | lists the icon override and cache directories, so only existing files are tried |
| `Widget.qml` | bar half of `Widget.qml` | a `BarButton`; text in `Theme.barForeground` |
| `Panel.qml` | panel half of `Widget.qml` | a haseen `panel` plugin (lazy popup via the panel host) |
| `kdeconnect.sh` | `bin/omapager-kdeconnect` | bash + `busctl` + `jq` instead of Python |
| `tests/*.cjs`, `tests/tst_security.qml`, `tests/corpus/*.json` | `tests/`, `security/corpus/` | pure-JS parts only, plus haseen store/layout cases |

Dropped: `bin/omapager-store`, `omapager-icon`, `omapager-run-*`,
`omapager_http.py`, `omapager_files.py` (the shell path carries no Python,
docs/architecture.md section 6), `bin/omapager-action` and `omapager-demo`
(Omarchy-only), `Picker.qml` and the in-panel preferences view (haseen plugin
settings live in `shell.json`), the Bubblewrap helper sandbox and its
`requireSandbox` setting (no helpers left to sandbox), the Python unit tests,
`assets/`, `docs/`, `security/` and CI files.

## Behaviour changes

- **Names.** Every `omapager`/`oma` identifier is now haseen's: plugin id
  `haseen.pager`, IPC target `pager` (was `omapager`), debug target
  `haseen.pager` (was `omapager.panel`), layer namespace `haseen-pager`, state
  in `$HASEEN_USER_STATE/pager/` (was `~/.local/state/omarchy/omapager/`), icon
  overrides in `$HASEEN_USER_CONFIG/pager/icons/`, remote icon cache in
  `$XDG_CACHE_HOME/haseen/pager/icons/`.
- **Do Not Disturb** is the shared `dnd` flag, written only through
  `Flags.set`; `notifications toggleDnd` reaches `toggleDnd()` through the
  `notifications` role. The Omarchy `notifications` IPC verbs
  (`dismissOne`, `dismissAll`, `invokeLast`, `showHistory`, `dismiss`) are on
  the `pager` target, because haseen's shell owns `notifications`.
  `notifications clear` dismisses the cards on screen and empties Recent.
- **Store.** Upstream's Python store kept one file per notification. Here
  `live.json`, `history.json` and `quiet.json` are written with `FileView`,
  coalesced per event-loop turn. The rules are unchanged: 100 entries,
  `historyHours` 0/1/24/168, codes redacted, held = closed as `snoozed` or
  `silenced`, restored cards get a 20 s grace.
- **Icons.** Resolved in QML: your override files, then (web sources) the
  icon theme by site name, then the remote cache, then the sender's icon hint,
  the icon theme and desktop entries by app name. The card walks the
  candidates until one draws, then shows the first letter.
  **`fetchRemoteIcons` defaults to `false`** (upstream: `true`): haseen is
  local-first, and a fetch tells the site your IP address and when a
  notification arrived. When enabled it fetches only
  `https://<host>/favicon.ico` with `curl` (HTTPS only, TLS 1.2+, 3 redirects,
  256 KiB, 8 s, hostnames that pass `Security.canonicalHostname`, so no IP
  literals), once per host per session. Unlike upstream it does not parse
  pages or manifests, does not pin DNS answers to public addresses, and does
  not re-encode the image with Pillow: Qt decodes it with a bounded
  `sourceSize`.
- **Sender images** (`image://icon//path`) are drawn by Qt with a bounded
  `sourceSize` instead of being decoded by the Python helper.
- **Surface.** The deck's layer surface exists only while cards are on screen
  (plus 800 ms for the last exit animation), instead of upstream's
  always-mapped canvas; it uses the normal exclusion mode, so it sits below
  the bar on its own. `fullscreenOverlay` became `avoidFullscreen`
  (`off`/`all`/`steam`, upstream's `-away` modes); the step-aside modes are
  unnecessary without an idle canvas.
- **Timers.** The card's 100 ms countdown ticker is a single-shot timer that
  banks paused time; the countdown line (`showCountdown`, off by default) is a
  `NumberAnimation`. The repeating 900 ms copied-code closer is single-shot.
- **Bar.** The bell appears only while something is quiet or a share offer is
  waiting (`alwaysShow` keeps it); Omarchy's bar-centre reveal does not exist
  here. Left click opens the panel, right click silences or resumes.
- **Panel.** No keyboard cursor over the source list and no tooltips; Escape
  closes it (panel host). History has a Clear button (`forgetHistory`).
- **Click actions** from `omarchy-exec-argv` hints (screenshot editor,
  Taildrop file, crash agent) are gone with the hint.
