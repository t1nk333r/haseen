# Plan 058: Neovim follows `haseen theme set`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (only links in `~/.config/nvim/lua/plugins/`; a file of the user's is never replaced, Omarchy's files are kept as backups)
- **Depends on**: 004 020 048
- **Category**: theme, editor, Omarchy migration
- **Planned at**: 2026-10-07, owner question "nvim?" on io
- **State**: DONE 2026-10-07 (live switch proven in a scratch copy of io's nvim; the owner's own nvim is an integrator step)

## Problem

io runs Omarchy's LazyVim config (`omarchy-nvim` 2026.8.13, seeded from
`/etc/skel/.config/nvim`). `lua/plugins/theme.lua` links to
`../../../../.local/state/omarchy/current/theme/neovim.lua`
(`omarchy-nvim-setup`, the `ln -snf` near its end), which is Omarchy's theme,
stale under haseen. haseen renders `~/.local/state/haseen/current/theme/neovim.lua`
from `share/haseen/themed/neovim.lua.tpl`, but nothing pointed nvim at it, and
the reload plugin is named `omarchy-theme-hotreload.lua`.

## How Omarchy does it (read on io)

- **Link:** `omarchy-nvim-setup` links `theme.lua`. Migrations
  `1781158082.sh` and `1785002349.sh` repoint any link ending in
  `/omarchy/current/theme/neovim.lua`.
- **Trigger:** lazy.nvim's change detection. `lazy/manage/reloader.lua` stats
  every spec module every 2000 ms with `vim.uv.fs_stat`, which follows the
  link, and on a size/mtime change runs `Plugin.load()` and fires
  `User LazyReload`. It is enabled on `VeryLazy` only when nvim has a UI
  (`lazy/core/config.lua`: headless nvim never polls).
- **Reload:** `omarchy-theme-hotreload.lua` listens for `LazyReload`. It
  re-requires `plugins.theme`, clears highlights, unloads the colourscheme
  plugin's modules, reloads the plugin if loaded (two themes on aether) or
  loads it, then applies `opts.colorscheme` and re-sources
  `plugin/after/transparency.lua`.
- **aether.nvim** also watches `~/.local/state/omarchy/current/theme/neovim.lua`
  with a libuv fs_event (`lua/aether/hotreload.lua`). That is an Omarchy-path
  speed-up only. haseen's path relies on lazy's poll, so a switch lands within
  2 s.
- **all-themes.lua** lists every theme plugin `lazy = true`, so lazy installs
  them at startup and a switch never needs a clone.

## Decision

- `share/haseen/default/nvim/haseen-theme-hotreload.lua` is Omarchy's reload
  under haseen's name, with the same trigger and steps (Omarchy notice in the
  header, NOTICE.md row). It registers its autocmd from the module body in a
  cleared augroup and returns an empty spec. lazy `loadfile`s every spec module
  on each load (`Spec:import`, `lazy/core/plugin.lua`), so the augroup keeps
  it to one autocmd.
- `share/haseen/default/nvim/haseen-all-themes.lua` lists the 15 plugins the
  stock themes and the template name. haseen's own list is needed: the
  template uses `omacom/aether.nvim` (upstream; `bjarneo/aether.nvim` is its
  fork, per the GitHub API `parent`), and a user without Omarchy has no list.
- `theme_link_nvim` (theme-lib.sh), called by `haseen theme set` after the
  swap:
  - It acts only on a LazyVim config: `lazyvim.json`, or `lua/config/lazy.lua`
    naming `LazyVim/LazyVim`.
  - It links `theme.lua` to `current/theme/neovim.lua` when the file is absent
    or a link matching `/(omarchy|haseen)/current/theme/neovim.lua$`. Any
    other link or a regular file is the user's and stays.
  - It links haseen's two files when absent, or when they are haseen links
    from another prefix.
  - It skips each of haseen's two files while Omarchy's twin is still there,
    because both would reload. Omarchy's twin is `omarchy-theme-hotreload.lua`,
    or an `all-themes.lua` that matches the packaged copy or mentions Omarchy.
  - Every link is made as a temporary link renamed over the old one, so lazy's
    poll never sees the spec missing.
  - It links nothing before the rendered `neovim.lua` exists, because a
    dangling spec would break nvim's startup.
