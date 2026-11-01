# shellcheck shell=bash
# haseen:covers share/haseen/shell/Haseen/Widgets/{Carousel.js,SkewSlice.qml,SkewCarousel.qml,qmldir}
# haseen:covers share/haseen/shell/plugins/haseen.{background,themepicker}/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The carousel the background and theme pickers share (plan 152): Omarchy's
# image picker without its dim. Its arithmetic (Carousel.js) runs under Qt's
# own engine; one slanted slice (SkewSlice.qml) is drawn by the software
# renderer the shell uses and its pixels read back, which proves the slant
# cuts the picture without a shader and leaves it upright; and the two
# pickers are checked to use the carousel, to dim nothing and to open as
# overlays.

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
    # The owner's ask (plan 152): no scrim over the screen, no shade over the
    # slices Omarchy dims, no shader to draw either.
    assert_eq "$id has no scrim, shade or shader" "" \
        "$(grep -nE 'scrim|dimColor|MultiEffect|ShaderEffect|layer\.effect' "$PLUGINS/$id"/*.qml || true)"
done
assert_eq "the carousel has no scrim, shade or shader" "" \
    "$(grep -vE '^\s*//' "$W"/{SkewCarousel,SkewSlice}.qml | grep -nE 'scrim|dimColor|MultiEffect|ShaderEffect|layer\.effect' || true)"
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
        const inCard = rel => { const p = C.slot(rel, 1120, false, G); return p.x >= 0 && p.x + p.width <= 1120; };
        out("compact", [C.COMPACT_STEPS, inCard(-C.COMPACT_STEPS), inCard(C.COMPACT_STEPS), inCard(C.COMPACT_STEPS + 1)]);
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
# No screen: the full design size. Compact (a panel card): the selected item
# and two slices a side, at full size.
assert_eq "design width, compact width, its card, its reach" '[1902,1200,1120,3]' "$(r sizes)"
# Uncapped, a third slice a side would reach past the compact card.
assert_eq "two slices a side fit the compact card, a third does not" '[2,true,true,false]' "$(r compact)"
assert_contains "the compact carousel caps its reach" "$(cat "$W/SkewCarousel.qml")" \
    'compact ? Math.min(Carousel.COMPACT_STEPS, Carousel.reach(strip.width, geometry))'
assert_eq "Omarchy's filter editing keys" '[true,false,true,false,false]' "$(r edits)"
assert_eq "Backspace, Ctrl+Backspace, Ctrl+U" '["a","tokyo ",""]' "$(r edited)"
assert_eq "one printable key types, a shortcut does not" '[true,true,false,false]' "$(r typed)"

# --- one slanted slice, drawn by the software renderer -----------------------------
# A 200x300 slice with a 28 px slant over a red picture with two upright
# stripes (blue at x 0-10, green at x 100-110), read back through a canvas.
# The slant must cut the top-left and bottom-right corners, keep the rest,
# and leave the green stripe where it is at the top and at the bottom: a
# sheared picture would move it 28 px at the top.
draw="$SANDBOX/draw"
mkdir -p "$draw"
cp "$W/SkewSlice.qml" "$draw/"
cat >"$draw/Draw.qml" <<EOF
//@ pragma DefaultEnv QT_QUICK_BACKEND = software
import QtQuick
import QtQuick.Window
Window {
    id: win
    width: 520; height: 340; visible: true; color: "transparent"
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Item {
        id: stage
        width: 240; height: 320
        SkewSlice {
            id: slice
            x: 20; y: 10; width: 200; height: 300; skew: 28; borderWidth: 0
            Rectangle { anchors.fill: parent; color: "red" }
            Rectangle { x: 0; width: 10; height: parent.height; color: "blue" }
            Rectangle { x: 100; width: 10; height: parent.height; color: "lime" }
        }
    }
    Canvas {
        id: probe
        x: 260; width: 240; height: 320
        property string file: "$draw/slice.png"
        onImageLoaded: requestPaint()
        onPaint: {
            if (!isImageLoaded("file://" + file))
                return;
            const ctx = getContext("2d");
            ctx.drawImage("file://" + file, 0, 0);
            const at = (x, y) => { const d = ctx.getImageData(x, y, 1, 1).data; return [d[0], d[1], d[2], d[3]].join(","); };
            const local = (x, y) => at(slice.x + x, slice.y + y);
            win.out("pixels", {
                centre: local(150, 150),
                topLeftCut: local(8, 5),
                bottomRightCut: local(195, 295),
                topRightKept: local(195, 5),
                bottomLeftKept: local(5, 295),
                stripeTop: local(105, 5),
                stripeBottom: local(105, 295)
            });
            const mouse = slice.children.filter(c => c.cursorShape !== undefined)[0];
            win.out("clicks", [mouse.contains(Qt.point(150, 150)), mouse.contains(Qt.point(8, 5)), mouse.contains(Qt.point(195, 295)), mouse.contains(Qt.point(5, 295))]);
            Qt.quit();
        }
    }
    Component.onCompleted: Qt.callLater(() => stage.grabToImage(r => { r.saveToFile(probe.file); probe.loadImage("file://" + probe.file); }))
}
EOF
draw_out="$(cd "$draw" && QT_QUICK_BACKEND=software QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Draw.qml 2>&1)"
d() { sed -n "s/^.*RESULT $1 //p" <<<"$draw_out"; }
px() { jq -r --arg k "$1" '.[$k]' <<<"$(d pixels)"; }
assert_eq "the slice draws its picture inside the slant" "255,0,0,255" "$(px centre)"
assert_eq "the slant cuts the top-left corner" "0" "$(px topLeftCut | cut -d, -f4)"
assert_eq "the slant cuts the bottom-right corner" "0" "$(px bottomRightCut | cut -d, -f4)"
assert_eq "the top-right corner is kept" "255,0,0,255" "$(px topRightKept)"
assert_eq "the bottom-left corner is kept" "0,0,255,255" "$(px bottomLeftKept)"
assert_eq "the picture is upright: the stripe at the top" "0,255,0,255" "$(px stripeTop)"
assert_eq "the picture is upright: the stripe at the bottom" "0,255,0,255" "$(px stripeBottom)"
assert_eq "only the slanted shape takes a click" '[true,false,false,true]' "$(d clicks)"
assert_eq "the slice loads without a warning" "" "$(grep -iE 'error|warning|TypeError|ReferenceError|Cannot' <<<"$draw_out" | grep -v RESULT || true)"
