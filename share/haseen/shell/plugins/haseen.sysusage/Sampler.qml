import QtQuick
import qs.Haseen

// CPU, RAM and GPU usage. No timer, no file read and no process lives here any
// more: haseen-sidecar samples /proc and the GPU sysfs nodes, and this is the
// subscription that asks it to, only while `active` (the bar widget or the
// panel is visible; architecture 6).
//
// `available` is the capability gate (plan 032): with no daemon, an older one
// or one that was killed, it goes false and the widget and panel hide
// themselves rather than showing a dead reading.
QtObject {
    id: root

    property bool active: false
    property bool wantGpu: true
    property bool wantTop: false
    property string gpuChoice: "auto"
    property int intervalMs: 3000

    readonly property bool available: Sidecar.has("sysusage")

    readonly property var _data: Sidecar.streams["sysusage"] || null
    // -1 = not known yet, the same contract the QML sampler had.
    readonly property real cpu: _data && typeof _data.cpu === "number" ? _data.cpu : -1
    readonly property var mem: _data ? _data.mem : null
    readonly property real gpu: _data && typeof _data.gpu === "number" ? _data.gpu : -1
    readonly property var processes: _data && _data.processes ? _data.processes : []
    readonly property var gpus: _data ? _data.gpus : null
    readonly property var gpuInfo: wantGpu && _data ? _data.gpuInfo : null
    readonly property string gpuMethod: gpuInfo ? gpuInfo.method : "none"
    readonly property string gpuLabel: gpuMethod === "freq" ? "GPU freq" : "GPU"

    // One key per instance, so two bars and the panel merge into one sampler in
    // the daemon instead of each reading /proc for itself.
    readonly property string _key: "sysusage:" + String(root)

    function _apply(): void {
        if (!active) {
            Sidecar.drop(_key);
            return;
        }
        Sidecar.want(_key, "sysusage", {
            intervalMs: intervalMs,
            gpu: wantGpu ? gpuChoice : "off",
            processes: wantTop
        });
    }

    onActiveChanged: _apply()
    onWantGpuChanged: _apply()
    onWantTopChanged: _apply()
    onGpuChoiceChanged: _apply()
    onIntervalMsChanged: _apply()
    Component.onCompleted: {
        // Ask for a daemon before subscribing: the capability it announces is
        // what makes the widget visible in the first place.
        Sidecar.ensure();
        _apply();
    }
    Component.onDestruction: Sidecar.drop(_key)
}
