//! What haseen.sysusage shows: CPU, memory, GPU busy and the top processes,
//! plus, on request, the system stats DMS desktop plugins read (temperature,
//! clock, network, disks). One sampler shared by every subscriber; the process
//! list is read straight from /proc instead of forking top. Ported from the Go
//! daemon's internal/sysusage (plan 167), behaviour unchanged.

mod gpu;
mod nvidia;
mod system;

pub use gpu::Gpu;
pub use system::{Disk, NetRate, StatFs, StatFsFn, System};

use crate::gocompat::join;
use crate::json::{go_lossy, Obj};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

/// One sysusage event. `system` adds cpuTempC, cpuFreqMHz, net and disks at the
/// top level only when it is set.
#[derive(Clone, Debug, PartialEq)]
pub struct Sample {
    pub cpu: f64,
    pub mem: Option<Mem>,
    pub gpu: f64,
    /// None is `null`: no DRM directory, or no card in it.
    pub gpus: Option<Vec<Gpu>>,
    pub gpu_info: Option<Gpu>,
    pub processes: Vec<Process>,
    pub system: Option<System>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Mem {
    pub total_kib: i64,
    pub available_kib: i64,
    pub used_kib: i64,
    pub percent: f64,
    pub swap_total_kib: i64,
    pub swap_used_kib: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Process {
    pub pid: i64,
    pub user: String,
    pub cpu: f64,
    pub mem: f64,
    pub command: String,
}

#[derive(Clone, Copy, Default)]
struct CpuTimes {
    total: i64,
    idle: i64,
}

#[derive(Clone)]
struct ProcTimes {
    jiffies: i64,
    command: String,
    rss_kib: i64,
}

/// The sampler. `root` is the filesystem it reads: a fixture tree in tests,
/// empty (the live machine) everywhere else. It is owned by one thread, so two
/// samples can never overlap (the Go daemon needed a mutex for that, PR #126).
pub struct Sampler {
    root: Vec<u8>,
    /// Sizes the disks (None = statfs(2)). A fixture tree has no mounted
    /// filesystems to ask, so tests fake it.
    pub statfs: Option<StatFsFn>,

    prev_cpu: Option<CpuTimes>,
    prev_proc: HashMap<i64, ProcTimes>,
    spare_proc: HashMap<i64, ProcTimes>,
    prev_proc_at: Option<Instant>,
    users: HashMap<String, String>,
    page_size: i64,
    gpu: gpu::GpuState,
    sys: system::SysState,
}

impl Sampler {
    pub fn new(root: &[u8]) -> Self {
        // SAFETY: sysconf has no preconditions.
        let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        Sampler {
            root: root.to_vec(),
            statfs: None,
            prev_cpu: None,
            prev_proc: HashMap::new(),
            spare_proc: HashMap::new(),
            prev_proc_at: None,
            users: HashMap::new(),
            page_size: if page > 0 { page as i64 } else { 4096 },
            gpu: gpu::GpuState::default(),
            sys: system::SysState::default(),
        }
    }

    fn path(&self, p: &str) -> PathBuf {
        join(&self.root, p.as_bytes())
    }

    /// One tick. `gpu_choice` is "auto", "off" or a card name, the values
    /// haseen.sysusage's `gpu` setting takes; `processes` adds the process
    /// list; `system` adds System.
    pub fn sample(&mut self, gpu_choice: &str, processes: bool, system: bool) -> Sample {
        let now = Instant::now();
        let cpu = self.cpu_percent();
        let mem = self.mem();
        let (gpus, gpu_info, gpu) = self.gpu_sample(gpu_choice, now);
        let processes = if processes {
            self.processes(8, now)
        } else {
            Vec::new()
        };
        let system = if system {
            Some(self.system(now))
        } else {
            // A subscriber that asks again later gets -1 first, not the
            // average over the time nobody was asking.
            self.sys.net = None;
            None
        };
        Sample {
            cpu,
            mem,
            gpu,
            gpus,
            gpu_info,
            processes,
            system,
        }
    }

    /// The busy share since the previous call; -1 on the first one. Idle
    /// counts idle + iowait: a CPU waiting on I/O is not busy.
    fn cpu_percent(&mut self) -> f64 {
        let Ok(raw) = std::fs::read(self.path("/proc/stat")) else {
            return -1.0;
        };
        let text = String::from_utf8_lossy(&raw);
        let mut cur = CpuTimes::default();
        for line in text.lines() {
            let fields: Vec<&str> = line.split_whitespace().collect();
            if fields.len() < 5 || fields[0] != "cpu" {
                continue;
            }
            for (i, field) in fields[1..].iter().enumerate() {
                if i >= 8 {
                    break;
                }
                let Ok(v) = field.parse::<i64>() else {
                    return -1.0;
                };
                cur.total = cur.total.wrapping_add(v);
                if i == 3 || i == 4 {
                    cur.idle = cur.idle.wrapping_add(v);
                }
            }
            break;
        }
        if cur.total == 0 {
            return -1.0;
        }
        let prev = self.prev_cpu.replace(cur);
        let Some(prev) = prev else {
            return -1.0;
        };
        let dt = cur.total.wrapping_sub(prev.total);
        let di = cur.idle.wrapping_sub(prev.idle);
        if dt <= 0 || di < 0 {
            return -1.0;
        }
        clamp(100.0 * (dt - di) as f64 / dt as f64)
    }

    fn mem(&self) -> Option<Mem> {
        let raw = std::fs::read(self.path("/proc/meminfo")).ok()?;
        let text = String::from_utf8_lossy(&raw);
        let mut kv: HashMap<&str, i64> = HashMap::new();
        for line in text.lines() {
            let Some((name, rest)) = line.split_once(':') else {
                continue;
            };
            let Some(first) = rest.split_whitespace().next() else {
                continue;
            };
            if let Ok(v) = first.parse::<i64>() {
                kv.insert(name, v);
            }
        }
        let get = |k: &str| kv.get(k).copied().unwrap_or(0);
        let total = get("MemTotal");
        if total <= 0 {
            return None;
        }
        // MemAvailable exists since Linux 3.14; estimate it on older kernels.
        let available = match kv.get("MemAvailable") {
            Some(&v) => v,
            None => get("MemFree")
                .wrapping_add(get("Buffers"))
                .wrapping_add(get("Cached")),
        };
        let used = total.wrapping_sub(available).max(0);
        let swap_used = get("SwapTotal").wrapping_sub(get("SwapFree")).max(0);
        Some(Mem {
            total_kib: total,
            available_kib: available,
            used_kib: used,
            percent: clamp(100.0 * used as f64 / total as f64),
            swap_total_kib: get("SwapTotal"),
            swap_used_kib: swap_used,
        })
    }

    /// The CPU share of each task between this tick and the last, which is
    /// what `top` prints, without forking anything. Only /proc/<pid>/stat is
    /// read for every task; the owner and the command line are read for the
    /// rows actually shown.
    fn processes(&mut self, limit: usize, now: Instant) -> Vec<Process> {
        let Some(names) = read_dir_sorted(&self.path("/proc")) else {
            return Vec::new();
        };
        let mut cur = std::mem::take(&mut self.spare_proc);
        cur.clear();
        let mem_total = self.mem().map(|m| m.total_kib as f64).unwrap_or(0.0);
        let hz = 100.0; // USER_HZ, which /proc/<pid>/stat counts in.
        let elapsed = self
            .prev_proc_at
            .map(|at| now.saturating_duration_since(at).as_secs_f64());

        let mut out = Vec::new();
        for name in &names {
            let Some(pid) = go_atoi(name) else {
                continue;
            };
            let Some(pt) = self.read_proc_stat(pid) else {
                continue;
            };
            let prev = self.prev_proc.get(&pid).map(|p| p.jiffies);
            let jiffies = pt.jiffies;
            let command = pt.command.clone();
            let rss = pt.rss_kib;
            cur.insert(pid, pt);
            let (Some(prev), Some(elapsed)) = (prev, elapsed) else {
                continue;
            };
            if elapsed <= 0.0 {
                continue;
            }
            let delta = jiffies.wrapping_sub(prev) as f64 / hz;
            if delta < 0.0 {
                continue;
            }
            let mem = if mem_total > 0.0 {
                100.0 * rss as f64 / mem_total
            } else {
                0.0
            };
            out.push(Process {
                pid,
                user: String::new(),
                cpu: 100.0 * delta / elapsed,
                mem,
                command,
            });
        }
        self.spare_proc = std::mem::replace(&mut self.prev_proc, cur);
        self.prev_proc_at = Some(now);

        out.sort_by(|a, b| {
            if a.cpu != b.cpu {
                b.cpu
                    .partial_cmp(&a.cpu)
                    .unwrap_or(std::cmp::Ordering::Equal)
            } else {
                b.mem
                    .partial_cmp(&a.mem)
                    .unwrap_or(std::cmp::Ordering::Equal)
            }
        });
        if limit > 0 && out.len() > limit {
            out.truncate(limit);
        }
        for p in &mut out {
            let dir = self.path(&format!("/proc/{}", p.pid));
            p.user = self.proc_user(&dir);
            if let Some(cmdline) = command_line(&dir) {
                p.command = cmdline;
            }
        }
        out
    }

    /// The one file per task this sampler reads every tick.
    fn read_proc_stat(&self, pid: i64) -> Option<ProcTimes> {
        let raw = std::fs::read(self.path(&format!("/proc/{pid}/stat"))).ok()?;
        // comm is parenthesised and may hold spaces, so split after the last ')'.
        let open = raw.iter().position(|&b| b == b'(')?;
        let close = raw.iter().rposition(|&b| b == b')')?;
        if close < open {
            return None;
        }
        let tail = String::from_utf8_lossy(&raw[close + 1..]);
        let fields: Vec<&str> = tail.split_whitespace().collect();
        if fields.len() < 22 {
            return None;
        }
        // After the state field: utime is index 11, stime 12, rss (pages) 21.
        let num = |i: usize| fields[i].parse::<i64>().unwrap_or(0);
        Some(ProcTimes {
            jiffies: num(11).wrapping_add(num(12)),
            command: go_lossy(&raw[open + 1..close]),
            rss_kib: num(21).wrapping_mul(self.page_size) / 1024,
        })
    }

    fn proc_user(&mut self, dir: &Path) -> String {
        let Ok(raw) = std::fs::read(dir.join("status")) else {
            return String::new();
        };
        let text = go_lossy(&raw);
        for line in text.split('\n') {
            if let Some(rest) = line.strip_prefix("Uid:") {
                if let Some(uid) = rest.split_whitespace().next() {
                    return self.user_name(uid);
                }
            }
        }
        String::new()
    }

    /// A uid's login name from /etc/passwd (the live one, never under the
    /// root: os/user's cgo would have read it for the Go daemon too).
    fn user_name(&mut self, uid: &str) -> String {
        if let Some(name) = self.users.get(uid) {
            return name.clone();
        }
        let mut name = uid.to_string();
        if let Ok(raw) = std::fs::read("/etc/passwd") {
            for line in go_lossy(&raw).split('\n') {
                let fields: Vec<&str> = line.split(':').collect();
                if fields.len() > 2 && fields[2] == uid {
                    name = fields[0].to_string();
                    break;
                }
            }
        }
        self.users.insert(uid.to_string(), name.clone());
        name
    }
}

/// The command line, friendlier than comm when it is readable (a kernel
/// thread has none, and hidepid may hide another user's).
fn command_line(dir: &Path) -> Option<String> {
    let raw = std::fs::read(dir.join("cmdline")).ok()?;
    if raw.is_empty() {
        return None;
    }
    let end = raw.iter().rposition(|&b| b != 0).map_or(0, |i| i + 1);
    let trimmed = &raw[..end];
    if trimmed.first().is_none_or(|&b| b == 0) {
        return None;
    }
    let joined: Vec<u8> = trimmed
        .iter()
        .map(|&b| if b == 0 { b' ' } else { b })
        .collect();
    Some(go_lossy(&joined))
}

/// Go's strconv.Atoi: an optional sign and decimal digits, within int64.
fn go_atoi(name: &[u8]) -> Option<i64> {
    std::str::from_utf8(name).ok()?.parse().ok()
}

/// A directory's entry names in byte order, as Go's os.ReadDir returns them.
pub(crate) fn read_dir_sorted(dir: &Path) -> Option<Vec<Vec<u8>>> {
    use std::os::unix::ffi::OsStringExt;
    let mut names: Vec<Vec<u8>> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().into_vec())
        .collect();
    names.sort();
    Some(names)
}

/// 0..100; NaN stays NaN, as the Go daemon's comparisons left it.
pub(crate) fn clamp(v: f64) -> f64 {
    v.clamp(0.0, 100.0)
}

impl Sample {
    /// The event's data as Go's encoder wrote it, or None when a value cannot
    /// be encoded (a NaN), which closed the Go daemon's connections too.
    pub fn encode(&self, out: &mut Vec<u8>) -> bool {
        let mut o = Obj::new(out);
        o.float("cpu", self.cpu);
        match &self.mem {
            None => {
                o.null("mem");
            }
            Some(m) => {
                o.raw("mem", |out| {
                    let mut o = Obj::new(out);
                    o.int("totalKiB", m.total_kib)
                        .int("availableKiB", m.available_kib)
                        .int("usedKiB", m.used_kib)
                        .float("percent", m.percent)
                        .int("swapTotalKiB", m.swap_total_kib)
                        .int("swapUsedKiB", m.swap_used_kib);
                    o.end()
                });
            }
        }
        o.float("gpu", self.gpu);
        match &self.gpus {
            None => {
                o.null("gpus");
            }
            Some(list) => {
                o.raw("gpus", |out| {
                    out.push(b'[');
                    for (i, g) in list.iter().enumerate() {
                        if i > 0 {
                            out.push(b',');
                        }
                        g.encode(out);
                    }
                    out.push(b']');
                    true
                });
            }
        }
        match &self.gpu_info {
            None => {
                o.null("gpuInfo");
            }
            Some(g) => {
                o.raw("gpuInfo", |out| {
                    g.encode(out);
                    true
                });
            }
        }
        o.raw("processes", |out| {
            let mut ok = true;
            out.push(b'[');
            for (i, p) in self.processes.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                let mut o = Obj::new(out);
                o.int("pid", p.pid)
                    .str("user", &p.user)
                    .float("cpu", p.cpu)
                    .float("mem", p.mem)
                    .str("command", &p.command);
                ok &= o.end();
            }
            out.push(b']');
            ok
        });
        if let Some(s) = &self.system {
            o.float("cpuTempC", s.cpu_temp_c)
                .float("cpuFreqMHz", s.cpu_freq_mhz);
            o.raw("net", |out| {
                let mut o = Obj::new(out);
                o.float("rxBps", s.net.rx_bps).float("txBps", s.net.tx_bps);
                o.end()
            });
            o.raw("disks", |out| {
                let mut ok = true;
                out.push(b'[');
                for (i, d) in s.disks.iter().enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    let mut o = Obj::new(out);
                    o.str("mount", &d.mount)
                        .str("device", &d.device)
                        .str("fstype", &d.fstype)
                        .int("totalKiB", d.total_kib)
                        .int("usedKiB", d.used_kib)
                        .int("availKiB", d.avail_kib)
                        .float("percent", d.percent);
                    ok &= o.end();
                }
                out.push(b']');
                ok
            });
        }
        o.end()
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::fs;

