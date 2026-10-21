//! wootingd — sole owner of the Wooting vendor HID command interface.
//!
//! Vendored from the owner's t1nk333r/haseen-wooting, daemon/src/main.rs at
//! 184f6fa (MIT, Copyright (c) 2026 t1nk33r); plan 099. Only comments differ.
//! haseen builds it with tools/build-sidecar.sh next to haseen-sidecar.
//!
//! Speaks line-delimited JSON over a unix socket so that QML (Quickshell
//! `Socket` + `SplitParser`) never touches HID. Quickshell 0.3.1 has no HID
//! access at all, so this daemon is not an optimisation, it is the architecture.
//!
//! Verbs (one per line):
//!   status              -> full snapshot
//!   profile get         -> active slot
//!   profile list        -> slots + names
//!   profile set <n>     -> switch, verified by read-back
//!   subscribe           -> snapshot now, then a line on every change
//!   analog get          -> keys currently reporting travel
//!   analog subscribe    -> keys now, then a line whenever the set changes
//!   ping                -> liveness, no device I/O
//!
//! The daemon never exits because the keyboard vanished: it polls slowly and
//! re-acquires on replug. Its lifetime is the keyboard's all the same: the
//! udev rule `haseen setup wooting on` installs
//! (share/haseen/default/udev/70-wootingd.rules) starts wootingd.service when a
//! Wooting is attached and BindsTo= stops it on unplug, so the poll covers the
//! seconds around those edges, not an empty desk. On SIGTERM it removes its
//! socket, which is how the bar widget learns it is gone without polling.

mod analog;
mod device;
mod fnmap;
mod proto;

use std::env;
use std::ffi::{c_char, CString};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};

use parking_lot::Mutex;
use std::thread;
use std::time::Duration;

use device::Device;

/// Slow poll: profile changes are user-initiated, so 1.5s is responsive enough
/// and leaves the command interface almost entirely idle.
const POLL_INTERVAL: Duration = Duration::from_millis(1500);

/// One profile the user can actually switch to. Slots are explicit because the
/// activatable slots are not necessarily `0..count`: a keyboard may have an
/// addressable range of 4 with only some of those slots populated, and
/// offering an empty slot in the list produces a click that always fails.
#[derive(Clone, PartialEq)]
struct Profile {
    slot: u8,
    /// Name stored in firmware metadata, absent for a profile that has one.
    name: Option<String>,
}

#[derive(Clone, PartialEq)]
struct Snapshot {
    present: bool,
    firmware: Option<(u8, u8, u8)>,
    serial: String,
    node: String,
    arm: bool,
    /// USB product id (masked of its controller-emulation nibble) and what it
    /// says about the board. `None` for a Wooting PID the table does not know.
    pid: u16,
    model: Option<proto::Model>,
    /// Physical layout as reported by GetDeviceConfig, "unknown" if the
    /// payload did not carry it.
    layout: &'static str,
    /// Addressable slot range, for diagnostics. Reported by `doctor`, not by
    /// the socket: clients care about what they can select, not the address
    /// space it lives in.
    range: u8,
    active: u8,
    profiles: Vec<Profile>,
}

impl Snapshot {
    fn absent() -> Snapshot {
        Snapshot {
            present: false,
            firmware: None,
            serial: String::new(),
            node: String::new(),
            arm: false,
            pid: 0,
            model: None,
            layout: "unknown",
            range: 0,
            active: 0,
            profiles: Vec::new(),
        }
    }

    /// Display name for a profile: firmware metadata when the profile carries
    /// one, otherwise a 1-based positional label.
    fn label(profile: &Profile) -> String {
        match &profile.name {
            Some(name) if !name.is_empty() => name.clone(),
            _ => format!("Profile {}", profile.slot + 1),
        }
    }

