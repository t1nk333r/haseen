# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-settings bin/haseen-plugin-validate bin/haseen-update
# haseen:covers bin/haseen-update-check share/haseen/VERSION share/haseen/default/shell.json
# haseen:covers share/haseen/lib/packages.sh share/haseen/migrations/1791560000-adopt-bar-basics.sh
# haseen:covers share/haseen/omarchy/bin/omarchy share/haseen/shell/{Bar,BarStrip}.qml
# haseen:covers share/haseen/shell/Overflow.js share/haseen/shell/Compat/**
# haseen:covers share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/*/manifest.json
# haseen:covers share/haseen/shell/plugins/haseen.{active-window,nook,power,updates}/**
# haseen:covers tests/fixtures/bar-basics/** tools/fake-upower.py tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 095: four of the owner's plugins adopted as first-party, off by
# default: haseen.active-window, haseen.power, haseen.updates, haseen.nook.
# Manifests and defaults; what the code may and may not use (no Omarchy, no
# hex colours, Apps.launch for the updater); the pure JS (Title.js, both
# Model.js, Overflow.fit's `never`) under the real Qt JS engine; `haseen
# update check` against stub checkupdates and paru; the four widgets and the
# updates panel in the real Quickshell engine (haseen.power on a fake UPower,
# the nook against a stand-in bar window); and the migration on fixture
# HOMEs.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
DEFAULT="$HASEEN_PATH/default/shell.json"
MIGRATION=1791560000-adopt-bar-basics.sh
IDS=(haseen.active-window haseen.power haseen.updates haseen.nook)
DIRS=()
for id in "${IDS[@]}"; do DIRS+=("$PLUGINS/$id"); done

# --- manifests and defaults ----------------------------------------------------
sandbox bar-basics
capture haseen plugin validate "${IDS[@]}"
assert_status "the four plugins validate" 0 "$STATUS"
for id in "${IDS[@]}"; do
    assert_contains "$id validates" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "none asks for the network" "$OUTPUT" "warning:"
assert_eq "kinds" "bar-widget|bar-widget|bar-widget panel|bar-widget" \
    "$(for id in "${IDS[@]}"; do jq -r '.kinds | join(" ")' "$PLUGINS/$id/manifest.json"; done | paste -sd'|')"
for id in "${IDS[@]}"; do
    assert_eq "$id is off by default" "false" "$(jq --arg id "$id" '.plugins[$id].enabled' "$DEFAULT")"
    assert_eq "$id is in no default bar list or service" "false" \
        "$(jq --arg id "$id" '[.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned, .services] | add | index($id) != null' "$DEFAULT")"
    entry="$(cat "$PLUGINS/$id/Widget.qml")"
    assert_contains "$id declares pluginId" "$entry" "property string pluginId"
    assert_contains "$id declares settings" "$entry" "property var settings: ({})"
    assert_contains "$id declares screen" "$entry" "property var screen: null"
    assert_eq "$id settings are typed and described" "" \
        "$(jq -r '.settings | to_entries[] | select((.value.type | not) or (.value.description | not)) | .key' "$PLUGINS/$id/manifest.json")"
    for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGINS/$id"/*.qml | cut -d. -f2 | sort -u); do
        assert_eq "$id declares the setting $key it reads" "$key" \
            "$(jq -r --arg k "$key" '.settings | has($k) | if . then $k else "undeclared" end' "$PLUGINS/$id/manifest.json")"
    done
done
assert_eq "updates defaults: 30 min, hidden when current, one total, 20 lines" "30 false false 20" \
    "$(jq -r '[.settings.interval.default, .settings.alwaysShow.default, .settings.splitAur.default, .settings.listLines.default] | map(tostring) | join(" ")' "$PLUGINS/haseen.updates/manifest.json")"
assert_eq "power shows the percentage by default" "true" "$(jq '.settings.showPercentage.default' "$PLUGINS/haseen.power/manifest.json")"
assert_eq "active-window: 50 characters, no pixel clamp" "50 0" \
    "$(jq -r '[.settings.maxChars.default, .settings.maxWidth.default] | map(tostring) | join(" ")' "$PLUGINS/haseen.active-window/manifest.json")"
assert_eq "permissions" "|exec files:write|exec files:read|" \
    "$(for id in "${IDS[@]}"; do jq -r '.permissions | sort | join(" ")' "$PLUGINS/$id/manifest.json"; done | paste -sd'|')"

