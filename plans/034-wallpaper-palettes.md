# Plan 034: Wallpaper palettes

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a new command and a cache; the theme pipeline is unchanged)
- **Depends on**: 004 032
- **Category**: shell
- **Planned at**: 2026-10-05, owner request (the one thing end-4 and caelestia have and haseen did not)
- **State**: DONE 2026-10-05

## Problem

haseen's themes were hand-written colour sets. A wallpaper could not become a
theme, which is the one feature every neighbouring shell has.

## Decision

Three generators were on the table and the choice mattered:

- **matugen** (what DankMaterialShell drives): an external Rust binary.
  `core/internal/matugen/matugen.go:1014,1082,1169` only shells out to it, with
  version sniffing for three flag generations, and it produces Material 3 role
  tokens that haseen's `colors.toml` does not speak.
- **Noctalia's vendored Material Color Utilities** (`third_party/`, Apache-2.0):
  real M3 in process, but C++ in a Go/QML/bash repo, and the same role-vs-ANSI
  mismatch.
- **aether's extractor** (MIT, pure Go, `internal/extraction` +
  `internal/color`): median cut over a sampled image, producing a **16-colour
  ANSI palette** — exactly the shape `colors.toml` and every template in
  `share/haseen/themed/` already read.

haseen takes aether's extractor, vendored into `core/internal/palette`, and
keeps the parts of DMS's pipeline that are mechanism rather than generator:

- A **seed cache** keyed on the image's **content hash** (upstream keys on path
  plus mtime), so a wallpaper that is copied, re-downloaded or touched is the
  same seed and costs nothing.
- **Serialised regeneration** (a flock around the theme directory) so two
  wallpaper changes in a row cannot race on one `colors.toml`.
- A **byte comparison before writing**, upstream's `renderColors`: an unchanged
  palette must not touch the file, or a theme set, a `FileView` and every hook
  downstream react to a wallpaper that produced the same colours. The generated
  text is therefore a function of the seed alone — no image path, no timestamp.

`haseen theme wallpaper <image>` writes an ordinary haseen theme
(`~/.config/haseen/themes/<name>/colors.toml` plus the image as its background)
and then runs `haseen theme set`, so every template renders exactly as it does
for a stock theme. The GUI question is answered by compatibility rather than
code: aether itself writes the same `colors.toml` format, so a user who wants
the visual editor installs aether and haseen reads its output.

## Verification

- Go tests (`core/internal/palette`): the cache hits on a second run, a copy of
  the image under another name is the same seed, a different image/mode/light
  setting is not, a non-image and an unknown mode are refused, and the
  `colors.toml` carries all 16 ANSI slots plus the named keys.
- `tests/test-wallpaper.sh` (24): dry-run purity, the theme and background land,
  an unchanged seed reports "palette unchanged" and leaves the file's mtime and
  inode alone, a different wallpaper regenerates, `--name`/`--light` work, a
  name that could escape the themes directory is refused, and the generated
  theme renders through `haseen theme set` into `shell.json` and `foot.ini`.
- Live on the reference laptop: 0.55 s cold, 0.11 s cached; a second wallpaper
  produced a different palette; the rendered shell tokens matched the generated
  `colors.toml`.

## Execution record

`core/internal/palette/` (vendored extractor plus haseen's cache, decoder and
`colors.toml` emitter), `core/cmd/haseen-palette`, `bin/haseen-theme-wallpaper`,
the second binary in `tools/build-sidecar.sh`, and `tests/test-wallpaper.sh`.
