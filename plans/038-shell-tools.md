# Plan 038: Shell rc layer — tools, aliases, functions, `mise activate`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (one include line in the user's rc; every tool behind `command -v`)
- **Depends on**: 001 017 023
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (items 21–23: `mise`, `gh`, omarchy shell-tools / shell-functions / TUIs)
- **State**: DONE 2026-10-05

## Problem

haseen had **no shell rc layer at all**. `grep -rn 'alias \|bashrc\|zshrc' share bin`
found exactly one hit, `share/haseen/lib/catalog.sh:225-228`, which *read*
`~/.bashrc` to check for `mise activate` and printed advice. Two consequences:

- Every alias and all 21 functions Omarchy documents were absent by
  construction (`/tmp/haseen-research/OmarchyManual.md` §1–§2, §7.1).
- `haseen install <development entry>` installed a runtime through mise and
  then left it off `PATH`, because nothing ever wrote the activation line.

Nine of the nine documented shell tools were missing except `fzf`, `ripgrep`
and `fd`, which the base layer already had.

## Decision

- **Three haseen-owned files** under `share/haseen/default/shell/`
  (`aliases.sh`, `functions.sh`, `init.sh`), pulled in by **one** include line
  that `share/haseen/seeds/60-shell.sh` appends to `~/.bashrc` (and to
  `~/.zshrc` only when that file already exists). This is
  `docs/architecture.md` §3's seeding rule applied to the rc: the user's file is
  written once, haseen's behaviour lives in `default/` and upgrades without ever
  touching it again.
- **Every tool is guarded by `command -v`.** A login shell that errors on every
  prompt because `eza` is missing is worse than having no alias.
- **`mise activate` is written, not advised.** `catalog.sh` now only checks, and
  points at `haseen seed user` when the line is absent; one writer, no race.
- **One multiplexer resolver** (`_haseen_mux`) behind all eight layout names
  (`tdl tds tdlm tsl` and `hdl hds hdlm hsl`), resolving
  `HERDR_PANE_ID` → `TMUX` → `~/.config/haseen/mux` → herdr installed → tmux
  installed. The owner ships both with herdr as the default (plan 044), and
  muscle memory for either prefix works.
- **`append_user_file`** joins `write_user_file` / `append_root_file` in
  `share/haseen/lib/common.sh`: the rc is the one user file haseen must *extend*
  rather than create, and the dry-run plan has to show exactly the line that
  lands. Idempotency stays in the seed (`grep -qsF`), not in the helper.
- **Packages** (all `extra`, verified with `pacman -Si`): `zoxide 0.10.0-1`,
  `eza 0.23.5-2`, `bat 0.26.1-2`, `tealdeer 1.9.0-1`, `yt-dlp 2026.08.19-1`,
  `lazygit 0.65.0-1`, `dua-cli 2.44.0-1`, `github-cli 2.100.0-1`,
  `mise 2026.9.1-1`, plus `tmux` and `yazi` for plans 044 and 037.
- **Owner decisions 2026-10-08.**
  - The one appended include line in an existing `~/.bashrc`/`~/.zshrc` is
    accepted (D12); `AGENTS.md`'s seed rule names it as the one exception.
  - Only `zoxide`, `eza` and `bat` go into the base layer, because the rc
    fragment wires them into every shell. `github-cli`, `lazygit`,
    `dua-cli`, `yt-dlp`, `tealdeer` and `mise` become catalogue entries
    (`haseen install app gh|lazygit|dua|yt-dlp|tealdeer|mise`); the fragment
    guards each one with `command -v`, and `mise_install_tools` still installs
    `mise` on first use (D6). `tmux` and `yazi` land with plans 044 and 037.

## Rejected

- **fastfetch, walker, elephant**: full duplicates of `bin/haseen-about`
  (`menu.jsonc:32`) and `haseen.launcher` / `haseen.menu`
  (`/tmp/haseen-research/OmarchyManual.md` §6).