# --- what the code may use -----------------------------------------------------
assert_eq "no Omarchy command, path, module or updater" "" \
    "$(grep -rnE 'omarchy-|OMARCHY_PATH|qs\.Commons|qs\.Ui|import qs\.(Common|Services|Widgets|Modules)\b' "${DIRS[@]}" "$REPO/bin/haseen-update-check" || true)"
assert_eq "no hex colour literals" "" "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "${DIRS[@]}" --include='*.qml' --include='*.js' || true)"
assert_eq "colours come from Theme only" "" \
    "$(grep -rnE '(^|[^a-zA-Z])color(\.[a-z]+)?:' "${DIRS[@]}" --include='*.qml' | grep -vE 'Theme\.' || true)"
assert_eq "no privilege escalation" "" "$(grep -rnE '\b(sudo|pkexec|run_root)\b' "${DIRS[@]}" "$REPO/bin/haseen-update-check" || true)"
assert_eq "no blur or shader" "" "$(grep -rnE 'MultiEffect|ShaderEffect|FastBlur|GaussianBlur|layer\.effect' "${DIRS[@]}" || true)"
assert_eq "the panel shows outside text as plain text" "2 2" \
    "$(printf '%s %s' "$(grep -c 'text: modelData' "$PLUGINS/haseen.updates/Panel.qml")" "$(grep -c 'textFormat: Text.PlainText' "$PLUGINS/haseen.updates/Panel.qml")")"
up="$(cat "$PLUGINS/haseen.updates/Widget.qml" "$PLUGINS/haseen.updates/Panel.qml")"
assert_contains "the updater runs through Apps.launch" "$up" 'Apps.launch([root.binDir + "/haseen-update"])'
assert_contains "the count comes from haseen update check" "$up" '"/haseen-update-check"'
assert_contains "haseen.updates explains itself on hover" "$up" "barTooltip"
assert_contains "the bar shows a native widget's tooltip" "$(cat "$SHELL_DIR/BarSlot.qml")" $'Compat.Tooltip {\n        target: hover.hovered'
assert_eq "haseen.updates has no command setting" "false" "$(jq '.settings | has("onClick")' "$PLUGINS/haseen.updates/manifest.json")"
assert_eq "the nook is no second drawer: no window of its own" "" \
    "$(grep -nE 'PanelWindow|PopupWindow|FloatingWindow|WlrLayershell|Repeater' "$PLUGINS/haseen.nook"/*.qml || true)"
assert_contains "the power button opens haseen.battery's panel" "$(cat "$PLUGINS/haseen.power/Widget.qml")" '"panel", "toggle", "haseen.battery"'
# The bar's contents are BarStrip.qml since plan 112.
bar="$(cat "$SHELL_DIR/BarStrip.qml")"
assert_contains "the bar keeps the nook out of the panel it opens" "$bar" 'never: [nookId]'
assert_contains "the bar's chevron gives way to the nook outside arrange mode and drags" "$bar" 'visible: strip.dragArmed || (strip.nookHosted ? strip.arranging : strip.fit.button || strip.overflowOpen)'

