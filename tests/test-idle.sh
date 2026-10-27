# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-validate bin/haseen-screensaver-style bin/haseen-setup-idle
# haseen:covers share/haseen/VERSION share/haseen/default/shell.json share/haseen/lib/terminal.sh
# haseen:covers share/haseen/shell/Compat/Manifest.js share/haseen/shell/lib/plugin.sh
# haseen:covers share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.{idle,screensaver}/**
# haseen:covers share/haseen/shell/plugins/*/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Idle suspend and battery timeouts (plan 082): the timeout selection on AC
# and on battery, the inhibitor gating of the suspend monitor (IdleLogic.js
# in Qt's own engine, the one Quickshell uses), and `haseen setup idle`.

PLUGINS="$HASEEN_PATH/shell/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox idle-validate
capture haseen plugin validate haseen.idle
assert_status "haseen.idle validates" 0 "$STATUS"
assert_eq "suspendAfter defaults to 0 (never)" "0" "$(jq -r .settings.suspendAfter.default "$PLUGINS/haseen.idle/manifest.json")"
assert_eq "no battery override by default" "{}" "$(jq -c .settings.onBattery.default "$PLUGINS/haseen.idle/manifest.json")"

# --- IdleLogic in Qt's JS engine ----------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.idle/IdleLogic.js" as Idle
Item {
    function out(name, v) { console.warn("RESULT " + name + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const t = (s, f) => { const r = Idle.timeouts(s, f, true); return [r.screensaver, r.lock, r.dpms, r.suspend].join(","); };
        const ac = { suspendAfter: 900, onBattery: { lockAfter: 120, dpmsAfter: 150, suspendAfter: 300 } };
        out("defaults", t({}, {}));
        out("defaults-battery", t({}, { onBattery: true }));
        out("suspend-ac", t({ suspendAfter: 600 }, {}));
        out("ac", t(ac, { onBattery: false }));
        out("battery", t(ac, { onBattery: true }));
        out("battery-partial", t({ suspendAfter: 900, onBattery: { suspendAfter: 300 } }, { onBattery: true }));
        out("battery-only", t({ onBattery: { suspendAfter: 300 } }, { onBattery: true }));
        out("battery-only-ac", t({ onBattery: { suspendAfter: 300 } }, { onBattery: false }));
        out("battery-zero", t({ suspendAfter: 900, onBattery: { suspendAfter: 0, lockAfter: 0 } }, { onBattery: true }));
        out("battery-null-keeps", t({ suspendAfter: 900, onBattery: { suspendAfter: null, lockAfter: "x", dpmsAfter: -1 } }, { onBattery: true }));
        out("battery-not-object", [t({ suspendAfter: 900, onBattery: 60 }, { onBattery: true }), t({ suspendAfter: 900, onBattery: [60] }, { onBattery: true }), t({ suspendAfter: 900, onBattery: null }, { onBattery: true })]);
        out("battery-unknown-key", t({ onBattery: { respectInhibitors: false, suspendAfter: 30 } }, { onBattery: true }));
        out("battery-ss-after-lock", t({ screensaverAfter: 100, onBattery: { lockAfter: 60 } }, { onBattery: true }));
        out("suspend-garbage", [t({ suspendAfter: "600" }, {}), t({ suspendAfter: -5 }, {}), t({ suspendAfter: 59.6 }, {})]);
        out("idle-off-battery", t(ac, { onBattery: true, idleOff: true }));
        out("screensaver-off-keeps-suspend", t({ suspendAfter: 600 }, { screensaverOff: true }));
        out("settings-untouched", (() => { const s = { suspendAfter: 1, onBattery: { suspendAfter: 2 } }; Idle.timeouts(s, { onBattery: true }, true); return s.suspendAfter; })());
        out("a-suspend-idle", Idle.actions("suspend", true, {}));
        out("a-suspend-idle-off", Idle.actions("suspend", true, { idleOff: true }));
        out("a-suspend-active", Idle.actions("suspend", false, {}));
        out("m-suspend", Idle.monitors(Idle.timeouts({ suspendAfter: 600 }, {}, true), true));
        out("m-suspend-ignores-respect", Idle.monitors({ screensaver: 0, lock: 60, dpms: 0, suspend: 600 }, false));
        out("m-default-no-suspend", Idle.monitors(Idle.timeouts({}, {}, true), true));
        out("m-idle-off", Idle.monitors(Idle.timeouts(ac, { idleOff: true, onBattery: true }, true), true));
        out("m-plug", [Idle.monitors(Idle.timeouts(ac, { onBattery: false }, true), true), Idle.monitors(Idle.timeouts(ac, { onBattery: true }, true), true)]);
        out("m-parse", Idle.parseMonitor("suspend:300:1"));
        // Quickshell's IdleMonitor turns a timeout above 2147483 s into 0 ms
        // (idle at once), so larger values are held at the maximum.
        out("max", [t({ suspendAfter: 2147483 }, {}), t({ suspendAfter: 2147484 }, {}), t({ lockAfter: 3000000, onBattery: { dpmsAfter: 1e21 } }, { onBattery: true })]);
        out("m-max", Idle.monitors(Idle.timeouts({ suspendAfter: 1e21 }, {}, true), true));
        // A plug event replacing an idle dpms monitor is not a removal.
        const plug = [Idle.monitors(Idle.timeouts(ac, { onBattery: false }, true), true), Idle.monitors(Idle.timeouts(ac, { onBattery: true }, true), true)];
        out("replaced", [Idle.replaced("dpms:330:1", plug[1]), Idle.replaced("screensaver:150:1", plug[1]), Idle.replaced("dpms:330:1", []), Idle.replaced("dpms:330:1", ["dpms:330:1"])]);
        // Manual screen off/on (plan 084) and the screensaver cycle (plan
        // 140) against haseen.idle. The model: Hyprland's DPMS state,
        // written by haseen screen off|on, by the service's dispatches and
        // by input (key_press_enables_dpms and mouse_move_enables_dpms wake
        // the displays before any monitor reports activity). The service
        // part is Service.qml: _run and _do (dpms.off sets _dpmsOff and sends
        // off, dpms.on clears it and sends on, cycle.start takes the cycle's
        // timeouts, cycle.end ends it through Qt.callLater), onTimeoutsChanged
        // (a cycle without a screensaver monitor ends without input), the
        // monitors are Idle.monitors' keys, and a key that changes replaces
        // its monitor with a fresh, active one. As the service harness below
        // measures: a removed monitor's Component.onDestruction runs at once,
        // when its key goes, and sees the new keys; onTimeoutsChanged runs
        // before the keys change; Qt.callLater runs after the event. "map" is Hyprland
        // re-checking idle inhibitors (a window maps, takes focus or goes
        // fullscreen: the screensaver's own terminal does all three); every
        // idle monitor that respects inhibitors goes active, and nothing
        // else. "input" makes every idle monitor active. { set: {...} }
        // changes the timeouts (a settings change, a plug event);
        // "stay-awake" sets them all to 0, as idle-off does.
        const sim = (events, tt) => {
            const t = Object.assign({ screensaver: 150, lock: 300, dpms: 330, suspend: 0 }, tt || {});
            const st = { screen: true, dpmsOff: false, cycle: false, snap: null, idle: {}, sent: [] };
            let keys = Idle.monitors(t, true, null);
            const posted = [];
            const apply = (m, isIdle, removed) => {
                st.idle[m] = isIdle;
                doAll(Idle.actions(m, isIdle, { dpmsOff: st.dpmsOff, idleOff: false, cycle: st.cycle, removed: removed === true }));
            };
            const destroyed = k => {
                const m = Idle.parseMonitor(k).name;
                if (!st.idle[m]) return;
                if (Idle.replaced(k, keys)) st.idle[m] = false;
                else apply(m, false, true);
            };
            const rekey = () => {
                const next = Idle.monitors(t, true, st.cycle ? st.snap : null);
                const gone = keys.filter(k => next.indexOf(k) < 0);
                keys = next;
                for (const k of gone) destroyed(k);
            };
            const endCycle = input => {
                if (!st.cycle) return;
                st.cycle = false;
                st.snap = null;
                rekey();
                doAll(Idle.cycleEnd({ dpmsOff: st.dpmsOff, input: input }));
            };
            const doAll = acts => {
                for (const a of acts) {
                    st.sent.push(a);
                    if (a === "dpms.off") { st.dpmsOff = true; st.screen = false; }
                    if (a === "dpms.on") { st.dpmsOff = false; st.screen = true; }
                    if (a === "cycle.start" && !st.cycle) { st.snap = Object.assign({}, t); st.cycle = true; rekey(); }
                    if (a === "cycle.end") posted.push(() => endCycle(true));
                }
            };
            const respects = m => keys.some(k => { const p = Idle.parseMonitor(k); return p.name === m && p.respectInhibitors; });
            for (const e of events) {
                if (e === "manual-off") st.screen = false;
                else if (e === "manual-on") st.screen = true;
                else if (e === "input") { st.screen = true; for (const m of Object.keys(st.idle)) if (st.idle[m]) apply(m, false); }
                else if (e === "map") { for (const m of Object.keys(st.idle)) if (st.idle[m] && respects(m)) apply(m, false); }
                else if (e === "stay-awake" || typeof e === "object") {
                    Object.assign(t, e === "stay-awake" ? { screensaver: 0, lock: 0, dpms: 0, suspend: 0 } : e.set);
                    // onTimeoutsChanged, then the monitorKeys binding.
                    if (st.cycle && t.screensaver === 0) endCycle(false);
                    rekey();
                } else {
                    const m = e.replace(/^idle:/, "");
                    if (keys.some(k => Idle.parseMonitor(k).name === m)) apply(m, true);
                    else st.sent.push("no monitor " + m);
                }
                while (posted.length) posted.shift()();
            }
            return { screen: st.screen, dpmsOff: st.dpmsOff, cycle: st.cycle, sent: st.sent, keys: keys };
        };
        // The sequences alone, for the cases that are not about keys.
        const run = (events, tt) => { const o = sim(events, tt); delete o.keys; return o; };
        out("s-off-input", run(["manual-off", "input"]));
        out("s-off-stays", run(["manual-off", "idle:screensaver"]));
        out("s-off-stay-awake", run(["manual-off", "idle:screensaver", "stay-awake"]));
        out("s-off-lock-dpms", run(["manual-off", "idle:screensaver", "idle:lock", "idle:dpms"]));
        out("s-off-lock-dpms-input", run(["manual-off", "idle:screensaver", "idle:presence", "idle:lock", "idle:dpms", "input"]));
        out("s-idle-off-manual-on", run(["idle:dpms", "manual-on", "input", "idle:dpms"]));
        out("s-idle-off-manual-on-cycle", run(["idle:dpms", "manual-on", "input", "idle:dpms", "input"]));
        out("s-on-awake", run(["manual-on"]));
        // The screensaver cycle (plan 140).
        out("s-map-keeps", run(["idle:screensaver", "map"]));
        out("s-map-lock-dpms", run(["idle:screensaver", "map", "idle:presence", "idle:lock", "map", "idle:dpms"]));
        out("s-map-back", run(["idle:screensaver", "map", "idle:presence", "input"]));
        out("s-map-back-after-dpms", run(["idle:screensaver", "map", "idle:presence", "idle:lock", "map", "idle:dpms", "input", "idle:screensaver"]));
        out("s-dpms-first-map", run(["idle:dpms", "idle:screensaver", "map"], { screensaver: 150, lock: 300, dpms: 100, suspend: 0 }));
        out("s-dpms-first-back", run(["idle:dpms", "idle:screensaver", "map", "idle:presence", "input"], { screensaver: 150, lock: 300, dpms: 100, suspend: 0 }));
        out("s-map-stay-awake", run(["idle:screensaver", "map", "idle:presence", "idle:lock", "idle:dpms", "stay-awake"]));
        out("s-again", run(["idle:screensaver", "idle:screensaver"]));
        // A plug event or a settings change during the cycle: the lock and
        // dpms keys stay, so their counts go on; turning one off removes it.
        out("s-set-screensaver", sim(["idle:screensaver", "map", "idle:presence", { set: { screensaver: 30 } }]));
        out("s-set-lock", sim(["idle:screensaver", "map", { set: { lock: 600 } }]));
        out("s-set-lock-off", sim(["idle:screensaver", "map", { set: { lock: 0 } }]));
        out("s-set-again", sim(["idle:screensaver", "map", { set: { screensaver: 30 } }, "idle:screensaver"]));
        // The screensaver monitor dropped in a dark room (a plug event whose
        // lockAfter is at or before screensaverAfter): nobody came back.
        out("s-dropped-dark", sim(["idle:screensaver", "map", "idle:presence", "idle:lock", "idle:dpms", { set: { screensaver: 0 } }]));
        // dpmsAfter equal to screensaverAfter: input only, 1 s after the start.
        out("s-dpms-equal", sim(["idle:dpms", "idle:screensaver", "idle:dpms", "map"], { dpms: 150 }));
        out("a-cycle", [
            Idle.actions("presence", true, { cycle: true }),
            Idle.actions("presence", false, { cycle: true }),
            Idle.actions("dpms", false, { cycle: true, dpmsOff: true }),
            Idle.actions("dpms", false, { cycle: true, dpmsOff: true, removed: true }),
            Idle.actions("screensaver", false, { cycle: true, removed: true }),
            Idle.actions("screensaver", false, { removed: true }),
            Idle.actions("lock", true, { cycle: true }),
            Idle.actions("suspend", true, { cycle: true }),
            Idle.actions("screensaver", true, { cycle: true }),
            Idle.actions("presence", false, { cycle: true, removed: true })
        ]);
        out("cycle-end", [Idle.cycleEnd({}), Idle.cycleEnd({ dpmsOff: true }), Idle.cycleEnd({ dpmsOff: true, input: true }), Idle.cycleEnd({ input: true })]);
        out("m-cycle", [
            Idle.monitors(Idle.timeouts({}, {}, true), true, true),
            Idle.monitors(Idle.timeouts({ suspendAfter: 600 }, {}, true), false, true),
            Idle.monitors({ screensaver: 150, lock: 300, dpms: 100, suspend: 0 }, true, true),
            Idle.monitors(Idle.timeouts({}, { screensaverOff: true }, true), true, true),
            Idle.monitors(Idle.timeouts({}, { idleOff: true }, true), true, true),
            Idle.monitors({ screensaver: 150, lock: 0, dpms: 0, suspend: 0 }, true, true),
            Idle.monitors({ screensaver: 150, lock: 300, dpms: 150, suspend: 0 }, true, true)
        ]);
        const c0 = Idle.timeouts({}, {}, true);
        out("m-cycle-snapshot", [
            Idle.monitors({ screensaver: 30, lock: 300, dpms: 330, suspend: 0 }, true, c0),
            Idle.monitors({ screensaver: 150, lock: 600, dpms: 400, suspend: 0 }, true, c0),
            Idle.monitors({ screensaver: 150, lock: 0, dpms: 330, suspend: 0 }, true, c0),
            Idle.monitors({ screensaver: 150, lock: 300, dpms: 330, suspend: 0 }, true, { screensaver: 150, lock: 0, dpms: 330, suspend: 0 }),
            Idle.monitors({ screensaver: 0, lock: 300, dpms: 330, suspend: 0 }, true, c0),
            Idle.monitors(c0, true, null)
        ]);
        out("m-cycle-parse", Idle.parseMonitor("presence:1:0"));
        out("m-cycle-replaced", [Idle.replaced("lock:300:1", Idle.monitors(Idle.timeouts({}, {}, true), true, true)), Idle.replaced("presence:1:0", Idle.monitors(Idle.timeouts({}, {}, true), true, false))]);
        Qt.quit();
    }
}
EOF
    js_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$js_out"; }
    # Timeouts: screensaver,lock,dpms,suspend seconds (0 = off).
    assert_eq "defaults never suspend" '"150,300,330,0"' "$(r defaults)"
    assert_eq "on battery without an override, the AC values" '"150,300,330,0"' "$(r defaults-battery)"
    assert_eq "suspendAfter on AC" '"150,300,330,600"' "$(r suspend-ac)"
    assert_eq "on AC the override is ignored" '"150,300,330,900"' "$(r ac)"
    assert_eq "on battery the override replaces each key it sets (the screensaver, now after the lock, drops)" '"0,120,150,300"' "$(r battery)"
    assert_eq "a partial override keeps the other AC values" '"150,300,330,300"' "$(r battery-partial)"
    assert_eq "suspend only on battery" '"150,300,330,300"' "$(r battery-only)"
    assert_eq "suspend only on battery: none on AC" '"150,300,330,0"' "$(r battery-only-ac)"
    assert_eq "0 on battery turns a monitor off there" '"150,0,330,0"' "$(r battery-zero)"
    assert_eq "null or invalid override keys keep the AC value" '"150,300,330,900"' "$(r battery-null-keeps)"
    assert_eq "a non-object override is ignored" '["150,300,330,900","150,300,330,900","150,300,330,900"]' "$(r battery-not-object)"
    assert_eq "only timeout keys are overridden" '"150,300,330,30"' "$(r battery-unknown-key)"
    assert_eq "the screensaver rule applies to the merged values" '"0,60,330,0"' "$(r battery-ss-after-lock)"
    assert_eq "invalid suspendAfter is never; seconds round" '["150,300,330,0","150,300,330,0","150,300,330,60"]' "$(r suspend-garbage)"
    assert_eq "Stay Awake/contexts (idle-off) win over the battery override" '"0,0,0,0"' "$(r idle-off-battery)"
    assert_eq "screensaver-off keeps suspend" '"0,300,330,600"' "$(r screensaver-off-keeps-suspend)"
    assert_eq "the user's settings object is not modified" '1' "$(r settings-untouched)"
    # Gating.
    assert_eq "suspend monitor idle suspends" '["suspend"]' "$(r a-suspend-idle)"
    assert_eq "no suspend once idle-off is set" '[]' "$(r a-suspend-idle-off)"
    assert_eq "input after suspend does nothing" '[]' "$(r a-suspend-active)"
    assert_eq "a suspend monitor honours inhibitors" '["screensaver:150:1","lock:300:1","dpms:330:1","suspend:600:1"]' "$(r m-suspend)"
    assert_eq "the suspend monitor honours inhibitors even with respectInhibitors off" '["lock:60:0","suspend:600:1"]' "$(r m-suspend-ignores-respect)"
    assert_eq "no suspend monitor by default" '["screensaver:150:1","lock:300:1","dpms:330:1"]' "$(r m-default-no-suspend)"
    assert_eq "idle-off runs no monitor on battery either" '[]' "$(r m-idle-off)"
    assert_eq "unplugging changes only the overridden monitors' keys" \
        '[["screensaver:150:1","lock:300:1","dpms:330:1","suspend:900:1"],["lock:120:1","dpms:150:1","suspend:300:1"]]' "$(r m-plug)"
    assert_eq "suspend keys parse back" '{"name":"suspend","timeout":300,"respectInhibitors":true}' "$(r m-parse)"
    assert_eq "timeouts above 2147483 s are held there, not passed on to wrap to 0 ms" \
        '["150,300,330,2147483","150,300,330,2147483","150,2147483,2147483,0"]' "$(r max)"
    assert_eq "a huge suspendAfter never makes an immediate monitor" \
        '["screensaver:150:1","lock:300:1","dpms:330:1","suspend:2147483:1"]' "$(r m-max)"
    assert_eq "a monitor replaced by a new timeout is not undone; one removed (screensaver dropped, idle-off) is" \
        '[true,false,false,false]' "$(r replaced)"
    # Manual screen off/on against the service (plan 084, the model above).
    assert_eq "manual off, then input: the input wakes the displays; the service sends nothing" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":[]}' "$(r s-off-input)"
    assert_eq "manual off, the screensaver monitor fires: the displays stay off" \
        '{"screen":false,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start"]}' "$(r s-off-stays)"
    assert_eq "manual off, then Stay Awake ends the cycle and removes the idle screensaver monitor: no dpms.on, the displays stay off" \
        '{"screen":false,"dpmsOff":false,"cycle":false,"sent":["screensaver.start","cycle.start","screensaver.dismiss","screensaver.dismiss"]}' "$(r s-off-stay-awake)"
    assert_eq "manual off: the lock still comes at lockAfter, then the service's own dpms off" \
        '{"screen":false,"dpmsOff":true,"cycle":true,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off"]}' "$(r s-off-lock-dpms)"
    assert_eq "manual off, an idle cycle, input: the service turns on only what it turned off" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off","cycle.end","screensaver.dismiss","dpms.on"]}' "$(r s-off-lock-dpms-input)"
    assert_eq "manual on while the service holds the displays off: its next cycle still turns them off" \
        '{"screen":false,"dpmsOff":true,"cycle":false,"sent":["dpms.off","dpms.on","dpms.off"]}' "$(r s-idle-off-manual-on)"
    assert_eq "manual on, input, a second cycle: off and on as before" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":["dpms.off","dpms.on","dpms.off","dpms.on"]}' "$(r s-idle-off-manual-on-cycle)"
    assert_eq "manual on with the displays on: nothing for the service" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":[]}' "$(r s-on-awake)"
    # The screensaver cycle (plan 140): Hyprland's inhibitor re-check when the
    # screensaver's window maps is not input.
    assert_eq "the screensaver's own window mapping does not dismiss it" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start"]}' "$(r s-map-keeps)"
    assert_eq "under the screensaver the lock and the displays still go at their time, through every re-check" \
        '{"screen":false,"dpmsOff":true,"cycle":true,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off"]}' "$(r s-map-lock-dpms)"
    assert_eq "input under the screensaver ends the cycle and dismisses it" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":["screensaver.start","cycle.start","cycle.end","screensaver.dismiss"]}' "$(r s-map-back)"
    assert_eq "back after the lock and the displays went: one dpms on, then a new cycle from scratch" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off","cycle.end","screensaver.dismiss","dpms.on","screensaver.start","cycle.start"]}' "$(r s-map-back-after-dpms)"
    assert_eq "displays already off before the screensaver: its window mapping does not wake them" \
        '{"screen":false,"dpmsOff":true,"cycle":true,"sent":["dpms.off","screensaver.start","cycle.start"]}' "$(r s-dpms-first-map)"
    assert_eq "displays off before the screensaver, then input: the cycle's end wakes them once" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":["dpms.off","screensaver.start","cycle.start","cycle.end","screensaver.dismiss","dpms.on"]}' "$(r s-dpms-first-back)"
    assert_eq "Stay Awake during a cycle with the displays off: the cycle ends, the dpms monitor's removal turns them on" \
        '{"screen":true,"dpmsOff":false,"cycle":false,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off","dpms.on","screensaver.dismiss"]}' "$(r s-map-stay-awake)"
    assert_eq "the screensaver monitor firing again inside a cycle starts no second one" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start","screensaver.start"]}' "$(r s-again)"
    assert_eq "a new screensaverAfter during the cycle: the lock and dpms keys stay, so their counts go on" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start"],"keys":["screensaver:30:1","lock:150:0","dpms:180:0","presence:1:0"]}' "$(r s-set-screensaver)"
    assert_eq "a new lockAfter during the cycle: the lock key keeps the cycle's time; the new value applies after it" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start"],"keys":["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"]}' "$(r s-set-lock)"
    assert_eq "lockAfter turned off during the cycle removes the lock monitor" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start"],"keys":["screensaver:150:1","dpms:180:0","presence:1:0"]}' "$(r s-set-lock-off)"
    assert_eq "the replaced screensaver monitor firing again keeps the cycle and its keys" \
        '{"screen":true,"dpmsOff":false,"cycle":true,"sent":["screensaver.start","cycle.start","screensaver.start"],"keys":["screensaver:30:1","lock:150:0","dpms:180:0","presence:1:0"]}' "$(r s-set-again)"
    assert_eq "the screensaver monitor dropped while nobody is there: the screensaver goes, the displays stay off" \
        '{"screen":false,"dpmsOff":true,"cycle":false,"sent":["screensaver.start","cycle.start","screensaver.dismiss","lock","dpms.off","screensaver.dismiss"],"keys":["lock:300:1","dpms:330:1"]}' "$(r s-dropped-dark)"
    assert_eq "dpmsAfter equal to screensaverAfter: an input-only 1 s dpms monitor in the cycle, which a re-check does not restart" \
        '{"screen":false,"dpmsOff":true,"cycle":true,"sent":["dpms.off","screensaver.start","cycle.start","dpms.off"],"keys":["screensaver:150:1","lock:150:0","dpms:1:0","presence:1:0"]}' "$(r s-dpms-equal)"
    assert_eq "cycle actions: presence idle arms, active ends, removed does nothing; inhibitor-aware resumes do nothing; removal still undoes; the screensaver firing in a cycle starts none" \
        '[[],["cycle.end"],[],["dpms.on"],[],["screensaver.dismiss"],["screensaver.dismiss","lock"],["suspend"],["screensaver.start"],[]]' "$(r a-cycle)"
    assert_eq "the cycle's end dismisses the screensaver, and wakes displays it turned off only on input" \
        '[["screensaver.dismiss"],["screensaver.dismiss"],["screensaver.dismiss","dpms.on"],["screensaver.dismiss"]]' "$(r cycle-end)"
    assert_eq "cycle monitors: lock and dpms count the rest on input only (at least 1 s), a 1 s presence monitor; suspend and earlier monitors keep their key" \
        '[["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"],["screensaver:150:0","lock:150:0","dpms:180:0","suspend:600:1","presence:1:0"],["screensaver:150:1","lock:150:0","dpms:100:1","presence:1:0"],["lock:300:1","dpms:330:1"],[],["screensaver:150:1","presence:1:0"],["screensaver:150:1","lock:150:0","dpms:1:0","presence:1:0"]]' "$(r m-cycle)"
    assert_eq "cycle keys come from the cycle's timeouts: current values only remove (0) or add a monitor, which then counts on input only; no screensaver, no cycle keys" \
        '[["screensaver:30:1","lock:150:0","dpms:180:0","presence:1:0"],["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"],["screensaver:150:1","dpms:180:0","presence:1:0"],["screensaver:150:1","lock:300:0","dpms:180:0","presence:1:0"],["lock:300:1","dpms:330:1"],["screensaver:150:1","lock:300:1","dpms:330:1"]]' "$(r m-cycle-snapshot)"
    assert_eq "presence keys parse back as input-only" '{"name":"presence","timeout":1,"respectInhibitors":false}' "$(r m-cycle-parse)"
    assert_eq "a cycle key replaces its monitor (no undo); presence is removed at the end" '[true,false]' "$(r m-cycle-replaced)"

    # The service itself (plan 140): Service.qml on stand-ins for Quickshell
    # and qs.Haseen. IdleMonitor is a settable isIdle, ScriptModel keeps the
    # rows whose value stays (as Quickshell's does), and every role call and
    # Hyprland dispatch goes to one log, in order. A Timer step lets Qt run
    # its posted events (Qt.callLater) between the steps.
    svc="$SANDBOX/service"
    mkdir -p "$svc"/imports/{Quickshell/{Hyprland,Io,Wayland,Services/UPower},qs/Haseen}
    printf 'module Quickshell\nScope 1.0 Scope.qml\nScriptModel 1.0 ScriptModel.qml\nsingleton Quickshell 1.0 QuickshellStub.qml\n' >"$svc/imports/Quickshell/qmldir"
    printf 'import QtQuick\nQtObject { default property list<QtObject> data }\n' >"$svc/imports/Quickshell/Scope.qml"
    cat >"$svc/imports/Quickshell/ScriptModel.qml" <<'EOF'
import QtQuick
ListModel {
    id: m
    property var values: []
    function sync() {
        for (let i = 0; i < m.count;) {
            if (values.indexOf(m.get(i).modelData) < 0) m.remove(i);
            else i++;
        }
        for (let i = 0; i < values.length; i++) {
            let found = false;
            for (let j = 0; j < m.count; j++) if (m.get(j).modelData === values[i]) found = true;
            if (!found) m.insert(i, { modelData: values[i] });
        }
    }
    onValuesChanged: sync()
    Component.onCompleted: sync()
}
EOF
    printf 'pragma Singleton\nimport QtQuick\nimport qs.Haseen\nQtObject { function execDetached(argv) { Log.push("exec " + argv.join(" ")); } }\n' >"$svc/imports/Quickshell/QuickshellStub.qml"
    printf 'module Quickshell.Hyprland\nsingleton Hyprland 1.0 Hyprland.qml\n' >"$svc/imports/Quickshell/Hyprland/qmldir"
    printf 'pragma Singleton\nimport QtQuick\nimport qs.Haseen\nQtObject { property bool usingLua: false; function dispatch(s) { Log.push(s); } }\n' >"$svc/imports/Quickshell/Hyprland/Hyprland.qml"
    printf 'module Quickshell.Io\nIpcHandler 1.0 IpcHandler.qml\n' >"$svc/imports/Quickshell/Io/qmldir"
    printf 'import QtQuick\nQtObject { property string target; property bool enabled }\n' >"$svc/imports/Quickshell/Io/IpcHandler.qml"
    printf 'module Quickshell.Wayland\nIdleMonitor 1.0 IdleMonitor.qml\n' >"$svc/imports/Quickshell/Wayland/qmldir"
    printf 'import QtQuick\nQtObject { property real timeout; property bool respectInhibitors: true; property bool isIdle: false; property bool enabled: true }\n' >"$svc/imports/Quickshell/Wayland/IdleMonitor.qml"
    printf 'module Quickshell.Services.UPower\nsingleton UPower 1.0 UPower.qml\n' >"$svc/imports/Quickshell/Services/UPower/qmldir"
    printf 'pragma Singleton\nimport QtQuick\nQtObject { property bool onBattery: false }\n' >"$svc/imports/Quickshell/Services/UPower/UPower.qml"
    printf 'module qs.Haseen\nsingleton Plugins 1.0 Plugins.qml\nsingleton Flags 1.0 Flags.qml\nsingleton Paths 1.0 Paths.qml\nsingleton Log 1.0 Log.qml\n' >"$svc/imports/qs/Haseen/qmldir"
    printf 'pragma Singleton\nimport QtQuick\nQtObject { property var lines: []; function push(s) { lines = lines.concat([s]); } function take() { const l = lines; lines = []; return l; } }\n' >"$svc/imports/qs/Haseen/Log.qml"
    printf 'pragma Singleton\nimport QtQuick\nQtObject { property var roles: ({ screensaver: {}, lock: {} }); function callRole(role, fn, args) { Log.push(role + "." + fn); return true; } function warnOnce(k, m) {} }\n' >"$svc/imports/qs/Haseen/Plugins.qml"
    printf 'pragma Singleton\nimport QtQuick\nQtObject { property bool idleOff: false; property bool screensaverOff: false }\n' >"$svc/imports/qs/Haseen/Flags.qml"
    printf 'pragma Singleton\nimport QtQuick\nQtObject { property string haseenPath: "/fixture/share/haseen" }\n' >"$svc/imports/qs/Haseen/Paths.qml"
    cat >"$svc/Harness.qml" <<EOF
import QtQuick
import qs.Haseen
import "file://$PLUGINS/haseen.idle" as Idle
Item {
    id: top
    property var svc: null
    property var out: ({})
    property var refs: ({})
    Component { id: comp; Idle.Service { pluginId: "haseen.idle" } }
    function inst() { for (const o of svc.data) if (o.objectAt !== undefined) return o; return null; }
    function mon(name) { const i = inst(); for (let k = 0; k < i.count; k++) { const o = i.objectAt(k); if (o && o.spec.name === name) return o; } return null; }
    function note(label) { out[label] = { keys: svc.monitorKeys, cycle: svc._cycle, started: svc.screensaverStartedThisCycle, sent: Log.take() }; }
    function idle(name, v) { const m = mon(name); if (m) m.isIdle = v; else Log.push("no monitor " + name); }
    property var steps: [
        () => { svc = comp.createObject(top, { settings: {} }); note("start"); },
        () => { idle("screensaver", true); note("cycle"); },
        () => { idle("screensaver", false); idle("presence", true); note("map"); refs.lock = mon("lock"); refs.dpms = mon("dpms"); },
        () => { svc.settings = { screensaverAfter: 30 }; out.same = [mon("lock") === refs.lock, mon("dpms") === refs.dpms]; note("set"); },
        () => { idle("lock", true); idle("dpms", true); note("lock-dpms"); },
        () => { Flags.screensaverOff = true; note("dropped"); },
        () => { Flags.screensaverOff = false; svc.settings = {}; Log.take(); idle("screensaver", true); idle("presence", true); idle("dpms", true); note("cycle2"); },
        () => { for (const n of ["screensaver", "lock", "dpms", "presence"]) idle(n, false); note("input"); },
        () => { note("input-later"); },
        () => { idle("screensaver", true); idle("presence", true); idle("lock", true); idle("dpms", true); Log.take(); Flags.idleOff = true; note("stay-awake"); },
        () => { Flags.idleOff = false; Log.take(); idle("screensaver", true); idle("presence", true); Log.take(); svc.destroy(); },
        () => { out.teardown = Log.take(); console.warn("RESULT " + JSON.stringify(out)); Qt.quit(); }
    ]
    property int at: 0
    Timer { interval: 10; repeat: true; running: true; onTriggered: top.steps[top.at++]() }
}
EOF
    svc_log="$(cd "$svc" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" -I imports Harness.qml 2>&1)"
    svc_out="$(sed -n 's/^.*RESULT //p' <<<"$svc_log")"
    sv() { jq -c "$1" <<<"${svc_out:-null}"; }
    assert_eq "service: the default monitors" '{"keys":["screensaver:150:1","lock:300:1","dpms:330:1"],"cycle":false,"started":false,"sent":[]}' "$(sv .start)"
    assert_eq "service: the screensaver monitor starts a cycle" '{"keys":["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"],"cycle":true,"started":true,"sent":["screensaver.start"]}' "$(sv .cycle)"
    assert_eq "service: the re-check when its window maps does not dismiss it" '{"keys":["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"],"cycle":true,"started":true,"sent":[]}' "$(sv .map)"
    assert_eq "service: a settings change during the cycle keeps the same lock and dpms monitors, counting" '[true,true]' "$(sv .same)"
    assert_eq "service: ... and only the screensaver key changes" '["screensaver:30:1","lock:150:0","dpms:180:0","presence:1:0"]' "$(sv .set.keys)"
    assert_eq "service: the lock and the displays at their time; screensaverStartedThisCycle ends with the lock" '{"keys":["screensaver:30:1","lock:150:0","dpms:180:0","presence:1:0"],"cycle":true,"started":false,"sent":["screensaver.dismiss","lock.lock","dpms off"]}' "$(sv '.["lock-dpms"]')"
    assert_eq "service: the screensaver monitor dropped without input: the cycle ends, the displays stay off" '{"keys":["lock:300:1","dpms:330:1"],"cycle":false,"started":false,"sent":["screensaver.dismiss"]}' "$(sv .dropped)"
    assert_eq "service: input ends the cycle after the handler returns" '{"keys":["screensaver:150:1","lock:150:0","dpms:180:0","presence:1:0"],"cycle":true,"started":true,"sent":[]}' "$(sv .input)"
    assert_eq "service: ... then dismisses the screensaver and wakes the displays it turned off" '{"keys":["screensaver:150:1","lock:300:1","dpms:330:1"],"cycle":false,"started":false,"sent":["screensaver.dismiss","dpms on"]}' "$(sv '.["input-later"]')"
    assert_eq "service: Stay Awake mid-cycle: onTimeoutsChanged ends it first, then the removed monitors undo their idle state" '{"keys":[],"cycle":false,"started":false,"sent":["screensaver.dismiss","dpms on","screensaver.dismiss"]}' "$(sv '.["stay-awake"]')"
    assert_eq "service: unloaded mid-cycle, it sends nothing" '[]' "$(sv .teardown)"
    assert_eq "service: no QML warnings or errors" "" "$(grep -v 'RESULT ' <<<"$svc_log" || true)"