- **`tldr` (Python, `extra 3.4.4-1`)** in favour of `tealdeer` (Rust, same
  `tldr` binary) — the owner asked for the Rust client.
- **Aliasing `cd` to zoxide**, which Omarchy does: silently landing somewhere
  else after a typo is a bad default in a shell that also runs the owner's
  scripts. `z` / `zi` are there deliberately.
- **`iso2sd` and `format-drive`**: both run privileged destructive commands
  against a whole disk. In haseen every privileged mutation goes through
  `lib/common.sh` and takes `--dry-run`; an rc function can do neither, and
  `sudo` must not appear outside `common.sh` (AGENTS.md). `haseen drive select`
  and `haseen drive info` already own the interactive part.
- **The `ssh` reconnect wrapper**: wrapping a core binary in a retry loop for
  every login shell is a surprise that cannot be opted out of per invocation.
- **Writing the mise line from `catalog.sh`**: a second editor of the user's rc,
  racing the seed.
- **`write_user_file` for the append**: it rewrites the rc wholesale and would
  print the whole file in every dry-run plan.

## Verification

- `tests/test-shelltools.sh` (100) and `tests/run.sh tests/test-shelltools.sh
  tests/test-seeds.sh` → 175/175; with `test-core.sh` and `test-catalog.sh` →
  271/271.
- `/tmp/tools/shellcheck --severity=warning -x` clean on every new file.
- **Live round trip** in a scratch `HOME` through the seeded rc: `compress` →
  `decompress` recovered the file; `ga` created `project--feature` as a real
  worktree and `gd` removed it and deleted the branch, refusing with
  `gd: project is not a <repo>--<branch> worktree` outside one; the same trace
  shows `mise hook-env … --reason chpwd` firing, i.e. activation really runs.
- Seeding twice leaves exactly one include line, and the second `--dry-run`
  plans nothing.

## Open

- **zsh is not installed on the reference machine**, so `zsh -n` could not be
  run. The test asserts it the moment zsh exists; the fragments avoid the
  constructs that differ.
- `hunk` (Omarchy's diff watcher) is not a haseen package, so the `tds`/`hds`
  layouts fall back to `git diff`.
- The layouts were not driven against a live multiplexer session: the resolver,
  the guard messages and the dispatch were exercised, the panes were not.
- `rsw` names `inotify-tools` as a missing package rather than haseen adding it:
  the watchers are its only user.

## Execution record

`share/haseen/default/shell/{aliases,functions,init}.sh`,
`share/haseen/seeds/60-shell.sh`, `share/haseen/lib/common.sh`
(`append_user_file`), `share/haseen/lib/catalog.sh` (the `mise_install_tools`
rc branch), `share/haseen/layers/base/packages.txt` (+3 after the owner's
2026-10-08 decision), `share/haseen/default/catalog.json` (+6 CLI entries),
`tests/test-shelltools.sh`, `tests/test-catalog.sh`.

Landing 2026-10-08: the two source reads of `catalog.sh` in
`tests/test-shelltools.sh` became a behavioural check (`haseen install dev
python --dry-run` with and without the include line).

Landing review 2026-10-08: interactive bash expands the user's aliases while
it parses a sourced file, so the fragment broke on a real rc. Omarchy's `alias
cd=zd` turned `HASEEN_SHELL_DIR` into zd's output, and an alias named like a
function (`decompress`, `ga`, `gd`, `ff`) made `ga() {` a syntax error that
left every later function undefined. The fix: `function name {` for every
definition, `builtin cd`/`builtin pwd` and a quoted `\.` in `init.sh`,
`builtin cd` inside the functions, and the zsh branch reads its own path with
`${(%):-%x}` instead of `$0`. `aliases.sh` keeps an alias the user's rc
already defines (the include is the last line, so haseen's used to replace
it). The seed matches an existing include by its `share/haseen/default/shell/init.sh`
suffix, so a second tree adds no second include, and it skips a dangling rc
link with a warning. `tests/test-shelltools.sh` sources the include under
`bash -i` with those aliases, a printing `cd` alias and a silent one.
