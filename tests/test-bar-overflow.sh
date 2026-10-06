# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The bar's overflow panel (architecture 5.3): which widgets leave a bar that
# is too short for them, in which order, and `haseen bar overflow`, which
# edits bar.overflow / bar.pinned. The fit in Overflow.js runs under the real
# Qt JS engine; the panel itself was proven in a nested Hyprland, not by
# reading QML source here.

SHELL_DIR="$HASEEN_PATH/shell"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

# --- the fit, under the Qt JS engine ------------------------------------------
sandbox bar-overflow-units
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/Overflow.js" as O

Item {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    // "a:100 b:50" -> [{id: "a", size: 100}, {id: "b", size: 50}]
    function w(text) {
        return text === "" ? [] : text.split(" ").map(t => ({ id: t.split(":")[0], size: Number(t.split(":")[1]) }));
    }

    // A 1000 px bar, 3 px between widgets, 6 px between sections, a 24 px
    // button. Centre 100 px wide: it spans 450..550, so the right section
    // may be at most 444 px long and the left one 444 px.
    function spec(left, center, right, extra) {
        const s = { length: 1000, spacing: 3, gap: 6, button: 24, hysteresis: 12,
                    left: w(left), center: w(center), right: w(right), overflow: [], pinned: [] };
        for (const k in (extra || {}))
            s[k] = extra[k];
        return s;
    }

    function ids(s, previous) {
        return O.fit(s, previous || null).ids;
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        // Sections: each id once, the tray first in the right section.
        eq("tray leads the right section", { left: ["a"], center: ["c"], right: ["haseen.tray", "x", "y"] },
           O.sections(["a"], ["c"], ["x", "haseen.tray", "y"]));
        eq("an id listed twice stays where it came first", { left: ["a", "b"], center: ["c"], right: ["d"] },
           O.sections(["a", "b", "a"], ["c", "b"], ["d", "a", "c"]));
        eq("missing sections are empty", { left: [], center: [], right: [] }, O.sections(undefined, null, "x"));
        eq("section length skips hidden widgets", 206, O.sectionLength([100, 0, 50, 50], 3));
        eq("empty section has no length", 0, O.sectionLength([0, 0], 3));

        // Room enough: nothing moves, no button.
        const roomy = O.fit(spec("w:200", "c:100", "haseen.tray:20 a:100 b:100 c2:100 d:100"));
        eq("fits: nothing overflows", [], roomy.ids);
        eq("fits: no button", false, roomy.button);
        eq("fits: fits", true, roomy.fits);

        // The right section reaches the centre (20+150+300+12 = 482 > 444):
        // its innermost movable widget, the one right of the tray, goes first.
        const full = O.fit(spec("w:200", "c:100", "haseen.tray:20 a:150 b:100 c2:100 d:100"));
        eq("right collision: innermost after the tray", ["a"], full.ids);
        eq("right collision: button shows", true, full.button);
        eq("right collision: fits after", true, full.fits);
        eq("right collision: counted as automatic", 1, full.autoRight);
        eq("bigger collision: in bar order from the inside", ["a", "b", "c2"],
           ids(spec("", "c:100", "haseen.tray:20 a:200 b:200 c2:200 d:200")));
        // Exactly at the limit: 20+3*100+100+4*3 = 432 <= 444 fits; the
        // button's 27 px would not, but it only shows with an overflow.
        eq("exact fit keeps everything", [], ids(spec("", "c:100", "haseen.tray:20 a:112 b:100 c2:100 d:100")));
        eq("one pixel over moves one", ["a"], ids(spec("", "c:100", "haseen.tray:20 a:125 b:100 c2:100 d:100")));
        // The button's own room counts: removing a 30 px widget for a 27 px
        // button gains only 3 px.
        eq("the button's room is counted", ["a", "b"],
           ids(spec("", "c:100", "haseen.tray:20 a:30 b:100 c2:150 d:150")));

        // Never the tray, never pinned ids; hidden widgets are skipped.
        eq("pinned widgets stay", ["b"], ids(spec("", "c:100", "haseen.tray:20 a:150 b:100 c2:100 d:100", { pinned: ["a"] })));
        eq("zero-size widgets are not moved", ["b"], ids(spec("", "c:100", "haseen.tray:20 z:0 b:150 c2:100 d:100 e:100")));
        eq("the tray never moves, even when huge", ["a"], O.fit(spec("", "c:100", "haseen.tray:600 a:50")).ids);
        eq("tray alone too big: nothing to move, does not fit", false, O.fit(spec("", "c:100", "haseen.tray:600")).fits);

        // bar.overflow: always in the panel, first, from any section, in
        // its own order; unknown ids and the tray are ignored.
        const forced = O.fit(spec("l:50", "c:100", "haseen.tray:20 a:50 b:50", { overflow: ["b", "nope.x", "haseen.tray", "c", "l"] }));
        eq("bar.overflow: always overflowed, in its order", ["b", "c", "l"], forced.ids);
        eq("bar.overflow: button shows", true, forced.button);
        eq("bar.overflow beats bar.pinned", ["a"], ids(spec("", "", "haseen.tray:20 a:50", { overflow: ["a"], pinned: ["a"] })));
        eq("bar.overflow first, then automatic", ["d", "a"],
           ids(spec("", "c:100", "haseen.tray:20 a:150 b:100 c2:100 d:100 e:150", { overflow: ["d"] })));
        const zero = O.fit(spec("", "c:100", "haseen.tray:20 z:0", { overflow: ["z"] }));
        eq("hidden widget in bar.overflow: listed", ["z"], zero.ids);
        eq("hidden widget in bar.overflow: not shown", [], zero.shown);
        eq("hidden widget in bar.overflow: no button", false, zero.button);

        // The left section reaching the centre gives up its innermost
        // (last) widget; the right section is left alone.
        const left = O.fit(spec("l1:200 l2:200 l3:100", "c:100", "haseen.tray:20 a:50"));
        eq("left collision: innermost (last) left widget", ["l3"], left.ids);
        eq("left collision: counted on the left", 1, left.autoLeft);
        eq("left collision: button shows on the right", true, left.button);

        // No centre: the side sections collide with each other; the right
        // one gives way first, then the left one.
        eq("no centre: fits", [], ids(spec("x:300", "", "haseen.tray:20 a:400 b:200")));
        eq("no centre: right gives way", ["a"], ids(spec("x:300", "", "haseen.tray:20 a:400 b:300")));
        eq("no centre: right exhausted, then left", ["a", "l2"], ids(spec("l1:500 l2:500", "", "haseen.tray:20 a:100")));

        // A centre too wide for anything: everything movable goes, and the
        // bar still does not fit.
        const wide = O.fit(spec("", "c:900", "haseen.tray:20 a:50"));
        eq("wide centre: every movable widget", ["a"], wide.ids);
        eq("wide centre: still does not fit", false, wide.fits);

        // Vertical bars use the same rule along their height (the sizes are
        // heights): a 700 px left bar, a 90 px clock in the middle (305..395),
        // a 280 px bottom section that may take 299.
        const tall = { length: 700, spacing: 3, gap: 6, button: 24, hysteresis: 12,
                       left: w("ws:120"), center: w("clock:90"), right: w("haseen.tray:28 a:60 b:60 c2:60 d:60"),
                       overflow: [], pinned: [] };
        eq("vertical bar: fits", [], O.fit(tall).ids);
        tall.length = 600; // centre 255..345: the bottom section may take 249
        eq("vertical bar: shorter screen moves the topmost of the bottom section", ["a"], O.fit(tall).ids);
        tall.length = 400; // centre 155..245: 149 left
        eq("vertical bar: much shorter moves more", ["a", "b", "c2"], O.fit(tall).ids);

        // Hysteresis: a widget that left comes back only with 12 px to spare.
        // a:105 -> 437 px, fits the 444 limit but not 432.
        const wobble = spec("", "c:100", "haseen.tray:20 a:105 b:100 c2:100 d:100");
        eq("hysteresis: fits from scratch", [], ids(wobble));
        eq("hysteresis: stays out after leaving", ["a"], ids(wobble, { autoRight: 1, autoLeft: 0 }));
        const settled = spec("", "c:100", "haseen.tray:20 a:95 b:100 c2:100 d:100");
        eq("hysteresis: comes back with room to spare", [], ids(settled, { autoRight: 1, autoLeft: 0 }));
        eq("hysteresis only holds widgets that would not fit with room to spare", ["a"], ids(spec("", "c:100", "haseen.tray:20 a:150 b:100 c2:100 d:100"), { autoRight: 3, autoLeft: 0 }));
        eq("hysteresis: grows at once", ["a", "b"], ids(spec("", "c:100", "haseen.tray:20 a:150 b:200 c2:100 d:100"), { autoRight: 1, autoLeft: 0 }));

        // Edits: the rule the CLI applies too.
        eq("edit add", { overflow: ["x", "a"], pinned: ["y"] }, O.edit(["x"], ["a", "y"], "add", "a"));
        eq("edit add twice keeps the order", { overflow: ["a", "x"], pinned: [] }, O.edit(["a", "x"], [], "add", "a"));
        eq("edit remove", { overflow: ["x"], pinned: ["y"] }, O.edit(["a", "x"], ["y"], "remove", "a"));
        eq("edit pin (keep in bar)", { overflow: ["x"], pinned: ["y", "a"] }, O.edit(["a", "x"], ["y"], "pin", "a"));
        eq("edit unpin", { overflow: ["x"], pinned: [] }, O.edit(["x"], ["a"], "unpin", "a"));
        eq("edit refuses the tray", null, O.edit([], [], "add", "haseen.tray"));
        eq("edit unknown verb", null, O.edit([], [], "toss", "a"));
        eq("edit from missing lists", { overflow: ["a"], pinned: [] }, O.edit(undefined, null, "add", "a"));

        // Drag and drop (Bar.qml arrange mode, haseen bar move).
        const L = { left: ["l1", "l2"], center: ["c1"], right: ["haseen.tray", "r1", "r2"], overflow: ["r2"], pinned: ["r1"] };
        const lists = r => r === null ? null : [r.left, r.center, r.right, r.overflow, r.pinned];
        eq("move within a section", [["l2", "l1"], ["c1"], ["haseen.tray", "r1", "r2"], ["r2"], ["r1"]],
           lists(O.move(L, "l2", "left", "l1", false)));
        eq("move to another section, in front of a widget", [["l1", "l2"], ["r1", "c1"], ["haseen.tray", "r2"], ["r2"], ["r1"]],
           lists(O.move(L, "r1", "center", "c1", false)));
        eq("move never lands in front of the tray", ["haseen.tray", "l1", "r1", "r2"], O.move(L, "l1", "right", "haseen.tray", false).right);
        eq("move to a section's end", ["haseen.tray", "r1", "r2", "l1"], O.move(L, "l1", "right", "", false).right);
        eq("move in front of itself keeps its place", ["haseen.tray", "r1", "r2"], O.move(L, "r1", "right", "r1", false).right);
        eq("move into the panel, in front of another", [["l1", "l2"], ["c1"], ["haseen.tray", "r1", "r2"], ["r1", "r2"], []],
           lists(O.move(L, "r1", "overflow", "r2", false)));
        eq("move out of the panel, pinned", [["l1", "l2"], ["c1", "r2"], ["haseen.tray", "r1"], [], ["r1", "r2"]],
           lists(O.move(L, "r2", "center", "", true)));
        eq("move refuses the tray", null, O.move(L, "haseen.tray", "left", "", false));
        eq("move refuses an id not in the bar", null, O.move(L, "nope.x", "left", "", false));
        eq("move refuses an unknown target", null, O.move(L, "l1", "middle", "", false));
        eq("move takes an id listed twice out of both", [[], [], ["a"], [], []],
           lists(O.move({ left: ["a"], center: ["a"] }, "a", "right", "", false)));

        // Where a drag along a 1000 px bar lands.
        const spans = { length: 1000, spacing: 4,
                        left: [{ id: "a", start: 0, end: 50 }, { id: "b", start: 54, end: 104 }],
                        center: [{ id: "c", start: 470, end: 530 }],
                        right: [{ id: "haseen.tray", start: 800, end: 830 }, { id: "x", start: 834, end: 900 }, { id: "y", start: 904, end: 1000 }] };
        eq("drop past a widget's middle: in front of the next", { section: "left", before: "b", at: 52 }, O.dropTarget(30, spans, "z"));
        eq("drop in the gap near the left section: its end", { section: "left", before: "", at: 106 }, O.dropTarget(200, spans, "z"));
        eq("drop in the gap near the centre: its start", { section: "center", before: "c", at: 468 }, O.dropTarget(400, spans, "z"));
        eq("drop right of the centre: its end", { section: "center", before: "", at: 532 }, O.dropTarget(600, spans, "z"));
        eq("drop on the tray: after it", { section: "right", before: "x", at: 832 }, O.dropTarget(810, spans, "z"));
        eq("drop at the bar's end", { section: "right", before: "", at: 1000 }, O.dropTarget(1000, spans, "z"));
        eq("the dragged widget is not a neighbour", { section: "right", before: "y", at: 902 }, O.dropTarget(880, spans, "x"));
        const noCentre = { length: 1000, spacing: 4, left: spans.left, center: [], right: spans.right };
        eq("an empty centre sits in the middle", { section: "center", before: "", at: 500 }, O.dropTarget(520, noCentre, "z"));

        // Where a drop on the panel lands: rows left to right, top to bottom.
        const cellRects = [{ id: "a", x: 0, y: 0, w: 40, h: 30 }, { id: "b", x: 50, y: 0, w: 40, h: 30 }, { id: "c", x: 0, y: 40, w: 40, h: 30 }];
        eq("panel drop on a cell's first half", "a", O.panelTarget({ x: 10, y: 10 }, cellRects, "z"));
        eq("panel drop on a cell's second half", "b", O.panelTarget({ x: 30, y: 10 }, cellRects, "z"));
        eq("panel drop past a row's end: the next row", "c", O.panelTarget({ x: 95, y: 10 }, cellRects, "z"));
        eq("panel drop after the last cell", "", O.panelTarget({ x: 60, y: 60 }, cellRects, "z"));
        eq("panel drop skips the dragged cell", "c", O.panelTarget({ x: 60, y: 10 }, cellRects, "b"));
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "overflow unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "overflow unit count" "75" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML_BIN"
fi

# --- haseen bar overflow ------------------------------------------------------
CFG() { printf '%s' "$XDG_CONFIG_HOME/haseen/shell.json"; }
ipc_stub() { stub qs "echo \"qs: \$*\" >>'$SANDBOX/qs.log'"; }
ipc_calls() {
    cat "$SANDBOX/qs.log" 2>/dev/null || true
    : >"$SANDBOX/qs.log"
}
lists() { jq -c '[.bar.overflow, .bar.pinned]' "$(CFG)"; }

sandbox bar-overflow-cli
f="$REPO/bin/haseen-bar-overflow"
assert_eq "haseen-bar-overflow is executable" yes "$([[ -x $f ]] && echo yes || echo no)"
assert_contains "takes --dry-run" "$(sed -n 's/^# haseen:args //p' "$f")" "--dry-run"
capture haseen bar overflow --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help prints usage" "$OUTPUT" "Usage: haseen bar overflow"
capture haseen commands bar
assert_contains "listed with the bar commands" "$OUTPUT" "haseen bar overflow"
assert_eq "defaults declare an empty bar.overflow" '[]' "$(jq -c .bar.overflow "$HASEEN_PATH/default/shell.json")"
assert_eq "defaults declare an empty bar.pinned" '[]' "$(jq -c .bar.pinned "$HASEEN_PATH/default/shell.json")"
assert_eq "the default bar.right starts with the tray" '"haseen.tray"' "$(jq -c '.bar.right[0]' "$HASEEN_PATH/default/shell.json")"

# Dry run: pure, shows the write and the IPC call, writes nothing.
capture haseen bar overflow add haseen.weather --dry-run
assert_status "add --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "add --dry-run" "$OUTPUT"
assert_contains "dry run shows the write" "$OUTPUT" "DRYRUN: write $(CFG).new"
assert_contains "dry run shows the new list" "$OUTPUT" '"haseen.weather"'
assert_contains "dry run shows the IPC apply" "$OUTPUT" "DRYRUN: haseen shell ipc bar overflow add haseen.weather"
assert_eq "dry run created no shell.json" no "$([[ -e $(CFG) ]] && echo yes || echo no)"

# Real runs edit the user's file, keep the rest, and apply over IPC.
ipc_stub
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"right":["haseen.tray","me.a","me.b"],"center":["haseen.clock"]},"plugins":{"me.a":{"enabled":true}}}\n' >"$(CFG)"
capture haseen bar overflow add me.a
assert_status "add exits 0" 0 "$STATUS"
assert_eq "add: in bar.overflow" '[["me.a"],[]]' "$(lists)"
assert_eq "add: other bar keys survive" '["haseen.tray","me.a","me.b"]' "$(jq -c .bar.right "$(CFG)")"
assert_eq "add: plugin entries survive" true "$(jq '.plugins["me.a"].enabled' "$(CFG)")"
assert_eq "add: applied live" "qs: -p $HASEEN_PATH/shell ipc call bar overflow add me.a" "$(ipc_calls)"
capture haseen bar overflow add haseen.clock
assert_eq "add: centre widgets may go too, in order" '[["me.a","haseen.clock"],[]]' "$(lists)"
capture haseen bar overflow pin me.a
ipc_calls >/dev/null
assert_eq "pin: out of overflow, into pinned" '[["haseen.clock"],["me.a"]]' "$(lists)"
capture haseen bar overflow add me.a --no-apply
assert_eq "add: unpins" '[["haseen.clock","me.a"],[]]' "$(lists)"
assert_eq "--no-apply skips IPC (the shell's own persist call)" "" "$(ipc_calls)"
capture haseen bar overflow remove haseen.clock
assert_eq "remove" '[["me.a"],[]]' "$(lists)"
capture haseen bar overflow pin me.b
capture haseen bar overflow unpin me.b
assert_eq "unpin" '[["me.a"],[]]' "$(lists)"
before="$(cat "$(CFG)")"
capture haseen bar overflow add me.a --dry-run
assert_dry_pure "add --dry-run (already there)" "$OUTPUT"
assert_not_contains "no write when nothing changes" "$OUTPUT" "DRYRUN: write"
assert_eq "dry run left the file alone" "$before" "$(cat "$(CFG)")"

