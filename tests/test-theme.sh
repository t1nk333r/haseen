# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Theme pipeline: every stock theme renders completely, shell.json carries the
# architecture §7 tokens, helpers match Omarchy's output, user templates win,
# installed themes go through the denylist, hooks run, dry runs write nothing.

THEME_OUTPUTS=(hyprland.lua foot.ini kitty.conf ghostty.conf alacritty.toml btop.theme neovim.lua gtk.css fonts.conf yazi.toml satty.css shell.json colors.toml)
SHELL_KEYS="mode background surface surfaceAlt foreground muted accent accentFg urgent warning success border selection fontFamily fontMono fontSize radius gap borderWidth"
SHELL_COLOUR_KEYS="background surface surfaceAlt foreground muted accent accentFg urgent warning success border selection"

# theme_sandbox NAME — sandbox plus fakes for the probes theme set uses to find
# running apps, so no test ever signals or retints the developer's session.
theme_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    stub pkill 'echo "STUB-CALLED: pkill $*" >&2; exit 97'
    stub gsettings 'echo "STUB-CALLED: gsettings $*" >&2; exit 97'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS HASEEN_THEME_HEADLESS
    # No detached image fetch racing the tree comparisons (test-themes2.sh
    # covers it), and a runtime dir without the developer's running units.
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run"
    CUR="$HOME/.local/state/haseen/current"
}

# tree — every path under HOME (dry-run purity = this does not change).
tree() { (cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort); }

# make_repo DIR — commit DIR as a git repository with the real git.
make_repo() {
    /usr/bin/git -C "$1" init -q
    /usr/bin/git -C "$1" add -A
    /usr/bin/git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -qm theme
}

colour_of() { sed -n "s/^$2 *= *\"\(#[0-9a-fA-F]*\)\".*/\1/p" "$1"; }

# staged_rounding — the radius `haseen theme set` wrote to current/theme/rounding.lua.
staged_rounding() { sed -n 's/.*rounding = \([0-9]*\).*/\1/p' "$CUR/theme/rounding.lua"; }

# window_rounding — the decoration.rounding Hyprland ends up with after the
# whole load order the seeded ~/.config/hypr/hyprland.lua runs (defaults, the
# shared radius, toggles, hyprmod, the current theme, the user's files), under
# Lua with a recording `hl`. A file that fails to load prints FAILED instead.
window_rounding() {
    HYPR_USER="$HASEEN_PATH/default/hypr/user/hyprland.lua" lua - <<'LUA'
local rounding, failed = "unset", nil
local function proxy()
  return setmetatable({}, { __index = function() return proxy() end, __call = function() return proxy() end })
end
hl = setmetatable({
  config = function(t)
    if type(t) == "table" and type(t.decoration) == "table" and t.decoration.rounding ~= nil then
      rounding = t.decoration.rounding
    end
  end,
}, { __index = function() return proxy() end })
print = function(...)
  local line = table.concat({ ... }, " ")
  if line:find("failed to load", 1, true) then failed = line end
end
dofile(os.getenv("HYPR_USER"))
io.write(failed and ("FAILED " .. failed) or tostring(rounding), "\n")
LUA
}

