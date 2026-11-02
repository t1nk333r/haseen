//! Wooting vendor HID protocol.
//!
//! Vendored from the owner's t1nk333r/haseen-wooting, daemon/src/proto.rs at
//! 184f6fa (MIT, Copyright (c) 2026 t1nk33r); plan 099. Comments differ, and
//! four command constants are renamed (38, 39, 48 and 55, below): their old
//! names were the unlicensed wootswitch's. Ordinals and wire bytes are as they
//! were.
//!
//! Every constant here is taken from source or from a probe against the real
//! keyboard. Citations use `<repo>/<path>:<line>`, at these commits:
//!
//!   wooting-rgb-sdk        = github.com/WootingKb/wooting-rgb-sdk (MPL-2.0)
//!                            @ 2a3f69916c4ffad2001ecde171e76070cf982cf3
//!   wooting-analog-sdk     = github.com/WootingKb/wooting-analog-sdk (MPL-2.0)
//!                            @ be35a629bd79967012da4dcb731fa9e5a6d3c132
//!   WootingProfileSwitcher = github.com/ShayBox/Wooting-Profile-Switcher (MIT)
//!                            @ de754a6b36148a9f54074a060b62070146e7d57b
//!   ApeironTsuka/wooting-sdk (ISC, declared in its package.json)
//!                            @ 47e20f287a204d610d6adc3c340cec28c29498a4
//!
//! wootingd links and vendors none of them; it only states their facts. The
//! short MPL-2.0 lines quoted below are citations, not code wootingd runs.
//!
//! Some command ordinals and sizes are also known from
//! github.com/clemenscodes/wootswitch, which publishes no licence: it is a
//! source of facts only (a number, a byte position), and nothing of its text
//! is quoted or copied here.
//!
//! What the profile-settings and metadata payloads hold (plan 153) is known
//! from OpenKeyboard's protocol notes, cited as
//!
//!   OpenKeyboard           = github.com/OpenKeyboard-Pr0ject/openkeyboard
//!                            (AGPL-3.0) @ 4029a069189e5542e86ebceaac9d95e8b95e885e
//!
//! by `docs/wooting.md:<line>`. AGPL-3.0 is not MIT: OpenKeyboard is a source
//! of facts only (a field number, an encoding range), as wootswitch is, and
//! none of its code or text is quoted or copied here.
//!
//! Lines marked PROBED were established on a Wooting 60HE+ (31e3:1322,
//! firmware v2.14.0) because no source publishes them; PROBED 2.14.1 marks
//! what plan 153 read from the same keyboard on firmware v2.14.1.

/// wooting-rgb-sdk/src/wooting-usb.c:34  `#define WOOTING_VID2 0x31e3`
pub const WOOTING_VID: u16 = 0x31E3;

/// Config/command interface, standard firmware.
/// wooting-rgb-sdk/src/wooting-usb.c:59  `#define CFG_USAGE_PAGE 0x1337`
pub const CFG_USAGE_PAGE: u16 = 0x1337;
/// Config/command interface, ARM ("V3"/multi-report) firmware — what a 60HE+ runs.
/// wooting-rgb-sdk/src/wooting-usb.c:60  `#define CFG_V3_USAGE_PAGE 0xFF55`
pub const CFG_V3_USAGE_PAGE: u16 = 0xFF55;
/// Read-only analog stream, V2 framing (64-byte reports). NOT the command
/// interface: it has no OUT endpoint and carries no command framing — this is
/// the interface the project's original design targeted, wrongly. It IS the
/// right interface for live key travel (see `analog.rs`).
/// wooting-analog-sdk/wooting-analog-sdk/src/plugin/wooting.rs:31
///   `pub(crate) const ANALOG_INTERFACE_V2: u16 = 0xFF53;`
pub const ANALOG_INTERFACE_V2: u16 = 0xFF53;
/// Legacy analog stream, V1 framing (48-byte reports, no matrix position).
/// wooting-analog-sdk/wooting-analog-sdk/src/plugin/wooting.rs:30
///   `pub(crate) const ANALOG_INTERFACE_V1: u16 = 0xFF54;`
pub const ANALOG_INTERFACE_V1: u16 = 0xFF54;

/// Low nibble of the PID selects controller emulation (XInput / DirectInput /
/// none) and must be masked off before identifying the model.
/// wooting-analog-sdk/wooting-analog-sdk/src/plugin/wooting.rs:33
///   `pub(crate) const WOOTING_PID_MODE_MASK: u16 = 0xFFF0;`
/// wooting-rgb-sdk/src/wooting-usb.c:40-42  `V2_ALT_PID_0/1/2`
pub const PID_MODE_MASK: u16 = 0xFFF0;

/// Physical description of a model: name, matrix width, and whether the
/// board has the function row (matrix row 0). Rows are always 6 in the SDK's
/// matrix (`WOOTING_RGB_ROWS`); a 60% board simply never reports row 0.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Model {
    pub name: &'static str,
    /// wooting-rgb-sdk/src/wooting-usb.c `set_meta_*` → `max_columns`
    pub columns: u8,
    pub function_row: bool,
}

/// Model by masked PID. Base PIDs verbatim from wooting-rgb-sdk/src/wooting-usb.c:36-57;
/// column counts from the matching `set_meta_*` function in the same file
/// (Two family 21 = `WOOTING_TWO_RGB_COLS`, 60HE family 14, 80HE 17, UwU 7).
/// The function-row flag is layout knowledge, not SDK data: a 60% has no F row.
pub fn model_for_pid(pid: u16) -> Option<Model> {
    let m = |name, columns, function_row| Some(Model { name, columns, function_row });
    match pid & PID_MODE_MASK {
        0x1100 => m("Wooting One", 21, true),
        0x1200 => m("Wooting Two", 21, true),
        0x1210 => m("Wooting Two Lekker Edition", 21, true),
        0x1220 => m("Wooting Two HE", 21, true),
        0x1230 => m("Wooting Two HE (ARM)", 21, true),
        0x1300 => m("Wooting 60HE", 14, false),
        0x1310 => m("Wooting 60HE (ARM)", 14, false),
        0x1320 => m("Wooting 60HE+", 14, false),
        0x1340 => m("Wooting 60HE V2", 14, false),
        0x1400 => m("Wooting 80HE", 17, true),
        0x1500 => m("Wooting UwU", 7, false),
        0x1510 => m("Wooting UwU RGB", 7, false),
        _ => None,
    }
}

