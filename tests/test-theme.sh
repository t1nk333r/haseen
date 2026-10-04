# shellcheck shell=bash
# Theme pipeline: every stock theme renders completely, shell.json carries the
# architecture §7 tokens, helpers match Omarchy's output, user templates win,
# installed themes go through the denylist, hooks run, dry runs write nothing.

THEME_OUTPUTS=(hyprland.lua foot.ini kitty.conf ghostty.conf alacritty.toml btop.theme neovim.lua gtk.css shell.json colors.toml)
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
        bad="$(jq -r --arg k "$SHELL_COLOUR_KEYS" '($k | split(" ")) as $ks | to_entries[] | select(.key as $x | $ks | index($x)) | select(.value | test("^#[0-9a-f]{6}$") | not) | .key' "$sj")"
        assert_eq "$t shell.json colours are #rrggbb" "" "$bad"
        assert_eq "$t shell.json numbers" "number number number number" "$(jq -r '[.fontSize, .radius, .gap, .borderWidth] | map(type) | join(" ")' "$sj")"
        assert_eq "$t mode follows colors.toml" "$(sed -n 's/^mode *= *"\(.*\)"/\1/p' "$dir/colors.toml")" "$(jq -r .mode "$sj")"
        assert_eq "$t accent from colors.toml" "$(colour_of "$dir/colors.toml" accent)" "$(jq -r .accent "$sj")"
    else
        _fail "$t shell.json is valid JSON" "$(cat "$sj" 2>/dev/null)"
    fi
    bg="$(colour_of "$dir/colors.toml" background)"
    assert_contains "$t foot background" "$(<"$CUR/theme/foot.ini")" "background=${bg#\#}"
    if command -v luac >/dev/null; then
        capture luac -p "$CUR/theme/hyprland.lua" "$CUR/theme/neovim.lua"
        assert_status "$t Lua outputs parse" 0 "$STATUS"
    fi
    assert_eq "$t theme-shipped neovim.lua wins over the template" "$(<"$dir/neovim.lua")" "$(<"$CUR/theme/neovim.lua")"
    assert_eq "$t no staging leftovers" "" "$(ls -d "$CUR/next-theme" "$CUR/old-theme" 2>/dev/null)"
done

# --- shell.json mapping and idempotency (tokyo-night) -----------------------
theme_sandbox theme-tokens
haseen theme set tokyo-night >/dev/null 2>&1
first="$(cd "$CUR/theme" && cat -- *)"
assert_eq "surface = mix background foreground 6%" "#232431" "$(jq -r .surface "$CUR/theme/shell.json")"
assert_eq "border = mix background foreground 20%" "#373949" "$(jq -r .border "$CUR/theme/shell.json")"
assert_eq "accentFg = background" "#1a1b26" "$(jq -r .accentFg "$CUR/theme/shell.json")"
assert_eq "hyprland.lua active border" 'local active_border_color = "#7aa2f7"' "$(head -n1 "$CUR/theme/hyprland.lua")"
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
assert_eq "gradient reaches hyprland.lua" 'local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }' "$(head -n1 "$CUR/theme/hyprland.lua")"

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
theme_sandbox theme-install-nord
stub git 'exec /usr/bin/git "$@"'
src="$SANDBOX/src/omarchy-nord-theme"
mkdir -p "$src/backgrounds"
cp "$FIXTURES/theme-omarchy-nord/"* "$src/"
printf 'img' >"$src/backgrounds/1-test.png"
make_repo "$src"
before="$(tree)"
capture haseen theme install "$src" --dry-run
assert_status "install dry-run" 0 "$STATUS"
assert_dry_pure "install" "$OUTPUT"
assert_contains "install dry-run plans the clone" "$OUTPUT" "DRYRUN: git clone -- $src $HOME/.config/haseen/themes/nord"
assert_eq "install --dry-run writes nothing" "$before" "$(tree)"
capture haseen theme install "$src"
assert_status "install nord" 0 "$STATUS"
assert_eq "installed theme applied" "nord" "$(cat "$CUR/theme.name" 2>/dev/null)"
assert_eq "clone kept as a repo" "yes" "$([[ -d $HOME/.config/haseen/themes/nord/.git ]] && echo yes)"
assert_eq "nord palette staged" "$(<"$FIXTURES/theme-omarchy-nord/colors.toml")" "$(cat "$CUR/theme/colors.toml" 2>/dev/null)"
assert_not_contains "installed neovim.lua dropped" "$(cat "$CUR/theme/neovim.lua" 2>/dev/null)" "nightfox"
assert_contains "neovim.lua generated instead" "$(cat "$CUR/theme/neovim.lua" 2>/dev/null)" "aether"
assert_eq "vscode.json dropped" "" "$(ls "$CUR/theme/vscode.json" 2>/dev/null)"
assert_contains "dropped files named" "$OUTPUT" "neovim.lua"
assert_eq "background linked" "$CUR/theme/backgrounds/1-test.png" "$(readlink "$CUR/background")"
assert_contains "nord listed" "$(haseen theme list)" "nord"
capture haseen theme install "$src" --yes
assert_status "re-install converges" 0 "$STATUS"
assert_eq "no install leftovers" "" "$(find "$HOME/.config/haseen/themes" -mindepth 1 -maxdepth 1 ! -name nord -printf '%f\n')"

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
assert_eq "own theme ships its hyprland.lua" "-- mine" "$(cat "$CUR/theme/hyprland.lua")"
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
stub gsettings 'echo "GSETTINGS $*"'

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
assert_contains "dry-run hook" "$OUTPUT" "DRYRUN: haseen-hook run theme-set catppuccin-latte"

