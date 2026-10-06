import Quickshell
import Quickshell.Wayland
import qs.Haseen

// The preview of the lock (settings.preview): the same LockView in an
// overlay window that never locks the session. A file of its own, loaded by
// URL, so Service.qml compiles where no PanelWindow backend exists (the
// offscreen engine of tests/test-lock.sh) and only the preview window is
// missing there.
PanelWindow {
    id: win

    // The haseen.lock Service, set by its loader.
    property var service: null

    screen: service ? service.focusedScreen() : null
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
        busy: win.service ? win.service.busy : false
        message: win.service ? win.service.message : ""
        fingerprint: win.service ? win.service.fingerprintAvailable : false
        fingerprintError: win.service ? win.service.fingerprintError : false
        onSubmitted: password => win.service.submit(password)
        onCancelled: win.service.closePreview()
    }
}
