# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Neovim follows haseen themes (plan 058): `haseen theme set` links a LazyVim
# config's lua/plugins/theme.lua to the rendered neovim.lua (repointing
# Omarchy's link, never touching a file of the user's) with haseen's
# hot-reload and theme list beside it; `haseen import omarchy` swaps Omarchy's
# twins; every theme's spec names a plugin the list installs; and the
# hot-reload switches a running nvim's colourscheme on LazyReload.

NVIM_SRC="$(readlink -f "$HASEEN_PATH/default/nvim")"
OMARCHY_LINK=../../../../.local/state/omarchy/current/theme/neovim.lua

# nvim_sandbox NAME — sandbox holding a LazyVim config, no theme set yet.
nvim_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run" HASEEN_SYSROOT="$SANDBOX/root"
    mkdir -p "$HASEEN_SYSROOT"
    NV="$XDG_CONFIG_HOME/nvim"
    P="$NV/lua/plugins"
    CUR="$XDG_STATE_HOME/haseen/current/theme"
    mkdir -p "$NV/lua/config" "$P"
    printf 'require("lazy").setup({ spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" }, { import = "plugins" } } })\n' \
        >"$NV/lua/config/lazy.lua"
}

# omarchy_nvim — what omarchy-nvim seeds: the relative theme link and its two
# plugin files.
omarchy_nvim() {
    ln -sfn "$OMARCHY_LINK" "$P/theme.lua"
    printf 'return { { name = "theme-hotreload" } }\n' >"$P/omarchy-theme-hotreload.lua"
    printf -- '-- Omarchy 4 generates most theme specs\nreturn {}\n' >"$P/all-themes.lua"
}

link_of() { readlink "$1" 2>/dev/null || echo "(no link)"; }
nvim_tree() { (cd "$NV" && find . -printf '%p %l\n' | LC_ALL=C sort) | sha256sum; }

# --- theme set links a fresh LazyVim config ------------------------------------
nvim_sandbox nvim-fresh
capture haseen theme set gruvbox
assert_status "set gruvbox" 0 "$STATUS"
assert_dry_pure "theme set with nvim" "$OUTPUT"
assert_eq "theme.lua links to haseen's neovim.lua" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
assert_eq "hot-reload linked" "$NVIM_SRC/haseen-theme-hotreload.lua" "$(link_of "$P/haseen-theme-hotreload.lua")"
assert_eq "theme list linked" "$NVIM_SRC/haseen-all-themes.lua" "$(link_of "$P/haseen-all-themes.lua")"
assert_contains "the links are reported" "$OUTPUT" "nvim lua/plugins/theme.lua -> $CUR/neovim.lua"
assert_contains "theme.lua resolves to the rendered spec" "$(cat "$P/theme.lua")" "ellisonleao/gruvbox.nvim"
assert_eq "no temporary link left" "" "$(find "$P" -name '*.haseen-tmp')"
capture haseen theme set tokyo-night
assert_not_contains "a second set changes no link" "$OUTPUT" "nvim lua/plugins"
assert_contains "the link follows the new theme" "$(cat "$P/theme.lua")" "tokyonight-night"

# --- a config that is not LazyVim is left alone ---------------------------------
nvim_sandbox nvim-plain
rm -rf "$NV/lua/config"
printf 'vim.cmd.colorscheme("habamax")\n' >"$NV/init.lua"
capture haseen theme set gruvbox
assert_status "set without LazyVim" 0 "$STATUS"
assert_eq "nothing linked into a plain config" "" "$(find "$P" -mindepth 1)"

# --- lazyvim.json alone marks LazyVim -------------------------------------------
nvim_sandbox nvim-lazyvim-json
rm -rf "$NV/lua/config"
echo '{"extras":[]}' >"$NV/lazyvim.json"
capture haseen theme set gruvbox
assert_eq "lazyvim.json config gets the link" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"

# --- Omarchy's link is repointed, its plugin files kept until the import -------
nvim_sandbox nvim-omarchy
omarchy_nvim
hot_before="$(sha256sum <"$P/omarchy-theme-hotreload.lua")"
capture haseen theme set gruvbox
assert_status "set over Omarchy's nvim" 0 "$STATUS"
assert_eq "Omarchy's theme link repointed" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
assert_contains "the old target is named" "$OUTPUT" "$OMARCHY_LINK -> $CUR/neovim.lua"
assert_eq "Omarchy's hot-reload untouched" "$hot_before" "$(sha256sum <"$P/omarchy-theme-hotreload.lua")"
assert_eq "no second hot-reload while Omarchy's is there" "absent" \
    "$([[ -e $P/haseen-theme-hotreload.lua || -L $P/haseen-theme-hotreload.lua ]] && echo present || echo absent)"