# --- every stock theme renders every output --------------------------------
for dir in "$HASEEN_PATH"/themes/*/; do
    t="$(basename "$dir")"
    theme_sandbox "theme-render-$t"
    capture haseen theme set "$t"
    assert_status "set $t" 0 "$STATUS"
    assert_dry_pure "set $t touches nothing privileged" "$OUTPUT"
    assert_eq "theme.name $t" "$t" "$(cat "$CUR/theme.name" 2>/dev/null)"
    for f in "${THEME_OUTPUTS[@]}"; do
        if [[ -s $CUR/theme/$f ]]; then
            assert_not_contains "$t $f fully rendered" "$(<"$CUR/theme/$f")" "{{"
        else
            _fail "$t renders $f" "missing or empty: $CUR/theme/$f"
        fi
    done
    sj="$CUR/theme/shell.json"
    if jq -e . "$sj" >/dev/null 2>&1; then
        assert_eq "$t shell.json has exactly the §7 keys" "$(tr ' ' '\n' <<<"$SHELL_KEYS" | sort)" "$(jq -r 'keys[]' "$sj" | sort)"
        bad="$(jq -r --arg k "$SHELL_COLOUR_KEYS" '($k | split(" ")) as $ks | to_entries[] | select(.key as $x | $ks | index($x)) | select(.value | test("^#[0-9a-fA-F]{6}$") | not) | .key' "$sj")"
        assert_eq "$t shell.json colours are #rrggbb" "" "$bad"
        assert_eq "$t shell.json numbers" "number number number number" "$(jq -r '[.fontSize, .radius, .gap, .borderWidth] | map(type) | join(" ")' "$sj")"
        assert_eq "$t mode follows colors.toml" "$(sed -n 's/^mode *= *"\(.*\)"/\1/p' "$dir/colors.toml")" "$(jq -r .mode "$sj")"
        # One radius for the frame, the menu and the windows (plans 046, 068):
        # twice the theme's radius with no frame.radius set, and the rendered
        # hyprland.lua leaves Hyprland at it, the theme's own rounding or not.
        # The menu reads it from Config.frameRadius (tests/test-menu-radius.sh).
        want_round="$(($(jq -r .radius "$sj") * 2))"
        assert_eq "$t rounding.lua is the frame radius" "$want_round" "$(staged_rounding)"
        if command -v lua >/dev/null; then
            assert_eq "$t windows round like the frame" "$want_round" "$(window_rounding)"
        fi
        assert_eq "$t accent from colors.toml" "$(colour_of "$dir/colors.toml" accent)" "$(jq -r .accent "$sj")"
    else
        _fail "$t shell.json is valid JSON" "$(cat "$sj" 2>/dev/null)"
    fi
    bg="$(colour_of "$dir/colors.toml" background)"
    assert_contains "$t foot background" "$(<"$CUR/theme/foot.ini")" "background=${bg#\#}"
    # libadwaita and GTK 3 named colours come from the theme's own colours.
    gtk="$(<"$CUR/theme/gtk.css")"
    assert_contains "$t libadwaita window background" "$gtk" "@define-color window_bg_color $bg;"
    assert_contains "$t libadwaita window foreground" "$gtk" "@define-color window_fg_color $(colour_of "$dir/colors.toml" foreground);"
    assert_contains "$t libadwaita accent" "$gtk" "@define-color accent_bg_color $(colour_of "$dir/colors.toml" accent);"
    assert_contains "$t GTK 3 base colour" "$gtk" "@define-color theme_base_color $bg;"
    if command -v luac >/dev/null; then
        capture luac -p "$CUR/theme/hyprland.lua" "$CUR/theme/neovim.lua"
        assert_status "$t Lua outputs parse" 0 "$STATUS"
    fi
    if [[ -f $dir/neovim.lua ]]; then
        assert_eq "$t theme-shipped neovim.lua wins over the template" "$(<"$dir/neovim.lua")" "$(<"$CUR/theme/neovim.lua")"
    fi
    assert_eq "$t no staging leftovers" "" "$(ls -d "$CUR/next-theme" "$CUR/old-theme" 2>/dev/null)"
done

# --- frame.radius sets the shared window radius (plan 046) -------------------
# Config.qml's rule: shell.json frame.radius, the user's file over the shipped
# one, when it is a number from 0 to 64 (rounded); else twice the radius token.
theme_sandbox theme-frame-radius
frame_case() { # NAME SHELL.JSON WANT — set haseen under that user shell.json
    printf '%s\n' "$2" >"$HOME/.config/haseen/shell.json"
    capture haseen theme set haseen
    assert_status "$1: the theme still sets" 0 "$STATUS"
    assert_eq "$1: rounding.lua" "$3" "$(staged_rounding)"
    if command -v lua >/dev/null; then
        assert_eq "$1: the windows" "$3" "$(window_rounding)"
    fi
}
mkdir -p "$HOME/.config/haseen"
frame_case "frame.radius 20" '{"frame":{"radius":20}}' 20
frame_case "frame.radius 7.6 rounds" '{"frame":{"radius":7.6}}' 8
frame_case "frame.radius 0 squares the corners" '{"frame":{"radius":0}}' 0
frame_case "frame.radius above 64 falls back" '{"frame":{"radius":65}}' 12
frame_case "a text frame.radius falls back" '{"frame":{"radius":"20"}}' 12
frame_case "an unreadable shell.json falls back" '{"frame":' 12
# A user theme whose hyprland.lua links elsewhere: the link target is the
# user's, never written; the staged copy still leaves the shared radius.
rm -f "$HOME/.config/haseen/shell.json"
mkdir -p "$HOME/.config/haseen/themes/linked"
cp "$HASEEN_PATH/themes/tokyo-night/colors.toml" "$HOME/.config/haseen/themes/linked/"
printf 'hl.config({ decoration = { rounding = 3 } })\n' >"$SANDBOX/own-hyprland.lua"
ln -s "$SANDBOX/own-hyprland.lua" "$HOME/.config/haseen/themes/linked/hyprland.lua"
capture haseen theme set linked
assert_status "a linked theme hyprland.lua sets" 0 "$STATUS"
assert_eq "the linked file is left as it was" 'hl.config({ decoration = { rounding = 3 } })' "$(<"$SANDBOX/own-hyprland.lua")"
if command -v lua >/dev/null; then
    assert_eq "its windows still round like the frame" 12 "$(window_rounding)"
fi
# A dangling link is the user's too: the template renders in its place in the
# staging copy, and the link's target is never created.
mkdir -p "$SANDBOX/dots" "$HOME/.config/haseen/themes/dangling"
cp "$HASEEN_PATH/themes/tokyo-night/colors.toml" "$HOME/.config/haseen/themes/dangling/"
ln -s "$SANDBOX/dots/hyprland.lua" "$HOME/.config/haseen/themes/dangling/hyprland.lua"
capture haseen theme set dangling
assert_status "a dangling theme hyprland.lua sets" 0 "$STATUS"
assert_eq "the dangling link's target is not created" "" "$(ls -A "$SANDBOX/dots")"
assert_contains "the template renders in its place" "$(<"$CUR/theme/hyprland.lua")" "active_border"
assert_eq "the staged file is not a link" "" "$(find "$CUR/theme/hyprland.lua" -type l)"
# A theme file that ends in a top-level `return` still parses: the radius
# hook is a prefix, not a line after the return.
mkdir -p "$HOME/.config/haseen/themes/returns"
cp "$HASEEN_PATH/themes/tokyo-night/colors.toml" "$HOME/.config/haseen/themes/returns/"
printf 'local t = {}\nhl.config({ decoration = { rounding = 3 } })\nreturn t\n' \
    >"$HOME/.config/haseen/themes/returns/hyprland.lua"
capture haseen theme set returns
assert_status "a theme ending in return sets" 0 "$STATUS"
if command -v luac >/dev/null; then
    capture luac -p "$CUR/theme/hyprland.lua"
    assert_status "and its staged hyprland.lua parses" 0 "$STATUS"
fi
if command -v lua >/dev/null; then
    assert_eq "and loads, at the shared radius" 12 "$(window_rounding)"
fi

# --- the shared radius is a default, not the last word (load order) ---------
# init.lua: defaults + current/theme/rounding.lua, then toggles, then hyprmod,
# then the theme file (its own rounding dropped), then the user's files.
theme_sandbox theme-rounding-order
stub hyprctl 'exit 0'
mkdir -p "$HOME/.config/haseen" "$HOME/.config/hypr"
printf '{"frame":{"radius":20}}\n' >"$HOME/.config/haseen/shell.json"
capture haseen theme set solitude
assert_status "set solitude (a theme with its own rounding)" 0 "$STATUS"
capture haseen theme set --dry-run solitude
assert_contains "the dry run plans the shared radius" "$OUTPUT" "rounding.lua: window corners 20"
if command -v lua >/dev/null; then
    assert_eq "the shared radius beats the theme's own rounding" 20 "$(window_rounding)"
    capture haseen toggle gaps on
    assert_status "toggle gaps on" 0 "$STATUS"
    assert_eq "haseen toggle gaps on still squares the corners" 0 "$(window_rounding)"
    capture haseen toggle gaps off
    assert_eq "and off brings the shared radius back" 20 "$(window_rounding)"
    printf 'hl.config({ decoration = { rounding = 5 } })\n' >"$HOME/.config/hypr/hyprland-gui.lua"
    assert_eq "hyprmod's rounding wins over the shared radius" 5 "$(window_rounding)"
    printf 'hl.config({ decoration = { rounding = 9 } })\n' >"$HOME/.config/hypr/local.lua"
    assert_eq "the user's own files win over hyprmod" 9 "$(window_rounding)"
    rm -f "$HOME/.config/hypr/hyprland-gui.lua" "$HOME/.config/hypr/local.lua"
fi
# A fractional radius token truncates like Theme.qml's int property (7.5 -> 7).
mkdir -p "$HOME/.config/haseen/themes/frac"
sed 's/^radius *=.*//' "$HASEEN_PATH/themes/tokyo-night/colors.toml" >"$HOME/.config/haseen/themes/frac/colors.toml"
printf 'radius = 7.5\n' >>"$HOME/.config/haseen/themes/frac/colors.toml"
rm -f "$HOME/.config/haseen/shell.json"
capture haseen theme set frac
assert_status "set a theme with a fractional radius" 0 "$STATUS"
assert_eq "the window radius truncates the token like QML" 14 "$(staged_rounding)"
if command -v Hyprland >/dev/null; then
    mkdir -p "$SANDBOX/verify" "$SANDBOX/run"
    chmod 700 "$SANDBOX/run"
    printf 'dofile("%s")\ndofile("%s")\n' "$CUR/theme/rounding.lua" "$CUR/theme/hyprland.lua" >"$SANDBOX/verify/rounding.lua"
    capture env XDG_RUNTIME_DIR="$SANDBOX/run" timeout 30 Hyprland --verify-config -c "$SANDBOX/verify/rounding.lua"
    assert_contains "Hyprland accepts the rounding files" "$OUTPUT" "config ok"
