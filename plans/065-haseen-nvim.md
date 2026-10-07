# Plan 065: haseen.nvim, the owner's Neovim config as haseen's

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (an existing `~/.config/nvim` is touched only with `--replace`, after it is moved to a backup; a failed fetch changes nothing)
- **Depends on**: 058
- **Category**: editor, seeds
- **Planned at**: 2026-10-07, owner request: his config <https://github.com/t1nk333r/nvim> becomes haseen's own, "haseen.nvim"
- **State**: DONE 2026-10-07 (tests, plus a scratch HOME with the real repo, real lazy.nvim and live theme switches; replacing io's config is the owner's call)

## Problem

haseen had no Neovim config of its own. Plan 058 made a LazyVim config
follow `haseen theme set`, and io runs Omarchy's LazyVim. The owner wants his
own config to be haseen's: seeded on a fresh install when `~/.config/nvim`
is absent, offered to existing users through a command, and following
haseen's themes like the LazyVim config does.

## The owner's repository (read at `e6ef714`, 2025-12-23)

- **Licence:** none. The repo has no LICENSE file, and the GitHub API reports
  `"license": null`.
- **Not LazyVim.** It is a plain lazy.nvim config:
  - `init.lua` requires `core`, which loads `options`, `keymap` (leader `,`)
    and `autocommands`.
  - `core/lazy.lua` bootstraps lazy.nvim (stable) and imports `lua/plugins`
    with `defaults.lazy = true` and the update checker on.
- **31 plugin specs:**
  - UI: alpha (dashboard), bufferline, lualine, which-key, neo-tree (in
    `nvim-tree.lua`), indent-blankline, colorizer, devicons, toggleterm, and
    snacks with every module off.
  - Editing: Comment, autopairs, surround, nvim-cmp with LuaSnip and
    friendly-snippets, treesitter.
  - LSP and formatting: lspconfig through the 0.11 `vim.lsp.config` API
    (12 servers), mason (18 tools ensured), none-ls with extras, conform
    (format on save), nvim-lint, schemastore, navic, trouble.
  - Git: gitsigns, lazygit.
  - Markdown: render-markdown.
  - Colours: `colourscheme.lua` loads everforest at startup and makes the
    window separators transparent.
- **Personal parts:**
  - Two `BufWritePost` autocommands, each defined twice: `aliasesrc.fish`
    re-sources the fish config, and `bm-files`/`bm-dirs` run `shortcuts.sh`.
  - Command-line mappings `Q`→`q`, `WQ`→`wq` and `w!`→`w !sudo tee %`. They
    are `cmap`s, not abbreviations.
  - `snippets/lua/snippets.lua`, which nothing loads (it also uses an
    undefined `Utils`).
  - The mason tool list (bicep, Go, fish).
- **No Omarchy branding:** `grep -ri omarchy` finds nothing.
- **Seen in the scratch run** (current plugin heads, nvim 0.12.5):
  - nvim-treesitter's default branch has no `nvim-treesitter.configs`, so
    opening a file reports `Failed to run config for nvim-treesitter`.
  - none-ls reports `luacheck`/`selene` missing until mason has installed
    them.
  - [INFERENCE] trouble.nvim v3 has no `TroubleToggle`, which the trouble
    keys call.

  These are fixes for the repository itself, not for haseen.

## io's current config (read-only)

`~/.config/nvim` is Omarchy's LazyVim starter (`lazyvim.json` with the
neo-tree extra, LazyVim's Apache-2.0 LICENSE). It holds:

- Omarchy's `disable-news-alert.lua`, `snacks-animated-scrolling-off.lua` and
  `example.lua`;
- the owner's own `keymaps-personal.lua` and `luasnip-snippets.lua`;
- haseen's `theme.lua`, `haseen-theme-hotreload.lua` and
  `haseen-all-themes.lua` links (plan 058);
- Omarchy's two files as `.bak-20261007-085038`.

haseen.nvim replaces it only if the owner runs `haseen setup nvim --replace`.

## Decision

- **Fetched at a pinned commit, not vendored.**
  - Without a licence, haseen (MIT) cannot carry the files. A clone on the
    user's machine ships none of them.
  - The owner's repo stays the one source for his machines and for haseen,
    and a new pin picks up his changes.
  - `bin/haseen-setup-nvim` holds the source in two variables: `NVIM_REPO_URL`
    (`https://github.com/t1nk333r/nvim`) and `NVIM_COMMIT` (`e6ef714`, full
    hash in the script).
  - The repo is expected to be renamed `t1nk333r/haseen.nvim`. GitHub
    redirects the old URL, and the rename is a one-line change.
  - An MIT LICENSE in that repo would allow vendoring later, under
    `share/haseen/default/nvim/haseen.nvim/` with a NOTICE.md row.
- **`haseen setup nvim [--replace | --if-absent] [--dry-run] [--yes]`:**
  - It clones into a stage beside `~/.config/nvim`
    (`~/.config/.nvim-haseen.XXXXXX`) and resets the default branch to the
    pin. The branch keeps its upstream, so `git pull` follows the owner past
    the pin.
  - It links the bridge, runs `theme_link_nvim` on the stage, and lists the
    four links in `.git/info/exclude`, so the checkout stays clean.
  - Only then is the stage moved into place. A clone or pin failure leaves
    `~/.config/nvim` as it was, and the stage is removed.
  - An existing config is refused without `--replace`. With it, the command
    asks, then moves the config to `~/.config/nvim.bak-<timestamp>`. Plugins
    and data under `~/.local/share/nvim` stay, so restoring the backup is a
    `mv`.
  - `--if-absent` exits 0 without touching an existing config.
  - With `--dry-run` it prints the plan and runs no git.
