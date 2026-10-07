# shellcheck shell=bash
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
        // Manual screen off/on (plan 084) against haseen.idle. The model:
        // Hyprland's DPMS state, written by haseen screen off|on, by the
        // service's dispatches and by input (key_press_enables_dpms and
        // mouse_move_enables_dpms wake the displays before any monitor
        // reports activity). The service part is Service.qml _run: dpms.off
        // sets _dpmsOff and sends off, dpms.on clears it and sends on.
        // "stay-awake" removes every monitor; an idle one runs its
        // non-idle edge (the delegate's Component.onDestruction).
        const sim = events => {
            const st = { screen: true, dpmsOff: false, idle: {}, sent: [] };
            const apply = (m, isIdle) => {
                st.idle[m] = isIdle;
                for (const a of Idle.actions(m, isIdle, { dpmsOff: st.dpmsOff, idleOff: false })) {
                    st.sent.push(a);
                    if (a === "dpms.off") { st.dpmsOff = true; st.screen = false; }
                    if (a === "dpms.on") { st.dpmsOff = false; st.screen = true; }
                }
            };
            const wake = () => { for (const m of Object.keys(st.idle)) if (st.idle[m]) apply(m, false); };
            for (const e of events) {
                if (e === "manual-off") st.screen = false;
                else if (e === "manual-on") st.screen = true;
                else if (e === "input") { st.screen = true; wake(); }
                else if (e === "stay-awake") { wake(); st.idle = {}; }
                else apply(e.replace(/^idle:/, ""), true);
            }
            return { screen: st.screen, dpmsOff: st.dpmsOff, sent: st.sent };
        };
        out("s-off-input", sim(["manual-off", "input"]));
        out("s-off-stays", sim(["manual-off", "idle:screensaver"]));
        out("s-off-stay-awake", sim(["manual-off", "idle:screensaver", "stay-awake"]));
        out("s-off-lock-dpms", sim(["manual-off", "idle:screensaver", "idle:lock", "idle:dpms"]));
        out("s-off-lock-dpms-input", sim(["manual-off", "idle:screensaver", "idle:lock", "idle:dpms", "input"]));
        out("s-idle-off-manual-on", sim(["idle:dpms", "manual-on", "input", "idle:dpms"]));
        out("s-idle-off-manual-on-cycle", sim(["idle:dpms", "manual-on", "input", "idle:dpms", "input"]));
        out("s-on-awake", sim(["manual-on"]));
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
    # Manual screen off/on against the service (plan 084, the model above).
    assert_eq "manual off, then input: the input wakes the displays; the service sends nothing" \
        '{"screen":true,"dpmsOff":false,"sent":[]}' "$(r s-off-input)"
    assert_eq "manual off, the screensaver monitor fires: the displays stay off" \
        '{"screen":false,"dpmsOff":false,"sent":["screensaver.start"]}' "$(r s-off-stays)"
    assert_eq "manual off, then Stay Awake removes an idle monitor: no dpms.on, the displays stay off" \
        '{"screen":false,"dpmsOff":false,"sent":["screensaver.start","screensaver.dismiss"]}' "$(r s-off-stay-awake)"
    assert_eq "manual off: the lock still comes at lockAfter, then the service's own dpms off" \
        '{"screen":false,"dpmsOff":true,"sent":["screensaver.start","screensaver.dismiss","lock","dpms.off"]}' "$(r s-off-lock-dpms)"
    assert_eq "manual off, an idle cycle, input: the service turns on only what it turned off" \
        '{"screen":true,"dpmsOff":false,"sent":["screensaver.start","screensaver.dismiss","lock","dpms.off","screensaver.dismiss","dpms.on"]}' "$(r s-off-lock-dpms-input)"
    assert_eq "manual on while the service holds the displays off: its next cycle still turns them off" \
        '{"screen":false,"dpmsOff":true,"sent":["dpms.off","dpms.on","dpms.off"]}' "$(r s-idle-off-manual-on)"
    assert_eq "manual on, input, a second cycle: off and on as before" \
        '{"screen":true,"dpmsOff":false,"sent":["dpms.off","dpms.on","dpms.off","dpms.on"]}' "$(r s-idle-off-manual-on-cycle)"
    assert_eq "manual on with the displays on: nothing for the service" \
        '{"screen":true,"dpmsOff":false,"sent":[]}' "$(r s-on-awake)"
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
assert_contains "prompt asks again after a bad answer" "$OUTPUT" "a whole number of seconds, please"
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

# A broken user shell.json is never overwritten.
echo '{ broken' >"$CFG"
capture haseen setup idle set suspend 60
assert_status "set refuses a broken shell.json" 1 "$STATUS"
assert_eq "the broken file stays as it was" "{ broken" "$(cat "$CFG")"