    fn json(&self, tag: &str, tag_value: &str) -> String {
        let mut out = String::with_capacity(256);
        out.push('{');
        out.push_str(&format!("\"{tag}\":{tag_value}"));
        out.push_str(&format!(",\"present\":{}", self.present));
        if let Some((a, b, c)) = self.firmware {
            out.push_str(&format!(",\"firmware\":\"{a}.{b}.{c}\""));
        } else {
            out.push_str(",\"firmware\":null");
        }
        out.push_str(&format!(",\"serial\":\"{}\"", esc(&self.serial)));
        out.push_str(&format!(",\"node\":\"{}\"", esc(&self.node)));
        out.push_str(&format!(",\"framing\":\"{}\"", if self.arm { "arm" } else { "standard" }));
        out.push_str(&format!(",\"pid\":{}", self.pid));
        match self.model {
            Some(m) => out.push_str(&format!(
                ",\"model\":\"{}\",\"columns\":{},\"functionRow\":{}",
                esc(m.name),
                m.columns,
                m.function_row
            )),
            None => out.push_str(",\"model\":null,\"columns\":0,\"functionRow\":false"),
        }
        out.push_str(&format!(",\"layout\":\"{}\"", self.layout));
        out.push_str(&format!(",\"count\":{}", self.profiles.len()));
        out.push_str(&format!(",\"active\":{}", self.active));
        out.push_str(",\"profiles\":[");
        for (i, profile) in self.profiles.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            let named = matches!(&profile.name, Some(n) if !n.is_empty());
            out.push_str(&format!(
                "{{\"slot\":{},\"name\":\"{}\",\"named\":{},\"active\":{}}}",
                profile.slot,
                esc(&Snapshot::label(profile)),
                named,
                profile.slot == self.active
            ));
        }
        out.push_str("]}");
        out
    }
}

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Everything that must be serialised: the device handle and the cache derived
/// from it. One mutex, because there is exactly one device and every operation
/// on it is a round trip.
struct Core {
    dev: Option<Device>,
    snap: Snapshot,
    /// Poll ticks to skip before the next acquire attempt. A device that opens
    /// but never answers (Wootility or wooting-bg-service holding it) would
    /// otherwise cost a 1 s identify timeout on every tick while the core lock
    /// is held, and one log line per tick.
    acquire_backoff: u32,
    /// Last acquire failure, so it is logged once rather than every tick.
    last_failure: Option<String>,
    /// Consecutive ticks on which the node was found but would not open.
    open_failures: u32,
    /// Ticks until the profile list is re-read. Profiles are created in
    /// Wootility, which the daemon cannot observe: without this, a profile
    /// added while the daemon held the device stayed invisible until a
    /// restart, and `wooting set 1` kept failing on a slot that was in fact
    /// ready. Observed on this 60HE+ with two profiles created live.
    reidentify_in: u32,
}

/// Ticks between acquire attempts after a failure: ~6 s at the 1.5 s poll.
const ACQUIRE_BACKOFF_TICKS: u32 = 4;

/// Consecutive open failures before one is logged: ~1.5 s of grace for udev
/// to apply the uaccess ACL after the node appears.
const OPEN_FAILURES_BEFORE_LOG: u32 = 2;

/// Ticks between profile-list re-reads: ~30 s at the 1.5 s poll. The read is
/// two round trips per addressable slot, so it must not run per tick, but
/// noticing a new profile within half a minute is the difference between the
/// widget being right and being confidently wrong.
const REIDENTIFY_TICKS: u32 = 20;

impl Core {
    fn new() -> Core {
        Core {
            dev: None,
            snap: Snapshot::absent(),
            acquire_backoff: 0,
            last_failure: None,
            open_failures: 0,
            reidentify_in: REIDENTIFY_TICKS,
        }
    }

    /// Record an open(2) failure. Unlike an identify timeout it costs nothing,
    /// so there is no backoff: the next tick simply tries again, which is the
    /// bounded wait for a node that is not ready yet. And right after hot-plug
    /// it is expected, not news: systemd starts this daemon when the USB
    /// device appears, the kernel creates the hidraw node at once, and udev
    /// applies the uaccess ACL a moment later — an EACCES in that window would
    /// otherwise be logged as a missing udev rule. Only a failure that
    /// survives a retry is logged.
    fn open_failed(&mut self, e: &dyn std::fmt::Display) {
        self.open_failures = self.open_failures.saturating_add(1);
        if self.open_failures >= OPEN_FAILURES_BEFORE_LOG {
            let msg = format!("open failed: {e}");
            if self.last_failure.as_deref() != Some(&msg) {
                log(&msg);
                self.last_failure = Some(msg);
            }
        }
        self.drop_device();
    }

