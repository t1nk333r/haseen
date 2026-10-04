import QtQuick
import Quickshell
import Quickshell.Io
import "Usage.js" as Usage

// CPU, RAM and GPU usage, sampled every 3 s and only while `active` (the
// bar widget or the panel is visible; architecture 6). CPU and RAM are
// FileView reads of /proc/stat and /proc/meminfo. The GPU source comes from
// gpu-probe.sh, run once on first activation:
//   AMD     FileView on gpu_busy_percent
//   Intel   FileView on the idle-residency counter (busy = 1 - idle/wall),
//           or the act/max clock ratio, labelled "GPU freq"
//   NVIDIA  ONE long-running `nvidia-smi -l 3` stream while active
// wantTop adds a `top -b -n 2` snapshot per tick for the panel.
Scope {
    id: root

    property bool active: false
    property bool wantGpu: true
    property bool wantTop: false
    property string gpuChoice: "auto"

    // -1 = not known yet.
    property real cpu: -1
    property var mem: null
    property real gpu: -1
    property var processes: []
    property var gpus: null
    readonly property var gpuInfo: wantGpu && gpus !== null ? Usage.pickGpu(gpus, gpuChoice) : null
    readonly property string gpuMethod: gpuInfo ? gpuInfo.method : "none"
    readonly property string gpuLabel: gpuMethod === "freq" ? "GPU freq" : "GPU"

    property var _prevStat: null
    property real _prevIdleMs: NaN
    property real _prevIdleAt: 0

    readonly property string _probe: Qt.resolvedUrl("gpu-probe.sh").toString().replace(/^file:\/\//, "")

    function sample(): void {
        stat.reload();
        meminfo.reload();
        if (gpuMethod === "busy" || gpuMethod === "rc6")
            gpuFile.reload();
        else if (gpuMethod === "freq")
            gpuAct.reload();
        if (wantTop && !top.running)
            top.running = true;
    }

    function probeOnce(): void {
        if (active && wantGpu && gpus === null && !probe.running)
            probe.running = true;
    }

    onActiveChanged: probeOnce()
    onWantGpuChanged: probeOnce()
    Component.onCompleted: probeOnce()
    onGpuInfoChanged: {
        gpu = -1;
        _prevIdleMs = NaN;
    }

    // haseen:sample
    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.active
        onTriggered: root.sample()
    }

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const cur = Usage.parseStat(text());
            const pct = Usage.cpuPercent(root._prevStat, cur);
            root._prevStat = cur;
            if (pct >= 0)
                root.cpu = pct;
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.mem = Usage.parseMeminfo(text())
    }

    FileView {
        id: gpuFile
        path: root.gpuMethod === "busy" || root.gpuMethod === "rc6" ? root.gpuInfo.args[0] : ""
        printErrors: false
        onLoaded: {
            const v = parseFloat(text());
            if (root.gpuMethod === "busy") {
                root.gpu = isFinite(v) ? Usage.clamp(v) : -1;
                return;
            }
            const now = Date.now();
            const pct = Usage.residencyBusy(root._prevIdleMs, v, now - root._prevIdleAt);
            root._prevIdleMs = v;
            root._prevIdleAt = now;
            if (pct >= 0)
                root.gpu = pct;
        }
    }

    FileView {
        id: gpuAct
        path: root.gpuMethod === "freq" ? root.gpuInfo.args[0] : ""
        printErrors: false
        // max is read after act, so the ratio uses this tick's act.
        onLoaded: gpuMax.reload()
    }

    FileView {
        id: gpuMax
        path: root.gpuMethod === "freq" ? root.gpuInfo.args[1] : ""
        printErrors: false
        onLoaded: root.gpu = Usage.freqPercent(gpuAct.text(), text())
    }

    Process {
        id: probe
        command: ["bash", root._probe]
        stdout: StdioCollector {
            onStreamFinished: root.gpus = Usage.parseGpus(text)
        }
    }

    Process {
        id: nvidia
        running: root.active && root.gpuMethod === "nvidia"
        command: ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits", "-i", root.gpuInfo ? String(root.gpuInfo.args[0]) : "0", "-l", "3"]
        stdout: SplitParser {
            onRead: line => root.gpu = Usage.parseNvidia(line)
        }
    }

    Process {
        id: top
        command: ["top", "-b", "-n", "2", "-d", "1", "-o", "%CPU", "-w", "512"]
        environment: ({
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: root.processes = Usage.parseTop(text, 8)
        }
    }
}
