# Plan 146: Claude accounts, the rest of Omarchy 4.5's release candidates

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW to MEDIUM. It adds one background job (a user timer that
  asks Anthropic for each Claude account's limits) and changes what `add`
  does with a finished login it could not register. Both stay inert on a
  machine with one Claude account, which is every machine until someone adds
  a second.
- **Depends on**: 108 (the accounts), 129 (plain `claude` follows the
  switch), 132 (the launcher's account rows)
- **Category**: agents, Omarchy compatibility
- **Planned at**: 2026-10-30, owner decision (below)
- **State**: DONE 2026-10-30 (`tests/test-agent-accounts.sh` 347/347, `tests/test-widgets-c.sh` 124/124; owner steps below)

## Decision (owner, 2026-10-30)

Asked for "multiaccount support for claude from the omarchy 4.5 RCs", the
owner was shown what plans 108, 129 and 132 already built from `v4.5.0-rc1`
and what the release candidates still have that haseen lacks, and chose:

- Build: "Per-account usage in the panel", "Panel controls", "Small faithful
  fixes".
- Not chosen: "Switch near a limit". `mode auto` stays refused, and haseen
  still sends no notification about limits.
- Refresh: "systemd user timer", described to the owner as running only
  while a provider has two or more accounts.
- Providers: "Claude only". The per-account limits are Claude's; the Codex
  and Grok collectors are unchanged.

## What the release candidates have (read-only clone of `basecamp/omarchy`)

`v4.5.0-rc2` (5978d93a, 2026-10-27) and `quattro` (432ae662, 2026-10-30)
change the account commands very little after rc1:
`git diff --stat v4.5.0-rc1 origin/quattro -- bin/omarchy-agent-account-*`
shows `exec` (+9/-2) and `state` (+1/-1) only.

- Per-account limits were already in rc1's Claude collector, which haseen
  never ported (haseen's collector is the 4.0.6 one, plan 093):
  `account_limits` (`bin/omarchy-agent-usage-claude@v4.5.0-rc1:1179`, from
  c05d90196, #13770) probes every registered account's home with a cache of
  its own, keyed by who the home is signed in as, and the record gains
  `accounts`; the top-level fields keep describing the active account. rc2
  moved the shared parts to `shell/plugins/agents/collectors.py`
  (`registered_accounts`, `account_entry`, `:3745`, `:3773`; 80e94608,
  #14040).
- Also in rc1 (75250d37, #14049): a lapsed access token whose refresh token
  is still good reads "Limits paused", not "Sign-in expired"
  (`bin/omarchy-agent-usage-claude@v4.5.0-rc1:1095`). An account that is not
  in use lapses within hours, so without this every parked account would say
  to sign in again.
- rc2 (80e94608, #14040): the weekly limit is the `seven_day` bucket;
  `seven_day_oauth_apps` is a side bucket Claude Code never shows as the
  week (`bin/omarchy-agent-usage-claude@origin/quattro:573`). haseen still
  preferred the side bucket.
- rc2 (e59c675c, #16593): `omarchy-agent-account-exec` appends mise's shims
  to the agent's PATH, so a long-lived session finds tools installed after it
  started.
- rc2: `grok_identity` guards a settings cache that is not an object
  (`bin/omarchy-agent-account-state@origin/quattro:189`).
- rc1 (64ec3839a, #15399): a login in progress keeps a receipt (its owner's
  pid and start time) in its pending home, and the next `add` registers a
  finished login whose owner died before registering it (`recover`,
  `bin/omarchy-agent-account-state@origin/quattro:404-478`;
  `bin/omarchy-agent-account-add@origin/quattro:189`).
- The panel adds and renames accounts (`shell/plugins/agents/Panel.qml@origin/quattro:292,362`)
  and keeps the limits fresh with a timer, every 15 minutes and every 3 near
  a switch threshold (`Main.qml:149`).

## A bug found on the way

haseen's Claude collector kept one limits cache, `claude-limits.json`, for
whichever home it read (`share/haseen/omarchy/bin/omarchy-agent-usage-claude`
before this plan, `collect_limits`). Its probe interval is 15 s, so a usage
update run within 15 s of a switch, or any run where the new account's
token had lapsed, showed the previous account's limits under the new
account's name.

## What was built

### 1. Every Claude account's limits (`omarchy-agent-usage-claude`)

The collector's bash part passes the registry it reads (haseen's, else
Omarchy's, `acct_load`) to its Python part in `HASEEN_AGENT_ACCOUNTS`, only
when Claude has two or more accounts. The entries carry ids, labels, homes
and display fields; the registry holds no token. The Python part, ported
from rc1's `account_limits` and rc2's `account_entry`:

- probes each account's home with its own token, one cache per account,
  `claude-limits-<accountUuid>.json` (the primary keeps
  `claude-limits.json` until its home says who it is);
- writes `accounts: [{id, label, email, plan, active, primary, limits,
  stale, fetchedAt, usageStatusText, authHelpText, retryAdvised}]`; the top
  level describes the active account, as before;
- with one account, keys the cache by the signed-in account too, which
  closes the bug above;
- reports "Limits paused" for a lapsed access token whose refresh token is
  good, "Sign-in expired" for a refused or fully lapsed one, marks numbers
  kept past a failed probe `stale` with when they were measured, and reads
  the weekly limit from `seven_day`.

Each token still goes nowhere but the Authorization header of its own
account's probe; the record and caches hold limits only (tests below).

### 2. The refresh (`haseen agent account usage`, a user timer)

- `bin/haseen-agent-account-usage` runs the Claude collector through
  `omarchy-agent-usage-update`. By hand it asks for fresh numbers
  (`--force`). With `--timer` it does nothing unless Claude has two or more
  accounts and the agents panel's usage section is on, so nothing asks
  Anthropic for numbers nobody reads.
- `haseen-agent-usage.timer` starts it 1 minute after it starts and every
  15 minutes after that. `haseen agent account add` enables and starts the
  timer when a second Claude account is registered; `remove` disables it
  when one is left. Both go through `run` (dry-run contract) and only warn
  when no user manager answers. An account registry adopted from Omarchy
  enables it on its first `add` or with
  `systemctl --user enable --now haseen-agent-usage.timer`.
- No 3-minute cadence near a limit: that served switching, which was not
  chosen.

### 3. The agents panel (`haseen.agents`)

- Usage: a record with `accounts` draws one line per account, the account
  in use first, each with its limits and how old they are when they are
  stale; a record without them draws its line as before.
- Accounts: `+ Add a Claude account…` under each listed provider (one row
  per provider when none is listed) runs `haseen agent account add
  <provider>` in haseen's floating terminal, as the launcher's add row does
  (plan 132), so the name prompt and the browser hand-off are the CLI's
  own, and the panel closes.
- Rename: a pencil on the hovered account row turns its label into a text
  field; Enter runs `haseen agent account rename <provider> <id> <name>`,
  Escape or leaving the field cancels. The list is read again afterwards.

### 4. Faithful fixes

- `omarchy-agent-account-exec` appends `<mise data>/shims` to the agent's
  PATH unless it is there (e59c675c).
- `add` writes a receipt, `.haseen-login.json` (0600: owner pid, its start
  time, the label; no credential), into each pending home. Its cleanup
  deletes a pending home only when no finished login is in it. Before a new
  additional sign-in, `add` (under the lock) registers every pending home
  whose owner has exited, which nothing runs in and which holds a finished
  login, deletes such a home without one, and leaves alone a home without a
  receipt (another, older `add` may still own it). A finished login that is
  already registered is deleted, as at a normal `add`. When it recovers one,
  it says so and starts no new login, as Omarchy's does.
- The Grok guard needed no change: haseen reads the plan in its own jq call,
  so a non-object `settings` costs only the plan name (test below).

## Rejected options

- **Switching near a limit** (`mode auto` and the manual mode's
  notifications): not chosen by the owner (above). `omarchy-agent-account-mode
  auto` stays refused, now giving that reason.
- **The panel's own timer** (Omarchy's `Main.qml:149`): the owner chose a
  systemd user timer, which keeps the collector's Python out of the shell
  process (architecture §6, "No Python for shell startup or polling").
- **A timer enabled by the shell layer on every machine**: it would wake
  every 15 minutes on machines with one account. Enabled by `add` instead.
- **An endpoint override for tests**: an environment variable that redirects
  the probe would send a real bearer token wherever it pointed. The tests
  seed fresh per-account caches instead, which the collector reuses without
  a probe.
- **Omarchy's in-panel sign-in** (`omarchy-agent-account-add --events`): a
  second sign-in flow. The floating terminal runs the one that exists.
- **Copying logins to another machine**: still refused (plan 108, and the
  owner's standing credential rule).

## Tests

- `tests/test-agent-accounts.sh`: per-account limits from seeded caches,
  stale and paused states, the single-account cache keyed by identity, the
  account in use leading, no token in any record or cache; `usage --timer`
  gated on two accounts and the usage section; the timer enabled by the
  second `add` and disabled by the `remove` that leaves one, in dry runs and
  with a stub `systemctl`; recovery of a finished login whose owner exited,
  a live owner's login left alone, a duplicate deleted, a home without a
  receipt left alone, a finished login kept when registering it fails (a
  read-only accounts directory, so that part is skipped as root); the exec's
  shims; the Grok guard; `mode auto`'s new reason. A proxy on a closed local
  port stands guard, so a probe that slipped past the seeded caches would
  fail without leaving the machine.
- The panel's new strings are in the English and Arabic catalogs
  (`tools/i18n.py check`).
- `tests/test-widgets-c.sh`: `Agents.usage` with accounts (order, stale age),
  the add rows and rename argv, the panel's Process count and argvs.

## Owner steps

- On a machine with two Claude accounts, turn on the panel's usage section
  (`settings.usage`), add or re-add an account, or run
  `systemctl --user enable --now haseen-agent-usage.timer`, and check the
  usage lines after a minute.
- Rename an account from the panel and check `haseen agent account list`.
