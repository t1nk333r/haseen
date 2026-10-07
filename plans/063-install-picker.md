# Plan 063: install picker that remembers the last choice

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (only interactive runs change; piped, `--yes` and `--layers` runs are as before)
- **Depends on**: 001 017 055 056
- **Category**: install
- **Planned at**: 2026-10-07, io round 9 (idea from aphotic-hypr's installer)
- **State**: DONE 2026-10-07 (gum driven in a scratch tmux; the owner's own terminal is an owner check)

## Problem and decision

`./install.sh` applied `base chaotic omarchy-repo desktop theme shell` unless
`--layers` said otherwise, and every optional piece (the secureboot, ai, dms,
gaming and flatpak layers; the keyd, fingerprint, geoclue and dotfiles setup
commands) had to be known and run by hand afterwards. Plan 056 noted that
haseen had no first-run list of optional steps.

aphotic-hypr's installer asks which pieces to install and remembers the
answer. That project is GPL, so only the idea is taken; the code is new.

- **When it asks.** At a terminal (stdin is a TTY) without `--layers`, `--yes`,
  `--tree-only` or `--uninstall-tree`; or anywhere with `--pick`, which is how
  scripted stdin drives it. `--pick` combined with any of those flags is an
  error. A piped run, a `--yes` run and a `--layers` run ask nothing and never
  read the saved choice: they behave exactly as before.
- **What it asks.** Two toggle lists: the layers (the six defaults ticked, the
  optional layers off) and the setup steps run after the layers
  (`haseen setup keyd on`, `haseen setup fingerprint`, `haseen setup geoclue
  on`, `haseen setup dotfiles <url>`; all off, owner rule). Ticking dotfiles
  asks for the repository URL; an empty or unquotable one drops the step.
  Each row shows the layer's `LAYER_SUMMARY` or the command's
  `haseen:summary`, so the list follows the tree. A layer's requirements are
  still added by `haseen layer apply` (unticking chaotic keeps it while
  desktop needs it). VAPT is not offered: plan 007 dropped it.
- **UI.** gum (`gum choose --no-limit`, `gum confirm`, `gum input`) when it is
  installed and stdin and stdout are a terminal; otherwise a bash `select`
  toggle list (type a number to toggle, the last number continues; end of
  input accepts what is ticked).
- **Memory.** After the install prompt is accepted the choice is written to
  `~/.config/haseen/install.toml` (`write_user_file`, so `--dry-run` prints it
  and writes nothing). The next interactive run shows it and asks "Reuse last
  choices?" (default yes); no opens the picker with that choice ticked. A
  reused choice is not rewritten. Unknown layers and steps in the file are
  dropped with a warning; a file without layers is not offered.
- **Why TOML, not JSON.** install.sh runs before the base layer installs jq.
  The file is three flat keys (`layers`, `setup`, `dotfiles_url`) that bash
  reads and writes with builtins, and a person can edit it like a theme's
  `colors.toml`. Nothing else reads it.
- **Failures.** A setup step that fails is reported with a warning and the
  remaining steps still run: the layers are already applied and every step
  can be re-run on its own.

Code: `share/haseen/lib/install-picker.sh` (sourced by `install.sh`).

## Verification

- `tests/run.sh tests/test-install-picker.sh` (60 checks, all `--dry-run`):
  a piped run without `--pick` applies the default layers, shows no picker,
  ignores a saved choice and runs no setup step; `--layers` still decides
  alone; `--pick` with `--layers`/`--yes` is refused; the picker's defaults
  (core on, optional off, `setup = []`); a scripted pick (drop omarchy-repo,
  add flatpak, tick keyd and geoclue) gives `apply order: base chaotic desktop
  theme shell flatpak`, saves that and runs the two steps after the layers;
  reuse (answer y, and end of input) applies the saved layers and step without
  rewriting the file; declining reopens the picker from the saved choice;
  unknown entries are dropped; the dotfiles URL is required, saved and passed,
  and its failure does not fail the install; dry-run writes no file.
- gum 2.0.0 driven by hand in a scratch tmux session (scratch `HOME`,
  fixture sysroot, `--dry-run`): defaults then Enter gives the six default
  layers and `setup = []`; ticking flatpak with `x` adds it to the apply order;
  ticking dotfiles asks for the URL with `gum input`, and an empty one skips
  it; with a saved choice, `gum confirm` Yes reuses it without rewriting the
  file, No reopens `gum choose` with it ticked. `gum choose --ordered` lists
  the options alphabetically, so it is not used; the list keeps the order of
  the printed summaries.

## Not done

- Not run on the owner's terminal emulator; `./install.sh --dry-run` there
  shows the picker without changing anything.
- No non-interactive flag for setup steps (`--setup`); the steps run from
  the picker or by hand.
