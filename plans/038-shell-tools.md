# Plan 038: Shell rc layer — tools, aliases, functions, `mise activate`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (one include line in the user's rc, added once; every tool behind `command -v`)
- **Depends on**: 001 017 023
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (items 21–23: `mise`, `gh`, omarchy shell-tools / shell-functions / TUIs)
- **State**: DONE 2026-10-05; rc include once, user names kept, layouts quoted 2026-10-13

## Problem

haseen had no shell rc layer. `grep -rn 'alias \|bashrc\|zshrc' share bin`
found one hit, `share/haseen/lib/catalog.sh:225-228`, which read `~/.bashrc`
for `mise activate` and printed advice. So every alias and all 21 functions
Omarchy documents were absent (`/tmp/haseen-research/OmarchyManual.md` §1–§2,
§7.1), and `haseen install <development entry>` installed a runtime through
mise and left it off `PATH`. Of the nine documented shell tools only `fzf`,
`ripgrep` and `fd` were installed.

## Decision

- **Three haseen-owned files** under `share/haseen/default/shell/`
  (`aliases.sh`, `functions.sh`, `init.sh`), pulled in by one include line
  that `share/haseen/seeds/60-shell.sh` appends to `~/.bashrc`, and to
  `~/.zshrc` only when that file exists. haseen's behaviour lives in
  `default/` and upgrades without touching the rc again.
- **Owner decision (owner, 2026-10-08; confirmed 2026-10-13): haseen may
  append that one include line to an existing `~/.bashrc`/`~/.zshrc`, once.**
  It is the one exception to "never edit a user file after seeding"
  (`AGENTS.md`, `docs/architecture.md` §3).
- **Once is recorded.** `install.sh` seeds on every run and migration
  `1791466288-seed-user.sh` seeds too, so the seed writes each rc it handled to
  `~/.local/state/haseen/rc-include` and skips an rc listed there
  (`60-shell.sh:32`, `:51`). A line the user deletes is never added back. A
  home seeded before the record existed counts its live include as the one
  line and is recorded without an append.
- **A live include is one whose path exists here.**
  `share/haseen/lib/shellrc.sh` reads every `…share/haseen/default/shell/init.sh`
  path in the rc (quoted or bare, `~`/`$HOME` expanded, commented-out lines
  included, since the user turned those off) and answers `live`, `dead` or
  `none`. A live include from any tree (the checkout, then `/usr/local`) is
  enough: a second would run `init.sh` twice. A dead one (an rc shared with a
  machine where haseen has another prefix) activates nothing, so an rc not yet
  recorded gets this tree's line under it (`60-shell.sh:44`); the old line
  stays. An rc already recorded whose include went dead (haseen moved) gets a
  warning with the line to use and no edit, because that would be a second
  append. `mise_install_tools` counts only a live include as mise activation
  (`catalog.sh:239`).
- **Every tool is guarded by `command -v`.** A login shell that errors on every
  prompt because `eza` is missing is worse than having no alias.
