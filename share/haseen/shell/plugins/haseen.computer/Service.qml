import QtQuick
import Quickshell
import qs.Haseen
import "Computer.js" as Computer

// haseen.computer's service (role `computer`, plan 165): the 90 s histories
// the panel draws, kept while the panel is closed, so it opens on a full line
// instead of starting a new one each time (owner, 2026-11-13: "it should be
// working passively in the background").
//
// It samples nothing itself. It keeps one subscription to haseen-sidecar's
// `sysusage` stream every 3 s with `system` (the temperature and the disks),
// which Sidecar merges with the bar widget's 3 s one, so the daemon still runs
// one sampler and only adds the system readings to it. What it keeps is
// bounded by time, the last 90 s: 31 samples while every consumer asks for
// 3 s, as all shipped ones do.
//
// It does not restart a daemon that died: Sidecar keeps the subscription and
// sends it again on the next hello, but only an ensure() from elsewhere
// (opening the panel, the bar widget) starts the daemon again.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var sample: Sidecar.streams["sysusage"] || null

    // The histories, {t, v} per sample, newest last (Computer.push).
    property var cpuHistory: []
    property var memHistory: []
    property var tempHistory: []
    property var _last: null

    // record(sample, t) — one sample into the histories. The stream handler
    // calls it with the arrival time; a test calls it with its own clock.
    function record(s: var, t: real): void {
        if (!s)
            return;
        cpuHistory = Computer.push(cpuHistory, t, s.cpu);
        memHistory = Computer.push(memHistory, t, s.mem ? s.mem.percent : -1);
        tempHistory = Computer.push(tempHistory, t, s.cpuTempC);
    }

    // One key for the life of the shell, merged by Sidecar with every other
    // consumer of the stream.
    readonly property string _key: "computer:" + String(root)

    onSampleChanged: {
        // Sidecar.streams changes for every stream; only a new sysusage
        // frame is a sample.
        if (!sample || sample === _last)
            return;
        _last = sample;
        record(sample, Date.now());
    }
    Component.onCompleted: {
        Sidecar.ensure();
        Sidecar.want(_key, "sysusage", {
            intervalMs: Computer.INTERVAL_MS,
            gpu: "off",
            system: true
        });
    }
    Component.onDestruction: Sidecar.drop(_key)
}
