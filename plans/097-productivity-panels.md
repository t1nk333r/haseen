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
`dirsReady`. `enqueue()` refuses every request but the key-free port scan
while not `ready`, so no builder (the poll, opening the panel, editing a
service, detail pages, posters, controls) can queue one with absent keys;
`pump()` and the three poll timers wait for it too. A change of `ready` drops
queued requests built before it, and `onReadyChanged` starts the next poll. A missing credentials file is `ok`
(no keys yet); any other read error, or text that is not a JSON object
(`Model.credentialsReadable`), is `error`: nothing is polled and the service
warns once, until a reload reads it. Credential writes are refused while the
file is not `ok` (`credentialsWritable`): `credentials.json` is rewritten whole
from the in-memory keys, which are empty then, so one edit after a transient
read error would have dropped every other key. The bar status reads "Keys
unreadable" and the settings fleet tab says why. A service with no stored key
is still polled, as upstream, and shows the server's 401.

**Evidence.**
- `tests/test-omarr.sh` 49/49 (34 before), three runs. New checks: every
  Sonarr request carries the header file; with a corrupt `credentials.json`,
  opening the panel and editing a service with a new key queue nothing for
  2 s, the status says "Keys unreadable", the key is refused and logged and the
  file keeps its bytes; repaired in place, polling resumes (the open panel's
  `wanted/missing` included) with the header and the key in no argv; made
  unreadable (`chmod 000`, "Permission denied") polling holds, and resumes once
  it is readable again (skipped as root). `tests/Model.test.js` checks
  `credentialsReadable`.
- The new test against older `Service.qml` files: the plan 097 one, 36/42 when
  it had six new checks, failing "every Sonarr request carries the header";
  the first follow-up commit's, which gated only `pump()` and the timers, 43/49,
  failing the queue, status, refusal, file, header and permission checks (an
  independent review of #51 had found the queue gap: seven requests queued
  with the panel open, all five Sonarr ones sent bare after the repair).
- `tests/test-surfaces.sh` and `tests/test-shell.sh` together: 347/347;
  `tools/lint.sh` and `tools/check-docs.sh` pass.
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
- *Gate only `enqueuePoll`/`forcePoll`*: detail pages, posters and controls
  queue through `enqueue()` too; the gate there covers every builder.
- *Merge a key edit into the unreadable file*: its other keys are unknown, so
  any rewrite could drop them; the edit waits until the file reads.

## Follow-up 2026-10-30: remove a torrent

**Problem.** The owner asked for qBittorrent's delete, citing qbittorrent-api's
`torrents_delete(delete_files=False, torrent_hashes=None)`: remove torrents by
hash, a list or `all`, and delete their files only when asked. A qBittorrent
row in the panel had only pause and resume (`OmarrDetail.qml`,
`queueActions`), and upstream never calls `torrents/delete`.

**Change.**
- `Model.js`: `qbitDeleteUrl` (`POST /api/v2/torrents/delete`),
  `qbitDeleteBody(hash, deleteFiles)` (`hashes=…&deleteFiles=true|false`,
  `false` unless `deleteFiles` is exactly `true`) and `isTorrentHash`, which
  admits one info hash (40 hex digits, or 64) and so never `all` or a
  `|`-joined list.
- `Service.runControl` takes `remove-item` and `remove-item-files` for
  qBittorrent (RDT included: it is configured as qBittorrent) and refuses
  anything but one hash. qBittorrent 5.0 renamed pause and resume, not delete,
  so one request does.
- `OmarrDetail.qml`: a remove button on each qBittorrent row. The first click
  only asks: the row's second line turns urgent ("Its files stay unless you
  delete them too") and pause and resume give way to remove (keeps the files),
  delete the files too, and cancel. Turning the page or opening another
  service drops the question. Removing a service in the settings asks the same
  way (`SettingsView.qml`, `removeRow`).
- qBittorrent commands send the session cookie only once a login gave one, as
  the poll does (`enqueueQbit`). They used to name the jar always, and the
  wrapper refuses a jar that is not there (`Model.safeCurlCmd`), so on a client
  that asks for no login pause and resume never reached curl either.

**Evidence.**
- `tests/test-omarr.sh` 57/57 (53 before): a qBittorrent service with one
  finished torrent joins the engine fleet. Its first remove click asks on that
  row only, cancel clears it, the second click removes it. The curl log holds
  exactly two posts to `:8081/api/v2/torrents/delete`, `deleteFiles=false`
  then `deleteFiles=true`, neither with a cookie; `all`, from the row or
  straight to `runControl`, sends nothing.
- With the old cookie line (the jar always named), 55/57: both delete checks
  fail, as no delete reached curl.
- `tests/Model.test.js`: the URL, both bodies, a string `"true"` keeping the
  files, v1 and v2 hashes taken, and `all`, a list, empty and undefined
  refused.
- `tests/run.sh --affected` (core, i18n, omarr, shell, surfaces) 691/691;
  `tools/lint.sh`, `tools/check-docs.sh` and `tools/i18n.py check` pass.

**Rejected.**
- *A delete-files setting*: the choice belongs to each removal, as the API
  makes it; a remembered default could delete files on a click meant to keep
  them.
- *Removing several, or all, torrents at once*: the API allows it, but a row
  acts on its own torrent, and `isTorrentHash` keeps a stray `all` from
  emptying the client.
- *Remove on SABnzbd rows too* (`mode=queue&name=delete`): not asked for.