/// Physical layout, as the firmware reports it through `GetDeviceConfig`.
/// Enum values from wooting-rgb-sdk/src/wooting-usb.h:51-59:
///   `LAYOUT_ANSI = 0, LAYOUT_ISO = 1, LAYOUT_JIS = 2, LAYOUT_ANSI_SPLIT = 3,
///    LAYOUT_ISO_SPLIT = 4`
pub fn layout_name(code: u8) -> &'static str {
    match code {
        0 => "ansi",
        1 => "iso",
        2 => "jis",
        3 => "ansi-split",
        4 => "iso-split",
        _ => "unknown",
    }
}

/// Where the layout byte sits in the raw `GetDeviceConfig` (19) report.
/// wooting-rgb-sdk/src/wooting-usb.c `wooting_usb_get_layout`:
///   `uint8_t index = wooting_usb_use_v2_interface() ? 10 : 9; layout = buff[index];`
/// `v2_interface` is the *model generation* flag — every 31E3 board sets it in
/// its `set_meta_*` (it is not the ARM/multi-report distinction, which is
/// `uses_multi_report`) — so raw index 10 applies to every board this daemon
/// accepts, whichever reply framing it uses. `buff` is the raw report as
/// read(2) returns it, so the payload-relative offset depends on the framing:
/// `10 - framing.payload` = payload[3] on ARM, payload[5] on standard.
/// PROBED only as far as: this ANSI 60HE+ returns payload `00 00 00 00 11 00 04`,
/// i.e. 0 = ANSI at payload[3], which is consistent. Any other value is
/// unverified.
pub const DEVICE_CONFIG_LAYOUT_RAW_INDEX: usize = 10;

/// wooting-rgb-sdk/src/wooting-usb.c:21  `#define WOOTING_COMMAND_SIZE 8`
pub const COMMAND_SIZE: usize = 8;

// Command frame, verbatim from wooting-rgb-sdk/src/wooting-usb.c:689-696:
//     [0] report id : 1 if multi-report (ARM) else 0
//     [1] magic     : 0xD1 if multi-report else 0xD0
//     [2] magic     : 0xDA
//     [3] commandId
//     [4] parameter3   <-- reversed parameter order
//     [5] parameter2
//     [6] parameter1
//     [7] parameter0
const MAGIC_STANDARD: u8 = 0xD0;
const MAGIC_ARM: u8 = 0xD1;
const MAGIC_WORD: u8 = 0xDA;
const REPORT_ID_STANDARD: u8 = 0;
const REPORT_ID_ARM: u8 = 1;

// Reply framing differs between the two firmware families, and hidraw
// contributes to the difference: for numbered reports (ARM, report id 1) read(2)
// delivers the id byte first; for unnumbered reports (standard, id 0) it does
// not.
//
// ARM / multi-report (PROBED on this 60HE+):
//   [0]=report id 1  [1]=0xD1  [2]=0xDA  [3]=cmd echo  [4]=status
//   [5]=payload length  [6]=0  [7..]=payload
// The length byte is unambiguous on this hardware (Ping=1, GetVersion=3,
// GetSerial=11, GetDeviceConfig=7, the slot-name read=32). This agrees with
// WootingProfileSwitcher/src/lib.rs:405-425 (`report_offset 1 + 5 +
// extra_data_offset 1 = 7`). wootswitch reads a different byte of the
// active-slot reply (`CMD_GET_ACTIVE_PROFILE`) as the slot on ARM; on this
// 60HE+ payload[0] reads back each slot switched to (PROBED).
//
// Standard (UNPROBED — no 0x1337 keyboard available; from
// WootingProfileSwitcher/src/lib.rs:304-311 "0-1 Magic Word, 2 Command,
// 3 Unknown, 4 Length, 5-L Buffer" and `report_offset 0 + 5 + 0`):
//   [0]=0xD0  [1]=0xDA  [2]=cmd echo  [3]=status  [4]=payload length  [5..]=payload

/// Byte offsets of one reply layout.
#[derive(Clone, Copy)]
pub struct Framing {
    pub echo: usize,
    pub status: usize,
    pub len_byte: usize,
    pub payload: usize,
}

pub const FRAMING_ARM: Framing = Framing { echo: 3, status: 4, len_byte: 5, payload: 7 };
pub const FRAMING_STANDARD: Framing = Framing { echo: 2, status: 3, len_byte: 4, payload: 5 };

pub fn framing(arm: bool) -> Framing {
    if arm { FRAMING_ARM } else { FRAMING_STANDARD }
}

/// Reply buffer size. On ARM firmware every reply is a single input report of
/// 33 bytes, the report id followed by 32 bytes (PROBED: every reply on this
/// device arrived that way); 128 leaves headroom for a longer report.
/// PROBED 2.14.1: the longer report is real; slot metadata over 26 bytes
/// arrives as report 2, 63 bytes.
pub const MAX_REPLY: usize = 128;

/// wooting-rgb-sdk/src/wooting-usb.c:31  `#define WOOTING_READ_RESPONSE_TIMEOUT 1000`
pub const READ_TIMEOUT_MS: i32 = 1000;
/// Reads per command before giving up on a reply that echoes it: unsolicited
/// reports in between are skipped. 8 is the bound wootswitch uses too (a fact
/// from an unlicensed source, no code taken).
pub const RESPONSE_RETRIES: usize = 8;

