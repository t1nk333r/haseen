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

haseen could capture but not share. It had no uploader and no annotation
defaults, its OCR invocation (copied from Omarchy) mangled Arabic, and it had
no circle to search. The two obvious upload targets are gone: **imgur** client
registration is closed (`GET https://api.imgur.com/oauth2/addclient` → `301`
to `imgur.com`; `POST /3/image` → `429` from this network; ShareX disabled it
by default, issue #8014, closed "not planned"), and **0x0.st** returns `503`,
*"uploads disabled because it's been almost nothing but AI botnet spam"*.

## Decision

### Uploader (`bin/haseen-upload`)

- **One `haseen upload FILE`**, with backends
  `xbackbone | catbox | uguu | temp.sh | rclone | 0x0 | imgur`; the capture
  commands call it. Default: XBackBone once `[xbackbone] url` is set,
  otherwise **catbox** (keyless, verified live 2026-10-05). imgur and 0x0 are
  never chosen automatically, and `--help` says why for each.
- **Credentials reach curl on stdin** (`curl --config -`, as `form-string` or
  `header` lines), so no token is in argv, `/proc/<pid>/cmdline`, a dry-run
  plan, stdout or a notification. The XBackBone form token is a
  `form-string`, so a token starting with `@` or `<` is never read as a file.
- **One file-part encoder**, `form_file` (`bin/haseen-upload:144`), writes
  curl's quoted form (`@"…"`, `"` and `\` escaped). Unquoted, curl reads
  `shot.png,.env` as two files and `;` as the start of `type=`/`filename=`.
- **No credential over plain http.** The XBackBone base URL and the 0x0
  target must be `https://`; plain `http://` is accepted only to `localhost`,
  `127.0.0.0/8` or `[::1]`, and a scheme-less URL is refused
  (`secure_endpoint`, `:155`). curl cannot widen that (`curl_transport`,
  `:165`; `curl_run`, `:175`): `-q` comes first so no `~/.curlrc` applies, no
  `-L` is passed, and `--proto =https --proto-redir =https` pin the protocol.
  A loopback endpoint gets `--proto =http --noproxy '*'`, so an inherited
  `http_proxy` never carries the cleartext request off the machine.
- **XBackBone's two shapes are detected.** `api = auto` sends
  `GET <base>/api/v1/upload`: `404`, or no three-digit answer, means the tagged
  ≤3.8.2 shape (`POST /upload`, the token as a form field, part `upload`);
  anything else means next-gen (`POST /api/v1/upload`, `Authorization:
  Bearer`, part `file`, link from `data.raw_url`) (`:371`).
- **Delete tokens stay private.** The 0x0/imgur delete token is written to
  `$XDG_RUNTIME_DIR/haseen-upload.delete-token` when that directory is ours
  and 0700, otherwise to `$HASEEN_USER_STATE/upload/` (made 0700), through a
  fresh `mktemp` file renamed over the name, so a planted link is replaced and
  never followed (`save_delete_token`, `:214`). 0x0's `X-Token` is read from
  curl's stdout (`-D -`, `:290`, `:300`): response headers are never written
  to a file.
- **`upload.toml` is read as TOML strings** (`cfg`, `:79`): a `"basic"`
  string (`\"` and `\\` unescaped), a `'literal'` string or a bare word, and
  a `#` after the value starts a comment, so the `--help` example, which has
  inline comments, works when copied. A `#` inside quotes is part of the
  value.
- **A readable `upload.toml` is a warning**, judged by the target's mode when
  the file is a link (`stat -L`, `:515`).

### Annotation (`bin/haseen-capture-screenshot --edit`)

- **What the editor saves is what is kept, copied and uploaded.** grim writes
  the capture to a private `mktemp -d` directory
  (`bin/haseen-capture-screenshot:207`), and the editor writes the annotated
  picture to a second file in it: satty runs with
  `--output-filename <dir>/edited.png --actions-on-enter save-to-file
  --early-exit` (`:223`). The seeded config's Enter is `save-to-clipboard`,
  which copies and exits without writing a file, so without the override the
  capture would keep, copy and upload the unannotated original.
- **No saved file means cancelled** (`:249`): after Escape nothing is saved,
  copied or uploaded, and the command exits 0, as for an empty selection.
  Ctrl+S saves like Enter. Ctrl+C (copy and leave) and Ctrl+Shift+S (save
  where the user picks) leave no file either, so they also count as
  cancelled; the user's own copy stays on the clipboard
  (`/usr/share/doc/satty/README.md`, Shortcuts).
- **Unsaved shots keep their name.** With `--no-save` the file is uploaded
  under the name it would have been saved as (`:215`), which is the name an
  upload host or an rclone bucket keeps.
- **The temporary directory goes on every exit** (EXIT trap, `:208`), a
  failed upload included.
- **PNG only.** satty refuses to save under a name not ending in `.png` and
  swappy writes PNG bytes whatever the name (Satty 0.22.0 `handle_save`,
  swappy `src/pixbuf.c` `write_file`), so `--edit` with `--format jpg|ppm` is
  a usage error (`:117`).
- **Upload last**, so the link replaces the annotated image on the clipboard.

### Theming the editor

satty is themed through `~/.config/satty/overrides.css`, linked to the theme
render (`share/haseen/themed/satty.css.tpl` → `current/theme/satty.css`),
because satty's `config.toml` is TOML and cannot include another file.
Satty 0.22.0 reads the CSS if it exists and prints one stderr line
otherwise, so a dangling link before the first theme is harmless. The
annotation palette stays static and high-contrast: annotations are drawn on a
picture of the themed screen, so theme-derived arrow colours would be the one
thing on the shot you cannot see.

### Arabic OCR

One argv drives the plan and both real paths:
`tesseract <in> stdout --oem 1 --psm 6 -l ara+eng -c preserve_interword_spaces=1`
(`bin/haseen-capture-text:52`, `bin/haseen-search-screen:197`). `--oem 1` is
required (the Arabic model has no legacy engine), `ara+eng` reads the mixed
text Arabic UIs contain, and Omarchy's `--dpi 300` is dropped (measured: it
merges words, `انتشارا فيالعالم`). `tesseract-data-ara` joins the desktop
layer.