else
    echo "  skip: $QML_BIN not installed, IdleLogic not exercised" >&2
fi

# --- haseen setup idle ----------------------------------------------------------
sandbox idle-setup
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen setup idle
assert_status "status works without a user shell.json" 0 "$STATUS"
assert_contains "status: suspend never by default" "$OUTPUT" "suspend      never      as on AC"
assert_contains "status: lock default" "$OUTPUT" "lock         300s       as on AC"

capture haseen setup idle set suspend 600 --dry-run
assert_status "set --dry-run" 0 "$STATUS"
assert_dry_pure "set --dry-run" "$OUTPUT"
assert_eq "set --dry-run writes nothing" "no" "$([[ -e $CFG ]] && echo yes || echo no)"

capture haseen setup idle set suspend 600
assert_status "set suspend" 0 "$STATUS"
assert_eq "set suspend saves suspendAfter" "600" "$(jq -r '.plugins["haseen.idle"].settings.suspendAfter' "$CFG")"
capture haseen setup idle set --battery suspend 120
capture haseen setup idle set lock 90 --battery
assert_eq "set --battery saves under onBattery" '{"suspendAfter":120,"lockAfter":90}' "$(jq -c '.plugins["haseen.idle"].settings.onBattery' "$CFG")"
assert_eq "set --battery leaves the AC value" "600" "$(jq -r '.plugins["haseen.idle"].settings.suspendAfter' "$CFG")"
capture haseen setup idle
assert_contains "status shows both columns" "$OUTPUT" "suspend      600s       120s"
assert_contains "status: battery follows AC where unset" "$OUTPUT" "dpms         330s       as on AC"

