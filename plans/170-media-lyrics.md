# Plan 170: synced lyrics in the media panel

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MEDIUM. A new outbound request to a third party (lrclib.net)
  that tells it what is playing. Off by default; needs the owner's approval
  of the host before it can ship even as an option.
- **Depends on**: 078 (media panel), 109 (interface language)
- **Category**: shell
- **Planned at**: 2026-11-14, from the owner (sent lucid's repository, "what
  could be good to take", then "go")
- **State**: DROPPED 2026-11-14 (owner decision: "no on 170"; the panel
  sends nothing to lrclib.net and shows no lyrics)

## Problem

The media panel shows the cover, the track, a seek bar, transport and
volume (`haseen.media/Panel.qml:122-421`), and nothing of the words. Lucid
(MIT, Sn3akyy1/lucid at d1bcf8a) adds a Lyrics page that follows the song
line by line and seeks on a click: `lucidui/LyricsSource.qml` (183 lines)
fetches from lrclib.net only while something shows the lyrics and keeps
every answer on disk (`:6-8`, `:88`, `:138-171`); `lucidui/Lyrics.js` (251
lines) parses LRC and lrclib's per-word "lyricsfile" into
`{t, end, text, words}` lines (`:1-5`).

## Decision

### Setting

`haseen.media/manifest.json` gains
`"lyrics": {"type": "boolean", "default": false, "description": "Show synced lyrics for the playing track in the panel. Off by default: each new track's title, artist and album go to lrclib.net, which sees your IP; answers are kept in ~/.cache/haseen/lyrics"}`.
The manifest already declares `network` (`manifest.json:32-34`), and the
description follows `remoteArt`'s wording (`:26-30`), the plan 010 rule that
a remote fetch is opt-in and says what it leaks (`plans/078-media-panel.md:40-50`).

### Fetching

- Only while the panel is open, `lyrics` is on, and the track has a title.
  The panel is a `LazyLoader` freed on close, so its process goes with it.
- A `Process` running `sh -c` with the pager favicon fetch's hardening
  (`haseen.pager/Service.qml:1112`): `curl --proto =https --proto-redir =https
  --tlsv1.2 --max-redirs 3 --max-filesize 1048576 --max-time 10 -fsS`, a
  `haseen/<VERSION>` User-Agent as `share/haseen/lib/wallhaven.sh:21` sets,
  `GET /api/get` with track, artist, album and duration, falling back to
  `/api/search` on 404 (lucid's order, `LyricsSource.qml:142-144`).
- The cache is `${HASEEN_USER_CACHE:-${XDG_CACHE_HOME:-~/.cache}/haseen}/lyrics/<hash>.json`
  (the themepicker's resolution, `haseen.themepicker/Panel.qml:41`), written
  to `.part` then moved; a hit makes no request. "Instrumental" and "none"
  answers are cached too, so a track is asked once.

### Showing

- `Lyrics.js` adapted from lucid's (header keeps lucid's MIT notice, a row in
  `NOTICE.md`): the LRC and lyricsfile parsers and `lineAt(lines, pos, hint)`.
  Pure functions, tested in `tests/test-media.sh`'s qml harness as `Media.js`
  is (`:38-140`).
- Under the volume row, a block of three lines (previous, current, next) in
  `Theme` tokens, the current one in `Theme.foreground`, the others in the
  panel's `subtle` (`Panel.qml:114`); a click on a line seeks there when the
  player `canSeek`. Unsynced lyrics show as a scrolling plain block. States:
  "Looking for lyrics", "No lyrics found", "Instrumental", "Offline".
- The line follows `root.position`, which the panel's existing 1 s clock
  already moves (`Panel.qml:94-111`, the plan 078 exception in architecture
  §6). No new `Timer`, so `tests/test-widgets-a.sh:60-71` still holds. Lines
  change on the second, not mid-word; lucid's per-frame clock and
  word-by-word fill are left out.
- The panel keeps its width (`Theme.fontSize * 24`, `Panel.qml:60`).

The reason for a new on-screen element (CLAUDE.md, "No visual clutter"): the
lyrics block appears only inside the panel opened on demand, and only with
`lyrics` on.

## Rejected

- **Lucid's word-by-word karaoke and frame clock** (`LyricsSource.qml:24-36`):
  needs a per-frame animation while playing, against architecture §6.
- **A desktop lyrics widget or a bar ticker**: always-visible clutter.
- **XMLHttpRequest**: haseen has none in the shell; plan 072 rejected it for
  the same kind of fetch (`plans/072-wallhaven.md:135`).
- **Fetching ahead for the whole queue**: more requests than the one track on
  screen.
- **Another provider (Musixmatch, Genius)**: keys or scraping; lrclib needs
  neither.

## Evidence (to collect)

- `tests/test-media.sh`: the manifest default is false and the default
  `shell.json` does not set it (as `remoteArt`, `:29-32`); the JS unit count
  rises from 30 (`:140`) by the new `Lyrics.js` cases; the panel with
  `lyrics` off starts no `Process`; with it on and a cached file, none
  either; with a stub `curl` on PATH, one request per track.
- The real-engine harness on `tools/fake-mpris.py` (`:166-285`) with a
  fixture LRC: the current line at a known position.
