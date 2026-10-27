# Plan 137: the banner says when the remote last reached the checkout

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. One `stat`-backed `date -r` on `.git/FETCH_HEAD`, printed only
  when that file exists; no fetch, no network, no mutation.
- **Depends on**: 136 (the `checkout` and `behind` lines this completes)
- **Category**: install, ergonomics
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27

## Problem

Plan 136's `behind=` line compares `HEAD` with the upstream ref git holds — and
on IO that comparison was innocent: `HEAD` and `origin/main` were **both**
`90d9c2c`, because nobody had fetched since. `behind` would have printed
nothing, on the very install it was written for.

A remote-tracking ref only knows what the remote said the last time someone
fetched. Without that date the banner can say the tree is old but not that
git's view of the remote is old too, which is the fact that explains a
"clean" behind count.

## What changed

`report_checkout` (plan 136) also prints, when git can name its directory and
`.git/FETCH_HEAD` exists:

```
    checkout=90d9c2c (2026-10-24)
    refs-fetched=2026-10-24
```

- The date is `.git/FETCH_HEAD`'s mtime — when git last heard from the remote,
  whoever ran the clone, pull or fetch. Both dates sitting days back is the
  whole story: the checkout and git's idea of the remote are the same age, so
  `behind` cannot be trusted and `git fetch` is the next step.
- No threshold and no judgement: a fresh install from a fresh clone prints the
  same date twice and looks correct; an old one prints two old dates.
- A tree without `.git/FETCH_HEAD` (a tarball, a `git` that cannot answer)
  prints no line, exactly as plan 136's two lines already behave.

Rejected: warning only when the date is "too old" (an arbitrary threshold that
is wrong for a deliberately pinned checkout, and it hides the date that makes
the warning true); fetching to find out (the dry-run contract).

## Tests

`tests/test-install-picker.sh`: a stubbed `git` whose `.git` holds a
`FETCH_HEAD` dated 2026-10-24 prints `refs-fetched=2026-10-24` beside the
commit and stays dry-pure; the same run without that file prints no date and
still succeeds — 87/87.

## Evidence

- `install.sh:276-296` — `report_checkout`; the fetch block sits between the
  `checkout` line and the `behind` comparison.
- IO, 2026-10-27: `git switch main && git reset --hard origin/main` printed
  `90d9c2c`, and `origin/main` was `68b710a` only after a fetch — the gap no
  local comparison could see.