### Circle to search (`haseen search screen [text|image]`)

- The default is local OCR to the clipboard; recognised text is never put in
  a notification.
- `image` copies the PNG as a *sensitive* clipboard entry and opens the
  provider's own paste page; haseen uploads nothing.
- `image --upload` warns on stderr and asks **on every invocation** (no
  "don't ask again", `:306`), then posts `encoded_image` to
  `https://lens.google.com/v3/upload` with the uploader's transport (`-q`,
  `--proto =https --proto-redir =https`, no `-L`, a quoted file part,
  `:321`–`:323`). Only an `https://` URL on `www.google.com` or
  `lens.google.com` from the `Location:` header is opened (`:330`); anything
  else is refused and nothing opens.
- Captures live only in `$XDG_RUNTIME_DIR/haseen-search-screen`. The runtime
  dir must be ours and 0700; the capture dir is made 0700 if absent, and one
  that is a link, someone else's or open to others is refused untouched,
  before the screen is frozen, swept or captured (`capture_dir`, `:70`). There
  is no `/tmp` fallback. Captures are `mktemp`'d, swept after 10 minutes and
  deleted on exit; with `--image` the command's own copy is deleted and the
  user's file never is.

### Seeding (`share/haseen/seeds/80-capture.sh`)

`~/.config/haseen/upload.toml` is created under umask 077 (`:36`), so it is
0600 from the moment it exists, and holds no credential. A dangling link
there is the user's and is never written through or chmod'ed (`:34`), the
rule the other seeds follow.

### Owner decision

D6 (owner, 2026-10-08): `satty` and `tesseract-data-ara` are desktop-layer
defaults, recorded in `AGENTS.md`.

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
| satty editing the capture in place (`--filename F --output-filename F`) | "saved" and "left" cannot be told apart, satty refuses a non-`.png` name, and it expands strftime `%` in `--output-filename` (Satty 0.22.0 `resolve_output_filename`) |
| keep satty's Enter (`save-to-clipboard`) and add `--save-after-copy` | a config with `auto-copy` copies, and so saves, on every change: Escape would still leave a file to upload |
| on Escape, keep the unannotated original (save and copy, no upload) | it is the picture the user was redacting; putting it on the clipboard repeats the leak locally |
| 0x0 response headers in a file in a private directory | `-D -` keeps them in memory, with nothing to clean up |
| open any `*.google.com` results URL | the verified answer is `https://www.google.com/search?…`; a narrower set fails closed if Google changes it |