fi

# --- shell selection stays readable under foreground text -------------------
# haseen's selection_background is a bright orange (2.3:1 under its
# light grey text); the shell token is darkened until the text reads (4.5:1).
theme_sandbox theme-selection
haseen theme set haseen >/dev/null 2>&1
assert_eq "bright selection darkened for the shell" "#864313" "$(jq -r .selection "$CUR/theme/shell.json")"

# --- shell.json mapping and idempotency (tokyo-night) -----------------------
theme_sandbox theme-tokens
haseen theme set tokyo-night >/dev/null 2>&1
first="$(cd "$CUR/theme" && cat -- *)"
assert_eq "surface = mix background foreground 6%" "#232431" "$(jq -r .surface "$CUR/theme/shell.json")"
assert_eq "border = mix background foreground 20%" "#373949" "$(jq -r .border "$CUR/theme/shell.json")"
assert_eq "accentFg = background" "#1a1b26" "$(jq -r .accentFg "$CUR/theme/shell.json")"
assert_eq "a readable selection is kept" "#292e42" "$(jq -r .selection "$CUR/theme/shell.json")"
assert_eq "hyprland.lua active border" 'local active_border_color = "#7aa2f7"' "$(grep -m1 '^local active_border_color' "$CUR/theme/hyprland.lua")"
capture haseen theme set "Tokyo Night"
assert_status "display name normalizes" 0 "$STATUS"
assert_eq "re-set is byte-identical" "$first" "$(cd "$CUR/theme" && cat -- *)"
capture haseen theme current
assert_eq "theme current" "tokyo-night" "$OUTPUT"
capture haseen theme list
assert_eq "theme list = stock themes" "$(ls "$HASEEN_PATH/themes" | LC_ALL=C sort)" "$OUTPUT"
capture haseen theme set no-such-theme
assert_status "unknown theme refused" 1 "$STATUS"
assert_contains "unknown theme message" "$OUTPUT" "does not exist"
capture haseen theme set ../../etc
assert_status "path-like name refused" 2 "$STATUS"
assert_eq "refusals keep the current theme" "tokyo-night" "$(cat "$CUR/theme.name")"

