# Plan 136: the install banner names the checkout and says when it is behind

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. Two read-only `git` questions in the preflight banner; every
  failure path prints nothing, so a tarball or a broken git changes no
  behaviour. No mutation, no network, no new dependency.
- **Depends on**: 127 (the sidecar fetch), 130 (the `go` shim test), 134 (the
  install stamp — the same `git rev-parse` the stamp already needs)
- **Category**: install, ergonomics
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27

## Problem

Owner, 2026-10-27, after `haseen update` and an install on IO:

```
cachyos-quickshellarchy main ❯ ./install.sh --yes
    distro=omarchy
    firmware=uefi
    ...
mise ERROR No version is set for shim: go
mise ERROR Version: 2026.10.17 linux-x64 (2026-10-21)
mise ERROR Run with --verbose or MISE_VERBOSE=1 for more information.
```

That `mise` trap was closed by plan 130 — but IO's checkout was at `90d9c2c`
(`git switch main && git reset --hard origin/main` printed `90d9c2c clock: add
a day-name toggle (#36)`) because **`git switch` does not fetch**. The fetch
that would have brought `68b710a` happened only later, by hand, and the
install then succeeded.

So the installer was doing exactly what it promises — building the tree it is
given — and giving the owner no way to see that the tree was two commits and
one fix old. The preflight banner names the distro, firmware, bootloader, ESP,
LUKS and GPU, and says nothing about the code.

## What changed

`install.sh` gains `report_checkout`, called straight after the preflight
banner, printing the same `key=value` shape:

```
    distro=omarchy
    ...
    gpu=intel
    checkout=90d9c2c (2026-10-24)
    behind=origin/main by 12 commit(s); run: git fetch && git pull --ff-only
```

- `checkout` is `git rev-parse --short HEAD` plus the commit date
  (`%cd --date=short`), so the tree's age is visible, not just its hash.
- `behind` appears only when the branch has an upstream and that ref already
  holds newer commits. It is **local refs only**: no fetch, no network, nothing
  to time out. A stale *remote-tracking* ref therefore understates the gap —
  that is the honest answer, because it is the only one this host can know
  without going online, and `haseen update haseen` is the command that fetches
  (plan 134).
- A checkout git cannot read prints neither line, which is what a tarball
  install already had. Every `git` call sends stderr to `/dev/null` and any
  failure returns 0, so a missing or stubbed git changes nothing.

Rejected: refusing to install a checkout that is behind (a branch under test is
a legitimate tree, and the owner installs from one); fetching in the installer
(the dry-run contract; `haseen update haseen` owns the network).

## Tests

`tests/test-install-picker.sh` drives `install.sh --dry-run` with a stubbed
`git`: a checkout 12 commits behind prints both lines and stays dry-pure, one
that is current prints `checkout` only, and a git that exits 1 prints neither
while the rest of the banner and the layer order are unchanged — 82/82.

## Evidence

- `install.sh:290-291` — `preflight_report | sed 's/^/    /'`, then the
  `report_checkout` call on the next line.
- `install.sh:276-287` — the function; `2>/dev/null` and `|| return 0` on each
  of the four `git` calls.
- IO's stamp after the fixed run: `commit=68b710a version=0.2.0-dev`.
