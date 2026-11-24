# Plan 194: wallpaper themes read under a terminal selection, keep their own picture and never replace a user's theme

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One key of a wallpaper theme's `colors.toml` changes
  (`selection_foreground`), so every existing wallpaper theme is rewritten
  once on its next `haseen theme wallpaper` run; `--name` now refuses names
  it used to overwrite.
- **Depends on**: 034 (wallpaper palettes), 064 (the contrast clamp), 067
  (`haseen theme generate`, whose ownership rule this copies), 115 (the
  shell's selection fill), 167 (the Rust generator)
- **Category**: theme
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit, run on plan 182's branch before it merged)
- **State**: DONE 2026-11-24 (`tests/test-wallpaper.sh` 52/52, among them
  `cargo test` with 30 unit, 8 command-line and 3 golden tests)

## Problem

The audit found five defects in the wallpaper theme path (group g10). Each
was re-checked on 9a9e82ab, main after plans 182-184, and still held. The
fourth is the comment side of the first.

### 1. Selected text in every terminal is unreadable (high)

`Generated::colors_toml` wrote `selection_foreground = p[0]`, the background,
and `selection_background = self.selection`
(`core/palette/src/generate.rs:376-381` at 9a9e82ab). The selection is the
background moved one small step (`anchors.rs:20-26`: 10 % toward white in
dark mode, 85 % in light). It is clamped only against the foreground
(`anchors.rs:43-47`). foot, kitty, ghostty and alacritty draw
`selection_foreground` on `selection_background` (`themed/foot.ini.tpl:4-5`,
`kitty.conf.tpl:3-4`, `ghostty.conf.tpl:4-5`, `alacritty.toml.tpl:26-27`),
and so does neovim's palette (`neovim.lua.tpl:40-42`). theme-lib aliases
`selection_foreground` only when the key is missing (`theme-lib.sh:246`), so
the written value wins.

The recorded golden showed it: `core/palette/tests/golden/png-rgb8-light-pastel.toml`
had `#f6f1e9` on `#d1cdc6`, which works out to 1.41:1 by the WCAG formula.
The new test below printed `mid-grey light=false normal:
selection_foreground #090909 on selection_background #222222: 1.25:1`
before the fix. The Go generator wrote the same thing, so the port carried
it over. `haseen theme generate` does it right: it writes Material's
`on_secondary_container` (`bin/haseen-theme-generate:199`).

### 2. A wallpaper with another extension keeps the old picture (medium)

The background link was named `<name>.<ext>`
(`bin/haseen-theme-wallpaper:105`), and nothing removed earlier links. After
`a.jpg` and then `b.png`, both `wallpaper.jpg` and `wallpaper.png` existed.
`haseen theme set` records the shown background first
(`haseen-theme-set:126`, `theme_remember_background`), and
`theme_link_background` (`theme-lib.sh:955-970`) prefers that remembered
image, or keeps the current link when it is a candidate. So the desktop kept
`a.jpg` in `b`'s colours. A path with no extension (`~/.wallpapers/sunset`)
gave `${image##*.}` = `wallpapers/sunset`. `ln` then failed under `set -e`
after `colors.toml` had already been replaced (`:100-101`).

### 3. `--name` overwrote a user's own, installed or stock-named theme (medium)

The only check was the name pattern (`:68`). Then
`$HASEEN_USER_CONFIG/themes/<name>/colors.toml` was replaced through `mv`
(`:100-101`), with no prompt and no ownership test. A `.lock` file was also
dropped into that directory (`:87-88`), which dirties the git checkout of an
installed theme. `--name tokyo-night` wrote a user overlay that recoloured
that stock theme for good (`theme_stage`, `theme-lib.sh:692-702`).
`haseen theme generate` refuses both cases (`bin/haseen-theme-generate:150-161`,
`:243-246`) and locks the directory itself (`:271`). docs/architecture.md
said "a theme of the user's own is never overwritten".

### 4. The comments named the wrong reader of `selection` (low)

`theme-lib.sh:320-325`, `bin/haseen-theme-generate:223` and
`core/palette/src/generate.rs:30` all said the shell draws its foreground
text on `selection`. Since plan 115 (70ac0c46) the shell's selection is
`mix background foreground 18%` (`themed/shell.json.tpl:14`,
docs/architecture.md:756-758 at 9a9e82ab). `git grep shell_selection share/haseen/themed`
finds nothing. The only reader of `shell_selection` is `omarchy-theme-color
--all` (`share/haseen/omarchy/bin/omarchy-theme-color:11`). The clamp still
protects real readers: yazi's hovered and selected rows
(`yazi.toml.tpl:71,87`), btop and neovim all draw the foreground on
`selection`. The comments credited it to the wrong reader, and they hid
finding 1: the pair terminals draw was never checked.

### 5. A computed palette was thrown away when the cache write failed (low)

`generate_with_cache` returns the palette together with a cache error, by
design (`generate.rs:278-280` doc, `:330-347`, and the unit test
`a_cache_that_cannot_be_written_is_an_error_after_the_palette`). `main`
exited 1 on any error before printing (`main.rs:171-174`). The temporary
file was a fixed `<key>.json.new` (`generate.rs:261`), so two runs on one
image (`--name a` and `--name b` do not share a lock) shared one inode, and
the second `rename` failed with ENOENT. The new test made 336 of 800
concurrent writes fail that way before the fix. An unwritable
`$XDG_CACHE_HOME/haseen/palette` failed every cold run, and
`haseen theme wallpaper` then died with "could not read a palette".

## Decision

1. **`selection_foreground` is the foreground** (`p[7]`, `generate.rs`
   `colors_toml`). The clamp already holds the foreground at 4.5:1 on the
   selection, so the pair terminals draw is now the pair that is checked.
   The golden `png-rgb8-light-pastel.toml` changes in that one line
   (`#25334c` on `#d1cdc6`, 8.0:1), and the header of `tests/golden.rs`
   records the hand edit. `CACHE_VERSION` stays 3: the cache holds the
   generator's palette, and that does not change.
2. **One link per run.** The link is still `<name>.<ext>`. After linking,
   the command deletes the other `<name>.*` symlinks in
   `backgrounds/<name>/`. These are only its own links: a picture the user
   put there is a regular file, and it stays. The new link is then written
   as the background remembered for the theme (`theme_bg_memory_file`,
   `replace_user_file`), so `theme set` shows it even when the folder holds
   other pictures. `theme set` records the picture shown under the current
   theme before it switches (`theme_remember_background`), so when the theme
   is already current and shows one of the user's own pictures (picked with
   `haseen theme bg`), that record would replace the new one: the command
   then points `current/background` at the new link first
   (`theme_set_background_link`), and only when it applies the theme. A
   path whose file name has no `THEME_BG_EXTS` extension is refused
   (`theme_background_named`) before anything is written.
