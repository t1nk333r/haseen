# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's theme commands (omarchy-theme-*; plan 093,
# g6a): the templates under share/haseen/omarchy/themed rendered from a
# fixture theme set with `haseen theme set`, every app publisher (Claude
# Code, Pi, T3 Code, Hermes, Obsidian, VS Code and friends, keyboards,
# browsers, GNOME, tmux, foot), the background and theme-list commands, and
# dry-run purity for every state change. Every app and tool is a stub or a
# directory under $SANDBOX; nothing reaches the session, a tmux server or a
# terminal.

OMA="$HASEEN_PATH/omarchy/bin"

MINE=(omarchy-theme-bg-current omarchy-theme-bg-install omarchy-theme-bg-switcher
    omarchy-theme-color omarchy-theme-colors-from-alacritty omarchy-theme-current
    omarchy-theme-dir omarchy-theme-extras omarchy-theme-install omarchy-theme-list
    omarchy-theme-osc omarchy-theme-refresh omarchy-theme-remove omarchy-theme-set-browser
    omarchy-theme-set-browser-policy omarchy-theme-set-claude omarchy-theme-set-foot
    omarchy-theme-set-gnome omarchy-theme-set-hermes omarchy-theme-set-keyboard
    omarchy-theme-set-keyboard-asus-rog omarchy-theme-set-keyboard-f16
    omarchy-theme-set-obsidian omarchy-theme-set-pi omarchy-theme-set-t3code
    omarchy-theme-set-tmux omarchy-theme-set-vscode omarchy-theme-switcher omarchy-theme-update)

# The fixture theme: dark, with every colour the templates use.
FIXTURE_COLORS='mode = "dark"
accent = "#5fafd7"
selection = "#3a3a4a"
muted = "#5c5c6e"
background = "#16161e"
dark_background = "#101016"
darker_background = "#0a0a0e"
lighter_background = "#22222c"
foreground = "#d0d0d8"
dark_foreground = "#6a6a7a"
light_foreground = "#dcdce4"
bright_foreground = "#eeeef4"
red = "#d75f5f"
yellow = "#d7af5f"
orange = "#d7875f"
green = "#87af5f"
cyan = "#5fafaf"
blue = "#5f87d7"
magenta = "#af87d7"
brown = "#875f3a"
bright_red = "#ff8787"
bright_yellow = "#ffd787"
bright_green = "#afd787"
bright_cyan = "#87d7d7"
bright_blue = "#87afff"
bright_magenta = "#d7afff"'

# box NAME — a sandbox where every program these commands drive is a stub:
# keyboards and editors log to calls.log and mark STUB-CALLED, so a dry run
# that reaches one fails its purity check; tmux answers no server; gsettings
# answers reads and logs writes; pgrep finds no foot.
box() {
    sandbox "$1"
    CUR="$HOME/.local/state/haseen/current"
    TOGGLES="$HOME/.local/state/haseen/toggles/omarchy"
    CALLS="$SANDBOX/calls.log"
    export HASEEN_THEME_FETCH=0
    unset HASEEN_THEME_HEADLESS HASEEN_THEME_MIRROR HASEEN_USER_CACHE
    # The apps' own homes: a session running inside one (T3 Code exports
    # T3CODE_HOME) would otherwise point a publisher at the live directory.
    unset CLAUDE_CONFIG_DIR T3CODE_HOME HERMES_HOME
    # An empty system tree: no Flatpak, icon theme or policy directory of this
    # machine counts. tmux and foot ask live process tables, so their checks
    # run without it.
    ROOT="$SANDBOX/root"
    mkdir -p "$ROOT"
    export HASEEN_SYSROOT="$ROOT"
    stub pgrep 'exit 1'
    local tool
    for tool in asusctl qmk_hid code code-insiders codium cursor xdg-open; do
        stub "$tool" "echo \"$tool \$*\" >>'$CALLS'; echo \"STUB-CALLED: $tool \$*\" >&2; exit 0"
    done
    stub gsettings "case \"\$1\" in
get) echo \"'Adwaita'\" ;;
*) echo \"gsettings \$*\" >>'$CALLS'; echo \"STUB-CALLED: gsettings \$*\" >&2 ;;
esac"
    # tmux: a server only while tmux-up exists; panes from tmux-panes.
    stub tmux "case \"\$1\" in
list-sessions) [ -f '$SANDBOX/tmux-up' ] || exit 1; echo s0 ;;
list-panes) cat '$SANDBOX/tmux-panes' 2>/dev/null ;;
list-clients) [ -f '$SANDBOX/tmux-up' ] && echo /dev/pts/77 ;;
*) echo \"tmux \$*\" >>'$CALLS'; echo \"STUB-CALLED: tmux \$*\" >&2 ;;
esac
exit 0"
}

calls() { cat "$CALLS" 2>/dev/null || true; }
tree() { (cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort); }

# fixture_theme NAME [light] — a user theme with FIXTURE_COLORS under
# ~/.config/haseen/themes, set with `haseen theme set` (headless, no bus).
fixture_theme() {
    local dir="$HOME/.config/haseen/themes/$1"
    mkdir -p "$dir"
    printf '%s\n' "$FIXTURE_COLORS" >"$dir/colors.toml"
    if [[ ${2:-} == light ]]; then sed -i 's/^mode = .*/mode = "light"/' "$dir/colors.toml"; fi
    capture env -u DBUS_SESSION_BUS_ADDRESS -u HASEEN_SYSROOT HASEEN_THEME_HEADLESS=1 haseen theme set "$1"
    assert_status "fixture theme $1 sets" 0 "$STATUS"
}

