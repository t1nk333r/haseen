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
// exists on Arch, CachyOS and NixOS, and its auth stack (system-auth:
// faillock, pam_unix, systemd-homed) is what a lock screen needs, so nothing
// has to be installed into /etc/pam.d. pamConfig/pamConfigDirectory point it
// at another service, e.g. a stub (pam_permit/pam_deny) in a scratch
// directory for testing.
//
// settings.preview (debug): lock() opens the same view in a normal overlay
// PanelWindow instead. The session is never locked, Escape closes it, and a
// correct password closes it too, so the UI and the PAM flow can be exercised
// without risking the real session.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool previewMode: settings.preview === true
    readonly property string pamConfig: _text(settings.pamConfig, "login")
    readonly property string pamConfigDirectory: _text(settings.pamConfigDirectory, "/etc/pam.d")

    property bool previewShown: false
    readonly property bool locked: sessionLock.locked || previewShown
    property bool busy: false
    property string message: ""
    property string _pending: ""
    property bool _responded: false

    function _text(v: var, fallback: string): string {
        return typeof v === "string" && v !== "" ? v : fallback;
    }

    function lock(): void {
        if (locked)
            return;
        _reset();
        if (previewMode) {
            console.info(pluginId + ": preview mode, showing the lock UI without locking the session");
            previewShown = true;
            return;
        }
        sessionLock.locked = true;
    }

    function submit(password: string): void {
        if (!locked || busy || password === "")
            return;
        _pending = password;
        _responded = false;
        busy = true;
        message = "";
        if (!pam.start()) {
            _reset();
            message = "Authentication could not start";
        }
    }

    function closePreview(): void {
        if (!previewShown)
            return;
        if (pam.active)
            pam.abort();
        _reset();
        previewShown = false;
    }

    function _reset(): void {
        busy = false;
        message = "";
        _pending = "";
        _responded = false;
    }

    function _unlocked(): void {
        _reset();
        if (previewShown)
            previewShown = false;
        else
            sessionLock.locked = false;
    }

    function _failed(text: string): void {
        _reset();
        message = text;
    }

    // One answer per attempt: a second prompt (e.g. an OTP module) cannot be
    // answered from a single password field, so the attempt is aborted.
    function _respond(): void {
        if (!busy || !pam.active || !pam.responseRequired)
            return;
        if (_responded) {
            const prompt = pam.message;
            pam.abort();
            _failed(prompt !== "" ? "Unsupported PAM prompt: " + prompt : "Unsupported PAM prompt");
            return;
        }
        _responded = true;
        const answer = _pending;
        _pending = "";
        pam.respond(answer);
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

        onResponseRequiredChanged: root._respond()
        onPamMessage: root._respond()
        onCompleted: result => {
            if (result === PamResult.Success)
                root._unlocked();
            else
                root._failed(result === PamResult.MaxTries ? "Too many attempts" : "Wrong password");
        }
        onError: error => root._failed("Authentication error: " + PamError.toString(error))
    }

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
                pamConfig: root.pamConfig
            });
        }
    }

    WlSessionLock {
        id: sessionLock

        locked: false

        WlSessionLockSurface {
            color: Theme.background

            LockView {
                anchors.fill: parent
                busy: root.busy
                message: root.message
                onSubmitted: password => root.submit(password)
            }
        }
    }

    LazyLoader {
        active: root.previewShown

        PanelWindow {
            screen: root.focusedScreen()
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.background
            WlrLayershell.namespace: "haseen-lock-preview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            LockView {
                anchors.fill: parent
                preview: true
                busy: root.busy
                message: root.message
                onSubmitted: password => root.submit(password)
                onCancelled: root.closePreview()
            }
        }
    }
}
