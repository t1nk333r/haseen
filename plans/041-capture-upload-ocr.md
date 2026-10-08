# Plan 041: Sharing a capture — uploader, annotation, Arabic OCR, circle to search

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (one path can send a screenshot to a third party; it is opt-in per invocation)
- **Depends on**: 004 018
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (items 18 and 19)
- **State**: DONE 2026-10-05

## Problem

haseen could capture but not share. No uploader; no annotation defaults; an OCR
invocation copied from Omarchy that silently mangles Arabic; no circle to
search. And the two obvious targets are gone: **imgur** client registration is
closed (`GET https://api.imgur.com/oauth2/addclient` → `301` to `imgur.com`;
`POST /3/image` → `429` from this network; ShareX disabled it by default, issue
#8014, closed "not planned"), and **0x0.st** returns `503` — *"uploads disabled
because it's been almost nothing but AI botnet spam"*.

## Decision

- **One `haseen upload FILE`** with pluggable backends; the capture commands
  call it rather than each growing an uploader.
  `xbackbone | catbox | uguu | temp.sh | rclone | 0x0 | imgur`.
  Default: XBackBone when `[xbackbone] url` is configured, otherwise **catbox**
  (keyless, verified live). imgur and 0x0 are selectable but never chosen
  automatically, and `--help` states why for each.
- **Credentials go to curl through `curl --config -` on stdin** (`form-string = "token=…"`,
  `header = "Authorization: Bearer …"`). No token ever reaches argv,
  `/proc/<pid>/cmdline`, `ps`, a dry-run plan, a notification or stdout. The
  tests assert it in both directions: present in the recorded curl stdin, absent
  from the recorded argv and from the output. `~/.config/haseen/upload.toml` is
  seeded at mode 0600 (created under umask 077).
- **XBackBone has two shapes and they are detected, not guessed.** `api = auto`
  does `GET <base>/api/v1/upload`: `404`/`000` → the tagged ≤3.8.2 shape
  (`POST /upload`, `token` as a **form field**, part named `upload`); anything
  else → next-gen (`POST /api/v1/upload`, `Authorization: Bearer`, part `file`,
  link from `data.raw_url`).
- **Arabic OCR**: one `ocr_argv` array drives the plan and both real paths —
  `tesseract <in> stdout --oem 1 --psm 6 -l ara+eng -c preserve_interword_spaces=1`.
  Omarchy's `--dpi 300` is **removed** (measured: it merges words, producing
  `انتشارا فيالعالم`), the default language set becomes `ara+eng`, and
  `tesseract-data-ara` joins the desktop layer.
- **Circle to search** (`haseen search screen [text|image]`): the default is
  fully local OCR to the clipboard, and recognised text is never put in a
  notification. `image` copies the PNG as a *sensitive* clipboard entry and
  opens the provider's own paste page — haseen uploads nothing. `image --upload`
  prints the warning to stderr, asks for confirmation **on every invocation**
  (no "don't ask again"), posts `encoded_image` to
  `https://lens.google.com/v3/upload`, follows the `Location:` header and
  `xdg-open`s it. Captures live in `$XDG_RUNTIME_DIR/haseen-search-screen`,
  used only when it and the runtime dir are real 0700 directories of ours,
  are `mktemp`'d, swept after 10 minutes and deleted on exit. There is no
  `/tmp` fallback.
- **satty is themed through `overrides.css`**, symlinked to the theme render
  (`share/haseen/themed/satty.css.tpl` → `current/theme/satty.css`), because
  satty's `config.toml` is TOML and cannot include another file. Satty 0.22.0
  reads the CSS if it exists and prints one stderr line otherwise, so a dangling
  link before the first theme is harmless. The annotation **palette** stays
  static high-contrast: annotations are drawn on a picture of the themed screen,
  so theme-derived arrow colours would be the one thing on the shot you cannot
  see.
- `--edit --upload` is one keystroke from region to link; the upload runs after
  the editor so the link, not the image, wins the clipboard.

