# Plan 100: Run only the affected tests on pull requests, the full suite on main

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (tests, CI and docs only; no shipped file changes. A coverage declaration that misses a dependency skips that test on a pull request; the full suite on `main` still runs it after the merge)
- **Depends on**: 094
- **Category**: tests, CI
- **Planned at**: 2026-10-21, owner (below)
- **State**: DONE 2026-10-21 (selection and check verified locally; CI's first affected run is this plan's own pull request)

## Owner decision (2026-10-21, verbatim)

- The owner asked: "make the test runs just for the affected code not the
  whole code base".
- The owner added: "make the test runs just for the affected code not the
  whole code base. update everything that has relavenc to test".
- Asked where the whole suite should still run as a safety net, the owner chose
  **"After each merge to main"**: PRs run only the tests for the files they
  change; a push to main runs the full suite, so anything the mapping missed
  shows up red on main and gets fixed; merges are never blocked by it.
- Rejected: "Nightly on main" (a miss can sit on main for up to a day) and
  "Never" (a test the mapping does not link to a change never runs until its
  own files change).

## Problem

CI's `test` job runs the whole suite on every pull request and every push to
`main`. On PR #53's last run (run 39596107714, job `test` 12:01:05-13:29:23
UTC) that took 88 minutes; the suite itself, from the job log's timestamps,
87.6 minutes over 153 files. PR #55 (`3d1e6a0`) raised the job's limit
from 90 to 150 minutes because `main`'s run for `ed84608` hit 90 (run
39613979814).

The time is concentrated: the 33 `test-vapt-*.sh` files take 68.8 of the 87.6
minutes (the ten slowest are all VAPT suites, 595 s to 129 s each); the other
120 files take 18.7. Most pull requests change no VAPT file, yet every one
waits for them.

## Design

### Coverage declarations

Every `tests/test-*.sh` names the repository paths it exercises in its leading
comment block (the lines before its first command), right after
`# shellcheck shell=bash`:

```sh
# shellcheck shell=bash
# haseen:covers bin/haseen-battery-limit bin/haseen-setup-battery-limit
# haseen:covers share/haseen/systemd/system/haseen-charge-limit.service
```

A line holds one or more globs separated by spaces; a file may have several
lines. Lines after the first command are not declarations, so a heredoc that
happens to contain the marker cannot declare anything
(`tools/affected-tests.sh` `covers()`; `tests/test-affected.sh` checks it with
a `# haseen:covers not/declared/**` line after a command).

Glob syntax (`tools/affected-tests.sh`, header and `glob_regex()`), matched
against the whole repository-relative path of a file:

| Glob | Matches |
|---|---|
| `*` | any characters except `/` |
| `?` | one character except `/` |
| `[abc]`, `[!a]` | one of the characters; `!` negates |
| `**` | a whole path segment only: zero or more directories in `a/**/b` and `**/b`; trailing (`a/**`), everything below `a` |
| `{a,b}` | either alternative; not nested; may contain `/` but not `**` |

