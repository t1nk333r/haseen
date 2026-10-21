# Plan 097: Todoist and omARR as first-party plugins

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (two ported plugins with network access and private credentials, plus a migration of the owner's `shell.json`; both plugins ship off, the migration is idempotent and only renames)
- **Depends on**: 005 010 025 026 045 074
- **Category**: shell
- **Planned at**: 2026-10-20, owner decision
- **State**: DONE 2026-10-20

## Problem

The owner runs two plugins of their own on IO and luna: `t1nk33r.todoist`, a
fork of Aryan-Techie's omarchy-todoist, and `t1nk33r.omarr`, a fork of
luccast's omARR (Sonarr, Radarr, SABnzbd, qBittorrent, Jellyfin and friends).
Both are Omarchy-style plugins that haseen runs through its compat layer: each
bar keeps a hidden popup alive, they read Omarchy's whole `shell.json`, write
through Omarchy's inline writer, notify through `omarchy-notification-send`,
and draw with `qs.Ui`/`qs.Commons`, which plan 092 had to repair under Qt
6.12.

The owner decided (2026-10-20) to adopt both as haseen's own plugins, off by
default, under `haseen.todoist` and `haseen.omarr`, with a migration so their
`shell.json` keeps working. This is an exception to "third-party plugins are
never bundled" for these two only: the code is MIT and the owner's own forks.

## Sources

Each plugin exists three times: the haseen copy on IO
(`~/.config/haseen/plugins/t1nk33r.*`), the Omarchy copy on IO and luna's copy
(`~/.config/omarchy/plugins/t1nk33r.*`). `diff -rq` found all three
byte-identical for each plugin on 2026-10-20, so the port starts from the IO
haseen copy. The forks are tracked as files in the owner's dotfiles, not as
repositories; their file hashes and last dotfile changes are recorded in each
plugin's `UPSTREAM.md`. The owner's config was read only for the ids, bar
slots and setting names they use; no value from it is in this repository.

## Change

The branch's commits landed squashed as `f9d6959` (#49); its branch
commits are not cited, because they leave the repository with the branch.

### haseen.todoist

`share/haseen/shell/plugins/haseen.todoist/`: kinds `service`, `bar-widget`,
`panel`, role `todoist`.

- `Service.qml` owns the task list, the count and the requests once per
  shell; `Widget.qml` and `Panel.qml` read it through `Plugins.roles.todoist`,
  and the panel exists only while it is open.
- The token stays where the owner keeps it: a 0600 `settings.json` in a 0700
  state directory, `$XDG_STATE_HOME/haseen/todoist`, or upstream's
  `~/.local/state/omarchy/t1nk33r.todoist` in place when only that one exists,
  so a stored token is never copied or moved. `haseen-todoist.sh` takes it
  once on stdin and hands curl the header through `-K <(…)`; the shell never
  holds it and it is in no argv. Requests go only to the Todoist API base
  (the helper takes a path, rejects `..` and `//`), with `--proto =https`.
- Upstream's request rules, paging, status texts and keys are kept; the
  priority colours map to theme roles; tasks open with `xdg-open` through
  `Apps.launch`.
- Polling: every 20 min while the panel is closed, every 2 min while it is
  open (`// haseen:sample`, architecture §6).

### haseen.omarr

`share/haseen/shell/plugins/haseen.omarr/`: kinds `service`, `bar-widget`,
`panel`, role `omarr`.

- The fleet, cadence, page size, density and download card are manifest
  settings, applied through `Config.setRuntime` and written through
  `haseen plugin settings`. API keys and passwords stay in `credentials.json`
  (0600) in a 0700 state directory, `$XDG_STATE_HOME/haseen/omarr` or
  upstream's `~/.local/state/omarchy/omarr` in place (`Model.chooseStateDir`).
  The cache moved to `$XDG_CACHE_HOME/haseen/omarr`.
- The panel is haseen's `panel` kind and tells the service it is open
  (`setPanelOpen`) for the faster poll and art fetches.
- Download clients are polled every 2 s only while one reports an active
  download or the panel is open; upstream polled them every 2 s always.
- The regular poll counts fixed 5 s ticks towards `pollSeconds`:
  the timer rule in `tests/test-surfaces.sh` reads only a literal interval,
  so a cadence that is not a multiple of 5 rounds up.

### Overlaps

- **Notifications**: both send through `haseen notification send` (the shell's
  server, history, Do Not Disturb) with the plugin's icon. omARR's always-on-top
  `DownloadToast.qml` window became one replaceable notification (`-t 0 -p`,
  `-r` on change, Hide closes it), so no window of its own.
- **Settings**: haseen's plugin settings path, not a private writer of
  `shell.json`.
- **Opening links**: `Apps.launch` with `xdg-open`. haseen has no web-app
  launcher, so omARR's `omarchy-launch-webapp` pages open in the default
  browser.
- **Bar overflow, popup placement, Escape**: the shell's host; the plugins'
  own relayout and popout-switching code is gone.
- No overlap with an existing haseen plugin: nothing else talks to Todoist or
  the *arr services.

### Dropped

- todoist's keyboard-shortcut recorder and `set-keybind.sh`: they edited
  `~/.config/hypr/bindings.lua`, and haseen never edits a user's files after
  seeding them.
- omARR's `DownloadToast.qml` (above), its Omarchy host guards and
  `shell.json` reader, the unused `icons/omarr.svg`, README, SECURITY.md,
  screenshots and upstream's `tests/run.sh` (Omarchy's validator).

