# Plan 042: Clipboard history with a toggleable preview

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (+0.7 MiB with the panel open; nothing instantiated while off)
- **Depends on**: 022
- **Category**: shell
- **Planned at**: 2026-10-05, owner request (item 17: "unified clipboard & history with toggleable preview")
- **State**: DONE 2026-10-05

## Problem

`haseen.clipboard` was already a complete cliphist front-end (service, panel,
launcher provider), but the list alone cannot tell two long entries apart:
cliphist collapses whitespace and truncates each preview to
`-preview-width` runes (100) before the panel sees it (cliphist 0.7.0
`cliphist.go` `preview()`/`trunc()`). An image entry showed as
`[[ binary data 52 MiB png 7680x4320 ]]` and nothing else.

## Decision

All paths are under `share/haseen/shell/plugins/haseen.clipboard/`.

- **A preview pane** (`Preview.qml`) shows the selected entry: a meta line
  (type, size, `W×H` or line count), wrapped scrollable text, a bounded
  `Image`, and a notice line for refused or failed entries. The panel opens
  with ALT + V (`share/haseen/default/hypr/binds.lua`, plan 043).
- **Bounded by construction.** `Cliphist.parse` (`Cliphist.js:24`) reads
  `type`, `size`, `bytes`, `width` and `height` off cliphist's list line (the
  0.7.0 `[[ binary data 52 MiB png 7680x4320 ]]` shape and the older MIME
  shape), and `tooLarge` (`Cliphist.js:107`) refuses an entry past
  `previewMaxBytes` (8 MiB) or `previewMaxPixels` (12 MP) before anything is
  read. The list rows use the same guard (`Panel.qml:320`): an unbounded row
  thumbnail costs the same pixmap as the pane.
- **Bounds stay bounds.** A QML `int` is 32-bit, and 3000000000 wrapped to
  -1294967296, which switched the byte bound off and cut text to 1 KiB.
  `Cliphist.limit` (`Cliphist.js:121`) clamps both settings to 1..2^31-1.
- **Text is decoded once and capped.** One `cliphist decode` feeds `head -c
  <cap>` for the body and `wc -c` for the rest (`Preview.qml:128`), so the
  pane holds at most 64 KiB (`textCap`, `Preview.qml:38`), the true size is
  known, and the meta line says `… · first 64 KiB`.
- **Binary is never shown as text.** cliphist's `binary data` that is not an
  image Qt reads here (a TIFF, `application/octet-stream`) is described by
  type and size and not decoded; a decoded body holding a NUL byte (current
  cliphist previews unmarked binary as text) is withheld
  (`Preview.qml:152`).
- **A private image cache.** Row thumbnails and the pane share one decode,
  `Cliphist.imageCommand` (`Cliphist.js:146`), into
  `$XDG_RUNTIME_DIR/haseen-clipboard`: umask 077, the cache made with
  `mkdir -m 700`, and the runtime dir and the cache must both be real
  directories of ours at mode 0700. A symlinked, foreign or group/other-open
  cache exits 3 untouched (its mode is never changed) and the pane names the
  refusal. Without an absolute `XDG_RUNTIME_DIR` no image is decoded
  (`Cliphist.cacheDir`, `Cliphist.js:130`). Closing the panel removes the
  cache only when it passes the same check (`Cliphist.cleanupCommand`,
  `Cliphist.js:152`), so a planted link is never followed or removed. Images
  are written through a temporary file and `mv`, so a row and the pane never
  read a half-written file.
- **Decodes cannot race.** Each run carries a serial (`Preview.qml:83`) and
  a superseded run's exit is ignored.
- **Nothing runs while the preview is off.** The pane is a `Loader` with
  `active: previewOn && results.length > 0` (`Panel.qml:402`), inside the
  panel's `LazyLoader`.
- **Default on** (owner, 2026-10-08; recorded in `AGENTS.md`). The pane is a
  new element in an approved plugin, so "No visual clutter" asks for a
  reason: it exists only while the panel is open, costs nothing at idle and
  +0.7 MiB with the panel open, and the truncation above is the gap the
  request names.
