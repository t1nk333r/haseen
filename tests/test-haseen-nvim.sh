# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.nvim (plan 065): `haseen setup nvim` clones a lazy.nvim config at a
# pinned commit into an empty ~/.config/nvim with haseen's colourscheme bridge
# and theme links; it refuses an existing config without --replace, backs it
# up with it, leaves it alone with --if-absent and on a failed fetch; and
# `haseen theme set` treats the bridge as the mark of a config to link. The
# repository is a local fixture shaped like the owner's (init.lua -> core ->
# lazy.lua importing lua/plugins); nvim loads the seeded config headless with
# a stub lazy.nvim, so nothing reaches the network.
#
# HASEEN_NVIM_TEST_REPO=<a checkout of the owner's repo> also seeds the real
# config at the shipped pin and loads it the same way.

NVIM_SRC="$(readlink -f "$HASEEN_PATH/default/nvim")"
REAL_GIT="$(PATH=/usr/local/bin:/usr/bin:/bin type -P git)"

# --- fixture: a two-commit repository; the first commit is the pin -----------
FIX="$OUT/haseen-nvim-fixture"
rm -rf "$FIX"
mkdir -p "$FIX/src"
fgit() { "$REAL_GIT" -C "$FIX/src" -c user.name=fixture -c user.email=fixture@example.invalid "$@"; }
fput() { # PATH CONTENT
    mkdir -p "$(dirname "$FIX/src/$1")"
    printf '%s\n' "$2" >"$FIX/src/$1"
}
fgit init -q -b main
fput init.lua 'require("core")'
fput lua/core/init.lua 'vim.g.mapleader = ","
require("core.lazy")'
fput lua/core/lazy.lua 'local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({ spec = { { import = "plugins" } }, defaults = { lazy = true } })'
fput lua/plugins/colourscheme.lua 'return { "neanias/everforest-nvim", lazy = false, priority = 1000 }'
fput .gitignore 'lazy-lock.json'
fgit add -A
fgit commit -q -m pinned
PIN="$(fgit rev-parse HEAD)"
fput lua/plugins/after-pin.lua 'return {}'
fgit add -A
fgit commit -q -m later
URL="$FIX/src"

# nvim_sandbox NAME — empty home; git is real, the repo and pin the fixture's.
nvim_sandbox() {
    sandbox "$1"
    stub git "exec '$REAL_GIT' \"\$@\""
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS NVIM_APPNAME
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run" HASEEN_SYSROOT="$SANDBOX/root"
    export HASEEN_NVIM_REPO="$URL" HASEEN_NVIM_COMMIT="$PIN"
    mkdir -p "$HASEEN_SYSROOT"
    NV="$XDG_CONFIG_HOME/nvim"
    P="$NV/lua/plugins"
    CUR="$XDG_STATE_HOME/haseen/current/theme"
}

link_of() { readlink "$1" 2>/dev/null || echo "(no link)"; }
leftovers() { find "$XDG_CONFIG_HOME" -maxdepth 1 -name '.nvim-haseen.*' 2>/dev/null; }

# --- dry run: the plan, nothing written ----------------------------------------
nvim_sandbox hnvim-dry
capture haseen setup nvim --dry-run
assert_status "dry run: exit" 0 "$STATUS"
assert_dry_pure "setup nvim" "$OUTPUT"
assert_contains "dry run: clone planned" "$OUTPUT" "DRYRUN: git clone --quiet --no-checkout -- $URL"
assert_contains "dry run: pin planned" "$OUTPUT" "reset --quiet --hard $PIN"
assert_contains "dry run: bridge planned" "$OUTPUT" "DRYRUN: ln -s -- $NVIM_SRC/haseen-colorscheme.lua"
assert_contains "dry run: placed last" "$OUTPUT" "DRYRUN: mv -T -- $XDG_CONFIG_HOME/.nvim-haseen.XXXXXX $NV"
assert_eq "dry run: no config written" "no" "$([[ -e $NV ]] && echo yes || echo no)"
assert_eq "dry run: no stage left" "" "$(leftovers)"