/// Status byte of an accepted command. PROBED: GetVersion, GetDeviceConfig
/// and ActivateProfile on a stored slot answer 0x88 on this 60HE+. Also
/// ApeironTsuka/wooting-sdk keyboard.js:24 (Success is 136).
pub const STATUS_SUCCESS: u8 = 0x88;
/// Status byte of a command the firmware does not implement. PROBED:
/// the profile-count command (9) answers 0x66 on this ARM 60HE+. Also
/// ApeironTsuka/wooting-sdk keyboard.js:23 (Unknown is 102).
pub const STATUS_UNSUPPORTED: u8 = 0x66;
/// Status byte of a refused argument. PROBED: ActivateProfile on an empty
/// slot and the slot-keymap read past the last slot answer 0xFF here. Also
/// ApeironTsuka/wooting-sdk keyboard.js:25 (Error is 255).
pub const STATUS_ERROR: u8 = 0xFF;

// --- command IDs -----------------------------------------------------------
// Only GetDeviceConfig=19 appears in WootingKb source
//   (wooting-rgb-sdk/src/wooting-usb.h:93 `#define WOOTING_DEVICE_CONFIG_COMMAND 19`).
// The rest are ordinals of the community's reverse-engineered command list:
// 3, 7, 11 and 23 as WootingProfileSwitcher/src/lib.rs:15-18 defines them,
// 1 and 23 as ApeironTsuka/wooting-sdk keyboard.js:13 and :21 do, and 38, 39,
// 48 and 55 as facts from wootswitch's list (no licence; ordinals only).
// Their names here are haseen's own, chosen for what each answers on this
// keyboard; none is that list's. What each command answers is marked PROBED.
/// GetVersion. ApeironTsuka/wooting-sdk keyboard.js:13 (GetVersion is 1).
/// PROBED: answers a 3-byte payload, the firmware version (2.14.0 here).
pub const CMD_GET_VERSION: u8 = 1;
/// WootingProfileSwitcher/src/lib.rs:15  `const GET_SERIAL: u8 = 3;`
pub const CMD_GET_SERIAL: u8 = 3;
/// WootingProfileSwitcher/src/lib.rs:16  `const RELOAD_PROFILE: u8 = 7;`
pub const CMD_RELOAD_PROFILE_0: u8 = 7;
/// WootingProfileSwitcher/src/lib.rs:17
///   `const GET_CURRENT_KEYBOARD_PROFILE_INDEX: u8 = 11;`
pub const CMD_GET_ACTIVE_PROFILE: u8 = 11;
/// The one command id published by WootingKb itself.
/// wooting-rgb-sdk/src/wooting-usb.h:93  `#define WOOTING_DEVICE_CONFIG_COMMAND 19`
/// PROBED: this 60HE+ answers 0x88 with a 7-byte payload `00 00 00 00 11 00 04`.
pub const CMD_GET_DEVICE_CONFIG: u8 = 19;
/// WootingProfileSwitcher/src/lib.rs:18  `const ACTIVATE_PROFILE: u8 = 23;`
///
/// PROBED, and important: this command validates its argument and refuses
/// slots that hold no stored profile. On this 60HE+ slot 0 answers 0x88 while
/// slots 1..=3 answer 0xFF — the same slots whose `CMD_SLOT_CONTENT` payload
/// is empty. Bytes 4 AND 5 are both range-checked (parameter2 = 1, i.e. an
/// index of 256, also answers 0xFF), so the slot argument is a 16-bit value
/// with parameter3 as its low byte; bytes 6-7 are ignored entirely (an
/// out-of-range slot placed in parameter0 or parameter1 returns a hollow 0x88
/// and changes nothing).
pub const CMD_ACTIVATE_PROFILE: u8 = 23;
/// Applies the activated profile: ordinal 38 in wootswitch's list (a fact; no
/// code taken). Tried before WootingProfileSwitcher's 7 by
/// `Device::set_profile`, with the read-back as the arbiter.
pub const CMD_APPLY_PROFILE: u8 = 38;
/// Reads a slot's key mapping: ordinal 48 in wootswitch's list (a fact; no
/// code taken). PROBED: used as the slot-*range* oracle — addressable slots answer 0x88,
/// the first out-of-range slot answers 0xFF. On this 60HE+ slots 0..=3 are
/// addressable and slot 4 returns 0xFF, matching the 4 onboard profiles in
/// Wooting's quickstart docs (Fn+O / Fn+P / Fn+[ / Fn+]). Addressable is NOT
/// the same as activatable — see `CMD_ACTIVATE_PROFILE` and
/// `Device::profile_settings`.
pub const CMD_SLOT_KEYMAP: u8 = 48;
/// Reads what a slot holds: ordinal 39 in wootswitch's list (a fact; no code
/// taken). PROBED: the activatable-slot oracle. Slot 0 returns a 22-byte
/// payload, slots 1..=3 return a zero-length payload on this device.
/// What the payload is, the profile's own settings, is plan 153's
/// (`ProfileSettings`).
pub const CMD_SLOT_CONTENT: u8 = 39;
/// Reads a slot's name: ordinal 55 in wootswitch's list (a fact; no code
/// taken). PROBED: answers the name as protobuf (`protobuf_bytes`). The
/// profile colour in the same payload is plan 153's (`ProfileMeta`).
pub const CMD_SLOT_NAME: u8 = 55;

/// Upper bound of the slot-range probe (`Device::profile_range`): the range
/// is probed slot by slot and never past this. wootswitch caps its probe at 8
/// too (a fact; no code taken); this 60HE+ stops at 4 (PROBED).
pub const MAX_PROFILES: u8 = 8;