# --- template helpers match Omarchy's renderer ------------------------------
# Expected values were produced by /tmp/ref/omarchy/bin/omarchy-theme-set-templates
# on the same colors.toml and template.
theme_sandbox theme-helpers
mkdir -p "$HOME/.config/haseen/themes/probe" "$HOME/.config/haseen/themed"
cp "$HASEEN_PATH/themes/tokyo-night/colors.toml" "$HOME/.config/haseen/themes/probe/"
echo 'hyprland_active_border = "rgba(33ccffee) rgba(00ff99ee) 45deg"' >>"$HOME/.config/haseen/themes/probe/colors.toml"
echo 'mix={{ mix background foreground 15% }} strip={{ mix_strip background accent 0.35 }} rgb={{ mix_rgb color0 color7 50 }} hg={{ hypr_gradient hyprland_active_border accent }} sg={{ shell_gradient hyprland_active_border accent }} gs={{ gradient_start hyprland_active_border accent }} hf={{ hypr_gradient missing_key rgba(595959aa) }} a={{ accent_rgb }} s={{ accent_strip }} u={{ unknown_key }}' \
    >"$HOME/.config/haseen/themed/probe.txt.tpl"
capture haseen theme set probe
assert_status "set user theme" 0 "$STATUS"
assert_eq "helpers match Omarchy" 'mix=#2f3240 strip=3c4a6f rgb=98,102,126 hg={ colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 } sg=rgba(33ccffee) rgba(00ff99ee) 45deg gs=#33ccff hf="rgba(595959aa)" a=122,162,247 s=7aa2f7 u={{ unknown_key }}' "$(<"$CUR/theme/probe.txt")"
assert_contains "unknown placeholder is reported" "$OUTPUT" "unrendered placeholder left in probe.txt"
assert_eq "gradient reaches hyprland.lua" 'local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }' "$(grep -m1 '^local active_border_color' "$CUR/theme/hyprland.lua")"

# --- user template override wins --------------------------------------------
theme_sandbox theme-user-template
mkdir -p "$HOME/.config/haseen/themed"
printf '# mine\nbackground {{ accent }}\n' >"$HOME/.config/haseen/themed/kitty.conf.tpl"
haseen theme set gruvbox >/dev/null 2>&1
assert_eq "user kitty template wins" "# mine"$'\n'"background $(colour_of "$HASEEN_PATH/themes/gruvbox/colors.toml" accent)" "$(<"$CUR/theme/kitty.conf")"
assert_contains "stock templates still render" "$(<"$CUR/theme/foot.ini")" "[colors-dark]"

