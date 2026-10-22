# Plan 108: several Claude, Codex and Grok accounts

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM. It touches how `claude`, `codex` and `grok` find their
  login. It is inert until used: with no account registry every lookup
  answers "the CLI's own home", exactly as before, and nothing signs in by
  itself. Credentials never leave the machine (no copy over SSH), and haseen
  never reads, prints or stores a token.
- **Depends on**: 093 and 102 (the `omarchy-agent-*` answers this replaces or
  extends), 100 (affected tests)
- **Category**: agents, Omarchy compatibility
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; owner steps below)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs
  stay as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "**Multiple Claude/Codex accounts**",
  "1-second boot menu", "New binds".

This plan implements "Multiple Claude/Codex accounts", off by default.
Earlier standing decisions it keeps: adopt all Omarchy commands except the
Apple-hardware ones (plan 093); a new built-in behaviour is off by default
unless the owner approved it on.

The owner also has a standing credential rule, kept in their private agent
instructions and not repeated here because it names a host: one named host
keeps its existing Claude route, official Claude sign-in there is prohibited
(including its containers, services and remote sessions), and it is excluded
from every distribution or sync of Claude OAuth tokens, refresh tokens and
login files; any transfer of official credentials needs an explicit
local-device allowlist. This plan therefore builds **no** credential transfer
(below), and gives every machine a way to refuse sign-ins before they start.

## Problem

Omarchy 4.5 lets one user keep several Claude Code, Codex and Grok
subscriptions and switch which one new sessions use. Verified against a
read-only clone of `basecamp/omarchy` at `v4.5.0-rc1` (no later change to
these files on `quattro`: `git log v4.5.0-rc1..origin/quattro --
bin/omarchy-agent-account-* etc/mise/conf.d/omarchy-agent-accounts.toml
bin/omarchy-agent bin/omarchy-default-agent bin/omarchy-agent-usage-update
shell/plugins/agents` printed nothing):

