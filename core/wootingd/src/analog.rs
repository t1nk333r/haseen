//! Analog key-travel stream (usage page 0xFF53 / 0xFF54).
//!
//! A separate HID interface from the command channel: its own hidraw node, its
//! own kernel report queue, no OUT endpoint, no command framing. Reading it
//! therefore cannot interleave with or corrupt a command/response round trip on
//! 0xFF55, and it needs no lock shared with `Device`. It is read on its own
//! thread, which publishes throttled frames to `analog subscribe` clients.
//!
//! Frame decode follows the analog SDK's; nothing here is guessed.
//!
//! Vendored from the owner's t1nk333r/haseen-wooting, daemon/src/analog.rs at
//! 184f6fa (MIT, Copyright (c) 2026 t1nk33r); plan 099. Only comments differ:
//! the SDK citations are pinned to the commits proto.rs names, where the
//! quoted lines were checked again.

use std::fs::{File, OpenOptions};
use std::io::{self, Read};
use std::os::fd::AsRawFd;

use crate::device;
use crate::proto::*;

/// One key currently reporting travel.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Key {
    /// Matrix position, the same row/column space as the RGB SDK's 6×21 grid
    /// (wooting-rgb-sdk/src/wooting-rgb-sdk.c `rgb_led_index`). V1 frames carry
    /// no position: both are 0xFF then.
    pub row: u8,
    pub col: u8,
    /// HID usage (keycode). V2: `(namespace << 8) | key`; V1: big-endian pair.
    pub code: u16,
    /// Travel, 0..=1023 (V2, 10-bit) or 0..=255 scaled to the same range (V1).
    pub value: u16,
    /// V2 only: the firmware's own actuation decision for this key.
    pub actuated: bool,
}

/// wooting-analog-sdk/wooting-analog-sdk/src/plugin/wooting.rs:29
///   `pub(crate) const ANALOG_BUFFER_SIZE_V2: usize = 64;`
pub const FRAME_V2: usize = 64;
/// wooting-analog-sdk/wooting-analog-sdk/src/plugin/wooting.rs:28
///   `pub(crate) const ANALOG_BUFFER_SIZE_V1: usize = 48;`
pub const FRAME_V1: usize = 48;
/// Full-scale value after decode; V2 is 10-bit.
/// wooting-analog-sdk/wooting-analog-sdk/src/device.rs:469-471
///   `analog_value_to_float = value / 1023.`
pub const FULL_SCALE: u16 = 1023;

/// Decode a V2 frame: 16 × 4-byte records.
/// Layout quoted from wooting-analog-sdk/wooting-analog-sdk/src/device.rs:438-450:
/// ```text
///   let matrix_pos = b[0]; let key = b[1]; let packed = b[2]; let value = b[3];
///   let row = (matrix_pos >> 5) & 0x07;  let col = matrix_pos & 0x1F;
///   let actuated = (packed & 0x01) != 0;
///   let key_namespace = (packed >> 2) & 0x0F;
///   let value_part = (packed >> 6) & 0x03;
///   let value = (u16::from(value) << 2) | u16::from(value_part);
/// ```
/// A record is a key under travel only while its value is nonzero — the SDK
/// filters V2 records with `.filter(|k| k.value.inner > 0.0)`, so a released
/// key that the firmware still reports at value 0 is dropped, and the frame
/// with every key released is genuinely empty (which is what triggers the
/// send-immediately-on-release path). HID usage 0 in namespace 0 is "no
/// event" and is dropped as well, whatever its value byte says.
pub fn decode_v2(frame: &[u8]) -> Vec<Key> {
    let mut keys = Vec::with_capacity(8);
    for b in frame.as_chunks::<4>().0 {
        let (matrix_pos, key, packed, value_hi) = (b[0], b[1], b[2], b[3]);
        let namespace = (packed >> 2) & 0x0F;
        let value = (u16::from(value_hi) << 2) | u16::from((packed >> 6) & 0x03);
        if value == 0 || (key == 0 && namespace == 0) {
            continue;
        }
        keys.push(Key {
            row: (matrix_pos >> 5) & 0x07,
            col: matrix_pos & 0x1F,
            code: (u16::from(namespace) << 8) | u16::from(key),
            value,
            actuated: packed & 0x01 != 0,
        });
    }
    keys
}

/// Decode a V1 frame: 16 × 3-byte records, no matrix position.
/// wooting-analog-sdk/wooting-analog-sdk/src/device.rs:292-298 (the / 255.0
/// scale at :256-258):
/// ```text
///   .filter(|&s| s[2] != 0)
///   let code = ((u16::from(s[0])) << 8) | u16::from(s[1]);
///   let value = self.analog_value_to_float(u16::from(s[2]));   // / 255.0
/// ```
/// Values are rescaled to the V2 range so consumers see one scale.
pub fn decode_v1(frame: &[u8]) -> Vec<Key> {
    let mut keys = Vec::with_capacity(8);
    for s in frame.as_chunks::<3>().0 {
        if s[2] == 0 {
            continue;
        }
        keys.push(Key {
            row: 0xFF,
            col: 0xFF,
            code: (u16::from(s[0]) << 8) | u16::from(s[1]),
            value: ((u32::from(s[2]) * u32::from(FULL_SCALE)) / 255) as u16,
            actuated: false,
        });
    }
    keys
}

/// JSON for one frame's keys, in the shape the socket publishes.
pub fn keys_json(keys: &[Key]) -> String {
    let mut out = String::with_capacity(16 + keys.len() * 64);
    out.push('[');
    for (i, k) in keys.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!(
            "{{\"row\":{},\"col\":{},\"code\":{},\"value\":{:.3},\"actuated\":{}}}",
            k.row,
            k.col,
            k.code,
            f32::from(k.value) / f32::from(FULL_SCALE),
            k.actuated
        ));
    }
    out.push(']');
    out
}

