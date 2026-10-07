# Plan 072: Wallhaven in the theme generator

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (three new commands that touch only the user's cache and backgrounds; a source switch in a panel that is off by default)
- **Depends on**: 067
- **Category**: theme
- **Planned at**: 2026-10-07, owner request (io): Aether-like behaviour, wallpapers from wallhaven.cc directly in the theme generator flow
- **State**: DONE 2026-10-07 (`tests/test-wallhaven.sh`, 132 checks; nested-session screenshots of the Wallhaven grid and a preview from a downloaded picture). `haseen.themegen` stays off by default and **awaiting the owner's approval**, as in plan 067.

## Problem

Plan 067 dropped Aether and gave haseen its own generator, but its panel only
picks from the user's wallpaper directories. Aether's useful part was its
Wallhaven browser: search, pick, theme. haseen had no way to fetch a
wallpaper at all.

## Research

**Wallhaven API v1** (<https://wallhaven.cc/help/api>, read 2026-10-07):

- `GET /api/v1/search`: `q` (tags, `-tag`, `+tag`, `@user`, `id:N`, `type:png`, `like:ID`),
  `categories` (general/anime/people bits, default 111), `purity` (sfw/sketchy/nsfw
  bits, default 100), `sorting` (date_added*, relevance, random, views,
  favorites, toplist), `order`, `topRange` (1d 3d 1w 1M* 3M 6M 1y, toplist
  only), `atleast`, `resolutions`, `ratios`, `colors` (a fixed palette of hex
  values), `page`, `seed` (`[a-zA-Z0-9]{6}`, random paging without repeats).
  24 results a page; `meta` carries `current_page`, `last_page`, `total`, `seed`.
- `GET /api/v1/w/<id>`: one record with `path` (the full image), `file_size`,
  `file_type`, `purity`, `thumbs.small|large|original`.
- **Rate limit**: 45 calls a minute, 429 beyond.
- **Key**: NSFW needs one (401 without); a key also applies the user's own
  settings. Sent as `?apikey=` or the `X-API-Key` header.
- Observed (live, SFW, read-only): search `mountains` → 24 results, 5 pages;
  `path` is `https://w.wallhaven.cc/full/<2>/wallhaven-<id>.<ext>`, thumbnails
  on `th.wallhaven.cc`. The help page's search example omits `full/`, so both
  shapes are accepted.

**Aether's defaults** (aether 4.31.1 is installed on io; `aether --help` and its
source, `bjarneo/aether` at `29d07b1a8f474c77bf02aece948373f40abed105`,
`internal/wallhaven/client.go` and `frontend/src/lib/stores/wallhaven.svelte.ts`):

| | Aether | haseen |
|---|---|---|
| categories | 111 | 111 (matched) |
| purity | 100 | 100, more only with a key |
| sorting | date_added | **toplist** (owner's choice; Latest is a chip) |
| order | desc | desc |
| atleast | 1920x1080 (store) | the focused monitor (`hyprctl -j monitors`, read-only; a rotated one swapped), 1920x1080 without one |
| API timeout | 30 s | 20 s (10 s connect) |
| image limit | 50 MiB (`MaxImageBytes`) | 50 MiB |
| thumbnail limit | 5 MiB | 5 MiB |
| key | `apikey` in the URL | `X-API-Key` header from a file |

Aether keeps its thumbnails in `~/.cache/aether/wallhaven-thumbs` with no
bound; haseen bounds its cache.

## Design

### Commands

`share/haseen/lib/wallhaven.sh` holds the client; the commands follow
`haseen-<group>-<verb>` (AGENTS.md), so `haseen wallhaven search|get|random`
route through `bin/haseen`.

- `haseen wallhaven search [query] [--query Q] [--sort S] [--top-range R] [--ratio 16x9] [--atleast WxH] [--color HEX] [--categories C] [--purity P] [--page N] [--seed S] [--json] [--no-thumbs] [--dry-run]`
  - Every option is validated before any call. `--query` carries a query that starts with `-` (wallhaven's tag exclusion).
  - The query string is URL-encoded by jq, so `--dry-run` prints the exact URL and calls nothing.
  - `--json`: `{query, sort, atleast, page, last_page, total, seed, results: [{id, url, purity, category, resolution, file_type, file_size, path, colors, thumb_url, thumb}]}`, where `thumb` is the cached file.
  - Without a key, entries whose `purity` is not `sfw` are dropped, a second lock after the request's own purity 100.
- `haseen wallhaven get <id|page URL> [--to DIR] [--dry-run]`
  - Default destination `~/.config/haseen/backgrounds/wallhaven/<id>.<ext>`. That is inside the panel's default scan directories, so a download shows under My wallpapers too.
  - A file already there is kept and no call is made.
  - Refused: an id that is not `[a-z0-9]{1,16}`; a non-SFW record without a key; a `path` that is not `https://w.wallhaven.cc/…/wallhaven-<id>.(jpg|png|webp)`; an announced type other than JPEG/PNG/WebP or a size over 50 MiB; a reply whose `Content-Type` is not an image; bytes that `file` does not call JPEG/PNG/WebP; a size other than the record's. The partial file goes in every case.
  - curl's progress bar is turned into `progress N` lines on stderr; stdout's last line is the path.
- `haseen wallhaven random [query] [--ratio …] [--atleast …] [--color …] [--to DIR]`: a random search without thumbnails, then `get` of its first result (two calls).

**Network rules.**
- curl with `--proto =https`, `--max-time`/`--connect-timeout` and `haseen/<version> (+https://github.com/t1nk333r/haseen)` as User-Agent.
- API replies are capped at 4 MiB and must be JSON.
- 401, 404 and 429 get plain messages.

**Rate limit.** `~/.cache/haseen/wallhaven/calls` holds the timestamps of the
last minute's API calls under `flock`. The 46th is refused with the wait in
seconds, before curl runs. Image and thumbnail hosts are not API calls and are
not counted.

**Key.** `~/.config/haseen/wallhaven.key`:
- Used only at mode 600 or 400; otherwise a warning with the `chmod` hint and the key is ignored.
- Written by curl's `--header @file` from a mktemp file that is removed at once. It is never in an argv (visible in `ps`), a URL, a dry-run line or a log.
- A key alone does not widen the search: purity stays 100 until `--purity` asks for more.

**Thumbnail cache.** `~/.cache/haseen/wallhaven/thumbs/<id>.<ext>`:
- The missing thumbnails of a page come in one `curl --parallel` (6 at a time).
- A hit is touched, so age means "unused".
- After every search, files unused for 7 days go, then the oldest beyond 600.
- A thumbnail that is not an image is deleted.

### Panel

`haseen.themegen` gains a source switch, **My wallpapers | Wallhaven**:

- `WallhavenGrid.qml` (one component) is loaded on the first switch and kept. It holds:
  - sort chips (Top, Latest, Random, Relevance, Views, Favourites);
  - a `GridView` of thumbnails (haseen.imagepicker's `ImageCard`, decoded at card size);
  - a progress track.
- The panel's text field becomes the search: Enter searches, Left/Right move through the grid.
- The first switch shows the toplist at once.
- **Paging**: `onAtYEndChanged` loads the next page when the grid is scrolled to its end. Repeats are dropped, and a random search passes its seed on. No timer, no polling.
- **Pick**: a click (or arrow) runs `haseen wallhaven get <id>`. The `progress N` lines drive the track and the card reads "downloading…". A pick during a download is queued and only the latest runs. Errors (the CLI's last stderr line) show in the header in `Theme.urgent`.
- The downloaded file becomes the panel's image. The theme name follows as `wallhaven-<id>` unless typed, and the existing matugen preview, Save and Apply (`haseen theme generate`) run unchanged.
- `Wallhaven.js` is the pure model: argv, parsing, append, progress, path, name.
- Theme tokens only. The grid reuses `Choice.qml` and `ImageCard`.
- The manifest:
  - adds the setting `source` (default `local`);
  - adds the permission `network`, because the panel now causes network traffic through the CLI;
  - says Wallhaven in the description.
- `share/haseen/default/shell.json` still has the plugin disabled; io keeps its own enablement.

### Resources

Nothing runs until the panel is open and switched to Wallhaven. Then there is
one search (one API call and up to 24 small thumbnails), one call per page
scrolled to, and one call plus one download per pick.

## Rejected options

- **`bin/haseen-wallhaven` with subcommands**: AGENTS.md's command shape is `bin/haseen-<group>-<verb>`. The router gives the same `haseen wallhaven search` spelling and lists the group (`haseen commands wallhaven`).
- **`apikey=` in the URL** (Aether): it would show in `ps`, in `--dry-run` output and in any proxy log.
- **Categories 110**: Aether's default is 111, and People in SFW is ordinary photography.
- **Thumbnails from `thumbs.large`**: the cards are about 10 em wide; `small` (300×200) is enough at 2× scaling and a third of the bytes.
- **A Timer to page or to show progress**: `atYEnd` and curl's own progress lines are events.
- **Downloading in QML (`XMLHttpRequest`)**: it would bypass the SFW rule, the size and type checks and the rate count, which live in one place, the CLI.
- **A separate Wallhaven panel**: the owner asked for it inside the theme generator flow.

## Verification

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-wallhaven.sh tests/test-themegen.sh`: 262/262. curl is `tests/fixtures/wallhaven/curl.sh`, serving a listing recorded from the API (one entry made sketchy), records and generated images, so no network is used. The checks:
  - help and the router listing;
  - argument refusals before any curl;
  - dry runs: the exact URL with the defaults (atleast from a stubbed rotated monitor), no curl, no file;
  - search parsing, the SFW filter, the cached thumbnails, https/timeout/User-Agent, one parallel thumbnail run, cache hits not refetched;
  - paging and the random seed;
  - SFW enforcement: `--purity 111` and a sketchy `get` refused without a key, a mode-644 key ignored, a 600 key sent only as a header and never in an argv;
  - 429/401 messages; the 46th call in a minute refused before curl; calls older than a minute forgotten;
  - `get`: the bytes saved, progress lines, a second get without curl, and refusals of a non-image, image bytes sent as `text/html`, a size mismatch, an off-host path, an announced 60 MiB or GIF record (neither fetched) and an unknown id, each with nothing kept;
  - `random`;
  - the cache: a week-old file pruned, 600 files at most, a non-image thumbnail not cached;
  - `Wallhaven.js` under the Qt JS engine, from search → results → page 2 → select → `get` argv → path → the `haseen theme generate` preview and Apply argv.
- Live, read-only and SFW, from scratch dirs: `haseen wallhaven search mountains --json` returned 24 results and their thumbnails in 3.2 s. `haseen wallhaven get 3q797y --to <scratch>` saved 3 177 780 bytes, and a second run said "already downloaded".
- Nested Hyprland (`nest-launch.sh`; the worktree shell; scratch `XDG_*`/`HASEEN_USER_*`; a private D-Bus; plan 067's PATH guard without its curl entry, whose log stayed empty). The panel was driven over `debugIpc` only. Screenshots in `~/.cache/haseen-wt/Wallhaven/shots/`:
  - `1-wallhaven-grid.png`: Wallhaven source, Top chip, the toplist grid ("24 of 1728 · page 1 of 72").
  - `2-downloading.png`: after `pickResult 1`, the card reads "downloading…" and the header "downloading pomle9…". Before that, `more` had loaded page 2 (48 results).
  - `3-wallhaven-preview.png`: the downloaded `pomle9.jpg` previewed: name `wallhaven-pomle9`, source `#b2750e`, accent `#f6bc70` on `#18120c`.
  - `4-wallhaven-saved.png`: after `save`, the panel showed "saved wallhaven-pomle9", and the theme directory held the marked `colors.toml` and `backgrounds/pomle9.jpg`.
  - The shell log has no QML warning. One unrelated polkit-agent warning appeared because the nested shell shares the system bus.
- `tools/lint.sh` (shellcheck at warning level, qmllint, jq) and `tools/check-docs.sh`: OK.

## Live apply

1. `./install.sh --tree-only` installs the three commands, the library, the panel files and the docs.
2. Nothing else is needed on io, where `haseen.themegen` is already enabled: `haseen shell ipc shell reload`, then menu Style › Theme Generator › Wallhaven.
3. Optional: put a Wallhaven API key in `~/.config/haseen/wallhaven.key` with `chmod 600`. Without one everything is SFW.
4. Owner check: Apply on a Wallhaven picture in the real session switches the desktop. The nested proof stopped at Save, because its PATH guard blocks the reloads.
