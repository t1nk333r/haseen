# Plan 081: launcher providers for windows, emoji, menu commands and web search

## Status

- **Priority**: P2
- **Effort**: S each
- **Risk**: LOW (each provider off by default; exists only while the launcher is open)
- **Depends on**: 018 074
- **Category**: shell, launcher
- **Planned at**: 2026-10-07, gap 7 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-launcher-providers.sh`; nested screenshots of `@` and `/` queries)

## Change

Four new built-in `launcher-provider` plugins, one per prefix, each **off** in `default/shell.json`.
`haseen plugin enable <id>` turns one on (it goes in no bar section and no service list); Setup ›
Launcher Prefixes toggles them from the menu. The launcher creates enabled providers when it opens and
destroys them with it (unchanged), and now lists their prefixes under the empty input
(`haseen.launcher/Panel.qml:34`, `prefixHelp`; also in the debug IPC `state`).

| Prefix | Plugin | Rows | Enter |
|---|---|---|---|
| `@` | `haseen.windows` | `Hyprland.toplevels`: title over class and workspace, the class's desktop-entry icon (else the class as an icon-theme name, or a generic icon) | `hyprctl dispatch` focus (Process, `execDetached`) |
| `:` | `haseen.emojisearch` | `haseen.emoji/emojis.json` and its `EmojiSearch.js` match | `wl-copy -- EMOJI` (never typed, plan 018) |
| `/` | `haseen.commands` | the action leaves of `default/menu.jsonc` + `~/.config/haseen/menu.jsonc` merged by `MenuModel.js`; submenu path as subtitle | the action in bash with `bin/` first through `Apps.launch`, as the menu runs it; a bare `haseen shell ipc panel toggle ID` goes to this shell over `qs ipc --pid` |
| `?` | `haseen.websearch` | one row for the query, the template's host as subtitle | `xdg-open URL` through `Apps.launch` |

- **Windows** (`haseen.windows/Windows.js:27`): empty query = every window, most recently focused
  first (`focusHistoryID`); otherwise the launcher's `Fuzzy.score` over title, class (×0.9) and workspace
  name (×0.5), ties to the more recent window. `focusArgv` (`:75`) uses the running Hyprland's syntax:
  `hl.dsp.focus({window = hl.get_window("address:…")})` in a Lua config (haseen's, as `haseen.pager`
  does), `focuswindow address:…` in a hyprlang one. An address that is not `0x` + hex runs nothing, so a
  title can never reach the Lua string. `Hyprland.refreshToplevels()` once per open fills class and focus order.
  The class is client input (Wayland `app_id`, X11 `WM_CLASS`): without a desktop entry it is used only as an
  icon-theme name when it is plain letters, digits, `.`, `_`, `-` (`Windows.themeIcon`); anything else, such
  as `http://host/x.png` or `/path/x.svg`, gets `application-x-executable`. Before the review fix, the
  launcher loaded such a class as an image URL or file (`Panel.qml` `iconSource` passes `://` and `/` through).
