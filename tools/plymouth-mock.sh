#!/usr/bin/env bash
# tools/plymouth-mock.sh OUT.png [THEME] — a labelled MOCK of the splash's LUKS
# prompt (plan 036), for review without a reboot. The layout is the real one:
# the theme script, rendered in THEME's colours (default: haseen), runs under
# tests/fixtures/plymouth-harness.js, and every sprite it shows is drawn with
# ImageMagick at the position and opacity the script gave it. The pixels are
# not Plymouth's: text is the system's fontconfig monospace standing in for the label plugin's
# font, the caret and the brackets are plain rectangles, and there is no mark.
# Two crops, stacked: before the first key, and after three.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
out="${1:?usage: tools/plymouth-mock.sh OUT.png [THEME]}"
theme="${2:-haseen}"
export HASEEN_PATH="$PWD/share/haseen"
command -v magick >/dev/null || { echo "plymouth-mock: needs ImageMagick (magick)" >&2; exit 1; }
command -v node >/dev/null || { echo "plymouth-mock: needs node" >&2; exit 1; }
mono="$(fc-match -f '%{file}' monospace)"
bold="$(fc-match -f '%{file}' 'sans:bold')"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/haseen-plymouth-mock.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=../share/haseen/lib/plymouth.sh
source "$HASEEN_PATH/lib/plymouth.sh"
read -r bg fg accent <<<"$(plymouth_theme_colors "$HASEEN_PATH/themes/$theme/colors.toml")"
plymouth_script "$bg" "$fg" "$accent" >"$tmp/haseen.script"
node tests/fixtures/plymouth-harness.js "$tmp/haseen.script" >"$tmp/report.json"

# draw STATE — ImageMagick draw arguments, one per line, for STATE's visible
# sprites. Colours are the script's own 0..1 floats; text baselines sit 17 px
# below the 22 px cell's top.
draw() {
    jq -r --arg state "$1" '
        .[$state][] | select(.opacity > 0 and .kind != "empty")
        | "rgba(\(.color | map(. * 255 | round) | join(",")),\(.opacity))" as $c
        | if .kind == "text" and .text != "█" then
              "-fill", $c, "-annotate", "+\(.x)+\(.y + 17)", .text
          else
              "-fill", $c, "-draw", "rectangle \(.x),\(.y) \(.x + .w - 1),\(.y + .h - 1)"
          end' "$tmp/report.json"
}

crop() { # STATE LABEL OUT
    local args
    mapfile -t args < <(draw "$1")
    magick -size 1920x1080 "xc:$bg" -font "$mono" -pointsize 18 "${args[@]}" \
        -crop 680x150+620+467 +repage \
        -fill "$fg" -pointsize 13 -annotate +10+18 "$2" "$3"
}
crop empty "before the first key (caret lit)" "$tmp/empty.png"
crop typed "after three keys" "$tmp/typed.png"
magick "$tmp/empty.png" "$tmp/typed.png" -append +repage \
    -gravity north -background "$accent" -fill "$bg" -font "$bold" -pointsize 14 \
    -splice 0x26 -annotate +0+5 "MOCK: fake-Plymouth layout, not a boot render ($theme theme)" \
    "$out"
echo "$out"