Each plugin's `UPSTREAM.md` lists every change and drop in detail.

### Migration

`share/haseen/migrations/1791560200-adopt-todoist-omarr.sh` renames
`t1nk33r.todoist` → `haseen.todoist` and `t1nk33r.omarr` → `haseen.omarr`:

- in `bar.left`, `center`, `right`, `overflow` and `pinned`, in place, an id
  kept once at its first place;
- in `services`, in place; an id that held a bar slot is added to `services`
  (the user's own list, or the defaults plus the id when there is none),
  because a native service only starts from `services`;
- `plugins.<old>` moves to `plugins.<new>` without the `id` Omarchy's writer
  adds; an existing new entry wins key by key.

It exits quietly when no old id is present or there is no `shell.json`, writes
through `shell_config_write` (atomic, `--dry-run` aware) under the config lock,
and never touches the old plugin or state directories. Upstream ids
(`io.github.*`) are not the owner's and stay as they are.

### Docs

`NOTICE.md` (both MIT notices; Dashboard Icons, Apache-2.0), `CLAUDE.md`
(adopted as first-party, off by default), `handoff.md` and
`docs/architecture.md` §5.2 (credentials stay in private state).

## Evidence

- `tests/test-todoist.sh`: 61/61 — manifest validation, `qmllint`, upstream's
  and haseen's node suites, the helper (private modes, legacy directory kept,
  token never in argv or output, path checks, dry run), and service, widget
  and panel in the real engine against a scripted curl.
- `tests/test-omarr.sh`: 34/34 — the same shape, plus a download card
  notification with the service icon, against the legacy credentials
  directory.
- `tests/test-migrate-097.sh`: 31/31 — the owner's layout with fixture values,
  dry run pure, idempotent re-run, defaults written when there is no own
  `services`, merge rules, invalid JSON left alone, old directories untouched.
  The order check pins only what matters: this migration sorts after plan
  095's, whose nook items it re-points; later plans' migrations may sort
  after it (review of #49).
- `tests/test-migrate.sh` and `tests/test-migrate-defaults.sh`: 92/92;
  `tests/test-shell.sh` together with the two plugin files: 353/353 (its hex
  check now skips the bundled SVG icons, which are artwork, not widget code).
- Full suite, once, from a short-path worktree at the docs commit (the
  fixture rename below changed only `tests/test-omarr.sh`), offscreen with
  `HASEEN_REQUIRE_ENGINE=1` and default signals: 14543/14545. The two
  failures:
  - `tests/test-surfaces.sh`, "no Timer under 2000 ms except marked
    single-shot UI timeouts": omARR's poll timer had a computed interval and
    its placeholder delay lacked `repeat: false`. Fixed before merge;
    `tests/test-surfaces.sh` 89/89, `tests/test-omarr.sh` 34/34 after it.
  - `tests/test-vapt-net.sh`, "foreground wrapper signals leave no helper
    endpoint behind": passes alone on the same tree (`tests/test-surfaces.sh`,
    `test-omarr.sh`, `test-shell.sh` and `test-vapt-net.sh` together:
    618/618); this plan touches nothing it covers.
- The omARR fixture credential in `tests/test-omarr.sh` is named `FIXTURE`,
  not `KEY`: gitleaks' generic-api-key rule flagged the first name, and the
  `secrets` gate scans all history, so it was renamed in the commit that added it.
- `tools/lint.sh` and `tools/check-docs.sh` pass.

## Follow-up 2026-10-21: no request before the keys are read