Nothing else is special, and a glob cannot contain a space, `^` or `\` (`?`
stands in for them). Each glob becomes an anchored POSIX ERE (`*` to `[^/]*`,
`**/` to `([^/]+/)*`, trailing `**` to `.+`, other ERE characters bracketed),
matched by awk. A `**` that is not a whole segment (`src/a**`) is a syntax
error, not a guess.

What a test declares: the commands it runs (`haseen a b` runs the longest
existing `bin/haseen-a-b…`) and the commands those run, the libraries any of
them source, the data they read (`share/haseen/default/`, themes, templates,
units, migrations, fixtures), the QML it loads (the `Haseen` module, the
compat modules and link files, top-level shell files, each plugin directory
and the plugins it imports), the `tools/` helpers and `core/` sources it runs
or builds, and the documents it asserts on (`NOTICE.md`, `AGENTS.md` and
`CLAUDE.md`, `docs/vapt.md`, `plans/093-adopt-omarchy-commands.md`). A test
does not list itself or the global set.

### The selector

`tools/affected-tests.sh [--committed] [--quiet] [BASE]` (default BASE
`origin/main`):

- Changed paths: `git diff --name-only --no-renames $(git merge-base BASE HEAD) HEAD`;
  `--no-renames` reports a rename as a deletion and an addition, so both the
  old and the new path count. Without `--committed` it adds
  `git diff --name-only --no-renames HEAD` (staged and unstaged) and
  `git ls-files --others --exclude-standard` (untracked, not ignored): the
  local mode for a pre-commit run. CI passes `--committed`.
- Paths are read NUL-separated (`-z`). A name with a control character (a
  tab, a newline) cannot travel in the selector's own line and tab formats,
  so it selects every test and is never matched against a glob (review round
  1 below).
- Each changed path, in order:
  1. matches GLOBAL: every test (`all`);
  2. is a `tests/test-*.sh` that exists: that test;
  3. matches covers: every test declaring a matching glob;
  4. matches EXEMPT: nothing;
  5. anything else: every test, so a file no test claims is never skipped.
- Output: the selected files, one per line, sorted, or the word `all`, on
  stdout; on stderr the merge base and one line per path saying why, for
  example `src/gamma/sub/g.c: no test covers it and it is neither global nor
  exempt, every test`.

GLOBAL and EXEMPT are two arrays at the top of the script, each entry with its
reason:

| GLOBAL | Why a change runs every test |
|---|---|
| `tests/lib.sh` | sourced into every test file's subshell (`tests/run.sh`) |
| `tests/run.sh` | the runner |
| `tools/affected-tests.sh` | the selector: a fault in it can skip any test |
| `.github/workflows/**` | CI: what runs, in which container, as which user |
| `share/haseen/lib/common.sh` | the dry-run helpers; the static draft reached it from 140 of 153 test files |
| `bin/haseen` | the router behind every `haseen <group> <verb>`; 115 of 153 test files call it by that form |

| EXEMPT | Why a change alone runs no test |
|---|---|
| `plans/**` | the engineering record; `tools/check-docs.sh` (CI `docs`) checks it |
| `docs/**` | architecture, decisions, guides |
| `*.md` | top-level docs: `README.md`, `AGENTS.md` (and its link `CLAUDE.md`), `handoff.md`, `NOTICE.md` |
| `LICENSE` | the licence text |
| `.editorconfig`, `.gitignore` | editor and git settings |
| `.gitleaksignore` | read only by `tools/secrets.sh` (CI `secrets`) |
| `.shellcheckrc` | read only by shellcheck in `tools/lint.sh` (CI `lint`) |
| `tools/lint.sh`, `tools/check-docs.sh` | the lint and docs gates, run by their own CI jobs |
| `tools/nest-launch.sh`, `tools/sync-apply.sh`, `tools/plymouth-mock.sh`, `tools/smoke-greeter.sh`, `tools/vptr/**` | developer tools no test and nothing shipped runs; lint still checks them |

Covers come before EXEMPT, so a document a test asserts on still selects it:
`NOTICE.md` selects the nine tests that read it; `AGENTS.md` selects
`test-logo-helium.sh`, `test-adopted-tools.sh` and `test-wooting.sh` (the last
two read it as `CLAUDE.md`, its link); `docs/vapt.md` selects
`test-vapt-inventory.sh` and `plans/093-adopt-omarchy-commands.md`
`test-omarchy-commands.sh`. `README.md` or `plans/README.md` alone selects
nothing.

### The completeness check

`tools/affected-tests.sh --check` fails, listing them, on:

- a file (tracked, or new and not ignored) that is neither GLOBAL, EXEMPT,
  covered by a test, nor a test file itself;
- a covers glob, or a GLOBAL or EXEMPT entry, that matches no file (a stale
  declaration);
- a malformed glob;
- a test file with no covers line;
- a file name with a control character.

Both modes first make sure git reads this checkout as its own repository:
when git refuses it (a checkout another user owns, without `safe.directory`)
or resolves a parent repository, or when it lists no file at all, the
selector stops with status 2 and says so. It never answers with an empty,
passing result (review round 1 below).

It runs in `tools/lint.sh`, not `tools/check-docs.sh`: it checks the tests'
own metadata against the tree, which is static code checking, and lint already
runs on every PR and before every commit; check-docs is about the written
record (plans, commits cited, paths in the agent docs). It needs no history,
so lint's shallow checkout suffices. It takes well under a second.

### The runner

`tests/run.sh --affected [--committed] [BASE]` runs the selector: `all` runs
every file, an empty selection prints `no test is affected by this change;
nothing to run` and exits 0, otherwise it prints `affected: N of M test
files` and runs those. A selector failure (unknown base, malformed glob)
fails the run with the selector's status. `tests/run.sh` and
`tests/run.sh FILE...` are unchanged (`tests/run.sh:24-40`).

### CI

`.github/workflows/ci.yml`, job `test` (its name is unchanged: branch
protection requires `lint`, `test`, `docs` and `secrets`):

- the checkout fetches full history (`fetch-depth: 0`) so the merge base is
  present;
- on `pull_request` it runs
  `tests/run.sh --affected --committed "$BASE_SHA"` with
  `BASE_SHA=${{ github.event.pull_request.base.sha }}`. The checked-out head
  is GitHub's test merge of the PR into its base, so the diff from their merge
  base is exactly what the merge would bring in;
- on `push` (to `main`) and `workflow_dispatch` it runs `tests/run.sh`, the
  full suite, as before;
- `HASEEN_REQUIRE_ENGINE=1`, the unprivileged `ci` user, the container and
  the packages are unchanged. The tests and their git run as `ci`, who owns
  the checkout after the job's `chown`, so this job needs no
  `safe.directory`.

Two more workflow changes came from review round 1:

- the `lint` job trusts its checkout
  (`git config --global --add safe.directory "$GITHUB_WORKSPACE"` right
  after `actions/checkout`): its steps run as root in the container on a
  checkout another uid owns, and `--check` is the first git command lint
  runs;
- `concurrency` cancels an in-progress run only for pull requests
  (`cancel-in-progress: ${{ github.event_name == 'pull_request' }}`). A
  running suite on `main` always finishes. GitHub keeps one pending run per
  concurrency group and cancels an older pending one when a newer run
  arrives, so of several merges queued behind a running suite only the newest
  waits, and it runs the full suite on a tree that contains every earlier
  merge: the latest `main` always gets a full run.

The workflow triggers on every `pull_request` without path filters, so the
job always runs and always reports; a docs-only PR selects nothing, and the
job passes after the container setup. The selection and its reasons are in
the step's log (the selector's stderr report, then `affected: N of M`).

### Where running the tests is described

The owner's second request covers every place that tells a person or an agent
how to run the tests. Each now says: pull requests and pre-commit runs use
`tests/run.sh --affected [BASE]`, `main` runs the full suite after each merge,
and `tests/run.sh` with no arguments still runs everything.

- `AGENTS.md` (`CLAUDE.md` links to it), "Gates": `tests/run.sh --affected` in
  the block, lint's new coverage check named, and a paragraph on the
  selection, the full run on `main` and the covers lines; the rest unchanged.
- `README.md`, "Docs": the gates line.
- `handoff.md`: a map row for this plan beside the Tests row; the gates block
  runs `--affected`, followed by when the full suite runs (on demand, and on
  `main` in CI); "run only through `tests/run.sh`" names both forms.
- `.github/workflows/ci.yml`: the header's `test` line and the step's comment.
- `tests/run.sh` (header), `tools/lint.sh` (header: run with
  `tests/run.sh --affected`; the check itself).
- `tools/lab.sh`: the VM lab keeps the full suite in the guest on purpose; its
  header, usage text and the guest command's comment now say so.
- Unchanged: `share/haseen/lib/common.sh:10` says `tests/run.sh` enforces
  "no state change under --dry-run" with PATH stubs, which stays true of any
  selection; `docs/architecture.md` names test files as evidence but gives no
  instructions for running them; plan files are history.

## How the declarations were made

1. **A static draft** (a scratch scanner, not committed): path literals with
   simple variable substitution, `haseen …` and `haseen-…` command words,
   plugin ids, fixture and library names, then each command's sourced
   libraries. It is the rejected "automatic inference" below, used once as a
   starting point.
2. **Review, test by test.** Eight readers each took a batch (VAPT ×2, Omarchy
   and core, shell and compat, plugins ×2, CLI ×2), read every test file in
   full with the fixture libraries it sources and the commands it runs, and
   corrected the draft: added what it reached through variables, loops and
   QML imports, dropped paths it took from help text and comments.
3. **Traced runs.** 130 of the 154 test files (every file except 23 of the
   33 VAPT suites and `test-affected.sh`) ran with their declarations in
   place, one at a time, through `tests/run.sh` in a private copy of the
   checkout under a recursive `inotifywait -e open` watch; every repository
   file a run opened was compared with that file's covers and GLOBAL. All 130
   passed (the ten slowest VAPT suites: stock-security 555/555, env 248/248,
   landed 782/782, oniomarchy-trust-adversarial 278/278, oniomarchy-trust
   265/265, vapt 357/357, trust 227/227, oniomarchy 306/306, commit 112/112,
   oniomarchy-admission-adversarial 169/169).

   The traces found 986 undeclared opens (pairs of a test file and a
   repository file it opened) in 41 test files, all now declared:
   - 881 plugin manifests: the `Haseen` module's plugin registry reads every
     `share/haseen/shell/plugins/*/manifest.json` when a harness starts, which
     27 files' readers had not seen;
   - 44 libraries in `test-keybinds.sh` and `test-migrate.sh`, which copy
     `share/haseen/lib` and run their commands from the copy;
   - 12 top-level shell files `test-compat.sh`'s colour probe links;
   - 49 single commands, libraries and data files: the menu model runs the
     `checked` probes of `menu.jsonc` rows (`haseen context status` and six
     more) in `test-launcher-providers.sh` and `test-menu-radius.sh`;
     `haseen vapt install`'s libraries in `test-vapt-trust.sh`, reached
     through `vapt_plan`; the layer scripts `install.sh` plans in
     `test-vapt.sh`; `AGENTS.md`, opened through its link `CLAUDE.md`.

   What still opens undeclared files are copies, by design (see
   Limitations): `test-themes2.sh` (1,182 files), `test-omarchy-commands.sh`
   (910), `test-secureboot.sh` (319 fixture files it checksums),
   `test-vapt-oniomarchy.sh` and `-admission-adversarial.sh` (67 each).
4. **The 23 untraced VAPT suites** keep their reviewed declarations: all of
   `share/haseen/layers/vapt/**`, `share/haseen/default/vapt/**`, their
   fixture trees and libraries, and the `bin/haseen-vapt-*` commands they run.
   A grep of every `vapt_cli`, `vapt_plan`, `haseen vapt …` and
   `haseen-vapt-…` in all 33 VAPT files against their covers found two
   undeclared commands, both in traced files and both fixed
   (`test-vapt-env.sh`, `test-vapt-trust.sh`).

## Evidence

- `tests/test-affected.sh` (75 checks), against a scratch repository it builds
  with copies of `tests/run.sh`, `tests/lib.sh` and the selector and the
  fixture `tests/fixtures/affected/`: `**` at depth and zero depth, `*` within
  a directory, `{a,b}`, several covers lines in one file, a rename (both
  tests), a deletion, the global set (`tests/lib.sh`, `common.sh`, the
  workflow), exempt docs, a covered document beating the exempt `*.md`, a
  changed and a deleted test, staged, unstaged and untracked changes with and
  without `--committed`, the merge base when the base moves on, an unknown
  base, `--check` on an uncovered file, a stale glob, a missing header and a
  malformed glob, a marker after the first command, and `tests/run.sh
  --affected` with an empty selection, one file, `all` and a failing
  selector, with `tests/run.sh` and `tests/run.sh FILE` unchanged; since
  review round 1 also tab and newline names and a git that cannot read the
  checkout (below). Three mutations of the selector each failed its first 57
  checks: `**/` matching exactly one directory (53/57), covers read past the
  first command (`--check` then fails on the scratch tree and every later
  check with it), and git's rename detection in place of `--no-renames`
  (56/57, the rename case).
- `tools/affected-tests.sh --check` on this tree: `affected-tests: 2472 files,
  154 tests, 1777 covers globs: every file is covered, global or exempt`.
- What a change to one path selects now (the selector on that path alone):

  | Path | Test files |
  |---|---|
  | `README.md`, `plans/README.md` | 0 |
  | `docs/vapt.md` | 1 |
  | `share/haseen/shell/plugins/haseen.clock/Widget.qml` | 7 |
  | `NOTICE.md` | 9 |
  | `share/haseen/layers/vapt/layer.sh` | 31 |
  | `share/haseen/shell/Haseen/Theme.qml` | 45 |
  | `share/haseen/lib/packages.sh` | 60 |

- The last ten merges to `main` (`git log --oneline -10 origin/main` at
  `3d1e6a0`), each commit's paths against its parent, selected with the
  declarations of this plan. Minutes are the selected files' times in run
  39596107714's log (87.6 minutes for 153 files), without the job's few
  minutes of container setup:

  | Commit | PR | Paths changed | Test files run | Minutes of tests | Why |
  |---|---|---|---|---|---|
  | `3d1e6a0` | #55 | 3 | 154 of 154 | 87 of 87 | `.github/workflows/ci.yml` is global |
  | `ed84608` | #53 | 42 | 154 of 154 | 87 of 87 | `.github/workflows/ci.yml` is global |
  | `a6d72e3` | #54 | 3 | 26 of 154 | 8 of 87 | the changed paths' covers |
  | `0fe087d` | #52 | 4 | 4 of 154 | 1 of 87 | the changed paths' covers |
  | `0f6c4d5` | #51 | 7 | 4 of 154 | 1 of 87 | the changed paths' covers |
  | `912a682` | #50 | 501 | 154 of 154 | 87 of 87 | `share/haseen/lib/common.sh` is global; `tests/lib.sh` is global |
  | `e0d8c18` | #48 | 42 | 63 of 154 | 11 of 87 | the changed paths' covers |
  | `274cf8b` | #47 | 67 | 72 of 154 | 16 of 87 | the changed paths' covers |
  | `f9d6959` | #49 | 88 | 62 of 154 | 10 of 87 | the changed paths' covers |
  | `c67dbbd` | #46 | 8 | 154 of 154 | 87 of 87 | `tests/run.sh` is global |

  Together: 847 test-file runs instead of 1,540, about 395 minutes of tests
  instead of 870. The four that still run everything changed the workflow,
  `tests/run.sh`, `tests/lib.sh` or `common.sh`.
- Gates: `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: `lint OK` (797 shell, 33
  Lua, 198 JSON, 334 QML, 41 Go files, and the check above);
  `tools/check-docs.sh`: `check-docs OK`; gitleaks and the privacy patterns
  over this branch's commits: no findings. After the traces, the 42 test files
  whose covers changed since their traced run, with `test-affected.sh`, ran
  again in this worktree: 4707/4709. The two failures, `test-nvim-theme.sh`
  "one line per spec" (15 of 17 lines) and `test-themegen-keys.sh` (its panel
  harness aborts), fail the same way with `origin/main`'s unchanged files in
  this worktree and pass in the shorter-path copies the traces used (108/108
  and 82/82 checks there): they depend on the checkout's location, not on
  this plan, and CI's checkout path is short.