# --- every template output is classified for the installed-theme denylist ---
theme_sandbox theme-classify
unclassified="$(bash -c '
    source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/layers/theme/theme-lib.sh"
    for tpl in "$THEME_TEMPLATES_DIR"/*.tpl; do
        out="${tpl##*/}"; out="${out%.tpl}"
        [[ $out == *.lua ]] && continue
        [[ " ${THEME_INSTALLED_DENIED[*]} ${THEME_COLOUR_ONLY[*]} " == *" $out "* ]] || echo "$out"
    done')"
assert_eq "every template output is denied or reviewed colour-only" "" "$unclassified"

# --- install an Omarchy theme from a local git repo -------------------------
# Named nordtest: nord is a stock theme now, and the stock copy would supply
# the neovim.lua/vscode.json this block checks the denylist drops.
theme_sandbox theme-install-nord
stub git 'exec /usr/bin/git "$@"'
src="$SANDBOX/src/omarchy-nordtest-theme"
mkdir -p "$src/backgrounds"
cp "$FIXTURES/theme-omarchy-nord/"* "$src/"
printf 'img' >"$src/backgrounds/1-test.png"
make_repo "$src"
before="$(tree)"
capture haseen theme install "$src" --dry-run
assert_status "install dry-run" 0 "$STATUS"
assert_dry_pure "install" "$OUTPUT"
assert_contains "install dry-run plans the clone" "$OUTPUT" "DRYRUN: git clone -- $src $HOME/.config/haseen/themes/nordtest"
assert_eq "install --dry-run writes nothing" "$before" "$(tree)"
capture haseen theme install "$src"
assert_status "install nordtest" 0 "$STATUS"
assert_eq "installed theme applied" "nordtest" "$(cat "$CUR/theme.name" 2>/dev/null)"
assert_eq "clone kept as a repo" "yes" "$([[ -d $HOME/.config/haseen/themes/nordtest/.git ]] && echo yes)"
assert_eq "nord palette staged" "$(<"$FIXTURES/theme-omarchy-nord/colors.toml")" "$(cat "$CUR/theme/colors.toml" 2>/dev/null)"
assert_not_contains "installed neovim.lua dropped" "$(cat "$CUR/theme/neovim.lua" 2>/dev/null)" "nightfox"
assert_contains "neovim.lua generated instead" "$(cat "$CUR/theme/neovim.lua" 2>/dev/null)" "aether"
assert_eq "vscode.json dropped" "" "$(ls "$CUR/theme/vscode.json" 2>/dev/null)"
assert_contains "dropped files named" "$OUTPUT" "neovim.lua"
assert_eq "background linked" "$CUR/theme/backgrounds/1-test.png" "$(readlink "$CUR/background")"
assert_contains "nordtest listed" "$(haseen theme list)" "nordtest"
capture haseen theme install "$src" --yes
assert_status "re-install converges" 0 "$STATUS"
assert_eq "no install leftovers" "" "$(find "$HOME/.config/haseen/themes" -mindepth 1 -maxdepth 1 ! -name nordtest -printf '%f\n')"

# --- the denylist rejects code an installed theme carries -------------------
theme_sandbox theme-denylist
stub git 'exec /usr/bin/git "$@"'
evil="$SANDBOX/src/evil-theme"
mkdir -p "$evil/extra"
cp "$FIXTURES/theme-omarchy-nord/colors.toml" "$evil/"
printf 'accent = "#fff\\"; os.execute(\\"id\\") --"\n' >>"$evil/colors.toml"
printf 'os.execute("touch %s/pwned")\n' "$HOME" >"$evil/hyprland.lua"
printf 'shell /bin/evil\n' >"$evil/kitty.conf"
printf '[main]\nshell=/bin/evil\n' >"$evil/foot.ini"
printf '#!/bin/sh\nid\n' >"$evil/run.sh"
printf '#!/bin/sh\nid\n' >"$evil/helper"
chmod +x "$evil/helper"
printf 'return {}\n' >"$evil/extra/plugin.lua"
ln -s /etc/hostname "$evil/unlock.png"
printf '#abcdef\n' >"$evil/keyboard.rgb"
make_repo "$evil"
capture haseen theme install "$evil"
assert_status "install evil theme (code dropped, colours kept)" 0 "$STATUS"
assert_not_contains "hyprland.lua is the template" "$(cat "$CUR/theme/hyprland.lua")" "os.execute"
assert_contains "hyprland.lua rendered" "$(cat "$CUR/theme/hyprland.lua")" "hl.config"
assert_not_contains "kitty.conf is the template" "$(cat "$CUR/theme/kitty.conf")" "/bin/evil"
assert_not_contains "foot.ini is the template" "$(cat "$CUR/theme/foot.ini")" "/bin/evil"
for f in run.sh helper unlock.png extra/plugin.lua; do
    assert_eq "denied $f not staged" "" "$(ls "$CUR/theme/$f" 2>/dev/null)"
    assert_contains "denied $f named" "$OUTPUT" "$f"