# The CLI and the shell share one rule: the same edits through Overflow.edit.
cat >"$H/Edit.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/Overflow.js" as O
Item {
    Component.onCompleted: {
        let r = { overflow: [], pinned: [] };
        for (const [verb, id] of [["add", "me.a"], ["add", "haseen.clock"], ["pin", "me.a"], ["add", "me.a"], ["remove", "haseen.clock"], ["pin", "me.b"], ["unpin", "me.b"]])
            r = O.edit(r.overflow, r.pinned, verb, id);
        console.warn("EDIT " + JSON.stringify([r.overflow, r.pinned]));
        Qt.exit(0);
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    js="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "$QML_BIN" "$H/Edit.qml" 2>&1 | sed -n 's/.*EDIT //p')"
    assert_eq "shell and CLI end with the same lists" "$js" "$(lists)"
fi

# Refusals.
capture haseen bar overflow add haseen.tray
assert_status "the tray is refused" 1 "$STATUS"
assert_contains "says why" "$OUTPUT" "never moves to the overflow panel"
capture haseen bar overflow add me.notthere
assert_status "an id not in the bar is refused" 1 "$STATUS"
capture haseen bar overflow pin me.notthere
assert_status "pin needs an id in the bar" 1 "$STATUS"
capture haseen bar overflow remove me.notthere
assert_status "remove of an unknown id is harmless" 0 "$STATUS"
capture haseen bar overflow add NotAnId
assert_status "malformed id refused" 1 "$STATUS"
capture haseen bar overflow toss me.a
assert_status "unknown verb is a usage error" 2 "$STATUS"
capture haseen bar overflow add
assert_status "add needs an id" 2 "$STATUS"
capture haseen bar overflow list me.a
assert_status "list takes no id" 2 "$STATUS"
capture haseen bar overflow
assert_status "a verb is required" 2 "$STATUS"

# list: the saved lists, plus each running bar's panel when a shell answers.
stub qs "echo '{\"overflow\":{\"eDP-1\":{\"ids\":[\"me.a\",\"me.b\"],\"open\":false}}}'"
capture haseen bar overflow list
assert_status "list exits 0" 0 "$STATUS"
assert_contains "list shows bar.overflow" "$OUTPUT" "overflow: me.a"
assert_contains "list shows bar.pinned" "$OUTPUT" "pinned: "
assert_contains "list shows a running bar's panel" "$OUTPUT" "eDP-1: me.a me.b"
stub qs 'echo "No running instances" >&2; exit 1'
capture haseen bar overflow list
assert_status "list without a shell still exits 0" 0 "$STATUS"
assert_not_contains "no live lines without a shell" "$OUTPUT" "eDP-1"
capture haseen bar overflow add me.b
assert_status "no shell running still saves" 0 "$STATUS"
assert_contains "says when it applies" "$OUTPUT" "applies at the next start"

# An unreadable user file is never overwritten.
printf '{"bar": ' >"$(CFG)"
capture haseen bar overflow add me.a
assert_status "invalid shell.json refused" 1 "$STATUS"
assert_eq "invalid shell.json untouched" '{"bar": ' "$(cat "$(CFG)")"

# --- haseen bar move (a drop in arrange mode) ---------------------------------
layout() { jq -c '[.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned]' "$(CFG)"; }

sandbox bar-move-cli
f="$REPO/bin/haseen-bar-move"
assert_eq "haseen-bar-move is executable" yes "$([[ -x $f ]] && echo yes || echo no)"
assert_contains "move takes --dry-run" "$(sed -n 's/^# haseen:args //p' "$f")" "--dry-run"
capture haseen bar move --help
assert_status "move --help exits 0" 0 "$STATUS"
assert_contains "move --help prints usage" "$OUTPUT" "Usage: haseen bar move"
capture haseen commands bar
assert_contains "move is listed with the bar commands" "$OUTPUT" "haseen bar move"

mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"left":["me.l"],"center":["haseen.clock"],"right":["haseen.tray","me.a","me.b"],"overflow":["me.b"],"pinned":[]},"plugins":{"me.a":{"enabled":true}}}\n' >"$(CFG)"
before="$(cat "$(CFG)")"
capture haseen bar move me.a center --before haseen.clock --dry-run
assert_status "move --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "move --dry-run" "$OUTPUT"
assert_contains "move dry run shows the write" "$OUTPUT" "DRYRUN: write $(CFG).new"
assert_contains "move dry run shows the IPC apply" "$OUTPUT" "DRYRUN: haseen shell ipc bar move me.a center haseen.clock false"
assert_eq "move dry run left the file alone" "$before" "$(cat "$(CFG)")"