## Rejected options

- **"Nightly on main"** and **"Never"** as the place the full suite runs (the
  owner's decision above).
- **Tag-based grouping** (each test tagged `shell`, `vapt`, `omarchy`, … and a
  path-to-tag table). A tag is a second, coarser name for the same mapping:
  every path still has to be assigned to tags, and a tag selects every test
  that carries it, so a change to one plugin runs every `shell` test. The
  declarations say directly which test reads which path, and the check holds
  them complete.
- **Automatic inference from grep/imports as the primary mechanism.** It was
  tried first, as the scratch draft for the declarations, and kept only as a
  starting point:
  - with a transitive closure over the scripts tests run, the first pass
    reached 1,644 of the 2,457 tracked files from nearly every test: help text
    and comments name commands (`haseen theme set` in a usage message), and a
    few hubs (`share/haseen/omarchy/commands.tsv` names 559 paths, the Omarchy
    dispatcher, `theme-lib.sh`) connect everything to everything;
  - without the closure it misses what is not spelled out: paths built from
    variables in loops (`"$PLUGINS/$id/manifest.json"` over an id list,
    `"$FIXTURES/$name"`), libraries a command's library sources, QML a harness
    loads by symlinking `Haseen`, `Compat` and `plugins` and importing one
    plugin by relative path, plugins importing each other
    (`haseen.commands` reads `haseen.menu/MenuModel.js`), data a command reads
    through a variable (`THEME_TEMPLATES_DIR="$HASEEN_PATH/themed"` in
    `theme-lib.sh`), and Go or Rust sources reached only through
    `tools/build-sidecar.sh`;
  - it changes silently when someone rewords a comment. Written declarations
    are reviewable in the diff that changes a test, and `--check` holds the
    whole tree to them.
- **Test sharding** (a matrix of `test` jobs). Branch protection requires a
  check named `test`, and a matrix job reports as `test (1)`, `test (2)`, …
  (also recorded by plan 094's amendment in PR #55). It also leaves the total
  compute where it is: every PR would still run all 87 minutes of tests, in
  parallel containers, each paying the package install.
- **Path filters on the workflow** (`on.pull_request.paths`). A filtered-out
  PR never reports `test`, and a required check that never reports blocks the
  merge; the job must always run and decide inside.
- **Hashing test inputs and caching results.** It would need the same
  declarations to know a test's inputs, plus a cache that survives the
  ephemeral container; the declarations alone already give the saving.

## Limitations

- **A new dependency of an existing test on an existing file is not caught by
  `--check`.** The check proves every file is claimed by some test, not that
  every test claims every file it reads. A PR that makes a test read a file
  its covers do not name, without changing that test file, skips the test;
  `main`'s full run catches it after the merge. The fix is then a covers line,
  and the PR that adds it selects that test.
- **Copies are not dependencies.** Several suites copy whole trees they do not
  read further: `test-vapt-oniomarchy*.sh` copy `share/haseen/lib` and
  `share/haseen/default` and run only the VAPT install from the copy,
  `test-themes2.sh` copies `share/haseen` as a fetch mirror, `test-secureboot.sh`
  checksums `tests/fixtures` to prove nothing wrote to it, and
  `test-omarchy-commands.sh` installs the tree into a prefix. Their covers name
  what the copy is used for, not every file copied; a change that broke only
  the copying itself would show on `main`.
- **Not every merge gets a run of its own.** A running suite on `main` is
  no longer cancelled, but a merge that queues behind it is replaced by a
  newer one, as above. The newest run covers every queued merge, so a miss
  still turns `main` red; the commit that caused it is then one of those
  merges, not necessarily the one the red run names.
- **A file name with a tab, a newline or another control character** selects
  every test on a pull request and fails `--check` (so lint) until renamed.
- **The local mode reads the working tree.** `tests/run.sh --affected` without
  `--committed` adds staged, unstaged and untracked files, so scratch files in
  the checkout can widen the selection (an unclaimed one selects `all`); CI
  uses `--committed` on a clean checkout.
- **The base must be fetched.** Locally the default base is `origin/main` as
  last fetched: a stale `origin/main` widens the selection to everything
  merged since, never narrows it.

## Review round 1 (2026-10-21, at `d107e3b`)

The reviewer's findings and CI's first run of this plan's pull request, and
what changed:

1. **CI `lint` failed: git refused the checkout.** Run 39647712605, job
   119387579445: `fatal: detected dubious ownership in repository at
   '/__w/haseen/haseen'` after `go: 41 files`. `actions/checkout` v7 adds
   `safe.directory` only to a temporary git config for its own step; the
   later steps run as root in the `archlinux:latest` container on a checkout
   another uid owns, and `tools/affected-tests.sh --check` is the first git
   command `tools/lint.sh` runs. Fix: a "Trust the checkout" step in `lint`
   right after the checkout. `test` runs its git as `ci` after `chown -R`, and
   `docs` and `secrets` are not container jobs, so none of them needs it.
   Reproduced in `archlinux:latest` with the checkout owned by uid 1001: as
   root, `--check` exits 2 without the step and passes with it; as `ci` after
   the `chown`, `--check` and the selection pass without it.

   Guard: the selector now checks `git rev-parse --show-toplevel` first and
   stops with status 2 and its own message ("git cannot read this
   repository", or "git's repository is …, not this checkout") instead of
   leaving git's text to explain it; `git ls-files` and `git diff` write to
   files whose status is checked, and an empty file list stops `--check`
   ("git listed no files"). `tests/test-affected.sh` covers all three: git's
   own `GIT_TEST_ASSUME_DIFFERENT_OWNER` knob stands in for the other owner
   (the test first asserts git itself refuses), a copy of the selector
   outside its checkout, and a repository whose files are all ignored.
   `tests/run.sh --affected` then fails with status 2 and runs nothing.
2. **Tabs in file names.** The classification read tab-separated fields, so
   a root file `lib<TAB>E<TAB>x.c` was read as `lib`, exempt, and selected
   nothing; a tab-named file under `bin/` did the same. Newlines could not
   shift fields but split a name in two (`docs/a<NL>README.md` became two
   exempt halves). Now every path is read NUL-separated; a name with any
   control character is set aside before any format that cannot carry it,
   selects every test with the reason, printed with `%q`, and fails
   `--check`. Four new cases in `tests/test-affected.sh` (root tab name,
   `bin/` tab name, newline name, `--check` on a tab name); against the
   selector at `d107e3b` they and the guard cases fail (64/75), now 75/75.
3. **`main`'s full run must not be cancelled.** The owner chose the full
   suite after each merge, but `cancel-in-progress: true` cancels a running
   suite on `main` when the next run in its group starts: run 39613318574
   for `ed84608` was cancelled at 14:07 UTC, five minutes in, when run
   39613979814 started. Cancelling now applies to pull requests only (CI,
   above; Limitations).
4. **Libraries a covered command sources.** A static scan of every covered
   `bin/haseen-*` for `share/haseen/lib/*` it sources found undeclared
   libraries in four tests: `test-aipanel.sh` (21 libraries, via
   `bin/haseen-*`), `test-menu.sh` (15, via `bin/haseen-*`),
   `test-omarchy-commands.sh` (5, via `bin/haseen-*`) and
   `test-bar-basics.sh` (3, via `bin/haseen-update`). None is exercised, so
   none was added: each test ran in a copy whose flagged libraries print a
   marker and exit 99 at their first line (Lua: `error()`), and each passed
   unchanged (aipanel 77/77, menu 306/306, omarchy-commands 171/171,
   bar-basics 138/138); poisoning a library they do declare fails them
   (menu with `branding.sh` 285/306, omarchy-commands with `layers.sh`
   155/171). The `bin/haseen-*` globs are existence checks (every command
   the skill, the menu or a shim names must exist), and `bar-basics` only
   asserts the updates panel launches `haseen-update` (`haseen update check`
   runs `bin/haseen-update-check`). In their traced runs none of the flagged
   commands opened, except in `test-omarchy-commands.sh`, where the opens
   come from its tree install. No `--check` warning was added: the same scan
   flags 143 such edges in those four tests, every one a false alarm.
