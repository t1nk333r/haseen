//! What DankMaterialShell desktop plugins (dms-conky) read from DMS's
//! DgopService, and the Your computer panel shows: CPU temperature and clock,
//! network throughput and the mounted disks. Sampled only when a subscriber
//! asks for `system`.

use super::gpu::{read_text, readable};
use super::{clamp, read_dir_sorted, Sampler};
use crate::json::go_lossy;
use std::collections::HashMap;
use std::io::Read;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Clone, Debug, PartialEq)]
pub struct System {
    /// -1 = unknown.
    pub cpu_temp_c: f64,
    /// Mean over online CPUs; -1 = unknown.
    pub cpu_freq_mhz: f64,
    pub net: NetRate,
    pub disks: Vec<Disk>,
}

/// Bytes per second since the previous system sample, summed over every
/// interface but lo; both -1 when there is no previous sample.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NetRate {
    pub rx_bps: f64,
    pub tx_bps: f64,
}

/// One block-device filesystem. Sizes follow df: percent is
/// used / (used + avail), so blocks reserved for root do not count as free.
#[derive(Clone, Debug, PartialEq)]
pub struct Disk {
    pub mount: String,
    pub device: String,
    pub fstype: String,
    pub total_kib: i64,
    pub used_kib: i64,
    pub avail_kib: i64,
    pub percent: f64,
}

/// A stand-in for statfs(2), for fixture trees.
pub type StatFsFn = Box<dyn Fn(&Path) -> Option<StatFs> + Send>;

/// The statfs(2) fields the disk sizes use.
#[derive(Clone, Copy, Debug, Default)]
pub struct StatFs {
    pub bsize: i64,
    pub frsize: i64,
    pub blocks: u64,
    pub bfree: u64,
    pub bavail: u64,
}

#[derive(Default)]
pub(super) struct SysState {
    temp_probed: bool,
    temp_path: Option<PathBuf>,
    freq_probed: bool,
    freq_paths: Vec<PathBuf>,
    /// Per interface, so an interface that goes away (a VPN going down) does
    /// not make the sum drop and the rate go negative. None = no previous
    /// sample.
    pub(super) net: Option<HashMap<Vec<u8>, NetCounter>>,
    net_tick: u64,
    pub(super) net_at: Option<Instant>,
}

pub(super) struct NetCounter {
    rx: i64,
    tx: i64,
    tick: u64,
}

/// hwmon drivers that report the CPU package, most preferred first, with the
/// labels naming the package sensor. Tdie comes before Tctl: on some Ryzen and
/// Threadripper parts Tctl carries a fan-control offset of up to 27 °C.
const CPU_SENSORS: [(&str, &[&str]); 3] = [
    ("coretemp", &["Package id 0"]),
    ("k10temp", &["Tdie", "Tctl"]),
    ("zenpower", &["Tdie", "Tctl"]),
];

/// Filesystems on a block device that are not a disk worth a row: read-only
/// images, always 100 % full. A denylist: the /dev/ source test already drops
/// every pseudo filesystem.
const IMAGE_FS: [&[u8]; 3] = [b"squashfs", b"erofs", b"iso9660"];

/// Block devices that are not disks: loop images and RAM disks (zram too).
const NOT_DISKS: [&[u8]; 3] = [b"/dev/loop", b"/dev/ram", b"/dev/zram"];

fn concat(dir: &Path, rest: &[u8]) -> PathBuf {
    let mut p = dir.as_os_str().as_bytes().to_vec();
    p.extend_from_slice(rest);
    PathBuf::from(std::ffi::OsStr::from_bytes(&p))
}

impl Sampler {
    pub(super) fn system(&mut self, now: Instant) -> System {
        System {
            cpu_temp_c: self.cpu_temp(),
            cpu_freq_mhz: self.cpu_freq(),
            net: self.net_rate(now),
            disks: self.disks(),
        }
    }