    /// Record an acquire failure: log it if it is news, and back off.
    fn acquire_failed(&mut self, what: &str, e: &dyn std::fmt::Display) {
        let msg = format!("{what}: {e}");
        if self.last_failure.as_deref() != Some(&msg) {
            log(&msg);
            self.last_failure = Some(msg);
        }
        self.acquire_backoff = ACQUIRE_BACKOFF_TICKS;
        self.drop_device();
    }

    /// Full identify after (re)acquiring the device. Expensive (two round trips
    /// per addressable slot), so it runs only on transition to present.
    ///
    /// Only slots that hold a stored profile are published: an addressable but
    /// empty slot cannot be activated (the firmware answers 0xFF), so listing
    /// it would offer the user a profile that always fails to switch.
    fn identify(&mut self) -> std::io::Result<()> {
        let dev = self.dev.as_mut().expect("identify without device");
        let firmware = dev.firmware()?;
        let range = dev.profile_range()?;
        let mut profiles = Vec::with_capacity(range as usize);
        for slot in 0..range {
            if !dev.profile_stored(slot).unwrap_or(false) {
                continue;
            }
            profiles.push(Profile {
                slot,
                name: dev.profile_name(slot).unwrap_or(None),
            });
        }
        let active = dev.active_profile()?;
        // The active profile is by definition selectable, so never hide it —
        // even if its slot somehow reported no stored data.
        if !profiles.iter().any(|p| p.slot == active) {
            profiles.push(Profile { slot: active, name: None });
            profiles.sort_by_key(|p| p.slot);
        }
        // Layout is decoration, not identity: a firmware that refuses cmd 19
        // still yields a usable device.
        let layout = match dev.layout() {
            Ok(Some(code)) => proto::layout_name(code),
            _ => "unknown",
        };
        let pid = dev.pid & proto::PID_MODE_MASK;
        let model = proto::model_for_pid(dev.pid);
        log(&format!(
            "{} (pid {:04x}, {} layout) firmware v{}.{}.{}, {} of {} addressable slots hold a profile, active {}",
            model.map(|m| m.name).unwrap_or("unknown Wooting model"),
            pid,
            layout,
            firmware.0, firmware.1, firmware.2, profiles.len(), range, active
        ));
        self.snap = Snapshot {
            present: true,
            firmware: Some(firmware),
            serial: dev.serial.clone(),
            node: dev.path.clone(),
            arm: dev.arm,
            pid,
            model,
            layout,
            range,
            active,
            profiles,
        };
        Ok(())
    }

    /// One poll tick. Cheap when nothing changed: a single round trip.
    fn refresh(&mut self) {
        if self.dev.is_none() {
            if device::find().is_none() {
                // Absence is not a failure: forget any stale backoff so a
                // replug is picked up on the very next tick.
                self.acquire_backoff = 0;
                self.last_failure = None;
                self.open_failures = 0;
                self.snap = Snapshot::absent();
                return;
            }
            if self.acquire_backoff > 0 {
                self.acquire_backoff -= 1;
                return;
            }
            match Device::open() {
                Ok(dev) => {
                    self.dev = Some(dev);
                    self.open_failures = 0;
                    match self.identify() {
                        Ok(()) => self.last_failure = None,
                        Err(e) => self.acquire_failed("identify failed", &e),
                    }
                }
                Err(e) => self.open_failed(&e),
            }
            return;
        }

        // The profile list is re-read on a slow cadence, because the only way
        // profiles appear is a user editing them in Wootility - the daemon
        // gets no notification and can only look again.
        if self.reidentify_in == 0 {
            self.reidentify_in = REIDENTIFY_TICKS;
            match self.identify() {
                Ok(()) => return,
                Err(e) => {
                    log(&format!("re-identify failed, releasing device: {e}"));
                    self.drop_device();
                    return;
                }
            }
        }
        self.reidentify_in -= 1;

        let result = self.dev.as_mut().unwrap().active_profile();
        match result {
            Ok(active) => self.snap.active = active,
            Err(e) => {
                log(&format!("poll failed, releasing device: {e}"));
                self.drop_device();
            }
        }
    }

    fn drop_device(&mut self) {
        self.dev = None;
        self.snap = Snapshot::absent();
    }

