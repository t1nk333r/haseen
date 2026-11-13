//! One turn cut into frames, and the request each frame sends.

use std::time::Duration;

/// The loop's cap of 10 frames a second: the pace of the loop on luna (1
/// degree every ~0.1 s), and each frame makes Hyprland redraw every border.
pub const MIN_FRAME: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Pace {
    pub frames: usize,
    pub interval: Duration,
}

/// A turn of `seconds` in whole frames no shorter than `min_frame`, at most one
/// a degree. 36 s is 360 frames of 1 degree every 100 ms.
pub fn pace_for(seconds: f64, min_frame: Duration) -> Pace {
    // Go's Duration(seconds * 1e9): nanoseconds, truncated.
    let turn_ns = (seconds * 1e9) as i64;
    let mut frames: i64 = 360;
    let min_ns = min_frame.as_nanos() as i64;
    if min_ns > 0 {
        let fit = turn_ns / min_ns;
        if fit < frames {
            frames = fit;
        }
    }
    if frames < 1 {
        frames = 1;
    }
    let interval_ns = (turn_ns / frames).max(0);
    Pace {
        frames: frames as usize,
        interval: Duration::from_nanos(interval_ns as u64),
    }
}

impl Pace {
    /// Frame i's angle in tenths of a degree, from the frame number rather
    /// than added up, so rounding never drifts the turn.
    pub fn tenths(&self, i: usize) -> usize {
        (i % self.frames) * 3600 / self.frames
    }
}

/// The request for one angle. The colours are fixed per theme, so everything
/// but the two angles is laid down once, and every frame writes into the same
/// buffer: no allocation per frame.
pub struct Frame {
    head: Vec<u8>,
    mid: Vec<u8>,
    tail: &'static [u8],
    buf: Vec<u8>,
}

impl Frame {
    /// The Lua the owner's Python loop sent: the window border and the group
    /// border, same gradient.
    pub fn new(colors: &[String]) -> Frame {
        let mut list = b"{".to_vec();
        for (i, c) in colors.iter().enumerate() {
            if i > 0 {
                list.extend_from_slice(b", ");
            }
            list.push(b'"');
            list.extend_from_slice(c.as_bytes());
            list.push(b'"');
        }
        list.push(b'}');
        let mut head = b"eval hl.config({ general = { col = { active_border = { colors = ".to_vec();
        head.extend_from_slice(&list);
        head.extend_from_slice(b", angle = ");
        let mut mid = b" } } }, group = { col = { border_active = { colors = ".to_vec();
        mid.extend_from_slice(&list);
        mid.extend_from_slice(b", angle = ");
        let tail: &[u8] = b" } } } })";
        let buf = Vec::with_capacity(head.len() + mid.len() + tail.len() + 16);
        Frame {
            head,
            mid,
            tail,
            buf,
        }
    }

    /// The bytes to send for an angle in tenths of a degree. The buffer is
    /// reused by the next call.
    pub fn request(&mut self, tenths: usize) -> &[u8] {
        self.buf.clear();
        self.buf.extend_from_slice(&self.head);
        append_tenths(&mut self.buf, tenths);
        self.buf.extend_from_slice(&self.mid);
        append_tenths(&mut self.buf, tenths);
        self.buf.extend_from_slice(self.tail);
        &self.buf
    }
}

fn append_tenths(b: &mut Vec<u8>, tenths: usize) {
    let whole = tenths / 10;
    // At most 4 digits (3599), written without a format call.
    let mut digits = [0u8; 20];
    let mut n = 0;
    let mut v = whole;
    loop {
        digits[n] = b'0' + (v % 10) as u8;
        n += 1;
        v /= 10;
        if v == 0 {
            break;
        }
    }
    b.extend(digits[..n].iter().rev());
    let frac = tenths % 10;
    if frac != 0 {
        b.push(b'.');
        b.push(b'0' + frac as u8);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pace_cuts_a_turn_into_frames() {
        let cases: [(f64, usize, u64, [usize; 4]); 4] = [
            // luna's loop: a degree every 100 ms.
            (36.0, 360, 100, [0, 10, 20, 3590]),
            // Faster: fewer, bigger steps, never more than 10 frames a second.
            (10.0, 100, 100, [0, 36, 72, 3564]),
            (1.0, 10, 100, [0, 360, 720, 3240]),
            // Slower: still a degree a frame, the frames just last longer.
            (72.0, 360, 200, [0, 10, 20, 3590]),
        ];
        for (seconds, frames, ms, tenths) in cases {
            let p = pace_for(seconds, MIN_FRAME);
            assert_eq!(
                (p.frames, p.interval),
                (frames, Duration::from_millis(ms)),
                "{seconds} s"
            );
            assert_eq!(
                [
                    p.tenths(0),
                    p.tenths(1),
                    p.tenths(2),
                    p.tenths(p.frames - 1)
                ],
                tenths,
                "{seconds} s"
            );
            assert_eq!(
                p.tenths(p.frames),
                0,
                "{seconds} s: the turn comes back to 0"
            );
        }
    }

    #[test]
    fn frame_is_the_eval_the_loop_on_luna_sent() {
        let colours: Vec<String> = [
            "rgba(F25623ff)",
            "rgba(F25623cc)",
            "rgba(F2562311)",
            "rgba(F25623cc)",
        ]
        .map(String::from)
        .to_vec();
        let mut f = Frame::new(&colours);
        let list = r#"{"rgba(F25623ff)", "rgba(F25623cc)", "rgba(F2562311)", "rgba(F25623cc)"}"#;
        let want = format!(
            "eval hl.config({{ general = {{ col = {{ active_border = {{ colors = {list}, angle = 37 }} }} }}, \
             group = {{ col = {{ border_active = {{ colors = {list}, angle = 37 }} }} }} }})"
        );
        assert_eq!(String::from_utf8_lossy(f.request(370)), want);
        assert!(String::from_utf8_lossy(f.request(36)).contains("angle = 3.6 }"));
        // The buffer is reused: no allocation per frame.
        let before = f.request(0).as_ptr();
        for t in 0..3600 {
            f.request(t);
        }
        assert_eq!(
            f.request(1234).as_ptr(),
            before,
            "a frame must reuse its buffer"
        );
    }
}
