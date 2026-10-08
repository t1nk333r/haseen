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
`-preview-width` runes (100) before the panel ever sees it
(cliphist 0.7.0 `cliphist.go` `preview()`/`trunc()`). An image entry showed as
`[[ binary data 52 MiB png 7680x4320 ]]` and nothing else.

## Decision

- **A preview pane** (`Preview.qml`) holding the decode state for one entry: a
  meta line (type / size / `W×H` or line count), a `Flickable` + `Text` for
  wrapped scrollable text, a bounded `Image`, and a notice line for refused or
  failed entries.
- **Bounded by construction.** `Cliphist.js` now parses `type`, `size`,
  `bytes`, `width` and `height` out of cliphist's own list line (both the 0.7.0
  `[[ binary data 52 MiB png 7680x4320 ]]` shape and the pre-0.7 MIME shape),
  and the shared `tooLarge()` guard refuses an entry past
  `previewMaxBytes` (8 MiB) or `previewMaxPixels` (12 MP). **The list rows use
  the same guard**: the unbounded thumbnail decode in the row delegate was the
  actual RSS hazard, not the pane.
- **Text is capped without lying about the size**: one `cliphist decode`
  feeds `head -c <cap>` for the body and `wc -c` for the rest, so memory is
  O(1), the true size is known and the meta line can say `… · first 64 KiB`.
  (Until the 2026-10-08 review fixes this decoded each entry twice.)
- **Decodes are serialised and race-free**: each run carries a serial and a
  superseded run's exit is ignored; the image decoder writes through a temp file
  and `mv`, so it cannot race the row thumbnail on the same path.
- **Nothing runs while the preview is off**: the pane is a plain `Loader` with
  `active: previewOn && results.length > 0`, inside the panel's existing
  `LazyLoader`.
- **Default on** (owner, 2026-10-08; recorded in AGENTS.md). The pane is a new
  element in an approved plugin, so "No visual clutter" asks for a reason: it
  exists only while the panel is open, costs nothing at idle and +0.7 MiB with
  the panel open, and the truncation above is exactly the gap the request
  names.
- **Toggle**: `Ctrl+P` or an eye button in the panel header; applied to the
  running shell at once *and* persisted to
  `shell.json` → `plugins."haseen.clipboard".settings.preview`.
- The service, the launcher provider and `History.qml` are byte-identical.

## Verification

- `tests/test-widgets-b.sh`: five `Cliphist.js` parser cases, and (at landing,
  2026-10-08) the real `Panel.qml` under `qs`, offscreen, on a stub cliphist
  that logs each decode: on by default, the newest entry decoded in full, a
  70 000-byte text capped at 64 KiB, a 9000×9000 screenshot described and
  never decoded by the pane or its row, the toggle applied at once and written
  to `shell.json`, and a persisted off decoding nothing for a pane.
  `tests/test-shell.sh` 195/195 — the new QML trips neither the timer rule nor
  the Compat-import rule.
- `haseen plugin validate haseen.clipboard` ok; qmllint 0 errors.
- **Live smoke** in a scratch Quickshell instance (`dbus-run-session` with
  `tools/smoke-session.conf`, only `haseen.clipboard` in `services`, driven
  entirely through `settings.debugIpc` — no injected input, one pid started and
  killed):
  - 6 KiB / 43-line text → `text · 6 KiB · 43 lines`, bytes 6079, not truncated;
  - 640×360 PNG → `png · 27 KiB · 640×360`, the decoded file byte-identical to
    the source;
  - 52 MiB / 7680×4320 → `png, 52 MiB, over the 8 MiB preview limit`, and across
    the whole 27-minute run the stand-in's `decoded.log` contains ids 1, 3, 5, 6
    and **never** id 2 — neither the pane nor the row thumbnail ever decoded it;
  - 242 KiB text → `text · 242 KiB · 1058 lines · first 64 KiB`, true size
    reported while only the cap was held;
  - toggling three times flips the pane and writes the setting on the same call;
    with the preview off no new decode appears;
  - closing the panel removes `$XDG_RUNTIME_DIR/haseen-clipboard` entirely.
  - Screenshots: `/tmp/haseen-clipsmoke/shots/{image,text}.png`.

## Open

`cliphist` is not installed on the reference machine (`extra/cliphist 1:0.7.0-2`
is available; installing needs sudo). The smoke used a stand-in `cliphist` on
the scratch `PATH` whose list-line format was taken from the upstream source at
the packaged version, so the two `wl-paste` watchers ran for real against the
live session while the owner's clipboard was never written anywhere. The parser
is therefore proven against upstream's format, not against upstream's binary.

Noted while scripting: `qs ipc call … search ""` is rejected by qs's argument
parser — an empty string cannot be passed over IPC.

## Execution record

`share/haseen/shell/plugins/haseen.clipboard/{Preview.qml,Panel.qml,Cliphist.js,manifest.json}`,
`tests/test-widgets-b.sh`.

## Review fixes 2026-10-08 (PR #38)

- **SEC-5, private image cache.** Decoded images went to
  `${XDG_RUNTIME_DIR:-/tmp}/haseen-clipboard`, created under the shell's
  umask (0755 dirs, 0644 files under 022). The `/tmp` fallback is gone:
  without an absolute `XDG_RUNTIME_DIR` no image is decoded, rows stay text
  lines and the pane says why. The row thumbnail and the pane share one
  decode, `Cliphist.imageCommand`: umask 077, the cache made with
  `mkdir -m 700`, and the runtime dir and the cache must both be real
  directories of ours at mode 0700. A symlinked, foreign or group/other-open
  cache exits 3 untouched (its mode is never changed) and the pane names the
  refusal. Closing the panel removes the cache only when it passes the same
  check, so a planted link is never followed or removed.
- **U-042, bounds and binary.** `previewMaxBytes`/`previewMaxPixels` go
  through `Cliphist.limit`, which clamps to 1..2^31-1: a QML `int` is 32-bit
  and 3000000000 wrapped to -1294967296, which switched the byte bound off
  and cut text to 1 KiB. Binary entries are described by type and size and
  never shown as text: cliphist's `binary data` that is not a Qt-native image
  (a TIFF, `application/octet-stream`) is not decoded at all, and a decoded
  body holding a NUL byte (current cliphist previews unmarked binary as text)
  is withheld.
- **Single text decode.** See "Text is capped" above; one shell and one
  `cliphist` per selection instead of two.
- Tests (`tests/test-widgets-b.sh`, the real panel under `qs` and umask 022):
  the cache is 0700/0600; each text entry is decoded once; a TIFF, an
  octet-stream entry and an unmarked NUL body are described with an empty
  body, and the marked ones are never decoded; bounds of 3000000000 read
  back as 2147483647 and keep the 64 KiB text cap; a symlinked cache, an
  existing 0755 cache, a 0755 runtime dir and an unset `XDG_RUNTIME_DIR` all
  leave image 2 undecoded, write nothing through the link and leave the
  link and the 0755 dir as they were. 17 of these failed before the fix.
