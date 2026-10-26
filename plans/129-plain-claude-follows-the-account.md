# Plan 129: A plain `claude` follows the account switch

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. A shell function wraps a CLI only where an account registry
  exists, only when haseen's exec answer is installed and only for a CLI that
  is actually there. A machine with one login (the default) sees nothing new,
  and `command claude` still reaches the program.
- **Depends on**: 108 (the registry and the commands), 038 (the shell fragment)
- **Category**: agents, shell
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, "omarchy 4.5 has a way to change claude
  accounts").

## Why

Plan 108 brought Omarchy 4.5's several Claude/Codex/Grok accounts to haseen:
the registry under `$HASEEN_USER_STATE/agents/accounts/`, `haseen agent
account add|use|list|…`, Omarchy's own `omarchy-agent-account-*` answers, and
the agents panel's Accounts section. One piece stayed Omarchy's: the *system
mise wrapper* that routes every `claude`, `codex` and `grok` through
`omarchy-agent-account-exec`, so a switch reaches the next command typed in a
terminal that is already open. Plan 108 says so in
`haseen agent account use --help`: "a plain claude … follows it only where
Omarchy 4.5's mise wrapper … is installed".

A haseen machine need not have that file. This one does not:

```
$ ls /etc/mise/conf.d/
omarchy.toml
```

So `haseen agent account use work` changed the registry while a plain
`claude` kept using `~/.claude` — the switch only worked through
`omarchy-agent`, the panel and `haseen agent account exec`.

## What changed

- **`share/haseen/default/shell/functions.sh`** — after the ordinary
  functions, defines `claude`, `codex` and `grok` as functions that run
  `omarchy-agent-account-exec <provider> "$@"`. Probes live at *call* time,
  exactly like a mise wrapper, so a switch applies to the next command in an
  open terminal rather than only to terminals opened afterwards.
  - Defined only when a registry exists — haseen's
    (`$HASEEN_USER_STATE/agents/accounts/`) or the one Omarchy 4.5 wrote
    (`$XDG_STATE_HOME/omarchy/agents/accounts/`), which plan 108's answers
    already read — and only for a provider whose CLI is on `PATH`.
  - These wrap a program on `PATH` on purpose, unlike every other function in
    the file; the comment says why, and `command claude` still bypasses.
- **`bin/haseen-agent-account-use`** — the help text and the post-switch line
  say where a plain CLI now follows the choice: a haseen shell (and every
  mise shim once Omarchy's wrapper exists), and to use
  `haseen agent account exec` from a script or a GUI launch.
- **`tests/test-shelltools.sh`** — the wrapper appears with either registry,
  runs the CLI through the account, is absent with no registry, absent for a
  CLI that is not installed, and leaves the program reachable (`type -P`).
  `tests/test-agent-accounts.sh` carries the new wording.

## Evidence

- `tests/test-shelltools.sh` → 158/158, `tests/test-agent-accounts.sh` →
  288/288.
- On luna, with a scratch registry:
  `type -t claude` → `function`, `claude --version` → `2.1.310 (Claude Code)`
  through `omarchy-agent-account-exec`; with no registry `type -t claude` →
  `file` and the CLI runs untouched.

## Owner steps

```sh
haseen agent account add claude work     # signs in through Claude's own login
haseen agent account use claude work     # new sessions use it; running ones stay
haseen agent account list                # what exists, which is active
```

The account's credentials stay in its home on this machine; nothing copies,
prints or sends them (plan 108), and the Eris restriction stands — that host
stays on CPA and receives no Claude login.

## Rejected options

- **Ship a mise conf of haseen's own** (`~/.config/mise/conf.d/…toml`). It
  only works where mise is installed and only for commands mise shims, and it
  would put a second, competing wrapper next to Omarchy's on the machines
  that have both.
- **Export `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`GROK_HOME` at shell start.** It
  fixes new terminals only: a switch would not reach a terminal that was
  already open, which is exactly the case Omarchy's wrapper handles.
- **Rewrite the user's `~/.bashrc`.** The fragment is sourced from it; haseen
  never edits the rc beyond the one include line it seeds (plan 038).
