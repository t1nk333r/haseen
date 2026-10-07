# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.battery (plans 075, 076): the manifest and the default shell.json
# (the warnings service on, criticalAction none), the migration that lists
# the service in a user's own `services`, the pure threshold, countdown and
# panel formatting in BatteryLogic.js and Model.js under the real Qt JS
# engine, and the service itself in the real Quickshell engine against
# tools/fake-upower.py on a private system bus, with every notification and
# power command recorded by a stub.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.battery"
DEFAULT="$HASEEN_PATH/default/shell.json"
MIGRATION=1791397394-battery-service.sh

# --- manifest and defaults ---------------------------------------------------
sandbox battery
capture haseen plugin validate haseen.battery
assert_status "battery validates" 0 "$STATUS"
assert_contains "battery ok" "$OUTPUT" "ok: haseen.battery (builtin:"
assert_eq "kinds: widget, service, panel" "bar-widget service panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "entries" "Widget.qml Service.qml Panel.qml" "$(jq -r '[.entry["bar-widget"], .entry.service, .entry.panel] | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "defaults: warnAt 20, criticalAt 10, criticalAction none, debugIpc off" "20 10 none false" \
    "$(jq -r '[.settings.warnAt.default, .settings.criticalAt.default, .settings.criticalAction.default, .settings.debugIpc.default] | map(tostring) | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "default shell.json starts the warnings service" "true" "$(jq '.services | index("haseen.battery") != null' "$DEFAULT")"
assert_eq "default shell.json keeps the bar widget" "true" "$(jq '.bar.right | index("haseen.battery") != null' "$DEFAULT")"
assert_eq "default shell.json sets no critical action" "null" "$(jq '.plugins["haseen.battery"].settings.criticalAction' "$DEFAULT")"

# --- migration ------------------------------------------------------------------
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
sandbox battery-migration
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"services":["haseen.pager","me.svc"],"plugins":{"me.svc":{"enabled":true}}}\n' >"$CFG"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "migration: appended to a user's own services" '["haseen.pager","me.svc","haseen.battery"]' "$(jq -c .services "$CFG")"
assert_eq "migration: the rest of shell.json survives" "true" "$(jq '.plugins["me.svc"].enabled' "$CFG")"
after="$(cat "$CFG")"
run_migration
assert_eq "migration: a re-run is a no-op" "$after" "$(cat "$CFG")"
printf '{"bar":{"left":[]}}\n' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "migration: no own services list, nothing written" "$before" "$(cat "$CFG")"
rm -f "$CFG"
run_migration
assert_status "migration without a shell.json exits 0" 0 "$STATUS"
assert_eq "migration: no shell.json, none written" no "$([[ -e $CFG ]] && echo yes || echo no)"

# --- pure logic under the real Qt JS engine ---------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/BatteryLogic.js" as L
import "file://$PLUGIN/Model.js" as M