# --- an empty home with a theme: the pinned config, the bridge and the links ----
nvim_sandbox hnvim-fresh
capture haseen theme set gruvbox
assert_status "theme set before nvim" 0 "$STATUS"
capture haseen setup nvim
assert_status "setup: exit" 0 "$STATUS"
assert_eq "setup: the pinned commit is checked out" "$PIN" "$("$REAL_GIT" -C "$NV" rev-parse HEAD)"
assert_eq "setup: init.lua is the repo's" 'require("core")' "$(<"$NV/init.lua")"
assert_eq "setup: nothing after the pin" "no" "$([[ -e $NV/lua/plugins/after-pin.lua ]] && echo yes || echo no)"
assert_eq "setup: the bridge is linked" "$NVIM_SRC/haseen-colorscheme.lua" "$(link_of "$P/haseen-colorscheme.lua")"
assert_eq "setup: theme.lua links to the rendered theme" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
assert_eq "setup: hot-reload linked" "$NVIM_SRC/haseen-theme-hotreload.lua" "$(link_of "$P/haseen-theme-hotreload.lua")"
assert_eq "setup: theme list linked" "$NVIM_SRC/haseen-all-themes.lua" "$(link_of "$P/haseen-all-themes.lua")"
assert_contains "setup: the links are reported" "$OUTPUT" "nvim lua/plugins/theme.lua -> $CUR/neovim.lua"
assert_eq "setup: haseen's links do not dirty the checkout" "" "$("$REAL_GIT" -C "$NV" status --porcelain)"
assert_eq "setup: the branch keeps its upstream" "origin/main" "$("$REAL_GIT" -C "$NV" rev-parse --abbrev-ref '@{upstream}')"
assert_eq "setup: no stage left" "" "$(leftovers)"
capture haseen theme set tokyo-night
assert_not_contains "theme set: haseen.nvim's links already right" "$OUTPUT" "nvim lua/plugins"
assert_contains "theme set: theme.lua follows" "$(cat "$P/theme.lua")" "tokyonight-night"

