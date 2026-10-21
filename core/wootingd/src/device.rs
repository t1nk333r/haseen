//! Device layer: locate the Wooting command interface, own it, exchange frames.
//!
//! Vendored from the owner's t1nk333r/haseen-wooting, daemon/src/device.rs at
//! 184f6fa (MIT, Copyright (c) 2026 t1nk33r); plan 099. Comments differ, and
//! two messages: the permission hint names `haseen setup wooting on`, and the
//! no-echo error is worded anew. Citations are pinned in proto.rs.
//!
//! Transport rationale — hidapi is not linked. A Wooting command is a HID
//! *feature* report (wooting-rgb-sdk/src/wooting-usb.c:698
//! `hid_send_feature_report`), which on Linux is the HIDIOCSFEATURE ioctl, and
//! the reply is an ordinary input report (wooting-rgb-sdk/src/wooting-usb.c:798
//! `hid_read_timeout`), i.e. read(2). That is the whole transport.

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use crate::proto::*;

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

const POLLIN: i16 = 0x001;

extern "C" {
    // glibc: `int ioctl(int fd, unsigned long request, ...)`. Declared variadic
    // to match; calling a variadic C function through a fixed prototype is UB
    // even where it happens to work.
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
}

/// `HIDIOCSFEATURE(len)` = `_IOWR('H', 0x06, len)` — linux/hidraw.h
fn hidiocsfeature(len: usize) -> u64 {
    (3u64 << 30) | ((len as u64) << 16) | ((b'H' as u64) << 8) | 0x06
}

fn err(msg: impl Into<String>) -> io::Error {
    io::Error::other(msg.into())
}

/// Walk a HID report descriptor, collecting Usage Page values.
fn usage_pages(desc: &[u8]) -> Vec<u16> {
    let mut pages = Vec::new();
    let mut i = 0usize;
    while i < desc.len() {
        let b = desc[i];
        i += 1;
        if b == 0xFE {
            // long item: [bDataSize][bLongItemTag][data...]
            if i >= desc.len() {
                break;
            }
            i += 2 + desc[i] as usize;
            continue;
        }
        let size = match b & 0x03 {
            0 => 0,
            1 => 1,
            2 => 2,
            _ => 4,
        };
        if i + size > desc.len() {
            break;
        }
        let mut data = 0u32;
        for (k, byte) in desc[i..i + size].iter().enumerate() {
            data |= (*byte as u32) << (8 * k);
        }
        i += size;
        // Global (type 1) / Usage Page (tag 0)
        if (b >> 2) & 0x03 == 1 && (b >> 4) & 0x0F == 0 {
            pages.push(data as u16);
        }
    }
    pages
}

pub struct Found {
    pub path: String,
    pub usage_page: u16,
    pub serial: String,
    /// USB product id, from the sysfs HID_ID triple. Low nibble is the
    /// controller-emulation mode; mask with `PID_MODE_MASK` before comparing.
    pub pid: u16,
}

/// Where the hidraw class tree lives. Overridable so the resolver can be
/// tested against fixture trees without a keyboard — the same seam name
/// `bin/wooting-doctor` already uses for its own /sys probe.
fn sysfs_root() -> PathBuf {
    match env::var_os("WOOTING_SYSFS_HIDRAW") {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from("/sys/class/hidraw"),
    }
}

/// Directory the character devices live in. Overridable for the same reason.
fn dev_dir() -> PathBuf {
    match env::var_os("WOOTING_DEV_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from("/dev"),
    }
}

/// One Wooting hidraw node with the usage pages its descriptor declares.
struct Node {
    found: Found,
    pages: Vec<u16>,
}

