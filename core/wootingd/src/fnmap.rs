//! Learned Fn-layer map: matrix position -> the code this keyboard reports for
//! that key while Fn is held.
//!
//! Vendored from the owner's t1nk333r/haseen-wooting, daemon/src/fnmap.rs at
//! 184f6fa (MIT, Copyright (c) 2026 t1nk33r); plan 099. Only comments differ.
//!
//! Why the daemon and not the UI: the mapping is only observable from the
//! analog stream, which the daemon owns, and it must outlive any one shell
//! session. A panel that relearned per session showed Wooting's documented
//! defaults after every shell restart — including for the keys where
//! this board disagrees with them, which is the worst case: a confident label
//! that is wrong.
//!
//! Not configuration: this is observed state, so it lives in the state
//! directory and never in `shell.json`. Nothing reads it as settings, and
//! deleting it only costs the keyboard a relearn.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;
use std::path::PathBuf;

use crate::analog;

/// Fn itself, namespace 4 key 9. PROBED on a 60HE+: the rightmost bottom key
/// reports this, and it is the only code that says "the Fn layer is active".
pub const CODE_FN: u16 = 0x409;

/// The firmware's answer for "this Fn cell does nothing". PROBED: 13 keys whose
/// Fn cell is empty in Wooting's Fn1 diagram all report it. Stored like any
/// other answer — a key that is *known* to do nothing is knowledge, and it is
/// what stops the UI from drawing a documented default there.
/// Kept as documentation of the probe and for the tests that pin the
/// behaviour; the daemon stores it like any other code and never special-cases
/// it - naming a cell "unassigned" is the UI's job.
#[allow(dead_code)]
pub const CODE_UNASSIGNED: u16 = 0x400;

pub struct FnMap {
    entries: BTreeMap<(u8, u8), u16>,
    path: Option<PathBuf>,
    dirty: bool,
    /// Positions held in the previous frame, so a key teaches only on the
    /// frame it goes down. See `observe`.
    down: BTreeSet<(u8, u8)>,
}

fn state_path() -> Option<PathBuf> {
    if let Ok(explicit) = std::env::var("WOOTINGD_FNMAP") {
        if !explicit.is_empty() {
            return Some(PathBuf::from(explicit));
        }
    }
    let dir = match std::env::var("XDG_STATE_HOME") {
        Ok(d) if !d.is_empty() => PathBuf::from(d),
        _ => PathBuf::from(std::env::var("HOME").ok()?).join(".local/state"),
    };
    Some(dir.join("wootingd").join("fnmap.json"))
}

/// Parse `{"5,10":80,"3,3":73}`. Hand-rolled because the daemon links no
/// dependencies; anything unparseable is dropped rather than fatal — a corrupt
/// cache must cost a relearn, never the daemon.
fn parse(text: &str) -> BTreeMap<(u8, u8), u16> {
    let mut out = BTreeMap::new();
    let mut rest = text.trim();
    if !rest.starts_with('{') {
        return out;
    }
    rest = rest[1..].trim_end_matches('}');
    // Split on '"' so a key's own comma ("3,3") cannot split a field. The
    // sequence is: leading junk, key, ":value,", key, ":value,", ...
    let mut fields = rest.split('"');
    let _ = fields.next();
    while let (Some(key), Some(tail)) = (fields.next(), fields.next()) {
        let value = tail
            .trim_start()
            .trim_start_matches(':')
            .trim()
            .trim_end_matches(',')
            .trim();
        let mut halves = key.split(',');
        let row = halves.next().and_then(|s| s.trim().parse::<u8>().ok());
        let col = halves.next().and_then(|s| s.trim().parse::<u8>().ok());
        let code = value.parse::<u16>().ok();
        if let (Some(row), Some(col), Some(code), None) = (row, col, code, halves.next()) {
            out.insert((row, col), code);
        }
    }
    out
}