- c05d90196 (#13770): eight `omarchy-agent-account-*` commands (add, home,
  list, mode, remove, rename, state, use) over a Python registry
  (`bin/omarchy-agent-account-state`, 909 lines at the tag after 64ec3839a,
  #15399, added recovery of interrupted sign-ins); exec, copy and transfer
  came later (below), eleven in all. The CLI's own
  login stays the primary account; each added account gets
  `~/.local/state/omarchy/agents/accounts/<provider>/<id>/`, holding only
  its login, with history, settings and skills linked back
  (`PROVIDERS`, `bin/omarchy-agent-account-state@v4.5.0-rc1:35`;
  `link_shared`, `:295`). A login runs through the CLI's own command in a
  private browser window (`bin/omarchy-agent-account-add@v4.5.0-rc1:127,134-136`).
  Automatic switching near a limit picks the account with the most headroom
  from per-account usage (`decide`, `:678`; `usage_by_account`, `:722`;
  `autoswitch`, `:760`), refreshed by a panel timer that runs the collectors
  (`shell/plugins/agents/Main.qml:149`).
- f9646299b (#14233): `etc/mise/conf.d/omarchy-agent-accounts.toml` wraps
  every `claude`, `codex` and `grok` run in `omarchy-agent-account-exec`, and
  `omarchy-agent` pins the chosen account per launch
  (`bin/omarchy-agent@v4.5.0-rc1:167-174`).
- 10a8579a1 (#15405), 8dae158c4 (#15430): `omarchy-agent-account-copy HOST`
  bundles every signed-in account's credential files
  (`FILES`, `bin/omarchy-agent-account-transfer@v4.5.0-rc1:32`) and pipes
  them, with Python source, into `ssh -T HOST`
  (`bin/omarchy-agent-account-copy@v4.5.0-rc1:40`); the receiver runs that
  source with `exec(compile(...))` (`bin/omarchy-agent-account-transfer@v4.5.0-rc1:75`).
- 909946139 (#7261), 1cc5c72e2 (#7709), ed7bae4ac (#6900): new agents Kimi
  (`kimi --yolo`), Ori (`ori code`) and Antigravity (`agy
  --dangerously-skip-permissions`; `gemini` becomes an alias of it)
  (`bin/omarchy-agent@v4.5.0-rc1:63,124,135`;
  `bin/omarchy-default-agent@v4.5.0-rc1:30,36,41`).

haseen before this plan (main at 4786acb): plan 102 made the account answers
run Omarchy's installed copy, or refuse ("haseen has no agent accounts yet");
`omarchy-agent-account-home` called Omarchy's Python registry; copy and
transfer were refused; the agents panel (`haseen.agents`) listed running
processes only; `haseen setup default agent` did not know agy, kimi or ori.

## What was built

### 1. haseen's own accounts (`share/haseen/lib/agent-accounts.sh`)

A bash and jq rewrite of Omarchy's registry rules, under its MIT notice:

- The registry is `~/.local/state/haseen/agents/accounts/<provider>.json` in
  Omarchy's format (`active`, `switch`, `threshold`, `alert`, `accounts`),
  so either side can read the other's. Added homes live beside it.
- Identity (`acct_identity`, `:139`) reads only display-safe fields: Claude's
  `oauthAccount` (account id, email, organisation) and the plan name from
  `.credentials.json`; Codex's account id, and the email and plan claims
  decoded from the id token's payload; Grok's user id, email and cached plan
  name. jq picks those fields inside its own process, so no token reaches a
  shell variable, an argument or any output. The registry holds no token
  (test: "the registry holds no token").
- Private by construction: the commands run under `umask 077`, `acct_save`
  (`:241`) writes atomically through `replace_user_file` and sets 0600, and
  `acct_private_credentials` (`:309`) sets a new account's credential files
  to 0600 after its login. Every change goes through `run`,
  `replace_user_file` and `write_user_file` (dry-run contract); a dry run
  creates nothing and takes no lock.
- One `flock` per provider (`acct_lock`, `:233`) serialises the panel, a
  typed command and an Omarchy caller.
- Without a haseen registry, Omarchy's is read (`acct_registry_source`,
  `:113`) and never written: accounts added under Omarchy keep resolving, and
  haseen's first change adopts them, their homes left where Omarchy made
  them (test: "Omarchy's registry is never written").
- `acct_login_refused` (`:340`): a provider (or `all`) listed in
  `~/.config/haseen/agents/login-refused` or, for every user and service on
  the machine, `/etc/haseen/agents/login-refused` makes `add` stop before any
  login starts. haseen never writes either file.
- `acct_home_in_use` (`:320`): a home a running session selected (its
  `CLAUDE_CONFIG_DIR`, `CODEX_HOME` or `GROK_HOME` in `/proc/<pid>/environ`,
  this user's processes only, through `sysroot_path`) is never removed.

### 2. Commands (`bin/haseen-agent-account-*`)

`haseen agent account add [--check] [--reauth ACCOUNT] [provider] [label]`,
`list [provider] [--json]`, `use [provider] [account|next]`,
`rename [provider] <account> <name>`, `remove [provider] <account> [--yes]`,
and hidden `home <provider>`, plus `exec <provider> [args]`. The provider may
be left out when it is the default agent. Every mutating command takes
`--dry-run`.

- `add`: the first sign-in goes to the CLI's own home through the normal
  browser; each further one gets a pending home with the shared links, runs
  `claude auth login`/`codex login`/`grok login` there with `BROWSER` set to
  a one-file wrapper around `omarchy-launch-browser --private`, then, under
  the lock, is refused if the same account is already here, named, moved
  into place and registered. A login that did not finish, or a refusal,
  leaves no home behind (an `EXIT` trap). Missing CLIs are not installed
  (haseen installs no coding agent; plan 093).
- `remove` never removes the main login, never a home in use, deletes only a
  home haseen made, asks unless `--yes`, and never logs out (a logout would
  revoke the sign-in for every copy).
- `use`, `rename`: as Omarchy's, `rename` keeps the home where it is.

### 3. The `omarchy-agent-account-*` answers (`share/haseen/omarchy/`)

| Command | Before (plan 102) | Now |
|---|---|---|
| `add`, `list`, `use`, `rename`, `remove` | Omarchy's installed copy, or refused | haseen's command (`add` drops Omarchy's `--events` panel protocol; `remove` says `--yes` without a terminal, as Omarchy asks only on one) |
| `home` | pin, else Omarchy's Python registry | pin, else haseen's registry, else Omarchy's read directly: no Omarchy code runs on a launch |
| `state` | Omarchy's copy | `registry`, `list`, `home`, `homes`, `refresh` answered from haseen's registry in Omarchy's output shapes; the changes and internals (`begin`, `register`, `recover`, `link`, `autoswitch`, `mode`) refused |
| `mode` | Omarchy's copy | says accounts switch when told; `manual` succeeds, `auto` is refused with the reason |
| `exec` | unchanged (plan 102) | unchanged; resolves through `home` |
| `copy`, `transfer` | refused | still refused; the note now says the stream also carries code run on the other host |

The kinds in `commands.tsv` stay `translate`/`port`/`refuse`, as plan 102's
inventory records them.

### 4. Launches and usage records

- `omarchy-agent` pins the account chosen now for each new session, a port
  of Omarchy's pin (`share/haseen/omarchy/bin/omarchy-agent:165-172`): an
  explicit home still wins, a parent session's pin is not inherited, and the
  pin travels in the command because a terminal started through uwsm does
  not inherit the environment.
- `omarchy-agent-usage-update` runs the Claude, Codex and Grok collectors
  with the active account's home and stamps the record with `account: {id,
  label}` (`:63-74`), so a record describes, and names, the account new
  sessions use, as Omarchy's top-level limits do.

### 5. Agent names

`haseen setup default agent` and `omarchy-default-agent` know `agy`
(aliases `antigravity`, `antigravity-cli`), `kimi` (`kimi-code`) and `ori`
(`openrouter`); `omarchy-agent` starts them with Omarchy's flags; the menu's
Default Agent list offers them; the agents panel's scan looks for `grok`,
`agy`, `kimi` and `ori` too.

### 6. The agents panel (`share/haseen/shell/plugins/haseen.agents/`)

Two sections, both off by default (`settings.accounts`, `settings.usage`):

- Accounts: `haseen agent account list --json` once when the panel opens and
  on `r`; clicking an account runs `haseen agent account use` (the panel's
  only change of state), then lists again.
- Usage: one `FileView` per record in `~/.local/state/haseen/agents/usage/`,
  read when the panel opens. The panel never runs a collector, so it asks
  no provider for anything. This also settles the survey's B.2 #22 (the
  collectors had no reader).

No Timer, no polling: Omarchy's panel refresh timer (`Main.qml:149`) and its
30 s clock tick are not ported.

## Copying logins to another machine: not built

Omarchy's `omarchy-agent-account-copy` and `-transfer` stay refused. Reasons:

1. **The owner's standing rule.** Claude credentials must never reach one
   named host, and any transfer needs an explicit local-device allowlist. A
   deny by name cannot be made sound offline: SSH resolves a destination
   through `~/.ssh/config` aliases, `Hostname`, `Match exec`, `ProxyJump`
   and `ProxyCommand`, DNS (including CNAMEs) and bare IP addresses, so the
   string a user types says little about which machine receives the stream.
   `ssh -G` evaluates part of the config without connecting but still runs
   `Match exec` commands and cannot see DNS. Not determined without network
   access: what a typed name finally reaches.
2. **Code runs on the receiver.** Omarchy's stream carries Python source that
   the receiver executes (`exec(compile(...))`,
   `bin/omarchy-agent-account-transfer@v4.5.0-rc1:75`); haseen will not ship
   code to run on another host.
3. **One login on two machines.** Copying a refresh token gives two machines
   one sign-in. Whether a provider rotates refresh tokens so that one copy
   invalidates the other was not verified (INFERRED risk); signing in on each
   machine with its own CLI avoids the question.
4. Signing in on the other machine is already one command there
   (`haseen agent account add`).

## Credentials

- Kept only where the CLIs keep them: the CLI's own login writes them into
  the selected home. haseen never copies, moves (except the whole pending
  home into place, on the same filesystem), prints, logs or sends a
  credential file, and never stores one in `shell.json` or the registry.
- Modes: homes 0700, registry 0600, credential files 0600 after a login
  (tests: "the home is private", "its credentials are this user's alone",
  "the registry is private").
- Only an explicit `haseen agent account add` signs in; no seed, layer,
  migration, timer or panel does. The panel cannot add an account.
- Tests use fake CLIs whose files carry the marker `fake-token-not-a-secret`;
  every command's output is checked not to contain it.

## Outside the brief's owned paths

- `share/haseen/lib/agent-accounts.sh` (new, shared by the commands and the
  answers).
- `share/haseen/omarchy/bin/omarchy-agent`, `omarchy-default-agent`,
  `omarchy-agent-usage-update` (plan 093 ports): the pin, the names, the
  account a record describes.
- `share/haseen/default/menu.jsonc`: three Default Agent rows.
- `tests/test-omarchy-45.sh` (plan 102) and `tests/test-omarchy-system.sh`
  (plan 093): expectations for the answers and the launch pin.
- `NOTICE.md`, `handoff.md`.

## Rejected options

- **Run Omarchy's Python registry for haseen** (keep plan 102's
  pass-through): it exists only where Omarchy is installed, and haseen's
  commands would act on Omarchy's state. Rejected for an own registry in
  the same format.
- **A registry under `~/.local/state/omarchy`**: shared with Omarchy's own
  code; haseen reads it, never writes it.
- **Automatic switching near a limit (`mode auto`)**: it needs every
  account's limits, and haseen's collectors are 4.0.6 copies that read one
  home; Omarchy keeps them fresh with a panel timer (`Main.qml:149`), which
  haseen's no-polling rule (architecture §6) would need reworked. Deferred;
  `mode auto` is refused with that reason.
- **Mapping `gemini` to `agy`** as 4.5 does: Google's Gemini CLI still exists
  apart from Antigravity's, so a working `HASEEN_AGENT=gemini` would point at
  a command the user may not have. `gemini` stays its own agent; `agy` is
  added beside it.
- **haseen's own mise wrappers** (`[wrappers]` in a mise config) so plain
  `claude` follows the account on machines without Omarchy's
  `/etc/mise/conf.d/omarchy-agent-accounts.toml`: that would edit or add the
  user's mise configuration. Instead, sessions from the agent key and menu
  pin the account, `haseen agent account exec claude` runs one directly, and
  Omarchy's wrappers (on IO and luna) reach haseen's `exec`.
- **Notifications on switch** (Omarchy sends one): the CLI prints the result
  and the panel shows it; no new on-screen element.
- **An allowlisted SSH copy with a deny list**: see above.

## Tests

`tests/test-agent-accounts.sh` (new, 139 checks): no registry changes
nothing; first and further sign-ins; private-window login; modes; shared
links; display-safe registry; duplicate and unfinished logins; use, next,
pins and explicit homes; rename (reserved ids); remove (main, in use through
a fixture `/proc`, dry run, without yes, adopted homes kept); user and
machine sign-in refusals before any login; dry-run add; `--reauth`; Codex
and Grok identities; Omarchy's registry read and never written; every
answer; copy and transfer refused before SSH; the launch pin; the usage
record's account; the new agent names and menu rows.

Changed: `tests/test-omarchy-45.sh` (the account answers are haseen's;
Omarchy's copies never run), `tests/test-omarchy-system.sh` (the launch pin),
`tests/test-widgets-c.sh` (three Processes, both sections off, no collector
run; `Agents.accounts` and `Agents.usage` under the Qt JS engine).

Counts are in the pull request description: `tests/run.sh --affected
origin/main`, `tools/lint.sh`, `tools/check-docs.sh`, gitleaks over the
branch range and the privacy grep.

## Owner steps

1. On a machine whose policy forbids an official sign-in for a provider,
   create `/etc/haseen/agents/login-refused` (root, one provider per line, or
   `all`) before anyone uses `haseen agent account add` there.
2. To try it: `haseen agent account add claude Work`, then `haseen agent
   account use claude work`. New sessions from the agent key or menu start
   as that account; on IO and luna, Omarchy's mise wrappers also route plain
   `claude`/`codex`/`grok` through haseen's `exec`.
3. To see accounts in the agents panel, add to `~/.config/haseen/shell.json`
   under `plugins`: `"haseen.agents": {"settings": {"accounts": true}}` (and
   `"usage": true` for the usage records).
4. If you added accounts under Omarchy on IO or luna, `haseen agent account
   list` shows them ("read from Omarchy"); the first `use`, `rename` or
   `remove` adopts them into haseen's registry.

## Not done

- Automatic switching near a limit, and per-account limits (see Rejected
  options).
- Copying logins to another machine (refused, above).
- Adding an account from the panel (a login needs a terminal and a browser).
- Recovering an interrupted sign-in (Omarchy 64ec3839a, #15399): haseen's
  `add` removes its pending home on any exit it sees (an `EXIT` trap), but a
  process killed outright between the login and the registration leaves
  `~/.local/state/haseen/agents/accounts/<provider>/.pending/login-*` with
  that login in it, private (0700); signing in again adds the account, and
  the leftover can be deleted by hand.
- Verified only against fake CLIs: the real `claude auth login`, `codex
  login` and `grok login` with `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`GROK_HOME`
  set, and the panel sections on a live compositor, were not run (no live
  session or account was touched).