/// Every hidraw node belonging to a Wooting keyboard, in sysfs order.
///
/// Resolved by usage page, never by a literal node number: hidraw numbering is
/// not stable across replug. Selection-by-usage-page (never by interface
/// number) mirrors wooting-rgb-sdk/src/wooting-usb.c:425-426.
fn scan() -> Vec<Node> {
    let mut entries: Vec<_> = match fs::read_dir(sysfs_root()) {
        Ok(rd) => rd.filter_map(|e| e.ok()).map(|e| e.path()).collect(),
        Err(_) => return Vec::new(),
    };
    entries.sort();

    let vid_tag = format!(":{:08X}:", WOOTING_VID);
    let mut nodes = Vec::new();

    for node in entries {
        let uevent = match fs::read_to_string(node.join("device/uevent")) {
            Ok(s) => s,
            Err(_) => continue,
        };
        let mut hid_id = "";
        let mut hid_uniq = "";
        for line in uevent.lines() {
            if let Some(v) = line.strip_prefix("HID_ID=") {
                hid_id = v;
            } else if let Some(v) = line.strip_prefix("HID_UNIQ=") {
                hid_uniq = v;
            }
        }
        if !hid_id.to_ascii_uppercase().contains(&vid_tag) {
            continue;
        }
        // HID_ID=0003:000031E3:00001322 — bus:vendor:product, hex.
        let pid = hid_id
            .rsplit(':')
            .next()
            .and_then(|p| u32::from_str_radix(p, 16).ok())
            .map(|p| p as u16)
            .unwrap_or(0);
        let desc = match fs::read(node.join("device/report_descriptor")) {
            Ok(d) => d,
            Err(_) => continue,
        };
        let name = match node.file_name() {
            Some(n) => n.to_string_lossy().to_string(),
            None => continue,
        };
        nodes.push(Node {
            found: Found {
                path: dev_dir().join(name).to_string_lossy().to_string(),
                usage_page: 0,
                serial: hid_uniq.to_string(),
                pid,
            },
            pages: usage_pages(&desc),
        });
    }
    nodes
}

/// First node declaring any of `wanted`, preferring earlier entries of
/// `wanted` across ALL nodes: node order is not usage-page order, and picking
/// per-node would let an earlier 0x1337 node win over the 0xFF55 interface the
/// firmware actually wants.
fn find_page(wanted: &[u16]) -> Option<Found> {
    let nodes = scan();
    for &page in wanted {
        if let Some(n) = nodes.iter().find(|n| n.pages.contains(&page)) {
            return Some(Found {
                path: n.found.path.clone(),
                usage_page: page,
                serial: n.found.serial.clone(),
                pid: n.found.pid,
            });
        }
    }
    None
}

/// Locate the command interface. 0xFF53 is never a candidate: it has no OUT
/// endpoint and carries no command framing.
///
/// Returns `None` when no Wooting command interface is present, which is how
/// the daemon learns the keyboard was unplugged.
pub fn find() -> Option<Found> {
    find_page(&[CFG_V3_USAGE_PAGE, CFG_USAGE_PAGE])
}

/// Locate the analog stream interface (V2 preferred).
pub fn find_analog() -> Option<Found> {
    find_page(&[ANALOG_INTERFACE_V2, ANALOG_INTERFACE_V1])
}

pub struct Device {
    file: File,
    /// ARM/multi-report framing (0xD1, report id 1), set purely from the
    /// 0xFF55 usage page — wooting-rgb-sdk/src/wooting-usb.c:438-440.
    pub arm: bool,
    pub path: String,
    pub serial: String,
    pub pid: u16,
}