# --- pure JS under the real Qt JS engine -----------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.active-window/Title.js" as T
import "file://$PLUGINS/haseen.updates/Model.js" as U
import "file://$PLUGINS/haseen.power/Model.js" as P
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
        // Title.js
        eq("a short title is kept", "foot", T.label("foot", 50));
        eq("exactly the budget is kept", "abcdefghij", T.label("abcdefghij", 10));
        eq("a long title keeps its head and tail", "abcd…wxyz", T.label("abcdefghijklmnopqrstuvwxyz", 9));
        eq("an even budget leans to the head", "abcd…xyz", T.label("abcdefghijklmnopqrstuvwxyz", 8));
        eq("the budget counts characters, not code units", "\u{1F600}\u{1F600}…\u{1F600}\u{1F600}",
           T.label("\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}", 5));
        eq("no surrogate pair is cut", false, /[\uD800-\uDBFF](?![\uDC00-\uDFFF])/.test(T.label("a\u{1F600}b\u{1F600}c\u{1F600}d\u{1F600}e", 4)));
        eq("budget: unset is 50", 50, T.budget(undefined));
        eq("budget: a string number counts", 12, T.budget("12"));
        eq("budget: at least 3", 3, T.budget(1));
        eq("budget: junk is 50", 50, T.budget("lots"));
        eq("title: the title", "Doc", T.titleOf({ title: "Doc", appId: "x" }));
        eq("title: else the app id", "foot", T.titleOf({ title: "", appId: "foot" }));
        eq("title: no window", "", T.titleOf(null));

        // updates Model.js
        const r = U.parse('{"repo":2,"aur":1,"lines":["a 1 -> 2","b 1 -> 2","c 1 -> 2  (AUR)"],"errors":[],"cached":true}');
        eq("parse: counts and lines", [2, 1, 3, 0], [r.repo, r.aur, r.lines.length, r.errors.length]);
        eq("parse: junk is one error", ["haseen update check gave no JSON"], U.parse("oops").errors);
        eq("parse: an array is no answer", 1, U.parse("[1]").errors.length);
        eq("parse: a negative or fractional count is 0", [0, 0], [U.parse('{"repo":-3,"aur":1.5}').repo, U.parse('{"repo":-3,"aur":1.5}').aur]);
        eq("parse: non-string lines are dropped", ["x"], U.parse('{"lines":["x",3,null]}').lines);
        eq("label: one total", "3", U.countLabel(r, false));
        eq("label: split", "2+1", U.countLabel(r, true));
        eq("label: split without AUR", "4", U.countLabel(U.parse('{"repo":4}'), true));
        eq("label: nothing pending", "", U.countLabel(U.parse('{"repo":0}'), false));
        eq("shown: pending", true, U.shown(r, false));
        eq("shown: current, hidden", false, U.shown(U.parse('{"repo":0}'), false));
        eq("shown: current with alwaysShow", true, U.shown(U.parse('{"repo":0}'), true));
        eq("shown: a failed check", true, U.shown(U.parse('{"errors":["x"]}'), false));
        eq("shown: before the first answer", false, U.shown(null, false));
        eq("summary: pending", "3 updates · repo 2 · AUR 1", U.summary(r, false));
        eq("summary: one", "1 update · repo 1 · AUR 0", U.summary(U.parse('{"repo":1}'), false));
        eq("summary: current", "System up to date", U.summary(U.parse('{}'), false));
        eq("summary: incomplete", "Check incomplete", U.summary(U.parse('{"errors":["x"]}'), false));
        eq("summary: checking", "Checking for updates…", U.summary(null, true));
        eq("listed: within the limit", 3, U.listed(r, 20).length);
        eq("listed: the rest summed up", ["a 1 -> 2", "… and 2 more"], U.listed(r, 1));
        eq("listed: none", ["… and 3 more"], U.listed(r, 0));
        eq("interval: default", 30, U.intervalMinutes(undefined));
        eq("interval: floor 2", 2, U.intervalMinutes(1));
        eq("interval: kept", 45, U.intervalMinutes("45"));
        eq("interval: at most a day", 1440, U.intervalMinutes(99999));

        // power Model.js (UPowerDeviceState numbers)
        const dev = (state, pct, rate, ttf) => ({ isPresent: true, state: state, percentage: pct, changeRate: rate, timeToFull: ttf });
        eq("held: pending charge", true, P.chargeHeld(dev(5, 0.8, 0, 0), false));
        eq("held: full below 99 %", true, P.chargeHeld(dev(4, 0.8, 0, 0), false));
        eq("held: truly full", false, P.chargeHeld(dev(4, 1, 0, 0), false));
        eq("held: a trickle", true, P.chargeHeld(dev(1, 0.8, 0.1, 0), false));
        eq("held: eight hours to full", true, P.chargeHeld(dev(1, 0.8, 5, 8 * 3600), false));
        eq("held: really charging", false, P.chargeHeld(dev(1, 0.5, 20, 3600), false));
        eq("held: never on battery", false, P.chargeHeld(dev(5, 0.8, 0, 0), true));
        eq("held: no battery", false, P.chargeHeld(null, false));
        eq("glyph: on battery, the level in tenths (55 % is the sixth)", "\u{F007F}", P.glyph(dev(2, 0.55, 9, 0), true));
        eq("glyph: charging", "\u{F0089}", P.glyph(dev(1, 0.55, 20, 3600), false));
        eq("glyph: held shows the level, not charging", "\u{F007F}", P.glyph(dev(5, 0.55, 0, 0), false));
        eq("glyph: full", "\u{F0085}", P.glyph(dev(4, 1, 0, 0), false));
        eq("glyph: no battery", "", P.glyph({ isPresent: false }, false));
        eq("percentage: default on", true, P.showPercentage(undefined));
        eq("percentage: the string false is off", false, P.showPercentage("false"));
        eq("percentage: false is off", false, P.showPercentage(false));
        eq("percentage: the string true is on", true, P.showPercentage("true"));

        // Overflow.fit: an id in never stays in the bar, even listed in bar.overflow.
        const spec = (overflow, length) => ({ length: length, spacing: 4, gap: 8, button: 0, hysteresis: 16,
            left: [], center: [], right: [{ id: "haseen.tray", size: 20 }, { id: "haseen.nook", size: 20 }, { id: "me.a", size: 60 }, { id: "me.b", size: 60 }],
            overflow: overflow, pinned: [], never: ["haseen.nook"] });
        eq("never: bar.overflow cannot take the nook", ["me.a"], O.fit(spec(["haseen.nook", "me.a"], 1000), null).ids);
        eq("never: a short bar never pushes the nook out", false, O.fit(spec([], 60), null).ids.indexOf("haseen.nook") >= 0);
    }
}
EOF
if [[ -x $QML ]]; then
    capture env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML" "$H/Units.qml"
    assert_status "JS units run under the Qt JS engine" 0 "$STATUS"
    assert_eq "no JS unit fails" "" "$(grep 'UNIT-FAIL' <<<"$OUTPUT" || true)"
    assert_eq "every JS unit ran" "58" "$(grep -c 'UNIT-PASS' <<<"$OUTPUT")"