assert_eq "no second theme list while Omarchy's is there" "absent" \
    "$([[ -L $P/haseen-all-themes.lua ]] && echo present || echo absent)"

# Omarchy 3's absolute spelling, and a haseen link from another install prefix.
nvim_sandbox nvim-omarchy3
ln -s "$HOME/.config/omarchy/current/theme/neovim.lua" "$P/theme.lua"
ln -s /usr/share/haseen/default/nvim/haseen-theme-hotreload.lua "$P/haseen-theme-hotreload.lua"
capture haseen theme set gruvbox
assert_eq "Omarchy 3 link repointed" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
assert_eq "haseen link from another prefix repointed" "$NVIM_SRC/haseen-theme-hotreload.lua" \
    "$(link_of "$P/haseen-theme-hotreload.lua")"

# --- the user's own theme.lua stays ----------------------------------------------
nvim_sandbox nvim-user-file
printf 'return { { "folke/tokyonight.nvim" } }\n' >"$P/theme.lua"
mine="$(sha256sum <"$P/theme.lua")"
capture haseen theme set gruvbox
assert_status "set with the user's theme.lua" 0 "$STATUS"
assert_eq "user's theme.lua still a regular file" "file" "$([[ -f $P/theme.lua && ! -L $P/theme.lua ]] && echo file || echo changed)"
assert_eq "user's theme.lua unchanged" "$mine" "$(sha256sum <"$P/theme.lua")"
assert_eq "hot-reload still linked" "$NVIM_SRC/haseen-theme-hotreload.lua" "$(link_of "$P/haseen-theme-hotreload.lua")"

nvim_sandbox nvim-user-link
printf 'return {}\n' >"$HOME/my-theme.lua"
ln -s "$HOME/my-theme.lua" "$P/theme.lua"
capture haseen theme set gruvbox
assert_eq "user's own link left" "$HOME/my-theme.lua" "$(link_of "$P/theme.lua")"

# --- dry run plans the links, writes nothing -------------------------------------
nvim_sandbox nvim-dry
omarchy_nvim
before="$(nvim_tree)"
capture haseen theme set gruvbox --dry-run
assert_status "dry-run set" 0 "$STATUS"
assert_dry_pure "dry-run set with nvim" "$OUTPUT"
assert_contains "dry run plans the theme link" "$OUTPUT" "DRYRUN: ln -sfn -- $CUR/neovim.lua $P/theme.lua.haseen-tmp"
assert_eq "dry run changes nothing in nvim" "$before" "$(nvim_tree)"

# --- haseen import omarchy swaps Omarchy's files ---------------------------------
# import_nvim_sandbox NAME — Omarchy's nvim seed plus the user's own plugin
# files, with a haseen theme already set (before the seed, so the link is
# still Omarchy's when the import runs).
import_nvim_sandbox() {
    nvim_sandbox "$1"
    mkdir -p "$XDG_CONFIG_HOME/omarchy"
    rm -rf "$NV/lua/config"
    HASEEN_THEME_HEADLESS=1 haseen theme set gruvbox >/dev/null 2>&1
    mkdir -p "$NV/lua/config"
    printf 'require("lazy").setup({ spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" } } })\n' >"$NV/lua/config/lazy.lua"
    omarchy_nvim
    printf 'return {}\n' >"$P/keymaps-personal.lua"
    printf 'return {}\n' >"$P/luasnip-snippets.lua"
}
import_nvim_sandbox nvim-import-dry
before="$(nvim_tree)"
capture "$REPO/bin/haseen-import-omarchy" --dry-run
assert_status "import dry run" 0 "$STATUS"
assert_dry_pure "import with nvim" "$OUTPUT"
assert_contains "dry run plans moving Omarchy's hot-reload aside" "$OUTPUT" "DRYRUN: mv -- $P/omarchy-theme-hotreload.lua $P/omarchy-theme-hotreload.lua.bak-"
assert_contains "dry run plans haseen's hot-reload" "$OUTPUT" "DRYRUN: ln -sfn -- $NVIM_SRC/haseen-theme-hotreload.lua"
assert_eq "import dry run changes nothing in nvim" "$before" "$(nvim_tree)"