impl Device {
    pub fn open() -> io::Result<Device> {
        let found = find().ok_or_else(|| {
            err("no Wooting command interface present (usage page 0xFF55 or 0x1337)")
        })?;
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&found.path)
            .map_err(|e| {
                if e.kind() == io::ErrorKind::PermissionDenied {
                    err(format!(
                        "{}: permission denied — install the udev rule \
                         (haseen setup wooting on → 70-wootingd.rules, TAG+=\"uaccess\")",
                        found.path
                    ))
                } else {
                    e
                }
            })?;
        Ok(Device {
            file,
            arm: found.usage_page == CFG_V3_USAGE_PAGE,
            path: found.path,
            serial: found.serial,
            pid: found.pid,
        })
    }

    /// Physical layout code from `GetDeviceConfig` (19), or None if the
    /// payload is too short to carry it. The SDK indexes the raw report, so
    /// the payload-relative offset follows the reply framing — see
    /// `DEVICE_CONFIG_LAYOUT_RAW_INDEX` for how weakly this is established.
    pub fn layout(&mut self) -> io::Result<Option<u8>> {
        let reply = self.exchange_ok(CMD_GET_DEVICE_CONFIG, [0; 4])?;
        let idx = DEVICE_CONFIG_LAYOUT_RAW_INDEX.saturating_sub(reply.framing.payload);
        Ok(reply.payload().get(idx).copied())
    }

    fn wait_readable(&self, timeout_ms: i32) -> io::Result<bool> {
        let mut pfd = PollFd {
            fd: self.file.as_raw_fd(),
            events: POLLIN,
            revents: 0,
        };
        let rc = unsafe { poll(&mut pfd, 1, timeout_ms) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(rc > 0)
    }

    /// Discard stale/unsolicited input reports before issuing a command.
    ///
    /// The firmware also writes reports nobody asked for on this interface,
    /// and a reply left over from an earlier exchange would look like the
    /// answer to this one; whatever is queued before the command goes out is
    /// read and dropped.
    fn drain(&mut self) {
        let mut sink = [0u8; MAX_REPLY];
        while matches!(self.wait_readable(0), Ok(true)) {
            if self.file.read(&mut sink).is_err() {
                break;
            }
        }
    }

    /// Send an 8-byte command frame and return the reply whose command echo matches.
    pub fn exchange(&mut self, command: u8, params: [u8; 4]) -> io::Result<Reply> {
        self.drain();
        let mut buf = frame(self.arm, command, params);
        let rc = unsafe {
            ioctl(
                self.file.as_raw_fd(),
                hidiocsfeature(COMMAND_SIZE),
                buf.as_mut_ptr(),
            )
        };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }

        // The reply is the first report that echoes the command id; any
        // other report read meanwhile is skipped, at most RESPONSE_RETRIES.
        for _ in 0..RESPONSE_RETRIES {
            if !self.wait_readable(READ_TIMEOUT_MS)? {
                return Err(err(format!("command {command}: no response in {READ_TIMEOUT_MS}ms")));
            }
            let mut reply = Reply {
                buf: [0u8; MAX_REPLY],
                len: 0,
                framing: framing(self.arm),
            };
            reply.len = self.file.read(&mut reply.buf)?;
            if reply.echo() == Some(command) {
                return Ok(reply);
            }
        }
        Err(err(format!("command {command}: none of {RESPONSE_RETRIES} reads echoed it")))
    }

    fn exchange_ok(&mut self, command: u8, params: [u8; 4]) -> io::Result<Reply> {
        let reply = self.exchange(command, params)?;
        match reply.status() {
            STATUS_SUCCESS => Ok(reply),
            STATUS_UNSUPPORTED => Err(err(format!("command {command}: unsupported by firmware"))),
            s => Err(err(format!("command {command}: status 0x{s:02X}"))),
        }
    }

    /// Firmware version as (major, minor, patch).
    pub fn firmware(&mut self) -> io::Result<(u8, u8, u8)> {
        let reply = self.exchange_ok(CMD_GET_VERSION, [0; 4])?;
        let p = reply.payload();
        if p.len() < 3 {
            return Err(err("GetVersion: short payload"));
        }
        Ok((p[0], p[1], p[2]))
    }

    /// Raw serial blob (cmd 3). The authoritative serial string is sysfs
    /// HID_UNIQ; this exists only so `doctor` can show the device answered.
    pub fn serial_blob(&mut self) -> io::Result<Vec<u8>> {
        Ok(self.exchange_ok(CMD_GET_SERIAL, [0; 4])?.payload().to_vec())
    }

    /// The slot of the profile in use, counted from 0.
    ///
    /// Absolute byte 7 of the reply, i.e. payload[0] — the same byte
    /// WootingProfileSwitcher/src/lib.rs:405-425 computes for multi-report
    /// devices (`report_offset 1 + 5 + extra_data_offset 1`).
    pub fn active_profile(&mut self) -> io::Result<u8> {
        let reply = self.exchange_ok(CMD_GET_ACTIVE_PROFILE, [0; 4])?;
        let p = reply.payload();
        if p.is_empty() {
            return Err(err("GetCurrentKeyboardProfileIndex: empty payload"));
        }
        Ok(p[0])
    }

    /// Addressable onboard profile-slot range.
    ///
    /// GetDigitalProfilesCount (cmd 9) cannot be asked: this ARM 60HE+
    /// answers it with status 0x66 (PROBED). So the range is probed instead:
    /// the first slot whose GetMappingProfile answers 0xFF is out of range.
    ///
    /// This is the *address space*, NOT the list of usable profiles. On this
    /// 60HE+ it reports 4 while only slot 0 can actually be activated — use
    /// `profile_stored` to find the profiles a user can switch to.
    pub fn profile_range(&mut self) -> io::Result<u8> {
        for slot in 0..MAX_PROFILES {
            let params = slot_params(self.arm, slot);
            match self.exchange(CMD_GET_MAPPING_PROFILE, params) {
                Ok(reply) if reply.status() == STATUS_ERROR => return Ok(slot.max(1)),
                Ok(_) => continue,
                Err(e) => {
                    if slot == 0 {
                        return Err(e);
                    }
                    return Ok(slot);
                }
            }
        }
        Ok(MAX_PROFILES)
    }

    /// Whether a slot holds a stored keyboard profile, i.e. whether it is a
    /// profile the user can switch to.
    ///
    /// PROBED, and the reason this function exists: an addressable slot is not
    /// necessarily an activatable one. On this 60HE+ only slot 0 holds data —
    /// `GetKeyboardProfile` (39) returns a 22-byte payload for slot 0 and a
    /// zero-length payload for slots 1..=3 — and `ActivateProfile` (23)
    /// answers 0xFF for exactly those empty slots while accepting slot 0.
    /// Reporting the addressable range as the profile list therefore offers
    /// the user three profiles that cannot be selected.
    ///
    /// Correlation, not documented firmware behaviour: stored-data-implies-
    /// activatable held for every slot on the only device available. A slot
    /// that answers with data but still refuses activation would surface as
    /// the daemon's `profile set` error rather than as a silent no-op.
    pub fn profile_stored(&mut self, slot: u8) -> io::Result<bool> {
        let params = slot_params(self.arm, slot);
        let reply = self.exchange(CMD_GET_KEYBOARD_PROFILE, params)?;
        if reply.status() != STATUS_SUCCESS {
            return Ok(false);
        }
        Ok(!reply.payload().is_empty())
    }

    /// Profile name for a slot, if the firmware has metadata stored for it.
    ///
    /// Unconfigured slots answer 0x88 with a zero-length payload (PROBED:
    /// slots 1..=3 on this device), which is not an error — the slot is still
    /// switchable, it just has no name.
    pub fn profile_name(&mut self, slot: u8) -> io::Result<Option<String>> {
        let params = slot_params(self.arm, slot);
        let reply = self.exchange_ok(CMD_GET_PROFILE_METADATA, params)?;
        let payload = reply.payload();
        // field 1 = name, field 3 = RGB theme id (PROBED: `0a 10 "1 Typing
        // Profile" 1a 0c "woot:p:black"`).
        match protobuf_bytes(payload, 1, reply.truncated()) {
            Some(bytes) => Ok(Some(String::from_utf8_lossy(bytes).trim().to_string())),
            None => Ok(None),
        }
    }

    /// Switch the active profile and verify the switch took effect.
    ///
    /// Activate, then reload, with a settle between: the order
    /// WootingProfileSwitcher/src/lib.rs:466-477 sends (`ACTIVATE_PROFILE`,
    /// a sleep, `RELOAD_PROFILE`). Which reload id ARM firmware wants is not
    /// settled: that source sends 7, while wootswitch's list (facts only)
    /// names 38. So 38 is tried first and 7 is the fallback, with the
    /// read-back index as the arbiter.
    /// No RGB commands are sent: lighting is out of scope for v0.1.
    pub fn set_profile(&mut self, slot: u8) -> io::Result<u8> {
        let params = slot_params(self.arm, slot);
        self.exchange_ok(CMD_ACTIVATE_PROFILE, params)?;
        thread::sleep(Duration::from_millis(SET_SETTLE_MS));

        for reload in [CMD_RELOAD_PROFILE, CMD_RELOAD_PROFILE_0] {
            // A firmware that does not know this reload id answers 0x66; that is
            // informative, not fatal.
            let _ = self.exchange(reload, params);
            thread::sleep(Duration::from_millis(SET_SETTLE_MS));
            let active = self.active_profile()?;
            if active == slot {
                return Ok(active);
            }
        }
        let active = self.active_profile()?;
        if active == slot {
            Ok(active)
        } else {
            Err(err(format!(
                "profile set {slot}: device still reports slot {active}"
            )))
        }
    }
}