    /// The CPU package temperature in °C; -1 when there is no sensor. Looked
    /// up once and again only when it stops answering.
    fn cpu_temp(&mut self) -> f64 {
        if !self.sys.temp_probed {
            self.sys.temp_probed = true;
            self.sys.temp_path = self.probe_temp();
        }
        let Some(path) = &self.sys.temp_path else {
            return -1.0;
        };
        match read_int(path) {
            Some(v) => v as f64 / 1000.0,
            None => {
                // hwmonN numbers are not stable across a driver reload.
                self.sys.temp_probed = false;
                -1.0
            }
        }
    }

    /// The input node of the best CPU package sensor: a package hwmon sensor
    /// first, then the x86_pkg_temp thermal zone.
    fn probe_temp(&self) -> Option<PathBuf> {
        let hwmons = read_dir_sorted(&self.path("/sys/class/hwmon")).unwrap_or_default();
        for (driver, labels) in CPU_SENSORS {
            for entry in &hwmons {
                let dir = crate::gocompat::join(
                    &self.root,
                    &[b"/sys/class/hwmon/".as_slice(), entry].concat(),
                );
                if read_text(&concat(&dir, b"/name")).trim() != driver {
                    continue;
                }
                if let Some(input) = hwmon_input(&dir, labels) {
                    return Some(input);
                }
            }
        }
        let zones = read_dir_sorted(&self.path("/sys/class/thermal")).unwrap_or_default();
        for entry in &zones {
            if !entry.starts_with(b"thermal_zone") {
                continue;
            }
            let dir = crate::gocompat::join(
                &self.root,
                &[b"/sys/class/thermal/".as_slice(), entry].concat(),
            );
            if read_text(&concat(&dir, b"/type")).trim() == "x86_pkg_temp" {
                return Some(concat(&dir, b"/temp"));
            }
        }
        None
    }

    /// The mean current clock over online CPUs in MHz, from cpufreq, else
    /// from /proc/cpuinfo (a VM without cpufreq), else -1.
    fn cpu_freq(&mut self) -> f64 {
        if !self.sys.freq_probed {
            self.sys.freq_probed = true;
            self.sys.freq_paths = self.probe_freq();
        }
        let mut sum: i64 = 0;
        let mut n = 0;
        for p in &self.sys.freq_paths {
            // An offline CPU's policy answers EBUSY, which leaves it out.
            if let Some(v) = read_int(p) {
                if v > 0 {
                    sum = sum.wrapping_add(v);
                    n += 1;
                }
            }
        }
        if n > 0 {
            return sum as f64 / n as f64 / 1000.0; // kHz
        }
        self.cpuinfo_mhz()
    }

    fn probe_freq(&self) -> Vec<PathBuf> {
        let Some(entries) = read_dir_sorted(&self.path("/sys/devices/system/cpu")) else {
            return Vec::new();
        };
        let mut paths = Vec::new();
        for entry in entries {
            let Some(num) = entry.strip_prefix(b"cpu") else {
                continue;
            };
            if num.is_empty() || !num.iter().all(u8::is_ascii_digit) {
                continue;
            }
            let rel = [
                b"/sys/devices/system/cpu/".as_slice(),
                &entry,
                b"/cpufreq/scaling_cur_freq",
            ]
            .concat();
            let p = crate::gocompat::join(&self.root, &rel);
            if std::fs::metadata(&p).is_ok() {
                paths.push(p);
            }
        }
        paths
    }

    fn cpuinfo_mhz(&self) -> f64 {
        let Ok(raw) = std::fs::read(self.path("/proc/cpuinfo")) else {
            return -1.0;
        };
        let mut sum = 0.0;
        let mut n = 0;
        for line in raw.split(|&b| b == b'\n') {
            if !line.starts_with(b"cpu MHz") {
                continue;
            }
            let Some(colon) = line.iter().position(|&b| b == b':') else {
                continue;
            };
            let value = String::from_utf8_lossy(&line[colon + 1..]);
            if let Ok(v) = value.trim().parse::<f64>() {
                if v > 0.0 {
                    sum += v;
                    n += 1;
                }
            }
        }
        if n == 0 {
            return -1.0;
        }
        sum / n as f64
    }