else
    _fail "qml missing: $QML"
fi

# --- haseen update check ---------------------------------------------------------
sandbox update-check
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/etc" && : >"$ROOT/etc/arch-release"
export HASEEN_SYSROOT="$ROOT"
LOG="$SANDBOX/calls.log"
stub checkupdates "printf 'checkupdates %s db=%s\n' \"\$*\" \"\$CHECKUPDATES_DB\" >>'$LOG'
printf 'linux 6.17.1-1 -> 6.17.2-1\n\033[1mmesa\033[0m 25.2-1 -> 25.3-1\n'"
stub paru "printf 'paru %s\n' \"\$*\" >>'$LOG'; echo 'helium-browser-bin 0.5 -> 0.6'"
capture haseen update check
assert_status "check exits 0" 0 "$STATUS"
assert_eq "repo and AUR counted, colours stripped, AUR marked" \
    '{"repo":2,"aur":1,"lines":["linux 6.17.1-1 -> 6.17.2-1","mesa 25.2-1 -> 25.3-1","helium-browser-bin 0.5 -> 0.6  (AUR)"],"errors":[],"cached":false}' "$OUTPUT"
assert_contains "checkupdates uses its own database" "$(cat "$LOG")" "checkupdates --nocolor db=$XDG_RUNTIME_DIR/haseen/updates-db"
assert_contains "the AUR is compared with -Qua" "$(cat "$LOG")" "paru -Qua"
: >"$LOG"
capture haseen update check
assert_eq "a second check within a minute reads the cache" "true" "$(jq .cached <<<"$OUTPUT")"
assert_eq "and runs nothing" "" "$(cat "$LOG")"
capture haseen update check --force
assert_eq "--force checks again" "false 2" "$(jq -r '"\(.cached) \(.repo)"' <<<"$OUTPUT")"
stub checkupdates 'exit 2'
stub paru 'exit 1'
capture haseen update check --force
assert_eq "nothing pending (checkupdates 2, paru 1 without output)" '{"repo":0,"aur":0,"lines":[],"errors":[],"cached":false}' "$OUTPUT"
stub checkupdates 'exit 1'
stub paru 'echo "error: rpc request failed" >&2; exit 1'
capture haseen update check --force
assert_status "a failed check still exits 0" 0 "$STATUS"
assert_eq "both failures named" '["repo check failed (checkupdates exit 1)","AUR check failed (paru exit 1)"]' "$(jq -c .errors <<<"$OUTPUT")"
assert_eq "a failed check is not cached (the last clean one stays)" '{"repo":0,"aur":0,"lines":[],"errors":[],"cached":true}' \
    "$(cat "$XDG_RUNTIME_DIR/haseen/updates.json")"
capture haseen update check --dry-run
assert_contains "dry run prints the repo check" "$OUTPUT" "DRYRUN: env CHECKUPDATES_DB=$XDG_RUNTIME_DIR/haseen/updates-db checkupdates --nocolor"
assert_contains "dry run prints the AUR check" "$OUTPUT" "DRYRUN: paru -Qua"
assert_dry_pure "update check" "$OUTPUT"
capture haseen update check --nope
assert_status "an unknown flag is refused" 2 "$STATUS"
HASEEN_SYSROOT="$SANDBOX/elsewhere" capture haseen update check
assert_eq "not Arch: one error, no check" '["not an Arch-based system"]' "$(jq -c .errors <<<"$OUTPUT")"
# Without checkupdates or an AUR helper on PATH: a toolbox of just the
# commands the check itself needs.
tools="$SANDBOX/tools"
mkdir -p "$tools"
for c in bash jq sed stat date flock mktemp mv cat rm mkdir dirname readlink env id; do ln -s "$(command -v "$c")" "$tools/$c"; done
capture env PATH="$tools" "$REPO/bin/haseen-update-check" --force
assert_eq "no checkupdates is named; no AUR helper is no error" '["checkupdates is not installed (pacman-contrib)"]' "$(jq -c .errors <<<"$OUTPUT")"
unset HASEEN_SYSROOT