    fn set_profile(&mut self, slot: u8) -> Result<u8, String> {
        if !self.snap.present {
            return Err("no keyboard present".to_string());
        }
        if !self.snap.profiles.iter().any(|p| p.slot == slot) {
            let available: Vec<String> =
                self.snap.profiles.iter().map(|p| p.slot.to_string()).collect();
            // Distinguish "no such slot" from "slot exists but holds no
            // profile": the second is the common case on a keyboard whose
            // extra profiles were never set up, and the firmware would reject
            // it with an opaque 0xFF.
            return Err(if slot < self.snap.range {
                format!(
                    "slot {slot} holds no stored profile — create it in Wootility first (selectable: {})",
                    available.join(", ")
                )
            } else {
                format!(
                    "slot {slot} out of range (device has {} addressable slots; selectable: {})",
                    self.snap.range,
                    available.join(", ")
                )
            });
        }
        let dev = self.dev.as_mut().ok_or("no keyboard present")?;
        match dev.set_profile(slot) {
            Ok(active) => {
                self.snap.active = active;
                Ok(active)
            }
            Err(e) => {
                let msg = e.to_string();
                // A failed write may mean the device went away mid-command.
                if device::find().is_none() {
                    self.drop_device();
                }
                Err(msg)
            }
        }
    }
}

fn log(msg: &str) {
    eprintln!("wootingd: {msg}");
}

/// What the analog thread knows right now. Separate from `Core` because it
/// changes at key-press rate and must never wait on a command round trip.
struct AnalogState {
    present: bool,
    node: String,
    keys: Vec<analog::Key>,
}

impl AnalogState {
    fn json(&self, tag: &str, tag_value: &str) -> String {
        format!(
            "{{\"{tag}\":{tag_value},\"present\":{},\"node\":\"{}\",\"keys\":{}}}",
            self.present,
            esc(&self.node),
            analog::keys_json(&self.keys)
        )
    }
}

type Analog = Arc<Mutex<AnalogState>>;

/// Minimum interval between analog broadcasts. The stream runs at up to 1 kHz;
/// a bar widget cannot paint faster than its compositor, so frames are
/// coalesced and the latest state is sent at most this often. A frame that
/// releases every key is sent immediately so a lit key never sticks.
const ANALOG_FLUSH_INTERVAL: Duration = Duration::from_millis(16);
/// How long a read blocks before the thread re-checks presence.
const ANALOG_READ_TIMEOUT_MS: i32 = 250;
/// Re-resolve cadence while the analog interface is absent.
const ANALOG_RETRY: Duration = Duration::from_millis(1500);

/// Owns the analog interface for the life of the process: resolve, read,
/// coalesce, publish; on any read error drop it and re-resolve, exactly like
/// the command side does on unplug.
fn fnmap_line(map: &Arc<Mutex<fnmap::FnMap>>) -> String {
    let map = map.lock();
    format!(
        "{{\"event\":\"fn\",\"count\":{},\"keys\":{}}}",
        map.len(),
        map.json()
    )
}

