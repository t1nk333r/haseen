# Plan 198: the agents, accounts, typist and browser-picker findings of the 2026-11-24 audit

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Each fix is local to one command or plugin. The widest
  change of behaviour is `haseen agent crash`, which now opens the agent in
  a terminal window through `omarchy-agent` instead of running it in the
  caller's process.
- **Depends on**: 093 (omarchy-agent), 096 (typist, browser picker), 108
  (agent accounts), 124 (the CLIProxyAPI usage row), 132 (launcher
  accounts)
- **Category**: agents, plugins
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2026-11-24)
- **State**: DONE 2026-11-24 (`tests/test-adopted-tools.sh` 247/247,
  `tests/test-webapp.sh` 55/55, `tests/test-widgets-c.sh` 127/127,
  `tests/test-launcher-providers.sh` 68/68, `tests/test-agent-accounts.sh`
  357/358, the one failure the laptop's own, see Notes; review is the
  coordinator's)

## Problem

The audit ran on the plan 182 branch, before pull requests #140 to #142
merged. Every finding below was re-checked on main at
`9a9e82ab` (plan 184) before it was fixed; line numbers are main's before
this plan.

## 1. A renamed primary frees the id `main`, and `--reauth main` then signs in to the wrong home

`bin/haseen-agent-account-add:134` compared the argument with the literal
`main` (or `primary`) before looking at the registry, and ran
`login_primary` in the CLI's own home. `haseen agent account rename`
renames the primary too (it sets `.id = $new`), and `main` is not in
`AGENT_ACCOUNT_RESERVED` (`share/haseen/lib/agent-accounts.sh:52`), so an
account added later may take the id `main`. `haseen agent account use`
prints `--reauth $id` for a signed-out account
(`bin/haseen-agent-account-use:58`). Following it signed the added account
in over the primary's credentials in `~/.claude`, and left the added home
signed out.

**Fix.** `--reauth` looks the id up with `acct_find` first (which already
maps `primary` to the first login) and uses the CLI's own home only when the
entry found has `primary == true`. `main` still names the primary when no
account holds that id, as it did before the primary could be renamed. The
help text says so.

**Test.** `tests/test-agent-accounts.sh`: rename the primary to Personal,
add an account labelled Main (it gets the id `main`), and `--reauth main`
logs in in `$STATE/claude/main` while `~/.claude.json` still holds the
primary's email; `--reauth personal` and `--reauth primary` still log in in
`~/.claude`. Before the fix the first assertion read `home=$HOME/.claude`.

**Rejected.** Reserving `main`: an existing registry may already hold an
added account with that id, which would stay misrouted, and the literal
check would still bypass the registry.

## 2. The agents panel never read `cpa.json`

`share/haseen/shell/plugins/haseen.agents/Panel.qml:404` listed the usage
records as `["claude", "codex", "grok", "kimi", "fireworks"]`. Plan 124
added `share/haseen/libexec/agent-usage-cpa`, which
`omarchy-agent-usage-update` runs as agent `cpa` and writes to
`$USAGE_DIR/cpa.json` (`share/haseen/omarchy/bin/omarchy-agent-usage-update:22`,
`:83`), and `manifest.json:42` and `handoff.md:40` promise its row, but the
panel never read the file.

**Fix.** `cpa` joins the list. `Agents.usage` already reads its record
(`tests/test-widgets-c.sh` checks it on a cpa fixture).

**Test.** `tests/test-widgets-c.sh` now checks that the usage list names
every collector in `share/haseen/libexec/agent-usage-*`, and covers that
glob, so a new collector without a panel row fails. Before the fix: "the
panel reads cpa's usage record" failed.

**Rejected.** Reading the usage folder with a `FolderListModel`: it would
draw any stray JSON file there, and the order would be the file system's.

## 3. "Diagnose" on a crash notification could not start Claude, Codex or Grok

`bin/haseen-agent-crash:96` ran `exec "$agent" --prompt "$prompt"`. None of
claude, codex or grok has a `--prompt` option: each takes the prompt as a
positional argument, which haseen's `omarchy-agent` passes after `--`
(`share/haseen/omarchy/bin/omarchy-agent`, the `claude`, `grok` and `codex`
cases). The command also runs inside `haseen-crash-watch.service` when the
notification is clicked (`bin/haseen-crash-watch:50` hands the argv to
`haseen notification send --exec`), where there is no terminal for an
agent's interface, and it skipped the account pin. `tests/test-webapp.sh:121`
asserted `DRYRUN: claude --prompt`, locking the wrong syntax in.

**Fix.** The report goes to `$HASEEN_PATH/omarchy/bin/omarchy-agent
--prompt`, as Omarchy's `omarchy-agent-crash` hands its report to
`omarchy-agent-prompt`. That applies each agent's prompt syntax and
unattended flags, pins the account chosen with `haseen agent account use`,
and opens a terminal window with `haseen terminal run`. `omarchy-agent`
refuses an unset or uninstalled agent itself and names `haseen setup
default agent`. `--dry-run` passes through. The header's "haseen has no
agent-account machinery" was stale since plan 108 and is gone.

**Test.** `tests/test-webapp.sh`: the dry run plans `foot -e ... claude
--permission-mode auto -- A process crashed ...`, never `claude --prompt`;
codex gets `codex --approve-for-me --`; a real run with a stub terminal
starts the stub agent with the report as its prompt. The no-agent and
not-a-PID refusals still hold. The test now covers `omarchy-agent` and
`haseen-terminal-run`.

**Rejected.** Fixing the syntax in `haseen-agent-crash` itself: it would
copy `omarchy-agent`'s per-agent table, and still have no terminal or
account pin.

## 4. An account with no email and no typed name was labelled `null`

`bin/haseen-agent-account-add:211` and `acct_recover`
(`share/haseen/lib/agent-accounts.sh:622`) fell back to
`jq -r '.email | split("@")[0]'`. For an empty email that is `[][0]`, null,
which `jq -r` prints as the string `null`, so the `label=Account` fallback
never ran and the account was registered as `null`.

**Fix.** `(.email // "") | split("@")[0] // ""` in both places.

**Test.** `tests/test-agent-accounts.sh`: the fake Grok login gains
`FAKE_NO_EMAIL`, and an add with no name typed registers id `account`,
label `Account`. Before the fix it was `null null`.

## 5. Launcher account rows drew the wrong glyph and a stray digit

`share/haseen/shell/plugins/haseen.accounts/Accounts.js:36-38` wrote the
menu's Nerd Font glyphs as `"4"` and `"9"`. A `\u` escape takes
exactly four hex digits, so each was U+F06C or U+F06A followed by a literal
`4` or `9`.

**Fix.** The braced escapes `"\u{F06C4}"` and `"\u{F06A9}"`, the code
points of `default/menu.jsonc`'s agent glyphs.

**Test.** `tests/test-launcher-providers.sh` checked only that a glyph was
not empty. It now checks that each account row's glyph is one code point,
U+F06C4 or U+F06A9.

## 6. A second browser-picker request that arrived while the first was read was dropped

`share/haseen/shell/plugins/haseen.browser-picker/Service.qml:71-78`
replaced `requestReader.command` and set `running = true` without checking
whether the reader still ran. A running Quickshell `Process` does not
restart (the same file's `scan()` guards with `if (!scanner.running)`,
`:101`), so the second request file was never read, while the IPC call had
already returned the shell's PID (`:283`). Its caller,
`bin/haseen-browser-picker`, then waits on its FIFO for as long as the shell
lives.

**Fix.** `pick()` appends the request file to `requestQueue` and starts the
reader only when it is idle. `readNextRequest()` takes the next one,
answering an open card "nothing chosen" first as before, and the reader's
`onExited` reads the next file after starting the request it just read.

**Test.** `tests/test-adopted-tools.sh`: two picks back to back, both
matching a rule; both selection files get their own answer and both callers
are released. Before the fix only the first was answered.

**Rejected.** Reading the request with a `FileView`: a second request would
still have to wait for the first to be answered, which is the queue again.

## 7. The typist picker's snippet indexes were not the file's

`share/haseen/shell/plugins/haseen.typist/Picker.js:141-142` dropped
entries that are not objects or have blank text and renumbered the rest, and
`snippetRows` (`:163`) handed out those indexes. `Panel.qml:144` runs
`haseen typist type snippet <index> <md5>`, and `bin/haseen-typist:125`
reads `.snippets[$i]` from the file itself, so every snippet after a skipped
entry hashed to another entry's text and was refused ("That snippet changed;
open the picker again."). A pin or delete rewrote the file from the filtered
list, dropping what the user had written there.

**Fix.** `parseSnippets` keeps every entry at its place: a usable one
normalised to `{name, text}`, an unusable one exactly as written.
`snippetRows` skips the unusable ones but keeps the file's index, the one
the CLI reads. `pinSnippet` and `removeSnippet` keep the unusable entries.

**Test.** `tests/test-adopted-tools.sh`: the picker's rows keep the file's
indexes (`0:aaa`, `1:B` for the old fixture, `1:sig` after a blank entry),
pin and remove keep the blank and malformed entries, and the CLI types
index 1 after a blank entry. The panel's test hook tolerates a non-object
entry.

**Rejected.** Making the CLI apply the picker's filter before indexing: a
pin or delete would still drop the user's entries.

## 8. The typist worker promised its key codes kept the text out of `/proc`

`typist-worker.py:16-17`, `:133-139` and `:231-233` said the text never
reaches another process's argv, "where it would be readable in
/proc/<pid>/cmdline". The worker starts one `--keys` process per character
(`:237-240`), and the shim one `hyprctl dispatch` per key
(`share/haseen/shell/Compat/bin/ydotool:112`); their argvs hold the key
codes and Shift, which the layout maps back to the text, and `/proc` is
readable by every local account on Arch.

**Fix.** The comments now say what is true: no character is passed as text,
but the key codes spell it, so typing a password with typist on a machine
shared with another account shows it to that account. The worker's
behaviour is unchanged.

**Test.** `tests/test-adopted-tools.sh` checks the worker says the codes can
be read back and no longer says "where it would be readable".

**Rejected.** Writing the dispatches to Hyprland's socket from the worker,
or batching keys over stdin to a long-lived helper: either changes the
`--keys` interface the tests and the shim share, and needs a live Hyprland
to verify, which this batch may not touch. It is the way to real secrecy if
the owner wants it.

## 9. The browser picker routed backslash URLs on a host the browser does not load

`share/haseen/shell/plugins/haseen.browser-picker/Model.js:46-49` cut the
authority at the first `/` and kept what follows the last `@`. Browsers
follow the WHATWG URL standard, where `\` is a path separator in http(s)
URLs and tabs and newlines are dropped, so
`https://attacker.example\@bank.example/login` routed on a bank.example rule
and opened attacker.example in that profile without asking.

**Fix.** `hostOf` drops tabs and newlines and reads `\` as `/` for the
WHATWG special schemes (http, https, ws, wss, ftp, file) and for
scheme-less input, before cutting the authority.

**Test.** `model.test.js` (run by `tests/test-adopted-tools.sh`, now 42
cases): the backslash URL is attacker.example, `https:\\attacker.example`
too, and a tab or newline inside the authority is dropped as the browser
drops it.

**Rejected.** `new URL(text).hostname`: QML's JavaScript engine has no
`URL`, and the scheme-less fallback would still need this parser.

## Notes

Every new assertion was run against main's code with this plan's tests
(a detached worktree of `9a9e82ab`) and failed there: 10 in
`test-adopted-tools.sh`, 3 in `test-agent-accounts.sh`, 5 in
`test-webapp.sh`, 1 each in `test-widgets-c.sh` and
`test-launcher-providers.sh`.

`tests/test-agent-accounts.sh` "and says where a plain CLI follows it"
fails on the author's laptop before and after this plan: at that point the
test sets no `HASEEN_SYSROOT`, so `bin/haseen-agent-account-use:69` reads
the laptop's real `/etc/mise/conf.d/omarchy-agent-accounts.toml` (Omarchy's
mise wrapper is installed there) and prints the mise wording. CI has no
such file. It is a test-hermeticity defect outside this plan's findings.