    /// The byte counters of /proc/net/dev as a rate since the previous call. A
    /// counter that went backwards (a driver reload) or an interface that just
    /// appeared contributes nothing this tick rather than a spike or a
    /// negative rate.
    fn net_rate(&mut self, now: Instant) -> NetRate {
        let unknown = NetRate {
            rx_bps: -1.0,
            tx_bps: -1.0,
        };
        let Ok(raw) = std::fs::read(self.path("/proc/net/dev")) else {
            self.sys.net = None;
            return unknown;
        };
        let had = self.sys.net.is_some();
        let prev_tick = self.sys.net_tick;
        self.sys.net_tick = self.sys.net_tick.wrapping_add(1);
        let tick = self.sys.net_tick;
        let counters = self.sys.net.get_or_insert_with(HashMap::new);

        let (mut rx_sum, mut tx_sum) = (0i64, 0i64);
        for line in raw.split(|&b| b == b'\n') {
            let Some(colon) = line.iter().position(|&b| b == b':') else {
                continue; // the two header lines
            };
            let name = line[..colon].trim_ascii();
            if name == b"lo" {
                continue;
            }
            let Some((rx, tx)) = net_bytes(&line[colon + 1..]) else {
                continue;
            };
            match counters.get_mut(name) {
                None => {
                    counters.insert(name.to_vec(), NetCounter { rx, tx, tick });
                }
                Some(c) => {
                    if c.tick == prev_tick {
                        rx_sum = rx_sum.wrapping_add(rx.wrapping_sub(c.rx).max(0));
                        tx_sum = tx_sum.wrapping_add(tx.wrapping_sub(c.tx).max(0));
                    }
                    c.rx = rx;
                    c.tx = tx;
                    c.tick = tick;
                }
            }
        }
        counters.retain(|_, c| c.tick == tick);

        let elapsed = self
            .sys
            .net_at
            .map(|at| now.saturating_duration_since(at).as_secs_f64());
        self.sys.net_at = Some(now);
        match elapsed {
            Some(e) if had && e > 0.0 => NetRate {
                rx_bps: rx_sum as f64 / e,
                tx_bps: tx_sum as f64 / e,
            },
            _ => unknown,
        }
    }

    /// The block-device filesystems of /proc/self/mounts, one per device:
    /// btrfs mounts one device at every subvolume's mountpoint, and the
    /// shortest path is the one a person recognises (/ rather than /var/log).
    fn disks(&self) -> Vec<Disk> {
        // (device, mount point) as bytes: Go compared and opened the raw
        // strings, and only its encoder replaced invalid UTF-8.
        let mut out: Vec<(Vec<u8>, Vec<u8>, Vec<u8>)> = Vec::new();
        let Ok(raw) = std::fs::read(self.path("/proc/self/mounts")) else {
            return Vec::new();
        };
        for line in raw.split(|&b| b == b'\n') {
            if !line.starts_with(b"/dev/") {
                continue;
            }
            let (device, rest) = next_field(line);
            let (mount, rest) = next_field(rest);
            let (fstype, _) = next_field(rest);
            let (Some(device), Some(mount), Some(fstype)) = (device, mount, fstype) else {
                continue;
            };
            if IMAGE_FS.contains(&fstype) || NOT_DISKS.iter().any(|p| device.starts_with(p)) {
                continue;
            }
            let mount = unescape_mount(mount);
            match out.iter_mut().find(|(dev, _, _)| dev.as_slice() == device) {
                None => out.push((device.to_vec(), mount, fstype.to_vec())),
                Some((_, kept, _)) => {
                    if mount.len() < kept.len() || (mount.len() == kept.len() && mount < *kept) {
                        *kept = mount;
                    }
                }
            }
        }

        let mut kept: Vec<(Vec<u8>, Disk)> = Vec::new();
        for (device, mount, fstype) in out {
            let path = crate::gocompat::join(&self.root, &mount);
            let st = match &self.statfs {
                Some(fake) => fake(&path),
                None => statfs(&path),
            };
            let Some(st) = st else {
                continue;
            };
            let bs = if st.frsize > 0 { st.frsize } else { st.bsize };
            let total_kib = (st.blocks as i64).wrapping_mul(bs) / 1024;
            let avail_kib = (st.bavail as i64).wrapping_mul(bs) / 1024;
            let used_kib = (st.blocks.wrapping_sub(st.bfree) as i64).wrapping_mul(bs) / 1024;
            if total_kib <= 0 {
                continue;
            }
            let mut percent = 0.0;
            if used_kib.wrapping_add(avail_kib) > 0 {
                percent = clamp(100.0 * used_kib as f64 / used_kib.wrapping_add(avail_kib) as f64);
            }
            let disk = Disk {
                mount: go_lossy(&mount),
                device: go_lossy(&device),
                fstype: go_lossy(&fstype),
                total_kib,
                used_kib,
                avail_kib,
                percent,
            };
            kept.push((mount, disk));
        }
        kept.sort_by(|a, b| a.0.cmp(&b.0));
        kept.into_iter().map(|(_, d)| d).collect()
    }
}