Window {
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

    // Feeds readings [percent, power] through step; returns the events per
    // reading and the final state.
    function feed(cfg, readings, start) {
        let s = start || L.initial();
        const out = [];
        for (const r of readings) {
            const res = L.step(s, { present: true, percent: r[0], power: r[1] }, cfg, 1000);
            s = res.state;
            out.push(res.events.join("+"));
        }
        return { events: out, state: s };
    }

    function run() {
        // config
        const dflt = L.config({});
        eq("config defaults", { warnAt: 20, criticalAt: 10, criticalAction: "none", countdown: 60 }, dflt);
        eq("config clamps critical to warn, rounds", { warnAt: 15, criticalAt: 15, criticalAction: "suspend", countdown: 60 },
           L.config({ warnAt: 15.2, criticalAt: 30, criticalAction: "suspend" }));
        eq("config: unknown action is none", "none", L.config({ criticalAction: "reboot" }).criticalAction);
        eq("config: junk numbers fall back", [20, 10], [L.config({ warnAt: "x" }).warnAt, L.config({ criticalAt: NaN }).criticalAt]);

        // readings
        eq("power: states", ["unknown", "charging", "discharging", "discharging", "charging", "charging", "discharging"],
           [0, 1, 2, 3, 4, 5, 6].map(L.power));
        eq("reading: a laptop battery", { present: true, percent: 19, power: "discharging" },
           L.reading({ ready: true, isLaptopBattery: true, isPresent: true, percentage: 0.194, state: 2 }));
        eq("reading: not ready is absent", false, L.reading({ ready: false, isLaptopBattery: true, isPresent: true, percentage: 0.1, state: 2 }).present);
        eq("reading: a mouse is not the battery", false, L.reading({ ready: true, isLaptopBattery: false, isPresent: true, percentage: 0.1, state: 2 }).present);
        eq("reading: null device", { present: false, percent: 0, power: "unknown" }, L.reading(null));

        // crossings, no repeats, hysteresis
        const d = "discharging";
        eq("one warn per crossing, nothing while below",
           ["", "warn", "", "", ""], feed(dflt, [[21, d], [20, d], [19, d], [18, d], [20, d]]).events);
        eq("hysteresis: a wobble back to warnAt+2 does not re-arm",
           ["warn", "", ""], feed(dflt, [[20, d], [22, d], [20, d]]).events);
        eq("hysteresis: warnAt+3 re-arms",
           ["warn", "", "warn"], feed(dflt, [[20, d], [23, d], [20, d]]).events);
        eq("critical once, after the warn",
           ["warn", "critical", "", ""], feed(dflt, [[20, d], [10, d], [9, d], [5, d]]).events);
        eq("starting below both levels notifies once, as critical",
           ["critical", ""], feed(dflt, [[5, d], [4, d]]).events);
        eq("charging resets: the next crossing warns again",
           ["warn", "", "", "warn"], feed(dflt, [[20, d], [19, "charging"], [25, d], [20, d]]).events);
        eq("charging state is the initial state", L.initial(), feed(dflt, [[5, d], [5, "charging"]]).state);
        eq("unknown power changes nothing", ["warn", "", ""], feed(dflt, [[20, d], [10, "unknown"], [19, d]]).events);
        eq("criticalAt 0 never goes critical", ["warn", ""], feed(L.config({ criticalAt: 0 }), [[20, d], [1, d]]).events);
        eq("no battery: nothing", { state: L.initial(), events: [] }, L.step(L.initial(), { present: false }, dflt, 0));

        // critical action: arm, countdown, cancel, disarm, fire
        const sus = L.config({ criticalAction: "suspend" });
        const armed = L.step(L.initial(), { present: true, percent: 9, power: d }, sus, 5000);
        eq("action: critical arms a 60 s countdown", ["critical", "arm"], armed.events);
        eq("action: deadline is now + 60 s", 65000, armed.state.deadline);
        eq("action: none never arms", ["critical"], L.step(L.initial(), { present: true, percent: 9, power: d }, dflt, 0).events);
        eq("countdown: 60 s left at the start", 60, L.remaining(armed.state, 5000));
        eq("countdown: rounds up", 1, L.remaining(armed.state, 64500));
        eq("countdown: 0 when not armed", 0, L.remaining(L.initial(), 0));
        eq("countdown: a charger disarms", ["disarm"], L.step(armed.state, { present: true, percent: 9, power: "charging" }, sus, 6000).events);
        eq("countdown: losing the battery disarms", ["disarm"], L.step(armed.state, { present: false }, sus, 6000).events);
        eq("countdown: recovering to criticalAt+3 disarms", ["disarm"], L.step(armed.state, { present: true, percent: 13, power: d }, sus, 6000).events);
        eq("countdown: staying low keeps it armed", { events: [], armed: true },
           (r => ({ events: r.events, armed: r.state.armed }))(L.step(armed.state, { present: true, percent: 8, power: d }, sus, 6000)));
        const onBattery = { present: true, percent: 8, power: d };
        eq("fire: at the deadline the action runs", { run: true, rearm: false, verb: "suspend" },
           (r => ({ run: r.run, rearm: r.rearm, verb: r.verb }))(L.fire(armed.state, onBattery, sus, 65000)));
        eq("fire: never before the deadline", false, L.fire(armed.state, onBattery, sus, 30000).run);
        eq("fire: after Cancel nothing runs", false, L.fire(L.cancel(armed.state), onBattery, sus, 65000).run);
        eq("fire: Cancel keeps the level reached, so it does not come back",
           [], L.step(L.cancel(armed.state), { present: true, percent: 7, power: d }, sus, 70000).events);
        eq("fire: on a charger nothing runs", false, L.fire(armed.state, { present: true, percent: 8, power: "charging" }, sus, 65000).run);
        eq("fire: without an action nothing runs", false, L.fire(armed.state, onBattery, dflt, 65000).run);
        const late = L.fire(armed.state, onBattery, sus, 65000 + 3600000);
        eq("fire: slept through the deadline: a fresh countdown, no action", { run: false, rearm: true, deadline: 65000 + 3600000 + 60000 },
           { run: late.run, rearm: late.rearm, deadline: late.state.deadline });
        eq("fire: it disarms after running", false, L.fire(armed.state, onBattery, sus, 65000).state.armed);
        eq("action verbs", ["hibernate", "shutdown"],
           [L.fire(armed.state, onBattery, L.config({ criticalAction: "hibernate" }), 65000).verb,
            L.fire(armed.state, onBattery, L.config({ criticalAction: "poweroff" }), 65000).verb]);
        eq("action command", ["/x/bin/haseen-system", "suspend"], L.actionCommand("/x/bin", "suspend"));
        eq("no command without a verb", [], L.actionCommand("/x/bin", ""));

        // notification texts
        eq("warn message", { summary: "Battery low", body: "20% left, about 1 h 05 min.", urgency: "normal" },
           L.message("warn", { percent: 20, timeToEmpty: 3900 }, dflt));
        eq("critical message without an action", { summary: "Battery critical", body: "9% left. Plug in now.", urgency: "critical" },
           L.message("critical", { percent: 9, timeToEmpty: 0 }, dflt));
        eq("critical message with the countdown", "9% left, about 12 min. Suspending in 60 s: plug in or press Cancel.",
           L.message("critical", { percent: 9, timeToEmpty: 720 }, sus).body);
        eq("disarm message", "The hibernation is called off.", L.message("disarm", {}, L.config({ criticalAction: "hibernate" })).body);
        eq("no message for arm", null, L.message("arm", {}, sus));

        // panel formatting
        eq("duration", ["", "1 min", "45 min", "1 h", "2 h 05 min"], [0, 20, 2700, 3600, 7500].map(M.duration));
        eq("time line on battery", "3 h left", M.timeLine(2, 10800, 0));
        eq("time line charging", "45 min to full", M.timeLine(1, 0, 2700));
        eq("time line full", "", M.timeLine(4, 0, 0));
        eq("state labels", ["On battery", "Charging", "Fully charged", "Plugged in, not charging", "Unknown"],
           [2, 1, 4, 5, 0].map(s => M.stateLabel(s, false, "")));
        eq("holding label", "Plugged in, holding at 75-80%", M.stateLabel(1, true, "75-80%"));
        eq("rate", ["8.4 W", "12 W", ""], [8.43, -12, 0].map(M.rate));
        eq("energy", ["41.2 / 50 Wh", ""], [M.energy(41.24, 50), M.energy(1, 0)]);
        eq("health", ["88%", "", ""], [M.health(88.4, true), M.health(0, true), M.health(90, false)]);
        eq("glyphs", ["\u{F008E}", "\u{F007E}", "\u{F0079}", "\u{F0084}"], [M.glyph(0, false), M.glyph(52, false), M.glyph(100, false), M.glyph(30, true)]);
        eq("charging states", [false, true, false, true, true], [0, 1, 2, 4, 5].map(M.isCharging));
        eq("profile names", ["power-saver", "balanced", "performance", ""], [0, 1, 2, 7].map(M.profileName));
        eq("profile labels", ["Power saver", "Balanced", "Performance"], ["power-saver", "balanced", "performance"].map(M.profileLabel));
        eq("profiles from haseen powerprofile list", ["power-saver", "balanced"], M.profiles("balanced\npower-saver\nbogus\n"));
        eq("profiles from --active-state lines", ["balanced", "performance"], M.profiles("performance\t1\nbalanced\t0\n"));
        eq("status parse", { percentage: "73%", state: "holding", threshold: "75-80%" },
           M.parseStatus("percentage\t73%\nstate\tholding\nthreshold\t75-80%\n"));
        eq("limit end", [80, 80, 100, -1, -1], ["75-80%", "80%", "0-100%", "", "junk"].map(M.limitEnd));
        eq("limit choices", [[60, 80, 100], [60, 75, 80, 100], []], [80, 75, -1].map(M.limitChoices));
        eq("limit labels", ["60%", "Full"], [60, 100].map(M.limitLabel));
        eq("limit args", [["set", "80"], ["off"]], [80, 100].map(M.limitArgs));
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "qml unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" "65" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the service in the real engine against a fake UPower ---------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-daemon >/dev/null || ! python3 -c 'import dbus, gi' 2>/dev/null; then
    echo "  skip: qs, dbus-daemon or python3-dbus missing; engine scenarios not run" >&2
else
    sandbox battery-engine
    LOG="$SANDBOX/calls.log"
    export LOG
    # Every notification and power command lands in $LOG. notify-send answers
    # "exec" (the Cancel button) when CLICK is set and it carries an action.
    stub notify-send 'printf "notify-send %s\n" "$*" >>"$LOG"
case "$* $CLICK" in *exec=Cancel*yes) sleep 1; echo exec ;; esac'
    stub systemctl 'printf "systemctl %s\n" "$*" >>"$LOG"'
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.battery" as Battery
ShellRoot {
    Battery.Service {
        id: svc
        pluginId: "haseen.battery"
        settings: JSON.parse(Quickshell.env("BATTERY_SETTINGS"))
    }
    Timer {
        interval: Number(Quickshell.env("BATTERY_RUN_MS"))
        running: true
        onTriggered: {
            console.warn("RESULT " + JSON.stringify({ logic: svc.logic, sent: svc.sent, lastAction: svc.lastAction }));
            Qt.quit();
        }
    }
}
QML
    # scenario NAME SETTINGS RUN_MS INITIAL STEPS — a private system bus with
    # the fake on it, the harness on a session bus of its own; sets RESULT
    # (the service's state at the end) and CALLS (the recorded commands).
    scenario() {
        : >"$LOG"
        local bus pid fake
        bus="$(mktemp -d "${TMPDIR:-/tmp}/haseen-battery.XXXXXX")"
        dbus-daemon --config-file="$REPO/tools/smoke-session.conf" --fork \
            --address="unix:path=$bus/system" --print-pid=3 3>"$bus/pid"
        pid="$(cat "$bus/pid")"
        printf '%s\n' "${@:5}" | DBUS_SYSTEM_BUS_ADDRESS="unix:path=$bus/system" \
            timeout 60 python3 "$REPO/tools/fake-upower.py" $4 >"$SANDBOX/fake.log" 2>&1 &
        fake=$!
        for _ in $(seq 50); do grep -q ready "$SANDBOX/fake.log" && break; sleep 0.1; done
        capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            DBUS_SYSTEM_BUS_ADDRESS="unix:path=$bus/system" BATTERY_SETTINGS="$2" BATTERY_RUN_MS="$3" \
            timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
        kill "$fake" "$pid" 2>/dev/null || true
        wait "$fake" 2>/dev/null || true
        rm -rf "$bus"
        if [[ $STATUS == 0 ]]; then _pass; else _fail "$1: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
        RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
        CALLS="$(cat "$LOG")"
    }
    sent() { jq -c '[.sent[] | split(":")[0]]' <<<"$RESULT"; }

    # Levels, no action: one warn, one critical, no repeats, a charger resets.
    scenario levels '{"warnAt":20,"criticalAt":10}' 9000 "Percentage=25 State=2" \
        "sleep=2 Percentage=21" "sleep=0.6 Percentage=20" "sleep=0.6 Percentage=19" \
        "sleep=0.6 Percentage=22" "sleep=0.6 Percentage=20" "sleep=0.6 Percentage=10" \
        "sleep=0.6 Percentage=9" "sleep=0.6 State=1" "sleep=0.6 State=2 Percentage=18"
    assert_eq "levels: warn, critical, then warn again after charging" '["warn","critical","warn"]' "$(sent)"
    assert_eq "levels: three notifications sent" 3 "$(grep -c '^notify-send' <<<"$CALLS")"
    assert_contains "levels: the warn is normal urgency, through haseen notification send" "$CALLS" "notify-send -a haseen -u normal -- Battery low 20% left, about 3 h."
    assert_contains "levels: the critical is critical urgency" "$CALLS" "notify-send -a haseen -u critical -- Battery critical 10% left, about 3 h. Plug in now."
    assert_not_contains "levels: no power command" "$CALLS" "systemctl"

    # Countdown, then a charger: the action is called off.
    scenario countdown '{"criticalAction":"suspend"}' 6000 "Percentage=12 State=2" \
        "sleep=2 Percentage=10" "sleep=1.5 State=1"
    assert_contains "countdown: the critical notification has a Cancel button" "$CALLS" \
        "-u critical -A exec=Cancel -- Battery critical 10% left, about 3 h. Suspending in 60 s: plug in or press Cancel."
    assert_contains "countdown: a charger calls it off" "$CALLS" "-u low -- Battery The suspend is called off."
    assert_eq "countdown: disarmed" "false" "$(jq '.logic.armed' <<<"$RESULT")"
    assert_eq "countdown: nothing ran" '""' "$(jq '.lastAction' <<<"$RESULT")"
    assert_not_contains "countdown: no systemctl" "$CALLS" "systemctl"

    # Cancel pressed: disarmed, the level stays reached, nothing comes back.
    export CLICK=yes
    scenario cancel '{"criticalAction":"poweroff"}' 6000 "Percentage=9 State=2" \
        "sleep=4 Percentage=8"
    assert_contains "cancel: the countdown notification went out" "$CALLS" "Shutting down in 60 s"
    assert_eq "cancel: disarmed by the button" "false true" "$(jq -r '"\(.logic.armed) \(.logic.critical)"' <<<"$RESULT")"
    assert_eq "cancel: one notification only" 1 "$(grep -c '^notify-send' <<<"$CALLS")"
    assert_not_contains "cancel: no systemctl" "$CALLS" "systemctl"
fi
