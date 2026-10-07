# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 067: `haseen theme generate` and the haseen.themegen panel. matugen is
# a stub that prints JSON recorded from matugen 4.2.0 (tests/fixtures/matugen/:
# a tonal-spot scheme of one wallpaper, dark and light, and the `matugen
# color` run for its terminal hues) and logs its argv. Checked: the Material
# roles land on the right colors.toml keys, plan 064's contrast floors hold
# (and move only what falls short), a dry run writes nothing, the theme
# renders through `haseen theme set`, names that are not ours are refused, and
# the panel's model runs under the Qt JS engine against the CLI's own output.

FIX="$FIXTURES/matugen"
PLUGIN="$HASEEN_PATH/shell/plugins/haseen.themegen"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox themegen
LOG="$SANDBOX/matugen.log"
# MATUGEN_IMAGE_JSON replaces the image run's output; MATUGEN_FAIL makes the
# stub fail the way matugen reports an error.
stub matugen "printf '%s\n' \"\$*\" >>'$LOG'
if [ -n \"\${MATUGEN_FAIL:-}\" ]; then printf 'Error: \n   0: %s\n' \"\$MATUGEN_FAIL\" >&2; exit 1; fi
kind=\$1 mode=dark
while [ \$# -gt 0 ]; do [ \"\$1\" = -m ] && mode=\$2; shift; done
if [ \"\$kind\" = image ] && [ -n \"\${MATUGEN_IMAGE_JSON:-}\" ]; then cat \"\$MATUGEN_IMAGE_JSON\"; else cat '$FIX'/\$kind-\$mode.json; fi"

# Any bytes do: the stub never reads the image, haseen only copies it.
img="$SANDBOX/Blue_Hour (2).PNG"
printf 'not really a png\n' >"$img"
other="$SANDBOX/dusk.jpg"
printf 'another picture\n' >"$other"
THEMES="$XDG_CONFIG_HOME/haseen/themes"
role() { jq -r --arg k "$1" '.colors[$k].default.color' "$FIX/image-$2.json"; }
hue() { jq -r --arg k "$1" '.colors[$k].default.color' "$FIX/color-$2.json"; }
contrast() { # A B -> WCAG ratio x100, theme-lib's own measure
    (
        # shellcheck source=../share/haseen/lib/common.sh
        source "$HASEEN_PATH/lib/common.sh"
        # shellcheck source=../share/haseen/layers/theme/theme-lib.sh
        source "$HASEEN_PATH/layers/theme/theme-lib.sh"
        _theme_contrast "$1" "$2"
        echo "$REPLY"
    )
}

# --- help and argument checks ----------------------------------------------------
capture haseen theme generate --help
assert_status "--help" 0 "$STATUS"
assert_contains "--help names the schemes" "$OUTPUT" "tonal-spot content expressive"
assert_contains "--help names the panel" "$OUTPUT" "haseen.themegen"

capture haseen theme generate "$SANDBOX/missing.png" --json
assert_status "a missing image is an error" 1 "$STATUS"
printf 'text\n' >"$SANDBOX/notes.txt"
capture haseen theme generate "$SANDBOX/notes.txt" --json
assert_status "a file that is not an image is refused" 1 "$STATUS"
capture haseen theme generate "$img" --scheme nonsense --json
assert_status "an unknown scheme is refused" 1 "$STATUS"
assert_contains "and the schemes are listed" "$OUTPUT" "tonal-spot"
capture haseen theme generate "$img" --mode dim --json
assert_status "a mode other than dark/light is refused" 1 "$STATUS"
capture haseen theme generate "$img" --name ../escape --json
assert_status "a name that could leave the themes dir is refused" 1 "$STATUS"
assert_eq "argument errors never ran matugen" "" "$(cat "$LOG" 2>/dev/null || true)"

# --- colour mapping ------------------------------------------------------------
capture haseen theme generate "$img" --json
assert_status "--json previews" 0 "$STATUS"
J="$OUTPUT"
c() { jq -r --arg k "$1" '.colors[$k]' <<<"$J"; }
assert_eq "the default name is the file name, slugged" "blue-hour-2" "$(jq -r .name <<<"$J")"
assert_eq "a new name" "new" "$(jq -r .target <<<"$J")"
assert_eq "tonal-spot, dark by default" "tonal-spot dark" "$(jq -r '.scheme + " " + .mode' <<<"$J")"
assert_eq "the source colour is matugen's" "$(role source_color dark)" "$(jq -r .source <<<"$J")"
assert_eq "background = surface" "$(role surface dark)" "$(c background)"
assert_eq "foreground = on_surface" "$(role on_surface dark)" "$(c foreground)"
assert_eq "accent = primary" "$(role primary dark)" "$(c accent)"
assert_eq "selection = secondary_container" "$(role secondary_container dark)" "$(c selection)"
assert_eq "selection_background follows it" "$(c selection)" "$(c selection_background)"
assert_eq "selection_foreground = on_secondary_container" "$(role on_secondary_container dark)" "$(c selection_foreground)"
assert_eq "muted = outline" "$(role outline dark)" "$(c muted)"
assert_eq "dark_foreground = on_surface_variant" "$(role on_surface_variant dark)" "$(c dark_foreground)"
assert_eq "lighter_background = surface_container_high" "$(role surface_container_high dark)" "$(c lighter_background)"
assert_eq "bright_foreground = neutral tone 95 in dark mode" \
    "$(jq -r '.palettes.neutral["95"].color' "$FIX/image-dark.json")" "$(c bright_foreground)"
for h in red yellow green cyan blue magenta; do
    assert_eq "$h is matugen's tonal-spot $h" "$(hue "$h" dark)" "$(c "$h")"
done
# Halfway from red (tone 80) to on_red_container (tone 90): #ffb3ae + #ffdad7.
assert_eq "bright_red is halfway to its on-container tone" "#ffc7c3" "$(c bright_red)"
assert_eq "every colour is #rrggbb" "22" "$(jq '[.colors[] | select(test("^#[0-9a-f]{6}$"))] | length' <<<"$J")"
assert_eq "a readable palette is not clamped" "[]" "$(jq -c .clamped <<<"$J")"
assert_eq "--json writes nothing" "" "$(ls "$THEMES" 2>/dev/null || true)"

first="$(sed -n 1p "$LOG")"
assert_contains "matugen reads the image" "$first" "image $img -t scheme-tonal-spot -m dark"
assert_contains "matugen runs as a dry run (JSON only)" "$first" "--json hex --dry-run"
assert_contains "with haseen's config, never the user's" "$first" "-c $HASEEN_PATH/layers/theme/matugen.toml"
assert_contains "without the interactive colour prompt" "$first" "--source-color-index 0"
assert_contains "the hues come from the source colour, tonal-spot" "$(sed -n 2p "$LOG")" \
    "color hex $(role source_color dark) -t scheme-tonal-spot -m dark --json hex --dry-run"

: >"$LOG"
capture haseen theme generate "$img" --scheme scheme-expressive --json
assert_status "a scheme- prefix is accepted" 0 "$STATUS"
assert_contains "the scheme reaches matugen" "$(sed -n 1p "$LOG")" "-t scheme-expressive"
assert_contains "the hues stay tonal-spot under any scheme" "$(sed -n 2p "$LOG")" "-t scheme-tonal-spot"

capture haseen theme generate "$img" --mode light --json
L="$OUTPUT"
assert_eq "light mode: background = light surface" "$(role surface light)" "$(jq -r .colors.background <<<"$L")"
assert_eq "light mode: bright_foreground = neutral tone 5" \
    "$(jq -r '.palettes.neutral["5"].color' "$FIX/image-light.json")" "$(jq -r .colors.bright_foreground <<<"$L")"
assert_eq "light mode: red is the light tone" "$(hue red light)" "$(jq -r .colors.red <<<"$L")"

# --- the readability clamp (plan 064 floors) -----------------------------------
# A scheme gone wrong: text, accent and selection all close to the surface.
bad="$SANDBOX/low-contrast.json"
jq '.colors.on_surface.default.color = "#3a3030" | .colors.primary.default.color = "#2a2020"
    | .colors.secondary_container.default.color = "#d0c0c0"' "$FIX/image-dark.json" >"$bad"
capture env MATUGEN_IMAGE_JSON="$bad" haseen theme generate "$img" --json
assert_status "an unreadable scheme still previews" 0 "$STATUS"
B="$OUTPUT"
bg="$(jq -r .colors.background <<<"$B")"
fg="$(jq -r .colors.foreground <<<"$B")"
assert_eq "the background is never moved" "$(role surface dark)" "$bg"
assert_eq "foreground, accent and selection were clamped" "foreground accent selection" \
    "$(jq -r '[.clamped[] | split(" ")[0]] | join(" ")' <<<"$B")"
assert_eq "foreground reaches 4.5:1 on the background" 1 "$(($(contrast "$fg" "$bg") >= 450))"
assert_eq "accent reaches 3:1 on the background" 1 "$(($(contrast "$(jq -r .colors.accent <<<"$B")" "$bg") >= 300))"
assert_eq "foreground text reaches 4.5:1 on the selection" 1 \
    "$(($(contrast "$fg" "$(jq -r .colors.selection <<<"$B")") >= 450))"
assert_contains "the move is reported with both ratios" "$(jq -r '.clamped[0]' <<<"$B")" ":1 -> "
assert_eq "the foreground moved toward white on a dark surface" 1 \
    "$((16#${fg:1:2} > 16#3a))"

# --- dry run ----------------------------------------------------------------------
capture haseen theme generate "$img" --dry-run
assert_status "a dry run" 0 "$STATUS"
assert_dry_pure "theme generate" "$OUTPUT"
assert_contains "it plans the colors.toml" "$OUTPUT" "DRYRUN: write $THEMES/blue-hour-2/colors.toml (matugen scheme-tonal-spot, dark"
assert_contains "it plans the background copy" "$OUTPUT" "DRYRUN: copy $img to $THEMES/blue-hour-2/backgrounds/blue-hour-2.png"
assert_contains "and the switch" "$OUTPUT" "DRYRUN: haseen theme set blue-hour-2"
assert_eq "a dry run writes no theme" "" "$(ls "$THEMES" 2>/dev/null || true)"
capture haseen theme generate "$img" --dry-run --no-apply
assert_not_contains "--no-apply plans no switch" "$OUTPUT" "theme set"

# --- writing the theme ---------------------------------------------------------------
capture haseen theme generate "$img" --no-apply
assert_status "the theme is written" 0 "$STATUS"
dir="$THEMES/blue-hour-2"
toml="$(cat "$dir/colors.toml")"
assert_eq "it starts with the generator's mark" '# Generated by `haseen theme generate`: matugen scheme-tonal-spot, dark, source '"$(role source_color dark)." \
    "$(sed -n 1p "$dir/colors.toml")"
assert_contains "it carries the mode" "$toml" 'mode = "dark"'
assert_contains "and the mapped keys" "$toml" "background = \"$(role surface dark)\""
assert_contains "and the hues" "$toml" "bright_red = \"#ffc7c3\""
assert_eq "the image is the theme's only background, copied" "blue-hour-2.png" "$(ls "$dir/backgrounds")"
assert_eq "a copy, not a link" "file" "$([[ -L $dir/backgrounds/blue-hour-2.png ]] && echo link || echo file)"
assert_eq "byte for byte" 0 "$(cmp -s "$img" "$dir/backgrounds/blue-hour-2.png" && echo 0 || echo 1)"
assert_eq "no lock or temp file is left in the theme" "backgrounds colors.toml" "$(ls -A "$dir" | tr '\n' ' ' | sed 's/ $//')"

before="$(stat -c %Y.%i "$dir/colors.toml")"
capture haseen theme generate "$img" --no-apply
assert_contains "the same image and scheme report no change" "$OUTPUT" "palette unchanged"
assert_eq "and leave colors.toml alone" "$before" "$(stat -c %Y.%i "$dir/colors.toml")"

capture haseen theme generate "$img" --name blue-hour-2 --json
assert_eq "our earlier theme previews as replaceable" "generated" "$(jq -r .target <<<"$OUTPUT")"
capture haseen theme generate "$other" --name blue-hour-2 --mode light --no-apply
assert_status "it may be regenerated from another image" 0 "$STATUS"
assert_eq "which replaces the background (named after the image)" "dusk.jpg" "$(ls "$dir/backgrounds")"
assert_contains "and the palette" "$(cat "$dir/colors.toml")" 'mode = "light"'

# Names that are not ours.
capture haseen theme generate "$img" --name tokyo-night --no-apply
assert_status "a stock theme's name is refused" 1 "$STATUS"
assert_contains "with the reason" "$OUTPUT" "tokyo-night is a stock theme"
capture haseen theme generate "$img" --name tokyo-night --json
assert_eq "and previews as stock" "stock" "$(jq -r .target <<<"$OUTPUT")"
mkdir -p "$THEMES/mine"
printf 'background = "#000000"\nforeground = "#ffffff"\n' >"$THEMES/mine/colors.toml"
capture haseen theme generate "$img" --name mine --no-apply
assert_status "a theme of the user's own is refused" 1 "$STATUS"
assert_eq "and left as it was" "$(printf 'background = "#000000"\nforeground = "#ffffff"')" "$(cat "$THEMES/mine/colors.toml")"
assert_eq "no background was put in it" "" "$(ls "$THEMES/mine/backgrounds" 2>/dev/null || true)"
capture haseen theme generate "$img" --name mine --json
assert_eq "and previews as taken" "taken" "$(jq -r .target <<<"$OUTPUT")"

# matugen missing or failing.
capture env MATUGEN_FAIL="Failed to open image" haseen theme generate "$img" --json
assert_status "a matugen failure is an error" 1 "$STATUS"
assert_contains "with matugen's cause" "$OUTPUT" "matugen could not read colours from $img: Failed to open image"
capture env PATH="$REPO/bin:/usr/bin:/bin" bash -c \
    'command -v matugen >/dev/null && exit 3; exec haseen theme generate "$1" --json' _ "$img"
if [[ $STATUS == 3 ]]; then
    echo "  skip: matugen is installed on this machine, the missing-matugen message is not exercised" >&2
else
    assert_status "without matugen" 1 "$STATUS"
    assert_contains "it says how to install it" "$OUTPUT" "haseen install package matugen"
fi

# --- applying: an ordinary theme set --------------------------------------------------
capture env HASEEN_THEME_HEADLESS=1 haseen theme generate "$img" --name applied
assert_status "generate and apply" 0 "$STATUS"
current="$XDG_STATE_HOME/haseen/current"
assert_eq "the theme is current" "applied" "$(cat "$current/theme.name")"
assert_eq "the shell tokens come from the image" "$(role surface dark)" "$(jq -r .background "$current/theme/shell.json")"
assert_eq "the image is the background on screen" "$current/theme/backgrounds/blue-hour-2.png" \
    "$(readlink "$current/background")"

# --- the panel: manifest, menu, defaults ------------------------------------------------
capture haseen plugin validate haseen.themegen
assert_status "haseen.themegen validates" 0 "$STATUS"
assert_contains "as a built-in" "$OUTPUT" "ok: haseen.themegen (builtin:"
M="$PLUGIN/manifest.json"
assert_eq "a panel and nothing else" "panel" "$(jq -r '.kinds | join(" ")' "$M")"
assert_eq "it needs matugen" "matugen" "$(jq -r '.requires.bins | join(" ")' "$M")"
assert_eq "exec and files:read only" "exec files:read" "$(jq -r '.permissions | sort | join(" ")' "$M")"
assert_eq "debugIpc defaults off" "false" "$(jq -r .settings.debugIpc.default "$M")"
assert_eq "the default scheme is one the CLI knows" "tonal-spot" "$(jq -r .settings.scheme.default "$M")"
for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGIN"/*.qml | cut -d. -f2 | sort -u); do
    assert_eq "the manifest declares the setting $key" "true" "$(jq --arg k "$key" '.settings | has($k)' "$M")"
done
assert_eq "no hex literals in the panel" "" "$(grep -nE '#[0-9A-Fa-f]{3,8}\b' "$PLUGIN"/*.qml || true)"
assert_eq "no timers in the panel" "" "$(grep -n 'Timer' "$PLUGIN"/*.qml || true)"
assert_eq "no shell strings: argv only" "" "$(grep -nE '"(ba)?sh", *"-c"' "$PLUGIN"/*.qml || true)"
assert_eq "off by default (awaiting the owner's approval)" "false" \
    "$(jq -r '.plugins["haseen.themegen"].enabled' "$HASEEN_PATH/default/shell.json")"
# The row alone: menu.jsonc as a whole is JSONC (comments, trailing commas).
MENU="$(printf '{%s}' "$(grep '^ *"style.theme-generator":' "$HASEEN_PATH/default/menu.jsonc" | sed 's/,$//')" | jq -c '."style.theme-generator"')"
assert_eq "menu Style > Theme Generator" "Theme Generator" "$(jq -r .label <<<"$MENU")"
assert_eq "opens the panel" "haseen shell ipc panel toggle haseen.themegen" "$(jq -r .action <<<"$MENU")"
mkdir -p "$XDG_CONFIG_HOME/haseen"
when="$(jq -r .when <<<"$MENU")"
printf '{}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
assert_eq "the menu row hides while the plugin is off" 1 "$(bash -c "$when" >/dev/null 2>&1 && echo 0 || echo 1)"
capture haseen plugin enable haseen.themegen
assert_eq "and shows once it is enabled" 0 "$(bash -c "$when" >/dev/null 2>&1 && echo 0 || echo 1)"

# --- the panel model under the Qt JS engine --------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    {
        printf 'var preview = %s;\n' "$(jq -Rs . <<<"$J")"
        printf 'var clamped = %s;\n' "$(jq -Rs . <<<"$B")"
        printf 'var cliSchemes = %s;\n' "$(sed -n 's/^SCHEMES=(\(.*\))$/\1/p' "$REPO/bin/haseen-theme-generate" | jq -Rc 'split(" ")')"
    } >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Themegen.js" as T
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        out("schemes", T.SCHEMES.join(" ") === D.cliSchemes.join(" "));
        out("labels", [T.schemeLabel("tonal-spot"), T.schemeLabel("fruit-salad"), T.schemeLabel("dark")]);
        out("names", [T.defaultName("/p/Blue_Hour (2).PNG"), T.defaultName("/p/dusk.jpg"), T.defaultName("/p/---.png"), T.defaultName("/p/" + "x".repeat(60) + ".jpg").length, T.defaultName("/p/a.b.c.webp")]);
        out("valid", [T.validName("blue-hour-2"), T.validName("../x"), T.validName(""), T.validName("-x")]);
        out("cycle", [T.cycle(T.SCHEMES, "tonal-spot", -1), T.cycle(T.SCHEMES, "vibrant", 1), T.cycle(T.MODES, "dark", 1), T.cycle(T.MODES, "nope", 1)]);
        out("preview", T.previewArgv("/b/haseen", "/i.png", "content", "light", "my-theme"));
        out("previewNoName", T.previewArgv("/b/haseen", "/i.png", "content", "light", "Bad Name"));
        out("save", T.writeArgv("/b/haseen", "/i.png", "vibrant", "dark", "x", false));
        out("apply", T.writeArgv("/b/haseen", "/i.png", "vibrant", "dark", "x", true));
        const p = T.parsePreview(D.preview);
        out("parsed", [p.ok, p.target, p.name, p.colors.background, p.clamped.length, p.source]);
        const c = T.parsePreview(D.clamped);
        out("parsedClamped", c.clamped.map(s => s.split(" ")[0]));
        out("rows", T.swatchRows(p.colors).map(r => r.map(s => s.key).join(",")));
        out("rowColour", T.swatchRows(p.colors)[0][0].color === p.colors.background);
        const broken = JSON.parse(D.preview); delete broken.colors.bright_cyan;
        out("broken", [T.parsePreview("").ok, T.parsePreview("{").error, T.parsePreview(JSON.stringify(broken)).error, T.parsePreview('{"colors":null}').ok]);
        out("notes", [T.targetNote("new", "a"), T.targetNote("generated", "a"), T.targetNote("stock", "nord"), T.targetNote("taken", "mine")]);
        out("canWrite", ["new", "generated", "stock", "taken", ""].map(T.canWrite));
        out("errors", [T.errorLine("Warning: x\nError: no such image: /x\n\n", "f"), T.errorLine("", "fallback")]);
        out("swatchLabels", ["background", "bright_yellow", "magenta", "lighter_background"].map(T.swatchLabel));
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "model: the schemes are the CLI's" "true" "$(r schemes)"
    assert_eq "model: scheme labels" '["Tonal spot","Fruit salad","Dark"]' "$(r labels)"
    assert_eq "model: default names follow the CLI's slug" '["blue-hour-2","dusk","generated",48,"a-b-c"]' "$(r names)"
    assert_eq "model: the CLI named the image the same" "blue-hour-2" "$(jq -r .name <<<"$J")"
    assert_eq "model: name check" '[true,false,false,false]' "$(r valid)"
    assert_eq "model: cycling wraps" '["vibrant","tonal-spot","light","dark"]' "$(r cycle)"
    assert_eq "model: the preview argv" \
        '["/b/haseen","theme","generate","/i.png","--scheme","content","--mode","light","--name","my-theme","--json"]' "$(r preview)"
    assert_eq "model: an invalid name is left to the CLI default" \
        '["/b/haseen","theme","generate","/i.png","--scheme","content","--mode","light","--json"]' "$(r previewNoName)"
    assert_eq "model: Save writes without switching" \
        '["/b/haseen","theme","generate","/i.png","--scheme","vibrant","--mode","dark","--name","x","--no-apply"]' "$(r save)"
    assert_eq "model: Apply switches" \
        '["/b/haseen","theme","generate","/i.png","--scheme","vibrant","--mode","dark","--name","x"]' "$(r apply)"
    assert_eq "model: reads the CLI's preview" "[true,\"new\",\"blue-hour-2\",\"$(role surface dark)\",0,\"$(role source_color dark)\"]" "$(r parsed)"
    assert_eq "model: reads the clamp report" '["foreground","accent","selection"]' "$(r parsedClamped)"
    assert_eq "model: swatch rows" \
        '["background,lighter_background,foreground,dark_foreground,muted,accent,selection","red,yellow,green,cyan,blue,magenta","bright_red,bright_yellow,bright_green,bright_cyan,bright_blue,bright_magenta"]' "$(r rows)"
    assert_eq "model: swatches carry the colours" "true" "$(r rowColour)"
    assert_eq "model: half a palette is no preview" '[false,"no preview","preview is missing bright_cyan",false]' "$(r broken)"
    assert_eq "model: what Save does to the name" \
        '["","replaces your generated theme a","nord is a stock theme: pick another name","mine is a theme of yours: pick another name"]' "$(r notes)"
    assert_eq "model: only new or generated names are written" '[true,true,false,false,false]' "$(r canWrite)"
    assert_eq "model: the error shown is the last stderr line" '["no such image: /x","fallback"]' "$(r errors)"
    assert_eq "model: swatch captions" '["bg","yel+","mag","surface"]' "$(r swatchLabels)"
else
    echo "  skip: $QML_BIN not installed, Themegen.js not exercised" >&2
fi