ipc_stub
capture haseen bar move me.a center --before haseen.clock
assert_status "move exits 0" 0 "$STATUS"
assert_eq "move: to another section, in front of a widget" '[["me.l"],["me.a","haseen.clock"],["haseen.tray","me.b"],["me.b"],[]]' "$(layout)"
assert_eq "move: plugin entries survive" true "$(jq '.plugins["me.a"].enabled' "$(CFG)")"
assert_eq "move: applied live" "qs: -p $HASEEN_PATH/shell ipc call bar move me.a center haseen.clock false" "$(ipc_calls)"
capture haseen bar move me.l right --before haseen.tray --no-apply
assert_eq "move: never in front of the tray" '["haseen.tray","me.l","me.b"]' "$(jq -c .bar.right "$(CFG)")"
assert_eq "move --no-apply skips IPC" "" "$(ipc_calls)"
capture haseen bar move me.a overflow --before me.b --no-apply
assert_eq "move: into the panel, in front of another" '[[],["me.a","haseen.clock"],["haseen.tray","me.l","me.b"],["me.a","me.b"],[]]' "$(layout)"
capture haseen bar move me.b left --pin --no-apply
assert_eq "move --pin: out of the panel and kept in the bar" '[["me.b"],["me.a","haseen.clock"],["haseen.tray","me.l"],["me.a"],["me.b"]]' "$(layout)"
before="$(cat "$(CFG)")"
capture haseen bar move me.l right --before me.l --dry-run
assert_not_contains "move in front of itself writes nothing" "$OUTPUT" "DRYRUN: write"
assert_eq "move in front of itself left the file alone" "$before" "$(cat "$(CFG)")"