/// statfs(2) on a path.
fn statfs(path: &Path) -> Option<StatFs> {
    let c = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    // SAFETY: c is a valid C string and st a properly sized out-parameter.
    unsafe {
        let mut st: libc::statfs = std::mem::zeroed();
        if libc::statfs(c.as_ptr(), &mut st) != 0 {
            return None;
        }
        Some(StatFs {
            bsize: st.f_bsize as i64,
            frsize: st.f_frsize as i64,
            blocks: st.f_blocks as u64,
            bfree: st.f_bfree as u64,
            bavail: st.f_bavail as u64,
        })
    }
}

/// tempN_input for the first label that matches. A driver that labels nothing
/// (k10temp before Linux 4.15) has its package sensor as temp1.
fn hwmon_input(dir: &Path, labels: &[&str]) -> Option<PathBuf> {
    let entries = read_dir_sorted(dir)?;
    let mut labelled = false;
    for want in labels {
        for name in &entries {
            let Some(base) = name.strip_suffix(b"_label") else {
                continue;
            };
            if !name.starts_with(b"temp") {
                continue;
            }
            labelled = true;
            let label = concat(dir, &[b"/".as_slice(), name].concat());
            if read_text(&label).trim() == *want {
                return Some(concat(dir, &[b"/".as_slice(), base, b"_input"].concat()));
            }
        }
    }
    let temp1 = concat(dir, b"/temp1_input");
    (!labelled && readable(&temp1)).then_some(temp1)
}

/// The fields after "iface:" in /proc/net/dev: receive bytes is the first,
/// transmit bytes the ninth.
fn net_bytes(mut fields: &[u8]) -> Option<(i64, i64)> {
    let mut rx = None;
    for i in 0.. {
        let (field, rest) = next_field(fields);
        let field = field?;
        fields = rest;
        match i {
            0 => rx = parse_int(field),
            8 => return Some((rx?, parse_int(field)?)),
            _ => {}
        }
    }
    None
}

/// Undoes the octal escapes /proc/self/mounts uses for space, tab, newline and
/// backslash (`/media/My\040Disk`).
fn unescape_mount(b: &[u8]) -> Vec<u8> {
    let octal = |c: u8| (b'0'..=b'7').contains(&c);
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() && octal(b[i + 1]) && octal(b[i + 2]) && octal(b[i + 3])
        {
            out.push(((b[i + 1] - b'0') << 6) | ((b[i + 2] - b'0') << 3) | (b[i + 3] - b'0'));
            i += 4;
            continue;
        }
        out.push(b[i]);
        i += 1;
    }
    out
}

/// A node holding one integer: one read of up to 32 bytes.
fn read_int(path: &Path) -> Option<i64> {
    let mut f = std::fs::File::open(path).ok()?;
    let mut buf = [0u8; 32];
    let n = f.read(&mut buf).unwrap_or(0);
    if n == 0 {
        return None;
    }
    parse_int(buf[..n].trim_ascii())
}