# --- the widgets and the panel in the real engine ----------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    _fail "qs missing: $QS_BIN"
else
    sandbox bar-basics-engine
    ROOT="$SANDBOX/root"
    mkdir -p "$ROOT/etc" && : >"$ROOT/etc/arch-release"
    LOG="$SANDBOX/calls.log"
    : >"$LOG"
    stub checkupdates "printf 'linux 1 -> 2\nmesa 1 -> 2\n'"
    stub paru "echo 'helium-browser-bin 0.5 -> 0.6'"
    stub systemd-run "printf 'systemd-run %s\n' \"\$*\" >>'$LOG'"
    stub qs "printf 'qs %s\n' \"\$*\" >>'$LOG'"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.active-window" as Aw
import "plugins/haseen.updates" as Up
import "plugins/haseen.nook" as Nook
ShellRoot {
    id: shellRoot

    property var states: []

    function snap(): var {
        return {
            aw: { visible: aw.visible, width: aw.implicitWidth, text: aw.text, activated: fake.activated, closed: fake.closed },
            up: { visible: up.visible, width: up.implicitWidth, text: up.text, glyph: up.glyph, failed: up.failed },
            panel: { lines: panel.result ? panel.result.lines.length : -1, repo: panel.result ? panel.result.repo : -1 },
            nook: { visible: nook.visible, width: nook.implicitWidth, glyph: nook.glyph, highlighted: nook.highlighted, registered: host.nookItem === nook, calls: host.calls },
            inert: { hosted: inert.hosted, visible: inert.visible }
        };
    }

    QtObject {
        id: fake

        property string title: "A rather long window title, really"
        property string appId: "foot"
        property int activated: 0
        property int closed: 0

        function activate() { activated++; }
        function close() { closed++; }
    }

    FloatingWindow {
        implicitWidth: 700
        implicitHeight: 40
        visible: true

        Row {
            height: 28

            Aw.Widget {
                id: aw
                pluginId: "haseen.active-window"
                settings: ({ maxChars: 9 })
                toplevel: fake
            }

            Up.Widget {
                id: up
                pluginId: "haseen.updates"
                settings: ({ splitAur: true })
            }
        }
    }

    FloatingWindow {
        implicitWidth: 500
        implicitHeight: 300
        visible: true

        Up.Panel {
            id: panel
            pluginId: "haseen.updates"
            settings: ({ listLines: 1 })
        }
    }

    // A stand-in for the bar window: the part of Bar.qml the nook uses.
    FloatingWindow {
        id: host

        property var fit: ({ button: false })
        property bool overflowOpen: false
        property bool arranging: false
        readonly property string overflowGlyph: overflowOpen ? "" : ""
        property Item nookItem: null
        property var calls: []

        function toggleOverflowFrom(item: Item): void {
            calls = calls.concat([item === nook ? "toggle from the nook" : "toggle"]);
            overflowOpen = !overflowOpen;
        }
        function setArranging(on: bool): void {
            calls = calls.concat(["arrange " + on]);
            arranging = on;
        }

        implicitWidth: 200
        implicitHeight: 40
        visible: true

        Nook.Widget {
            id: nook
            pluginId: "haseen.nook"
            height: 28
        }
    }

    // Anywhere else (here: a plain window) the nook does nothing.
    FloatingWindow {
        implicitWidth: 100
        implicitHeight: 40
        visible: true

        Nook.Widget {
            id: inert
            pluginId: "haseen.nook"
            height: 28
        }
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            aw.clicked(Qt.LeftButton);
            aw.clicked(Qt.MiddleButton);
            aw.clicked(Qt.RightButton);
            up.clicked(Qt.LeftButton);
            up.clicked(Qt.RightButton);
            host.fit = { button: true };
            nook.clicked(Qt.LeftButton);
            nook.clicked(Qt.RightButton);
            inert.clicked(Qt.LeftButton);
            second.start();
        }
    }

    Timer {
        id: second
        interval: 600
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            // A newer clean result in the cache (another bar's check) is
            // adopted.
            up.adoptCache('{"repo":5,"aur":0,"lines":[],"errors":[],"cached":true}');
            fake.title = "";
            fake.appId = "";
            host.overflowOpen = false;
            host.fit = { button: false };
            third.start();
        }
    }

    Timer {
        id: third
        interval: 400
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            console.warn("RESULT " + JSON.stringify(shellRoot.states));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        HASEEN_SYSROOT="$ROOT" timeout 60 "$QS_BIN" -p "$harness"
    assert_status "the harness completes in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    CALLS="$(cat "$LOG")"
    s() { jq -c ".[$1]$2" <<<"$RESULT"; }
    assert_eq "active-window: the title within 9 characters" '"A ra…ally"' "$(s 0 .aw.text)"
    assert_eq "active-window: takes room with a window" "true" "$(jq '.[0].aw | .visible and .width > 0' <<<"$RESULT")"
    assert_eq "active-window: left focuses, middle and right close" '[1,2]' "$(jq -c '.[1].aw | [.activated, .closed]' <<<"$RESULT")"
    assert_eq "active-window: no window takes no room" '[false,0]' "$(jq -c '.[2].aw | [.visible, .width]' <<<"$RESULT")"
    assert_eq "updates: the split count from the check" '"2+1"' "$(s 0 .up.text)"
    assert_eq "updates: shown while updates wait" "true" "$(jq '.[0].up | .visible and .width > 0 and (.failed | not)' <<<"$RESULT")"
    assert_contains "updates: a left click runs haseen update in its own scope" "$CALLS" "systemd-run --user --scope --slice=app-graphical.slice --collect --quiet --unit=app-haseen-haseen_update-"
    assert_contains "updates: … haseen's updater, never Omarchy's" "$CALLS" "-- $REPO/bin/haseen-update"
    assert_contains "updates: a right click toggles the list" "$CALLS" "call panel toggle haseen.updates"
    assert_eq "updates: a newer cached result is adopted" '"5"' "$(s 2 .up.text)"
    assert_eq "panel: the check read on open" '{"lines":3,"repo":2}' "$(s 0 .panel)"
    assert_eq "nook: nothing in overflow takes no room" '[false,0]' "$(jq -c '.[0].nook | [.visible, .width]' <<<"$RESULT")"
    assert_eq "nook: registers with its bar" "true" "$(s 0 .nook.registered)"
    assert_eq "nook: shows while something is in overflow" "true" "$(jq '.[1].nook | .visible and .width > 0' <<<"$RESULT")"
    assert_eq "nook: a left click opens the panel from the nook, a right click arranges" '["toggle from the nook","arrange true"]' "$(s 1 .nook.calls)"
    assert_eq "nook: open, it shows the bar's turned chevron (U+F077), highlighted" '[61559,true]' "$(jq -c '.[1].nook | [(.glyph | explode[0]), .highlighted]' <<<"$RESULT")"
    assert_eq "nook: empty again, no room" "false" "$(s 2 .nook.visible)"
    assert_eq "nook: outside a bar it is inert and hidden" '{"hosted":false,"visible":false}' "$(s 1 .inert)"
    assert_not_contains "no Omarchy updater anywhere" "$CALLS" "omarchy"

fi

# haseen.power on a fake UPower (tools/fake-upower.py on a private bus). The
# fake needs dbus-daemon and python's dbus and gi; CI, which requires the
# engine, installs them (python-dbus python-gobject), and a run without them
# says so instead of reading a missing battery as a failure of the widget.
if [[ ! -x $QS_BIN ]] || ! command -v dbus-daemon >/dev/null || ! python3 -c 'import dbus, gi' 2>/dev/null; then
    echo "  skip: qs, dbus-daemon or python3-dbus missing; haseen.power not run on a fake UPower" >&2
    if [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]]; then
        assert_eq "power: fake UPower prerequisites (dbus-daemon, python dbus and gi)" available unavailable
    fi
