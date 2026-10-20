# UPSTREAM — haseen.typist

`haseen.typist` is a port of **Typist**, MIT, Copyright (c) 2026 sanjuanjor.
`LICENSE` in this directory is the upstream licence, unchanged.

| | |
|---|---|
| Upstream | https://github.com/sanjuanjor/typist (Omarchy plugin `io.github.sanjuanjor.typist`) |
| Ported from | the owner's fork `t1nk33r.typist` 1.1.0 (picker panel, snippets, recent clipboard rows, vim keys), tracked as files at `~/.config/omarchy/plugins/t1nk33r.typist` on luna (yadm, last `88c47f7`) and copied unchanged to IO's `~/.config/haseen/plugins/` and `~/.config/omarchy/plugins/` (all three copies identical, `diff -rq`) |
| Fork file hashes (sha256, first 12) | `typist` `0ec69718ba6c`, `typist_worker.py` `0cc2adfb7cf5`, `Picker.js` `e7dd2c901385`, `Panel.qml` `da142b777f47` |
| Ported | 2026-10-20, plan `plans/096-adopt-tools-forks.md` (owner decision of 2026-10-20) |

## What changed

- **Names.** Id `haseen.typist`, command `haseen typist` (`bin/haseen-typist`),
  worker `typist-worker.py`, unit `haseen-typist.service`, snippets in
  `~/.config/haseen/typist.json`.
- **Typing path.** Keys go through haseen's `ydotool key` shim
  (`share/haseen/shell/Compat/bin/ydotool`), which sends Hyprland
  `send_key_state` dispatches to the session's own instance: no ydotoold, no
  `/dev/uinput`. The unit gets `HYPRLAND_INSTANCE_SIGNATURE` explicitly.
  The shim has no Hyprland mod name for AltGr (LevelThree/Mod5), so a
  character the layout reaches only through AltGr is skipped and counted,
  where the fork would have sent it with that modifier.
- **Recent rows** are haseen.clipboard's cliphist store, addressed by
  cliphist id (never reused); a pin decodes the entry in full first, because
  cliphist's preview is truncated. The fork read Omarchy's
  `clipboard-history.json` by index plus md5.
- **Settings** are the manifest's, in `shell.json`. The fork's right-click
  settings menu (`omarchy-menu-select`) and its drawer (`nook-offload`)
  writer are dropped: haseen.settings edits manifest settings, and right
  click opens the snippets file instead.
- **Empty input** is refused with a notice; the fork typed a space.
- **Failures** are reported through `haseen notification send`.