/// Inter-command settle time. WootingProfileSwitcher/src/config.rs:70 defaults
/// to 250ms; wootswitch's notes give 100 ms (a fact). 100ms is used: every
/// command here is already gated on its own read-back round trip.
pub const SET_SETTLE_MS: u64 = 100;

#[cfg(test)]
mod tests {
    use super::*;
    use parking_lot::{Mutex, MutexGuard};

    // `find()` reads process-wide env vars, so the fixture tests must not run
    // concurrently with each other.
    static ENV: Mutex<()> = Mutex::new(());

    /// Real descriptors, captured from the Wooting 60HE+ (31e3:1322).
    const DESC_COMMAND: &[u8] = &[
        0x06, 0x55, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x0C, 0x15, 0x00, 0x26, 0xFF,
        0x00, 0x75, 0x08, 0x96, 0x20, 0x00, 0x81, 0x02, 0xC0,
    ];
    const DESC_ANALOG: &[u8] = &[
        0x06, 0x53, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x09, 0x02, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75,
        0x08, 0x95, 0x40, 0x81, 0x02, 0xC0,
    ];
    const DESC_KEYBOARD: &[u8] = &[
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0xC0,
    ];
    /// Standard-firmware command interface: usage page 0x1337.
    const DESC_COMMAND_STD: &[u8] = &[0x06, 0x37, 0x13, 0x09, 0x01, 0xA1, 0x01, 0xC0];