## Verification

`tests/test-capture-upload.sh` (360 assertions) against stubs; every network
call goes to a curl stub that records argv, stdin and the bytes of each file
part.

- Credentials in the recorded curl stdin and absent from argv and output, for
  every backend; dry-run purity; the request shape of every backend.
- `upload-multipart` runs the real curl against
  `tests/fixtures/multipart-receiver.py` (loopback only) and asserts one file
  part with the selected file's bytes for `,`, `;`, `"` and `\` names on every
  curl backend, an `@`-leading token sent as a literal, no request through an
  inherited proxy for a loopback endpoint, an https instance whose 307 to
  plain http is not followed while `~/.curlrc` says `location`, and 0x0's
  `X-Token` read from a real response.
- `upload-config-example` copies the `--help` example (inline comments
  included) into `upload.toml` and uploads through XBackBone and rclone; a
  quoted `#`, `\"` and `\\` and a literal string read as values. 7 of these
  failed before the reader handled comments.
- `upload-perms` asserts the mode warning for a linked config follows the
  target (failed with "mode 777" before). `upload-0x0` asserts no header file
  is written (failed before: the headers went to `mktemp` in `/tmp`).
- `shot-plan`: `--edit` with `--format jpg` is a usage error.
  `shot-enter`: satty is given the capture, and the saved file, the clipboard
  image and the uploaded bytes are all the annotated picture, the link last on
  the clipboard. `shot-escape`: nothing printed, copied, uploaded or saved.
  `shot-temp`: `--no-save --upload` (succeeding and failing) and a cancelled
  `--edit --no-save` leave nothing in `TMPDIR`. The satty stub models Satty
  0.22.0: Enter runs `--actions-on-enter` or the seeded `save-to-clipboard`,
  and a file is written only by `save-to-file` (or a copy with
  `--save-after-copy`) to a `.png` name. 11 of these failed before.
- `search-lens`: the Lens curl starts `curl -q --proto =https --proto-redir
  =https`, sends the capture's bytes, and opens the results URL;
  `search-lens-location` refuses `http://`, other hosts,
  `www.google.com.evil.example`, `www.google.com@evil.example`, a URL with a
  space, and `ftp://`; `search-image-file` sends the bytes of the `--image`
  copy. 24 of these failed before.
- `search-store-*`: no runtime dir, an open runtime dir, a symlinked, a 0755
  and a foreign-owned capture dir each stop before grim runs, sweeping or
  writing nothing.
- `tests/test-seeds.sh:143`: a dangling `upload.toml` link is left a link and
  nothing is written through it (failed before).
- `tests/test-theme.sh` renders `satty.css` with resolved colours and no
  placeholder.

## Open

- The uploader was exercised against stubs and a local receiver, not against
  a real XBackBone instance; the owner has one, haseen does not. The Lens path
  was verified end to end for its request and redirect shape on 2026-10-05.
- satty is not run by the tests (they never touch the live session); its
  Enter, save and `.png` rules are taken from the Satty 0.22.0 source and
  `satty --help`.
- swappy writes its `-o` file whenever it closes, Escape included, so with
  swappy an `--edit` cannot be cancelled.
- A user config that sets both `auto-copy` and `save-after-copy` makes satty
  save on every change, so Escape would still leave a file.
- The foreign-owned capture dir case needs a subordinate uid
  (`unshare --map-auto`) and is skipped where none is available. util-linux's
  `--map-auto` helper waits forever when `unshare(2)` is refused, so the probe
  runs under `timeout` with no descriptor of the suite (a CI run that held the
  suite's stdout hung for 2 h 11 min, run 37798664013);
  `tests/test-run-harness.sh` covers the runner side.

## Execution record

`bin/haseen-upload`, `bin/haseen-search-screen`, `bin/haseen-capture-text`,
`bin/haseen-capture-screenshot`, `share/haseen/default/satty/config.toml`,
`share/haseen/themed/satty.css.tpl`, `share/haseen/seeds/80-capture.sh`,
`share/haseen/layers/desktop/packages.txt`, `tests/test-capture-upload.sh`,
`tests/test-seeds.sh`, `tests/test-trigger.sh`, `tests/test-theme.sh`,
`share/haseen/layers/theme/theme-lib.sh`,
`tests/fixtures/multipart-receiver.py`.