- **Emoji** (`haseen.emojisearch/Emoji.js:10`): `EmojiSearch.filterEmojis`'s substring match, ordered
  keywords-start-with-the-word (the emoji's name), then whole word, then word prefix, then substring, each
  in the data's order; 50 rows. The list is read from `haseen.emoji`'s directory in the registry (a user
  copy wins), whether or not that panel is enabled.
- **Commands** (`haseen.commands/Commands.js:13`): a leaf is listed only when every `when` on it and on its
  submenus has answered true and its `disabled` guard (if any) answered false, **in this open of the
  launcher**: the provider runs one guard batch (`MenuModel.guardScript`) the first time `/` is typed
  (`Provider.qml:51`) and lists guarded rows only from its answers, which it also merges into
  `MenuModel.memory.guards` for the menu. An unknown guard hides the row: a guarded command never runs on a
  guess, nor on an answer cached by an earlier open (review fix; the provider first started from the cache).
  Ranking is the menu's own search (`matchesQuery`, `searchScore`); empty query keeps menu order.
- **Web search** (`haseen.websearch/WebSearch.js:11`): setting `url`, default
  `https://duckduckgo.com/?q=%s`. Only `http://`/`https://` templates whose authority is a fixed host name,
  IPv4 or bracketed IPv6 address with an optional port, with no whitespace or backslash and a `%s` after
  the authority, are accepted (review fix: `https://search.%s/` let the query pick the host); anything else
  shows a warning row and opens nothing. Every `%s` becomes
  `encodeURIComponent(query)` (`:34`), so the query cannot change the host or add parameters. The shell
  makes no request; `xdg-open` hands the URL to the default browser in its own scope (plan 074).

## Evidence

- `tests/test-launcher-providers.sh` (52 checks): each plugin validates, is off by default, `haseen plugin
  enable` turns it on in the user `shell.json` without a bar or service entry, `disable` turns it off; 59
  model units in the Qt JS engine (window ranking, bad addresses, both focus syntaxes; emoji tiers on a
  fixture and the real list; command leaves under unknown/true/false `when`, a guarded submenu, `disabled`,
  hidden parents, breadcrumbs, ✓, ranking, both run paths, guard merge, and no `when` row of the real
  default menu listed without answers; URL encoding, every refused template kind, including `%s`, userinfo,
  escapes and a backslash in the authority; a window class that is a URL or path becoming the generic icon);
  and the launcher with
  all four enabled in the real Quickshell engine against recording stubs: the prefixes listed, `?a b&c` →
  `systemd-run … --unit=app-haseen-haseen_websearch-… -- xdg-open https://duckduckgo.com/?q=a%20b%26c`,
  a window row → `hyprctl dispatch focuswindow address:0xab12`, `/fixture` lists only the unguarded rows
  until the batch answers, then the `when: true` row and never the `when: false` one, runs go through
  `systemd-run … bash -c … eval`, a panel row → `qs ipc --pid … call panel toggle`, `:red heart` → `wl-copy -- ❤️`,
  a hostile window class resolving only through `image://icon/`, and a second open listing no guarded row
  before its own batch answers.
- `tests/test-apps.sh`, `tests/test-calculator.sh`, `tests/test-menu.sh`, `tests/test-menu-view.sh` and the
  other suites reading `default/shell.json` or the launcher pass unchanged.

## Nested proof

`~/.cache/haseen-wt/scratch-providers/shots/` (worktree shell in a nest, `haseen.windows` and
`haseen.commands` enabled, driven through the launcher's debug IPC):

- `empty-help.png`: the empty launcher lists `= Calculator  > Clipboard  / Commands  @ Windows`.
- `windows-all.png`: `@` lists three foot windows on workspaces 1–3, most recent first; `windows-build.png`:
  `@build`. Accepting it moved the nest to workspace 3 with "Build log" active (`hyprctl -j activewindow`
  on the nest), so the Lua focus dispatch works; `windows-focused.png`.
- `commands-theme.png`: `/theme` → Theme (Style), Theme (Install › Style), Extra Themes (Update);
  `commands-foot.png`: the `when: haseen-cmd-present foot` row after the batch answered.

## Not verified

- Emoji and web search rows on screen in a nest (the engine test drives both; two providers per the brief).
- Running a menu command from `/` in the nest (it would change the scratch config through the owner's user
  systemd scope); the engine test covers the argv.
- `focuswindow` on a hyprlang (non-Lua) Hyprland.

## Rejected

- **Windows mixed into the app results without a prefix** (DMS Spotlight style): would change the
  launcher's ranking for everyone who enables it; `@` keeps app search as it is.
- **Commands listing submenus** (opening the menu there): the brief asks for leaves; the menu's own search
  finds submenus.
- **Running guarded rows whose answer is unknown, or skipping guards entirely**: a `when` hides "Stop
  recording" and laptop-only rows for a reason.
- **Suggestions while typing** (DuckDuckGo/Google suggest APIs): a network request from the shell for every
  keystroke; the brief forbids it.
- **A `:` provider inside `haseen.emoji`**: enabling the emoji panel would then also take the `:` prefix;
  each provider is its own plugin.
- **Showing guarded rows from the menu's cache until the batch answers** (and correcting the "never on a
  guess" claim instead): the cache lives for the shell's lifetime, so a row whose guard has since turned
  false (a package removed, a recording stopped) could run.
- **Fetching a window class that is a URL, behind the media panel's `remoteArt` opt-in**: the class is set
  by any client, not by the user; a generic icon costs nothing.
- **Repairing a template with `%s` in the host** (moving it to a query parameter): a refused template is
  shown as a warning row, the same as the other refused kinds.