3. **Generate's ownership rule.** A stock theme's name is refused. An
   existing directory is accepted only when its `colors.toml` starts with
   `# Generated by `haseen theme wallpaper``, the line haseen-palette
   writes first. An empty directory, or one holding only the `.lock` an
   older version left after a failed run, is also accepted. Anything else
   is refused, and the message names the directory. The check runs before
   `--dry-run` exits, so a dry run refuses too. The lock is now taken on
   the directory itself (`exec 9<"$theme_dir"`), and the old `.lock` file
   is removed.
4. **The comments name the real readers**: terminals, yazi, btop and neovim.
   `shell_selection` is described as `omarchy-theme-color`'s key. The
   comment at generate's clamp notes that `on_secondary_container` sits on
   the far side of the selection, away from the background, so the move
   toward the background only adds contrast for it.
5. **A cache error is a warning.** `main` prints the error on stderr. It
   exits 1 only when there is no palette, and otherwise prints the palette
   and exits 0. The temporary file is `<key>.json.<pid>.<n>.new`, where n
   is a per-process counter, and it is removed if the rename fails.

docs/architecture.md now covers the one key where the output differs from
Go's colors.toml, the per-writer temporary file and the warning, the link
replacement, and the ownership rule for both commands.

## Tests

- `core/palette/src/anchors.rs` `generated_themes_keep_anchor_contrast`:
  for every low-contrast fixture, both variants and every mode, it reads
  `selection_foreground` and `selection_background` out of the written
  `colors.toml` and requires 4.5:1. It failed before fix 1 (the 1.25:1
  above).
- `core/palette/src/generate.rs` `concurrent_writers_of_one_entry_both_succeed`:
  eight threads each write one entry 100 times. Every write must succeed,
  and only `key.json` may be left. Before fix 5, 336 writes failed with
  ENOENT.
- `core/palette/tests/cli.rs` `a_cache_that_cannot_be_written_still_prints_the_palette`:
  the cache path sits under a regular file, and the run must exit 0, print
  the palette and warn once. It exited 1 before.
- `tests/test-wallpaper.sh`, 19 new assertions. Run against the script at
  9a9e82ab, 13 of them failed (39/52):
  - a png and then a jpg wallpaper leave only `wallpaper.jpg` plus the
    user's own `aaa-mine.png`, and `current/background` resolves to the jpg;
  - no `.lock` in the theme;
  - with the theme current and `current/background` on `aaa-mine.png`, a
    new wallpaper is the picture shown afterwards (the old script left the
    user's picture);
  - an extension-less path (a different image, so the old script would
    have rewritten the palette) exits 1 with `colors.toml` untouched;
  - `--name` of a hand-written theme exits 1, leaving its `colors.toml` and
    directory as they were;
  - `--name tokyo-night` exits 1, with or without `--dry-run`, and writes
    no overlay;
  - a directory that holds only an old `.lock` is reused, and the lock goes.

## Rejected

- **Clamping the selection against the background colour** so that
  `selection_foreground = p[0]` would read. A selection far enough from the
  background to carry background-coloured text at 4.5:1 is no longer a
  quiet surface step. It would also stop meeting the foreground clamp that
  yazi and btop need.
- **One fixed link name per theme** (`wallpaper.img`). `theme_backgrounds`
  and `theme_background_named` list only `THEME_BG_EXTS` names, so the
  link would vanish from `haseen theme bg`.
- **Deleting everything else in `backgrounds/<name>/`**, as generate does
  in its own `themes/<name>/backgrounds/`. That folder is the user's
  backgrounds folder, and pictures they add there are their files.
- **A `--force` to overwrite a user's theme.** It needs an owner decision
  and nobody asked for one. A different `--name` does the job.
- **Exiting 1 but still printing the palette on a cache error.** The
  caller's `|| die` would still throw the palette away.
- **A random suffix from `/dev/urandom` for the temporary name.** The PID
  is unique across processes and the counter is unique within one, which
  is enough.