    /// A temporary directory removed on drop, like Go's t.TempDir.
    pub struct TempDir(pub PathBuf);

    impl TempDir {
        pub fn new() -> Self {
            use std::sync::atomic::{AtomicUsize, Ordering};
            static N: AtomicUsize = AtomicUsize::new(0);
            let base = std::env::var_os("TMPDIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/tmp"));
            let dir = base.join(format!(
                "hs-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::SeqCst)
            ));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(&dir).unwrap();
            TempDir(dir)
        }

        pub fn bytes(&self) -> Vec<u8> {
            use std::os::unix::ffi::OsStrExt;
            self.0.as_os_str().as_bytes().to_vec()
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    pub fn write(path: &Path, content: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    // Busy share is (dtotal - didle) / dtotal, and idle counts iowait: a CPU
    // waiting on I/O is not busy.
    #[test]
    fn cpu_percent() {
        let root = TempDir::new();
        let mut s = Sampler::new(&root.bytes());
        let stat = root.0.join("proc/stat");

        write(&stat, "cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 1 2 3 4\n");
        assert_eq!(
            s.cpu_percent(),
            -1.0,
            "first sample: nothing to compare with"
        );
        write(&stat, "cpu  150 0 150 800 100 0 0 0 0 0\n");
        assert_eq!(s.cpu_percent(), 50.0);
        // A counter that went backwards (a reset) is unknown, not negative.
        write(&stat, "cpu  100 0 100 700 100 0 0 0 0 0\n");
        assert_eq!(s.cpu_percent(), -1.0);
    }

    #[test]
    fn cpu_percent_garbage() {
        let root = TempDir::new();
        write(&root.0.join("proc/stat"), "intr 1 2 3\n");
        assert_eq!(Sampler::new(&root.bytes()).cpu_percent(), -1.0);
    }

    // Used is MemTotal - MemAvailable, which is what free(1) prints as used.
    #[test]
    fn mem() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/meminfo"),
            "MemTotal:       32554964 kB\nMemFree:  1 kB\nMemAvailable:   18094064 kB\n\
             SwapCached: 0 kB\nSwapTotal:      1000 kB\nSwapFree:       250 kB\n",
        );
        let m = Sampler::new(&root.bytes()).mem().expect("mem");
        assert_eq!(m.used_kib, 14460900);
        assert_eq!((m.percent * 100.0 + 0.5).trunc() / 100.0, 44.42);
        assert_eq!(m.swap_used_kib, 750);
    }