capture haseen theme set catppuccin-latte
assert_status "set with session" 0 "$STATUS"
assert_contains "hyprctl reload ran" "$OUTPUT" "HYPRCTL reload"
assert_contains "kitty signalled" "$OUTPUT" "PKILL -USR1 -x kitty"
assert_contains "gsettings light" "$OUTPUT" "GSETTINGS set org.gnome.desktop.interface color-scheme prefer-light"
assert_eq "hooks ran in order, samples skipped" $'HOOK catppuccin-latte\nD catppuccin-latte' "$(cat "$HOME/hook.out" 2>/dev/null)"

rm -f "$HOME/hook.out"
unset HYPRLAND_INSTANCE_SIGNATURE
capture env HASEEN_THEME_HEADLESS=1 haseen theme set tokyo-night
assert_not_contains "headless skips reloads" "$OUTPUT" "PKILL"
assert_eq "headless skips hooks" "" "$(cat "$HOME/hook.out" 2>/dev/null)"
capture haseen theme set tokyo-night
assert_not_contains "no Hyprland, no hyprctl" "$OUTPUT" "HYPRCTL"
assert_contains "dark colour scheme" "$OUTPUT" "color-scheme prefer-dark"

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
fx="$FIXTURES/cachyos-limine-luks-dualboot"
layer_cmd() { env HASEEN_SYSROOT="$fx" DRY_RUN="${2:-false}" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; _layer_env theme; '"$1"; }
capture layer_cmd layer_status
assert_status "layer status before" 1 "$STATUS"
assert_contains "status names the missing theme" "$OUTPUT" "missing: no theme set"
before="$(tree)"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_run_apply theme'
assert_status "layer apply dry-run" 0 "$STATUS"
assert_dry_pure "theme layer" "$OUTPUT"
assert_contains "layer plans the default theme" "$OUTPUT" "DRYRUN: write $CUR/theme.name: tokyo-night"
assert_eq "layer apply --dry-run writes nothing" "$before" "$(tree)"
capture layer_cmd layer_apply
assert_status "layer apply" 0 "$STATUS"
assert_eq "default theme set" "tokyo-night" "$(cat "$CUR/theme.name" 2>/dev/null)"
haseen theme set gruvbox >/dev/null 2>&1
capture layer_cmd layer_apply
assert_contains "re-apply keeps the user's choice" "$OUTPUT" "theme already set: gruvbox"
assert_eq "theme unchanged by re-apply" "gruvbox" "$(cat "$CUR/theme.name")"
capture layer_cmd layer_status
assert_status "layer status after" 0 "$STATUS"
