# UPSTREAM — haseen.todoist

`haseen.todoist` is a port of **omarchy-todoist**, MIT, Copyright (c) 2026
aryan-techie. `LICENSE` in this directory is the upstream licence, unchanged.

| | |
|---|---|
| Upstream | https://github.com/Aryan-Techie/omarchy-todoist (Omarchy plugin `io.github.aryan-techie.todoist`) |
| Ported from | the owner's fork `t1nk33r.todoist` 1.14.0, tracked as files in the owner's dotfiles (no commit of its own); its last change there is `e0e33cd todoist: close the credential-lifecycle holes and the badge lie (review)`, then the Qt 6.12 palette fix `88c47f7` |
| Copies compared | the haseen copy on IO (`~/.config/haseen/plugins/t1nk33r.todoist/`), the Omarchy copy on IO and luna's copy (`~/.config/omarchy/plugins/t1nk33r.todoist/`) are byte-identical (`diff -rq`, 2026-10-20) |
| Fork file hashes | `Model.js` sha256 `498655ea…be06`, `Panel.qml` sha256 `691aa91b…d20d` |
| Adopted | 2026-10-20 by the owner as a first-party plugin, off by default; ported in `plans/097-productivity-panels.md` |

## What changed

- **Names.** Plugin id `haseen.todoist`, display name "Todoist", IPC target
  `haseen.todoist`, role `todoist`.
- **Structure.** Upstream's bar widget kept a hidden `Panel.qml` alive to own
  the token, the list and the count, once per bar. Here `Service.qml` owns
  them once per shell, `Widget.qml` and `Panel.qml` read it through
  `Plugins.roles.todoist`, and the panel exists only while it is open. The
  task row, the settings section, the text field and the section label are
  their own files.
- **The token.** It stays where the owner keeps it: a private `settings.json`
  (0600) in a 0700 state directory, never in `shell.json`. The directory is
  `$XDG_STATE_HOME/haseen/todoist`, except that a HOME which already has
  upstream's `~/.local/state/omarchy/t1nk33r.todoist` and no haseen one keeps
  using that one in place, so a token stored there is never copied or moved.
  The shell no longer holds the token at all: `haseen-todoist.sh` takes it
  once on stdin (`set`), and for each request reads it from the file and gives
  curl the Authorization header as a config on a pipe (`-K <(printf …)`), so it
  is in no argv. Upstream kept the token in a QML property and a second copy in
  `curl-headers.conf`, kept in sync by synchronous FileView reads; that file is
  no longer written, and it is emptied whenever the token changes or is
  removed. Requests go only to `https://api.todoist.com/api/v1/` (the helper
  takes a path, never a URL).
- **Requests.** Upstream's rules are kept: `-w "\n%{http_code}"`, no `-f`, a
  10 s limit, the status classes and wording of `Model.statusMessage`, the
  paging (limit 200, `next_cursor`, at most 10 pages, `+` on a capped count),
  401/403 dimming the mark until the next good answer. New: `--proto =https`.
- **Theme.** Theme tokens and the shared `Pill` instead of `qs.Ui` and
  `qs.Commons`. Todoist's fixed priority colours (`#eb5757`, `#f2b84b`,
  `#4a90d2`) become the theme's urgent, warning and accent roles
  (`Model.priorityTone`).
- **Opening.** Tasks and todoist.com open with `xdg-open` through
  `Apps.launch`, outside the shell's cgroup.
- **Keys.** As upstream, except: Escape always closes the panel (haseen's host
  owns it; upstream first backed out of an edit or Settings); the Settings
  view has no Tab focus chain; Delete works beside `x`.
- **Model.js.** Upstream's file, plus `taskListPath`, `quickAddText`,
  `readSettings` (the token itself is never returned), the panel-size clamps,
  `priorityTone` and `sectionTitle`.

## What was dropped, and why

- **The keyboard-shortcut recorder and `set-keybind.sh`.** They edited
  `~/.config/hypr/bindings.lua`; haseen never edits a user's files after
  seeding them (CLAUDE.md). Bind `haseen shell ipc panel toggle haseen.todoist`
  in your own binds instead. A `keybind` key left in the settings file is kept
  and ignored.
- **The rotating header phrases.** A 2.8 s timer and a fade animation for
  decoration (architecture 6). The header shows the view and the sync time.
- **Omarchy host plumbing.** `KeyboardPanel`, popout switching, Tab to the
  neighbouring panel, `centerOnBar`: haseen's panel host places and closes
  panels itself.
- **Assets and docs.** The hero banner, preview, theme screenshot, Todoist SVG
  (unused by the fork, which draws a glyph), CHANGELOG, CONTRIBUTING, CODE OF
  CONDUCT and SECURITY files. The source rules in `tests/contract.test.mjs`
  were about the header file and are replaced by `tests/test-todoist.sh`.

## Tests

`tests/model.test.mjs` is upstream's suite, unchanged, and passes against this
`Model.js`. `tests/haseen.test.mjs` covers the additions. `tests/test-todoist.sh`
runs both, the helper (token only on the pipe, only to Todoist, 0700/0600, the
legacy directory, `--dry-run`) and the service, bar widget and panel in the
real Quickshell engine against a scripted curl.