- **Toggle**: `Ctrl+P` or an eye button in the panel header, applied to the
  running shell at once and persisted to
  `shell.json` → `plugins."haseen.clipboard".settings.preview`
  (`Panel.qml:80`).

## Rejected

| option | evidence |
|---|---|
| a `/tmp` fallback for the image cache | a shared, predictable directory shows copied images to other accounts and lets them plant the cache (`Cliphist.js:127`) |
| decoding each text entry twice (once for the size, once for the body) | two `cliphist` runs per selection; `head -c` and `wc -c` on one decode give both (`Preview.qml:121`) |
| decoding any image the list names | Qt decodes a PNG in full before scaling it, so a 7680×4320 screenshot costs hundreds of MiB of pixmap (`Cliphist.js:101`) |
| a preview outside the panel | "No visual clutter" (`AGENTS.md`): the pane exists only while the panel is open |

## Verification

- `tests/test-widgets-b.sh:122`–`:139`: the `Cliphist.js` parser, filter,
  sizes, metadata line, bounds clamping (`[2147483647,1,7,7,7,8388608]`) and
  the cache path (no `/tmp` fallback).
- `tests/test-widgets-b.sh:144`–`:376`: the real `Panel.qml` under `qs`,
  offscreen, under umask 022, on a stub cliphist that logs each decode. On by
  default, the newest entry decoded in full; a 70 000-byte text capped at
  64 KiB and decoded once; a 9000×9000 screenshot described and never decoded
  by the pane or its row; the toggle applied at once and written to
  `shell.json`; a persisted off decoding nothing for a pane; a TIFF, an
  octet-stream entry and an unmarked NUL body described with an empty body,
  the marked ones never decoded; bounds of 3000000000 reading back as
  2147483647 with the 64 KiB text cap kept; the cache 0700 with 0600 files;
  a symlinked cache, an existing 0755 cache and a 0755 runtime dir each
  leaving the small image undecoded, writing nothing through the link and
  leaving the link and the 0755 dir as they were. Each run is its own process
  group with its output in a file, killed afterwards, so a shell that dies
  fails the case instead of hanging the suite.
- `haseen plugin validate haseen.clipboard` ok; qmllint 0 errors.
- **Live smoke** in a scratch Quickshell instance (`dbus-run-session` with
  `tools/smoke-session.conf`, only `haseen.clipboard` in `services`, driven
  through `settings.debugIpc`, no injected input):
  - 6 KiB / 43-line text → `text · 6 KiB · 43 lines`, bytes 6079, not truncated;
  - 640×360 PNG → `png · 27 KiB · 640×360`, the decoded file byte-identical to
    the source;
  - 52 MiB / 7680×4320 → `png, 52 MiB, over the 8 MiB preview limit`; across
    the 27-minute run the stand-in's `decoded.log` holds ids 1, 3, 5, 6 and
    never 2;
  - 242 KiB text → `text · 242 KiB · 1058 lines · first 64 KiB`;
  - toggling three times flips the pane and writes the setting on the same
    call; with the preview off no new decode appears;
  - closing the panel removes `$XDG_RUNTIME_DIR/haseen-clipboard`.

## Open

`cliphist` is not installed on the reference machine (`extra/cliphist
1:0.7.0-2` is available; installing needs sudo). The smoke used a stand-in
`cliphist` whose list-line format was taken from the upstream source at the
packaged version, while the two `wl-paste` watchers ran against the live
session and the owner's clipboard was never written. The parser is proven
against upstream's format, not upstream's binary.

An unset `XDG_RUNTIME_DIR` is covered only by the `cacheDir` unit case
(`tests/test-widgets-b.sh:139`), not in the real engine: Quickshell then
uses `/run/user/<uid>` for its own instance directory, which is the live
session's on a desktop, and exits when it cannot create it. In the CI
container the shell exited and its crash handler kept the test's output pipe
open, which hung the suite (PR #41's first two CI runs).

`qs ipc call … search ""` is rejected by qs's argument parser: an empty
string cannot be passed over IPC.

## Execution record

`share/haseen/shell/plugins/haseen.clipboard/{Preview.qml,Panel.qml,Cliphist.js,manifest.json}`,
`tests/test-widgets-b.sh`.
