# Plan 012: AI panel plugin and the haseen agent skill

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 005 006
- **Category**: ai
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. Live chat, stop and policy refusal were verified over IPC, and the skill's plugin steps were followed end to end in a scratch HOME. The panel has no idle cost until it is first opened.

## Why this matters

Requirement 2 (an agent can extend the desktop safely) and requirement 6 (local AI in the UI).

## Scope

- `haseen.ai` panel plugin: OpenAI-compatible streaming chat, local-only policy by default.
- `share/haseen/agents/skills/haseen/SKILL.md` and its topic files.
- `haseen ai skill install` symlinks the skill into agent skill directories.

## Acceptance

- A live chat against Ollama, or a stub endpoint.
- An agent following only the skill creates a working plugin.

## Execution record

Executed 2026-10-04 against quickshell 0.3.1 and Hyprland 0.56 (Lua) on the live session, beside the other agents' instances. No commit (integrator).

### What changed

| File | Role |
|---|---|
| `share/haseen/shell/plugins/haseen.ai/manifest.json` | `panel` kind, setting `endpoint` (empty = ai.json `default`), permissions `exec network:local files:write` |
| `share/haseen/shell/plugins/haseen.ai/Panel.qml` | the chat panel: header (endpoint, policy badge, model picker, new chat), message list, input, send/stop |
| `share/haseen/shell/plugins/haseen.ai/MessageView.qml` | one message: role/model line, selectable plain text, copy button on hover |
| `share/haseen/agents/skills/haseen/{SKILL,plugins,hyprland,theming,ai}.md` | the end-user agent skill (structure adapted from Omarchy's skill, MIT) |
| `bin/haseen-ai-skill-install` | `haseen ai skill install [--dry-run]`: one `run ln -sfn` per present agent |
| `tests/test-aipanel.sh` | 75 assertions (below) |

**The panel never speaks HTTP.** On open it runs `haseen ai config` (merged, validated ai.json), then `haseen ai models --endpoint <ep>`; each runs once, with no polling and no timers. A message runs
`setsid bash -c '<wrapper>' haseen-ai-chat <bin>/haseen ai chat --endpoint <ep> --model <m>`, where the wrapper writes the conversation (JSON `[{role, content}]`, from stdin) to a `mktemp` file in `$XDG_RUNTIME_DIR` (mode 0600), opens it on fd 3, unlinks it and `exec`s the CLI with `--messages-file /dev/fd/3 </dev/null`. So the loopback-only `local` policy, endpoint resolution and keyRef handling stay in `layers/ai/ai.sh`, the conversation never appears in argv, and nothing is left on disk. Stdout is read with `SplitParser { splitMarker: "" }`, so every chunk lands as it arrives. `bin/haseen` is found as `$HASEEN_PATH/../../bin/haseen`, which works for the checkout, `/usr/local`, `/usr` and the Nix package (`$out/share/haseen` → `$out/bin/haseen`).

- **`haseen ai chat` change.** The CLI had no history input. Main added `--messages-file FILE` on request (tested in `tests/test-ai.sh`), and the panel uses it. The interim flattened-transcript fallback was dropped.
- **Stop.** Escape or the stop button runs `kill -TERM -- -<pid>`. `setsid` makes the chat the leader of its own process group, so curl, sed and jq die too. Without that, a reasoning model emitting only `reasoning` deltas would keep generating, because jq would never write and so never hit SIGPIPE. Closing the panel mid-reply stops it the same way (`Component.onDestruction`).
- **State.** The conversation and the chosen model are kept in `~/.local/state/haseen/ai/chat.json` (FileView, written when a turn starts and ends, never per token). An accidental outside click therefore loses nothing; "+" starts a new chat.
- **Text is plain text** (`TextEdit.PlainText`, selectable). Copy uses `Quickshell.clipboardText`.
- **Keys.** Enter sends, Shift+Enter inserts a newline. Escape closes the picker, else stops a running reply, else closes the panel.
- **Skill install.** It covers the agents Omarchy provisions (`bin/omarchy-provision-user`): `~/.agents`, `~/.claude` (`$CLAUDE_CONFIG_DIR`), `~/.codex` (`$CODEX_HOME`), `~/.pi/agent`, `~/.gemini` → `config/skills`, `~/.hermes` plus `profiles/*`. Only agents whose home exists get a link; a missing `skills/` dir is created with `run mkdir -p`. A link that is already correct is reported and skipped, a stale link is replaced, and a real file or directory named `haseen` is left alone with a warning.
- **The skill.** `SKILL.md` covers the hard rule (never edit `$HASEEN_PATH`), the user-owned file table, command discovery, IPC, the change workflow, verification, troubleshooting and the decision framework. The topic files are:
  - `plugins.md`: kinds, the seven-step new → edit → validate → enable → reload → verify flow with a load-average example, manifest fields, the entry contract, Theme tokens, resource rules, the bar layout, overriding a built-in, removal.
  - `hyprland.md`: the ownership table, the `haseen.*` helpers, unbind-before-rebind, monitors, `local.lua`, window rules, `hyprctl configerrors`.
  - `theming.md`: overlay vs new theme, token keys, fonts and sizes, user templates, hooks.
  - `ai.md`: ai.json keys, never store keys, never flip `policy` on your own, the panel.

### Evidence

- `tests/run.sh tests/test-aipanel.sh` → `75/75 passed`. Coverage:
  - `haseen plugin validate haseen.ai` ok, with no network warning.
  - The panel calls `ai config`, `ai models` and `ai chat --messages-file /dev/fd/3`, and has no `"curl"` and no XMLHttpRequest.
  - Stop kills the process group; the chunk parser is `splitMarker: ""`; no Markdown or rich text.
  - Every chat flag the panel passes exists in `bin/haseen-ai-chat`.
  - The wrapper is extracted from Panel.qml and run against a fake chat: `--messages-file /dev/fd/3`, the history is readable on fd 3, and `tmp-left:0`.
  - Skill front matter is checked; every linked topic exists and every topic is linked.
  - Every `haseen …` command in the skill's code resolves to a `bin/` command (drift guard).
  - The skill's plugin steps run hermetically: new → the plugins.md example as Widget.qml → validate → enable → `bar.right`.
  - Skill install with no agents: says so, creates nothing. An extra argument gives exit 2. The router lists `haseen ai skill install`.
  - Dry-run plan per present agent home: claude gets `mkdir -p` + `ln -sfn`, codex an `ln -sfn` without mkdir (its skills dir exists), hermes and `profiles/work` get links, exactly 4 links, and absent agents stay untouched. Purity: no STUB-CALLED, and `find $HOME` is identical before and after.
  - A real run creates links that point at the skill. A re-run says `already linked` and leaves `$HOME` unchanged.
  - A stale link is replaced; a user's real `~/.agents/skills/haseen/` is kept and warned about. `CODEX_HOME`/`CLAUDE_CONFIG_DIR` are honoured.
- `/tmp/tools/shellcheck --severity=warning -x bin/haseen-ai-skill-install tests/test-aipanel.sh` → rc 0; `bash -n` ok; `jq empty` on the manifest ok; qmllint (`tools/lint.sh` flags) on both QML files → 0 `Error:` lines (only the usual unresolved `qs.Haseen` import warnings).
- **Live chat** (stub OpenAI server: python3 `http.server` on 127.0.0.1 with a random port, two models, 0.15 s between chunks, a `slow` mode at 1 s per chunk, logging each request; scratch `XDG_CONFIG_HOME`/`XDG_STATE_HOME` with `ai.json` → `"default":"stub"`):
  - `panel toggle haseen.ai` opened `haseen-panel 522,58 492x622`. Screenshot: `stub` · "local only" badge, picker showing `stub-small`, empty-state text, focused input.
  - Message typed with `wtype` + Return. A screenshot 1.2 s in shows `[stub-small] turn 1 of the conversation. You said:` with `stub-small · …` and the stop glyph; 4 s later the full reply. Server log: `{"model": "stub-small", "messages": [{"role": "user", …}]}`.
  - Second turn after `shell reload`: the conversation was restored from chat.json, and the server received `user, assistant, user` (history via `--messages-file`). Screenshot shows `turn 2`.
  - Stop: a `slow` reply, then Escape. Before: wrapper, `haseen-ai-chat` and `curl` processes plus `haseen-ai-chat.waUaX3` in `/run/user/1000`. After: no processes, no temp file, the server logged `CLIENT-GONE`, the panel stayed open and the message shows `stub-small · stopped` with the partial text. During a run the temp file mode was `600`.
  - Closing the panel mid-reply (`panel close`): no processes and no temp file afterwards. The first version used a trap to delete the file and left `haseen-ai-chat.sHrhAa` behind, because the host kills the process before the trap runs. Unlinking after the fd-3 open fixed it, and the re-test showed 0 files.
  - Policy: with `{"default":"remote", … "url":"https://api.example.com/v1"}`, the header shows the CLI's refusal (`Error: endpoint 'remote' (api.example.com) is not on this machine and ai.json policy is "local". …`), the reply bubble shows it in the urgent colour with a red border, and the server received nothing.
  - Picker and copy, using a throwaway user-copy override in the scratch config: `picking: true` rendered the dropdown with `stub-small` (highlighted) and `stub-large`. A `copytest` hook calling the same `Quickshell.clipboardText =` path put the last message into the clipboard (`wl-paste` → `should be refused`). The user's clipboard was restored afterwards.
  - Final code, IPC only (no keyboard, in an isolated `XDG_RUNTIME_DIR`): a throwaway override that sends once models load. The mid-stream screenshot shows `turn 3 … You said:` and the final one the full reply. The server received `user, assistant, user, assistant, user`.
- **Skill acceptance** (scratch `HOME=/tmp/skillhome/home`, scratch `XDG_RUNTIME_DIR` so IPC reached only this instance, following only `plugins.md`):
  - `haseen plugin list`, then `haseen plugin new alice.load --kind bar-widget`.
  - The plugins.md example was written to Widget.qml, then `haseen plugin validate alice.load` → `ok: alice.load (user: …)`, `haseen plugin enable alice.load`, `haseen shell ipc shell reload`.
  - `haseen shell ipc shell plugins | jq '.plugins[] | select(.id == "alice.load")'` → `"valid":true,"enabled":true,"listed":true,"errors":[]`, and `.errors` → `[]`.
  - In the log there was a single `unknown plugin id 'alice.load'` line before the reload and none after.
  - Screenshot of the bar's right end: tray, `40%`, wifi, `50%`, then the gauge glyph and `1.45`, matching `/proc/loadavg` (`1.41 1.45 …`).
- **Resources** (isolated runtime dir; full default bar plus the other agents' current services; software backend):

| state | RSS | PSS |
|---|---|---|
| tree without `haseen.ai`, idle 30 s | 195328 kB | 136632 kB |
| with `haseen.ai`, idle 30 s (never opened) | 191028 kB | 129436 kB |
| panel open | 203404 kB | 135052 kB |
| closed, 10 s later | 201396 kB | 134013 kB |
| 60 s later | 201076 kB | 136780 kB |

  - Until it is opened, the panel costs nothing measurable; the difference is within run-to-run noise.
  - After the first open and close, RSS stays about 10 MiB higher. That is the cached compiled QML plus heap the allocator keeps; PSS moves by under 1 MiB.
  - CPU: 2 ticks (0.02 s) in 60 s of idle after closing.

### Rejected

- **Calling the HTTP API from QML (XMLHttpRequest).** It would duplicate the ai.json merge, the loopback policy and the keyRef/Secret Service handling, and it would put the key into the shell process. The CLI keeps them in one place, as the task asks.
- **Flattening the history into one user prompt.** This was used briefly before `--messages-file` existed. It would lose the roles the model needs, and the conversation would cross on stdin. Replaced as soon as Main added the flag.
- **A trap that deletes the temp file.** The process can be killed before the trap runs; observed leftover above. The file is now unlinked right after it is opened.
- **Signalling only the bash pid on stop.** curl and jq would outlive it; see "Stop" above.
- **Markdown or rich text for replies.** Qt's text engine would fetch remote `![](http://…)` images named in a model's reply. That is a network side channel out of a "local only" panel. Plain text is selectable and safe.
- **QtQuick.Controls (ComboBox, TextArea, ScrollView).** These need a style and load a large module into an idle-sensitive shell. The picker and input are plain `Rectangle`/`TextEdit`/`BarButton`.
- **Linking into every agent dir, as Omarchy does (`mkdir -p` for all six).** That creates empty dot-directories for agents the user does not have. Only present agent homes get a link.

### Open risks

- [INFERENCE] Not run against a real Ollama or llama-server, only the stub, as in plan 006. Only `delta.content` is shown, so reasoning tokens (qwen3 `reasoning`) do not appear while the model thinks; the reply shows `…` until content arrives.
- Clicks were not exercised live: no pointer injection tool is installed. The send and stop buttons, the picker entries, the copy button and the outside-click close all rest on the same functions verified via keys and the probe overrides.
- After `--messages-file` is used, the CLI may still append stdin as a prompt. The wrapper passes `</dev/null`, so that never happens from the panel.
- When the conversation exceeds the model's context window, the server truncates it or errors; the error is shown in the bubble. The panel does not trim the history itself; "+" starts over.
- On NixOS the installed link points at the current store path. After an update plus GC it dangles until `haseen ai skill install` runs again; the stale link is then replaced. The Nix module could run it on activation (plan for the nix slice).
- [INFERENCE] The ~10 MiB retained after the first open is allocator and type-cache memory, not a leak; repeated open/close cycles were not profiled beyond the one cycle above.
- Live-session incident: during the first smoke, a `wtype` meant for the panel went to the focused terminal after the panel had closed. Keyboard input is no longer used for live checks; the final verification ran over IPC only.
