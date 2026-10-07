# Plan 066: `haseen`, haseen's own theme and the default

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (the colours are unchanged; the only user files touched are `theme.name` and the background folder of a user who is on `greek-noir-akane`, through a migration)
- **Depends on**: 004 020 028
- **Category**: theme, defaults, migrations
- **Planned at**: 2026-10-07, owner request on io: "greek-noir-akane becomes haseen's own theme `haseen`, the default for new installs"
- **State**: DONE 2026-10-07 (theme, alias, migration and install tests; the live rename on io is an integrator step)

## Problem

The default theme was `greek-noir-akane`: HANCORE's Greek Noir (MIT) as the
owner runs it on luna, with the owner's "akane" active-border wipe. The owner
wants it to be haseen's own derivative theme, named `haseen`, and the colours
of every new install. Existing users on the old name, io among them, must keep
their theme and wallpaper.

Two facts found while doing it:

- io was not on gruvbox. Its `theme.name` was `greek-noir-akane`, and
  `current/background` pointed at
  `~/.config/haseen/backgrounds/greek-noir-akane/1-akane.jpg`.
- `install.sh` ran migrations only when `~/.local/state/haseen/migrations/`
  existed, and sealed them otherwise. No migration had shipped before this
  one, so that directory existed nowhere, and every existing user would have
  had this first real migration sealed and never run.

## Change

- **Theme:** `share/haseen/themes/greek-noir-akane/` becomes
  `share/haseen/themes/haseen/`. `LICENSE` (2026 HANCORE, MIT) is kept.
  `UPSTREAM.md` and the `colors.toml` header credit HANCORE's Greek Noir and
  name the theme `haseen`. The colours, `hyprland.lua`, `neovim.lua`
  (aether), `vscode.json` ("Amp Dark") and `icons.theme` (Yaru-sage) are
  unchanged; none of them carried the old name. The theme ships no images and
  no fetch list: the "akane" images have no known licence and it is not an
  Omarchy theme. The user's backgrounds go in `~/.config/haseen/backgrounds/haseen/`.
  The readable shell selection (`shell_selection`, `#864313`) comes from
  theme-lib unchanged.
- **Default:** `THEME_DEFAULT=haseen` in `theme-lib.sh`, used by the theme
  layer (which `install.sh` applies) and the "no theme set" hints. The
  fallback tokens in `shell/Haseen/Theme.qml` are now the `haseen` theme's
  rendered `shell.json`, fonts included (Inter, JetBrainsMono Nerd Font, 11).
  A test keeps the two in step.
- **Alias:** `THEME_ALIASES=([greek-noir-akane]=haseen)` in `theme-lib.sh`.
  `theme_resolve_alias` maps an old name to the new one and prints
  `theme 'greek-noir-akane' is now called 'haseen'` on stderr.
  `haseen theme set` resolves names through it, and so does
  `theme_current_name`, which backs `theme current`, `theme bg` and
  `theme fetch`, for an old `theme.name`. A user theme directory of the old
  name is the user's own and is not aliased. `theme_backgrounds haseen` also
  reads `backgrounds/greek-noir-akane/` after `backgrounds/haseen/`, so
  `theme set haseen` on a HOME that was never migrated keeps the wallpaper.
- **Migration:** `share/haseen/migrations/1791356361-theme-haseen.sh` acts
  only when `theme.name` says `greek-noir-akane`:
  1. It moves `backgrounds/greek-noir-akane/` to `backgrounds/haseen/`,
     unless that folder already exists.
  2. It points `current/background` at the same image in the moved folder.
  3. It rewrites `theme.name` last, so a run that stops partway finishes on
     the next run.

  `current/theme/` is left as it is, because its colours are identical.
- **First-install check:** before the layers run, `install.sh` decides
  whether HOME is fresh. A HOME is fresh when it has no migration ledger, no
  `~/.config/haseen/shell.json` and no `current/theme.name`. Only a fresh HOME
  seals migrations, and it is still the only case that seeds haseen.nvim
  (`--if-absent`). Any other HOME has its pending migrations run.

## Tests

`tests/test-theme-haseen.sh` (65 checks) covers:
- **Theme:** the old directory is gone; the licence, UPSTREAM, header and
  NOTICE credit HANCORE; `haseen` renders with the darkened selection;
  every `Theme.qml` fallback equals the rendered `shell.json`.
- **Alias:** `theme set Greek-Noir-Akane` sets `haseen` with the notice, and
  its dry run plans `haseen`; an old `theme.name` reads as `haseen` with the
  notice; a user theme of the old name is not aliased.
- **Backgrounds:** with no `backgrounds/haseen/`, the image comes from the old
  folder; when both exist, `backgrounds/haseen/` is listed first.
- **Migration:** when the current theme is greek-noir-akane, it renames
  `theme.name`, moves the folder, relinks the same image and records
  `applied`. A second `haseen migrate` has nothing pending, and re-running the
  script itself changes nothing. On gruvbox nothing moves. When
  `backgrounds/haseen/` already exists, that folder and the link are left
  alone.
- **install.sh --dry-run:** a fresh HOME seals the migration and plans
  `theme.name: haseen`. A HOME with `theme.name` but no ledger runs it, and so
  does a HOME with only `shell.json`.

`tests/test-theme.sh` and `tests/test-themes2.sh` now use `haseen` as the
default and haseen's own stock theme.

## Live apply (integrator, io)

1. `./install.sh` from the worktree. io has `theme.name`, so the install runs
   the pending migration: `theme.name` becomes `haseen`, and
   `~/.config/haseen/backgrounds/greek-noir-akane/` moves to
   `backgrounds/haseen/` with `current/background` relinked to
   `backgrounds/haseen/1-akane.jpg`. The theme layer leaves the set theme
   alone.
2. `haseen theme set haseen` re-renders `current/theme` under the new name,
   with the same colours and the same 1-akane.jpg.
3. Check: `haseen theme current` prints `haseen` with no notice, and
   `readlink ~/.local/state/haseen/current/background` ends in
   `backgrounds/haseen/1-akane.jpg`.