fn analog_thread(state: Analog, subs: Subs, fnmap: Arc<Mutex<fnmap::FnMap>>) {
    use std::time::Instant;
    let mut last_failure: Option<String> = None;
    loop {
        let mut stream = match analog::Stream::open() {
            Ok(s) => {
                last_failure = None;
                s
            }
            Err(e) => {
                // Absence is expected (unplugged, or a board without the
                // interface) and silent; anything else — EACCES from a udev
                // rule that misses the analog node, EBUSY — is logged once.
                if e.kind() != std::io::ErrorKind::NotFound {
                    let msg = format!("analog stream open failed: {e}");
                    if last_failure.as_deref() != Some(&msg) {
                        log(&msg);
                        last_failure = Some(msg);
                    }
                }
                // Never hold the state lock across the sleep: `analog get`
                // must answer `present:false` immediately, not after 1.5 s.
                let line = {
                    let mut guard = state.lock();
                    if guard.present {
                        guard.present = false;
                        guard.node.clear();
                        guard.keys.clear();
                        Some(guard.json("event", "\"analog\""))
                    } else {
                        None
                    }
                };
                if let Some(line) = line {
                    broadcast(&subs, &line);
                }
                thread::sleep(ANALOG_RETRY);
                continue;
            }
        };
        log(&format!("analog stream on {}", stream.path));
        {
            let mut guard = state.lock();
            guard.present = true;
            guard.node = stream.path.clone();
            guard.keys.clear();
        }
        // (Re)attach is itself an event: a client that saw keys lit before a
        // transient loss must see them cleared now, not at the next keypress.
        let line = state.lock().json("event", "\"analog\"");
        broadcast(&subs, &line);
        let mut last_sent: Vec<analog::Key> = Vec::new();
        let mut last_flush = Instant::now();
        let mut dirty = false;
        loop {
            // While a change is pending, block only until the flush window
            // opens; otherwise the final frame of a press-and-hold (frames stop
            // once the key is still) would wait out the full read timeout.
            let timeout = if dirty {
                let waited = Instant::now().duration_since(last_flush);
                ANALOG_FLUSH_INTERVAL.saturating_sub(waited).as_millis().max(1) as i32
            } else {
                ANALOG_READ_TIMEOUT_MS
            };
            match stream.next(timeout) {
                Ok(Some(keys)) => {
                    // Learn before publishing: a frame with Fn held carries
                    // each key's resolved Fn-layer code, and this is the only
                    // place that code is ever visible.
                    let learned = fnmap.lock().observe(&keys);
                    if learned {
                        let line = fnmap_line(&fnmap);
                        broadcast(&subs, &line);
                    }
                    let mut guard = state.lock();
                    if guard.keys != keys {
                        guard.keys = keys;
                        dirty = true;
                    }
                }
                Ok(None) => {}
                Err(e) => {
                    log(&format!("analog stream lost: {e}"));
                    break;
                }
            }
            if dirty {
                let now = Instant::now();
                // Decide first, format only when actually flushing: this runs
                // per frame, up to 1 kHz mid-press, while flushes are ≤60/s.
                let flush = {
                    let guard = state.lock();
                    let released = guard.keys.is_empty();
                    if released || now.duration_since(last_flush) >= ANALOG_FLUSH_INTERVAL {
                        Some((guard.json("event", "\"analog\""), guard.keys.clone()))
                    } else {
                        None
                    }
                };
                if let Some((line, keys)) = flush {
                    // Persist when the press ends, never per frame: a held key
                    // produces up to 1 kHz of identical frames.
                    let released = keys.is_empty();
                    if keys != last_sent {
                        broadcast(&subs, &line);
                        last_sent = keys;
                    }
                    if released {
                        fnmap.lock().persist();
                    }
                    last_flush = now;
                    dirty = false;
                }
            }
        }
    }
}

/// Subscribers keyed by a connection id so the owning client thread can remove
/// its entry on hangup instead of leaving a dead clone until the next broadcast.
type Subs = Arc<Mutex<Vec<(u64, UnixStream)>>>;

static NEXT_CLIENT: AtomicU64 = AtomicU64::new(1);

/// A subscriber that stops reading must not stall the poll thread: every
/// subscription stream carries this write timeout, and a timed-out write
/// evicts it.
const SUBSCRIBER_WRITE_TIMEOUT: Duration = Duration::from_millis(500);

/// One write per line. Reply and event lines can be written to the same
/// socket from two threads (a client that subscribed and then sends verbs), and
/// a line split across two syscalls could interleave with the other thread's.
fn write_line(stream: &mut UnixStream, line: &str) -> bool {
    let mut buf = String::with_capacity(line.len() + 1);
    buf.push_str(line);
    buf.push('\n');
    stream.write_all(buf.as_bytes()).is_ok()
}

fn broadcast(subs: &Subs, line: &str) {
    let mut guard = subs.lock();
    guard.retain_mut(|(_, s)| write_line(s, line));
}

fn socket_path() -> PathBuf {
    if let Some(explicit) = env::var_os("WOOTINGD_SOCKET") {
        return PathBuf::from(explicit);
    }
    if let Some(dir) = env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(dir).join("wootingd.sock");
    }
    PathBuf::from(format!("/tmp/wootingd-{}.sock", unsafe { getuid() }))
}

extern "C" {
    fn getuid() -> u32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn unlink(path: *const c_char) -> i32;
    fn _exit(code: i32) -> !;
}

