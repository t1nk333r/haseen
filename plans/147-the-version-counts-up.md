# Plan 147: the installed version counts up, and an update says which branch it follows

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. The installed tree's `VERSION` gains a suffix the version
  checks already ignore (they read the leading `x.y.z`); the checkout's file,
  the sidecar release named after it and every test that reads it are
  unchanged. The branch note is a warning on stderr and changes no behaviour.
- **Depends on**: 134 (`haseen update haseen` and the install stamp), 136 (the
  banner names the checkout)
- **Category**: install, ergonomics
- **Planned at**: 2026-10-31 (owner, after `haseen update haseen --tree-only`
  on luna printed `haseen 0.2.0-dev installed under /usr/local`: "its still
  not incrementing … this is what i ment")
- **State**: DONE 2026-10-31 (`tests/test-update-haseen.sh` 64/64,
  `tests/test-install-picker.sh` 93/93)

## Problem

1. **The version never moves between bumps.** `share/haseen/VERSION` is set
   by hand. Plan 134 last set it, to `0.2.0-dev` (578fdea, #84), and sixteen
   merges since then have all installed as `0.2.0-dev`: `install.sh` printed
   `cat "$REPO/share/haseen/VERSION"` and wrote it to the stamp, and
   `haseen --version` (`bin/haseen:74`) and `haseen about`
   (`bin/haseen-about:124`) read the same file.
2. **luna's checkout followed a branch that no longer moved.** Its source
   checkout was left on `compat/summon-answers`, tracking
   `origin/compat/summon-answers`. Pull request #99 was squash-merged into
   main as 8bdd84a, so that branch stayed at 5944f3e. Every update fetched and
   reported `the checkout is already at 5944f3e`, while `origin/main` was two
   commits further on (`git rev-list --count HEAD..origin/main` → 2).

## What changed

- **`share/haseen/lib/install-stamp.sh` `install_build_version REPO`** prints
  the file plus the commits since it last changed (`git log -1 --format=%H --
  share/haseen/VERSION`, then `rev-list --count <that>..HEAD`):
  - a pre-release takes the count as one more dot-separated identifier, so
    `0.2.0-dev` and 21 commits is `0.2.0-dev.21`, which semver orders above
    `.20`;
  - a release takes it as build metadata: `0.3.0` and 2 commits is `0.3.0+2`;
  - the file alone, with no suffix, when git cannot say: no git, a history
    that never set the file, an uncommitted edit to it, or no commits since.
  On 2026-10-31 it gives `0.2.0-dev.16` for main (ae4bc37) and `0.2.0-dev.18`
  for luna's topic branch, which carries plan 145's own commits where main has
  their squash.
- **`install.sh`** writes that version into the installed tree's
  `share/haseen/VERSION` (`install.sh:243`, through `write_root_file`, before
  the swap), records it in the stamp and names it in the closing line. Every
  reader of the installed file (`haseen --version`, `haseen about`, the
  ledger, the user-agent strings, plugin `requires.haseen`) now sees the
  build's number with no change of its own.
- **`bin/haseen-update-haseen`** prints the same version in `--check` and in
  its install and "already installed" lines (`:178`, `:202`), and warns when
  the checkout's upstream is not the remote's default branch
  (`refs/remotes/<remote>/HEAD`, `:167`), with how many commits there the
  checkout lacks and the `git switch` that follows it.

## Rejected options

- **Bumping `VERSION` in every pull request, by hand or by CI.** A machine
  without Go downloads the sidecar from the `sidecar-v<VERSION>` release
  (plan 127, `tools/build-sidecar.sh:34`), so every bump needs a release cut
  for it; and `main` takes no bot pushes (protected, admins included).
- **Counting every commit (`git rev-list --count HEAD`).** It grows, but says
  nothing about the release line, and a new `x.y.z-dev` would start in the
  thousands instead of at zero.
- **`--first-parent` counting.** A topic branch that merges main in would
  count fewer commits than main itself has. Neither count makes a topic
  branch's number comparable with main's. The number orders builds along one
  branch, which is what `haseen update` follows: it only fast-forwards.
- **Refusing to update from a non-default branch.** Installing a branch under
  test is legitimate (plan 136); the warning names the problem and the fix.
- **Switching luna's checkout to main.** That is the owner's checkout; the
  warning and the reply give the command.

## Tests

- `tests/test-update-haseen.sh`, against real repositories: a checkout at the
  commit that set `VERSION` reports the file; one commit on installs as
  `0.3.0-dev.1`; a release version takes `+2`; an uncommitted bump and a tree
  without git report the file as it is; a checkout on `origin/topic` warns
  with main's one extra commit and the `git switch main` to follow it, and one
  on main does not. 64/64.
- `tests/test-install-picker.sh`, with a stubbed git that reports 21 commits
  since the bump: the installed `VERSION`, the stamp and the closing line all
  carry `<VERSION>.21`, and the run stays dry; with no git the stamp keeps
  the file's version. 93/93. With `install.sh` reading the file again, the
  three new assertions fail (90/93).

## Owner steps

```sh
git -C ~/Projects/cachyos-quickshellarchy switch main
haseen update haseen --tree-only   # installs main as 0.2.0-dev.N
haseen --version
```