done
assert_eq "colour file kept" "#abcdef" "$(cat "$CUR/theme/keyboard.rgb" 2>/dev/null)"
assert_contains "hostile value skipped" "$OUTPUT" "skipping accent"
rendered="$(for f in "$CUR/theme"/*; do [[ -f $f && ${f##*/} != colors.toml ]] && cat "$f"; done; true)"
assert_not_contains "hostile value never rendered" "$rendered" "os.execute"
assert_eq "theme Lua never executed" "" "$(ls "$HOME/pwned" 2>/dev/null)"

# A repo that is not a theme is refused and leaves nothing behind.
notheme="$SANDBOX/src/notatheme"
mkdir -p "$notheme"
printf 'hello\n' >"$notheme/README"
make_repo "$notheme"
capture haseen theme install "$notheme"
assert_status "repo without colors.toml refused" 1 "$STATUS"
assert_contains "refusal reason" "$OUTPUT" "colors.toml"
assert_eq "refused repo not kept" "" "$(find "$HOME/.config/haseen/themes" -mindepth 1 -maxdepth 1 ! -name evil -printf '%f\n')"
capture haseen theme install "--upload-pack=touch $HOME/x"
assert_status "git option as URL refused" 1 "$STATUS"
capture haseen theme install "ext::sh -c touch% $HOME/x"
assert_status "transport helper refused" 1 "$STATUS"
assert_eq "nothing executed by refused URLs" "" "$(ls "$HOME/x" 2>/dev/null)"

# A theme the user wrote (no .git) is trusted in full and never replaced.
mkdir -p "$HOME/.config/haseen/themes/mine"
cp "$FIXTURES/theme-omarchy-nord/colors.toml" "$HOME/.config/haseen/themes/mine/"
printf -- '-- mine\n' >"$HOME/.config/haseen/themes/mine/hyprland.lua"
haseen theme set mine >/dev/null 2>&1
assert_contains "own theme ships its hyprland.lua" "$(<"$CUR/theme/hyprland.lua")" "-- mine"
if command -v lua >/dev/null; then
    assert_eq "and its windows round like the frame" "$(($(jq -r .radius "$CUR/theme/shell.json") * 2))" \
        "$(window_rounding)"
fi
mkdir -p "$SANDBOX/src/mine"
cp "$FIXTURES/theme-omarchy-nord/colors.toml" "$SANDBOX/src/mine/"
make_repo "$SANDBOX/src/mine"
capture haseen theme install "$SANDBOX/src/mine" --yes
assert_status "install over own theme refused" 1 "$STATUS"
assert_eq "own theme untouched" "-- mine" "$(cat "$HOME/.config/haseen/themes/mine/hyprland.lua")"

# --- post-set reloads and hooks --------------------------------------------
theme_sandbox theme-post-set
mkdir -p "$HOME/.config/haseen/hooks/theme-set.d"
printf 'echo "HOOK $1" >"$HOME/hook.out"\n' >"$HOME/.config/haseen/hooks/theme-set"
printf 'echo "D $1" >>"$HOME/hook.out"\n' >"$HOME/.config/haseen/hooks/theme-set.d/10-a"
printf 'echo SAMPLE >>"$HOME/hook.out"\n' >"$HOME/.config/haseen/hooks/theme-set.d/20-b.sample"
stub hyprctl 'echo "HYPRCTL $*"'
stub pgrep '[ "$2" = kitty ]'
stub pkill 'echo "PKILL $*"'
export HYPRLAND_INSTANCE_SIGNATURE=test DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
# `gsettings get … gtk-theme` answers from $HOME/gtk-theme (quoted, as gsettings does).
stub gsettings '[ "$1" = get ] && { cat "$HOME/gtk-theme"; exit 0; }; echo "GSETTINGS $*"'
echo "'Adwaita-dark'" >"$HOME/gtk-theme"

