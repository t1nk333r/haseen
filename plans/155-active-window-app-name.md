# Plan 155: the active window's title drops its own app's name

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW. One pure function changes the label only; a title whose
  last segment does not name its window's app reads exactly as before, and
  clicks, sizing and the `maxChars` and `maxWidth` settings are untouched.
- **Depends on**: 095 (haseen.active-window)
- **Category**: shell, plugins
- **Planned at**: 2026-11-02, owner: "the bar plugin has a long name". Asked
  which label (the active window's title, the Wooting profile name, an
  overflow cell's plugin name), the owner chose the active window's title.
- **State**: DONE 2026-11-02 (`tests/test-bar-basics.sh` 140/140; the
  affected set, 60 files, 5303/5303; the live bar is an owner step after the
  next install)

## Problem

On luna's bar the title read the first 12 characters of a show's name, an
ellipsis and `fin MPV Shim` (the bar strip captured with
`grim -g "0,0 1920x48"`, 2026-11-02). `hyprctl activewindow -j`
gave the class `com.github.iwalton3.jellyfin-mpv-shim` and a 66-character
title ending in ` - Jellyfin MPV Shim`; the owner's `shell.json` sets
haseen.active-window's `maxChars` to 25. `Title.label` keeps 12 characters
of head and 12 of tail around the ellipsis (`share/haseen/shell/plugins/
haseen.active-window/Title.js:54-55`), so the whole tail was the player's
name and the episode was cut out. Plan 095 dropped the fork's tooltip because
"the middle ellipsis keeps both ends" (`plans/095-bar-basics.md:79`);
for a title that ends in its app's name, the end kept is the one the bar
least needs.

## Decision

The widget drops a trailing ` - App Name` when the name is the window's own
app, before the middle cut. The app is the last dotted part of the
toplevel's app id (`jellyfin-mpv-shim`). The title's last segment after
` - `, ` – ` or ` — ` matches when, in lowercase ASCII words:

- its words and the app's run together are equal (`Text Editor` from
  `org.gnome.TextEditor`);
- the app's words occur in it as consecutive whole words (`Mozilla Firefox`
  from `firefox`, `Jellyfin MPV Shim` from `jellyfin-mpv-shim`);
- or its words occur in the app's (`Brave` from `brave-browser`).

Whole words keep `~/src - football` whole in `foot`. Only the last segment
goes, only after a dash between spaces or tabs, and only when text stays
before it on the same line, so a window titled with its app's name alone
keeps it.

Rejected:

- **An end ellipsis instead of the middle one.** It fixes this title and
  breaks the ones whose tail is the point (a path's file name), and reverses
  plan 095's choice for every window.
- **Dropping any last segment after a dash.** `Song - Artist` would lose the
  artist; only the app's own name carries nothing.
- **A list of known app suffixes.** It needs upkeep and misses every app not
  on it; the app id is already on the toplevel.
- **Matching the desktop entry's name too** (Quickshell's `DesktopEntries`).
  It would read `Firefox` for `Mozilla Firefox` no better than the app id
  does, and it ties a pure function to the shell's desktop database, which
  the unit tests do not load.
- **A setting to keep the app's name.** Nobody asked for it; it can come with
  the first request.

## Change

- `Title.js`: `words` (`:68`), `wordRun` (`:73`) and `withoutAppName`
  (`:92`).
- `Widget.qml`: the label is `Title.label(Title.withoutAppName(title,
  appId), maxChars)` (`:36`); the header comment says so (`:12-13`).
- `manifest.json`: the description says the title is shown "less a trailing
  name of its own app".
- `tests/test-bar-basics.sh`: fourteen Qt-engine units (`:141-155`), among
  them `football` against `foot`, another app's name, a segment that is not
  the last, the app's name alone, a hyphen inside a word, no app id, a
  segment without words, no title, a separator with nothing before it and a
  line break before the dash; the unit count is 72 (`:219`). The engine
  harness's window title gains ` - foot` (`:317`) and still reads `A ra…ally`
  at 9 characters (`:456`); without the change it reads `A ra…foot`.

## Evidence

- `Title.js` under `/usr/lib/qt6/bin/qml`, `maxChars` 25: luna's live title
  kept `fin MPV Shim` as its tail before and the episode's name after. With a
  neutral title, `Big Buck Bunny - s1e01 - Pilot - Jellyfin MPV Shim` reads
  `Big Buck Bun…fin MPV Shim` before and `Big Buck Bun…1e01 - Pilot` after.
- `tests/run.sh tests/test-bar-basics.sh`: 140/140, hermetic.
- `tests/run.sh --affected`: 60 files, 5303/5303, from a short worktree
  under `/tmp`. In the author's checkout `tests/test-menu-back.sh`'s IPC
  socket path is 109 bytes, past the 108-byte limit ("Failed to start IPC
  server"), so it runs only from a shorter path.
- With the regex's old `\s` around the dash, the new line-break unit fails
  (`Page\n- foot` reads `Page`).

## Residual unknowns

- An app name outside ASCII yields no words, so it never matches and its
  title stays whole.
- An app whose title names a brand unrelated to its id keeps the suffix.
- A last segment that is content but happens to spell the app's name (a page
  titled `Firefox` in Firefox) is dropped.
- An id whose last part is a generic word drops a segment that is only that
  word: `com.spotify.Client` turns `Report - Client` into `Report`,
  `org.telegram.desktop` drops a last ` - Desktop`, `google-chrome` drops a
  last ` - Google`. Each needs the whole segment to be the word or a run of
  the id's words, so it is rare.
- The whole last segment goes, so anything after the app's name in it goes
  too: `x - mpv (Paused)` from `mpv` reads `x`.