/// Decimal digits with an optional '-', wrapping on overflow like the Go
/// daemon's hand-written parser.
fn parse_int(b: &[u8]) -> Option<i64> {
    let (neg, digits) = match b.first() {
        Some(b'-') => (true, &b[1..]),
        _ => (false, b),
    };
    if digits.is_empty() {
        return None;
    }
    let mut v: i64 = 0;
    for &c in digits {
        if !c.is_ascii_digit() {
            return None;
        }
        v = v.wrapping_mul(10).wrapping_add((c - b'0') as i64);
    }
    Some(if neg { v.wrapping_neg() } else { v })
}

/// The next field separated by spaces or tabs, and the rest.
fn next_field(b: &[u8]) -> (Option<&[u8]>, &[u8]) {
    let mut i = 0;
    while i < b.len() && (b[i] == b' ' || b[i] == b'\t') {
        i += 1;
    }
    let mut j = i;
    while j < b.len() && b[j] != b' ' && b[j] != b'\t' {
        j += 1;
    }
    if i == j {
        return (None, &[]);
    }
    (Some(&b[i..j]), &b[j..])
}

#[cfg(test)]
mod tests {
    use super::super::tests::{write, TempDir};
    use super::*;
    use std::time::Duration;

    /// One fixture hwmon device with labelled inputs: (label, millidegrees).
    fn hwmon(root: &Path, dir: &str, name: &str, sensors: &[(&str, &str)]) {
        let base = root.join("sys/class/hwmon").join(dir);
        write(&base.join("name"), &format!("{name}\n"));
        for (i, (label, milli)) in sensors.iter().enumerate() {
            write(
                &base.join(format!("temp{}_label", i + 1)),
                &format!("{label}\n"),
            );
            write(
                &base.join(format!("temp{}_input", i + 1)),
                &format!("{milli}\n"),
            );
        }
    }

    fn zone(root: &Path, dir: &str, kind: &str, milli: &str) {
        let base = root.join("sys/class/thermal").join(dir);
        write(&base.join("type"), &format!("{kind}\n"));
        write(&base.join("temp"), &format!("{milli}\n"));
    }

    // The package sensor wins: coretemp, then k10temp (Tdie before Tctl),
    // then the x86_pkg_temp thermal zone; ACPI zones and NVMe never.
    #[test]
    fn cpu_temp_precedence() {
        let root = TempDir::new();
        let r = &root.0;
        assert_eq!(Sampler::new(&root.bytes()).cpu_temp(), -1.0);

        hwmon(r, "hwmon0", "acpitz", &[("", "99000")]);
        hwmon(r, "hwmon1", "nvme", &[("Composite", "38000")]);
        zone(r, "thermal_zone0", "acpitz", "98000");
        zone(r, "thermal_zone1", "x86_pkg_temp", "51000");
        assert_eq!(Sampler::new(&root.bytes()).cpu_temp(), 51.0);

        hwmon(
            r,
            "hwmon2",
            "k10temp",
            &[("Tctl", "70500"), ("Tdie", "43500"), ("Tccd1", "40000")],
        );
        assert_eq!(Sampler::new(&root.bytes()).cpu_temp(), 43.5);

        hwmon(
            r,
            "hwmon3",
            "coretemp",
            &[("Core 0", "60000"), ("Package id 0", "62000")],
        );
        let mut s = Sampler::new(&root.bytes());
        assert_eq!(s.cpu_temp(), 62.0);

        // A sensor that disappears is unknown for one tick and looked up
        // again on the next.
        std::fs::remove_dir_all(r.join("sys/class/hwmon/hwmon3")).unwrap();
        assert_eq!(s.cpu_temp(), -1.0);
        assert_eq!(s.cpu_temp(), 43.5);
    }

    // k10temp before Linux 4.15 labels nothing; its temp1 is the package.
    #[test]
    fn cpu_temp_unlabelled() {
        let root = TempDir::new();
        write(&root.0.join("sys/class/hwmon/hwmon0/name"), "k10temp\n");
        write(
            &root.0.join("sys/class/hwmon/hwmon0/temp1_input"),
            "45250\n",
        );
        assert_eq!(Sampler::new(&root.bytes()).cpu_temp(), 45.25);
    }