const SIGINT: i32 = 2;
const SIGPIPE: i32 = 13;
const SIGTERM: i32 = 15;
const SIG_DFL: usize = 0;

/// The socket this process bound, set once before the handler is installed.
static BOUND_SOCKET: OnceLock<CString> = OnceLock::new();

/// SIGTERM/SIGINT: remove our socket, then leave. systemd sends SIGTERM when
/// the keyboard is unplugged (BindsTo= on its device unit); the bar widget
/// watches for the socket file and must see it go, because a stale socket
/// left behind fires no change at all. Only unlink(2) and _exit(2) run here,
/// both async-signal-safe; the Fn map needs no flush (`FnMap::persist`
/// writes-then-renames on every change).
extern "C" fn on_terminate(_sig: i32) {
    if let Some(path) = BOUND_SOCKET.get() {
        unsafe { unlink(path.as_ptr()) };
    }
    unsafe { _exit(0) }
}

/// Installed only after bind succeeds, so a daemon refused by the
/// single-owner guard can never delete the live owner's socket.
fn remove_socket_on_terminate(path: &std::path::Path) {
    use std::os::unix::ffi::OsStrExt;
    let Ok(cpath) = CString::new(path.as_os_str().as_bytes()) else { return };
    if BOUND_SOCKET.set(cpath).is_err() {
        return;
    }
    let handler = on_terminate as extern "C" fn(i32) as usize;
    unsafe {
        signal(SIGTERM, handler);
        signal(SIGINT, handler);
    }
}

/// Behave like a normal CLI when stdout is a closed pipe (`wootingd doctor |
/// head`). Rust ignores SIGPIPE process-wide, which turns that into a panic on
/// the next print.
///
/// Scoped to `doctor` deliberately: the daemon must keep ignoring SIGPIPE, or a
/// client that hangs up mid-broadcast would kill it.
fn restore_sigpipe_for_cli() {
    unsafe { signal(SIGPIPE, SIG_DFL) };
}

/// Everything a client thread needs. Analog events go to their own subscriber
/// list: a bar widget that only wants profile changes must not be fed key
/// travel at 60 Hz.
struct Shared {
    core: Arc<Mutex<Core>>,
    subs: Subs,
    analog: Analog,
    analog_subs: Subs,
    /// What this keyboard reports under Fn. Written only by the analog thread,
    /// read by clients; its own lock so a `fn get` cannot be delayed behind a
    /// key-travel frame.
    fnmap: Arc<Mutex<fnmap::FnMap>>,
}

fn subscribe(out: &UnixStream, id: u64, list: &Subs, snapshot: String) -> String {
    match out.try_clone() {
        Ok(sub) => {
            // A failed timeout set is not worth refusing the subscription
            // over; the eviction just becomes lazier.
            let _ = sub.set_write_timeout(Some(SUBSCRIBER_WRITE_TIMEOUT));
            list.lock().push((id, sub));
            snapshot
        }
        Err(e) => format!("{{\"ok\":false,\"error\":\"{}\"}}", esc(&e.to_string())),
    }
}

