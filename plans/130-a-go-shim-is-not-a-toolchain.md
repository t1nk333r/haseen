# Plan 130: A `go` shim that does not run is not a toolchain

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. One probe changes from `command -v` to running the tool. A
  real toolchain answers `go version`; anything else is treated as absent,
  which is the path plan 127 already made safe (fetch, or skip with a
  warning).
- **Depends on**: 127
- **Category**: build
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, running the installer on IO).

## Why

Plan 127 made a machine without a Go toolchain fetch the sidecar release
instead of building it. The test for "has a toolchain" was
`command -v "$GO"` — and a mise shim answers that. On IO the shim exists with
no version set, so `install.sh` stopped at the first build:

```
$ ./install.sh --yes
mise ERROR No version is set for shim: go
Set a global default version with one of the following:
mise use -g go@1.27.1
```

`tools/build-sidecar.sh` then failed under `set -e`, and the install aborted
instead of fetching the release. `build_wootingd` already avoids exactly this
trap for rustup's `cargo` ("cargo --version, not only command -v"); the Go
side did not.

## What changed

- **`tools/build-sidecar.sh`** — `build_go` runs `"$GO" version` (quietly)
  instead of trusting `command -v`, so a shim that errors counts as no
  toolchain and the release is fetched. The header says so too.
- **`tests/test-sidecar-fetch.sh`** — a `go` that exists and exits 1 (mise's
  message on stderr) still installs the fetched daemon.

## Evidence

- `tests/run.sh tests/test-sidecar-fetch.sh` → 16/16 (the broken-shim case is
  three of them).
- IO: the same `install.sh --yes` that failed above completes and reports
  `build-sidecar: … (0.1.0-dev, fetched linux-amd64)`.

## Owner steps

- Machines that hit this rerun `./install.sh --yes` after pulling `main`;
  nothing has to be configured.

## Rejected options

- **Point mise at a Go version** (`mise use -g go@1.27.1`). That installs a
  toolchain to build a daemon we published prebuilt for exactly this case,
  and it is the user's mise config to change, not the installer's.
- **Skip the sidecar whenever `mise` is on `PATH`.** mise can wrap a working
  Go as well as a broken one; the tool's own answer is the fact we need.
