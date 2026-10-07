# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.menu's view (plan 068), under the real Qt JS engine: an asynchronous
# guard answer updates a real ListModel in place, keeps the selected row and
# its delegate; and secondary text (menu descriptions, launcher subtitles)
# reads at 3:1 on normal and selected rows in every stock theme, computed
# from each theme's rendered shell.json with the shell's own colour code
# (Haseen/Ink.js through Theme.subtle, MenuStyle.js).

MENU="$HASEEN_PATH/shell/plugins/haseen.menu"
INK="$HASEEN_PATH/shell/Haseen/Ink.js"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

assert_eq "menu opens as Omarchy's overlay" "overlay" "$(jq -r '.settings.placement.default' "$MENU/manifest.json")"
assert_eq "menu debug hook off by default" "false" "$(jq -r '.settings.debugIpc.default' "$MENU/manifest.json")"

# Every stock theme's rendered tokens, the way `haseen theme set` writes them.
tokens="["
for dir in "$HASEEN_PATH"/themes/*/; do
    t="$(basename "$dir")"
    sandbox "menu-view-$t"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS HASEEN_THEME_HEADLESS
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run"
    capture haseen theme set "$t"
    assert_status "render $t" 0 "$STATUS"
    tokens+="$(jq -c --arg t "$t" '{t: $t, background, surface, foreground, selection}' "$HOME/.local/state/haseen/current/theme/shell.json"),"
done
tokens="${tokens%,}]"
themes=$(($(grep -o '"t":' <<<"$tokens" | wc -l)))

sandbox menu-view
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$MENU/MenuModel.js" as M
import "file://$MENU/MenuStyle.js" as S
import "file://$INK" as Ink

Window {
    id: win

    property int failures: 0
    width: 300
    height: 800
    visible: true

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    ListModel {
        id: model
    }

    ListView {
        id: list

        width: 300
        height: 800
        model: model
        delegate: Item {
            required property string itemId
            required property string label

            width: 300
            height: 40
        }
    }

    // The System submenu as Panel.qml builds it: visible children, one row each.
    function rows(m, guards) {
        const out = [];
        for (const id of m.itemOrder) {
            const e = m.items[id];
            if (e && e.parent === "system" && M.isVisible(m.items, m.itemOrder, guards.w, e, 0))
                out.push(M.displayRow(m.items, m.itemOrder, guards.c, guards.d, e, e.description, ""));
        }
        return out;
    }

    function delegates() {
        list.forceLayout();
        const out = {};
        for (let i = 0; i < model.count; i++)
            out[model.get(i).itemId] = list.itemAtIndex(i);
        return out;
    }

    // Panel.qml's rebuildDisplay(true): sync in place, keep the selected row.
    function refresh(m, guards, current) {
        const keep = model.get(current).itemId;
        const next = rows(m, guards);
        const ops = M.syncRows(model, next);
        return { ops: ops, current: M.selectionAfter(next, keep, current) };
    }

    function hex(s) {
        return Qt.lighter(s, 1.0);
    }

    // Theme.subtle(bg): the foreground at the raised alpha, drawn over bg.
    function subtleRatio(fg, bg) {
        const a = Ink.readableAlpha(fg, bg, Ink.SUBTLE, Ink.MIN_RATIO);
        return { alpha: a, ratio: Ink.ratio(Ink.over(fg, a, bg), bg) };
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
        const m = M.mergeMenuSources(M.parseMenuJsonc('{"system": {"label": "System"},' +
            '"system.lock": {"label": "Lock", "action": "x", "checked": "c"},' +
            '"system.suspend": {"label": "Suspend", "action": "x"},' +
            '"system.hibernate": {"label": "Hibernate", "action": "x", "when": "w"},' +
            '"system.logout": {"label": "Logout", "action": "x"},' +
            '"system.reboot": {"label": "Reboot", "action": "x"}}'), []);
        const none = { w: {}, c: {}, d: {} };
        M.syncRows(model, rows(m, none));
        eq("before the guards answer, a when row is hidden", ["system.lock", "system.suspend", "system.logout", "system.reboot"], rows(m, none).map(r => r.itemId));
        const before = delegates();

        // The batch answers: Hibernate appears above the selected Logout and
        // Lock gains its check mark.
        const answered = { w: { "system.hibernate": true }, c: { "system.lock": true }, d: {} };
        let r = refresh(m, answered, 2);
        const after = delegates();
        eq("the selection stays on Logout", "system.logout", model.get(r.current).itemId);
        eq("which moved down one row", 3, r.current);
        eq("the new row is in place", "system.hibernate", model.get(2).itemId);
        eq("the delegates exist", true, !!before["system.logout"] && !!after["system.logout"] && !!after["system.lock"]);
        eq("Logout keeps its delegate", true, before["system.logout"] === after["system.logout"]);
        eq("Reboot keeps its delegate", true, before["system.reboot"] === after["system.reboot"]);
        eq("Lock keeps its delegate", true, before["system.lock"] === after["system.lock"]);
        eq("Lock's label is updated in place", "Lock ✓", after["system.lock"].label);

        // The same answer again changes nothing at all.
        r = refresh(m, answered, 3);
        eq("an unchanged answer writes nothing", 0, r.ops);
        eq("and keeps the selection", 3, r.current);

        // The selected row itself goes away: the cursor stays at its place.
        r = refresh(m, none, 2);
        eq("a vanished selected row leaves the cursor in place", "system.logout", model.get(r.current).itemId);
        eq("rows after the change", ["system.lock", "system.suspend", "system.logout", "system.reboot"], [0, 1, 2, 3].map(i => model.get(i).itemId));

        // Secondary text in every stock theme.
        const themes = $tokens;
        for (const t of themes) {
            const bg = hex(t.background), fg = hex(t.foreground);
            const menuSelected = Ink.over(fg, S.SELECTED_FILL, bg);
            const checks = {
                "menu description, selected row": menuSelected,
                "menu description, card": bg,
                "launcher subtitle, selected row": hex(t.selection),
                "launcher subtitle, panel": hex(t.surface)
            };
            for (const name in checks) {
                const s = subtleRatio(fg, checks[name]);
                eq(t.t + ": " + name + " reads at 3:1", true, s.ratio >= 3);
            }
        }
        // Where Omarchy's own alpha already reads, it is kept as is.
        const haseen = themes.filter(t => t.t === "haseen")[0];
        const hbg = hex(haseen.background), hfg = hex(haseen.foreground);
        eq("haseen: Omarchy's 0.52 kept on the selected menu row", 0.52, subtleRatio(hfg, Ink.over(hfg, S.SELECTED_FILL, hbg)).alpha);
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "menu view unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "menu view unit count" "$((14 + themes * 4))" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML_BIN"
fi