# nvim_load NAME — start nvim on the sandbox's config, headless, with a stub
# lazy.nvim that imports lua/plugins the way lazy does (sorted, module by
# module), loads a fake theme plugin from ColorSchemePre the way lazy loads a
# lazy colourscheme plugin (off the runtimepath until then), and fires User
# LazyDone. Prints the imported modules, g:colors_name, whether a spec
# disabled LazyVim, and the last error.
nvim_load() {
    local lazy="$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy" theme="$XDG_DATA_HOME/nvim/lazy/fake-theme" c
    mkdir -p "$lazy" "$theme/colors"
    for c in "$@"; do
        printf 'vim.cmd("highlight clear")\nvim.g.colors_name = "%s"\n' "$c" >"$theme/colors/$c.lua"
    done
    cat >"$lazy/init.lua" <<'EOF'
local M = { specs = {} }
function M.setup(opts)
  local theme = vim.fn.stdpath("data") .. "/lazy/fake-theme"
  vim.api.nvim_create_autocmd("ColorSchemePre", {
    callback = function()
      vim.opt.rtp:append(theme)
    end,
  })
  for _, s in ipairs(opts.spec or {}) do
    if s.import then
      local dir = vim.fn.stdpath("config") .. "/lua/" .. s.import:gsub("%.", "/")
      local names = {}
      for name in vim.fs.dir(dir) do
        if name:match("%.lua$") then
          names[#names + 1] = name:sub(1, -5)
        end
      end
      table.sort(names)
      for _, n in ipairs(names) do
        local spec = dofile(dir .. "/" .. n .. ".lua")
        M.specs[#M.specs + 1] = { mod = n, spec = type(spec[1]) == "table" and spec or { spec } }
      end
    end
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyDone", modeline = false })
end
return M
EOF
    cat >"$SANDBOX/report.lua" <<'EOF'
local mods, disabled = {}, false
for _, e in ipairs(require("lazy").specs) do
  mods[#mods + 1] = e.mod
  for _, s in ipairs(e.spec) do
    if s[1] == "LazyVim/LazyVim" and s.enabled == false then
      disabled = true
    end
  end
end
io.stdout:write(table.concat(mods, ",") .. " colors=" .. tostring(vim.g.colors_name)
  .. " lazyvim_disabled=" .. tostring(disabled) .. " err=" .. vim.v.errmsg .. "\n")
EOF
    capture nvim --headless -i NONE -c "luafile $SANDBOX/report.lua" -c 'qa!'
}

if command -v nvim >/dev/null; then
    nvim_load tokyonight-night
    assert_status "nvim: loads the seeded config" 0 "$STATUS"
    assert_eq "nvim: specs imported, the theme applied, LazyVim disabled" \
        "colourscheme,haseen-all-themes,haseen-colorscheme,haseen-theme-hotreload,theme colors=tokyonight-night lazyvim_disabled=true err=" \
        "$OUTPUT"
fi

# --- an existing config: refused, kept with --if-absent, backed up with --replace
nvim_sandbox hnvim-existing
mkdir -p "$NV"
printf '%s\n' '-- mine' >"$NV/init.lua"
capture haseen setup nvim
assert_status "existing: refused without --replace" 1 "$STATUS"
assert_contains "existing: says how" "$OUTPUT" "--replace"
assert_eq "existing: untouched" "-- mine" "$(<"$NV/init.lua")"
capture haseen setup nvim --if-absent
assert_status "existing: --if-absent is no error" 0 "$STATUS"
assert_contains "existing: --if-absent leaves it" "$OUTPUT" "left as is"
assert_eq "existing: still untouched" "-- mine" "$(<"$NV/init.lua")"
capture haseen setup nvim --replace --if-absent
assert_status "existing: --replace and --if-absent conflict" 2 "$STATUS"
capture bash -c 'echo n | haseen setup nvim --replace'
assert_status "existing: declining stops" 1 "$STATUS"
assert_eq "existing: declined, untouched" "-- mine" "$(<"$NV/init.lua")"
assert_eq "existing: declined, nothing cloned" "" "$(leftovers)"
capture haseen setup nvim --replace --dry-run
assert_dry_pure "setup nvim --replace" "$OUTPUT"
assert_contains "existing: dry run plans the backup" "$OUTPUT" "DRYRUN: mv -T -- $NV $NV.bak-"
assert_eq "existing: dry run untouched" "-- mine" "$(<"$NV/init.lua")"
capture haseen setup nvim --replace --yes
assert_status "replace: exit" 0 "$STATUS"
mapfile -t bak < <(find "$XDG_CONFIG_HOME" -maxdepth 1 -name 'nvim.bak-*')
assert_eq "replace: one backup" 1 "${#bak[@]}"
assert_eq "replace: the backup is the old config" "-- mine" "$(cat "${bak[0]:-none}/init.lua" 2>/dev/null)"
assert_contains "replace: the backup is reported" "$OUTPUT" "your previous config is in ${bak[0]:-none}"
assert_eq "replace: haseen.nvim in place" 'require("core")' "$(<"$NV/init.lua")"
assert_eq "replace: bridge linked" "$NVIM_SRC/haseen-colorscheme.lua" "$(link_of "$P/haseen-colorscheme.lua")"
assert_contains "replace: no theme yet is said" "$OUTPUT" "no haseen theme yet"
assert_eq "replace: no theme yet, no theme.lua" "(no link)" "$(link_of "$P/theme.lua")"

# --- the bridge makes theme set link a config seeded before any theme ----------
capture haseen theme set gruvbox
assert_eq "later theme set: theme.lua linked" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
# The tree moved (/usr/local -> /usr): the dangling bridge is repointed.
ln -sfn /old/prefix/share/haseen/default/nvim/haseen-colorscheme.lua "$P/haseen-colorscheme.lua"
capture haseen theme set tokyo-night
assert_eq "moved tree: bridge repointed" "$NVIM_SRC/haseen-colorscheme.lua" "$(link_of "$P/haseen-colorscheme.lua")"
# A bridge of the user's own (a copy) stays.
rm "$P/haseen-colorscheme.lua"
cp "$NVIM_SRC/haseen-colorscheme.lua" "$P/haseen-colorscheme.lua"
capture haseen theme set gruvbox
assert_eq "own bridge copy: kept" "(no link)" "$(link_of "$P/haseen-colorscheme.lua")"
assert_contains "own bridge copy: still follows themes" "$(cat "$P/theme.lua")" "gruvbox"

# --- a failed fetch leaves the old config ---------------------------------------
nvim_sandbox hnvim-fail
mkdir -p "$NV"
printf '%s\n' '-- mine' >"$NV/init.lua"
capture env HASEEN_NVIM_REPO="$FIX/missing" haseen setup nvim --replace --yes
assert_status "bad repo: fails" 1 "$STATUS"
assert_contains "bad repo: says so" "$OUTPUT" "cannot clone $FIX/missing"
assert_eq "bad repo: old config kept" "-- mine" "$(<"$NV/init.lua")"
assert_eq "bad repo: no backup" "" "$(find "$XDG_CONFIG_HOME" -maxdepth 1 -name 'nvim.bak-*')"
assert_eq "bad repo: no stage left" "" "$(leftovers)"
capture env HASEEN_NVIM_COMMIT=0123456789abcdef0123456789abcdef01234567 haseen setup nvim --replace --yes
assert_status "unknown pin: fails" 1 "$STATUS"
assert_contains "unknown pin: says so" "$OUTPUT" "is not in $URL"
assert_eq "unknown pin: old config kept" "-- mine" "$(<"$NV/init.lua")"
assert_eq "unknown pin: no stage left" "" "$(leftovers)"

# --- opt-in: the owner's real config at the shipped pin ---------------------------
if [[ -n ${HASEEN_NVIM_TEST_REPO:-} ]] && command -v nvim >/dev/null; then
    nvim_sandbox hnvim-real
    unset HASEEN_NVIM_COMMIT
    export HASEEN_NVIM_REPO="$HASEEN_NVIM_TEST_REPO"
    capture haseen theme set gruvbox
    capture haseen setup nvim
    assert_status "real: setup" 0 "$STATUS"
    assert_eq "real: no stage left" "" "$(leftovers)"
    nvim_load gruvbox
    assert_status "real: nvim loads it" 0 "$STATUS"
    assert_contains "real: theme applied, LazyVim disabled, no error" "$OUTPUT" "colors=gruvbox lazyvim_disabled=true err="
    assert_eq "real: no error" "" "${OUTPUT##*err=}"
fi