capture haseen setup idle unset --battery lock
assert_status "unset --battery" 0 "$STATUS"
assert_eq "unset drops only that battery key" '{"suspendAfter":120}' "$(jq -c '.plugins["haseen.idle"].settings.onBattery' "$CFG")"

# Unrelated user settings survive every write.
jq '.bar.position = "bottom" | .plugins["haseen.idle"].settings.respectInhibitors = false' "$CFG" >"$CFG.tmp" && mv "$CFG.tmp" "$CFG"
capture haseen setup idle set dpms 0
assert_eq "other settings are kept" "bottom false 0" \
    "$(jq -r '"\(.bar.position) \(.plugins["haseen.idle"].settings.respectInhibitors) \(.plugins["haseen.idle"].settings.dpmsAfter)"' "$CFG")"

# Prompts (HASEEN_INLINE: no floating terminal; answers through a pipe).
# AC: keep screensaver, lock 200, retry a bad dpms answer, suspend 0.
capture env HASEEN_INLINE=1 bash -c 'printf "\n200\nsoon\n400\n0\n" | haseen setup idle prompt'
assert_status "prompt (AC)" 0 "$STATUS"
assert_contains "prompt asks again after a bad answer" "$OUTPUT" "a whole number of seconds up to 2147483, please"
assert_eq "prompt (AC) saves the answers, Enter keeps" "null 200 400 0" \
    "$(jq -r '.plugins["haseen.idle"].settings | "\(.screensaverAfter) \(.lockAfter) \(.dpmsAfter) \(.suspendAfter)"' "$CFG")"