# The CLI and the shell share one rule: the same drops through Overflow.move.
cat >"$H/Move.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/Overflow.js" as O
Item {
    Component.onCompleted: {
        let r = { left: ["me.l"], center: ["haseen.clock"], right: ["haseen.tray", "me.a", "me.b"], overflow: ["me.b"], pinned: [] };
        for (const [id, to, before, pin] of [["me.a", "center", "haseen.clock", false], ["me.l", "right", "haseen.tray", false],
                                             ["me.a", "overflow", "me.b", false], ["me.b", "left", "", true], ["me.l", "right", "me.l", false]])
            r = O.move(r, id, to, before, pin);
        console.warn("MOVE " + JSON.stringify([r.left, r.center, r.right, r.overflow, r.pinned]));
        Qt.exit(0);
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    js="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "$QML_BIN" "$H/Move.qml" 2>&1 | sed -n 's/.*MOVE //p')"
    assert_eq "shell and CLI end with the same bar" "$js" "$(layout)"
fi

capture haseen bar move haseen.tray left
assert_status "move refuses the tray" 1 "$STATUS"
assert_contains "move says why" "$OUTPUT" "never moves"
capture haseen bar move me.notthere left
assert_status "move needs an id in the bar" 1 "$STATUS"
capture haseen bar move me.a middle
assert_status "move: unknown target is a usage error" 2 "$STATUS"
capture haseen bar move me.a
assert_status "move needs a target" 2 "$STATUS"
capture haseen bar move me.a left --before
assert_status "move: --before needs an id" 2 "$STATUS"
capture haseen bar move me.a left --before NotAnId
assert_status "move: malformed --before refused" 1 "$STATUS"
printf '{"bar": ' >"$(CFG)"
capture haseen bar move me.a left
assert_status "move: invalid shell.json refused" 1 "$STATUS"
assert_eq "move: invalid shell.json untouched" '{"bar": ' "$(cat "$(CFG)")"

# --- haseen bar arrange (session only) -----------------------------------------
sandbox bar-arrange-cli
capture haseen bar arrange --help
assert_status "arrange --help exits 0" 0 "$STATUS"
assert_contains "arrange --help prints usage" "$OUTPUT" "Usage: haseen bar arrange"
capture haseen bar arrange --dry-run
assert_status "arrange --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "arrange --dry-run" "$OUTPUT"
assert_contains "arrange defaults to toggle" "$OUTPUT" "bar arrange toggle"
ipc_stub
capture haseen bar arrange on
assert_status "arrange on exits 0" 0 "$STATUS"
assert_eq "arrange asks the running shell" "qs: -p $HASEEN_PATH/shell ipc call bar arrange on" "$(ipc_calls)"
capture haseen bar arrange sideways
assert_status "arrange: unknown mode is a usage error" 2 "$STATUS"
assert_eq "arrange writes no shell.json" no "$([[ -e $(CFG) ]] && echo yes || echo no)"
