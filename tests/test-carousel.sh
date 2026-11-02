# shellcheck shell=bash
# haseen:covers share/haseen/shell/Haseen/Widgets/{Carousel.js,SkewSlice.qml,SkewCarousel.qml,qmldir}
# haseen:covers share/haseen/shell/plugins/haseen.{background,themepicker}/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The carousel that the background and theme pickers share (plan 152), which
# is Omarchy's image picker without its dim. The test runs the arithmetic in
# Carousel.js under Qt's own engine. It draws one slanted slice
# (SkewSlice.qml) on the software renderer the shell uses, at scales 1, 1.25
# and 2, and reads its pixels back. That proves the slant cuts the picture
# without a shader and leaves it upright and whole (plan 156). It also checks
# that both pickers use the carousel, dim nothing and open as overlays.

W="$HASEEN_PATH/shell/Haseen/Widgets"
PLUGINS="$HASEEN_PATH/shell/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox carousel

# --- the pickers use the carousel, open as overlays, dim nothing -----------------
for id in haseen.background haseen.themepicker; do
    entry="$(cat "$PLUGINS/$id/Panel.qml")"
    assert_contains "$id draws the shared carousel" "$entry" "SkewCarousel {"
    assert_eq "$id opens over the whole screen" "overlay" "$(jq -r '.settings.placement.default' "$PLUGINS/$id/manifest.json")"
    assert_eq "$id lost the grid's settings" "" "$(jq -r '.settings | keys[] | select(. == "columns" or . == "rows")' "$PLUGINS/$id/manifest.json")"
    assert_contains "$id is compact in a panel card" "$entry" 'compact: (root.settings.placement || "overlay") !== "overlay"'
    # The owner asked for no scrim over the screen and no shade over the
    # slices that Omarchy dims (plan 152), and the slant needs no shader. The
    # check skips ShaderEffectSource, which names a layer's texture setting
    # (plan 156).
    assert_eq "$id has no scrim, shade or shader" "" \
        "$(grep -nE 'scrim|dimColor|MultiEffect|ShaderEffect\b|layer\.effect' "$PLUGINS/$id"/*.qml || true)"
done
assert_eq "the carousel has no scrim, shade or shader" "" \
    "$(grep -vE '^\s*//' "$W"/{SkewCarousel,SkewSlice}.qml | grep -nE 'scrim|dimColor|MultiEffect|ShaderEffect\b|layer\.effect' || true)"
assert_eq "the carousel's colours come from Theme" "" \
    "$(grep -nE '#[0-9A-Fa-f]{3,8}\b' "$W"/{SkewCarousel,SkewSlice}.qml "$W/Carousel.js" || true)"
assert_contains "the widgets module lists the slice" "$(cat "$W/qmldir")" "SkewSlice 1.0 SkewSlice.qml"
assert_contains "the widgets module lists the carousel" "$(cat "$W/qmldir")" "SkewCarousel 1.0 SkewCarousel.qml"
for f in "$W/SkewSlice.qml" "$W/SkewCarousel.qml" "$W/Carousel.js"; do
    assert_contains "$(basename "$f") keeps the Omarchy MIT notice" "$(cat "$f")" "MIT, Copyright (c) David"
done
# Every slice decodes at the selected size, never the file's own.
for id in haseen.background haseen.themepicker; do
    assert_contains "$id decodes at the selected item's size" "$(cat "$PLUGINS/$id"/*.qml)" "carousel.geometry.expandedWidth * carousel.pixelRatio"
done

if [[ ! -x $QML_BIN ]]; then
    echo "  (no $QML_BIN: the carousel's arithmetic and drawing were not exercised)" >&2
    return 0
fi

