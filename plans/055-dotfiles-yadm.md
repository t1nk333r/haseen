# Plan 055: Dotfiles with yadm (`haseen setup dotfiles`)

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MEDIUM (writes into `$HOME`; every replaced file is backed up first)
- **Depends on**: 001 048
- **Category**: tooling, setup
- **Planned at**: 2026-10-07, owner request: his yadm dotfiles become part of haseen
- **State**: DONE 2026-10-07 (66 tests; real yadm and a network remote are owner checks)

Plan 053 is taken by luna's uncommitted work.

## Problem

The owner keeps his dotfiles in a yadm repository and wants a haseen machine
to be set up from it. Plain `yadm clone` does two things a haseen machine cannot
accept:

- It leaves every file in `$HOME` that differs from the repo untouched and
  prints a note (yadm 3.5.0 `clone()`, upstream `yadm` lines 857-880: only
  `ls-files --deleted` is checked out). The repo does not win, and the
  documented way to make it win, `yadm checkout "$HOME"`, overwrites without a
  copy.
- An Omarchy-era repo carries Omarchy's `~/.config/hypr/hyprland.lua`. Placed
  over haseen's seed, it takes `default/hypr/init.lua` out of the session.

## Decision

`bin/haseen-setup-dotfiles <git-url> [--branch B] [--bootstrap] [--dry-run] [--yes]`
and `haseen setup dotfiles status`:

- **Plan from a throwaway bare clone.** The repo's tree is compared with
  `$HOME`. The comparison uses one `git hash-object --stdin-paths` call, the
  executable bit, and symlink targets. Each path is new, identical, replaced,
  kept or skipped. The plan prints before the confirmation, and it is all that
  `--dry-run` runs.
- **Back up, then the repo wins.** Replaced files are copied with
  `cp -a --parents` to `~/.local/state/haseen/dotfiles-backup/<timestamp>/`.
  Then `yadm clone --no-bootstrap [-b B]` runs, followed by `yadm checkout --`
  of exactly those files. yadm itself comes from `extra/yadm` (3.5.0-1,
  `pacman -Si yadm`) through `pkg_install`.
- **haseen's entry point stays.** If the repo's `hyprland.lua` lacks
  `default/hypr/init.lua`, the repo's whole `.config/hypr` is treated as
  Omarchy's. This is the same test the desktop layer uses
  (`share/haseen/layers/desktop/layer.sh:208`).
  - Files already there are kept.
  - Files yadm placed there are taken back out; they stay in the repo.
  - The seed is restored when missing (`seed_user_file`).
  - The repo's copy is checked out to `~/.local/state/haseen/dotfiles-omarchy/<timestamp>/`
    and passed to the import as `--hypr`.
  - The run reports all of this.
- **Plugin sources stay read-only** (AGENTS.md). Existing files under
  `~/.config/omarchy/plugins` and `~/.config/DankMaterialShell/plugins` are
  never replaced. New files there are added, which is what `yadm clone` does
  anyway.
- **Import.** If the repo carries `~/.config/omarchy`, the command runs
  `haseen import omarchy --merge`. The import is skipped when the repo also
  tracks `~/.config/haseen/shell.json`: such a repo is already set up for haseen,
  and a merge would rewrite the shell.json the repo just placed. That case was
  raised while the waydots `haseen` branch was being built.
- **Bootstrap** runs only with `--bootstrap`, because a bootstrap script can
  install anything.
- **Refusal.** The command refuses when a yadm repo already exists with a
  different remote. With the same remote (ignoring a trailing `/` or `.git`), it
  prints the status and does nothing.
- **Local paths.** A local repository path is made absolute before cloning:
  `yadm clone` runs `git clone` from a temporary directory (upstream lines 832-834).
- **Menu.** Setup › Dotfiles has Status and Clone Repository. Clone asks for
  the URL in a floating terminal, the same way Setup › Local AI › Pull Model
  asks for a model.

Rejected:

- **`yadm checkout "$HOME"` after the clone.** It overwrites without a backup
  and would rewrite plugin sources.
- **A git stash as the backup.** The copy would sit inside the repo it guards,
  where a user cannot see or `cp` it back.
- **Keeping only `hyprland.lua` and letting the repo's Omarchy `bindings.lua`
  land.**
  - haseen's seed includes `bindings.lua`. An `o.bind` file fails there and
    raises an error notification at every start (`include_optional`,
    `share/haseen/default/hypr/init.lua:65-83`).
  - The import refuses haseen's own `~/.config/hypr` as its source
    (`bin/haseen-import-omarchy:421-422`).
- **A first-run step.** haseen has no first-run or optional-steps flow:
  `install.sh` only applies layers, hardware quirks and migrations. The command
  stays an explicit menu or CLI action, never automatic.

## Verification

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-dotfiles.sh` → `66/66 passed`.
  - The stubs are pacman (installs yadm by marker) and yadm (a re-enactment of
    yadm 3.5.0's clone: bare clone, `reset`, check out only deleted paths;
    other commands pass through to git).
  - The repo is a local bare git repository built by the test. Its `main` branch
    is Omarchy-era, using files from `tests/fixtures/omarchy-import/`. Its
    `haseen` branch loads haseen.
  - Covered:
    - the dry-run plan, with home checksum unchanged and no clone;
    - the conflict backed up and then replaced, with identical files not backed
      up;
    - haseen's seed and `monitors.lua` kept, and Omarchy's `bindings.lua` not
      placed;
    - the plugin source unchanged and the new plugin file added;
    - a directory in the way left alone;
    - the import triggered with the repo's hypr copy, writing `shell.json`;
    - same-remote no-op and different-remote refusal, also under `--dry-run`;
    - `--branch` and `--bootstrap`, with the import skipped for a haseen repo;
    - `status` showing remote, branch and changed count;
    - a relative path cloned by its absolute path.
- `tests/run.sh tests/test-dotfiles.sh tests/test-menu.sh tests/test-core.sh` →
  all passed. test-menu now also requires `setup.dotfiles.clone`, and its "every
  `haseen …` command exists" check resolves the new actions. test-core's
  plugin-directory grep finds no destructive operation.
- `tools/lint.sh` (shellcheck 0.11.0 static binary, `--severity=warning`) clean,
  and `tools/check-docs.sh` OK.
- A dry run against the fixture from a plain home lists:
  - 6 new files by directory;
  - `.bashrc` to back up;
  - haseen's `hyprland.lua` kept;
  - `bindings.lua`/`monitors.lua` not placed;
  - the import with `--hypr`;
  - `DRYRUN: sudo pacman -S --needed yadm`, `yadm clone --no-bootstrap`,
    `yadm checkout -- .bashrc`.
- yadm behaviour was read from upstream yadm 3.5.0:
  - `--no-bootstrap`: line 784;
  - clone with `-b` passed through to `git clone`: lines 832-834;
  - only deleted paths checked out, differing files left: lines 862-880;
  - `introspect repo`: line 1305;
  - git commands pass through without a `cd`: lines 1144-1170.

## Not done

- **Real yadm and a real remote were not exercised.** This laptop has no yadm
  installed and no access to the owner's GitLab remote. The integrator runs the
  first real clone.
- **The menu entries were not clicked in a live session.**