- **First install:** in `install.sh`, the fresh-home branch (no migration
  ledger, `shell.json` or theme name before the layers ran; plan 066 owns
  that test) calls `haseen setup nvim --if-absent` after the layers, so a
  theme is already rendered. A failure is a warning. Later runs and layer
  re-applies never seed, so deleting `~/.config/nvim` is respected.
- **Theme bridge** `share/haseen/default/nvim/haseen-colorscheme.lua`
  (haseen's own code, linked):
  - haseen's theme specs carry the colourscheme on a `LazyVim/LazyVim`
    entry. The bridge returns `{ "LazyVim/LazyVim", enabled = false }`, so
    lazy never clones LazyVim.
  - On `User LazyDone` it applies `opts.colorscheme` from `plugins.theme`.
    The autocmd is `nested`: without it, `:colorscheme` inside the callback
    fires no `ColorSchemePre`, so lazy never loads the theme's plugin. That
    was the first scratch run's `E185`.
  - The hot-reload of plan 058 handles later switches unchanged.
- **`theme-lib.sh`:**
  - `theme_nvim_follows` = LazyVim, or `theme_nvim_haseen` (the bridge is in
    `lua/plugins`, as a file or as a link, dangling or not).
  - `theme_link_nvim` and `haseen import omarchy` use it.
  - The bridge link is repointed when it comes from another prefix, like the
    other two. A copy of the user's own stays.
- **Not changed:** the owner's files. His personal autocommands and
  mappings, the everforest spec (haseen's theme list makes it lazy, so the
  haseen theme wins), and the issues above stay his to change upstream.

Rejected:

- **Vendoring:** there is no licence (see above).
- **Seeding from the desktop layer:** a layer re-apply would clone again
  after the user deleted the config. A fresh install is the moment the
  owner asked for.
- **Patching the fetched files** (dropping `colourscheme.lua`, the fish
  autocommand): the patches would have to be redone at every pin and would
  diverge from the owner's repo. The bridge and the links do haseen's part
  from outside.
- **Moving `~/.local/share/nvim` aside as well:** the plugins are shared by
  name, and keeping them makes the backup restorable offline.

## Verification

- `tests/run.sh tests/test-haseen-nvim.sh` (59 checks; 64 with
  `HASEEN_NVIM_TEST_REPO`), against a two-commit local fixture repo shaped
  like the owner's:
  - Dry run: the clone, the pin, the bridge link and the move are planned,
    and nothing is written (git stays a stub).
  - Empty HOME after `theme set gruvbox`:
    - the pin is checked out, not the later commit;
    - the bridge, `theme.lua`, the hot-reload and the theme list are linked;
    - `git status` is clean, the upstream is `origin/main`, and no stage is
      left;
    - a later `theme set` changes no link.
  - Headless nvim with a stub lazy.nvim (imports `lua/plugins` sorted, loads
    the theme's colours from `ColorSchemePre`, fires `LazyDone`): every spec
    is imported, `g:colors_name` is the theme's, LazyVim is disabled, and
    there is no error. With `nested` removed this check fails with `E185`.
  - Existing config:
    - without flags: refused (exit 1);
    - `--if-absent`: exit 0, untouched;
    - `--replace --if-absent`: usage (exit 2);
    - declining the prompt: exit 1, nothing cloned;
    - `--replace --dry-run`: the backup is planned;
    - `--replace --yes`: one `nvim.bak-*` holding the old config, and
      haseen.nvim in place.
  - Seeded before any theme: `theme set` links `theme.lua`. A dangling
    bridge from `/old/prefix` is repointed, and a copied bridge is kept.
  - A missing repo or an unknown pin: exit 1, the old config is kept, there
    is no backup and no stage.
  - `HASEEN_NVIM_TEST_REPO=<checkout>`: the owner's real config at the
    shipped pin seeds and loads headless with the theme applied and no error.
- Scratch HOME (`~/.cache/haseen-wt/HaseenNvim/e2e`), real network, real
  lazy.nvim, nvim 0.12.5:
  - `haseen setup nvim` cloned GitHub at `e6ef714` and made the four links.
  - `nvim --headless "+Lazy! install"` installed 58 plugins, none of them
    LazyVim.
  - The next start had `colors_name=gruvbox`, LazyVim in `spec.disabled`,
    and everforest not loaded.
  - In a UI nvim (private tmux), rewriting `current/theme/neovim.lua`
    switched tokyonight-night → everforest → catppuccin-latte (background
    light). The `haseen-theme-hotreload` augroup held 1 autocmd throughout.

## Not done

- io keeps its Omarchy LazyVim config. Running
  `haseen setup nvim --replace` there is the owner's decision.
- No menu entry: the command is the offer (owner rule: optional features
  off by default, offered from the menu or a command).
- After `:Lazy clean` in haseen.nvim, LazyVim's plugins are gone from
  `~/.local/share/nvim`. A restored backup then reinstalls them on its first
  start (network).