# --- the arithmetic, under the Qt JS engine ----------------------------------------
harness="$SANDBOX/harness"
mkdir -p "$harness"
cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$W/Carousel.js" as C
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const G = C.GEOMETRY;
        const names = ["tokyo-night", "rose-pine", "retro-82", "nord"];
        out("labels", [C.labelFor("tokyo-night"), C.labelFor("/x/1-deep_sea.jpg"), C.nameFor("/x/a.b.png")]);
        out("shown", [C.shown(names, ""), C.shown(names, "ro"), C.shown(names, "Tokyo N"), C.shown(names, "zzz")]);
        out("step", [C.step([0, 1, 2, 3], 3, 1), C.step([0, 1, 2, 3], 0, -1), C.step([1, 2], 1, -1), C.step([1, 2], 0, 1), C.step([], 0, 1)]);
        out("keep", [C.keep([1, 2], 2), C.keep([1, 2], 0), C.keep([], 3)]);
        const big = C.fit(1536, 864, 134);
        const small = C.fit(800, 600, 134);
        out("fit", [big.scale, big.expandedWidth, big.skew, C.fit(0, 0, 0).scale]);
        out("fitSmall", [small.scale < 1, small.expandedWidth + 2 * small.sliceWidth <= 800, small.expandedHeight <= 600 - 134]);
        out("reach", [C.reach(1536, G), C.reach(3840, G), C.reach(0, G)]);
        out("slots", [C.slot(0, 1536, false, G), C.slot(-1, 1536, false, G), C.slot(1, 1536, false, G), C.slot(2, 1536, false, G)]);
        out("mirrored", [C.slot(0, 1536, true, G).x, C.slot(1, 1536, true, G).x, C.slot(-1, 1536, true, G).x]);
        out("card", [C.stripWidth(G), C.cardWidth(G, 1536), C.cardWidth(G, 3840)]);
        out("sizes", [C.designWidth(), C.compactWidth(), C.cardWidth(C.fit(C.compactWidth(), 864, 134), C.compactWidth()), C.reach(1120, G)]);
        // The compact card on a wide screen (1120 px), on a 1080 px screen
        // (1000) and on a 1024 px screen (944), with room for more than the
        // cap (1500), and before layout (0). Then, at every whole width from
        // 0 to 2000, the slices it reaches always fit.
        const cardFor = w => C.cardWidth(C.fit(Math.min(w, C.compactWidth()), 864, 134), Math.min(w, C.compactWidth()));
        let fits = true;
        for (let w = 0; w <= 2000; w++) {
            const g = C.fit(Math.min(w, C.compactWidth()), 864, 134);
            const card = cardFor(w);
            const n = C.fitReach(card, g, C.COMPACT_STEPS);
            if (n > 0 && (C.slot(-n, card, false, g).x < 0 || C.slot(n, card, false, g).x + g.sliceWidth > card))
                fits = false;
        }
        out("compact", [C.COMPACT_STEPS, cardFor(1536), cardFor(1080), C.fitReach(1120, G, 2), C.fitReach(1000, G, 2), C.fitReach(944, G, 2),
            C.fitReach(1500, G, 2), C.fitReach(0, G, 2), fits]);
        out("edits", [C.editsFilter(Qt.Key_Backspace, Qt.NoModifier, "ab"), C.editsFilter(Qt.Key_Backspace, Qt.NoModifier, ""),
            C.editsFilter(Qt.Key_U, Qt.ControlModifier, "ab"), C.editsFilter(Qt.Key_U, Qt.ControlModifier | Qt.ShiftModifier, "ab"),
            C.editsFilter(Qt.Key_Backspace, Qt.AltModifier, "ab")]);
        out("edited", [C.editedFilter(Qt.Key_Backspace, Qt.NoModifier, "ab"), C.editedFilter(Qt.Key_Backspace, Qt.ControlModifier, "tokyo nig"),
            C.editedFilter(Qt.Key_U, Qt.ControlModifier, "tokyo")]);
        out("typed", [C.typed("a", Qt.NoModifier), C.typed("A", Qt.ShiftModifier), C.typed("a", Qt.ControlModifier), C.typed("", Qt.NoModifier)]);
        Qt.quit();
    }
}
EOF
qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1)"
r() { sed -n "s/^.*RESULT $1 //p" <<<"$qml_out"; }
assert_eq "labels read as Omarchy's: words, capitals, no extension" '["Tokyo Night","1 Deep Sea","a.b"]' "$(r labels)"
assert_eq "the filter matches a name or its label, any case" '[[0,1,2,3],[1,2],[0],[]]' "$(r shown)"
assert_eq "stepping wraps, and starts from the first match when the selection hides" '[0,3,2,1,-1]' "$(r step)"
assert_eq "a filter keeps the selection while it shows" '[2,1,3]' "$(r keep)"
assert_eq "Omarchy's size on a screen it fits" '[1,768,28,1]' "$(r fit)"
assert_eq "a small screen shrinks it to fit" '[true,true,true]' "$(r fitSmall)"
assert_eq "the slices that reach into the screen, each side, none before layout" '[6,21,0]' "$(r reach)"
assert_eq "the selected item centred, slices beside it at Omarchy's step" \
    '[{"x":384,"y":0,"width":768,"height":475,"z":100},{"x":306,"y":22,"width":108,"height":432,"z":49},{"x":1122,"y":22,"width":108,"height":432,"z":49},{"x":1200,"y":22,"width":108,"height":432,"z":48}]' \
    "$(r slots)"
assert_eq "right to left, the next item sits on the left" '[384,306,1122]' "$(r mirrored)"
assert_eq "Omarchy's strip and card widths" '[1782,1456,1822]' "$(r card)"
# With no screen the carousel takes its full design size. A compact one, in a
# panel card, holds the selected item and two slices on each side at full size.
assert_eq "design width, compact width, its card, its reach" '[1902,1200,1120,3]' "$(r sizes)"
# A compact card shows only the slices that fit inside it, two at most on
# each side.
assert_eq "the compact card's reach: 2, then 1 on a narrow screen, never past the card" \
    '[2,1120,1000,2,1,1,2,0,true]' "$(r compact)"