else
    sandbox bar-basics-power
    LOG="$SANDBOX/calls.log"
    : >"$LOG"
    stub qs "printf 'qs %s\n' \"\$*\" >>'$LOG'"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.power" as Power
ShellRoot {
    id: shellRoot

    property var states: []

    function snap(): var {
        return { visible: power.visible, width: power.implicitWidth, glyph: power.glyph, text: power.text };
    }

    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 40
        visible: true

        Power.Widget {
            id: power
            pluginId: "haseen.power"
            settings: Plugins.settingsFor("haseen.power")
            height: 28
        }
    }

    // Snapshots 1.5 s apart against the fake's script (on battery, then
    // held by the limit, then charging); the clicks after the third.
    Timer {
        property int n: 0

        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            if (++n === 3) {
                power.clicked(Qt.RightButton);
                power.clicked(Qt.LeftButton);
            }
            if (n === 5) {
                console.warn("RESULT " + JSON.stringify(shellRoot.states));
                Qt.quit();
            }
        }
    }
}
QML
    bus="$(mktemp -d "${TMPDIR:-/tmp}/haseen-power.XXXXXX")"
    dbus-daemon --config-file="$REPO/tools/smoke-session.conf" --fork \
        --address="unix:path=$bus/system" --print-pid=3 3>"$bus/pid"
    printf '%s\n' client "sleep=2 OnBattery=false State=5" "sleep=3.5 State=1 EnergyRate=20 TimeToFull=3600" |
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$bus/system" timeout 60 python3 "$REPO/tools/fake-upower.py" \
            Percentage=55 State=2 >"$SANDBOX/fake.log" 2>&1 &
    fake=$!
    for _ in $(seq 50); do grep -q ready "$SANDBOX/fake.log" && break; sleep 0.1; done
    capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$bus/system" \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    kill "$fake" "$(cat "$bus/pid")" 2>/dev/null || true
    wait "$fake" 2>/dev/null || true
    rm -rf "$bus"
    assert_status "the power harness completes in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    assert_eq "power: on battery, the 55 % level glyph (U+F007F) and the percentage" '[983167,"55%"]' "$(jq -c '.[0] | [(.glyph | explode[0]), .text]' <<<"$RESULT")"
    assert_eq "power: plugged in and held by the limit, still the level glyph" '983167' "$(jq -c '.[1].glyph | explode[0]' <<<"$RESULT")"
    assert_eq "power: a right click hides the percentage at once" '""' "$(jq -c '.[3].text' <<<"$RESULT")"
    assert_eq "power: charging, the 55 % charging glyph (U+F0089)" '983177' "$(jq -c '.[4].glyph | explode[0]' <<<"$RESULT")"
    assert_eq "power: the right click is saved to shell.json" "false" \
        "$(jq '.plugins["haseen.power"].settings.showPercentage' "$XDG_CONFIG_HOME/haseen/shell.json" 2>/dev/null)"
    assert_contains "power: a left click opens haseen.battery's panel" "$(cat "$LOG")" "call panel toggle haseen.battery"
