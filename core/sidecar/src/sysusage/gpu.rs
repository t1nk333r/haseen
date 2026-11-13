//! One DRM card and how its busy share can be read without root. The shape is
//! the one haseen.sysusage's Usage.js draws from: method is busy (amdgpu
//! percent), rc6 (Intel idle residency in ms, busy = 1 - idle/wall), freq
//! (Intel clock ratio), nvidia (nvidia-smi for that PCI slot) or none. Probed
//! once per daemon and shared by every subscriber.

use super::nvidia::Nvidia;
use super::{clamp, read_dir_sorted, Sampler};
use crate::json::{go_lossy, Obj};
use std::ffi::OsString;
use std::io::Read;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Clone, Debug, PartialEq)]
pub struct Gpu {
    pub card: String,
    pub driver: String,
    pub boot_vga: bool,
    pub method: String,
    /// Paths (or the PCI slot for nvidia) as bytes: they are opened, and
    /// shown in the JSON as Go shows a string.
    pub args: Vec<Vec<u8>>,
}

impl Gpu {
    pub fn encode(&self, out: &mut Vec<u8>) {
        let args: Vec<String> = self.args.iter().map(|a| go_lossy(a)).collect();
        let mut o = Obj::new(out);
        o.str("card", &self.card)
            .str("driver", &self.driver)
            .bool("bootVga", self.boot_vga)
            .str("method", &self.method)
            .strs("args", &args);
        o.end();
    }

    fn arg(&self, i: usize) -> PathBuf {
        PathBuf::from(OsString::from_vec(self.args[i].clone()))
    }
}

#[derive(Default)]
pub(super) struct GpuState {
    probed: bool,
    cards: Option<Vec<Gpu>>,
    prev_idle_ms: f64,
    pub(super) prev_idle_at: Option<Instant>,
    nvidia: Option<Nvidia>,
}

/// `card` followed by digits: connectors (card1-eDP-1) share the directory.
fn is_card(name: &[u8]) -> bool {
    name.len() > 4 && name.starts_with(b"card") && name[4..].iter().all(u8::is_ascii_digit)
}

fn cat(dir: &[u8], rest: &str) -> Vec<u8> {
    let mut p = dir.to_vec();
    p.extend_from_slice(rest.as_bytes());
    p
}

fn path_of(bytes: &[u8]) -> &Path {
    Path::new(std::ffi::OsStr::from_bytes(bytes))
}

pub(super) fn read_text(path: &Path) -> String {
    std::fs::read(path)
        .map(|raw| go_lossy(&raw))
        .unwrap_or_default()
}

/// Opens and reads one byte, or reaches the end: a sysfs node can exist and
/// still fail to read (no permission, no device).
pub(super) fn readable(path: &Path) -> bool {
    let Ok(mut f) = std::fs::File::open(path) else {
        return false;
    };
    let mut b = [0u8; 1];
    f.read(&mut b).is_ok()
}

/// Go's exec.LookPath for a bare name: an executable regular file in an
/// absolute PATH directory (a relative one is refused, as Go refuses it).
fn on_path(name: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    let path = std::env::var_os("PATH").unwrap_or_default();
    for dir in path.as_bytes().split(|&b| b == b':') {
        if dir.first() != Some(&b'/') {
            continue;
        }
        let candidate = path_of(dir).join(name);
        if let Ok(meta) = std::fs::metadata(&candidate) {
            if meta.is_file() && meta.permissions().mode() & 0o111 != 0 {
                return true;
            }
        }
    }
    false
}

/// Usage.js pickGpu: "off" shows none, a card name that card, "auto" the boot
/// VGA device. On a hybrid laptop that is the iGPU, so auto never wakes a
/// runtime-suspended dGPU.
pub fn pick_gpu<'a>(cards: &'a [Gpu], choice: &str) -> Option<&'a Gpu> {
    if cards.is_empty() || choice == "off" {
        return None;
    }
    if !choice.is_empty() && choice != "auto" {
        return cards.iter().find(|c| c.card == choice);
    }
    cards.iter().find(|c| c.boot_vga).or(cards.first())
}