before="$(tree)"
capture haseen theme set catppuccin-latte --dry-run
assert_status "set dry-run" 0 "$STATUS"
assert_dry_pure "set" "$OUTPUT"
assert_eq "set --dry-run writes nothing" "$before" "$(tree)"
assert_contains "dry-run renders shell.json" "$OUTPUT" "-> $CUR/next-theme/shell.json"
assert_contains "dry-run keeps the theme's neovim.lua" "$OUTPUT" "keep neovim.lua"
assert_contains "dry-run hyprctl" "$OUTPUT" "DRYRUN: hyprctl reload"
assert_contains "dry-run kitty reload" "$OUTPUT" "DRYRUN: pkill -USR1 -x kitty"
assert_not_contains "foot not running, not retinted" "$OUTPUT" "theme_retint_foot"
assert_contains "dry-run light colour scheme" "$OUTPUT" "DRYRUN: gsettings set org.gnome.desktop.interface color-scheme prefer-light"
assert_contains "dry-run light GTK 3 theme" "$OUTPUT" "DRYRUN: gsettings set org.gnome.desktop.interface gtk-theme Adwaita"
assert_not_contains "dry-run light keeps no dark GTK 3 theme" "$OUTPUT" "gtk-theme Adwaita-dark"
assert_contains "dry-run hook" "$OUTPUT" "DRYRUN: haseen-hook run theme-set catppuccin-latte"

capture haseen theme set catppuccin-latte
assert_status "set with session" 0 "$STATUS"
assert_contains "hyprctl reload ran" "$OUTPUT" "HYPRCTL reload"
assert_contains "kitty signalled" "$OUTPUT" "PKILL -USR1 -x kitty"
assert_contains "gsettings light" "$OUTPUT" "GSETTINGS set org.gnome.desktop.interface color-scheme prefer-light"
assert_contains "Adwaita-dark becomes Adwaita for a light theme" "$OUTPUT" "GSETTINGS set org.gnome.desktop.interface gtk-theme Adwaita"
assert_not_contains "light theme sets no Adwaita-dark" "$OUTPUT" "gtk-theme Adwaita-dark"
assert_eq "hooks ran in order, samples skipped" $'HOOK catppuccin-latte\nD catppuccin-latte' "$(cat "$HOME/hook.out" 2>/dev/null)"

rm -f "$HOME/hook.out"
unset HYPRLAND_INSTANCE_SIGNATURE
capture env HASEEN_THEME_HEADLESS=1 haseen theme set tokyo-night
assert_not_contains "headless skips reloads" "$OUTPUT" "PKILL"
assert_eq "headless skips hooks" "" "$(cat "$HOME/hook.out" 2>/dev/null)"
capture haseen theme set tokyo-night
assert_not_contains "no Hyprland, no hyprctl" "$OUTPUT" "HYPRCTL"
assert_contains "dark colour scheme" "$OUTPUT" "color-scheme prefer-dark"
assert_contains "Adwaita becomes Adwaita-dark for a dark theme" "$OUTPUT" "GSETTINGS set org.gnome.desktop.interface gtk-theme Adwaita-dark"
echo "'Breeze'" >"$HOME/gtk-theme"
capture haseen theme set tokyo-night
assert_not_contains "a user's own GTK theme stays" "$OUTPUT" "gtk-theme"

# --- GTK and libadwaita follow the theme ------------------------------------
# gtk-4.0/gtk.css (libadwaita included) and gtk-3.0/gtk.css are written once
# with an @import of the rendered colours; a gtk.css the user has stays theirs.
theme_sandbox theme-gtk
cfg="$HOME/.config"
before="$(tree)"
capture haseen theme set tokyo-night --dry-run
assert_contains "dry-run plans the GTK 4 import" "$OUTPUT" "DRYRUN: write $cfg/gtk-4.0/gtk.css"
assert_contains "dry-run plans the GTK 3 import" "$OUTPUT" "DRYRUN: write $cfg/gtk-3.0/gtk.css"
assert_eq "GTK dry-run writes nothing" "$before" "$(tree)"
capture haseen theme set tokyo-night
assert_status "set tokyo-night" 0 "$STATUS"
for v in 3.0 4.0; do
    assert_contains "gtk-$v/gtk.css imports the rendered colours" "$(cat "$cfg/gtk-$v/gtk.css" 2>/dev/null)" "@import url(\"$CUR/theme/gtk.css\");"
done
gtk="$(<"$CUR/theme/gtk.css")"
assert_contains "views on the theme background" "$gtk" "@define-color view_bg_color #1a1b26;"
assert_contains "cards mix background toward foreground" "$gtk" "@define-color card_bg_color #232431;"
assert_contains "popovers a step further" "$gtk" "@define-color popover_bg_color #2b2d3b;"
assert_contains "text on accent is the background" "$gtk" "@define-color accent_fg_color #1a1b26;"
assert_contains "warning colour from yellow" "$gtk" "@define-color warning_bg_color #e0af68;"
assert_contains "GTK 3 selection is the accent" "$gtk" "@define-color theme_selected_bg_color #7aa2f7;"
capture haseen theme set haseen
assert_contains "a theme change recolours through the same import" "$(<"$CUR/theme/gtk.css")" "@define-color accent_bg_color #F25623;"
echo "/* mine */" >"$cfg/gtk-4.0/gtk.css"
rm "$cfg/gtk-3.0/gtk.css"
ln -s /nonexistent "$cfg/gtk-3.0/gtk.css"
capture haseen theme set gruvbox
assert_status "set over the user's gtk.css" 0 "$STATUS"
assert_eq "the user's gtk-4.0/gtk.css stays" "/* mine */" "$(<"$cfg/gtk-4.0/gtk.css")"
assert_eq "the user's gtk-3.0/gtk.css link stays" "/nonexistent" "$(readlink "$cfg/gtk-3.0/gtk.css")"