/// Which frame byte carries a profile-slot argument.
/// ARM: parameter3, frame byte 4 (wooting-rgb-sdk/src/wooting-usb.c:693 puts
/// parameter3 there; WootingProfileSwitcher/src/lib.rs:467 passes the slot as
/// parameter3). PROBED: confirmed — passing the slot as parameter0 on this
/// ARM device is silently ignored (all 8 metadata slots returned slot 0's
/// bytes); passing it as parameter3 returns per-slot data.
/// Standard firmware: parameter0, frame byte 7, as wootswitch places it (a
/// fact; no code taken). UNPROBED: no 0x1337 keyboard was available.
pub fn slot_params(arm: bool, slot: u8) -> [u8; 4] {
    if arm {
        [0, 0, 0, slot] // p0,p1,p2,p3 -> slot lands in frame byte 4
    } else {
        [slot, 0, 0, 0] // slot lands in frame byte 7
    }
}

/// Build the 8-byte command frame.
pub fn frame(arm: bool, command: u8, params: [u8; 4]) -> [u8; COMMAND_SIZE] {
    [
        if arm { REPORT_ID_ARM } else { REPORT_ID_STANDARD },
        if arm { MAGIC_ARM } else { MAGIC_STANDARD },
        MAGIC_WORD,
        command,
        params[3],
        params[2],
        params[1],
        params[0],
    ]
}

/// A parsed reply. Fixed-size: a reply is one input report, so nothing is
/// heap-allocated on the hot path (the poll loop runs this every tick).
/// PROBED 2.14.1: a payload of up to 26 bytes comes in report 1 (33 bytes
/// read), a longer one in report 2 (63 bytes read: slot metadata with a name
/// and a colour), which `MAX_REPLY` holds whole.
pub struct Reply {
    pub buf: [u8; MAX_REPLY],
    pub len: usize,
    pub framing: Framing,
}

impl Reply {
    pub fn status(&self) -> u8 {
        self.buf.get(self.framing.status).copied().unwrap_or(0)
    }

    /// Command echo byte, or None on a report too short to carry one.
    pub fn echo(&self) -> Option<u8> {
        if self.len > self.framing.echo {
            Some(self.buf[self.framing.echo])
        } else {
            None
        }
    }

    /// Payload slice, bounded by both the length byte and the bytes actually read.
    pub fn payload(&self) -> &[u8] {
        let start = self.framing.payload;
        if self.len <= start {
            return &[];
        }
        let declared = self.buf[self.framing.len_byte] as usize;
        let available = self.len - start;
        &self.buf[start..start + declared.min(available)]
    }

    /// True when the firmware declared more payload than arrived in this report.
    /// Multi-report continuation is not implemented, so a truncated payload is
    /// a fact of life for anything over ~26 bytes, not a parse error.
    pub fn truncated(&self) -> bool {
        let start = self.framing.payload;
        self.len > start && (self.buf[self.framing.len_byte] as usize) > self.len - start
    }
}

/// Minimal protobuf field reader: returns the bytes of the first length-delimited
/// field with the given number.
///
/// PROBED: `CMD_SLOT_NAME` payloads really are protobuf — slot 0 returns
/// `0a 10 "1 Typing Profile" 1a 0c "woot:p:black"`, i.e. field 1 (name) and
/// field 3 (RGB theme), both wire type 2. WootingProfileSwitcher parses the
/// serial blob the same way (WootingProfileSwitcher/src/lib.rs:99-112).
///
/// `truncated` says the buffer was cut short by the transport rather than being
/// malformed: a field whose declared length runs past the end is then returned
/// as the available prefix instead of being rejected, so a 25+ byte profile
/// name shows up shortened rather than vanishing as "unnamed".
pub fn protobuf_bytes(payload: &[u8], field: u8, truncated: bool) -> Option<&[u8]> {
    let mut i = 0usize;
    while i < payload.len() {
        let key = payload[i];
        if key == 0 {
            return None; // zero padding: end of meaningful data
        }
        i += 1;
        let (num, wire) = (key >> 3, key & 0x07);
        match wire {
            0 => {
                // varint
                while i < payload.len() && payload[i] & 0x80 != 0 {
                    i += 1;
                }
                i += 1;
            }
            2 => {
                if i >= payload.len() {
                    return None;
                }
                // Lengths here are one-byte varints: a 33-byte report cannot
                // carry a field of 128+ bytes, so a continuation bit means the
                // buffer is not what we think it is.
                let len_byte = payload[i];
                if len_byte & 0x80 != 0 {
                    return None;
                }
                let len = len_byte as usize;
                i += 1;
                if i + len > payload.len() {
                    return if truncated && num == field {
                        Some(&payload[i..])
                    } else {
                        None
                    };
                }
                if num == field {
                    return Some(&payload[i..i + len]);
                }
                i += len;
            }
            5 => i += 4,
            1 => i += 8,
            _ => return None,
        }
    }
    None
}