impl FnMap {
    pub fn load() -> Self {
        let path = state_path();
        let entries = path
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .map(|t| parse(&t))
            .unwrap_or_default();
        FnMap {
            entries,
            path,
            dirty: false,
            down: BTreeSet::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Fold one analog frame in. Two rules, both learned the hard way on real
    /// hardware:
    ///
    /// 1. Only frames with Fn held teach anything. Otherwise a key reports its
    ///    base code and the Fn mapping would be overwritten with "A" the moment
    ///    the user typed.
    /// 2. Only a key's *first* frame teaches. On release the firmware reverts
    ///    keys to their base code while still reporting Fn: a recorded Fn+O
    ///    press went `r2c9=0x403 + Fn` then `r2c9=0x012 + Fn`, so last-write
    ///    learning stored plain `O` and the panel showed `O` as the Fn-layer
    ///    function of O.
    ///
    /// Returns true when the map changed, so the caller can broadcast and
    /// persist exactly then.
    pub fn observe(&mut self, keys: &[analog::Key]) -> bool {
        // A key teaches only once it has *actuated*. Below that the firmware
        // has not resolved the layer yet and reports whatever it likes: every
        // wrong entry this code ever produced came from a record sitting at
        // ~0.02 travel with `actuated:false`, where Fn+O read as plain `O` and
        // Fn+1 as plain `1`. The flag is the firmware's own decision, so it is
        // the right gate rather than a travel threshold of our choosing.
        let usable = |k: &&analog::Key| k.row != 0xFF && k.col != 0xFF && k.actuated;
        let held: BTreeSet<(u8, u8)> = keys.iter().filter(usable).map(|k| (k.row, k.col)).collect();
        let fn_down = keys
            .iter()
            .filter(usable)
            .any(|k| k.code == CODE_FN);
        if !fn_down {
            // Nothing to learn, but the key set still has to be tracked or the
            // next Fn press would look like a continuation of this one.
            self.down = held;
            return false;
        }
        // The cell reporting Fn is the layer switch, not a mapping. Skip the
        // whole position: one release frame carried a second record there
        // (0x603) that would otherwise have been learned as Fn's own function.
        let fn_cells: BTreeSet<(u8, u8)> = keys
            .iter()
            .filter(|k| k.code == CODE_FN)
            .map(|k| (k.row, k.col))
            .collect();
        let mut changed = false;
        for k in keys.iter().filter(usable) {
            let pos = (k.row, k.col);
            if fn_cells.contains(&pos) || self.down.contains(&pos) {
                continue;
            }
            if self.entries.insert(pos, k.code) != Some(k.code) {
                changed = true;
            }
        }
        self.down = held;
        if changed {
            self.dirty = true;
        }
        changed
    }

    pub fn json(&self) -> String {
        let mut out = String::with_capacity(16 + self.entries.len() * 12);
        out.push('{');
        for (i, ((row, col), code)) in self.entries.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str(&format!("\"{row},{col}\":{code}"));
        }
        out.push('}');
        out
    }

    /// Write the map out if it changed. Called when a press ends, not per
    /// frame: a held key produces up to 1 kHz of frames and the map is the
    /// same for all of them.
    pub fn persist(&mut self) {
        if !self.dirty {
            return;
        }
        self.dirty = false;
        let Some(path) = self.path.clone() else { return };
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        // Write-then-rename: a daemon killed mid-write must not leave a
        // half-written cache that parses as a smaller map.
        let tmp = path.with_extension("json.tmp");
        let body = self.json();
        let wrote = std::fs::File::create(&tmp).and_then(|mut f| {
            f.write_all(body.as_bytes())?;
            f.write_all(b"\n")
        });
        if wrote.is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(row: u8, col: u8, code: u16) -> analog::Key {
        analog::Key {
            row,
            col,
            code,
            value: 1023,
            actuated: true,
        }
    }

    fn empty() -> FnMap {
        FnMap {
            entries: BTreeMap::new(),
            path: None,
            dirty: false,
            down: BTreeSet::new(),
        }
    }

    #[test]
    fn learns_only_while_fn_is_held() {
        let mut m = empty();
        // Fn+D reporting Insert is the mapping to keep.
        assert!(m.observe(&[key(5, 13, CODE_FN), key(3, 3, 0x49)]));
        assert_eq!(m.json(), "{\"3,3\":73}");
        // The same key typed without Fn reports its base code; taking that
        // would replace the learned Insert with "D" as soon as the user typed.
        assert!(!m.observe(&[key(3, 3, 0x07)]));
        assert_eq!(m.json(), "{\"3,3\":73}");
    }

    #[test]
    fn fn_key_itself_is_not_a_mapping() {
        let mut m = empty();
        assert!(!m.observe(&[key(5, 13, CODE_FN)]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn unpositioned_v1_frames_teach_nothing() {
        let mut m = empty();
        assert!(!m.observe(&[key(0xFF, 0xFF, CODE_FN), key(0xFF, 0xFF, 0x49)]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn repeat_frames_do_not_report_a_change() {
        let mut m = empty();
        let frame = [key(5, 13, CODE_FN), key(3, 3, 0x49)];
        assert!(m.observe(&frame));
        assert!(!m.observe(&frame));
    }

    #[test]
    fn a_remap_replaces_the_old_answer() {
        let mut m = empty();
        m.observe(&[key(5, 13, CODE_FN), key(3, 3, 0x49)]);
        // Released, then pressed again: a fresh press is what teaches.
        m.observe(&[key(5, 13, CODE_FN)]);
        assert!(m.observe(&[key(5, 13, CODE_FN), key(3, 3, 0x4D)]));
        assert_eq!(m.json(), "{\"3,3\":77}");
    }

    #[test]
    fn a_key_below_actuation_teaches_nothing() {
        // Verbatim shape from the frames that produced every wrong entry: the
        // key sits at 0.02 travel with actuated:false, and the firmware reports
        // its base code although Fn is held. That is how Fn+O learned "O".
        let mut m = empty();
        let noise = analog::Key { row: 2, col: 9, code: 0x012, value: 20, actuated: false };
        assert!(!m.observe(&[key(5, 13, CODE_FN), noise]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn a_releasing_fn_does_not_open_the_layer() {
        // Recorded: Fn at 0.441 with actuated:false next to a fresh keypress.
        // Treating that as "Fn held" is how Fn+1 learned plain "1".
        let mut m = empty();
        let releasing = analog::Key { row: 5, col: 13, code: CODE_FN, value: 451, actuated: false };
        assert!(!m.observe(&[releasing, key(1, 1, 0x1E)]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn a_release_does_not_overwrite_the_resolved_code() {
        // Verbatim from a recorded Fn+O press on this 60HE+: the press frame
        // carries the resolved selector, and the release frame carries the
        // key's *base* code while Fn is still reported. Last-write learning
        // stored 0x12 and the panel then showed "O" as O's Fn-layer function.
        let mut m = empty();
        assert!(m.observe(&[key(2, 9, 0x403), key(5, 13, CODE_FN)]));
        assert!(!m.observe(&[key(2, 9, 0x012), key(5, 13, CODE_FN)]));
        assert_eq!(m.json(), "{\"2,9\":1027}");
    }

    #[test]
    fn the_fn_cells_own_position_is_never_learned() {
        // The same release frame reported a second record at the Fn cell
        // (0x603). Keyed by position, not by code, or that becomes "Fn's own
        // Fn-layer function".
        let mut m = empty();
        assert!(!m.observe(&[key(5, 13, CODE_FN), key(5, 13, 0x603)]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn a_key_held_across_the_fn_press_is_not_credited() {
        // Typing "a", then reaching for Fn while still holding it, must not
        // teach that Fn+A is "a": the key was already down when Fn arrived.
        let mut m = empty();
        m.observe(&[key(3, 1, 0x04)]);
        assert!(!m.observe(&[key(3, 1, 0x04), key(5, 13, CODE_FN)]));
        assert_eq!(m.json(), "{}");
    }

    #[test]
    fn unassigned_is_stored_like_any_other_answer() {
        // "does nothing" is what stops the UI drawing a documented default.
        let mut m = empty();
        assert!(m.observe(&[key(5, 13, CODE_FN), key(2, 4, CODE_UNASSIGNED)]));
        assert_eq!(m.json(), "{\"2,4\":1024}");
    }

    #[test]
    fn json_round_trips() {
        let mut m = empty();
        m.observe(&[
            key(5, 13, CODE_FN),
            key(3, 3, 0x49),
            key(4, 2, 0x4D),
            key(2, 12, 0x46),
        ]);
        let text = m.json();
        assert_eq!(parse(&text), m.entries);
    }

    #[test]
    fn a_corrupt_cache_costs_a_relearn_not_the_daemon() {
        assert!(parse("").is_empty());
        assert!(parse("not json").is_empty());
        assert!(parse("{").is_empty());
        assert!(parse("{\"nonsense\":1}").is_empty());
        assert!(parse("{\"3,3\":not-a-number}").is_empty());
        assert!(parse("{\"3,3,3\":1}").is_empty());
        assert!(parse("{\"999,3\":1}").is_empty());
        // A truncated write keeps the entries that did land.
        assert_eq!(parse("{\"3,3\":73,\"4,2\":").len(), 1);
    }

    #[test]
    fn parse_accepts_what_the_daemon_writes_with_a_trailing_newline() {
        assert_eq!(parse("{\"3,3\":73}\n").len(), 1);
    }
}