# fake_tree — a share/haseen whose bin/ is $FAKE/bin: `recorder` puts haseen
# commands there that log "name [arg]..." to fake.log; `fake` runs one of
# these scripts against it.
fake_tree() {
    FAKE="$SANDBOX/fake"
    mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
    local e
    for e in "$HASEEN_PATH"/*; do
        [[ -e $FAKE/share/haseen/${e##*/} ]] || ln -s "$e" "$FAKE/share/haseen/${e##*/}"
    done
}
# recorder NAME [BODY] — $FAKE/bin/NAME logs its argv, then runs BODY.
recorder() {
    fake_tree
    {
        printf '#!/bin/sh\n'
        printf 'printf %%s "${0##*/}" >>"%s"; for a in "$@"; do printf " [%%s]" "$a" >>"%s"; done; echo >>"%s"\n' \
            "$SANDBOX/fake.log" "$SANDBOX/fake.log" "$SANDBOX/fake.log"
        printf '%s\n' "${2:-}"
    } >"$FAKE/bin/$1"
    chmod +x "$FAKE/bin/$1"
}
fake() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/$1" "${@:2}"; }
flog() { cat "$SANDBOX/fake.log" 2>/dev/null || true; }

valid_json() { jq -e . "$1" >/dev/null 2>&1 && echo valid; }
img_png() { printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\x08\x06\0\0\0\x1f\x15\xc4\x89%s' "$2" >"$1"; }

# --- every script: help, notice, mode ---------------------------------------------
box omarchy-theme-help
bad="" notice=""
for name in "${MINE[@]}"; do
    capture "$OMA/$name" --help
    [[ $STATUS == 0 && $OUTPUT == *Usage* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
    [[ -f $OMA/$name && ! -L $OMA/$name && -x $OMA/$name ]] || bad+="$name(not an executable script) "
    tr -s ' \n#' ' ' <"$OMA/$name" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' || notice+="$name "
done
assert_eq "every g6a script is executable, answers --help and runs nothing" "" "$bad"
assert_eq "every g6a script names Omarchy's MIT notice" "" "$notice"
assert_eq "nothing written by --help" "" "$(calls)"
templates_notice=""
for tpl in "$HASEEN_PATH"/omarchy/themed/*.tpl; do
    case $tpl in *.json.tpl | *.theme.tpl | *.rgb.tpl) continue ;; esac
    grep -q 'Copyright (c) David Heinemeier Hansson' "$tpl" || templates_notice+="${tpl##*/} "
done
assert_eq "commentable themed templates carry Omarchy's notice" "" "$templates_notice"
assert_eq "the haseen.themed library names Omarchy's notice" "yes" \
    "$(tr -s ' \n#' ' ' <"$HASEEN_PATH/omarchy/themed/lib.sh" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' && echo yes)"

# --- no current theme: the publishers do nothing ----------------------------------
box omarchy-theme-none
mkdir -p "$HOME/.claude" "$HOME/.pi/agent" "$HOME/.t3/userdata"
before="$(tree)"
quiet=""
for name in omarchy-theme-set-claude omarchy-theme-set-pi omarchy-theme-set-t3code \
    omarchy-theme-set-hermes omarchy-theme-set-obsidian omarchy-theme-set-vscode \
    omarchy-theme-set-keyboard omarchy-theme-set-tmux omarchy-theme-set-foot omarchy-theme-osc; do
    capture "$OMA/$name"
    [[ $STATUS == 0 && -z $OUTPUT ]] || quiet+="$name($STATUS: $OUTPUT) "
done
assert_eq "without a theme every publisher exits 0 and says nothing" "" "$quiet"
assert_eq "without a theme nothing is written" "$before" "$(tree)"
assert_eq "without a theme no tool runs" "" "$(calls)"
capture "$OMA/omarchy-theme-set-claude" --activate
assert_status "claude --activate without a theme fails" 1 "$STATUS"
assert_contains "and says to set one" "$OUTPUT" "haseen theme set"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_status "vscode --activate without a theme fails" 1 "$STATUS"
assert_contains "vscode says to set one" "$OUTPUT" "haseen theme set"
capture "$OMA/omarchy-theme-current"
assert_eq "theme-current without a theme" "Unknown" "$OUTPUT"
assert_status "theme-current without a theme exits 0" 0 "$STATUS"
capture "$OMA/omarchy-theme-bg-current"
assert_eq "bg-current without a background" "Unknown" "$OUTPUT"
capture "$OMA/omarchy-theme-color" accent
assert_status "theme-color without a theme cannot resolve accent" 1 "$STATUS"
capture "$OMA/omarchy-theme-color" mode
assert_eq "theme-color without a theme still answers mode dark (Omarchy)" "dark" "$OUTPUT"
capture "$OMA/omarchy-theme-bg-install"
assert_status "bg-install without a theme fails" 1 "$STATUS"
assert_contains "bg-install says to set one" "$OUTPUT" "haseen theme set"

# --- the fixture theme, colours and names -----------------------------------------
box omarchy-theme-fixture
fixture_theme fixture-night
assert_eq "theme set left the fixture's colors.toml current" "yes" "$([[ -f $CUR/theme/colors.toml ]] && echo yes)"
capture "$OMA/omarchy-theme-current"
assert_eq "theme-current title-cases" "Fixture Night" "$OUTPUT"
capture "$OMA/omarchy-theme-list"
assert_contains "theme-list names the user theme" "$OUTPUT" "Fixture Night"
assert_contains "theme-list names stock themes" "$OUTPUT" "Tokyo Night"
assert_not_contains "theme-list prints no raw names" "$OUTPUT" "tokyo-night"
capture "$OMA/omarchy-theme-dir" fixture-night
assert_eq "theme-dir: the user's theme" "$HOME/.config/haseen/themes/fixture-night" "$OUTPUT"
capture "$OMA/omarchy-theme-dir" tokyo-night
assert_eq "theme-dir: else the stock theme" "$HASEEN_PATH/themes/tokyo-night" "$OUTPUT"
capture "$OMA/omarchy-theme-dir"
assert_status "theme-dir needs a name" 1 "$STATUS"

capture "$OMA/omarchy-theme-color" accent
assert_eq "theme-color resolves a key" "#5fafd7" "$OUTPUT"
capture "$OMA/omarchy-theme-color" color4
assert_eq "theme-color resolves ANSI aliases" "#5f87d7" "$OUTPUT"
capture "$OMA/omarchy-theme-color" no_such_key
assert_status "theme-color: an unknown key exits 1" 1 "$STATUS"
capture "$OMA/omarchy-theme-color" no_such_key background
assert_eq "theme-color: the fallback is tried as a key" "#16161e" "$OUTPUT"
capture "$OMA/omarchy-theme-color" no_such_key "#123456"
assert_eq "theme-color: else used verbatim" "#123456" "$OUTPUT"
capture "$OMA/omarchy-theme-color" --all
assert_contains "theme-color --all: key<TAB>value" "$OUTPUT" $'accent\t#5fafd7'
assert_contains "theme-color --all: resolved keys too" "$OUTPUT" $'color0\t#16161e'
capture "$OMA/omarchy-theme-color" --raw
assert_eq "theme-color --raw: the file's keys in file order" $'mode\tdark\naccent\t#5fafd7' "$(head -2 <<<"$OUTPUT")"
assert_not_contains "theme-color --raw: nothing resolved" "$OUTPUT" "color0"
printf 'accent = "#010203"\n' >"$SANDBOX/other.toml"
capture "$OMA/omarchy-theme-color" --file "$SANDBOX/other.toml" accent
assert_eq "theme-color --file" "#010203" "$OUTPUT"
capture "$OMA/omarchy-theme-color"
assert_status "theme-color without a query: usage" 1 "$STATUS"

capture "$OMA/omarchy-theme-osc"
assert_contains "theme-osc: background" "$OUTPUT" $'\e]11;#16161e\a'
assert_contains "theme-osc: foreground" "$OUTPUT" $'\e]10;#d0d0d8\a'
# haseen's parser draws the cursor in bright_foreground, whatever the file says.
assert_contains "theme-osc: cursor" "$OUTPUT" $'\e]12;#eeeef4\a'
assert_contains "theme-osc: palette" "$OUTPUT" $'\e]4;4;#5f87d7\a'
capture "$OMA/omarchy-theme-osc" "$SANDBOX/missing.toml"
assert_eq "theme-osc: a missing file prints nothing" "" "$OUTPUT"
assert_status "theme-osc: a missing file exits 0" 0 "$STATUS"

# --- template rendering into each app -----------------------------------------------
mkdir -p "$HOME/.claude" "$HOME/.pi/agent" "$HOME/.t3/userdata" "$HOME/.hermes/profiles/work" "$SANDBOX/vault/.obsidian" "$SANDBOX/flatvault/.obsidian"
printf '{"theme": "dark", "keep": 1}\n' >"$HOME/.claude/settings.json"
: >"$HOME/.hermes/config.yaml"
mkdir -p "$HOME/.config/obsidian" "$HOME/.var/app/md.obsidian.Obsidian/config/obsidian"
printf '{"vaults": {"a": {"path": "%s", "ts": 1}}}\n' "$SANDBOX/vault" >"$HOME/.config/obsidian/obsidian.json"
printf '{"vaults": {"b": {"path": "%s", "ts": 1}}}\n' "$SANDBOX/flatvault" >"$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
before="$(tree)"
dry=""
for name in claude pi t3code hermes obsidian vscode keyboard browser gnome tmux foot; do
    capture "$OMA/omarchy-theme-set-$name" --dry-run
    assert_dry_pure "set-$name" "$OUTPUT"
    [[ $STATUS == 0 ]] || dry+="$name($STATUS) "
done
capture "$OMA/omarchy-theme-set-claude" --activate --dry-run
assert_dry_pure "set-claude --activate" "$OUTPUT"
assert_contains "set-claude --activate --dry-run plans the setting" "$OUTPUT" '"theme": "custom:haseen"'
capture "$OMA/omarchy-theme-set-hermes" --activate --dry-run
assert_contains "set-hermes --activate --dry-run plans the switch" "$OUTPUT" "DRYRUN: timeout 30 $HOME/.local/bin/hermes config set display.skin haseen"
capture "$OMA/omarchy-theme-set-vscode" --activate --dry-run
assert_dry_pure "set-vscode --activate" "$OUTPUT"
assert_contains "set-vscode --activate --dry-run plans the setting" "$OUTPUT" '"workbench.colorTheme": "haseen"'
assert_eq "every publisher's dry run exits 0" "" "$dry"
assert_eq "dry runs write nothing" "$before" "$(tree)"
assert_eq "dry runs run no tool" "" "$(calls)"
assert_eq "dry runs leave no scratch directory" "" "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'haseen-omarchy-theme.*' 2>/dev/null)"

capture "$OMA/omarchy-theme-set-claude"
assert_status "set-claude" 0 "$STATUS"
f="$HOME/.claude/themes/haseen.json"
assert_eq "claude.json renders to valid JSON" "valid" "$(valid_json "$f")"
assert_eq "claude theme is named haseen" "haseen" "$(jq -r .name "$f" 2>/dev/null)"
assert_eq "claude.json has no placeholder left" "" "$(grep -o '{{[^}]*}}' "$f" 2>/dev/null || true)"
assert_contains "claude.json carries the fixture's colours" "$(<"$f")" "#5fafd7"
assert_eq "settings.json untouched without --activate" '{"theme": "dark", "keep": 1}' "$(<"$HOME/.claude/settings.json")"
capture "$OMA/omarchy-theme-set-claude" --activate
assert_eq "--activate sets custom:haseen and keeps the rest" "custom:haseen 1" "$(jq -r '"\(.theme) \(.keep)"' "$HOME/.claude/settings.json")"

capture "$OMA/omarchy-theme-set-pi"
f="$HOME/.pi/agent/themes/haseen.json"
assert_eq "pi.json renders to valid JSON" "valid" "$(valid_json "$f")"
assert_eq "pi theme is named haseen" "haseen" "$(jq -r .name "$f" 2>/dev/null)"
assert_eq "pi.json has no placeholder left" "" "$(grep -o '{{[^}]*}}' "$f" 2>/dev/null || true)"
assert_eq "pi settings.json not created without --activate" "no" "$([[ -e $HOME/.pi/agent/settings.json ]] && echo yes || echo no)"

capture "$OMA/omarchy-theme-set-t3code"
f="$HOME/.t3/userdata/themes/haseen.json"
assert_eq "t3code.json renders to valid JSON" "valid" "$(valid_json "$f")"
assert_eq "t3code theme is named haseen, dark" "haseen dark" "$(jq -r '"\(.name) \(.appearance)"' "$f" 2>/dev/null)"
assert_eq "t3code accent from the fixture" "#5fafd7" "$(jq -r .accent "$f" 2>/dev/null)"

capture "$OMA/omarchy-theme-set-hermes"
assert_status "set-hermes" 0 "$STATUS"
f="$HOME/.hermes/skins/haseen.yaml"
assert_contains "hermes skin is named haseen" "$(cat "$f" 2>/dev/null)" "name: haseen"
assert_eq "hermes skin has no placeholder left" "" "$(grep -o '{{[^}]*}}' "$f" 2>/dev/null || true)"
assert_eq "every Hermes profile gets the skin" "yes" "$(cmp -s "$f" "$HOME/.hermes/profiles/work/skins/haseen.yaml" && echo yes)"

capture "$OMA/omarchy-theme-set-obsidian"
assert_status "set-obsidian" 0 "$STATUS"
assert_contains "obsidian: the native app's vault gets the theme" "$(cat "$SANDBOX/vault/.obsidian/themes/haseen/theme.css" 2>/dev/null)" "#5fafd7"
assert_eq "obsidian: the Flatpak's vault too" "yes" "$(cmp -s "$SANDBOX/vault/.obsidian/themes/haseen/theme.css" "$SANDBOX/flatvault/.obsidian/themes/haseen/theme.css" && echo yes)"
assert_eq "obsidian manifest names haseen" "haseen" "$(jq -r .name "$SANDBOX/vault/.obsidian/themes/haseen/manifest.json" 2>/dev/null)"
assert_eq "obsidian: the vault's chosen theme is left alone" "no" "$([[ -e $SANDBOX/vault/.obsidian/appearance.json ]] && echo yes || echo no)"

capture "$OMA/omarchy-theme-set-keyboard-asus-rog"
assert_eq "asus-rog: aura static colour = rendered keyboard.rgb (accent)" "asusctl aura effect static -c 5fafd7" "$(calls)"
: >"$CALLS"
capture "$OMA/omarchy-theme-set-keyboard-f16"
# colorsys.rgb_to_hsv(0x5f, 0xaf, 0xd7 /255): h*255 = 141, s*255 = 142.
assert_eq "f16: QMK effect, hue, saturation, brightness, save" \
    "qmk_hid via --rgb-effect 1"$'\n'"qmk_hid via --rgb-hue 141"$'\n'"qmk_hid via --rgb-saturation 142"$'\n'"qmk_hid via --rgb-brightness 100"$'\n'"qmk_hid via --save" "$(calls)"
: >"$CALLS"
capture "$OMA/omarchy-theme-set-keyboard" --dry-run
assert_contains "set-keyboard runs the ROG helper" "$OUTPUT" "DRYRUN: asusctl aura effect static -c 5fafd7"
assert_contains "set-keyboard runs the F16 helper" "$OUTPUT" "DRYRUN: qmk_hid via --save"

capture env DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent "$OMA/omarchy-theme-set-gnome"
assert_eq "gnome: dark scheme, Adwaita-dark" \
    "gsettings set org.gnome.desktop.interface color-scheme prefer-dark"$'\n'"gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark" "$(calls)"
: >"$CALLS"
capture env -u DBUS_SESSION_BUS_ADDRESS "$OMA/omarchy-theme-set-gnome"
assert_eq "gnome: nothing without a session bus" "" "$(calls)"

# --- browser policy -----------------------------------------------------------------
mkdir -p "$ROOT/etc/chromium/policies/managed" "$ROOT/etc/brave/policies/managed"
chmod 0755 "$ROOT/etc/chromium/policies/managed"
chmod 0777 "$ROOT/etc/brave/policies/managed"
capture "$OMA/omarchy-theme-set-browser" --dry-run
assert_dry_pure "set-browser" "$OUTPUT"
assert_contains "browser: the theme's background as the policy colour" "$OUTPUT" \
    'DRYRUN: write /etc/chromium/policies/managed/color.json (mode 0644):
    | {"BrowserThemeColor": "#16161e", "BrowserColorScheme": "device"}'
assert_contains "browser: a directory others can write is skipped" "$OUTPUT" "skipping /etc/brave/policies/managed"
assert_not_contains "browser: a missing directory is never created" "$OUTPUT" "/etc/opt/chrome"
assert_status "browser: a skipped directory is a failure" 1 "$STATUS"
for bad_colour in 16161E "#16161e" 16161 zzzzzz; do
    capture "$OMA/omarchy-theme-set-browser-policy" "$bad_colour" --dry-run
    assert_status "browser-policy refuses '$bad_colour'" 1 "$STATUS"
    assert_not_contains "browser-policy '$bad_colour' writes nothing" "$OUTPUT" "DRYRUN"
done
printf '{"BrowserThemeColor": "#16161e", "BrowserColorScheme": "device"}\n' >"$ROOT/etc/chromium/policies/managed/color.json"
chmod 0755 "$ROOT/etc/brave/policies/managed"
capture "$OMA/omarchy-theme-set-browser-policy" 16161e --dry-run
assert_not_contains "browser-policy: an unchanged file is not rewritten" "$OUTPUT" "chromium"
assert_contains "browser-policy: the other directory is" "$OUTPUT" "DRYRUN: write /etc/brave/policies/managed/color.json"
assert_status "browser-policy" 0 "$STATUS"

# --- tmux and foot ------------------------------------------------------------------
: >"$SANDBOX/tmux-up"
printf '/dev/pts/77\n' >"$SANDBOX/tmux-panes"
stub ps "echo ' 4242424'"
capture env -u HASEEN_SYSROOT "$OMA/omarchy-theme-set-tmux" --dry-run
assert_dry_pure "set-tmux" "$OUTPUT"
assert_contains "tmux: COLORFGBG for a dark theme" "$OUTPUT" "DRYRUN: tmux set-environment -g COLORFGBG 15;0"
assert_contains "tmux: per session too" "$OUTPUT" "DRYRUN: tmux set-environment -t s0 COLORFGBG 15;0"
assert_contains "tmux: window style" "$OUTPUT" "DRYRUN: tmux set-option -g window-style fg=#d0d0d8,bg=#16161e"
assert_contains "tmux: cursor colour" "$OUTPUT" "DRYRUN: tmux set-option -g cursor-colour #eeeef4"
assert_contains "tmux: palette to every pane" "$OUTPUT" "DRYRUN: write the theme palette (OSC sequences) to /dev/pts/77"
assert_contains "tmux: SIGWINCH to the pane's foreground group" "$OUTPUT" "DRYRUN: kill -WINCH -- -4242424"
assert_contains "tmux: clients refreshed" "$OUTPUT" "DRYRUN: tmux refresh-client -t /dev/pts/77"
assert_eq "tmux dry run changes nothing" "" "$(calls)"
: >"$SANDBOX/tmux-panes"
capture env -u HASEEN_SYSROOT "$OMA/omarchy-theme-set-tmux"
assert_contains "tmux: the server gets the window style" "$(calls)" "tmux set-option -g window-style fg=#d0d0d8,bg=#16161e"
rm -f "$SANDBOX/tmux-up"
: >"$CALLS"
capture env -u HASEEN_SYSROOT "$OMA/omarchy-theme-set-tmux"
assert_eq "tmux: nothing without a server" "" "$OUTPUT$(calls)"
capture "$OMA/omarchy-theme-set-tmux" --dry-run
assert_eq "tmux: nothing on a fixture" "" "$OUTPUT"
# A "foot" whose only child writes to a file, not a terminal.
sleep 30 >"$SANDBOX/child.out" &
child=$!
stub pgrep "case \"\$*\" in '-x foot') echo 1 ;; '-P 1') echo $child ;; esac"
capture env -u HASEEN_SYSROOT "$OMA/omarchy-theme-set-foot" --dry-run
kill "$child" 2>/dev/null || true
wait "$child" 2>/dev/null || true
assert_dry_pure "set-foot" "$OUTPUT"
assert_eq "foot: only a child on a pts gets the palette" "" "$OUTPUT"
capture "$OMA/omarchy-theme-set-foot"
assert_eq "foot: nothing on a fixture" "" "$OUTPUT"

# --- a theme with unresolved colours is not published --------------------------------
box omarchy-theme-unresolved
fixture_theme fixture-night
mkdir -p "$HOME/.config/haseen/themed" "$HOME/.t3/userdata/themes" "$HOME/.claude"
printf '{"name": "haseen", "accent": "{{ no_such_colour }}"}\n' >"$HOME/.config/haseen/themed/t3code.json.tpl"
printf '{"old": true}\n' >"$HOME/.t3/userdata/themes/haseen.json"
capture "$OMA/omarchy-theme-set-t3code"
assert_contains "t3code: an unresolved render is skipped" "$OUTPUT" "unresolved colors"
assert_eq "t3code: the previous file stays" '{"old": true}' "$(<"$HOME/.t3/userdata/themes/haseen.json")"
printf '{"name": "mine", "background": "{{ background }}"}\n' >"$HOME/.config/haseen/themed/claude.json.tpl"
capture "$OMA/omarchy-theme-set-claude"
assert_eq "claude: the user's own template wins" "mine #16161e" "$(jq -r '"\(.name) \(.background)"' "$HOME/.claude/themes/haseen.json" 2>/dev/null)"

# --- VS Code and friends -------------------------------------------------------------
box omarchy-theme-vscode
fixture_theme fixture-night
EXT_DIRS=("$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" "$HOME/.vscode-oss/extensions" "$HOME/.cursor/extensions")
capture "$OMA/omarchy-theme-set-vscode"
assert_status "set-vscode" 0 "$STATUS"
missing=""
for base in "${EXT_DIRS[@]}"; do
    ext="$base/haseen-theme"
    [[ $(valid_json "$ext/themes/haseen-color-theme.json") == valid ]] || missing+="$base(theme) "
    [[ $(jq -r '.contributes.themes[0] | "\(.label) \(.uiTheme)"' "$ext/package.json" 2>/dev/null) == "haseen vs-dark" ]] || missing+="$base(package) "
done
assert_eq "every installed editor gets the local haseen extension" "" "$missing"
assert_eq "no editor's extensions.json is written without --activate" "" "$(find "${EXT_DIRS[@]}" -name extensions.json)"
assert_contains "it says how to register the extension" "$OUTPUT" "omarchy-theme-set-vscode --activate' once"
f="$HOME/.vscode/extensions/haseen-theme/themes/haseen-color-theme.json"
assert_eq "vscode theme: named haseen, dark, fixture background" "haseen dark #16161e" "$(jq -r '"\(.name) \(.type) \(.colors["editor.background"])"' "$f" 2>/dev/null)"
assert_eq "vscode theme has no placeholder left" "" "$(grep -o '{{[^}]*}}' "$f" 2>/dev/null || true)"
assert_eq "no settings.json is written without --activate" "" "$(find "$HOME/.config" -name settings.json)"
assert_eq "no extension is installed without --activate" "" "$(calls)"

# VS Code's own bookkeeping is the user's: without --activate an obsolete mark
# stays as it is.
printf '{"local.haseen-theme-1.0.0": true, "other.ext-2.0.0": true}\n' >"$HOME/.vscode/extensions/.obsolete"
printf '{"local.haseen-theme-1.0.0": true}\n' >"$HOME/.cursor/extensions/.obsolete"
capture "$OMA/omarchy-theme-set-vscode"
assert_eq ".obsolete is not edited without --activate" '{"local.haseen-theme-1.0.0":true,"other.ext-2.0.0":true}' \
    "$(jq -c . "$HOME/.vscode/extensions/.obsolete")"
assert_eq "nor removed" "yes" "$([[ -e $HOME/.cursor/extensions/.obsolete ]] && echo yes || echo no)"

# --activate edits settings.json as text: JSONC comments and commas survive.
code_settings="$HOME/.config/Code/User/settings.json"
cursor_settings="$HOME/.config/Cursor/User/settings.json"
mkdir -p "$(dirname "$code_settings")" "$(dirname "$cursor_settings")"
printf '{\n  // my editor\n  "editor.fontSize": 14,\n}\n' >"$code_settings"
printf '{\n  "workbench.colorTheme": "Default Dark+",\n  "x": 1\n}\n' >"$cursor_settings"
ln -s "$cursor_settings" "$SANDBOX/cursor-link"
before="$(tree)"
capture "$OMA/omarchy-theme-set-vscode" --activate --dry-run
assert_dry_pure "set-vscode --activate" "$OUTPUT"
assert_eq "--activate --dry-run writes nothing" "$before" "$(tree)"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_status "set-vscode --activate" 0 "$STATUS"
missing=""
for base in "${EXT_DIRS[@]}"; do
    ext="$base/haseen-theme"
    [[ $(jq -r --arg p "$ext" '[.[] | select(.identifier.id == "local.haseen-theme" and .location.fsPath == $p)] | length' "$base/extensions.json" 2>/dev/null) == 1 ]] || missing+="$base "
done
assert_eq "--activate registers the extension with every editor" "" "$missing"
assert_eq "--activate lifts the obsolete mark, other entries stay" '{"other.ext-2.0.0":true}' "$(jq -c . "$HOME/.vscode/extensions/.obsolete")"
assert_eq "an emptied .obsolete is removed" "no" "$([[ -e $HOME/.cursor/extensions/.obsolete ]] && echo yes || echo no)"
before="$(tree)"
capture "$OMA/omarchy-theme-set-vscode" --dry-run
assert_eq "a re-run of a registered extension has nothing to change" "" "$OUTPUT"
capture "$OMA/omarchy-theme-set-vscode"
assert_eq "a re-run writes nothing" "$before" "$(tree)"
assert_eq "the extension is registered once" "1" "$(jq length "$HOME/.vscode/extensions/extensions.json")"
assert_eq "an added colorTheme keeps the user's comment and keys" \
    $'{ "workbench.colorTheme": "haseen",\n  // my editor\n  "editor.fontSize": 14,\n}' "$(<"$code_settings")"
assert_eq "an existing colorTheme is replaced in place" \
    $'{\n  "workbench.colorTheme": "haseen",\n  "x": 1\n}' "$(<"$cursor_settings")"
assert_eq "a missing settings.json is created" "haseen" "$(jq -r '."workbench.colorTheme"' "$HOME/.config/VSCodium/User/settings.json" 2>/dev/null)"
capture "$OMA/omarchy-theme-set-vscode" --activate --dry-run
assert_eq "a re-activation has nothing to change" "" "$OUTPUT"
insiders_settings="$HOME/.config/Code - Insiders/User/settings.json"
rm -f "$insiders_settings"
ln -s "$SANDBOX/dots/settings.json" "$insiders_settings"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_contains "a dangling settings.json link is reported" "$OUTPUT" "links to nothing: left alone"
assert_eq "and its target is never created" "no" "$([[ -e $SANDBOX/dots ]] && echo yes || echo no)"

# A stock theme may name its own VS Code theme: --activate installs it (once).
cp "$HASEEN_PATH/themes/tokyo-night/vscode.json" "$CUR/theme/vscode.json"
want_name="$(jq -r .name "$CUR/theme/vscode.json")"
want_ext="$(jq -r .extension "$CUR/theme/vscode.json")"
mkdir -p "$HOME/.cursor/extensions/${want_ext,,}-1.2.3"
: >"$CALLS"
capture "$OMA/omarchy-theme-set-vscode"
assert_eq "without --activate the theme's extension is not installed" "" "$(calls)"
capture "$OMA/omarchy-theme-set-vscode" --activate --dry-run
assert_dry_pure "set-vscode --activate with a vscode.json" "$OUTPUT"
assert_contains "the dry run plans the install" "$OUTPUT" "DRYRUN: code --install-extension $want_ext"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_contains "--activate installs the theme's extension" "$(calls)" "code --install-extension $want_ext"
assert_not_contains "an editor that has it is not asked again" "$(calls)" "cursor --install-extension"
assert_eq "colorTheme names the theme's own theme" "$want_name" "$(sed -n 's/.*"workbench.colorTheme": "\([^"]*\)".*/\1/p' "$code_settings")"
assert_eq "in every editor" "$want_name" "$(sed -n 's/.*"workbench.colorTheme": "\([^"]*\)".*/\1/p' "$cursor_settings")"
printf '{"name": "Evil\\" , \\"x", "extension": "a;rm -rf ~"}\n' >"$CUR/theme/vscode.json"
: >"$CALLS"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_eq "a malformed extension ID is never installed" "" "$(calls)"
assert_eq "a label that is not a JSON string falls back to haseen" "haseen" "$(sed -n 's/.*"workbench.colorTheme": "\([^"]*\)".*/\1/p' "$code_settings")"

box omarchy-theme-vscode-more
fixture_theme day light
mkdir -p "$TOGGLES"
: >"$TOGGLES/skip-cursor-theme-changes"
mkdir -p "$ROOT/var/lib/flatpak/app/com.vscodium.codium"
cp "$HASEEN_PATH/themes/tokyo-night/vscode.json" "$CUR/theme/vscode.json"
stub flatpak "echo \"flatpak \$*\" >>'$CALLS'; exit 1"
capture "$OMA/omarchy-theme-set-vscode" --activate
assert_eq "a light theme is a light VS Code theme" "vs" "$(jq -r '.contributes.themes[0].uiTheme' "$HOME/.vscode/extensions/haseen-theme/package.json" 2>/dev/null)"
assert_eq "the skip toggle leaves Cursor alone" "no" "$([[ -e $HOME/.cursor || -e $HOME/.config/Cursor ]] && echo yes || echo no)"
flat="$HOME/.var/app/com.vscodium.codium/config/VSCodium/User/settings.json"
assert_contains "a Flatpak VSCodium is asked through flatpak run" "$(calls)" "flatpak run --command=codium com.vscodium.codium --install-extension $(jq -r .extension "$CUR/theme/vscode.json")"
assert_eq "a failed install selects haseen instead" "haseen" "$(jq -r '."workbench.colorTheme"' "$flat" 2>/dev/null)"
assert_contains "and says so" "$OUTPUT" "selecting haseen instead"

# --- legacy themes: colors.toml from alacritty.toml ---------------------------------
box omarchy-theme-alacritty
legacy="$SANDBOX/legacy"
mkdir -p "$legacy"
cat >"$legacy/alacritty.toml" <<'EOF'
[colors.primary]
background = "#101010"
foreground = '0xE0E0E0'

[colors.normal]
black = "#000000"
red = "#aa0000"
green = "#00aa00"
yellow = "#aaaa00"
blue = "#0000aa"
magenta = "#aa00aa"
cyan = "#00aaaa"
white = "#aaaaaa"

[colors.bright]
red = "#ff5555"
EOF
capture "$OMA/omarchy-theme-colors-from-alacritty" "$legacy" --dry-run
assert_dry_pure "colors-from-alacritty" "$OUTPUT"
assert_contains "colors-from-alacritty plans colors.toml" "$OUTPUT" "DRYRUN: write $legacy/colors.toml:"
assert_eq "--dry-run writes no colors.toml" "no" "$([[ -e $legacy/colors.toml ]] && echo yes || echo no)"
capture "$OMA/omarchy-theme-colors-from-alacritty" "$legacy"
toml="$(cat "$legacy/colors.toml" 2>/dev/null)"
assert_contains "accent is normal blue" "$toml" 'accent = "#0000aa"'
assert_contains "selection falls back to the foreground" "$toml" 'selection = "#e0e0e0"'
assert_contains "color0 is the background" "$toml" 'color0 = "#101010"'
assert_contains "color7 is the foreground" "$toml" 'color7 = "#e0e0e0"'
assert_contains "a bright colour that is set" "$toml" 'color9 = "#ff5555"'
assert_contains "a missing bright colour falls back to the normal one" "$toml" 'color12 = "#0000aa"'
printf 'accent = "#123456"\n' >"$legacy/colors.toml"
capture "$OMA/omarchy-theme-colors-from-alacritty" "$legacy"
assert_eq "an existing colors.toml is left alone" 'accent = "#123456"' "$(<"$legacy/colors.toml")"
mkdir -p "$SANDBOX/partial"
printf '[colors.normal]\nblack = "#000000"\n' >"$SANDBOX/partial/alacritty.toml"
capture "$OMA/omarchy-theme-colors-from-alacritty" "$SANDBOX/partial"
assert_contains "too few colours: a warning" "$OUTPUT" "skipping generation"
assert_eq "too few colours: nothing written" "no" "$([[ -e $SANDBOX/partial/colors.toml ]] && echo yes || echo no)"
capture "$OMA/omarchy-theme-colors-from-alacritty"
assert_status "colors-from-alacritty needs a directory" 1 "$STATUS"

# --- backgrounds -------------------------------------------------------------------
box omarchy-theme-bg
fixture_theme fixture-night
bgdir="$HOME/.config/haseen/backgrounds/fixture-night"
before="$(tree)"
capture "$OMA/omarchy-theme-bg-install" --dry-run
assert_dry_pure "bg-install" "$OUTPUT"
assert_eq "bg-install --dry-run plans the folder and the opener" "DRYRUN: mkdir -p -- $bgdir"$'\n'"DRYRUN: xdg-open $bgdir" "$OUTPUT"
assert_eq "bg-install --dry-run writes nothing" "$before" "$(tree)"
capture "$OMA/omarchy-theme-bg-install"
assert_eq "bg-install creates the theme's folder" "yes" "$([[ -d $bgdir ]] && echo yes)"
assert_eq "bg-install opens it" "xdg-open $bgdir" "$(calls)"
capture "$OMA/omarchy-theme-bg-install" extra
assert_status "bg-install takes no argument" 1 "$STATUS"
capture "$OMA/omarchy-theme-bg-current"
assert_eq "bg-current: no background yet" "Unknown" "$OUTPUT"
img_png "$bgdir/2-blue-hour.png" blue
capture haseen theme bg set "$bgdir/2-blue-hour.png"
assert_status "the fixture background is set" 0 "$STATUS"
capture "$OMA/omarchy-theme-bg-current"
assert_eq "bg-current prettifies the image's name" "Blue Hour" "$OUTPUT"
assert_status "bg-current exits 0" 0 "$STATUS"

recorder haseen-shell-ipc
capture fake omarchy-theme-bg-switcher
assert_eq "bg-switcher opens haseen's background panel" "haseen-shell-ipc [panel] [toggle] [haseen.background]" "$(flog)"
assert_eq "bg-switcher prints nothing (callers set nothing)" "" "$OUTPUT"
assert_status "bg-switcher" 0 "$STATUS"
: >"$SANDBOX/fake.log"
capture fake omarchy-theme-switcher
assert_eq "theme-switcher opens haseen's theme picker" "haseen-shell-ipc [panel] [toggle] [haseen.themepicker]" "$(flog)"
assert_eq "theme-switcher prints nothing" "" "$OUTPUT"
: >"$SANDBOX/fake.log"
capture fake omarchy-theme-switcher --preload
assert_eq "--preload opens nothing" "" "$(flog)"
assert_status "--preload exits 0" 0 "$STATUS"
recorder haseen-shell-ipc 'exit 3'
capture fake omarchy-theme-bg-switcher
assert_status "bg-switcher fails when the shell does not answer" 3 "$STATUS"

# --- install, refresh, remove, extras, update -----------------------------------------
box omarchy-theme-manage
recorder haseen-theme-install
capture fake omarchy-theme-install https://example.invalid/theme.git --dry-run
assert_eq "theme-install passes the URL on, replacing as Omarchy does" "haseen-theme-install [https://example.invalid/theme.git] [--yes] [--dry-run]" "$(flog)"
: >"$SANDBOX/fake.log"
capture fake omarchy-theme-install
assert_status "theme-install without a URL and a terminal fails" 1 "$STATUS"
assert_eq "theme-install without a URL installs nothing" "" "$(flog)"
capture fake omarchy-theme-install a b
assert_status "theme-install takes one URL" 1 "$STATUS"

recorder haseen-theme-current 'echo fixture-night'
recorder haseen-theme-set
: >"$SANDBOX/fake.log"
capture fake omarchy-theme-refresh --dry-run
assert_eq "theme-refresh sets the current theme again" "haseen-theme-current"$'\n'"haseen-theme-set [fixture-night] [--dry-run]" "$(flog)"
recorder haseen-theme-current 'exit 1'
: >"$SANDBOX/fake.log"
capture fake omarchy-theme-refresh
assert_status "theme-refresh without a theme does nothing" 0 "$STATUS"
assert_not_contains "and sets nothing" "$(flog)" "haseen-theme-set"

themes="$HOME/.config/haseen/themes"
mkdir -p "$themes/gitty/.git" "$themes/plain" "$SANDBOX/worktree/.git"
printf '%s\n' "$FIXTURE_COLORS" >"$themes/plain/colors.toml"
ln -s "$SANDBOX/worktree" "$themes/linked"
capture "$OMA/omarchy-theme-extras"
assert_eq "theme-extras lists the git-installed theme only" "$themes/gitty" "$OUTPUT"
assert_status "theme-extras" 0 "$STATUS"

mkdir -p "$CUR"
echo gitty >"$CUR/theme.name"
before="$(tree)"
capture "$OMA/omarchy-theme-update" --dry-run
assert_dry_pure "theme-update" "$OUTPUT"
assert_contains "theme-update pulls each git theme" "$OUTPUT" "DRYRUN: git -C $themes/gitty pull --ff-only"
assert_not_contains "theme-update leaves your own themes" "$OUTPUT" "plain"
assert_contains "theme-update plans applying the current theme again" "$OUTPUT" "haseen-theme-set gitty (when the pull changed it)"
assert_eq "theme-update --dry-run changes nothing" "$before" "$(tree)"
stub git "echo \"git \$*\" >>'$CALLS'; case \"\$*\" in *rev-parse*) echo 0123abc ;; esac; exit 0"
capture "$OMA/omarchy-theme-update"
assert_status "theme-update" 0 "$STATUS"
assert_contains "theme-update ran the pull" "$(calls)" "git -C $themes/gitty pull --ff-only"
assert_eq "an unchanged theme is not applied again" "Updating: gitty" "$OUTPUT"
stub git "case \"\$*\" in *pull*) exit 1 ;; esac; echo 0123abc"
capture "$OMA/omarchy-theme-update"
assert_status "a pull that fails is a failure" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "could not update gitty"

recorder haseen-notification-send
: >"$SANDBOX/fake.log"
before="$(tree)"
capture fake omarchy-theme-remove plain --dry-run
assert_dry_pure "theme-remove" "$OUTPUT"
assert_contains "theme-remove --dry-run plans the removal" "$OUTPUT" "DRYRUN: rm -rf -- $themes/plain"
assert_eq "theme-remove --dry-run removes nothing" "$before" "$(tree)"
capture fake omarchy-theme-remove plain
assert_status "theme-remove" 0 "$STATUS"
assert_eq "theme-remove deletes the theme" "no" "$([[ -e $themes/plain ]] && echo yes || echo no)"
assert_eq "theme-remove says so" "haseen-notification-send [Theme removed] [plain]" "$(flog)"
capture fake omarchy-theme-remove tokyo-night
assert_status "a stock theme cannot be removed" 1 "$STATUS"
assert_contains "and says it is haseen's" "$OUTPUT" "stock haseen theme"
capture fake omarchy-theme-remove ../haseen
assert_status "a name that leaves the themes directory is refused" 1 "$STATUS"
assert_eq "the themes directory is intact" "yes" "$([[ -d $themes && -d $HOME/.config/haseen ]] && echo yes)"
capture fake omarchy-theme-remove gitty --dry-run
assert_contains "removing the current theme warns" "$OUTPUT" "is the current theme"
recorder haseen-menu-select 'echo linked'
capture fake omarchy-theme-remove
assert_status "theme-remove picks from the menu" 0 "$STATUS"
assert_eq "a linked theme: the link goes, its target stays" "gone kept" \
    "$([[ -e $themes/linked || -L $themes/linked ]] && echo kept || echo gone) $([[ -d $SANDBOX/worktree/.git ]] && echo kept || echo gone)"
capture fake omarchy-theme-remove gitty
assert_eq "the current theme is removed all the same" "no" "$([[ -e $themes/gitty ]] && echo yes || echo no)"
capture "$OMA/omarchy-theme-extras"
assert_status "theme-extras exits 1 when there are none" 1 "$STATUS"
