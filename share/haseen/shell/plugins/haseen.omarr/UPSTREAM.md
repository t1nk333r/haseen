# UPSTREAM — haseen.omarr

`haseen.omarr` is a port of **omARR**, MIT, Copyright (c) 2026 luccast.
`LICENSE` in this directory is the upstream licence, unchanged. The service
icons under `icons/` are Dashboard Icons (Homarr Labs, Apache-2.0), bundled
unmodified with their `NOTICE` and `LICENSE-APACHE`.

| | |
|---|---|
| Upstream | https://github.com/luccast/omARR (Omarchy plugin `io.github.luccast.omarr`) |
| Ported from | the owner's fork `t1nk33r.omarr` 1.0.0, tracked as files in the owner's dotfiles (no commit of its own); its last changes there are `b19e67b` (publish the live feed to `feed.json`) and the Qt 6.12 palette fix `88c47f7` |
| Copies compared | the haseen copy on IO (`~/.config/haseen/plugins/t1nk33r.omarr/`), the Omarchy copy on IO and luna's copy (`~/.config/omarchy/plugins/t1nk33r.omarr/`) are byte-identical (`diff -rq`, 2026-10-20) |
| Fork file hashes | `Model.js` sha256 `9611e49a…5394`, `Service.qml` `4c114c0d…74c8`, `Panel.qml` `9fd86d16…bc9c`, `SettingsView.qml` `015097b1…f9cf` |
| Adopted | 2026-10-20 by the owner as a first-party plugin, off by default; ported in `plans/097-productivity-panels.md` |

## What changed

- **Names.** Plugin id `haseen.omarr`, display name "omARR", role `omarr`, the
  Jellyfin device name "haseen". Notifications keep the app name "omARR".
- **Kinds.** Upstream was a service plus a bar widget that carried its own
  popup. Here the panel is haseen's `panel` kind: created on open, destroyed on
  close, placed and closed by the host. The panel tells the service it is open
  (`setPanelOpen`), which polls faster and fetches art meanwhile, as upstream.
- **Settings.** The fleet, the cadence, the page size, the density and the
  download card are the manifest's settings (`shell.json`
  `plugins."haseen.omarr".settings`), applied at once through
  `Config.setRuntime` and written through `haseen plugin settings`. Upstream
  read Omarchy's whole `shell.json` and wrote through `updateEntryInline`;
  `Model.pluginSettings` now takes the settings object, and the payload drops
  Omarchy's entry `id`.
- **Private state.** API keys, Jellyfin keys and passwords stay out of
  `shell.json`, in `credentials.json` (0600) in a 0700 state directory, with
  `seen.json` and the `feed.json` export. The directory is
  `$XDG_STATE_HOME/haseen/omarr`, except that a HOME which already has
  upstream's `~/.local/state/omarchy/omarr` and no haseen one keeps using that
  one in place (`Model.chooseStateDir`, `stateDirProbeCmd`), so stored keys
  are never copied or moved and readers of `feed.json` keep finding it. The
  cache (headers, form bodies, cookies, art) moved to
  `$XDG_CACHE_HOME/haseen/omarr`. Upstream's private-file writers and its
  curl wrapper are unchanged: keys and passwords never reach an argv.
- **Notifications.** Through `haseen notification send` (the shell's own
  notification server, its history and Do Not Disturb) instead of
  `omarchy-notification-send`, with the service's bundled icon; a click
  toggles the panel. Each sender waits for its click, so it runs detached
  instead of in upstream's one-at-a-time queue.
- **The download card.** Upstream drew its own always-on-top window
  (`DownloadToast.qml`). Here it is one notification, kept by a sender that
  waits on it: `-t 0` keeps it up, `-p` prints its id, and changes replace it
  in place (`-r`), only when its text changed. Its Hide button or closing it
  hides those jobs until they finish, as upstream's dismiss did; stopping the
  sender (no job left, or `showProgressToast` off) closes it. Poster art and
  the progress bar are not drawn: the notification server shows text and icon.
