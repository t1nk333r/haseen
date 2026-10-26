# Plan 135: a version bump is read by tests, depended on by none

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. It narrows a test selection for one file whose content no
  test asserts on; `tools/lint.sh` checks that file's format instead, and
  `tests/run.sh --affected` still widens for everything else.
- **Depends on**: 100 (the selector), 127 (the sidecar release reads VERSION)
- **Category**: tests, process
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26

## Problem

Owner, 2026-10-26: "i told you to just test the affected code not the whole".

`share/haseen/VERSION` appears in **104** test files' `# haseen:covers`
lines. They really do read it — `haseen about`, the sidecar release tag, the
`requires.haseen` comparison — but none of them pins its value, so the bump
from `0.1.0-dev` to `0.2.0-dev` (plan 134) selected almost the whole suite,
VAPT included: three local `--affected` runs of 40-60 minutes each for a
release nobody could break with a version string.

## What changed

- **`tools/affected-tests.sh`** gains a third list beside `GLOBAL` and
  `EXEMPT`:

  ```sh
  NOWIDEN=(
      share/haseen/VERSION         # the version string: read, printed, never pinned
  )
  ```

  A path in it selects **no test**, and — unlike `EXEMPT`, which a covers
  glob overrides — it is checked *before* the covers globs, because the point
  is precisely that a hundred tests name it. The report says so:
  `share/haseen/VERSION: read by many tests, depended on by none, no test`.
  `--check` accepts it as claimed, so the file is still neither uncovered nor
  stale.
- **`tools/lint.sh`** checks the format it can no longer get from a test:
  three numbers with an optional suffix. A malformed version (one that would
  break `requires.haseen` comparisons) fails lint before any install.
- **`tests/test-affected.sh`** builds the file for every `NOWIDEN` entry and
  asserts that a change to it selects nothing and that the report says why.

## Evidence

- `tests/test-affected.sh` → 77/77.
- `tools/affected-tests.sh --check` → 2700 files, 170 tests, 1916 covers
  globs, every file covered, global or exempt.
- With only `share/haseen/VERSION` changed, `tools/affected-tests.sh` prints
  nothing (before: about a hundred files).

## Rejected options

- **Deleting `share/haseen/VERSION` from the 104 covers lines.** They do read
  it, and it is a 104-file diff for the same result.
- **`GLOBAL`.** That runs the whole suite, which is what this removes.
- **`EXEMPT`.** A covers glob wins over it (`tools/affected-tests.sh`, rule
  order), so it would have changed nothing.
- **Trusting the bump because lint passed.** Formulaic and easy to forget;
  the check is three lines and runs with every commit.