# Battery: screensaver 30, lock "-" (follow AC; it was unset), keep dpms,
# suspend "-" removes the 120 override.
capture env HASEEN_INLINE=1 bash -c 'printf "30\n-\n\n-\n" | haseen setup idle prompt --battery'
assert_status "prompt --battery" 0 "$STATUS"
assert_eq "prompt --battery: - follows AC again" '{"screensaverAfter":30}' "$(jq -c '.plugins["haseen.idle"].settings.onBattery' "$CFG")"
assert_contains "prompt prints the result" "$OUTPUT" "screensaver  150s       30s"
before="$(cat "$CFG")"
capture env HASEEN_INLINE=1 bash -c 'printf "\n\n\n\n" | haseen setup idle prompt'
assert_contains "prompt with only Enter changes nothing" "$OUTPUT" "Nothing changed."
assert_eq "prompt with only Enter leaves the file" "$before" "$(cat "$CFG")"

# Bad input is refused.
for bad in "set suspend" "set suspend soon" "set nap 60" "set suspend -5" "unset suspend" "unset --battery nap" "status --battery" "nap"; do
    # shellcheck disable=SC2086  # the words are the arguments
    capture haseen setup idle $bad
    assert_status "refuses: setup idle $bad" 2 "$STATUS"
done
assert_eq "refusals leave the file" "$before" "$(cat "$CFG")"