fn handle_client(stream: UnixStream, shared: Arc<Shared>) {
    let (core, subs) = (&shared.core, &shared.subs);
    let peer = match stream.try_clone() {
        Ok(s) => s,
        Err(e) => {
            log(&format!("client clone failed: {e}"));
            return;
        }
    };
    let id = NEXT_CLIENT.fetch_add(1, Ordering::Relaxed);
    let mut out = stream;
    let reader = BufReader::new(peer);

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let request = line.trim();
        if request.is_empty() {
            continue;
        }
        let reply = match request {
            "ping" => "{\"ok\":true,\"pong\":true}".to_string(),
            "status" => core.lock().snap.json("ok", "true"),
            "profile get" => {
                let core = core.lock();
                if core.snap.present {
                    format!("{{\"ok\":true,\"active\":{}}}", core.snap.active)
                } else {
                    "{\"ok\":false,\"error\":\"no keyboard present\"}".to_string()
                }
            }
            "profile list" => core.lock().snap.json("ok", "true"),
            "subscribe" => {
                let snapshot = core.lock().snap.json("event", "\"status\"");
                subscribe(&out, id, subs, snapshot)
            }
            "analog get" => shared.analog.lock().json("ok", "true"),
            "analog subscribe" => {
                let snapshot = shared.analog.lock().json("event", "\"analog\"");
                subscribe(&out, id, &shared.analog_subs, snapshot)
            }
            // The learned Fn layer. A client asks once on connect; changes
            // arrive as `{"event":"fn",...}` on the analog subscription, so a
            // panel opened long after the learning is correct immediately.
            "fn get" => {
                let map = shared.fnmap.lock();
                format!(
                    "{{\"ok\":true,\"count\":{},\"keys\":{}}}",
                    map.len(),
                    map.json()
                )
            }
            other => {
                if let Some(arg) = other.strip_prefix("profile set ") {
                    match arg.trim().parse::<u8>() {
                        Ok(slot) => {
                            let result = core.lock().set_profile(slot);
                            match result {
                                Ok(active) => {
                                    let event = {
                                        let core = core.lock();
                                        core.snap.json("event", "\"change\"")
                                    };
                                    broadcast(subs, &event);
                                    format!("{{\"ok\":true,\"active\":{active}}}")
                                }
                                Err(e) => {
                                    format!("{{\"ok\":false,\"error\":\"{}\"}}", esc(&e))
                                }
                            }
                        }
                        Err(_) => format!(
                            "{{\"ok\":false,\"error\":\"profile set: {} is not a slot number\"}}",
                            esc(arg.trim())
                        ),
                    }
                } else {
                    format!(
                        "{{\"ok\":false,\"error\":\"unknown verb: {}\"}}",
                        esc(other)
                    )
                }
            }
        };
        if !write_line(&mut out, &reply) {
            break;
        }
    }

    // Hangup: drop this connection's subscriptions now rather than at the next
    // broadcast, which may be hours away on an idle keyboard.
    subs.lock().retain(|(owner, _)| *owner != id);
    shared.analog_subs.lock().retain(|(owner, _)| *owner != id);
}