- **Polling.** SABnzbd and qBittorrent are polled every 2 s only while one of
  them reported an active download or the panel is open; upstream polled them
  every 2 s all the time (architecture 6). A job that starts and ends within
  one regular poll (`pollSeconds`) gets no card, but still its finished or
  failed notification. The regular poll ticks every 5 s towards
  `pollSeconds`, so a cadence that is not a multiple of 5 rounds up.
- **Opening.** Services and items open with `xdg-open` through `Apps.launch`,
  outside the shell's cgroup. haseen has no web-app launcher yet, so media
  pages open in the default browser instead of `omarchy-launch-webapp`.
- **UI.** Theme tokens, `Pill` and the local `Omarr*` controls instead of
  `qs.Ui`/`qs.Commons`; one component per file (the overview, the detail and
  the rows are their own files); square art corners instead of a
  `MultiEffect` mask; a still glyph instead of the endless spinner; the kind
  dropdown is a row of pills; removing a service asks for a second click.
  A qBittorrent row can remove its torrent (`torrents/delete`, which upstream
  did not call): the first click asks, the second removes it and keeps its
  files, and a button beside it deletes the files too.
- **Seerr.** A kind upstream did not have (its scan named port 5055
  "Jellyseerr" and checked only that it answered). It also serves Jellyseerr
  and Overseerr, which share the API. Its queue is the requests waiting for
  approval, newest first: `/api/v1/request?filter=pending`, keyed with
  `X-Api-Key` like an \*arr. A request names its media only by TMDB id, so
  each title is one lookup (`/api/v1/movie/<id>` or `/api/v1/tv/<id>`), kept
  for the session, and a page is committed once its titles have answered, so
  a new request's notification ("New request on Seerr") names what was asked
  for and by whom. It goes with the grab switch (`notifyGrab`). A row approves
  in one click; decline asks first, as a declined request cannot be approved
  later. A click on the row opens it in Seerr. The keyless `/api/v1/status`
  gives the version only: health comes from the keyed list, so a wrong key
  shows the service down instead of flipping it every poll.
  The detail has four tabs. REQUESTS shows the waiting ones, then every
  request with its state (processing, available, declined…), page by page.
  TRENDING and UPCOMING (movies and series together) are Seerr's discover
  lists, and SEARCH finds movies and series by name. These three are asked
  for when shown, never polled. A title Seerr does not have can be requested
  from its row (`POST /api/v1/request`, JSON; a series for every season it
  lacks) after a second click. Posters come through Seerr's
  `/imageproxy/tmdb/`, without the key.
- **The request queue.** A handler that queues more work (qBittorrent's poll
  after a login, Jellyfin's library after its users, Seerr's titles) no longer
  starts it inside the finished request's exit, where `currentReq` was cleared
  just after: that request's answer was dropped. It starts once the exit has
  run (`settling`).
  Escape always closes the panel (the host's), and Tab cycles the overview
  tabs instead of switching to a neighbouring panel.

## What was dropped, and why

- `DownloadToast.qml`: replaced by the notification above (no window of its
  own, "no visual clutter").
- Omarchy host plumbing: the host-write and host-call guards
  (`setHostProperty`, `callHostMethod`), the relayout reopen
  (`popupShouldReopen`), the reveal suppression, popout switching and the
  `shell.json` document reader (`shellConfigIn`). haseen hands the plugin its
  settings and owns the popup.
- `icons/omarr.svg` (unused since the fork draws a glyph), the README,
  SECURITY.md, the screenshots under `docs/` and upstream's `tests/run.sh`
  (which ran Omarchy's validator).

## Tests

`tests/Model.test.js` is upstream's suite, with the sections for the removed
host plumbing dropped, the settings, open and notification cases rewritten
for haseen, and cases added for the notification text, the download card and
the state-directory choice; it still runs the shipped `publishFeed` lifted
out of `Service.qml`. `tests/test-omarr.sh` runs it and the service, bar
widget and panel in the real Quickshell engine against a scripted curl.