- **The user's names win.** `aliases.sh` keeps an alias the rc already defines
  (the include is the rc's last line). `functions.sh` defines each public
  function only while its name is not an alias, function, builtin or command
  (`_haseen_free`, `functions.sh:26`): a user's `gd` must never become haseen's
  worktree-and-branch-deleting `gd`, and ncompress's `compress` stays reachable.
- **Interactive bash expands aliases while it parses a sourced file**, so
  every function uses the `function name {` form (an alias `ga` makes `ga() {`
  a syntax error even when the definition is skipped), `init.sh` and the
  functions use `builtin cd`/`builtin pwd` and a quoted `\.`, and zsh reads the
  fragment's own path with `${(%):-%x}`.
- **`mise activate` is written, not advised.** `init.sh` runs it; `catalog.sh`
  only checks, and points at `haseen seed user` when no rc activates mise.
- **One multiplexer resolver** (`_haseen_mux`) behind all eight layout names
  (`tdl tds tdlm tsl` and `hdl hds hdlm hsl`), resolving `HERDR_PANE_ID` →
  `TMUX` → `~/.config/haseen/mux` → herdr installed → tmux installed. Both
  multiplexers ship, herdr first (plan 044). `tdlm`/`hdlm` type
  `cd <dir> && _haseen_layout dl <agent>` into each pane with every word quoted
  by `printf %q`: the pane's shell runs it, and a directory name is data.
- **`append_user_file`** joins `write_user_file` / `append_root_file` in
  `share/haseen/lib/common.sh:114`: the rc is the one user file haseen extends
  rather than creates, and the dry-run plan shows exactly the line that lands.
  Whether to append is the seed's decision, not the helper's.
- **Packages (owner, 2026-10-08; confirmed 2026-10-13): `zoxide`, `eza` and
  `bat` go into the base layer** (`share/haseen/layers/base/packages.txt:17-19`),
  because the fragment wires them into every shell. `github-cli`, `lazygit`,
  `dua-cli`, `yt-dlp`, `tealdeer` and `mise` are catalogue entries
  (`haseen install app gh|lazygit|dua|yt-dlp|tealdeer|mise`), guarded in the
  fragment by `command -v`; `mise_install_tools` still installs `mise` on first
  use. `tmux` (base) and `herdr` (desktop) are plan 044's, `yazi` plan 037's.
  All are in `extra` (`pacman -Si`: `zoxide 0.10.0-1`, `eza 0.23.5-2`,
  `bat 0.26.1-2`, `tealdeer 1.9.0-1`, `yt-dlp 2026.08.19-1`, `lazygit 0.65.0-1`,
  `dua-cli 2.44.0-1`, `github-cli 2.100.0-1`, `mise 2026.9.1-1`).

## Rejected

- **fastfetch, walker, elephant**: duplicates of `bin/haseen-about`
  (`share/haseen/default/menu.jsonc:42`) and `haseen.launcher` / `haseen.menu`
  (`/tmp/haseen-research/OmarchyManual.md` §6).
- **`tldr` (Python, `extra 3.4.4-1`)** in favour of `tealdeer` (Rust, same
  `tldr` binary): the owner asked for the Rust client.
- **Aliasing `cd` to zoxide**, as Omarchy does: landing somewhere else after a
  typo is a bad default in a shell that also runs scripts. `z` / `zi` exist.
- **`iso2sd` and `format-drive`**: privileged destructive commands against a
  whole disk. Every privileged mutation goes through `lib/common.sh` and takes
  `--dry-run`; an rc function can do neither, and `sudo` must not appear
  outside `common.sh` (`AGENTS.md`). `haseen drive select` / `haseen drive info`
  own the interactive part.
- **The `ssh` reconnect wrapper**: a retry loop around a core binary in every
  login shell, with no per-invocation opt-out.
- **Writing the mise line from `catalog.sh`**: a second editor of the user's rc.
- **`write_user_file` for the append**: it rewrites the rc wholesale and prints
  the whole file in every dry-run plan.
- **Re-adding a deleted include on every seed**: the approval is one line,
  once.
- **Matching an include by its path suffix alone**: an include of a path that
  does not exist here counted as wired, so neither the seed nor the mise check
  noticed that nothing was sourced.
- **Appending a second line when an include haseen added goes dead**: a
  second append, which the approval does not cover; the seed prints the line
  instead.
- **Defining the functions under the user's aliases** (reachable as `\ga`):
  that still replaced a user's function of the same name and hid programs on
  PATH.

## Verification

- `tests/test-shelltools.sh` (148 checks): the fragment parses and sources with
  no tools installed, prints nothing, and wires eza/bat/zoxide/mise when they
  exist; the resolver's order; the seed's dry-run plan, one append, the
  user's rc untouched above it, a zshrc only when present; the record (a
  deleted include stays deleted, also for a home seeded before the record);
  a dead include gets this tree's line once and keeps the user's, and a dead
  include haseen added gets a warning and no edit; `haseen install dev python
  --dry-run` advises seeding when the rc's include is dead; your `gd`
  function and a `compress` on PATH survive the include, and aliased names get
  no function; `bash -i` with Omarchy's aliases (`cd=zd` that prints, one that
  silently cds, `decompress`, `ga`, `gd`, `ff`) sources cleanly; compress →
  decompress round trip; `ga` then `gd` on a throwaway repository under
  `GIT_CEILING_DIRECTORIES`; `tdlm`/`hdlm` against recording fake tmux and
  herdr in a directory holding `a'; echo pwned >PWNED; '`: running what they
  typed creates no `PWNED` and lands in that directory (before the `%q` fix the
  file appeared).
- Live round trip (2026-10-05) in a scratch `HOME` through the seeded rc:
  `compress` → `decompress` recovered the file, `ga` created
  `project--feature` as a real worktree and `gd` removed it and its branch, and
  the trace showed `mise hook-env … --reason chpwd` firing.
- `tests/test-seeds.sh`: a live include from another tree on the machine gets
  no second include; a dangling rc link is skipped with a warning.
- `tests/test-catalog.sh`, `tests/test-migrate-defaults.sh` unchanged and green.

## Open

- **zsh is not installed on the reference machine**, so `zsh -n` and the
  zsh paths were not run. The test runs `zsh -n` once zsh exists.
- `hunk` (Omarchy's diff watcher) is not a haseen package, so `tds`/`hds` fall
  back to `git diff`.
- The layouts were not driven against a live multiplexer; the resolver, the
  dispatch and what they type were exercised against fakes.
- `rsw` names `inotify-tools` as a missing package rather than haseen adding
  it: the watchers are its only user.

## Execution record

`share/haseen/default/shell/{aliases,functions,init}.sh`,
`share/haseen/seeds/60-shell.sh`, `share/haseen/lib/shellrc.sh`,
`share/haseen/lib/common.sh` (`append_user_file`),
`share/haseen/lib/catalog.sh` (`mise_install_tools`),
`share/haseen/layers/base/packages.txt`, `share/haseen/default/catalog.json`
(six CLI entries), `docs/architecture.md` §2, §3,
`tests/test-shelltools.sh`, `tests/test-seeds.sh`, `tests/test-catalog.sh`.