# --- haseen hook ------------------------------------------------------------
theme_sandbox theme-hook
printf 'echo "RAN $*"\n' >"$SANDBOX/myhook.sh"
before="$(tree)"
capture haseen hook install theme-set "$SANDBOX/myhook.sh" --dry-run
assert_status "hook install dry-run" 0 "$STATUS"
assert_contains "hook install plan" "$OUTPUT" "DRYRUN: install -Dm0755 -- $SANDBOX/myhook.sh $HOME/.config/haseen/hooks/theme-set.d/myhook.sh"
assert_eq "hook install --dry-run writes nothing" "$before" "$(tree)"
capture haseen hook install theme-set "$SANDBOX/myhook.sh"
assert_status "hook install" 0 "$STATUS"
assert_eq "hook installed executable" "yes" "$([[ -x $HOME/.config/haseen/hooks/theme-set.d/myhook.sh ]] && echo yes)"
capture haseen hook install theme-set "$SANDBOX/myhook.sh"
assert_contains "hook re-install is a no-op" "$OUTPUT" "already installed"
capture haseen hook run theme-set a b
assert_eq "hook run passes args" "RAN a b" "$OUTPUT"
capture haseen hook run theme-set a --dry-run
assert_contains "hook run dry-run" "$OUTPUT" "DRYRUN: bash $HOME/.config/haseen/hooks/theme-set.d/myhook.sh a"
assert_not_contains "hook not executed in dry-run" "$OUTPUT" "RAN"
capture haseen hook install them-set "$SANDBOX/myhook.sh"
assert_status "unknown event refused" 2 "$STATUS"
capture haseen hook run ..
assert_status "dot-dot event refused" 2 "$STATUS"
capture haseen hook run a/b
assert_status "slash event refused" 2 "$STATUS"
printf 'exit 3\n' >"$HOME/.config/haseen/hooks/post-update"
capture haseen hook run post-update
assert_status "failing hook is not fatal" 0 "$STATUS"
assert_contains "failing hook reported" "$OUTPUT" "Hook failed"

# --- theme layer ------------------------------------------------------------
theme_sandbox theme-layer
# The layer also enables haseen-background.service (swaybg): a present
# swaybg and a systemctl that records the enable as systemd would.
stub swaybg 'exit 0'
stub systemctl "[ \"\$*\" = '--user enable haseen-background.service' ] || { echo \"STUB-CALLED: systemctl \$*\" >&2; exit 97; }
mkdir -p '$HOME/.config/systemd/user/graphical-session.target.wants'
ln -sf /usr/lib/systemd/user/haseen-background.service '$HOME/.config/systemd/user/graphical-session.target.wants/haseen-background.service'"
fx="$FIXTURES/cachyos-limine-luks-dualboot"
layer_cmd() { env HASEEN_SYSROOT="$fx" DRY_RUN="${2:-false}" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; _layer_env theme; '"$1"; }
capture layer_cmd layer_status
assert_status "layer status before" 1 "$STATUS"
assert_contains "status names the missing theme" "$OUTPUT" "missing: no theme set"
before="$(tree)"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_run_apply theme'
assert_status "layer apply dry-run" 0 "$STATUS"
assert_dry_pure "theme layer" "$OUTPUT"
assert_contains "layer plans the default theme" "$OUTPUT" "DRYRUN: write $CUR/theme.name: haseen"
assert_eq "layer apply --dry-run writes nothing" "$before" "$(tree)"
capture layer_cmd layer_apply
assert_status "layer apply" 0 "$STATUS"
assert_eq "default theme set" "haseen" "$(cat "$CUR/theme.name" 2>/dev/null)"
haseen theme set gruvbox >/dev/null 2>&1
capture layer_cmd layer_apply
assert_contains "re-apply keeps the user's choice" "$OUTPUT" "theme already set: gruvbox"
assert_eq "theme unchanged by re-apply" "gruvbox" "$(cat "$CUR/theme.name")"
capture layer_cmd layer_status
assert_status "layer status after" 0 "$STATUS"