# Timeouts beyond what IdleMonitor takes (2147483 s; more wraps to an
# immediate timeout) and digit strings that would wrap Bash's integers are
# refused, never stored.
for bad in 2147484 3000000 9223372036854775808 18446744073709551616 99999999999999999999999; do
    capture haseen setup idle set suspend "$bad"
    assert_status "refuses: set suspend $bad" 2 "$STATUS"
    capture haseen setup idle set --battery lock "$bad"
    assert_status "refuses: set --battery lock $bad" 2 "$STATUS"
done
assert_eq "out-of-range refusals leave the file" "$before" "$(cat "$CFG")"
capture env HASEEN_INLINE=1 bash -c 'printf "\n3000000\n\n\n\n" | haseen setup idle prompt'
assert_contains "prompt refuses a timeout above the maximum" "$OUTPUT" "up to 2147483, please"
assert_eq "prompt with only a refused answer leaves the file" "$before" "$(cat "$CFG")"
capture haseen setup idle set suspend 0002147483
assert_status "set accepts the maximum (leading zeros dropped)" 0 "$STATUS"
assert_eq "the maximum is stored as a number" "2147483" "$(jq -r '.plugins["haseen.idle"].settings.suspendAfter' "$CFG")"
jq '.plugins["haseen.idle"].settings.lockAfter = 3000000' "$CFG" >"$CFG.tmp" && mv "$CFG.tmp" "$CFG"
capture haseen setup idle
assert_contains "status shows a hand-edited huge value as the shell uses it" "$OUTPUT" "lock         2147483s"