    struct Fixture {
        root: PathBuf,
        _guard: MutexGuard<'static, ()>,
    }

    impl Fixture {
        fn new(name: &str) -> Fixture {
            let guard = ENV.lock();
            let root = env::temp_dir().join(format!("wootingd-test-{name}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&root);
            fs::create_dir_all(&root).expect("fixture root");
            env::set_var("WOOTING_SYSFS_HIDRAW", &root);
            env::set_var("WOOTING_DEV_DIR", "/dev");
            Fixture { root, _guard: guard }
        }

        /// Lay down one hidraw node exactly as the kernel presents it.
        fn node(&self, name: &str, hid_id: &str, serial: &str, desc: &[u8]) -> &Fixture {
            let dir = self.root.join(name).join("device");
            fs::create_dir_all(&dir).expect("node dir");
            fs::write(
                dir.join("uevent"),
                format!("DRIVER=hid-generic\nHID_ID={hid_id}\nHID_NAME=Wooting Wooting 60HE+\nHID_UNIQ={serial}\n"),
            )
            .expect("uevent");
            fs::write(dir.join("report_descriptor"), desc).expect("descriptor");
            self
        }

        fn unplug(&self) {
            fs::remove_dir_all(&self.root).expect("unplug");
            fs::create_dir_all(&self.root).expect("empty root");
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
            env::remove_var("WOOTING_SYSFS_HIDRAW");
            env::remove_var("WOOTING_DEV_DIR");
        }
    }

    const WOOTING: &str = "0003:000031E3:00001322";

    /// The whole point of resolving by usage page: the command interface is
    /// picked out of five sibling nodes, and its number is irrelevant.
    #[test]
    fn picks_command_interface_by_usage_page() {
        let fx = Fixture::new("pick");
        fx.node("hidraw3", WOOTING, "A02B", DESC_KEYBOARD)
            .node("hidraw4", WOOTING, "A02B", DESC_KEYBOARD)
            .node("hidraw5", WOOTING, "A02B", DESC_COMMAND)
            .node("hidraw7", WOOTING, "A02B", DESC_ANALOG);

        let found = find().expect("command interface");
        assert_eq!(found.path, "/dev/hidraw5");
        assert_eq!(found.usage_page, CFG_V3_USAGE_PAGE);
        assert_eq!(found.serial, "A02B");
    }

    /// Numbering moves across replug; the resolver must follow the usage page,
    /// never a remembered node number.
    #[test]
    fn follows_the_usage_page_when_numbering_moves() {
        let fx = Fixture::new("moved");
        fx.node("hidraw5", WOOTING, "A02B", DESC_ANALOG)
            .node("hidraw7", WOOTING, "A02B", DESC_COMMAND);

        assert_eq!(find().expect("command interface").path, "/dev/hidraw7");
    }

    /// The analog stream must never be selected: it has no OUT endpoint, so a
    /// daemon that opened it would answer nothing forever.
    #[test]
    fn never_selects_the_analog_stream() {
        let fx = Fixture::new("analog");
        fx.node("hidraw7", WOOTING, "A02B", DESC_ANALOG);
        assert!(find().is_none());
    }

    /// Unplug is reported as absence — this is exactly how the poll loop learns
    /// the keyboard is gone, and how it re-acquires on replug.
    #[test]
    fn absence_then_replug() {
        let fx = Fixture::new("replug");
        fx.node("hidraw5", WOOTING, "A02B", DESC_COMMAND);
        assert!(find().is_some(), "plugged in");

        fx.unplug();
        assert!(find().is_none(), "unplugged");

        // Replug, on a different node number than before.
        fx.node("hidraw9", WOOTING, "A02B", DESC_COMMAND);
        let found = find().expect("replugged");
        assert_eq!(found.path, "/dev/hidraw9");
    }

    /// A missing hidraw class tree must be absence, not a panic.
    #[test]
    fn missing_sysfs_tree_is_absence() {
        let _guard = ENV.lock();
        env::set_var("WOOTING_SYSFS_HIDRAW", "/nonexistent/wootingd-test");
        assert!(find().is_none());
        env::remove_var("WOOTING_SYSFS_HIDRAW");
    }

    /// Another vendor's device on the same usage page is not ours.
    #[test]
    fn ignores_foreign_vendor_on_same_usage_page() {
        let fx = Fixture::new("foreign");
        fx.node("hidraw2", "0003:00000B05:00001AA6", "x", DESC_COMMAND);
        assert!(find().is_none());
    }

    /// Standard firmware exposes 0x1337 and must still be found, with standard
    /// framing rather than ARM.
    #[test]
    fn accepts_standard_firmware_usage_page() {
        let fx = Fixture::new("std");
        fx.node("hidraw4", WOOTING, "A02B", DESC_COMMAND_STD);
        let found = find().expect("standard interface");
        assert_eq!(found.usage_page, CFG_USAGE_PAGE);
    }

    /// When a device offers both, ARM/V3 wins even though the standard node
    /// sorts first — the preference is across nodes, not per node.
    #[test]
    fn prefers_arm_page_over_standard_regardless_of_node_order() {
        let fx = Fixture::new("both");
        fx.node("hidraw1", WOOTING, "A02B", DESC_COMMAND_STD)
            .node("hidraw6", WOOTING, "A02B", DESC_COMMAND);

        let found = find().expect("command interface");
        assert_eq!(found.usage_page, CFG_V3_USAGE_PAGE);
        assert_eq!(found.path, "/dev/hidraw6");
    }

    /// A node whose sysfs files vanish mid-scan (a real race during unplug)
    /// must be skipped, not fatal.
    #[test]
    fn node_without_uevent_is_skipped() {
        let fx = Fixture::new("partial");
        fs::create_dir_all(fx.root.join("hidraw5").join("device")).expect("bare node");
        fx.node("hidraw6", WOOTING, "A02B", DESC_COMMAND);
        assert_eq!(find().expect("command interface").path, "/dev/hidraw6");
    }

    #[test]
    fn usage_pages_reads_real_descriptors() {
        assert!(usage_pages(DESC_COMMAND).contains(&CFG_V3_USAGE_PAGE));
        assert!(usage_pages(DESC_ANALOG).contains(&ANALOG_INTERFACE_V2));
        assert!(!usage_pages(DESC_KEYBOARD).contains(&CFG_V3_USAGE_PAGE));
        // Truncated descriptors must terminate instead of reading past the end.
        assert!(usage_pages(&DESC_COMMAND[..2]).is_empty());
        assert!(usage_pages(&[]).is_empty());
    }
}