## Rejected

| option | evidence |
|---|---|
| imgur as default | registration closed (301), `429` from this network, ShareX disabled it |
| 0x0.st as default or fallback | `503`, uploads switched off upstream |
| litterbox | endpoint and fields `[UNVERIFIED]` (403 from this network; fields came from a third-party crate). uguu (3 h) and temp.sh (3 d) were verified live |
| Bing / Yandex / TinEye / SauceNAO for the upload path | Bing needs base64 `imageBin`; Yandex and TinEye need a publicly hosted URL or a session; SauceNAO refuses anonymous API use. Lens is the only keyless file upload that works end to end. They stay available through the clipboard hand-off |
| autopaste into the browser (the owner's reference plugin uses `wtype`) | haseen never injects keystrokes into the live session (handoff.md working rules) |
| `themed/satty.toml.tpl` | satty would have to be launched with `-c <render>`, bypassing the user's own `config.toml`, which is theirs after seeding |
| `--dpi 300` | measured to merge words at native resolution |

## Verification

- `tests/test-capture-upload.sh` (188) green, run four times, stable; with
  `test-trigger.sh`, `test-seeds.sh` and `test-core.sh` → 513/513.
- Every backend's request shape asserted against a stub `curl`; no credential in
  argv or output; dry-run purity; the OCR argv asserted exactly.
- `tools/secrets.sh` clean.
- The rendered `satty.css` carries resolved colours and no placeholder.

## Open

The uploader was exercised against a stub and a local server, not against a real
XBackBone instance — the owner has one, haseen does not. The Lens path was
verified end to end for the request/redirect shape; the quality of the results
is Google's.

## Execution record

`bin/haseen-upload`, `bin/haseen-search-screen`, `bin/haseen-capture-text`,
`bin/haseen-capture-screenshot`, `share/haseen/default/satty/config.toml`,
`share/haseen/themed/satty.css.tpl`, `share/haseen/seeds/80-capture.sh`,
`share/haseen/layers/desktop/packages.txt`, `tests/test-capture-upload.sh`,
`tests/test-trigger.sh`, `tests/test-theme.sh`,
`share/haseen/layers/theme/theme-lib.sh`.

## Landing 2026-10-08

- Owner decision D6: `satty` and `tesseract-data-ara` are approved as
  desktop-layer defaults and recorded in `AGENTS.md`.
- `tests/test-capture-upload.sh` no longer reads the scripts' headers; it checks
  that `haseen commands` lists `haseen upload` and `haseen search screen` with
  their arguments and summaries.

## Review fixes 2026-10-08 (PR #38)

- **SEC-2, one file-part encoder.** Every backend builds its `-F` file part
  with `form_file FIELD PATH`, which puts the path inside curl's quoted form
  (`@"…"`, `"` and `\` escaped). Unquoted, curl read `shot.png,.env` as two
  files and `;` as the start of `type=`/`filename=`. The XBackBone form token
  is a `form-string`, so a token starting with `@` or `<` is never read as a
  file. `tests/fixtures/multipart-receiver.py` is a loopback-only receiver;
  the test runs the real curl through a stub that only rewrites the host, and
  asserts exactly one file part with the selected file's bytes for comma,
  semicolon, quote and backslash names on every curl backend.
- **SEC-6, no credential over plain http.** The XBackBone base URL, and the
  0x0 target (it answers with a management token), must be `https://`. Plain
  `http://` is accepted only to this machine (`localhost`, `127.0.0.0/8`,
  `[::1]`); a scheme-less URL is refused, since curl would default to http.
  The URL check alone did not bind curl (security re-review): every call,
  the XBackBone probe included, now goes through `curl_run`, which starts
  with `-q` (no `~/.curlrc`, so no `location`, `proxy` or `insecure` from
  it), passes no `-L`, and pins `--proto =https --proto-redir =https`; a
  loopback endpoint gets `--proto =http --noproxy '*'`, so an inherited
  `http_proxy` never carries the cleartext request off the machine. The
  real-curl tests run a recording receiver as `http_proxy`/`all_proxy` for a
  loopback form upload, and an HTTPS receiver (self-signed, trusted through
  `CURL_CA_BUNDLE`) that answers 307 to a plain-http receiver while
  `~/.curlrc` says `location`. Before the fix the proxy got the request and
  the redirect replayed it over http (279/284); after, 284/284.
- **SEC-4, private delete token.** The 0x0/imgur delete token goes to
  `$XDG_RUNTIME_DIR/haseen-upload.delete-token` only when that directory is
  ours and 0700, otherwise to `$HASEEN_USER_STATE/upload/` (created 0700).
  It is written to a fresh `mktemp` file (0600) and renamed over the name, so
  a planted link is replaced, never followed. Never a shared `/tmp` path.
- **XBackBone probe.** A connection failure printed `000000`
  (`-w` plus `|| echo 000`) and was read as next-gen; anything that is not
  three digits is now `000`, the tagged-release shape.

## Final review fixes 2026-10-08 (PR #38)

- **RV-1, private capture storage.** The capture dir fell back to the shared
  `/tmp/haseen-search-screen`, and an existing dir was used without checking
  that it was ours, real or private (a failed `chmod` was ignored), with the
  sweep running first. Now image mode settles the directory before freezing
  the screen, sweeping or capturing: no `XDG_RUNTIME_DIR` stops it (no `/tmp`
  fallback); the runtime dir must be ours and 0700; the capture dir is made
  0700 if absent, and one that is a link, someone else's, or open to others
  is refused untouched. The undocumented `HASEEN_SEARCH_TMP` override is gone.
  Cases: no runtime dir, an open runtime dir, a symlinked, a 0755 and a
  foreign-owned capture dir (chowned to a subordinate uid through
  `unshare --map-auto`; skipped where none is available), each asserting
  that grim never ran and nothing was swept or written. 18 failed before.
- **RV-2, `--image` copy.** Cleanup skipped the capture whenever `--image`
  was given, so every hand-off and upload left a copy of the picture behind.
  The command-owned copy is now removed on every exit; the user's file never
  is. Cases: hand-off, consented upload and declined upload, each asserting
  the original is unchanged and no copy remains. 3 failed before.
- **RV-4, OCR fixture.** The tesseract stub answered without reading stdin,
  so a grim that wrote late got `SIGPIPE` and the `pipefail` OCR reported
  failure. The stub now drains stdin when its input is `stdin`; a
  `GRIM_DELAY` case makes the race deterministic (failed before).

## CI hang 2026-10-08 (PR #38)

- **Cause.** The RV-1 foreign-dir case probed with
  `unshare --map-auto --map-root-user … 2>/dev/null`. util-linux unshare forks
  a helper for `--map-auto` that blocks reading an eventfd until the parent
  has unshared; in the CI container `unshare(2)` is refused, the parent exits
  and the helper is orphaned for good, holding the suite's stdout. tests/run.sh
  read each file through `$(…)`, which waits for EOF, so after the skip line
  the job hung until it was cancelled (run 37798664013, 2h11m; b067f04 passed
  the file in 10s). Reproduced with
  `bwrap --unshare-user --disable-userns -- env -i … tests/run.sh tests/test-capture-upload.sh`:
  hung before, 316/316 in 2.9s after.
- **Fix.** The probe first tries a helper-free `unshare --user --map-root-user`
  and runs the `--map-auto` step under `timeout` with no descriptor of the
  suite. tests/run.sh collects each file's output in a file (it waits for the
  file's subshell, not for every process holding its stdout) and gives tests
  `/dev/null` as stdin, since the scripted curl drains stdin and hung on an
  open pipe. The loopback receivers write to their own logs, time out idle
  connections (the TLS handshake included) and exit after 300s on their own;
  the receiver cases skip without python3. tests/test-run-harness.sh fails
  against the old runner (timed out, 0/2) and passes after.