- `haseen import omarchy` (`import_nvim`) moves Omarchy's two files to
  `<file>.bak-<timestamp>` and runs the same linking with
  `--replacing-omarchy`. It logs every move and link, and lists anything kept
  under "Not imported". It does nothing until a haseen theme is set. The
  user's other plugin files are untouched.
- Theme specs:
  - `greek-noir-akane` now names `omacom/aether.nvim`, like the template.
  - `hackerman`'s dependency is `{ "omacom/aether.nvim", branch = "v3", name = "aether" }`.
    The bare `"bjarneo/aether.nvim"` resolved to a separate plugin `aether.nvim`
    (lazy keys by name, falling back to the URL, `lazy/core/meta.lua`), which no
    list installs, so a switch to hackerman needed a clone.

Rejected:
- **Omarchy's wrapper**: a local plugin with `dir = stdpath("config")`.
  lazy finds an existing plugin by name, then by URL or dir
  (`lazy/core/meta.lua`, `str_to_meta`). Any second spec with that dir
  (Omarchy's hook, or one of the user's) would therefore merge with it, and
  one config would replace the other.
- **An fs_event watcher of haseen's own** (aether-style). It would duplicate
  lazy's poll, which already runs, and a second trigger would reload twice.
- **Relative links** (Omarchy's choice, made for `/etc/skel`). haseen links
  per user at `theme set`, so absolute paths follow `XDG_STATE_HOME`.
- **Deleting Omarchy's files** on import. They were seeded into the user's
  config, so they are kept as backups.

## Verification

- `tests/run.sh tests/test-nvim-theme.sh` (sandbox HOME):
  - fresh LazyVim links all three files;
  - a plain config and a `lazyvim.json`-only config;
  - Omarchy 4 relative and Omarchy 3 absolute links are repointed, and
    Omarchy's files are left alone by `theme set`;
  - the user's regular `theme.lua` and the user's own link stay;
  - dry runs write nothing;
  - the import moves Omarchy's files to backups, links haseen's, keeps the
    user's `keymaps-personal.lua`, `luasnip-snippets.lua` and a user
    `all-themes.lua`, and a re-run changes nothing;
  - the import refuses before a theme is set.
- The same file runs headless `nvim -l` checks:
  - every `themes/*/neovim.lua` and the rendered template parse, set a
    colourscheme, and name only plugins (by lazy name, URL and branch) that
    `haseen-all-themes.lua` lists;
  - firing `LazyReload` after `theme.lua` changed switches `g:colors_name`
    (lazy internals stubbed, colourschemes real). The file runs twice, as
    lazy does, and the switch still happens once.
- Live on io, in a scratch copy of the owner's nvim config and lazy data:
  - `theme set gruvbox`, then the import, gave the link and the swap above;
  - in a UI nvim (private tmux), successive `theme set` calls switched
    `g:colors_name` with no new clone (51 plugin dirs before and after):
    tokyo-night → tokyonight-night, ethereal → aether, hackerman → hackerman,
    greek-noir-akane → aether (Function fg #88a57d), catppuccin-latte →
    catppuccin-latte (background light), everforest → everforest. After six
    reloads the `haseen-theme-hotreload` augroup held one autocmd;
  - every stock theme's colourscheme exists in the cached plugin's `colors/`.

## Not done

- lazy's "Config Change Detected" notice shows on each switch, as it does
  under Omarchy (`change_detection.notify` is the user's lazy.lua setting).
- `install.sh --uninstall-tree` leaves these links, like the gtk.css import
  and the btop link. The two `haseen-*.lua` links then dangle. nvim still
  starts, but lazy prints `Failed to load plugins.<name>` until they are
  removed (checked with a dangling link in the scratch copy).
