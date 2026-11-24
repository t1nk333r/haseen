# Plan 191: seeds and dotfiles keep what the user set

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. `haseen seed system` writes `/etc/conf.d/snapper` less often
  and leaves the timeline timer alone when another config exists; the shell
  fragment binds Ctrl-R and sets `MANPAGER` less often; `haseen setup
  dotfiles` runs its two yadm calls with a scratch yadm directory only when
  the repo carries hooks.
- **Depends on**: 033 (the snapper policy), 038 (the shell include, once),
  063 (the install picker's dotfiles step)
- **Category**: seeds
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2026-11-24, group g07-seeds)
- **State**: DONE 2026-11-24 (`tests/test-seeds.sh` 109/109,
  `tests/test-dotfiles.sh` 91/91, `tests/test-shelltools.sh` 170/170,
  `tests/test-install-picker.sh` 97/97; the new checks fail on the code
  before this plan: 7, 11 and 7 failures, and the review round's 6)

## Problem

The audit ran before plans 182-184 merged; every finding below was re-checked on
`9a9e82ab`, where none had changed.

### 1. `haseen seed system` drops every snapper config but root

`bin/haseen-seed-system:101` (before this plan) piped
`SNAPPER_CONFIGS="root"` into `write_root_file` on every run, without
reading the file, and `:103` ran `systemctl disable --now
snapper-timeline.timer` on every run. After `snapper -c home create-config
/home` the file reads `SNAPPER_CONFIGS="root home"`; the seed cut it back to
`root`, so snapper's cleanup and `omarchy-snapshot`
(`share/haseen/omarchy/bin/omarchy-snapshot:43-60`, which reads the list)
stopped seeing `home`. The timer is global, and root's policy
(`share/haseen/default/snapper/root`) already sets `TIMELINE_CREATE="no"`,
so turning the timer off only stopped the other configs' timelines. The
usage text (`:34-35`) said "each step is skipped when it is already in
place". The overwrite of `configs/root` (`:92-99`) is deliberate (plan 033)
and is not part of the defect.

### 2. The dotfiles step removes the include for good

`install.sh:383` runs `seed user`, which appends the include to `~/.bashrc`
and records the rc in `rc-include`; `install.sh:391` then runs the picker's
`haseen setup dotfiles URL`. A repo `.bashrc` without the include differs,
lands in CONFLICT and is checked out over the seeded one
(`bin/haseen-setup-dotfiles:308` before this plan). Every later seed finds
the rc in the record and skips it silently
(`share/haseen/seeds/60-shell.sh:32-38` before this plan; only a `dead`
include warns), and `share/haseen/lib/catalog.sh:241` still sent the user to
`haseen seed user`, which then added nothing. `docs/architecture.md:98`
justifies the record only for "a line the user deletes"; here haseen's own
step removed it.

### 3. The fragment replaces the rc's `MANPAGER` and Ctrl-R

The include is the rc's last line. `share/haseen/default/shell/init.sh:111`
exported `MANPAGER` whenever bat exists and `:94-96` sourced fzf's key
bindings in every interactive shell, so an rc's `export MANPAGER='nvim
+Man!'` and atuin's Ctrl-R were replaced; bat and fzf are base packages
(`share/haseen/layers/base/packages.txt`). `aliases.sh` already keeps an
alias the rc defined, for this reason.

### 4. `haseen setup dotfiles` runs the repo's yadm hooks

yadm 3.5.0 checks out every file missing from `$HOME` during `clone`
(`/usr/bin/yadm:862-864`), including `.config/yadm/hooks/post_clone` with
its exec bit, then `exit_with_hook` runs `$YADM_DIR/hooks/post_clone` when it
is executable (`:1869-1882`); the passthrough `checkout` runs
`post_checkout` the same way. The plan printed "yadm bootstrap: not run"
(`bin/haseen-setup-dotfiles:288` before this plan), and the installer runs
the step under `--yes`. Reproduced with the real yadm in a scratch `$HOME`:
a plain `yadm clone` plus `yadm checkout -- .bashrc` left both
`RAN-post_clone` and `RAN-post_checkout` marker files; the same two calls
with `-Y <dir with an empty hooks/>` left neither, and the hooks were still
placed in `~/.config/yadm/hooks/`.

## Fix

1. `seed_snapper` reads `SNAPPER_CONFIGS` the way `omarchy-snapshot` does
   (last assignment, quotes optional). A list that has `root` is left alone
   ("already lists root"); otherwise `root` is put first and the file is
   rewritten with every other line kept. The timeline timer is turned off
   only when root is the only config; otherwise the plan says it is left
   for the others. The usage text says what is skipped and what is kept.
2. `haseen setup dotfiles` checks each repo `.bashrc`/`.zshrc` that replaces
   (or newly fills) an rc listed in `rc-include`: when the repo's copy has
   no live include (`shellrc_include`), the plan lists it under "Without
   haseen's shell include", the record line is dropped after the checkout
   (`write_user_file`, so `--dry-run` shows it), and the summary says
   `haseen seed user` adds the one line. The next seed (every install and
   update runs one) adds it. A repo rc that is a link (mode 120000, whose
   blob is the link's target) is judged by the tracked file it names inside
   the repo; a link that leaves the repo, climbs out with `..` or names an
   untracked path keeps its record, so the seed never appends through it.
   The installer seeds before its setup steps, so `picker_run_setup` runs
   `haseen seed user` once more after a dotfiles step that worked: a fresh
   install has the include back before the first login. `catalog.sh` prints the include line itself
   when `~/.bashrc` is already recorded, since the seed would add nothing
   there; otherwise it still advises the seed. `60-shell.sh`'s comment
   names the new case.
3. `MANPAGER`/`MANROFFOPT` are exported only when `MANPAGER` is empty.
   Before sourcing fzf's bindings, init.sh looks at Ctrl-R: in bash, free
   means readline's `reverse-search-history` or fzf's own
   `__fzf_history__`; in zsh, `history-incremental-search-backward`,
   `redisplay`, `undefined-key`, `fzf-history-widget` or unbound. Anything
   else is the rc's choice, so `FZF_CTRL_R_COMMAND` is set empty for the
   source (fzf 0.74's own switch, `/usr/share/fzf/key-bindings.bash:160`,
   `.zsh:189`) and unset after; Ctrl-T and Alt-C still come. A
   `FZF_CTRL_R_COMMAND` the user set is left to fzf.
4. When the repo tracks files under `$YADM_DIR/hooks/`, the clone and the
   checkout run as `yadm -Y <scratch>` whose `hooks/` is empty and whose
   `encrypt` and `config` link to the real ones. When the repo also keeps
   `$YADM_DIR/alt/` files, the scratch config is a copy of the real one plus
   `yadm.auto-alt = false` (yadm reads it with `git config --file`, which
   ignores includes, and yadm finds the alt directory by path, so linking
   now would misplace the links); the summary names `yadm alt`. The plan
   lists the hooks, the usage text and `docs/architecture.md` §10 say they
   are placed, not run, and that the user's later yadm commands run them.

## Tests

- `tests/test-seeds.sh` "other snapper configs stay": `root home` is left
  alone and the timer stays on; `home` becomes `root home` with the comment
  kept; an empty list gets `root` and the timer is turned off.
- `tests/test-dotfiles.sh` "the repo's yadm hooks do not run": the fixture
  repo tracks executable `post_clone`/`post_checkout` and a `.bashrc`
  without the include; the stub yadm runs `$YADM_DIR/hooks/post_<cmd>` like
  yadm does. The dry run lists the hooks, the `-Y` calls and the record
  rewrite; the real run places the hooks without running them, drops only
  `~/.bashrc` from the record, and `haseen seed user` then adds the line.
- `tests/test-dotfiles.sh` "links: …": a `.zshrc` linked to
  a tracked file without the include loses its record, a `.bashrc` linked to
  one with it keeps it, and a `.bashrc` linked out of the repo keeps its
  record and the record is not rewritten.
- `tests/test-install-picker.sh`: a dotfiles step that worked is followed by
  one `haseen seed user`, and a failed one by none.
- `tests/test-shelltools.sh` "the rc's own choices stay": a preset
  `MANPAGER` survives; in an interactive bash an rc's `bind -x` Ctrl-R
  survives while Ctrl-T is fzf's and the switch is unset after; a default
  Ctrl-R is fzf's; the same in zsh when zsh is installed. The mise advice
  is the line once `~/.bashrc` is recorded, and the seed when it is not.

## Rejected

- **Warning from `60-shell.sh` on every seed when a recorded rc has no
  include.** A line the user deleted would warn on every install and update;
  plan 038 makes that deletion final.
- **Running `haseen seed user` from `haseen setup dotfiles`.** A second
  path that edits the user's rc; the next seed (every install and update)
  adds it, and the summary names the command.
  The installer's picker runs the seed itself after the step instead: it is
  the same seed the installer runs on every install.
- **Skipping the check for a linked repo rc.** Its record would stay, and an
  rc linked to a file without the include would lose it for good, the defect
  this plan fixes; reading the tracked target costs one `git ls-tree`.
- **Disabling the timer when root is listed, whatever else is.** It is the
  defect: root never uses the timeline.
- **Writing `TIMELINE_CREATE=no` into the other configs.** Their timelines
  are the user's.
- **Asking before the clone when hooks exist.** `--yes` (the installer)
  would still need a safe default, and with the scratch directory nothing
  of the repo's runs, so there is nothing to ask.
- **An `[include]` of the real yadm config in the scratch one.** yadm reads
  it with `git config --file`, which skips includes by default.
- **Detecting Ctrl-R with `bind -p` alone.** `bind -x` bindings (atuin's)
  do not appear in it.

## Review

The independent Sonnet review of the first head approved it with two nits,
both taken. First, the installer runs `haseen seed user` before the picker's
setup steps, so on a fresh install whose dotfiles repo replaced `~/.bashrc`
the include only came back at the next seed: `picker_run_setup` now seeds
again after a dotfiles step that worked (`share/haseen/lib/install-picker.sh`,
tested in `tests/test-install-picker.sh`). Second, for a repo rc that is a
symlink `git cat-file` printed the link's target rather than the rc, so the
record was dropped whatever the target held, and the next seed could append
through the link; the check now reads the tracked file the link names and
keeps the record for a link it cannot resolve inside the repo
(`rc_object` in `bin/haseen-setup-dotfiles`, tested in
`tests/test-dotfiles.sh`). The new checks fail on the code before the round
(6 failures across the two files: the four "links: …" checks and two of the
picker's, run against the first reviewed head's `bin/haseen-setup-dotfiles` and
`install-picker.sh`). A second pass over the answer found that a link whose
target ends in `/` made `git ls-tree` list a directory's children, so the
first child's blob could stand in for the rc; `rc_object` now accepts only a
single entry for exactly the named path, and keeps the record otherwise.