/// An open analog interface.
pub struct Stream {
    file: File,
    pub path: String,
    v2: bool,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
}

impl Stream {
    pub fn open() -> io::Result<Stream> {
        let found = device::find_analog()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no analog interface"))?;
        let file = OpenOptions::new().read(true).open(&found.path)?;
        Ok(Stream {
            file,
            path: found.path,
            v2: found.usage_page == ANALOG_INTERFACE_V2,
        })
    }

    /// Wait up to `timeout_ms` for a frame; `Ok(None)` on timeout. Returns the
    /// decoded keys. Read errors (EIO/ENODEV on unplug) propagate so the caller
    /// drops the stream and re-resolves.
    pub fn next(&mut self, timeout_ms: i32) -> io::Result<Option<Vec<Key>>> {
        let mut pfd = PollFd {
            fd: self.file.as_raw_fd(),
            events: 0x001, // POLLIN
            revents: 0,
        };
        let rc = unsafe { poll(&mut pfd, 1, timeout_ms) };
        if rc < 0 {
            let e = io::Error::last_os_error();
            if e.kind() == io::ErrorKind::Interrupted {
                return Ok(None);
            }
            return Err(e);
        }
        if rc == 0 {
            return Ok(None);
        }
        let mut buf = [0u8; FRAME_V2];
        let n = self.file.read(&mut buf)?;
        if n == 0 {
            return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "analog stream closed"));
        }
        Ok(Some(if self.v2 {
            decode_v2(&buf[..n.min(FRAME_V2)])
        } else {
            decode_v1(&buf[..n.min(FRAME_V1)])
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(row: u8, col: u8, key: u8, namespace: u8, value10: u16, actuated: bool) -> [u8; 4] {
        let packed = (actuated as u8) | (namespace << 2) | (((value10 & 0x03) as u8) << 6);
        [(row << 5) | col, key, packed, (value10 >> 2) as u8]
    }

    #[test]
    fn v2_record_fields_round_trip() {
        // W key (HID 0x1A) at row 2 col 2, 62% travel, actuated.
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(2, 2, 0x1A, 0, 634, true));
        let keys = decode_v2(&frame);
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0], Key { row: 2, col: 2, code: 0x1A, value: 634, actuated: true });
    }

    #[test]
    fn v2_low_value_bits_live_in_packed_byte() {
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(0, 0, 0x29, 0, 1023, false));
        assert_eq!(decode_v2(&frame)[0].value, 1023);
        frame[..4].copy_from_slice(&rec(0, 0, 0x29, 0, 3, false));
        assert_eq!(decode_v2(&frame)[0].value, 3);
    }

    #[test]
    fn v2_namespace_extends_keycode() {
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(5, 12, 0x01, 0x0F, 10, false));
        assert_eq!(decode_v2(&frame)[0].code, 0x0F01);
    }

    #[test]
    fn v2_empty_records_and_all_released_frame() {
        assert!(decode_v2(&[0u8; FRAME_V2]).is_empty());
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(1, 1, 0x1E, 0, 100, false));
        frame[8..12].copy_from_slice(&rec(1, 2, 0x1F, 0, 200, true));
        let keys = decode_v2(&frame);
        assert_eq!(keys.len(), 2);
        assert_eq!(keys[1].col, 2);
    }

    /// The SDK's `.filter(|k| k.value.inner > 0.0)`: a key the firmware still
    /// reports at value 0 is released, not "under travel", and a frame holding
    /// only such records is the empty frame that triggers send-on-release.
    #[test]
    fn v2_zero_travel_record_is_a_release() {
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(2, 2, 0x1A, 0, 0, false));
        assert!(decode_v2(&frame).is_empty());
        // A record with a real key code but zero value alongside a live key.
        frame[4..8].copy_from_slice(&rec(2, 3, 0x08, 0, 400, true));
        let keys = decode_v2(&frame);
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0].code, 0x08);
        // Usage 0 in namespace 0 is "no event" even with a nonzero value.
        frame[..4].copy_from_slice(&rec(0, 0, 0x00, 0, 512, false));
        assert_eq!(decode_v2(&frame).len(), 1);
    }

    #[test]
    fn v2_max_matrix_position() {
        let mut frame = [0u8; FRAME_V2];
        frame[..4].copy_from_slice(&rec(7, 31, 0x04, 0, 1, false));
        let k = &decode_v2(&frame)[0];
        assert_eq!((k.row, k.col), (7, 31));
    }

    #[test]
    fn v1_records_rescaled_and_positionless() {
        let mut frame = [0u8; FRAME_V1];
        frame[..3].copy_from_slice(&[0x00, 0x1A, 255]);
        frame[3..6].copy_from_slice(&[0x00, 0x1B, 0]); // released, dropped
        let keys = decode_v1(&frame);
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0].code, 0x1A);
        assert_eq!(keys[0].value, FULL_SCALE);
        assert_eq!((keys[0].row, keys[0].col), (0xFF, 0xFF));
    }

    #[test]
    fn short_frame_does_not_panic() {
        assert!(decode_v2(&[0x22, 0x1A, 0x01]).is_empty());
        assert!(decode_v1(&[0x00, 0x1A]).is_empty());
    }

    #[test]
    fn json_shape() {
        let keys = vec![Key { row: 2, col: 2, code: 26, value: 1023, actuated: true }];
        assert_eq!(
            keys_json(&keys),
            "[{\"row\":2,\"col\":2,\"code\":26,\"value\":1.000,\"actuated\":true}]"
        );
        assert_eq!(keys_json(&[]), "[]");
    }
}