# A failed locked read or transform writes nothing (plan 082 review): the
# new file is produced in full before shell_config_write replaces the old.
before="$(cat "$CFG")"
real_jq="$(command -v jq)"
stub jq 'case "$*" in *"as \$s"*) echo "injected transform failure" >&2; exit 7;; esac; exec '"$real_jq"' "$@"'
capture haseen setup idle set suspend 60
assert_status "set reports the failed transform" 7 "$STATUS"
assert_eq "a failed transform leaves shell.json as it was" "$before" "$(cat "$CFG")"
# The shared writer refuses anything but one JSON object, for every caller
# that pipes into it (here haseen screensaver style).
stub jq 'case "$*" in *".style = \$s"*) exit 5;; esac; exec '"$real_jq"' "$@"'
capture haseen screensaver style native
assert_status "screensaver style reports the failed transform" 1 "$STATUS"
assert_contains "the writer says why it wrote nothing" "$OUTPUT" "not one JSON object"
assert_eq "shell_config_write keeps the file on empty input" "$before" "$(cat "$CFG")"
rm -f "$SANDBOX/stubs/jq"

# A broken user shell.json is never overwritten.
echo '{ broken' >"$CFG"
capture haseen setup idle set suspend 60
assert_status "set refuses a broken shell.json" 1 "$STATUS"
assert_eq "the broken file stays as it was" "{ broken" "$(cat "$CFG")"