/// One-shot diagnostics, for `haseen wooting doctor`. Talks to the
/// device directly, so run it only when the daemon is not holding the device.
fn doctor() -> i32 {
    restore_sigpipe_for_cli();
    match device::find() {
        None => {
            println!("device        : NOT FOUND (no usage page 0xFF55 / 0x1337 under vid 31e3)");
            println!("hint          : is the keyboard plugged in?");
            2
        }
        Some(found) => {
            println!("device        : {} usage_page=0x{:04X}", found.path, found.usage_page);
            println!("serial        : {}", found.serial);
            match Device::open() {
                Err(e) => {
                    println!("open          : FAILED — {e}");
                    3
                }
                Ok(mut dev) => {
                    println!("framing       : {}", if dev.arm { "ARM (0xD1, report id 1)" } else { "standard (0xD0, report id 0)" });
                    match dev.firmware() {
                        Ok((a, b, c)) => println!("firmware      : v{a}.{b}.{c}"),
                        Err(e) => {
                            println!("firmware      : FAILED — {e}");
                            println!("hint          : is Wootility or wooting-bg-service holding the device?");
                            return 4;
                        }
                    }
                    match dev.profile_range() {
                        Ok(range) => {
                            let mut stored = Vec::new();
                            for slot in 0..range {
                                if dev.profile_stored(slot).unwrap_or(false) {
                                    stored.push(slot.to_string());
                                }
                            }
                            println!("slot range    : {range} addressable");
                            println!(
                                "selectable    : {}",
                                if stored.is_empty() {
                                    "none — no slot holds a stored profile".to_string()
                                } else {
                                    format!("slot(s) {}", stored.join(", "))
                                }
                            );
                            if stored.len() < range as usize {
                                println!("note          : empty slots refuse ActivateProfile (0xFF); create profiles in Wootility to use them");
                            }
                        }
                        Err(e) => println!("slot range    : FAILED — {e}"),
                    }
                    match dev.active_profile() {
                        Ok(n) => println!("active slot   : {n}"),
                        Err(e) => println!("active slot   : FAILED — {e}"),
                    }
                    match dev.serial_blob() {
                        Ok(blob) => println!(
                            "serial blob   : {}",
                            blob.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ")
                        ),
                        Err(e) => println!("serial blob   : FAILED — {e}"),
                    }
                    0
                }
            }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("doctor") => std::process::exit(doctor()),
        Some("--help") | Some("-h") => {
            println!("usage: wootingd [doctor]");
            println!("  (no args)  run the daemon on $XDG_RUNTIME_DIR/wootingd.sock");
            println!("  doctor     one-shot device diagnostics");
            return;
        }
        Some(other) => {
            log(&format!("unknown argument: {other}"));
            std::process::exit(2);
        }
        None => {}
    }

    let path = socket_path();

    // Single-owner guard: only one process may usefully own the vendor
    // interface, so refuse to start beside a live daemon and clear a stale
    // socket left by one that died.
    if path.exists() {
        if UnixStream::connect(&path).is_ok() {
            log(&format!("another wootingd is already listening on {}", path.display()));
            std::process::exit(1);
        }
        if let Err(e) = std::fs::remove_file(&path) {
            log(&format!("cannot remove stale socket {}: {e}", path.display()));
            std::process::exit(1);
        }
    }

    let listener = match UnixListener::bind(&path) {
        Ok(l) => l,
        Err(e) => {
            log(&format!("cannot bind {}: {e}", path.display()));
            std::process::exit(1);
        }
    };
    remove_socket_on_terminate(&path);
    log(&format!("listening on {}", path.display()));

    let shared = Arc::new(Shared {
        core: Arc::new(Mutex::new(Core::new())),
        subs: Arc::new(Mutex::new(Vec::new())),
        analog: Arc::new(Mutex::new(AnalogState {
            present: false,
            node: String::new(),
            keys: Vec::new(),
        })),
        analog_subs: Arc::new(Mutex::new(Vec::new())),
        fnmap: Arc::new(Mutex::new(fnmap::FnMap::load())),
    });

    {
        let core = Arc::clone(&shared.core);
        let subs = Arc::clone(&shared.subs);
        thread::spawn(move || loop {
            let event = {
                let mut guard = core.lock();
                let before = guard.snap.clone();
                guard.refresh();
                if guard.snap == before {
                    None
                } else {
                    Some(guard.snap.json("event", "\"change\""))
                }
            };
            if let Some(event) = event {
                broadcast(&subs, &event);
            }
            thread::sleep(POLL_INTERVAL);
        });
    }

    {
        let analog = Arc::clone(&shared.analog);
        let analog_subs = Arc::clone(&shared.analog_subs);
        let map = Arc::clone(&shared.fnmap);
        log(&format!("fn map: {} learned key(s)", map.lock().len()));
        thread::spawn(move || analog_thread(analog, analog_subs, map));
    }

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let shared = Arc::clone(&shared);
                thread::spawn(move || handle_client(stream, shared));
            }
            Err(e) => log(&format!("accept failed: {e}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// systemd starts the daemon the moment the USB device appears, and the
    /// hidraw node can exist before udev has applied its uaccess ACL. That
    /// first EACCES must cost one tick, not the ~6 s acquire backoff, and must
    /// not be logged as a missing udev rule; one that persists is logged once.
    #[test]
    fn open_failure_retries_next_tick_and_logs_only_if_it_persists() {
        let mut core = Core::new();
        let e = std::io::Error::other("/dev/hidraw5: permission denied");

        core.open_failed(&e);
        assert_eq!(core.acquire_backoff, 0, "no backoff: the next tick retries");
        assert!(core.last_failure.is_none(), "the udev ACL race is not news");
        assert!(!core.snap.present);

        core.open_failed(&e);
        assert_eq!(core.acquire_backoff, 0, "still no backoff on a persistent EACCES");
        assert_eq!(core.last_failure.as_deref(), Some("open failed: /dev/hidraw5: permission denied"));

        // Logged once, not per tick.
        core.open_failed(&e);
        assert_eq!(core.open_failures, 3);
        assert_eq!(core.last_failure.as_deref(), Some("open failed: /dev/hidraw5: permission denied"));
    }

    /// An identify that opens but never answers (a second owner) still backs
    /// off: that path holds the core lock through a 1 s timeout per attempt.
    #[test]
    fn identify_failure_still_backs_off() {
        let mut core = Core::new();
        core.acquire_failed("identify failed", &"timed out");
        assert_eq!(core.acquire_backoff, ACQUIRE_BACKOFF_TICKS);
    }
}