## Follow-up 2026-10-31: Seerr

**Problem.** The owner asked whether Seerr can be in omARR. It could only as
a generic tile: `SCAN_SERVICES` named port 5055 "Jellyseerr" with
`kind: "generic"` (`Model.js`, before this change), which checks that the
URL answers and nothing else. The owner runs Seerr 3.5.1
(`/api/v1/status` answered `{"version":"3.5.1",…}`, 2026-10-31); their fleet
(`shell.json`) has no Seerr entry yet.

**Sources.** Seerr's `seerr-api.yml` and `server/routes/request.ts`
(seerr-team/seerr, `develop`, 2026-10-31): `GET /api/v1/request` takes
`take`, `skip`, `filter=pending`, `sort=added`, `sortDirection` and answers
`{pageInfo: {results}, results: [MediaRequest]}`; a `MediaRequest` carries
`media.tmdbId`, `type`, `seasons[].seasonNumber`, `is4k` and `requestedBy`,
and no title (`server/entity/Media.ts` has no title column), which Seerr's
own request list fetches from `/api/v1/movie/<id>` or `/api/v1/tv/<id>`.
`POST /api/v1/request/<id>/approve|decline` answers 409 unless the request
is pending. Requests are keyed with `X-Api-Key`; `/api/v1/status` needs no
key. Jellyseerr and Overseerr answer the same API.

**Change.**
- `Model.js`: a `seerr` kind (name Seerr, group Media, port 5055, API key),
  which the port scan now finds. The request list, title lookup and decision
  URLs; `isSeerrRequestId`, so approve and decline take one numeric id and
  never a path; the parsers; `applySeerrTitles`, which shows `TMDB <id>`
  until a title answers; `requestLine` ("Seasons 1, 2 · 4K · by bob");
  `fleetLine` "3 pending"; a `request` event per new request id, which the
  grab switch (`notifyGrab`) silences; and `itemOpenUrl` to the request's
  page in Seerr. The bundled Dashboard Icon `icons/seerr.svg` (Apache-2.0,
  unmodified); a Seerr kind named Jellyseerr or Overseerr keeps that mark.
- `Service.qml`: the status gives the version only, and the keyed request
  list decides health, so a wrong key shows the service down instead of
  flipping it every poll. A page waits for the titles it lacks: one lookup
  each, queued behind it, kept for the session (an HTTP error is kept too,
  so it is not asked every poll; a lookup curl could not send is asked again). The last lookup's answer commits the page whole,
  so a new request's notification names what was asked for. `runControl`
  takes `approve-item` and `decline-item` and refreshes the list behind the
  decision. Paging works as for the other queues.
- `OmarrDetail.qml`: approve and decline on each request. Decline asks first,
  sharing the torrent remove's question (`confirmRemoveId` became
  `confirmId`), as a declined request cannot be approved later. A click on
  the row opens it in Seerr. `SettingsView.qml`: the Seerr pill and "Notify
  on new requests".
- The request queue (an older bug, found by this test): a handler that
  queues more work started it inside the finished request's exit
  (`enqueue` pumps, and `apiProc.running` is already false there). The exit
  then cleared `currentReq`, and the request just started had its answer
  dropped. That request was whichever was first in the queue: here the first
  title lookup and later a queued decline. qBittorrent's poll after a login
  and Jellyfin's on-deck fetch after its users take the same path. `pump`
  now waits while a finished request is handled (`settling`).

**Evidence.**
- `tests/test-omarr.sh` 69/69 (57 before): a Seerr service joins the engine
  fleet with its own key. Its two pending requests are listed by their
  looked-up titles, newest first, with their lines; the fleet row says
  "3 pending" and the detail the version. Approve posts once to
  `request/9/approve`. Decline asks on its row, can be cancelled, and posts
  once to `request/7/decline`. `all` and `1/approve` send nothing. Every
  keyed request carries the header file, the status none, and the key never
  reaches an argv. Each title is looked up once. A request that arrives
  later is notified as "New request on Seerr Inception (2010) · Carol" with
  Seerr's icon, and the requests found at start are not.
- Without `settling`, 68/69: the decline never reached curl, and the first
  poll lost its first title lookup (the curl log showed only
  `movie/603`, with `tv/1399` asked a poll later).
- `tests/Model.test.js`: the kind, scan, icons, URLs, ids, parsers, titles,
  lines, events, notification switch and fleet line.
- `tests/run.sh --affected` 5191/5192 (the manifest and catalogue changes
  select 59 test files). The one failure is `test-menu-back`: its IPC socket path
  in this checkout is 109 bytes, over the 108-byte limit, and run from a
  short bind mount it passes 34/34. `tools/lint.sh`, `tools/check-docs.sh`
  and `tools/i18n.py check` pass.

**Rejected.**
- *Read the status for health*: it needs no key, so a wrong key would read
  up there and down on the list, and notify both every poll.
- *Commit the list first and the titles as they come*: the notification for
  a new request would go out with its TMDB id, and the requests found at
  start would notify once their titles arrived after the start had ended.
- *Skip a lookup already in flight*: a newer page would then commit without
  that title and replace the page waiting for it; a second lookup, when a
  request arrives between two refreshes, is cheaper.
- *Seerr's requests on the bar badge or the overview*: not asked for; the
  fleet row and the notification already show them ("no visual clutter").
- *Delete, retry or edit requests*: not asked for.

## Rejected

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
