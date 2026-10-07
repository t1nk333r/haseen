pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen

// qs.Services.DgopService for DankMaterialShell plugins (architecture 5.4):
// the system figures DMS reads from its dgop backend, read here from
// haseen-sidecar's `sysusage` stream with `system` asked for (plan 032), so
// one sampler serves this and haseen.sysusage. Property names, units, the
// 60-sample history and the addRef/removeRef reference counting follow
// DankMaterialShell's quickshell/Services/DgopService.qml (MIT, Copyright (c)
// 2025 Avenge Media LLC):
//   cpuUsage, memoryUsage        percent
//   cpuTemperature               °C (0 = unknown, as DMS)
//   cpuFrequency                 MHz
//   networkRxRate/TxRate         bytes per second
//   networkHistory.rx/.tx        KiB per second, newest last
//   diskMounts                   [{ mount, device, fstype, size, used, avail,
//                                  percent }] with df -h strings ("476G",
//                                  "11%"), as dgop reports them
// The sidecar samples every 3 s while at least one reference is held, as
// DMS's own interval with someone watching, and not at all otherwise.
// Processes, GPUs, disk I/O rates and the system-info strings are not
// provided: no plugin haseen runs reads them.
Singleton {
    id: root

    property int refCount: 0
    property var enabledModules: []
    property var moduleRefCounts: ({})
    readonly property bool available: Haseen.Sidecar.has("sysusage")

    readonly property int historySize: 60
    property real cpuUsage: 0
    property real cpuFrequency: 0
    property real cpuTemperature: 0
    property real memoryUsage: 0
    property real totalMemoryMB: 0
    property real usedMemoryMB: 0
    property real availableMemoryMB: 0
    property int totalMemoryKB: 0
    property int usedMemoryKB: 0
    property int totalSwapKB: 0
    property int usedSwapKB: 0
    property real networkRxRate: 0
    property real networkTxRate: 0
    property var diskMounts: []
    property var cpuHistory: []
    property var memoryHistory: []
    property var networkHistory: ({
            rx: [],
            tx: []
        })

    readonly property string _key: "dms-dgop"
    property var _lastSample: null

    function addRef(modules) {
        refCount++;
        if (modules) {
            const counts = Object.assign({}, moduleRefCounts);
            for (const m of (Array.isArray(modules) ? modules : [modules]))
                counts[m] = (counts[m] || 0) + 1;
            moduleRefCounts = counts;
            enabledModules = Object.keys(counts);
        }
    }

    function removeRef(modules) {
        refCount = Math.max(0, refCount - 1);
        if (modules) {
            const counts = Object.assign({}, moduleRefCounts);
            for (const m of (Array.isArray(modules) ? modules : [modules])) {
                if ((counts[m] || 0) > 1)
                    counts[m]--;
                else
                    delete counts[m];
            }
            moduleRefCounts = counts;
            enabledModules = Object.keys(counts);
        }
    }

    function hasModule(module) {
        return refCount > 0 && (enabledModules.indexOf(module) >= 0 || enabledModules.indexOf("all") >= 0);
    }

    // df -h: KiB -> "476G", one decimal below 10.
    function humanKiB(kib) {
        const units = ["K", "M", "G", "T", "P"];
        let v = kib, i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (v < 10 && i > 0 ? v.toFixed(1) : Math.round(v)) + units[i];
    }

    function _append(list, value) {
        const out = list.concat([value]);
        return out.length > historySize ? out.slice(out.length - historySize) : out;
    }

    function _apply(s) {
        if (!s || s === _lastSample)
            return;
        _lastSample = s;
        if (typeof s.cpu === "number" && s.cpu >= 0) {
            cpuUsage = Math.round(s.cpu * 10) / 10;
            cpuHistory = _append(cpuHistory, cpuUsage);
        }
        if (s.mem) {
            memoryUsage = Math.round(s.mem.percent * 10) / 10;
            totalMemoryKB = s.mem.totalKiB;
            usedMemoryKB = s.mem.usedKiB;
            totalMemoryMB = s.mem.totalKiB / 1024;
            usedMemoryMB = s.mem.usedKiB / 1024;
            availableMemoryMB = s.mem.availableKiB / 1024;
            totalSwapKB = s.mem.swapTotalKiB;
            usedSwapKB = s.mem.swapUsedKiB;
            memoryHistory = _append(memoryHistory, memoryUsage);
        }
        // The system fields ride only on samples taken while someone asked
        // for them; a sample from before that leaves the last figures alone.
        if (typeof s.cpuTempC === "number")
            cpuTemperature = s.cpuTempC >= 0 ? Math.round(s.cpuTempC) : 0;
        if (typeof s.cpuFreqMHz === "number")
            cpuFrequency = s.cpuFreqMHz >= 0 ? Math.round(s.cpuFreqMHz) : 0;
        if (s.net && s.net.rxBps >= 0 && s.net.txBps >= 0) {
            networkRxRate = s.net.rxBps;
            networkTxRate = s.net.txBps;
            networkHistory = {
                rx: _append(networkHistory.rx, s.net.rxBps / 1024),
                tx: _append(networkHistory.tx, s.net.txBps / 1024)
            };
        }
        if (Array.isArray(s.disks))
            diskMounts = s.disks.map(d => ({
                        mount: d.mount,
                        device: d.device,
                        fstype: d.fstype,
                        size: humanKiB(d.totalKiB),
                        used: humanKiB(d.usedKiB),
                        avail: humanKiB(d.availKiB),
                        percent: Math.round(d.percent) + "%"
                    }));
    }

    function _subscribe() {
        if (refCount > 0)
            Haseen.Sidecar.want(_key, "sysusage", {
                intervalMs: 3000,
                gpu: "off",
                system: true
            });
        else
            Haseen.Sidecar.drop(_key);
    }

    onRefCountChanged: _subscribe()

    Connections {
        target: Haseen.Sidecar

        function onStreamsChanged() {
            if (root.refCount > 0)
                root._apply(Haseen.Sidecar.streams["sysusage"]);
        }
    }
}
