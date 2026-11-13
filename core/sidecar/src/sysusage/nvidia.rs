//! One long-running `nvidia-smi -l 3` per daemon, as Sampler.qml ran per
//! shell: polling it per tick would start a process every three seconds.

use super::clamp;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

pub(super) struct Nvidia {
    pub(super) slot: String,
    child: Child,
    /// The last reading as f64 bits; -1 until the first line.
    value: Arc<AtomicU64>,
}

impl Nvidia {
    pub(super) fn start(slot: &str) -> Option<Nvidia> {
        let mut child = Command::new("nvidia-smi")
            .args([
                "--query-gpu=utilization.gpu",
                "--format=csv,noheader,nounits",
                "-i",
                slot,
                "-l",
                "3",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .ok()?;
        let stdout = child.stdout.take()?;
        let value = Arc::new(AtomicU64::new((-1.0f64).to_bits()));
        let shared = Arc::clone(&value);
        let reader = std::thread::Builder::new()
            .name("nvidia-smi".into())
            .stack_size(64 * 1024)
            .spawn(move || {
                let mut reader = BufReader::new(stdout);
                let mut line = Vec::new();
                while reader.read_until(b'\n', &mut line).is_ok_and(|n| n > 0) {
                    if let Ok(v) = String::from_utf8_lossy(&line).trim().parse::<f64>() {
                        shared.store(clamp(v).to_bits(), Ordering::Relaxed);
                    }
                    line.clear();
                }
            });
        if reader.is_err() {
            let _ = child.kill();
            let _ = child.wait();
            return None;
        }
        Some(Nvidia {
            slot: slot.to_string(),
            child,
            value,
        })
    }

    pub(super) fn value(&self) -> f64 {
        f64::from_bits(self.value.load(Ordering::Relaxed))
    }

    pub(super) fn stop(mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
