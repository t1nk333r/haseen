# Plan 127: The sidecar arrives as a release, not a toolchain

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM. The installer now downloads two binaries. Nothing is
  installed unless the release's `SHA256SUMS` names the asset and the hash
  matches, and an unreachable release falls back to the old behaviour (a tree
  with no daemon, plan 032), so the failure mode is the one that shipped
  before — not a broken install.
- **Depends on**: 032
- **Category**: build
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, "create the sidecar on github and install
  it on IO and make it when on a new machine it gets pulled").

## Why

`install.sh` runs `tools/build-sidecar.sh` before it copies the tree
(`install.sh:219-229`), and that script could only build the daemon from
`core/` with a Go toolchain. IO has none, so its install ended without the
daemon:

```
$ ssh io 'uname -m; command -v go || echo "no go"; ls /usr/local/share/haseen/sidecar'
x86_64
no go
ls: cannot access '/usr/local/share/haseen/sidecar': No such file or directory
$ ssh io 'haseen sidecar status'
binary:       missing (/usr/local/share/haseen/sidecar/haseen-sidecar)
capabilities: none; features that need the daemon stay hidden
```

Two approved features are behind that daemon: `haseen.sysusage` (its sampler
is the daemon's `sysusage` stream, `docs/architecture.md` §5.6) and the theme
border wipe (`borderwipe`). A machine with no Go lost both silently, and a
new machine would too.

The binaries are pure Go (`CGO_ENABLED=0`), so one static build per
architecture serves every machine — there is no reason for each install to
carry a toolchain, or to wait for a build. What a fresh machine needed was
somewhere to *pull* them from.

## What changed

- **`tools/release-sidecar.sh`** (new) — `[--target REF] [--dry-run]` builds
  `haseen-sidecar` and `haseen-palette` for `linux/amd64` and `linux/arm64`
  from `core/` (`CGO_ENABLED=0`, `-trimpath -buildvcs=false`, `-s -w`, the
  version stamped), writes `SHA256SUMS` over the four assets, then creates
  `sidecar-v<share/haseen/VERSION>` (if absent) and uploads them with
  `--clobber`. One release per version: a `VERSION` bump needs a new run, and
  re-running the same version replaces the assets rather than piling up tags.
  `--target` decides the commit the tag points at; the default is `HEAD`, and
  it is run against `origin/main` so the tag names merged code. Arguments are
  read in a `while` loop, so `--dry-run --target REF` means what it says.
- **`tools/build-sidecar.sh`** — with no `go` on `PATH` (or `$GO` pointing at
  nothing) it now fetches the release instead of skipping: `SHA256SUMS`, then
  `haseen-sidecar-linux-<arch>` and `haseen-palette-linux-<arch>` from
  `https://github.com/t1nk333r/haseen/releases/download/sidecar-v$VERSION`,
  verified in the temp directory before either file is installed:
  `SHA256SUMS` must *name* both assets (one line each, which
  `--ignore-missing` alone does not require), and then
  `sha256sum --ignore-missing -c` must agree with both. Both land where the
  built ones do (`$DEST` and `haseen-palette` beside it), so nothing
  downstream changes.
  - `HASEEN_SIDECAR_URL` points the fetch at another base — a mirror, or a
    `file://` directory in tests; `HASEEN_FETCH_SIDECAR=0` restores the old
    "no go toolchain; haseen-sidecar not built" and installs nothing.
  - A checksum mismatch is an error (exit 1) and installs nothing. No curl, no
    asset for the architecture, or an unreachable release is a warning and
    exit 0: the tree ships without the daemon and the shell hides what needs
    it (plan 032), exactly as before. An install never fails because a release
    is missing.
  - `GO` is now an override (`GO="${GO:-go}"`), which is how the new test
    simulates a machine with no toolchain on a host that has `/usr/bin/go`.
- **`tests/test-sidecar-fetch.sh`** (new) — a `file://` "release" directory, a
  stubbed `curl` that only reads it, and `GO` naming a missing binary: the
  fetch installs both files and prints `fetched linux-<arch>`; a tampered
  asset fails with `does not match its SHA256SUMS` and leaves nothing behind;
  a sums file that names neither asset of this architecture fails before the
  hash is read; `HASEEN_FETCH_SIDECAR=0` keeps the old message and installs
  nothing.
- **`tests/test-sidecar-release.sh`** (new) — a stub `go` writes the asset path
  it is asked to build and a stub `gh` records the calls, so the publisher is
  exercised without a toolchain or the network: the release is created at the
  given commit with all four assets and `SHA256SUMS` (`--clobber`), an
  existing release is uploaded to without a second create, the dry run calls
  no `gh` at all, and a bad argument exits 2.

## Also in this change

- **`AGENTS.md`** — the gates gain one rule: **test the affected code, not the
  whole suite.** `tests/run.sh --affected` is the local gate, the one file a
  change touches is what you iterate on, and the full run stays CI's job on
  `main` (owner, 2026-10-26, "make a rule to test the affected code not the
  whole"). It was being observed by habit; a rule makes a full local run the
  exception it should be.

## Evidence

- `tests/run.sh tests/test-sidecar-fetch.sh tests/test-sidecar-release.sh` →
  33/33 (13 fetch, 20 release).
- `tools/release-sidecar.sh --dry-run` builds all four assets and prints the
  three `gh` calls it would make; the built `haseen-sidecar` answers
  `-capabilities` with `sysusage borderwipe`, and the `arm64` asset is an ELF
  aarch64 binary (`file`).
- A real fetch against the published release on a host with no toolchain in
  `PATH`: `build-sidecar: …/haseen-sidecar (0.1.0-dev, fetched linux-amd64)`,
  and the installed binary answers `-capabilities` the same way.
- IO after re-running `install.sh` with the sidecar commit: the binary and
  palette are in `/usr/local/share/haseen/sidecar`, `haseen sidecar status`
  reports the capabilities, and `haseen-shell.service` starts with no
  "Process failed to start" for the daemon.

## Owner steps

- After merging a change to `core/` or a `VERSION` bump, run
  `tools/release-sidecar.sh --target origin/main` from a machine with Go: that
  is the only way an install without a toolchain sees the new daemon.
- Machines installed before this change pick it up on their next
  `install.sh` run; nothing else has to be done on them.

## Rejected options

- **Commit the binaries to the repository.** The repo is public and its
  history is linear; four binaries per release would live in history forever
  and no checksum would mean anything. A release is a versioned, replaceable
  place for exactly this.
- **Build on the target machine.** That is what failed: IO has no Go, and
  installing a toolchain per host to build a 12 MiB daemon once is a worse
  dependency than a download.
- **A package (AUR/Haseen's own repo).** The AUR is the last resort
  (`AGENTS.md`), and a package would either depend on Go (the same problem) or
  publish the same prebuilt binaries with a second versioning scheme.
- **Fetch from a haseen-hosted endpoint.** One more service to run, secure and
  keep alive for the same bytes GitHub already stores next to the source.
- **`git` as the transport (`git archive` a built tree).** Binaries do not
  belong in a branch, and the checkout the installer uses has no write access
  to the release either way.
