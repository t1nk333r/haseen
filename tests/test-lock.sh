# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Lock screen fingerprint unlock (haseen.lock): `haseen setup fingerprint`
# writes the haseen-lock-fingerprint PAM service, and the lock service, run
# in preview mode in the real engine with stub PAM services (pam_permit /
# pam_deny) in a scratch pamConfigDirectory and a stub fprintd-list, unlocks
# on a fingerprint success, keeps the password path working when the
# fingerprint fails, and offers fingerprint only with an enrolled finger and
# the service present. A real finger on a real reader is not tested here.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.lock"
QS_BIN=${QS_BIN:-/usr/bin/qs}
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY

# --- the PAM service comes from haseen setup fingerprint ---------------------------
sandbox lock-setup
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/etc/pam.d"
capture env HASEEN_SYSROOT="$ROOT" haseen setup fingerprint --dry-run
assert_status "setup fingerprint dry-run" 0 "$STATUS"
assert_dry_pure "setup fingerprint" "$OUTPUT"
assert_contains "writes the lock's own fingerprint service" "$OUTPUT" \
    $'DRYRUN: write /etc/pam.d/haseen-lock-fingerprint (mode 0644):\n    | #%PAM-1.0\n    | # haseen lock screen, fingerprint only (written by haseen setup fingerprint)\n    | auth       required                    pam_fprintd.so\n    | account    include                     system-local-login'
assert_not_contains "does not need Omarchy's service" "$OUTPUT" "omarchy-lock"
# Re-run on a machine that already has it: nothing to write.
printf '#%%PAM-1.0\n# haseen lock screen, fingerprint only (written by haseen setup fingerprint)\nauth       required                    pam_fprintd.so\naccount    include                     system-local-login\n' \
    >"$ROOT/etc/pam.d/haseen-lock-fingerprint"
capture env HASEEN_SYSROOT="$ROOT" haseen setup fingerprint --dry-run
assert_not_contains "an identical service is left alone" "$OUTPUT" "write /etc/pam.d/haseen-lock-fingerprint"
assert_eq "fingerprint is on by default" true "$(jq -r '.settings.fingerprint.default' "$PLUGIN/manifest.json")"
assert_eq "and uses haseen's service" haseen-lock-fingerprint "$(jq -r '.settings.fingerprintPamConfig.default' "$PLUGIN/manifest.json")"

# --- the service in the real engine --------------------------------------------------
# lock_harness NAME QML_BODY — a ShellRoot with the plugin tree linked in;
# runs it offscreen and sets RESULT to the last "RESULT {json}" line.
lock_harness() {
    local harness="$SANDBOX/$1"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons plugins; do
        ln -sfn "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    printf '%s\n' "$2" >"$harness/shell.qml"
    capture env XDG_RUNTIME_DIR="$SANDBOX/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n 1)"
    [[ -n $RESULT ]] || RESULT='{"error":"no result"}'
}

if [[ -x $QS_BIN && -e /usr/lib/security/pam_permit.so ]]; then
    sandbox lock-qml
    mkdir -p "$SANDBOX/run" "$SANDBOX/pam"
    chmod 700 "$SANDBOX/run"
    PAM="$SANDBOX/pam"
    printf 'auth required pam_permit.so\naccount required pam_permit.so\n' | tee "$PAM/pw-permit" >"$PAM/fp-permit"
    printf 'auth required pam_deny.so\naccount required pam_permit.so\n' | tee "$PAM/pw-deny" >"$PAM/fp-deny"
    # A conversation that never answers: pam_exec waits on a command that
    # shows no message and does not end in time.
    printf 'auth required pam_exec.so /usr/bin/sleep 20\naccount required pam_permit.so\n' >"$PAM/fp-hang"
    # fprintd-list's real output for a user with one enrolled finger.
    stub fprintd-list "printf '%s\n' 'found 1 devices' 'Device at /net/reactivated/Fprint/Device/0' 'Using device /net/reactivated/Fprint/Device/0' \"Fingerprints for user \$1 on Synaptics Sensors (press):\" ' - #0: right-index-finger'"

    lock_harness enrolled "$(
        cat <<QML