/// One protobuf varint at `*i`, moving `*i` past it. None when it runs off
/// the end or past the ten bytes a u64 takes, or when its tenth byte holds
/// more than the one bit left, which would otherwise be dropped unseen.
fn read_varint(buf: &[u8], i: &mut usize) -> Option<u64> {
    let mut value = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *buf.get(*i)?;
        *i += 1;
        if shift == 63 && byte > 1 {
            return None;
        }
        value |= u64::from(byte & 0x7F) << shift;
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

/// The first varint field with the given number, or None when there is none
/// or the bytes stop making sense before it. A field cut short by the
/// transport is None, never a guess: its value would be wrong.
pub fn protobuf_varint(payload: &[u8], field: u64) -> Option<u64> {
    let mut i = 0usize;
    while i < payload.len() {
        let key = read_varint(payload, &mut i)?;
        if key == 0 {
            return None; // zero padding: end of meaningful data
        }
        match key & 0x07 {
            0 => {
                let value = read_varint(payload, &mut i)?;
                if key >> 3 == field {
                    return Some(value);
                }
            }
            2 => {
                let len = usize::try_from(read_varint(payload, &mut i)?).ok()?;
                i = i.checked_add(len)?;
            }
            5 => i += 4,
            1 => i += 8,
            _ => return None,
        }
    }
    None
}

/// A stored distance in hundredths of a millimetre, rounded to the 0.05 mm
/// step Wootility offers. Two encodings occur, both spanning 0 to 4 mm
/// (OpenKeyboard docs/wooting.md:166-167): precise, 0x4000..=0x7FFF over
/// 0x3FFF steps, and legacy, 0..=0xFF over 255. Anything else is not a
/// distance, and neither is zero: Wootility sets nothing below 0.1 mm
/// (docs/wooting.md:158), so a zero is more likely unset than a setting, and
/// "0.00 mm" would be a wrong value where nothing is the honest one. PROBED 2.14.1: every distance in this 60HE+'s three profiles is
/// precise; their actuation points read 0x67FF, 0x5000 and 0x5999, which are
/// 2.50, 1.00 and 1.60 mm.
pub fn travel_hundredths(raw: u64) -> Option<u16> {
    let (offset, span) = match raw {
        0x4000..=0x7FFF => (raw - 0x4000, 0x3FFF),
        0..=0xFF => (raw, 0xFF),
        _ => return None,
    };
    // 4 mm is 80 steps of 0.05 mm; rounded half up, in integers.
    let steps = (offset * 80 * 2 + span) / (2 * span);
    if steps == 0 {
        return None;
    }
    u16::try_from(steps * 5).ok()
}

/// One profile's own settings, from the `CMD_SLOT_CONTENT` (39, 0x27) payload:
/// a protobuf whose field 1 is the settings message (OpenKeyboard
/// docs/wooting.md:133-144). Each value is None when the payload does not
/// carry it, so an unknown firmware shows nothing rather than a wrong value.
/// These are the profile's defaults: a key with its own actuation or Rapid
/// Trigger (commands 0x31 and 0x3D, not read) overrides them.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ProfileSettings {
    /// Actuation point, hundredths of a millimetre (`travel_hundredths`).
    pub actuation: Option<u16>,
    pub rapid_trigger: Option<bool>,
    /// Rapid Trigger sensitivity, hundredths of a millimetre.
    pub sensitivity: Option<u16>,
    /// Continuous Rapid Trigger. Stored inverted: field 7 is 1 when it is off.
    pub continuous: Option<bool>,
    pub tachyon: Option<bool>,
}

impl ProfileSettings {
    /// PROBED 2.14.1, slot 0 of this 60HE+: `0a 14 08 ff cf 01 10 01 18 00 20
    /// 90 a0 01 28 00 30 02 38 01 48 00`, actuation 2.50 mm, Rapid Trigger off
    /// at 1.00 mm, continuous off, Tachyon off. Fields 2 and 6 are not known
    /// and not read.
    pub fn decode(payload: &[u8], truncated: bool) -> ProfileSettings {
        let Some(inner) = protobuf_bytes(payload, 1, truncated) else {
            return ProfileSettings::default();
        };
        let flag = |field| match protobuf_varint(inner, field) {
            Some(0) => Some(false),
            Some(1) => Some(true),
            _ => None,
        };
        // Tachyon Mode moved fields 5 and 9 together on OpenKeyboard's 80HE
        // (docs/wooting.md:141,144) and which one the firmware reads is not
        // known, so either one set means on.
        let tachyon = match (protobuf_varint(inner, 5), protobuf_varint(inner, 9)) {
            (None, None) => None,
            (a, b) => Some(a.unwrap_or(0) != 0 || b.unwrap_or(0) != 0),
        };
        ProfileSettings {
            actuation: protobuf_varint(inner, 1).and_then(travel_hundredths),
            rapid_trigger: flag(3),
            sensitivity: protobuf_varint(inner, 4).and_then(travel_hundredths),
            continuous: flag(7).map(|off| !off),
            tachyon,
        }
    }
}

/// What the `CMD_SLOT_NAME` (55, 0x37) payload says about a profile: field 1
/// the name, field 2 a colour message whose fields 1, 2 and 3 are red, green
/// and blue (OpenKeyboard docs/wooting.md:115-121); field 3, the icon, is not
/// read.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ProfileMeta {
    pub name: Option<String>,
    pub color: Option<(u8, u8, u8)>,
}

