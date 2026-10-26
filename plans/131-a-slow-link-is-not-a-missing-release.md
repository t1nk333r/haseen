# Plan 131: A slow link is not a missing release

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. A longer limit on two downloads and a message that names the
  real cause; the failure path is unchanged.
- **Depends on**: 127
- **Category**: build
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (IO's install, the same day).

## Why

Plan 127's fetch gave each binary 120 s (`curl -m 120`) and reported any
failure as "is not in the release". On IO the release download of
`haseen-palette-linux-amd64` (3.78 MB) took **2m6s**:

```
$ time curl -fsSL -o /tmp/probe-palette …/haseen-palette-linux-amd64
real    2m6.077s
```

so the install printed

```
build-sidecar: haseen-palette-linux-amd64 is not in the release; haseen-sidecar not installed
```

for an asset that is there, and shipped a tree without the daemon.

## What changed

- **`tools/build-sidecar.sh`** — the per-asset limit is
  `HASEEN_SIDECAR_TIMEOUT` (default 300 s), and a failure that is not curl's
  `22` (HTTP error) is reported as what it is: `did not download (curl exit
  N, 300s limit)`. Only a 404 still says "is not in the release".
- **`tests/test-sidecar-fetch.sh`** — a release directory that has the sidecar
  and not the palette (curl exits 37 on `file://`) reports the download, not
  the release, and installs nothing.

## Evidence

- `tests/run.sh tests/test-sidecar-fetch.sh` → 19/19.
- IO: after the change the install fetches both assets and
  `haseen sidecar status` reports `sysusage borderwipe` from a running
  daemon.

## Owner steps

- Nothing to configure. A very slow link can be given more time with
  `HASEEN_SIDECAR_TIMEOUT=600 ./install.sh --yes`.

## Rejected options

- **Retry in a loop.** A retry hides the cause and can hold an install for
  minutes per attempt; one limit that fits the link plus a message that says
  which failed is enough.
- **Fetch in the background during the install.** The tree is copied right
  after the build; a download that lands later would not be in it.
