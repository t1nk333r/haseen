import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Haseen

// haseen.lock: answers the `lock` role (`haseen shell ipc lock lock`, the idle
// service) with an ext-session-lock: one LockView per screen, the password
// checked by PAM. The surfaces exist only while locked.
//
// PAM: the `login` service by default, as hyprlock and swaylock do. It
// exists on Arch and CachyOS, and its auth stack (system-auth:
// faillock, pam_unix, systemd-homed) is what a lock screen needs, so nothing
// has to be installed into /etc/pam.d. pamConfig/pamConfigDirectory point it
// at another service, e.g. a stub (pam_permit/pam_deny) in a scratch
// directory for testing.
//
// settings.preview (debug): lock() opens the same view in a normal overlay
// PanelWindow instead. The session is never locked, Escape closes it, and a
// correct password closes it too, so the UI and the PAM flow can be exercised
// without risking the real session.
//
// Fingerprint: while locked, a second PamContext runs the
// `haseen-lock-fingerprint` service (pam_fprintd, written by `haseen setup
// fingerprint`) next to the password field, and a touch unlocks. It is
// offered only when that service exists and fprintd has a finger enrolled
// for the user (checked when the shell starts and at every lock, never
// polled), and restarted after each failed scan. The mechanism (a parallel
// fingerprint context started once the lock is secure, retried, gated on an
// enrolled finger, a hint inside the field) is adapted from Omarchy's lock,
// shell/plugins/lock/Service.qml (MIT, Copyright (c) David Heinemeier
// Hansson).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool previewMode: settings.preview === true
    readonly property string pamConfig: _text(settings.pamConfig, "login")
    readonly property string pamConfigDirectory: _text(settings.pamConfigDirectory, "/etc/pam.d")
    readonly property bool fingerprintEnabled: settings.fingerprint !== false
    readonly property string fingerprintPamConfig: _text(settings.fingerprintPamConfig, "haseen-lock-fingerprint")
    // Silence after which a fingerprint conversation counts as hung (_fingerprintStall).
    readonly property int fingerprintStallMs: typeof settings.fingerprintStallMs === "number" && settings.fingerprintStallMs >= 100 ? Math.round(settings.fingerprintStallMs) : 5000
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    // Result of the last fprintd check (refreshFingerprint()).
    property bool fingerprintEnrolled: false
    readonly property bool fingerprintAvailable: fingerprintEnabled && fingerprintEnrolled && !_fingerprintGaveUp
    // The last pam_fprintd message was an error ("Failed to match fingerprint").
    property bool fingerprintError: false
    property bool _fingerprintGaveUp: false
    property int _fingerprintQuickFailures: 0
    property double _fingerprintStartedAt: 0
    // The current conversation was aborted as hung; its late end is ignored.
    property bool _fingerprintStalled: false

    property bool previewShown: false
    // Our own record of "a lock was asked for and not yet released". Not
    // `sessionLock.locked`: Quickshell 0.3 does not notify a change to that
    // property when it is assigned from JS, so a binding on it stayed false
    // for the whole lock, submit() returned early, and Enter on the lock screen
    // did nothing (io, 2026-10-06; reproduced in a nested session, plan 048).
    // `secure` is the compositor's confirmation and does notify.
    property bool lockRequested: false
    readonly property bool locked: lockRequested || sessionLock.secure || previewShown

    // "Oopsie daisy, your lock screen app died": when the shell crashes while
    // the session is locked, Hyprland keeps the session locked behind its red
    // screen and waits for a lock client. systemd restarts the shell
    // (Restart=on-failure), and this marker tells the new instance the old one
    // was holding the lock, so it takes the lock back
    // (misc.allow_session_lock_restore, set in default/hypr/looknfeel.lua)
    // and the owner gets a password field instead of the red screen. In the
    // runtime dir, so a reboot forgets it. `haseen lock release` clears it.
    // The marker names the Hyprland instance that held the lock: the runtime
    // dir outlives a compositor (a crash and a fresh login, a nested test
    // session), and a stale "1" made every later shell lock itself at start.
    readonly property string heldMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/haseen-lock-held"
    readonly property string compositorInstance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

    onLockRequestedChanged: if (!previewMode)
        heldFile.setText(lockRequested ? "1 " + compositorInstance + "\n" : "0\n")

    FileView {
        id: heldFile

        path: root.heldMarker
        printErrors: false
        // Synchronous: the marker must be on disk before the session can die.
        blockWrites: true
        atomicWrites: true
        onLoaded: {
            const held = text().trim().split(/\s+/);
            if (root.previewMode || held[0] !== "1" || root.locked)
                return;
            // A bare "1" predates the instance field; honour it, a lock that
            // is not needed is safer than a crashed lock left on the red screen.
            if (held.length > 1 && held[1] !== root.compositorInstance) {
                setText("0\n");
                return;
            }
            console.warn(root.pluginId + ": the previous shell died holding the lock; taking it back");
            root.lock();
        }
    }
    property bool busy: false
    // The last failure in English, as IPC and the tests read it.
    property string message: ""
    // The same failure for the screen: its catalog key and the %1 it fills
    // (a PAM prompt or error name, shown as PAM gives it), so the view
    // translates it (plan 109).
    property string messageKey: ""
    property string messageArg: ""
    property string _pending: ""
    property bool _responded: false

    function _text(v: var, fallback: string): string {
        return typeof v === "string" && v !== "" ? v : fallback;
    }

    function lock(): void {
        if (locked)
            return;
        _reset();
        _fingerprintGaveUp = false;
        _fingerprintQuickFailures = 0;
        // The cached answer starts the reader at once; this one catches a
        // finger enrolled (or removed) since the last lock.
        refreshFingerprint();
        if (previewMode) {
            console.info(pluginId + ": preview mode, showing the lock UI without locking the session");
            previewShown = true;
            _startFingerprint();
            return;
        }
        lockRequested = true;
        sessionLock.locked = true;
    }

    function submit(password: string): void {
        if (!locked || busy || password === "")
            return;
        _pending = password;
        _responded = false;
        busy = true;
        message = "";
        if (!pam.start())
            _failed(I18n.mark("Authentication could not start"), "");
    }

    // Escape during "Checking…": a PAM module that never answers would
    // otherwise hold the field read-only until `haseen lock release` from a
    // TTY. Cancelling only fails the attempt; the session stays locked.
    function cancelAttempt(): void {
        if (!busy)
            return;
        if (pam.active)
            pam.abort();
        _failed(I18n.mark("Cancelled"), "");
    }

    function closePreview(): void {
        if (!previewShown)
            return;
        if (pam.active)
            pam.abort();
        _stopFingerprint();
        _reset();
        previewShown = false;
    }

    function _reset(): void {
        busy = false;
        message = "";
        messageKey = "";
        messageArg = "";
        _pending = "";
        _responded = false;
    }

    // Either path unlocks: stop the other one, so a password check still in
    // flight cannot report "Wrong password" on an unlocked session.
    function _unlocked(): void {
        if (pam.active)
            pam.abort();
        _stopFingerprint();
        _reset();
        if (previewShown) {
            previewShown = false;
        } else {
            lockRequested = false;
            sessionLock.locked = false;
        }
    }

    // key is English with an optional %1; arg fills it.
    function _failed(key: string, arg: string): void {
        _reset();
        messageKey = key;
        messageArg = arg;
        message = key.replace("%1", () => arg);
    }

    // One answer per attempt: a second prompt (e.g. an OTP module) cannot be
    // answered from a single password field, so the attempt is aborted.
    function _respond(): void {
        if (!busy || !pam.active || !pam.responseRequired)
            return;
        if (_responded) {
            const prompt = pam.message;
            pam.abort();
            _failed(prompt !== "" ? I18n.mark("Unsupported PAM prompt: %1") : I18n.mark("Unsupported PAM prompt"), prompt);
            return;
        }
        _responded = true;
        const answer = _pending;
        _pending = "";
        pam.respond(answer);
    }

    function refreshFingerprint(): void {
        if (fingerprintEnabled && userName !== "" && !fingerprintCheck.running)
            fingerprintCheck.running = true;
    }

    // On a real lock, only once the compositor confirms it (secure), so a
    // touch can never "unlock" a session that is not locked yet.
    function _startFingerprint(): void {
        if (!fingerprintAvailable || fingerprintRetry.running)
            return;
        if (fingerprintPam.active) {
            // Still holding a conversation aborted as hung: that is another
            // failure, so a context that never lets go reaches the give-up.
            if (_fingerprintStalled) {
                _fingerprintStartedAt = Date.now();
                _fingerprintFinished(false);
            }
            return;
        }
        if (!previewShown && !(lockRequested && sessionLock.secure))
            return;
        fingerprintError = false;
        _fingerprintStalled = false;
        _fingerprintStartedAt = Date.now();
        fingerprintStall.restart();
        if (!fingerprintPam.start()) {
            fingerprintStall.stop();
            _fingerprintFinished(false);
        }
    }

    // A conversation that neither speaks nor ends has hung: pam_fprintd says
    // "Place your finger…" as soon as it holds the reader, and a stack that
    // cannot reach it fails at once. Seen on CI: a context restarted every 2 s
    // stopped answering, and fingerprint was then dead for the whole lock.
    // Abort it and count it as a failure that came at once, so the retry and
    // give-up rules above apply.
    function _fingerprintStall(): void {
        if (!fingerprintPam.active)
            return;
        console.warn(pluginId + ": the fingerprint conversation stopped answering; restarting it");
        _fingerprintStalled = true;
        fingerprintPam.abort();
        _fingerprintStartedAt = Date.now();
        _fingerprintFinished(false);
    }

    function _stopFingerprint(): void {
        fingerprintRetry.stop();
        fingerprintStall.stop();
        if (fingerprintPam.active)
            fingerprintPam.abort();
        fingerprintError = false;
    }

    function _fingerprintFinished(success: bool): void {
        if (!locked)
            return;
        if (success) {
            _unlocked();
            return;
        }
        // pam_fprintd waits for a finger (30 s by default) and gives up after
        // three mismatches, both of which take seconds; it is then restarted
        // at once. An attempt that fails immediately means the reader cannot
        // be reached (lid shut, device busy, fprintd missing): back off to
        // 2 s and give up after five in a row, so a dead reader does not
        // churn PAM conversations for the whole lock. The password still works.
        if (Date.now() - _fingerprintStartedAt < 2000) {
            _fingerprintQuickFailures += 1;
            if (_fingerprintQuickFailures >= 5) {
                console.warn(pluginId + ": the fingerprint reader keeps failing; fingerprint unlock is off until the next lock");
                _fingerprintGaveUp = true;
                return;
            }
            fingerprintRetry.interval = 2000;
        } else {
            _fingerprintQuickFailures = 0;
            fingerprintRetry.interval = 250;
        }
        fingerprintRetry.restart();
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    PamContext {
        id: pam

        config: root.pamConfig
        configDirectory: root.pamConfigDirectory

        // pamMessage only. Handling responseRequiredChanged as well answered
        // the first "Password:" twice: the second call saw an answered prompt
        // and aborted as "Unsupported PAM prompt", so even the right password
        // could never unlock (io, 2026-10-06, plan 048).
        onPamMessage: root._respond()
        // Only an attempt in flight counts. After a cancel, an unsupported
        // prompt or an error the attempt is already over, and its late end
        // must neither unlock nor overwrite the message with "Wrong password".
        onCompleted: result => {
            if (!root.busy)
                return;
            if (result === PamResult.Success)
                root._unlocked();
            else
                root._failed(result === PamResult.MaxTries ? I18n.mark("Too many attempts") : I18n.mark("Wrong password"), "");
        }
        onError: error => root._failed(I18n.mark("Authentication error: %1"), PamError.toString(error))
    }

    PamContext {
        id: fingerprintPam

        config: root.fingerprintPamConfig
        configDirectory: root.pamConfigDirectory

        // pam_fprintd only informs ("Place your finger…", "Failed to match
        // fingerprint"). A stack that asks for typed input cannot be answered
        // from here, and waiting on it would hold the context forever.
        onPamMessage: {
            fingerprintStall.stop();
            if (responseRequired) {
                console.warn(root.pluginId + ": " + root.fingerprintPamConfig + " asks for input; fingerprint unlock is off until the next lock");
                abort();
                root._fingerprintGaveUp = true;
                return;
            }
            root.fingerprintError = messageIsError;
        }
        // An error is followed by completed(Error), so this sees every end.
        // The end of a conversation aborted as hung was already counted.
        onCompleted: result => {
            fingerprintStall.stop();
            if (root._fingerprintStalled) {
                root._fingerprintStalled = false;
                return;
            }
            root._fingerprintFinished(result === PamResult.Success);
        }
    }

    // Single shot, armed only when a fingerprint attempt has ended (250 ms
    // after a real scan, 2 s after an immediate failure, see
    // _fingerprintFinished), so it never runs on its own.
    // haseen:ui-timeout
    Timer {
        id: fingerprintRetry

        repeat: false
        onTriggered: root._startFingerprint()
    }

    // Single shot, armed for each fingerprint attempt and stopped by its first
    // message or its end (_fingerprintStall).
    // haseen:ui-timeout
    Timer {
        id: fingerprintStall

        interval: root.fingerprintStallMs
        repeat: false
        onTriggered: root._fingerprintStall()
    }

    // `fprintd-list` prints each enrolled finger as " - #0: right-index-finger"
    // and "User x has no fingers enrolled" otherwise, so match the list
    // entry, not the word "finger". No PAM service file, no fingerprint.
    Process {
        id: fingerprintCheck

        command: ["sh", "-c", "test -f \"$1\" && exec fprintd-list \"$2\"", "sh", root.pamConfigDirectory + "/" + root.fingerprintPamConfig, root.userName]
        stdout: StdioCollector {
            onStreamFinished: {
                root.fingerprintEnrolled = /^\s*-\s*#\d+:/m.test(text);
                if (root.fingerprintAvailable)
                    root._startFingerprint();
                else
                    root._stopFingerprint();
            }
        }
    }

    Component.onCompleted: refreshFingerprint()

    // Test hook, preview mode only: submit a password to the preview over
    // IPC (`qs ipc call haseen.lock submit x`) instead of injecting keys.
    // Disabled whenever lock() would take the real session lock.
    IpcHandler {
        target: "haseen.lock"
        enabled: root.previewMode

        function submit(password: string): void {
            if (root.previewShown)
                root.submit(password);
        }

        function close(): void {
            root.closePreview();
        }

        function state(): string {
            return JSON.stringify({
                preview: root.previewShown,
                sessionLocked: sessionLock.locked,
                busy: root.busy,
                message: root.message,
                pamConfig: root.pamConfig,
                fingerprint: root.fingerprintAvailable,
                fingerprintActive: fingerprintPam.active
            });
        }
    }

    WlSessionLock {
        id: sessionLock

        locked: false
        onSecureStateChanged: if (secure)
            root._startFingerprint()

        WlSessionLockSurface {
            color: Theme.background

            LockView {
                anchors.fill: parent
                busy: root.busy
                message: root.message
                messageText: I18n.tr(root.messageKey, root.messageArg)
                fingerprint: root.fingerprintAvailable
                fingerprintError: root.fingerprintError
                onSubmitted: password => root.submit(password)
                onAttemptCancelled: root.cancelAttempt()
            }
        }
    }

    LazyLoader {
        active: root.previewShown
        source: Qt.resolvedUrl("PreviewWindow.qml")
        onItemChanged: if (item)
            item.service = root
    }
}