import_nvim_sandbox nvim-import
capture "$REPO/bin/haseen-import-omarchy"
assert_status "import" 0 "$STATUS"
assert_eq "import repoints theme.lua" "$CUR/neovim.lua" "$(link_of "$P/theme.lua")"
assert_eq "Omarchy's hot-reload moved aside" "1 absent" \
    "$(find "$P" -name 'omarchy-theme-hotreload.lua.bak-*' | wc -l) $([[ -e $P/omarchy-theme-hotreload.lua ]] && echo present || echo absent)"
assert_eq "Omarchy's theme list moved aside" "1 absent" \
    "$(find "$P" -name 'all-themes.lua.bak-*' | wc -l) $([[ -e $P/all-themes.lua ]] && echo present || echo absent)"
assert_eq "the backup is Omarchy's file" 'return { { name = "theme-hotreload" } }' "$(cat "$P"/omarchy-theme-hotreload.lua.bak-*)"
assert_eq "haseen's hot-reload linked" "$NVIM_SRC/haseen-theme-hotreload.lua" "$(link_of "$P/haseen-theme-hotreload.lua")"
assert_eq "haseen's theme list linked" "$NVIM_SRC/haseen-all-themes.lua" "$(link_of "$P/haseen-all-themes.lua")"
assert_eq "the user's files stay" "return {}|return {}" "$(cat "$P/keymaps-personal.lua")|$(cat "$P/luasnip-snippets.lua")"
assert_contains "the import logs the move" "$OUTPUT" "nvim lua/plugins/omarchy-theme-hotreload.lua: Omarchy's, moved to omarchy-theme-hotreload.lua.bak-"
assert_contains "the import logs the repoint" "$OUTPUT" "nvim lua/plugins/theme.lua: $OMARCHY_LINK -> $CUR/neovim.lua"
before="$(nvim_tree)"
capture "$REPO/bin/haseen-import-omarchy" --merge
assert_status "import re-run" 0 "$STATUS"
assert_contains "re-run reports nothing to do" "$OUTPUT" "nvim: already on haseen's theme and hot-reload"
assert_eq "re-run changes nothing in nvim" "$before" "$(nvim_tree)"

# A theme list of the user's own (no Omarchy in it) stays beside haseen's.
import_nvim_sandbox nvim-import-own-list
printf 'return { { "my/colours.nvim", lazy = true } }\n' >"$P/all-themes.lua"
capture "$REPO/bin/haseen-import-omarchy"
assert_eq "user's all-themes.lua kept" 'return { { "my/colours.nvim", lazy = true } }' "$(cat "$P/all-themes.lua")"
assert_eq "haseen's list added beside it" "$NVIM_SRC/haseen-all-themes.lua" "$(link_of "$P/haseen-all-themes.lua")"

# Before any haseen theme: the Omarchy link would be swapped for a dangling one.
nvim_sandbox nvim-import-no-theme
mkdir -p "$XDG_CONFIG_HOME/omarchy"
omarchy_nvim
capture "$REPO/bin/haseen-import-omarchy"
assert_status "import without a haseen theme" 0 "$STATUS"
assert_contains "import says to set a theme first" "$OUTPUT" "nvim: no haseen theme yet"
assert_eq "Omarchy's link left without a theme" "$OMARCHY_LINK" "$(link_of "$P/theme.lua")"
assert_eq "Omarchy's hot-reload left without a theme" "present" \
    "$([[ -f $P/omarchy-theme-hotreload.lua ]] && echo present || echo absent)"