**Problem.** On #50's CI (run 39511424739, Arch container, merge of main
`f9d6959`), `tests/test-omarr.sh` failed "engine: the key travels in the
private header file". The logged curl calls show all four Sonarr requests
(`/api/v3/system/status`, `queue`, `calendar`, `history`) without any
`-H @…/header.txt`, while SABnzbd's form posts did use `body.txt`. A header
that could not be written does not do this: on a failed private write the
writer calls `handleFailure()` and drops the request
(`share/haseen/shell/plugins/haseen.omarr/Service.qml`, `secretProc`
`onExited`). The requests were built without a key.

**Cause.** A race in this port, not in the test library or the atomic writer.
`credsFile`'s path is bound to `dirsReady`, because the state directory is
chosen by a probe; the handler that set `dirsReady` called `forcePoll()` in
the same turn, assuming the bound FileView loads synchronously. It does not: a
probe shell that sets a FileView's path (with `blockLoading: true`) and reads
the `onLoaded` result at once and one turn later saw "none" both times, three
runs out of three (Quickshell 0.3, 2026-10-21). With logging in `forcePoll`
and `enqueueArr`, `tests/test-omarr.sh` on this laptop printed `forcePoll
services=2 creds=0`, `enqueueArr key=no`, then `creds loaded`, then a second
poll with `key=yes`. So the first poll goes out without keys everywhere. The
laptop's run still passed because a keyed poll followed before the probe
finished; in CI the probe finished first. The owner's fork set the path at
construction, so its keys were loaded long before the first poll
(`~/.config/omarchy/plugins/t1nk33r.omarr/Service.qml`, `credsFile`; read
only). `seen.json` had the same race: a late load overwrote the ids the first
poll had seeded.

**Change.** `Service.qml` keeps `credsState` (`""` until `credentials.json`
answers, then `ok`, or `error`) and `seenLoaded`. `ready` requires both plus
`dirsReady`, and `pump()` and the three poll timers wait for it.
`onReadyChanged` starts the first poll. A missing credentials file is `ok`
(no keys yet); any other read error, or text that is not a JSON object
(`Model.credentialsReadable`), is `error`: nothing is polled and the service
warns once, until a reload reads it. A service with no stored key is still
polled, as upstream, and shows the server's 401.

**Evidence.**
- `tests/test-omarr.sh` 42/42 (34 before). New checks: every Sonarr request
  carries the header file; a corrupt `credentials.json` holds polling for 2 s
  with an empty queue and the warning; repaired in place, polling resumes with
  the header and the key in no argv. `tests/Model.test.js` checks
  `credentialsReadable`.
- With the old `Service.qml` and the new test: 36/42, failing "every Sonarr
  request carries the header" and the five broken-credentials checks.
- `tests/test-omarr.sh`, `tests/test-surfaces.sh` and `tests/test-shell.sh`
  together, twice: 389/389 each time; `tools/lint.sh` and
  `tools/check-docs.sh` pass.
- The CI order was not reproduced in an `archlinux:latest` container; the
  logging above shows the keyless first poll directly, and the new check
  fails on the old code here.

**Rejected.**
- *Read the file at the first poll* (`credsFile.text()` blocks with
  `blockLoading`): it still reads an unreadable or corrupt file as "no keys"
  and sends the requests bare.
- *Skip every \*arr request without a key*: a service with no key stored is the
  owner's configuration, not a failure; its 401 is what tells them so, and no
  secret is involved.
- *Bind the path at construction, as the fork did*: the state directory is not
  known until the probe has chosen it.

- **Keep Todoist's preferences in `shell.json`.** The token and preferences
  share upstream's private file; splitting them would mean two sources and a
  migration of secrets. Only the debug IPC switch is a manifest setting.
- **Copy or move the credentials into haseen's state directory.** It would
  touch the owner's private files and leave two copies; the legacy directory
  is used in place instead.
- **Rename upstream's `io.github.*` ids too.** They are other people's
  plugins; the migration renames only the owner's forks.
- **Keep omARR's always-on 2 s download poll.** It breaks architecture §6;
  the fast poll now runs only while it has something to show.
- **Keep omARR's own progress window.** A second always-on-top surface with
  its own placement; the notification server already does this job.
- **Add a web-app launcher for omARR's pages.** Not this plan's scope; links
  open in the default browser until haseen has one.

## Remaining

- Not verified against the owner's real Todoist account or *arr services, and
  no screenshots from a nested Hyprland session; the engine tests run against
  scripted responses.
- The owner enables them on IO by running the migration (`haseen migrate`),
  which adds both to `services` where they held a bar slot.
- Media pages open in the browser rather than as a web app.
