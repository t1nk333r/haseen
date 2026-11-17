# Plan 176: CI runs only the affected tests on main too

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW for the shipped tree (CI and docs only). It removes plan
  100's safety net: a test whose `# haseen:covers` misses a file it reads no
  longer runs after a merge that changes that file.
- **Depends on**: 100 (the affected selection)
- **Category**: tests, CI
- **Planned at**: 2026-11-17, owner (below)
- **State**: DONE 2026-11-17 (the workflow change selects every test, as a
  change to `.github/workflows/**` does, so this plan's own pull request and
  merge run the full suite one last time; the first narrowed run on `main`
  is the next merge after it)

## Owner decision (2026-11-17, verbatim)

After PR #132's merge ran the full suite on `main`, the owner said: "make the
test only for affected code not the whole thin g".

Plan 100 chose, with the owner on 2026-10-21, "After each merge to main" as
the place the full suite runs, and rejected "Never". This decision replaces
that one: a push to `main` now runs the tests that push affects, as a pull
request does. The full suite stays available by hand.

## Problem

Every push to `main` ran all of `tests/run.sh`
(`.github/workflows/ci.yml` on origin/main at `18d743c`, the `test` job's
step: `args=()` unless the event is `pull_request`). For PR #132:

- the pull request's own run, 44046677536, selected 21 of 175 test files
  ("affected: 21 of 175 test files") and passed 3497/3497 in 7 minutes
  (job `test`, 08:26:02-08:33:14 UTC);
- the merge's run on `main`, 44048108539, ran all 175 files, 20785/20785,
  in 84 minutes (08:36-10:00 UTC), for the same change.

Branch protection already requires an up-to-date branch, so the merge commit
is the pull request's tree: the full run tested the same change again with
more files.

## Decision

- The `test` job on a push to `main` runs
  `tests/run.sh --affected --committed "$BEFORE"`, where `$BEFORE` is
  `github.event.before`, the commit `main` pointed at before the push. A
  squash merge's push then selects exactly the merged pull request's paths.
- If `$BEFORE` is not an ancestor of the head, the job runs the full suite
  and says why. That covers a new branch's all-zero SHA and a rewritten
  history (protection forbids force pushes on `main`, but the workflow does
  not rely on that). `git merge-base --is-ancestor` exits 128 on an unknown
  or all-zero commit, so both fall through to the full suite. The check runs
  as `ci`, who owns the checkout after the `chown`; as root, git would refuse
  it as dubious ownership and every push would fall back to the full suite.
- A manual run (`workflow_dispatch`, `gh workflow run ci --ref main`) still
  runs the full suite. A change to a GLOBAL path (`tests/lib.sh`,
  `tests/run.sh`, `tools/affected-tests.sh`, `.github/workflows/**`,
  `common.sh`, `bin/haseen`) still selects every test, as before.
- Concurrency. In the old shared group `ci-refs/heads/main`, GitHub keeps
  one pending run and cancels an older pending one. That was safe while each
  run tested the whole tree: the newest run carried every earlier merge.
  With each push testing only its own diff, a dropped pending run would
  mean that merge's tests never run. Every run other than a pull request's
  now has its own group (`github.run_id`), so nothing cancels it. Pull
  requests keep `ci-<ref>` with `cancel-in-progress`.
- Docs: `AGENTS.md` (`CLAUDE.md` links to it), `handoff.md`, and the
  comments in `tests/run.sh` and `tools/affected-tests.sh` stop saying that
  `main` runs everything.

## Rejected

- **A nightly full run.** Plan 100 rejected it as a safety net that leaves a
  miss on `main` for a day. The owner asked for affected tests only, and the
  manual run covers the occasional full check. It can be added later as a
  `schedule:` trigger without touching the selection.
- **Keeping the shared concurrency group for `main`.** It would drop a
  merge's only test run whenever two merges queue behind a third (above).
- **Testing from the pull request's base instead of `github.event.before`.**
  A push event has no pull request, and `before` is the same commit for a
  squash merge onto an up-to-date branch.

## Limitations

- **A missing covers line is no longer caught after the merge.** Plan 100's
  first limitation ("A new dependency of an existing test on an existing
  file is not caught by `--check`") used to end with "`main`'s full run
  catches it after the merge". It now shows only when that test's own
  covered files change, a global path changes, or someone runs the workflow
  by hand. Plan 100's "Copies are not dependencies" limitation is affected
  the same way.
- **Shared-library changes still widen.** A change under `share/haseen/lib/`
  selects every test whose covers name that library, which can be most of
  the suite. That is the selection working, not a fallback.

## Verification

- `git merge-base --is-ancestor` in a scratch repository: the all-zero SHA
  and an unknown SHA exit 128, `HEAD` exits 0, so only a real ancestor
  selects.
- `tools/lint.sh`, `tools/check-docs.sh` and `tools/secrets.sh` on this
  branch.
- This pull request's CI selects every test (the workflow is GLOBAL); the
  next merge's run on `main` should log "affected: N of 175 test files".