fi

# --- the migration on fixture HOMEs --------------------------------------------------
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
sandbox bar-basics-migration
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
mkdir -p "$XDG_CONFIG_HOME/haseen"
OLD_PLUGINS="$XDG_CONFIG_HOME/haseen/plugins"
mkdir -p "$OLD_PLUGINS/t1nk33r.updates" "$OLD_PLUGINS/t1nk33r.nook"
echo '{"id":"t1nk33r.updates"}' >"$OLD_PLUGINS/t1nk33r.updates/manifest.json"
echo '{"id":"t1nk33r.nook"}' >"$OLD_PLUGINS/t1nk33r.nook/manifest.json"
plugins_before="$(find "$OLD_PLUGINS" -type f -exec sha256sum {} + | sort)"

# The owner's shape: a nook inside bar.overflow holding widgets, one with its
# own settings, one recorded as coming from the left section, one already in
# the bar; the old ids in sections, services and plugins.
cp "$FIXTURES/bar-basics/nested.json" "$CFG"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "left: active-window renamed in place, the left-born widget appended" \
    '["haseen.logo","haseen.active-window","me.clock","me.left"]' "$(jq -c .bar.left "$CFG")"
assert_eq "center: updates renamed in place" '["haseen.clock","haseen.updates"]' "$(jq -c .bar.center "$CFG")"
assert_eq "right: the nook's widgets where it was, the nook gone" \
    '["haseen.tray","me.a","me.b","me.vpn","me.after"]' "$(jq -c .bar.right "$CFG")"
assert_eq "overflow: the nook's widgets in its place, in its order" \
    '["me.o","me.a","me.left","me.b","me.after"]' "$(jq -c .bar.overflow "$CFG")"
assert_eq "pinned: renamed, the nested nook gone" '["haseen.updates"]' "$(jq -c .bar.pinned "$CFG")"
assert_eq "services: the old ids dropped, the rest kept in order" '["haseen.pager","me.vpn"]' "$(jq -c .services "$CFG")"
assert_eq "plugins: no old id left" "[]" "$(jq -c '[.plugins | keys[] | select(startswith("t1nk33r."))]' "$CFG")"
assert_eq "active-window: enabled and maxChars kept, an unknown key dropped" '{"enabled":true,"settings":{"maxChars":25}}' \
    "$(jq -c '.plugins["haseen.active-window"]' "$CFG")"