    // MemAvailable only exists since Linux 3.14.
    #[test]
    fn mem_fallback() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/meminfo"),
            "MemTotal: 100 kB\nMemFree: 50 kB\nBuffers: 10 kB\nCached: 10 kB\n",
        );
        assert_eq!(
            Sampler::new(&root.bytes()).mem().map(|m| m.percent),
            Some(30.0)
        );
    }

    #[test]
    fn mem_garbage() {
        let root = TempDir::new();
        write(&root.0.join("proc/meminfo"), "");
        assert_eq!(Sampler::new(&root.bytes()).mem(), None);
    }

    fn proc(root: &Path, pid: i64, jiffies: i64, comm: &str) {
        let dir = root.join(format!("proc/{pid}"));
        let fields = format!("R 1 1 1 0 -1 0 0 0 0 0 {jiffies} 0 0 0 20 0 1 0 0 0 1");
        write(&dir.join("stat"), &format!("{pid} ({comm}) {fields}\n"));
        write(
            &dir.join("status"),
            &format!("Name:\t{comm}\nUid:\t1000\t1000\t1000\t1000\n"),
        );
    }

    // The process list is the CPU share between two ticks, highest first.
    #[test]
    fn processes() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/meminfo"),
            "MemTotal: 1000 kB\nMemAvailable: 500 kB\n",
        );
        proc(&root.0, 10, 100, "quiet");
        proc(&root.0, 11, 100, "busy");

        let mut s = Sampler::new(&root.bytes());
        let t0 = Instant::now();
        assert!(
            s.processes(8, t0).is_empty(),
            "first tick: no previous sample"
        );
        proc(&root.0, 10, 110, "quiet");
        proc(&root.0, 11, 400, "busy");
        let got = s.processes(8, t0 + std::time::Duration::from_secs(3));
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].command, "busy");
        assert!(got[0].cpu > got[1].cpu, "sorted by cpu: {got:?}");
        assert_eq!(got[0].pid, 11);
        assert_eq!(got[0].cpu, 100.0, "300 jiffies over 3 s");

        // A comm with spaces and parentheses still parses: the fields after
        // it are taken from the last ')', not the first space.
        proc(&root.0, 12, 100, "Web (Content)");
        let mut s2 = Sampler::new(&root.bytes());
        s2.processes(8, t0);
        proc(&root.0, 12, 200, "Web (Content)");
        let found = s2.processes(8, t0 + std::time::Duration::from_secs(1));
        assert!(
            found
                .iter()
                .any(|p| p.pid == 12 && p.command == "Web (Content)"),
            "{found:?}"
        );
    }

    #[test]
    fn process_limit() {
        let root = TempDir::new();
        write(&root.0.join("proc/meminfo"), "MemTotal: 1000 kB\n");
        for pid in 10..30 {
            let dir = root.0.join(format!("proc/{pid}"));
            write(
                &dir.join("stat"),
                &format!("{pid} (p) R 1 1 1 0 -1 0 0 0 0 0 1 0 0 0 20 0 1 0 0 0 1\n"),
            );
            write(&dir.join("status"), "Uid:\t1000\t1000\t1000\t1000\n");
        }
        let mut s = Sampler::new(&root.bytes());
        let t0 = Instant::now();
        s.processes(8, t0);
        for pid in 10..30 {
            let dir = root.0.join(format!("proc/{pid}"));
            write(
                &dir.join("stat"),
                &format!("{pid} (p) R 1 1 1 0 -1 0 0 0 0 0 9 0 0 0 20 0 1 0 0 0 1\n"),
            );
        }
        assert_eq!(
            s.processes(8, t0 + std::time::Duration::from_secs(1)).len(),
            8
        );
    }

    #[test]
    fn command_line_reads_nuls_as_spaces() {
        let root = TempDir::new();
        let dir = root.0.join("p");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("cmdline"), b"/usr/bin/foot\0--server\0\0").unwrap();
        assert_eq!(
            command_line(&dir).as_deref(),
            Some("/usr/bin/foot --server")
        );
        fs::write(dir.join("cmdline"), b"\0x\0").unwrap();
        assert_eq!(command_line(&dir), None);
        fs::write(dir.join("cmdline"), b"").unwrap();
        assert_eq!(command_line(&dir), None);
    }

    #[test]
    fn an_empty_root_is_unknown_everywhere() {
        let root = TempDir::new();
        let mut s = Sampler::new(&root.bytes());
        let mut out = Vec::new();
        assert!(s.sample("auto", true, false).encode(&mut out));
        assert_eq!(
            String::from_utf8(out).unwrap(),
            r#"{"cpu":-1,"mem":null,"gpu":-1,"gpus":null,"gpuInfo":null,"processes":[]}"#
        );
    }
}