assert_contains "the compact carousel fits its reach to the card" "$(cat "$W/SkewCarousel.qml")" 'Carousel.fitReach('
assert_eq "Omarchy's filter editing keys" '[true,false,true,false,false]' "$(r edits)"
assert_eq "Backspace, Ctrl+Backspace, Ctrl+U" '["a","tokyo ",""]' "$(r edited)"
assert_eq "one printable key types, a shortcut does not" '[true,true,false,false]' "$(r typed)"

# --- one slanted slice, drawn by the software renderer -----------------------------
# A 200x300 slice with a 28 px slant. Its picture is red, with two upright
# stripes (blue at x 0-10, green at x 100-110) and a yellow band along the
# bottom edge. The slant must cut the top-left and bottom-right corners and
# keep the rest. The green stripe must sit at the same x at the top and at
# the bottom, because a sheared picture would move it 28 px at the top. The
# slice is drawn at scale 1, at IO's 1.25 and at 2. Without plan 156's fix it
# lost the bottom quarter of its picture at 1.25 and all of it at 2, and the
# yellow band and the stripes catch that. ImageMagick reads the grab,
# because a Canvas reads pixels back wrong at a fractional scale too.
draw="$SANDBOX/draw"
mkdir -p "$draw"
cp "$W/SkewSlice.qml" "$draw/"
cat >"$draw/Draw.qml" <<EOF
//@ pragma DefaultEnv QT_QUICK_BACKEND = software
import QtQuick
import QtQuick.Window
Window {
    id: win
    width: 260; height: 340; visible: true; color: "transparent"
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Item {
        id: stage
        width: 240; height: 320
        SkewSlice {
            id: slice
            x: 20; y: 10; width: 200; height: 300; skew: 28; borderWidth: 0
            Rectangle { anchors.fill: parent; color: "red" }
            Rectangle { y: 280; width: parent.width; height: 20; color: "yellow" }
            Rectangle { x: 0; width: 10; height: parent.height; color: "blue" }
            Rectangle { x: 100; width: 10; height: parent.height; color: "lime" }
        }
    }
    // Grab at the screen's scale. A grab at another size goes through a
    // rescaled layer with the same bug.
    Component.onCompleted: Qt.callLater(() => stage.grabToImage(r => {
        r.saveToFile("$draw/slice.png");
        const mouse = slice.children.filter(c => c.cursorShape !== undefined)[0];
        win.out("clicks", [mouse.contains(Qt.point(150, 150)), mouse.contains(Qt.point(8, 5)), mouse.contains(Qt.point(195, 295)), mouse.contains(Qt.point(5, 295))]);
        Qt.quit();
    }))
}
EOF
# The pixel at (x, y) in the slice, at scale $1, as "r,g,b,a".
pixel() {
    local x y
    x=$(awk -v s="$1" -v v="$2" 'BEGIN { printf "%d", (20 + v) * s }')
    y=$(awk -v s="$1" -v v="$3" 'BEGIN { printf "%d", (10 + v) * s }')
    magick "$draw/slice.png" -crop "1x1+$x+$y" -depth 8 txt:- | sed -n 's/^0,0: *(\([^)]*\)).*/\1/p' | tr -d ' '
}
have_magick=1
command -v magick >/dev/null || {
    have_magick=0
    echo "  (magick missing: the slice's pixels were not read back)" >&2
    # CI installs it (ARCH_PACKAGES), so there a missing magick fails the
    # test instead of skipping the pixel checks.
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "carousel: required magick prerequisite" available unavailable
}
for scale in 1 1.25 2; do
    rm -f "$draw/slice.png"
    draw_out="$(cd "$draw" && QT_SCALE_FACTOR=$scale QT_QUICK_BACKEND=software QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Draw.qml 2>&1)"
    at=" (scale $scale)"
    assert_eq "only the slanted shape takes a click$at" '[true,false,false,true]' "$(sed -n 's/^.*RESULT clicks //p' <<<"$draw_out")"
    assert_eq "the slice loads without a warning$at" "" "$(grep -iE 'error|warning|TypeError|ReferenceError|Cannot' <<<"$draw_out" | grep -v RESULT || true)"
    ((have_magick)) || continue
    assert_eq "the slice draws its picture inside the slant$at" "255,0,0,255" "$(pixel "$scale" 150 150)"
    assert_eq "the slant cuts the top-left corner$at" "0" "$(pixel "$scale" 8 5 | cut -d, -f4)"
    assert_eq "the slant cuts the bottom-right corner$at" "0" "$(pixel "$scale" 195 295 | cut -d, -f4)"
    assert_eq "the top-right corner is kept$at" "255,0,0,255" "$(pixel "$scale" 195 5)"
    assert_eq "the bottom-left corner is kept$at" "0,0,255,255" "$(pixel "$scale" 5 295)"
    assert_eq "the picture is upright: the stripe at the top$at" "0,255,0,255" "$(pixel "$scale" 105 5)"
    assert_eq "the picture is upright: the stripe at the bottom$at" "0,255,0,255" "$(pixel "$scale" 105 295)"
    assert_eq "the picture reaches the slice's bottom edge$at" "255,255,0,255" "$(pixel "$scale" 60 290)"
done