assert_eq "updates: tooltipLines is listLines, onClick dropped, enabled set (listed, no flag)" \
    '{"enabled":true,"settings":{"interval":15,"splitAur":true,"listLines":5}}' "$(jq -c '.plugins["haseen.updates"]' "$CFG")"
assert_eq "power: disabled stays disabled, the string false is false" '{"enabled":false,"settings":{"showPercentage":false}}' \
    "$(jq -c '.plugins["haseen.power"]' "$CFG")"
assert_eq "the nested nook leaves no plugin entry" "null" "$(jq '.plugins["haseen.nook"]' "$CFG")"
assert_eq "an item's own keys fill in its settings, existing ones win" '{"enabled":true,"settings":{"hidden":"x","mode":"mine"}}' \
    "$(jq -c '.plugins["me.a"]' "$CFG")"
assert_eq "the rest of shell.json survives" '{"position":"top","theme":"keep"}' "$(jq -c '{position: .bar.position, theme: .other.theme}' "$CFG")"
assert_contains "the onClick drop is said" "$OUTPUT" "haseen.updates: the old onClick setting is dropped"
assert_contains "the moved widgets are named" "$OUTPUT" "haseen.nook: the nook's widgets are in the bar's overflow panel now: me.a, me.left, me.b"
after="$(cat "$CFG")"
run_migration
assert_eq "a re-run is a no-op" "$after" "$(cat "$CFG")"
assert_eq "the old plugin directories are untouched" "$plugins_before" "$(find "$OLD_PLUGINS" -type f -exec sha256sum {} + | sort)"

# A nook in a section (not nested) stays, renamed, and its widgets join the panel.
cp "$FIXTURES/bar-basics/section.json" "$CFG"
run_migration
assert_eq "section nook: renamed in place, widgets after it" '["haseen.tray","haseen.nook","me.a","me.b","me.z"]' "$(jq -c .bar.right "$CFG")"
assert_eq "section nook: widgets appended to the panel" '["me.o","me.a","me.b"]' "$(jq -c .bar.overflow "$CFG")"
assert_eq "section nook: on, settings dropped" '{"enabled":true}' "$(jq -c '.plugins["haseen.nook"]' "$CFG")"
assert_eq "section nook: not a service" '["haseen.pager"]' "$(jq -c .services "$CFG")"

# A hidden nook (disabled) moves nothing into the bar.
cp "$FIXTURES/bar-basics/hidden.json" "$CFG"
run_migration
assert_eq "hidden nook: its widgets stay out of the bar" '["haseen.tray","haseen.nook"]' "$(jq -c .bar.right "$CFG")"
assert_eq "hidden nook: nothing added to the panel" '[]' "$(jq -c .bar.overflow "$CFG")"
assert_eq "hidden nook: stays off" '{"enabled":false}' "$(jq -c '.plugins["haseen.nook"]' "$CFG")"

# Old and new both present: the new one wins and the old one goes.
printf '%s\n' '{"bar":{"left":["t1nk33r.active-window"],"right":["haseen.active-window"]},"plugins":{"t1nk33r.active-window":{"settings":{"maxChars":10}},"haseen.active-window":{"enabled":true,"settings":{"maxChars":30}}}}' >"$CFG"
run_migration
assert_eq "both: one id, where it comes first" '[["haseen.active-window"],[]]' "$(jq -c '[.bar.left, .bar.right]' "$CFG")"
assert_eq "both: the new settings win" '{"enabled":true,"settings":{"maxChars":30}}' "$(jq -c '.plugins["haseen.active-window"]' "$CFG")"

# Dry run: the write is printed, nothing changes.
cp "$FIXTURES/bar-basics/nested.json" "$CFG"
before="$(cat "$CFG")"
DRY_RUN=true run_migration
assert_status "dry run exits 0" 0 "$STATUS"
assert_contains "dry run prints the write" "$OUTPUT" "DRYRUN: write $CFG.new:"
assert_eq "dry run changes nothing" "$before" "$(cat "$CFG")"
assert_dry_pure "migration" "$OUTPUT"

# Nothing to do.
printf '%s\n' '{"bar":{"left":["haseen.logo"]},"plugins":{"me.x":{"enabled":true}}}' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "no old id: nothing written" "$before" "$(cat "$CFG")"
rm -f "$CFG"
run_migration
assert_status "no shell.json: exits 0" 0 "$STATUS"
assert_eq "no shell.json: none written" no "$([[ -e $CFG ]] && echo yes || echo no)"
printf '[1]\n' >"$CFG"
run_migration
assert_status "a shell.json that is not an object is refused" 1 "$STATUS"
assert_eq "and left as it was" "[1]" "$(cat "$CFG")"