impl Sampler {
    pub(super) fn probe_gpus(&mut self) -> Option<Vec<Gpu>> {
        if self.gpu.probed {
            return self.gpu.cards.clone();
        }
        self.gpu.probed = true;
        let drm = self.path("/sys/class/drm");
        let names = read_dir_sorted(&drm)?;
        let mut cards: Option<Vec<Gpu>> = None;
        for name in names {
            if !is_card(&name) {
                continue;
            }
            let dir =
                crate::gocompat::join(&self.root, &[b"/sys/class/drm/".as_slice(), &name].concat())
                    .into_os_string()
                    .into_vec();
            let uevent = read_text(path_of(&cat(&dir, "/device/uevent")));
            if uevent.is_empty() {
                continue;
            }
            let mut card = Gpu {
                card: go_lossy(&name),
                driver: "unknown".to_string(),
                boot_vga: false,
                method: "none".to_string(),
                args: Vec::new(),
            };
            let mut slot = String::new();
            for line in uevent.split('\n') {
                if let Some(v) = line.strip_prefix("DRIVER=") {
                    card.driver = v.to_string();
                }
                if let Some(v) = line.strip_prefix("PCI_SLOT_NAME=") {
                    slot = v.to_string();
                }
            }
            card.boot_vga = read_text(path_of(&cat(&dir, "/device/boot_vga"))).trim() == "1";

            match card.driver.as_str() {
                "amdgpu" => {
                    let busy = cat(&dir, "/device/gpu_busy_percent");
                    if readable(path_of(&busy)) {
                        card.method = "busy".to_string();
                        card.args = vec![busy];
                    }
                }
                "nvidia" => {
                    if !slot.is_empty() && on_path("nvidia-smi") {
                        card.method = "nvidia".to_string();
                        card.args = vec![slot.into_bytes()];
                    }
                }
                "i915" | "xe" => {
                    for f in [
                        "/gt/gt0/rc6_residency_ms",
                        "/power/rc6_residency_ms",
                        "/device/tile0/gt0/gtidle/idle_residency_ms",
                    ] {
                        let f = cat(&dir, f);
                        if readable(path_of(&f)) {
                            card.method = "rc6".to_string();
                            card.args = vec![f];
                            break;
                        }
                    }
                    if card.method == "none" {
                        for (act, max) in [
                            ("/gt_act_freq_mhz", "/gt_max_freq_mhz"),
                            (
                                "/device/tile0/gt0/freq0/act_freq",
                                "/device/tile0/gt0/freq0/max_freq",
                            ),
                        ] {
                            let (act, max) = (cat(&dir, act), cat(&dir, max));
                            if readable(path_of(&act)) && readable(path_of(&max)) {
                                card.method = "freq".to_string();
                                card.args = vec![act, max];
                                break;
                            }
                        }
                    }
                }
                _ => {}
            }
            cards.get_or_insert_with(Vec::new).push(card);
        }
        self.gpu.cards = cards.clone();
        cards
    }

