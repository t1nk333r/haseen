.pragma library

// Pure parsers for haseen.sysusage. No Qt or Quickshell types, so
// tests/test-widgets-a.sh runs them headless under /usr/lib/qt6/bin/qml.

// /proc/stat aggregate "cpu" line -> { total, idle } in jiffies, or null.
// idle counts idle + iowait: a CPU waiting on I/O is not busy.
function parseStat(text) {
    const lines = String(text || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const f = lines[i].trim().split(/\s+/);
        if (f[0] !== "cpu")
            continue;
        const n = f.slice(1, 9).map(Number);
        if (n.length < 4 || n.some(v => !isFinite(v)))
            return null;
        // user nice system idle iowait irq softirq steal; guest time is
        // already included in user/nice, so it is not added again.
        const total = n.reduce((a, b) => a + b, 0);
        const idle = n[3] + (n.length > 4 ? n[4] : 0);
        return {
            total: total,
            idle: idle
        };
    }
    return null;
}

// Busy percentage between two parseStat samples; -1 when unknown.
function cpuPercent(prev, cur) {
    if (!prev || !cur)
        return -1;
    const dt = cur.total - prev.total;
    const di = cur.idle - prev.idle;
    if (dt <= 0 || di < 0)
        return -1;
    return clamp(100 * (dt - di) / dt);
}

// /proc/meminfo -> { totalKiB, availableKiB, usedKiB, percent, swapTotalKiB,
// swapUsedKiB }, or null. "Used" is total - MemAvailable, the figure `free`
// prints as used + (buff/cache that cannot be reclaimed).
function parseMeminfo(text) {
    const kv = {};
    const lines = String(text || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const m = /^(\w+(?:\(\w+\))?):\s+(\d+)/.exec(lines[i]);
        if (m)
            kv[m[1]] = Number(m[2]);
    }
    const total = kv.MemTotal;
    if (!(total > 0))
        return null;
    // MemAvailable exists since Linux 3.14; estimate it on older kernels.
    const available = kv.MemAvailable !== undefined ? kv.MemAvailable : (kv.MemFree || 0) + (kv.Buffers || 0) + (kv.Cached || 0);
    const used = Math.max(0, total - available);
    const swapTotal = kv.SwapTotal || 0;
    return {
        totalKiB: total,
        availableKiB: available,
        usedKiB: used,
        percent: clamp(100 * used / total),
        swapTotalKiB: swapTotal,
        swapUsedKiB: Math.max(0, swapTotal - (kv.SwapFree || 0))
    };
}

// Intel busy share from an idle-residency counter (i915 rc6_residency_ms,
// xe gtidle/idle_residency_ms): busy = 1 - idle time / wall time. -1 when
// unknown (first sample, counter reset).
function residencyBusy(prevIdleMs, curIdleMs, wallMs) {
    if (!(wallMs > 0) || !isFinite(prevIdleMs) || !isFinite(curIdleMs) || curIdleMs < prevIdleMs)
        return -1;
    return clamp(100 * (1 - (curIdleMs - prevIdleMs) / wallMs));
}

// Frequency fallback: actual / max GPU clock, labelled as frequency.
function freqPercent(actMhz, maxMhz) {
    const a = Number(actMhz), m = Number(maxMhz);
    if (!(m > 0) || !isFinite(a))
        return -1;
    return clamp(100 * a / m);
}

// One line of `nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits`.
// Several GPUs print one line each per tick; this reads one line.
function parseNvidia(line) {
    const v = parseFloat(String(line || "").trim());
    return isFinite(v) ? clamp(v) : -1;
}

// Output of the GPU probe in Sampler.qml, one line per card:
//   "<card> <driver> <boot_vga 0|1> <method> [args…]"
// method: busy PATH (amdgpu %), rc6 PATH (idle-residency ms), freq ACT MAX
// (MHz files), nvidia PCI_SLOT, none.
// -> [{ card, driver, bootVga, method, args }]
function parseGpus(text) {
    const out = [];
    const lines = String(text || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const f = lines[i].trim().split(/\s+/);
        if (f.length >= 4 && /^card\d+$/.test(f[0]))
            out.push({
                card: f[0],
                driver: f[1],
                bootVga: f[2] === "1",
                method: f[3],
                args: f.slice(4)
            });
    }
    return out;
}

// The GPU to show. "off" -> null; "cardN" -> that card; "auto" -> the boot
// VGA device, else the first card. On a hybrid laptop the boot VGA device is
// the iGPU, so auto never reads the dGPU: reading amdgpu's busy file or
// running nvidia-smi wakes a runtime-suspended dGPU and keeps it awake.
function pickGpu(gpus, choice) {
    if (!gpus || gpus.length === 0 || choice === "off")
        return null;
    if (choice && choice !== "auto")
        return gpus.find(g => g.card === choice) || null;
    return gpus.find(g => g.bootVga) || gpus[0];
}

// `top -b -n 2` output -> the last frame's tasks, highest CPU first:
// [{ pid, user, cpu, mem, command }], at most `limit`.
function parseTop(text, limit) {
    const lines = String(text || "").split("\n");
    let start = -1;
    for (let i = lines.length - 1; i >= 0; i--)
        if (/^\s*PID\s+USER\s/.test(lines[i])) {
            start = i + 1;
            break;
        }
    if (start < 0)
        return [];
    const header = lines[start - 1].trim().split(/\s+/);
    const cpuCol = header.indexOf("%CPU");
    const memCol = header.indexOf("%MEM");
    const cmdCol = header.indexOf("COMMAND");
    if (cpuCol < 0 || memCol < 0 || cmdCol < 0)
        return [];
    const rows = [];
    for (let i = start; i < lines.length; i++) {
        const f = lines[i].trim().split(/\s+/);
        if (f.length <= cmdCol || !/^\d+$/.test(f[0]))
            continue;
        const cpu = parseFloat(f[cpuCol].replace(",", "."));
        const mem = parseFloat(f[memCol].replace(",", "."));
        rows.push({
            pid: Number(f[0]),
            user: f[1],
            cpu: isFinite(cpu) ? cpu : 0,
            mem: isFinite(mem) ? mem : 0,
            command: f.slice(cmdCol).join(" ")
        });
    }
    rows.sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
    return rows.slice(0, limit > 0 ? limit : 8);
}

// KiB -> "3.4 GiB" / "512 MiB".
function formatKiB(kib) {
    if (!(kib >= 0))
        return "?";
    if (kib >= 1048576)
        return (kib / 1048576).toFixed(1) + " GiB";
    return Math.round(kib / 1024) + " MiB";
}

function clamp(v) {
    return Math.max(0, Math.min(100, v));
}