import QtQuick
import Quickshell
ShellRoot {
    id: probe
    property int phase: 0
    property int tick: 0
    property int mark: 0
    property var result: ({})
    property var a: null
    property var b: null
    property var h: null
    property var d: null
    property var e: null
    function make(fp: string, extra: var): var {
        const c = Qt.createComponent("file://$PLUGIN/Service.qml");
        if (c.status !== Component.Ready) {
            probe.done({ error: c.errorString() });
            return null;
        }
        const s = { preview: true, pamConfigDirectory: "$PAM", pamConfig: "pw-deny", fingerprintPamConfig: fp };
        for (const k in extra)
            s[k] = extra[k];
        return c.createObject(probe, { pluginId: "haseen.lock", settings: s });
    }
    function done(r: var): void {
        console.log("RESULT " + JSON.stringify(r));
        Qt.quit();
    }
    Component.onCompleted: {
        a = make("fp-permit", {});
        b = make("fp-deny", { fingerprintStallMs: 1000 });
        h = make("fp-hang", { fingerprintStallMs: 300 });
        d = make("fp-absent", {});
        e = make("fp-permit", { fingerprint: false });
        const v = Qt.createComponent("file://$PLUGIN/LockView.qml");
        const on = v.createObject(probe, { fingerprint: true });
        const off = v.createObject(probe, { fingerprint: false });
        const find = (item) => {
            if (item.objectName === "fingerprintHint")
                return item;
            for (const c of item.children) {
                const f = find(c);
                if (f)
                    return f;
            }
            return null;
        };
        const hint = (view) => {
            const h = find(view);
            return h ? h.visible : null;
        };
        result.hintShown = hint(on);
        result.hintHidden = hint(off);
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.tick += 1;
            const t = probe.tick - probe.mark;
            if (probe.phase === 0 && probe.a && probe.a.fingerprintEnrolled && probe.b.fingerprintEnrolled && t >= 10) {
                probe.result.offeredWithEnrolledFinger = probe.a.fingerprintAvailable;
                probe.result.offeredWithoutService = probe.d.fingerprintAvailable;
                probe.result.offeredWhenDisabled = probe.e.fingerprintAvailable;
                probe.e.lock();
                probe.a.lock();
                probe.result.shownAfterLock = probe.a.previewShown;
                probe.phase = 1;
                probe.mark = probe.tick;
            } else if (probe.phase === 1 && !probe.a.previewShown) {
                probe.result.fingerprintUnlocked = true;
                probe.b.lock();
                probe.h.lock();
                probe.phase = 2;
                probe.mark = probe.tick;
            } else if (probe.phase === 1 && t > 50) {
                probe.done({ error: "fingerprint success did not unlock" });
            } else if (probe.phase === 2 && t >= 5) {
                probe.result.denyStillShown = probe.b.previewShown;
                probe.result.denyStillOffered = probe.b.fingerprintAvailable;
                probe.b.submit("wrong");
                probe.phase = 3;
                probe.mark = probe.tick;
            } else if (probe.phase === 3 && !probe.b.busy && probe.b.message !== "") {
                probe.result.wrongMessage = probe.b.message;
                probe.result.shownAfterWrong = probe.b.previewShown;
                probe.result.offeredAfterWrong = probe.b.fingerprintAvailable;
                probe.phase = 4;
                probe.mark = probe.tick;
            } else if (probe.phase === 4 && ((probe.b._fingerprintGaveUp && probe.h._fingerprintGaveUp) || t > 400) /* 5 retries 2 s apart: 40 s for a loaded CI runner */) {
                probe.result.gaveUpOnDeadReader = probe.b._fingerprintGaveUp;
                probe.result.gaveUpOnHungReader = probe.h._fingerprintGaveUp;
                probe.result.disabledStillShown = probe.e.previewShown;
                probe.e.closePreview();
                const s = Object.assign({}, probe.b.settings);
                s.pamConfig = "pw-permit";
                probe.b.settings = s;
                probe.b.submit("right");
                probe.phase = 5;
                probe.mark = probe.tick;
            } else if (probe.phase === 5 && !probe.b.previewShown) {
                probe.result.passwordUnlocked = true;
                probe.done(probe.result);
            } else if (probe.phase === 5 && t > 50) {
                probe.done({ error: "password did not unlock" });
            }
        }
    }
}
QML
    )"
    assert_eq "the service loads" "" "$(jq -r '.error // empty' <<<"$RESULT")"
    assert_eq "fingerprint is offered with an enrolled finger" true "$(jq -r .offeredWithEnrolledFinger <<<"$RESULT")"
    assert_eq "not without the PAM service" false "$(jq -r .offeredWithoutService <<<"$RESULT")"
    assert_eq "not when turned off" false "$(jq -r .offeredWhenDisabled <<<"$RESULT")"
    assert_eq "the lock comes up" true "$(jq -r .shownAfterLock <<<"$RESULT")"
    assert_eq "a fingerprint success unlocks without typing" true "$(jq -r .fingerprintUnlocked <<<"$RESULT")"
    assert_eq "a failing fingerprint keeps the lock" true "$(jq -r .denyStillShown <<<"$RESULT")"
    assert_eq "and keeps offering it" true "$(jq -r .denyStillOffered <<<"$RESULT")"
    assert_eq "a wrong password still says so" "Wrong password" "$(jq -r .wrongMessage <<<"$RESULT")"
    assert_eq "and keeps the lock" true "$(jq -r .shownAfterWrong <<<"$RESULT")"
    assert_eq "a reader that fails at once is given up on" true "$(jq -r .gaveUpOnDeadReader <<<"$RESULT")"
    if [[ -e /usr/lib/security/pam_exec.so ]]; then
        assert_contains "a conversation that stops answering is aborted" "$OUTPUT" "fingerprint conversation stopped answering"
        assert_eq "and a reader that keeps hanging is given up on" true "$(jq -r .gaveUpOnHungReader <<<"$RESULT")"
    fi
    assert_eq "fingerprint off: no unlock without a password" true "$(jq -r .disabledStillShown <<<"$RESULT")"
    assert_eq "the right password unlocks" true "$(jq -r .passwordUnlocked <<<"$RESULT")"
    assert_eq "the hint shows inside the field" true "$(jq -r .hintShown <<<"$RESULT")"
    assert_eq "and only when offered" false "$(jq -r .hintHidden <<<"$RESULT")"
    pam_starts="$(grep -c 'config "pw-deny"' <<<"$OUTPUT" || true)"
    assert_eq "one password conversation per submit" 1 "$pam_starts"

    # No enrolled finger: never offered, even with a service that would pass.
    stub fprintd-list "printf '%s\n' 'found 1 devices' 'Using device /net/reactivated/Fprint/Device/0' \"User \$1 has no fingers enrolled for Synaptics Sensors.\""
    lock_harness unenrolled "$(
        cat <<QML
import QtQuick
import Quickshell
ShellRoot {
    id: probe
    property var svc: null
    property int tick: 0
    Component.onCompleted: {
        const c = Qt.createComponent("file://$PLUGIN/Service.qml");
        svc = c.createObject(probe, { pluginId: "haseen.lock", settings: { preview: true, pamConfigDirectory: "$PAM", pamConfig: "pw-deny", fingerprintPamConfig: "fp-permit" } });
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.tick += 1;
            if (probe.tick === 10)
                probe.svc.lock();
            if (probe.tick === 40) {
                console.log("RESULT " + JSON.stringify({ offered: probe.svc.fingerprintAvailable, shown: probe.svc.previewShown }));
                Qt.quit();
            }
        }
    }
}
QML
    )"
    assert_eq "no enrolled finger: not offered" false "$(jq -r .offered <<<"$RESULT")"
    assert_eq "and the lock stays until a password" true "$(jq -r .shown <<<"$RESULT")"
else
    echo "  skip: quickshell or pam_permit not installed; the lock service is not loaded" >&2
fi