impl ProfileMeta {
    /// PROBED 2.14.1: slot 2 of this 60HE+ answers `0a 07 "Firefly" 12 08 08
    /// ff 01 10 d4 01 18 5c 1a 0c "woot:p:black"`, colour (255, 212, 92); its
    /// other two profiles carry no colour message at all.
    pub fn decode(payload: &[u8], truncated: bool) -> ProfileMeta {
        let name = protobuf_bytes(payload, 1, truncated)
            .map(|bytes| String::from_utf8_lossy(bytes).trim().to_string());
        // A colour cut short by the transport is not a colour, so it is read
        // only when whole. Inside it a missing component is 0, as protobuf
        // leaves zero values out.
        let color = protobuf_bytes(payload, 2, false).and_then(|message| {
            let part = |field| match protobuf_varint(message, field) {
                None => Some(0),
                Some(value) => u8::try_from(value).ok(),
            };
            Some((part(1)?, part(2)?, part(3)?))
        });
        ProfileMeta { name, color }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Byte-for-byte against wooting-rgb-sdk/src/wooting-usb.c:689-696,
    /// including the reversed parameter order that makes parameter0 land in
    /// frame byte 7.
    #[test]
    fn arm_frame_layout() {
        let f = frame(true, CMD_ACTIVATE_PROFILE, [1, 2, 3, 4]);
        assert_eq!(f, [0x01, 0xD1, 0xDA, 23, 4, 3, 2, 1]);
    }

    #[test]
    fn standard_frame_layout() {
        let f = frame(false, CMD_GET_VERSION, [0, 0, 0, 0]);
        assert_eq!(f, [0x00, 0xD0, 0xDA, 1, 0, 0, 0, 0]);
    }

    /// The slot must reach frame byte 4 on ARM: byte 7 is ignored by this
    /// firmware, which is why passing it there looks like success and changes
    /// nothing.
    #[test]
    fn slot_reaches_byte_four_on_arm() {
        assert_eq!(frame(true, CMD_SLOT_NAME, slot_params(true, 3))[4], 3);
        assert_eq!(frame(false, CMD_SLOT_NAME, slot_params(false, 3))[7], 3);
    }

    fn reply_of(bytes: &[u8]) -> Reply {
        reply_with(bytes, FRAMING_ARM)
    }

    fn reply_with(bytes: &[u8], framing: Framing) -> Reply {
        let mut buf = [0u8; MAX_REPLY];
        buf[..bytes.len()].copy_from_slice(bytes);
        Reply { buf, len: bytes.len(), framing }
    }

    /// A 33-byte ARM report exactly as the hardware delivers it: header, length
    /// byte, pad, then payload zero-padded to the report size.
    fn arm_report(cmd: u8, status: u8, declared: u8, payload: &[u8]) -> Reply {
        let mut bytes = vec![0x01, 0xD1, 0xDA, cmd, status, declared, 0];
        bytes.extend_from_slice(payload);
        bytes.resize(33, 0);
        reply_of(&bytes)
    }

    /// A real GetVersion reply: header, length byte 3, then the version.
    #[test]
    fn payload_starts_after_length_prefix() {
        let r = reply_of(&[0x01, 0xD1, 0xDA, 1, 0x88, 3, 0, 2, 14, 0]);
        assert_eq!(r.status(), STATUS_SUCCESS);
        assert_eq!(r.echo(), Some(1));
        assert_eq!(r.payload(), &[2, 14, 0]);
        assert!(!r.truncated());
    }

    /// Every real reply is 33 bytes with 26 payload bytes available, so the
    /// length byte — not the report size — must bound the payload.
    #[test]
    fn length_byte_bounds_payload_within_full_report() {
        let r = arm_report(1, 0x88, 3, &[2, 14, 0]);
        assert_eq!(r.len, 33);
        assert_eq!(r.payload(), &[2, 14, 0]);
        assert!(!r.truncated());
    }

    /// The slot-keymap read declares 150 bytes but only one 33-byte report
    /// arrives; the payload must clamp to what was actually read instead of
    /// reading past it, and say so.
    #[test]
    fn payload_clamps_to_bytes_read() {
        let r = arm_report(48, 0x88, 150, &[0xAB; 26]);
        assert_eq!(r.payload().len(), 26);
        assert!(r.truncated());
    }

    /// The unconfigured-slot case as the hardware sends it: a full 33-byte
    /// report whose length byte is zero. `profile_settings` decides "empty"
    /// from exactly this.
    #[test]
    fn empty_payload_for_unconfigured_slot() {
        let r = arm_report(39, 0x88, 0, &[]);
        assert_eq!(r.len, 33);
        assert!(r.payload().is_empty());
        assert!(!r.truncated());
    }

    #[test]
    fn short_report_has_no_payload_or_echo() {
        let r = reply_of(&[0x01, 0xD1, 0xDA, 55, 0x88]);
        assert!(r.payload().is_empty());
        assert_eq!(r.echo(), Some(55));
        assert_eq!(reply_of(&[0x01, 0xD1]).echo(), None);
        assert_eq!(reply_of(&[0x01, 0xD1]).status(), 0);
    }

    /// Standard firmware: no report-id byte and no pad byte
    /// (WootingProfileSwitcher/src/lib.rs:304-311). UNPROBED layout — this test
    /// pins the cited offsets, not hardware truth.
    #[test]
    fn standard_framing_offsets() {
        let r = reply_with(&[0xD0, 0xDA, 1, 0x88, 3, 2, 14, 0], FRAMING_STANDARD);
        assert_eq!(r.echo(), Some(1));
        assert_eq!(r.status(), STATUS_SUCCESS);
        assert_eq!(r.payload(), &[2, 14, 0]);
        // The same bytes read with ARM offsets must NOT look like a reply,
        // which is how the original bug (every standard command timing out)
        // would have shown up.
        assert_ne!(reply_of(&[0xD0, 0xDA, 1, 0x88, 3, 2, 14, 0]).echo(), Some(1));
    }

    /// The SDK reads the layout from raw byte 10 of the GetDeviceConfig
    /// report. Under ARM framing that is payload[3] — the real 60HE+ reply
    /// `00 00 00 00 11 00 04` puts ANSI(0) there — and under standard framing
    /// it is payload[5]; the raw index is what the citation fixes, so both
    /// framings must land on raw byte 10.
    #[test]
    fn device_config_layout_index_follows_framing() {
        let arm = arm_report(19, 0x88, 7, &[0, 0, 0, 1, 0x11, 0, 4]);
        let idx = DEVICE_CONFIG_LAYOUT_RAW_INDEX - arm.framing.payload;
        assert_eq!(idx, 3);
        assert_eq!(arm.payload()[idx], 1);
        assert_eq!(arm.buf[DEVICE_CONFIG_LAYOUT_RAW_INDEX], 1);

        let std = reply_with(&[0xD0, 0xDA, 19, 0x88, 7, 0, 0, 0, 0, 0, 2, 4], FRAMING_STANDARD);
        let idx = DEVICE_CONFIG_LAYOUT_RAW_INDEX - std.framing.payload;
        assert_eq!(idx, 5);
        assert_eq!(std.payload()[idx], 2);
        assert_eq!(std.buf[DEVICE_CONFIG_LAYOUT_RAW_INDEX], 2);
    }

    /// Slot 0's real metadata payload: field 1 = name, field 3 = RGB theme.
    #[test]
    fn metadata_name_is_protobuf_field_one() {
        let mut payload = vec![0x0A, 0x10];
        payload.extend_from_slice(b"1 Typing Profile");
        payload.extend_from_slice(&[0x1A, 0x0C]);
        payload.extend_from_slice(b"woot:p:black");
        payload.extend(std::iter::repeat_n(0, 4));

        assert_eq!(protobuf_bytes(&payload, 1, false), Some(&b"1 Typing Profile"[..]));
        assert_eq!(protobuf_bytes(&payload, 3, false), Some(&b"woot:p:black"[..]));
        assert_eq!(protobuf_bytes(&payload, 2, false), None);
    }

    /// The real slot-0 report: 32 declared, 26 available. The name fits; the
    /// theme field is cut by the transport and must come back as a prefix,
    /// not vanish.
    #[test]
    fn clamped_field_returns_available_prefix() {
        let mut payload = vec![0x0A, 0x10];
        payload.extend_from_slice(b"1 Typing Profile");
        payload.extend_from_slice(&[0x1A, 0x0C]);
        payload.extend_from_slice(b"woot:p:black");
        let clamped = &payload[..26];

        assert_eq!(protobuf_bytes(clamped, 1, true), Some(&b"1 Typing Profile"[..]));
        assert_eq!(protobuf_bytes(clamped, 3, true), Some(&b"woot:p"[..]));
        // Without the truncation hint the same bytes are malformed.
        assert_eq!(protobuf_bytes(clamped, 3, false), None);

        // A 25-byte name overruns the 26-byte clamp by one; it must survive.
        let mut long = vec![0x0A, 25];
        long.extend_from_slice(b"Long Profile Name Here!!!");
        assert_eq!(protobuf_bytes(&long[..26], 1, true), Some(&b"Long Profile Name Here!!"[..]));
    }

    /// Fixed-offset slicing is what this replaces: a varint field before the
    /// name must not shift the parse.
    #[test]
    fn varint_field_is_skipped() {
        let mut payload = vec![0x08, 0x96, 0x01, 0x0A, 0x04];
        payload.extend_from_slice(b"Game");
        assert_eq!(protobuf_bytes(&payload, 1, false), Some(&b"Game"[..]));
    }

    #[test]
    fn malformed_protobuf_is_rejected_not_panicked() {
        assert_eq!(protobuf_bytes(&[], 1, false), None);
        assert_eq!(protobuf_bytes(&[0x0A], 1, false), None);
        // Declared length runs past the buffer.
        assert_eq!(protobuf_bytes(&[0x0A, 0x20, b'x'], 1, false), None);
        // Zero padding terminates the scan.
        assert_eq!(protobuf_bytes(&[0x00, 0x0A, 0x01, b'x'], 1, false), None);
        // Multi-byte length varint cannot occur in one report.
        assert_eq!(protobuf_bytes(&[0x0A, 0x81, 0x01, b'x'], 1, true), None);
        // Varint value running off the end.
        assert_eq!(protobuf_bytes(&[0x08, 0x80], 1, false), None);
        // Fixed64 / fixed32 keys at the end of the buffer.
        assert_eq!(protobuf_bytes(&[0x09], 1, false), None);
        assert_eq!(protobuf_bytes(&[0x0D, 1, 2], 1, false), None);
    }

    // --- plan 153: profile settings and colour ---------------------------------
    // The SLOT_* captures are this 60HE+'s replies on firmware 2.14.1, read
    // with commands 39 and 55 alone.

    const SLOT0_SETTINGS: &[u8] = &[
        0x0A, 0x14, 0x08, 0xFF, 0xCF, 0x01, 0x10, 0x01, 0x18, 0x00, 0x20, 0x90, 0xA0, 0x01, 0x28,
        0x00, 0x30, 0x02, 0x38, 0x01, 0x48, 0x00,
    ];
    const SLOT1_SETTINGS: &[u8] = &[
        0x0A, 0x14, 0x08, 0x80, 0xA0, 0x01, 0x10, 0x01, 0x18, 0x00, 0x20, 0xE6, 0x8C, 0x01, 0x28,
        0x00, 0x30, 0x02, 0x38, 0x01, 0x48, 0x00,
    ];

    #[test]
    fn varints_read_whole_or_not_at_all() {
        let mut i = 0;
        assert_eq!(read_varint(&[0xFF, 0xCF, 0x01], &mut i), Some(0x67FF));
        assert_eq!(i, 3);
        let mut i = 0;
        assert_eq!(read_varint(&[0x90, 0xA0], &mut i), None, "cut short");
        let mut i = 0;
        assert_eq!(read_varint(&[0x80; 11], &mut i), None, "longer than a u64");
        let mut max = [0xFF; 10];
        max[9] = 0x01;
        let mut i = 0;
        assert_eq!(read_varint(&max, &mut i), Some(u64::MAX), "all 64 bits");
        max[9] = 0x02;
        let mut i = 0;
        assert_eq!(read_varint(&max, &mut i), None, "a 65th bit");
        assert_eq!(protobuf_varint(&[0x08, 0x05, 0x10, 0x07], 2), Some(7));
        assert_eq!(protobuf_varint(&[0x08, 0x05], 2), None);
        // A length-delimited field before the wanted one is skipped whole.
        assert_eq!(protobuf_varint(&[0x0A, 0x02, 0x10, 0x09, 0x10, 0x03], 2), Some(3));
        // A two-byte key (field 16) is read as one key, not two.
        assert_eq!(protobuf_varint(&[0x80, 0x01, 0x05, 0x08, 0x02], 1), Some(2));
        assert_eq!(protobuf_varint(&[0x08], 1), None, "value missing");
        assert_eq!(protobuf_varint(&[0x00, 0x08, 0x01], 1), None, "zero padding ends the scan");
        assert_eq!(protobuf_varint(&[0x0B], 1), None, "group wire types are not ours");
    }

    #[test]
    fn travel_follows_both_encodings_and_wootility_step() {
        // This 60HE+'s own values.
        assert_eq!(travel_hundredths(0x67FF), Some(250));
        assert_eq!(travel_hundredths(0x5000), Some(100));
        assert_eq!(travel_hundredths(0x5999), Some(160));
        assert_eq!(travel_hundredths(0x5010), Some(100));
        assert_eq!(travel_hundredths(0x4666), Some(40));
        // The ends of the precise range; zero, in either encoding, is unset.
        assert_eq!(travel_hundredths(0x4000), None);
        assert_eq!(travel_hundredths(0x4001), None, "rounds to zero");
        assert_eq!(travel_hundredths(0x7FFF), Some(400));
        assert_eq!(travel_hundredths(0), None);
        // Legacy 8-bit: 0x1A is 0.408 mm and 0x3F 0.988 mm, shown on the step.
        assert_eq!(travel_hundredths(0x1A), Some(40));
        assert_eq!(travel_hundredths(0x3F), Some(100));
        assert_eq!(travel_hundredths(0xFF), Some(400));
        // Between the encodings, and above them, is not a distance.
        assert_eq!(travel_hundredths(0x100), None);
        assert_eq!(travel_hundredths(0x3FFF), None);
        assert_eq!(travel_hundredths(0x8000), None);
    }

    #[test]
    fn settings_decode_this_keyboards_profiles() {
        assert_eq!(
            ProfileSettings::decode(SLOT0_SETTINGS, false),
            ProfileSettings {
                actuation: Some(250),
                rapid_trigger: Some(false),
                sensitivity: Some(100),
                continuous: Some(false),
                tachyon: Some(false),
            }
        );
        let slot1 = ProfileSettings::decode(SLOT1_SETTINGS, false);
        assert_eq!((slot1.actuation, slot1.sensitivity), (Some(100), Some(40)));
    }

    #[test]
    fn settings_flags_rapid_trigger_continuous_and_tachyon() {
        // Rapid Trigger on, continuous on (field 7 = 0), Tachyon in field 5 only.
        let on = [0x0A, 0x0C, 0x08, 0x80, 0xA0, 0x01, 0x18, 0x01, 0x28, 0x01, 0x38, 0x00, 0x20, 0x1A];
        let s = ProfileSettings::decode(&on, false);
        assert_eq!(s.rapid_trigger, Some(true));
        assert_eq!(s.continuous, Some(true));
        assert_eq!(s.tachyon, Some(true));
        assert_eq!(s.sensitivity, Some(40), "a legacy sensitivity");
        // Tachyon in field 9 only is on too.
        let s = ProfileSettings::decode(&[0x0A, 0x04, 0x28, 0x00, 0x48, 0x01], false);
        assert_eq!(s.tachyon, Some(true));
        // Neither field: unknown, not off.
        let s = ProfileSettings::decode(&[0x0A, 0x02, 0x18, 0x01], false);
        assert_eq!((s.tachyon, s.rapid_trigger), (None, Some(true)));
        // A flag that is neither 0 nor 1 is unknown.
        assert_eq!(ProfileSettings::decode(&[0x0A, 0x02, 0x18, 0x02], false).rapid_trigger, None);
    }

    #[test]
    fn settings_missing_or_cut_show_nothing_wrong() {
        assert_eq!(ProfileSettings::decode(&[], false), ProfileSettings::default());
        assert_eq!(ProfileSettings::decode(&[0x12, 0x00], false), ProfileSettings::default());
        // Cut inside the sensitivity varint: what came before is kept, the cut
        // value and everything after it are unknown.
        let cut = &SLOT0_SETTINGS[..12];
        let s = ProfileSettings::decode(cut, true);
        assert_eq!((s.actuation, s.rapid_trigger), (Some(250), Some(false)));
        assert_eq!((s.sensitivity, s.continuous, s.tachyon), (None, None, None));
        // Without the transport's word that it was cut, the same bytes are malformed.
        assert_eq!(ProfileSettings::decode(cut, false), ProfileSettings::default());
    }

    #[test]
    fn metadata_carries_the_colour_when_whole() {
        let mut firefly = vec![0x0A, 0x07];
        firefly.extend_from_slice(b"Firefly");
        firefly.extend_from_slice(&[0x12, 0x08, 0x08, 0xFF, 0x01, 0x10, 0xD4, 0x01, 0x18, 0x5C]);
        firefly.extend_from_slice(&[0x1A, 0x0C]);
        firefly.extend_from_slice(b"woot:p:black");
        let meta = ProfileMeta::decode(&firefly, false);
        assert_eq!(meta.name.as_deref(), Some("Firefly"));
        assert_eq!(meta.color, Some((255, 212, 92)));

        // Slot 0 as it reads: a name and an icon, no colour.
        let mut typing = vec![0x0A, 0x10];
        typing.extend_from_slice(b"1 Typing Profile");
        typing.extend_from_slice(&[0x1A, 0x0C]);
        typing.extend_from_slice(b"woot:p:black");
        let meta = ProfileMeta::decode(&typing, false);
        assert_eq!((meta.name.as_deref(), meta.color), (Some("1 Typing Profile"), None));

        // A zero component left out is 0; a value past 255 is no colour.
        assert_eq!(ProfileMeta::decode(&[0x12, 0x03, 0x08, 0xFF, 0x01], false).color, Some((255, 0, 0)));
        assert_eq!(ProfileMeta::decode(&[0x12, 0x03, 0x08, 0x80, 0x02], false).color, None);
        // Cut by the transport inside the colour: the name survives, the colour does not.
        let meta = ProfileMeta::decode(&firefly[..14], true);
        assert_eq!((meta.name.as_deref(), meta.color), (Some("Firefly"), None));
        assert_eq!(ProfileMeta::decode(&[], false), ProfileMeta::default());
    }
}