# --- every theme names a plugin haseen-all-themes.lua installs -------------------
# The template output stands for every theme without its own neovim.lua.
nvim_sandbox nvim-specs
HASEEN_THEME_HEADLESS=1 haseen theme set ethereal >/dev/null 2>&1
specs=("$HASEEN_PATH"/themes/*/neovim.lua "$CUR/neovim.lua")
if command -v nvim >/dev/null; then
    # Each spec through nvim's Lua: "file<TAB>name=repo ...<TAB>colorscheme"
    # (plugin entries and their table dependencies, keyed by lazy's name).
    cat >"$SANDBOX/specs.lua" <<'EOF'
local function add(out, s)
  if type(s) == "string" then s = { s } end
  if type(s) == "table" and type(s[1]) == "string" and s[1] ~= "LazyVim/LazyVim" then
    out[#out + 1] = (s.name or s[1]:match("[^/]+$")) .. "=" .. s[1] .. "@" .. (s.branch or "")
    for _, d in ipairs(s.dependencies or {}) do add(out, d) end
  end
end
for _, file in ipairs(arg) do
  local ok, spec = pcall(dofile, file)
  local plugins, cs = {}, "-"
  if ok and type(spec) == "table" then
    for _, s in ipairs(spec) do
      if s[1] == "LazyVim/LazyVim" then cs = s.opts and s.opts.colorscheme or "-" else add(plugins, s) end
    end
  else
    cs = "ERROR " .. tostring(spec)
  end
  print(file .. "\t" .. table.concat(plugins, " ") .. "\t" .. cs)
end
EOF
    list="$(nvim --clean --headless -l "$SANDBOX/specs.lua" "$NVIM_SRC/haseen-all-themes.lua" 2>&1 | cut -f2)"
    out="$(nvim --clean --headless -l "$SANDBOX/specs.lua" "${specs[@]}" 2>&1)"
    assert_eq "one line per spec" "${#specs[@]}" "$(grep -c . <<<"$out")"
    while IFS=$'\t' read -r file plugins cs; do
        label="${file#"$HASEEN_PATH/"}"
        [[ $file == "$CUR/neovim.lua" ]] && label="rendered neovim.lua.tpl"
        [[ $cs != -* && $cs != ERROR* ]] && _pass || _fail "$label sets a colorscheme" "$cs"
        [[ -n $plugins ]] && _pass || _fail "$label names a colourscheme plugin"
        for p in $plugins; do
            assert_contains "$label: $p is in haseen-all-themes.lua" " $list " " $p "
        done
    done <<<"$out"
else
    # No nvim: syntax only, and the plugin repos by text.
    if command -v luac >/dev/null; then
        capture luac -p "${specs[@]}" "$NVIM_SRC"/*.lua
        assert_status "theme specs and haseen's nvim files parse" 0 "$STATUS"
    fi
    for file in "${specs[@]}"; do
        repo="$(grep -oE '"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"' "$file" | grep -v '"LazyVim/LazyVim"' | head -1)"
        assert_contains "${file##*/themes/}: $repo is in haseen-all-themes.lua" "$(<"$NVIM_SRC/haseen-all-themes.lua")" "theme($repo"
    done
fi

# --- the hot-reload switches a running nvim ---------------------------------------
# Lazy's change detection fires User LazyReload after theme.lua changed; the
# lazy internals the hot-reload calls are stubbed, the colourschemes are real.
# lazy runs the file on every spec load, so it runs twice here: one switch
# (one loader call) means the autocmd did not pile up, and the spec is empty
# so it cannot merge into another local plugin.
if command -v nvim >/dev/null; then
    root="$SANDBOX/rtp"
    mkdir -p "$root/lua/plugins" "$root/colors"
    for c in haseen_a haseen_b; do
        printf 'vim.cmd("highlight clear")\nvim.g.colors_name = "%s"\n' "$c" >"$root/colors/$c.lua"
    done
    spec() { printf 'return { { "test/%s.nvim" }, { "LazyVim/LazyVim", opts = { colorscheme = "%s" } } }\n' "$1" "$1"; }
    spec haseen_a >"$root/lua/plugins/theme.lua"
    cat >"$SANDBOX/hotreload.lua" <<'EOF'
local root, plugin_file = arg[1], arg[2]
vim.opt.rtp:prepend(root)
local calls = {}
package.preload["lazy.core.config"] = function() return { plugins = {} } end
package.preload["lazy.core.util"] = function() return { walkmods = function() end } end
package.preload["lazy.core.loader"] = function()
  return { colorscheme = function(n) calls[#calls + 1] = n end, reload = function() end }
end
vim.cmd.colorscheme("haseen_a")
local spec = dofile(plugin_file)
dofile(plugin_file)
local f = assert(io.open(root .. "/lua/plugins/theme.lua", "w"))
f:write('return { { "test/haseen_b.nvim" }, { "LazyVim/LazyVim", opts = { colorscheme = "haseen_b" } } }\n')
f:close()
vim.api.nvim_exec_autocmds("User", { pattern = "LazyReload" })
vim.wait(2000, function() return vim.g.colors_name == "haseen_b" end, 10)
print(vim.g.colors_name .. " " .. table.concat(calls, ",") .. " spec=" .. #spec)
EOF
    capture nvim --clean --headless -l "$SANDBOX/hotreload.lua" "$root" "$NVIM_SRC/haseen-theme-hotreload.lua"
    assert_eq "LazyReload applies the new colourscheme, once" "haseen_b haseen_b spec=0" "$OUTPUT"
fi