    pub(super) fn gpu_sample(
        &mut self,
        choice: &str,
        now: Instant,
    ) -> (Option<Vec<Gpu>>, Option<Gpu>, f64) {
        let cards = self.probe_gpus();
        let chosen = pick_gpu(cards.as_deref().unwrap_or(&[]), choice).cloned();
        let Some(chosen) = chosen else {
            self.stop_nvidia();
            return (cards, None, -1.0);
        };
        if chosen.method != "nvidia" {
            self.stop_nvidia();
        }
        let number = |p: PathBuf| read_text(&p).trim().parse::<f64>().ok();
        let value = match chosen.method.as_str() {
            "busy" => number(chosen.arg(0)).map_or(-1.0, clamp),
            "rc6" => {
                let cur = number(chosen.arg(0));
                let (prev, prev_at) = (self.gpu.prev_idle_ms, self.gpu.prev_idle_at);
                if let Some(cur) = cur {
                    self.gpu.prev_idle_ms = cur;
                    self.gpu.prev_idle_at = Some(now);
                }
                // Whole milliseconds of wall time, as Go's Duration.Milliseconds.
                let wall_ms =
                    prev_at.map(|at| now.saturating_duration_since(at).as_millis() as f64);
                match (cur, wall_ms) {
                    (Some(cur), Some(wall_ms)) if wall_ms > 0.0 && cur >= prev => {
                        clamp(100.0 * (1.0 - (cur - prev) / wall_ms))
                    }
                    _ => -1.0,
                }
            }
            "freq" => match (number(chosen.arg(0)), number(chosen.arg(1))) {
                (Some(act), Some(max)) if max > 0.0 => clamp(100.0 * act / max),
                _ => -1.0,
            },
            "nvidia" => {
                let slot = go_lossy(&chosen.args[0]);
                self.nvidia_value(&slot)
            }
            _ => -1.0,
        };
        (cards, Some(chosen), value)
    }

    fn nvidia_value(&mut self, slot: &str) -> f64 {
        if self.gpu.nvidia.as_ref().is_none_or(|n| n.slot != slot) {
            self.stop_nvidia();
            self.gpu.nvidia = Nvidia::start(slot);
        }
        self.gpu.nvidia.as_ref().map_or(-1.0, Nvidia::value)
    }

    fn stop_nvidia(&mut self) {
        if let Some(n) = self.gpu.nvidia.take() {
            n.stop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{write, TempDir};
    use super::*;
    use std::time::Duration;

    /// One fixture DRM card: driver, boot_vga and whichever nodes the probe
    /// looks for.
    fn card(root: &Path, name: &str, driver: &str, boot_vga: &str, files: &[&str]) {
        let dir = root.join("sys/class/drm").join(name);
        let last = &name[name.len() - 1..];
        write(
            &dir.join("device/uevent"),
            &format!("DRIVER={driver}\nPCI_SLOT_NAME=0000:0{last}:00.0\n"),
        );
        write(&dir.join("device/boot_vga"), &format!("{boot_vga}\n"));
        for f in files {
            write(&dir.join(f), "42\n");
        }
        // Connectors live in the same directory and must be skipped.
        std::fs::create_dir_all(root.join("sys/class/drm").join(format!("{name}-eDP-1"))).unwrap();
    }

    fn probe(root: &TempDir) -> Vec<Gpu> {
        Sampler::new(&root.bytes()).probe_gpus().unwrap_or_default()
    }

    #[test]
    fn probe_intel_residency() {
        let root = TempDir::new();
        card(
            &root.0,
            "card1",
            "i915",
            "1",
            &[
                "gt/gt0/rc6_residency_ms",
                "gt_act_freq_mhz",
                "gt_max_freq_mhz",
            ],
        );
        let cards = probe(&root);
        assert_eq!(cards.len(), 1, "the connector is not a card");
        assert_eq!(cards[0].method, "rc6", "residency wins over frequency");
        assert!(cards[0].boot_vga);
    }

    #[test]
    fn probe_intel_frequency_fallback() {
        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "i915",
            "1",
            &["gt_act_freq_mhz", "gt_max_freq_mhz"],
        );
        let cards = probe(&root);
        assert_eq!((cards[0].method.as_str(), cards[0].args.len()), ("freq", 2));
    }

    #[test]
    fn probe_xe_gtidle() {
        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "xe",
            "1",
            &["device/tile0/gt0/gtidle/idle_residency_ms"],
        );
        assert_eq!(probe(&root)[0].method, "rc6");
    }

