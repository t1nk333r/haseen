# Plan 132: Agent accounts in the launcher

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. It adds one launcher provider and one rule to the launcher;
  the rest of the launcher is unchanged, and a query that matches no account
  looks exactly as it did. Nothing runs while the launcher is closed, and the
  provider starts one read-only `haseen agent account list` per open.
- **Depends on**: 081 (launcher providers), 108 (the accounts), 122 (the
  launcher's at-rest height), 129 (a switch reaching a plain CLI)
- **Category**: agents, launcher
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26

## Decision (owner, 2026-10-26)

After plan 129 the owner wrote the three commands they use and asked for them
"in the launcher":

```sh
haseen agent account add claude work      # Claude's own sign-in, private browser window
haseen agent account use claude work      # new sessions use it; running ones stay
haseen agent account list
```

So the account workflow should not need a terminal first. Being in the
launcher means: open SUPER + D, type `account` (or `claude`, or the account's
name), Enter. A new prefix such as `&` would be a second thing to remember and
would say nothing when the owner types the word they actually mean, so the
rows are searched beside the apps instead.

## What changed

- **`share/haseen/launcher` rule — a provider with no prefix is searched
  beside the apps.** `haseen.launcher`'s `results` already handed the input to
  the first provider whose prefix it starts with; providers with an empty
  prefix are now asked as well, on every non-empty query, and their rows come
  before the fuzzy app matches. At rest (`text` empty) nothing is added: the
  empty launcher keeps the menu's ten app rows and so the menu's height
  (plan 122). `prefixHelp` already skipped an empty prefix, so the header line
  is unchanged. Documented in `docs/architecture.md` §5.2 and in the plugin
  skill.
- **`share/haseen/shell/plugins/haseen.accounts/`** — a new built-in
  launcher-provider, on by default (the owner's request is the approval;
  AGENTS.md records it):
  - one row per account a switch could mean — the providers with a login or
    more than one account, the account in use first (the agents panel's rule,
    plan 108), titled by its label, its detail line naming the provider, the
    address, the plan and `in use` / `signed in` / `signed out`;
  - `Add a Claude account…`, `Add a Codex account…`, `Add a Grok account…` —
    present even with nothing signed in, so a first sign-in is one Enter;
  - `Agent accounts`, the list.
  - Every row runs the CLI's own verb through `Apps.launch`, so the launcher
    and a typed command cannot drift: `agent account use <provider> <id>`,
    `agent account add <provider>`, `agent account list`.
  - Each runs inside `haseen config terminal -- …`, haseen's floating
    terminal: `add` needs a TTY for its "Name this Claude account:" prompt and
    `claude auth login`'s browser hand-off, and the other two print the
    sentence the owner needs to see ("New Claude sessions now use work…").
  - `haseen agent account list --json` is the only source of what exists: one
    read-only run when the launcher opens, no polling, and display fields
    only — no credential is read, printed or stored (plan 108).
  - `Accounts.js` holds the parsing, the matching and the argv as pure
    functions so the Qt JS engine can test them; the provider is the thin
    QML shell around them, and exposes `rowsFor(json, text)` for the
    real-engine test the way `haseen.windows` does.
- **`share/haseen/default/menu.jsonc`** — Setup › Launcher Prefixes gains an
  Agent Accounts row (and its on/off rows), so the menu says where the rows
  are and can turn the provider off without editing JSON.

## Evidence

- `tests/test-launcher-providers.sh` → 68/68: the provider validates, is on
  unless turned off, the JS model's rows/commands/translation, and the real
  engine — `account` lists the three add rows and the list row before any app
  row and nothing before the list answers; a fixture `--json` becomes account
  rows with the one in use first; Enter logs
  `haseen config terminal -- haseen agent account use claude work` through
  `Apps.launch`.
- `tools/lint.sh` → lint OK (920 shell, 348 QML, 207 JSON files).
- `tests/run.sh --affected` → 67 files, 6748/6749. The one failure is
  `test-menu-back.sh` and it is environmental: the test's IPC socket path is
  108 characters under this checkout
  (`…/cachyos-quickshellarchy/tests/.out/menu-back/run/quickshell/by-id/…/ipc.sock`,
  the `sun_path` limit), and the same test passes 24/24 from the same commit
  in a short worktree.
- `tools/check-docs.sh` → OK.

## Rejected options

- **A prefix (`&` accounts).** One more thing to remember, and typing
  `account` would still find nothing. The owner asked for the words they
  type.
- **Menu rows only** (`/` commands). `haseen.commands` is off by default, the
  rows would be fixed (`use next` at best, never a named account) and the
  owner asked for the launcher.
- **A panel of its own.** The agents panel already lists the accounts and the
  switch; a second panel would duplicate it, and the launcher row is the
  shorter path (no panel to open, no `haseen shell ipc` line to remember).
- **Reading the registry files directly instead of the CLI.** The signed-in
  state comes from each account's home through the CLI's own identity read
  (plan 108); a second implementation here would drift and would have to
  read credential files.
- **Running `use` silently and notifying.** A toast hides the sentence the
  CLI prints (which account, which plan, what stays); the floating terminal
  shows it and closes on Enter.