    #[test]
    fn cpu_freq() {
        let root = TempDir::new();
        let cpu = root.0.join("sys/devices/system/cpu");
        write(&cpu.join("cpu0/cpufreq/scaling_cur_freq"), "2000000\n");
        write(&cpu.join("cpu1/cpufreq/scaling_cur_freq"), "3000000\n");
        // No cpufreq for this one, and the policy directory is not a CPU.
        std::fs::create_dir_all(cpu.join("cpu2")).unwrap();
        write(&cpu.join("cpufreq/policy0/scaling_cur_freq"), "9000000\n");
        write(&root.0.join("proc/cpuinfo"), "cpu MHz\t\t: 100.0\n");
        assert_eq!(Sampler::new(&root.bytes()).cpu_freq(), 2500.0);
    }

    // Without cpufreq (a VM), /proc/cpuinfo's per-CPU "cpu MHz" is the source.
    #[test]
    fn cpu_freq_fallback() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/cpuinfo"),
            "processor\t: 0\ncpu MHz\t\t: 1000.500\n\nprocessor\t: 1\ncpu MHz\t\t: 3000.500\n",
        );
        assert_eq!(Sampler::new(&root.bytes()).cpu_freq(), 2000.5);
        assert_eq!(Sampler::new(&TempDir::new().bytes()).cpu_freq(), -1.0);
    }

    const NET_HEADER: &str = "Inter-|   Receive                                                |  Transmit\n \
        face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n";

    fn net_line(name: &str, rx: i64, tx: i64) -> String {
        format!("  {name}: {rx} 10 0 0 0 0 0 0 {tx} 10 0 0 0 0 0 0\n")
    }

    // Rates are per second over the wall time between system samples, lo is
    // not traffic, and an interface that comes or goes moves nothing.
    #[test]
    fn net_rate() {
        let root = TempDir::new();
        let dev = root.0.join("proc/net/dev");
        let mut s = Sampler::new(&root.bytes());
        let t0 = Instant::now();

        write(
            &dev,
            &(NET_HEADER.to_string()
                + &net_line("lo", 5000, 5000)
                + &net_line("wlan0", 1000, 100)
                + &net_line("eth0", 7000, 700)),
        );
        assert_eq!(
            s.net_rate(t0),
            NetRate {
                rx_bps: -1.0,
                tx_bps: -1.0
            }
        );

        write(
            &dev,
            &(NET_HEADER.to_string()
                + &net_line("lo", 900000, 900000)
                + &net_line("wlan0", 5000, 1100)
                + &net_line("tun0", 99999, 99999)),
        );
        let got = s.net_rate(t0 + Duration::from_secs(2));
        // 4000 B and 1000 B over 2 s.
        assert_eq!(
            got,
            NetRate {
                rx_bps: 2000.0,
                tx_bps: 500.0
            }
        );
        assert!(
            !s.sys.net.as_ref().unwrap().contains_key(b"eth0".as_slice()),
            "eth0 went away and is still tracked"
        );

        // A counter that went backwards is zero, not negative.
        write(
            &dev,
            &(NET_HEADER.to_string()
                + &net_line("wlan0", 10, 10)
                + &net_line("tun0", 99999, 99999)),
        );
        assert_eq!(
            s.net_rate(t0 + Duration::from_secs(3)),
            NetRate {
                rx_bps: 0.0,
                tx_bps: 0.0
            }
        );
    }

    /// Answers for fixture mountpoints: 1000 blocks of 4 KiB, 400 free, 300
    /// of them available to users; /mnt/gone fails like an unplugged disk.
    fn fake_statfs(root: PathBuf) -> StatFsFn {
        Box::new(move |path: &Path| {
            let rel = path.strip_prefix(&root).ok()?;
            let mount = format!("/{}", rel.display());
            if mount == "/mnt/gone" {
                return None;
            }
            let mut st = StatFs {
                bsize: 4096,
                frsize: 4096,
                blocks: 1000,
                bfree: 400,
                bavail: 300,
            };
            if mount == "/mnt/empty" {
                st.blocks = 0;
            }
            Some(st)
        })
    }

    #[test]
    fn disks() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/self/mounts"),
            &([
                "proc /proc proc rw,nosuid 0 0",
                "tmpfs /run tmpfs rw 0 0",
                "/dev/mapper/root /var/log btrfs rw,subvol=/@log 0 0",
                "/dev/mapper/root / btrfs rw,subvol=/@ 0 0",
                "/dev/mapper/root /home btrfs rw,subvol=/@home 0 0",
                "/dev/nvme0n1p1 /boot vfat rw 0 0",
                "/dev/loop0 /snap/core/1 squashfs ro 0 0",
                "/dev/sr0 /run/media/cd iso9660 ro 0 0",
                "/dev/zram0 /tmp ext4 rw 0 0",
                "/dev/mapper/verity /usr erofs ro 0 0",
                r"/dev/sdb1 /media/My\040Disk fuseblk rw 0 0",
                "/dev/sdc1 /mnt/gone ext4 rw 0 0",
                "/dev/sdd1 /mnt/empty ext4 rw 0 0",
                "overlay /var/lib/docker/overlay2/x/merged overlay rw 0 0",
            ]
            .join("\n")
                + "\n"),
        );
        let mut s = Sampler::new(&root.bytes());
        s.statfs = Some(fake_statfs(root.0.clone()));
        let got = s.disks();
        let want = [
            ("/", "/dev/mapper/root", "btrfs"),
            ("/boot", "/dev/nvme0n1p1", "vfat"),
            ("/media/My Disk", "/dev/sdb1", "fuseblk"),
        ];
        assert_eq!(got.len(), want.len(), "{got:?}");
        for (d, (mount, device, fstype)) in got.iter().zip(want) {
            // df's percent: used / (used + available), reserved blocks excluded.
            let w = Disk {
                mount: mount.into(),
                device: device.into(),
                fstype: fstype.into(),
                total_kib: 4000,
                used_kib: 2400,
                avail_kib: 1200,
                percent: 100.0 * 2400.0 / 3600.0,
            };
            assert_eq!(*d, w);
        }
    }

    #[test]
    fn unescape_mount_escapes() {
        assert_eq!(unescape_mount(br"/a\040b"), b"/a b");
        assert_eq!(unescape_mount(br"/a\040"), b"/a ");
        // Not three octal digits: left as it is.
        assert_eq!(unescape_mount(br"/a\04"), br"/a\04");
        assert_eq!(unescape_mount(br"/a\\x"), br"/a\\x");
    }

    // Nobody asking for `system` leaves the payload as haseen.sysusage knew
    // it; asking adds all four fields, net starting at -1.
    #[test]
    fn system_fields_on_request() {
        let root = TempDir::new();
        write(
            &root.0.join("proc/net/dev"),
            &(NET_HEADER.to_string() + &net_line("wlan0", 1, 1)),
        );
        let mut s = Sampler::new(&root.bytes());
        s.statfs = Some(fake_statfs(root.0.clone()));
        let text = |sample: super::super::Sample| {
            let mut out = Vec::new();
            assert!(sample.encode(&mut out));
            String::from_utf8(out).unwrap()
        };

        let plain = text(s.sample("off", false, false));
        for k in ["cpuTempC", "cpuFreqMHz", "\"net\"", "disks"] {
            assert!(!plain.contains(k), "{k} present without system: {plain}");
        }
        assert!(
            plain.starts_with(r#"{"cpu":"#),
            "base payload lost: {plain}"
        );

        let full = text(s.sample("off", false, true));
        assert!(
            full.ends_with(r#","processes":[],"cpuTempC":-1,"cpuFreqMHz":-1,"net":{"rxBps":-1,"txBps":-1},"disks":[]}"#),
            "{full}"
        );

        // Dropping `system` forgets the counters: asking again starts at -1.
        s.sample("off", false, true);
        s.sample("off", false, false);
        let again = text(s.sample("off", false, true));
        assert!(
            again.contains(r#""net":{"rxBps":-1,"txBps":-1}"#),
            "{again}"
        );
    }
}