    #[test]
    fn probe_amd_and_nvidia() {
        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "amdgpu",
            "0",
            &["device/gpu_busy_percent"],
        );
        card(&root.0, "card1", "nvidia", "1", &[]);
        let cards = probe(&root);
        assert_eq!(cards.len(), 2);
        assert_eq!(cards[0].method, "busy");
        // Without nvidia-smi that card has no unprivileged source and says so.
        if !on_path("nvidia-smi") {
            assert_eq!(cards[1].method, "none");
        }
    }

    #[test]
    fn probe_empty() {
        let root = TempDir::new();
        assert_eq!(Sampler::new(&root.bytes()).probe_gpus(), None);
    }

    fn gpu(card: &str, method: &str, boot_vga: bool) -> Gpu {
        Gpu {
            card: card.into(),
            driver: String::new(),
            boot_vga,
            method: method.into(),
            args: Vec::new(),
        }
    }

    #[test]
    fn pick_gpu_choices() {
        let cards = [gpu("card0", "nvidia", false), gpu("card1", "rc6", true)];
        assert_eq!(
            pick_gpu(&cards, "auto").map(|c| c.card.as_str()),
            Some("card1")
        );
        assert_eq!(
            pick_gpu(&cards, "card0").map(|c| c.method.as_str()),
            Some("nvidia")
        );
        assert_eq!(pick_gpu(&cards, "off"), None);
        assert_eq!(pick_gpu(&cards, "card9"), None);
        let first = [gpu("card0", "busy", false)];
        assert_eq!(
            pick_gpu(&first, "auto").map(|c| c.card.as_str()),
            Some("card0")
        );
    }

    #[test]
    fn gpu_sample_busy_and_freq() {
        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "amdgpu",
            "1",
            &["device/gpu_busy_percent"],
        );
        write(
            &root.0.join("sys/class/drm/card0/device/gpu_busy_percent"),
            "37\n",
        );
        let (_, chosen, value) = Sampler::new(&root.bytes()).gpu_sample("auto", Instant::now());
        assert!(chosen.is_some());
        assert_eq!(value, 37.0);

        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "i915",
            "1",
            &["gt_act_freq_mhz", "gt_max_freq_mhz"],
        );
        write(&root.0.join("sys/class/drm/card0/gt_act_freq_mhz"), "350\n");
        write(
            &root.0.join("sys/class/drm/card0/gt_max_freq_mhz"),
            "1400\n",
        );
        assert_eq!(
            Sampler::new(&root.bytes())
                .gpu_sample("auto", Instant::now())
                .2,
            25.0
        );
    }

    // Residency is an idle counter: busy = 1 - idle time / wall time, and the
    // first sample has nothing to subtract from.
    #[test]
    fn gpu_sample_residency() {
        let root = TempDir::new();
        card(&root.0, "card0", "i915", "1", &["gt/gt0/rc6_residency_ms"]);
        let path = root.0.join("sys/class/drm/card0/gt/gt0/rc6_residency_ms");
        write(&path, "1000\n");
        let mut s = Sampler::new(&root.bytes());
        let t0 = Instant::now();
        assert_eq!(s.gpu_sample("auto", t0).2, -1.0);
        // 2 s passed and the GPU idled for 1.7 s of it.
        write(&path, "2700\n");
        let got = s.gpu_sample("auto", t0 + Duration::from_secs(2)).2;
        assert!((got - 15.0).abs() < 1e-9, "residency busy = {got}, want 15");
    }

    #[test]
    fn gpu_sample_off() {
        let root = TempDir::new();
        card(
            &root.0,
            "card0",
            "amdgpu",
            "1",
            &["device/gpu_busy_percent"],
        );
        let (cards, chosen, value) = Sampler::new(&root.bytes()).gpu_sample("off", Instant::now());
        assert_eq!(
            (cards.map(|c| c.len()), chosen, value),
            (Some(1), None, -1.0)
        );
    }
}
