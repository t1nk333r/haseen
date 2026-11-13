//! Hyprland's two sockets: the request socket, which answers one request per
//! connection and then closes (connect, send, receive, close, as hyprctl
//! does), and the event socket.

use crate::json::{parse, Value};
use std::io::{ErrorKind, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Hyprland's request socket and event socket for one instance.
pub fn socket_paths(runtime_dir: &Path, signature: &str) -> (PathBuf, PathBuf) {
    let dir = crate::gocompat::join(
        std::os::unix::ffi::OsStrExt::as_bytes(runtime_dir.as_os_str()),
        format!("hypr/{signature}").as_bytes(),
    );
    (dir.join(".socket.sock"), dir.join(".socket2.sock"))
}

pub const REQ_ANIMATIONS: &[u8] = b"j/animations";
pub const REQ_ANIMATIONS_ON: &[u8] = b"j/getoption animations:enabled";
pub const REQ_ACTIVE_WINDOW: &[u8] = b"j/activewindow";
pub const REQ_RELOAD: &[u8] = b"reload";

const TIMEOUT: Duration = Duration::from_secs(2);

/// A send or receive that took longer than two seconds: a Hyprland that is
/// stuck, which counts as not answering.
pub const ERR_TIMEOUT: &str = "hyprland did not answer within 2 s";

pub struct Hypr {
    path: PathBuf,
    reply: Vec<u8>,
}

impl Hypr {
    pub fn new(path: PathBuf) -> Hypr {
        Hypr {
            path,
            reply: Vec::with_capacity(512),
        }
    }

    /// Sends `msg` and returns the whole answer, in a buffer the next call
    /// reuses.
    pub fn request(&mut self, msg: &[u8]) -> Result<&[u8], String> {
        let timed_out =
            |e: &std::io::Error| matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut);
        let mut conn = UnixStream::connect(&self.path).map_err(|e| e.to_string())?;
        let _ = conn.set_read_timeout(Some(TIMEOUT));
        let _ = conn.set_write_timeout(Some(TIMEOUT));
        if let Err(e) = conn.write_all(msg) {
            return Err(if timed_out(&e) {
                ERR_TIMEOUT.to_string()
            } else {
                e.to_string()
            });
        }
        self.reply.clear();
        if let Err(e) = conn.read_to_end(&mut self.reply) {
            return Err(if timed_out(&e) {
                ERR_TIMEOUT.to_string()
            } else {
                e.to_string()
            });
        }
        Ok(&self.reply)
    }
}

/// Go's message for a JSON value that does not fit the type it was read into.
fn cannot(v: &Value, into: &str) -> String {
    format!(
        "json: cannot unmarshal {} into Go value of type {into}",
        v.kind()
    )
}

/// Hyprland's borderangle animation already turns the border: the leaf exists,
/// is enabled and loops. A leaf that is not overridden takes everything from
/// `global`. A build without the leaf has no native wipe at all.
///
/// `hyprctl -j animations` is [[leaves...], [curves...]]; a flat list of
/// leaves is read too.
pub fn native_loop(reply: &[u8]) -> Result<bool, String> {
    let doc = parse(reply)?;
    let items = match &doc {
        Value::Array(items) => items,
        // Go read `null` as an empty list: no leaf, no native loop.
        Value::Null => return Ok(false),
        other => return Err(cannot(other, "[]json.RawMessage")),
    };
    let leaves_value = match items.first() {
        Some(first @ Value::Array(_)) => first,
        _ => &doc,
    };
    let Value::Array(raw_leaves) = leaves_value else {
        return Err(cannot(leaves_value, "[]borderwipe.leaf"));
    };
    struct Leaf {
        name: String,
        overridden: bool,
        enabled: bool,
        style: String,
    }
    let mut leaves = Vec::with_capacity(raw_leaves.len());
    for (i, v) in raw_leaves.iter().enumerate() {
        let mut leaf = Leaf {
            name: String::new(),
            overridden: false,
            enabled: false,
            style: String::new(),
        };
        match v {
            Value::Null => {}
            Value::Object(fields) => {
                for (key, value) in fields {
                    let field = |want: &str| key.eq_ignore_ascii_case(want);
                    let wrong = |ty: &str| {
                        format!(
                            "json: cannot unmarshal {} into Go struct field leaf.{}.{} of type {ty}",
                            value.kind(),
                            i,
                            key.to_ascii_lowercase()
                        )
                    };
                    if field("name") || field("style") {
                        let s = match value {
                            Value::String(s) => s.clone(),
                            Value::Null => continue,
                            _ => return Err(wrong("string")),
                        };
                        if field("name") {
                            leaf.name = s;
                        } else {
                            leaf.style = s;
                        }
                    } else if field("overridden") || field("enabled") {
                        let b = match value {
                            Value::Bool(b) => *b,
                            Value::Null => continue,
                            _ => return Err(wrong("bool")),
                        };
                        if field("overridden") {
                            leaf.overridden = b;
                        } else {
                            leaf.enabled = b;
                        }
                    }
                }
            }
            other => return Err(cannot(other, "borderwipe.leaf")),
        }
        leaves.push(leaf);
    }
    let angle = leaves.iter().rposition(|l| l.name == "borderangle");
    let global = leaves.iter().rposition(|l| l.name == "global");
    let Some(mut angle) = angle else {
        return Ok(false);
    };
    if !leaves[angle].overridden {
        if let Some(g) = global {
            angle = g;
        }
    }
    let leaf = &leaves[angle];
    Ok(leaf.enabled && leaf.style.starts_with("loop"))
}

/// `j/getoption animations:enabled`: {"bool": true} on Hyprland 0.56,
/// {"int": 1} on older builds.
pub fn animations_on(reply: &[u8]) -> Result<bool, String> {
    let doc = parse(reply)?;
    let fields = match &doc {
        Value::Object(fields) => fields.as_slice(),
        Value::Null => &[],
        other => {
            return Err(cannot(
                other,
                "struct { Bool *bool \"json:\\\"bool\\\"\"; Int *int \"json:\\\"int\\\"\" }",
            ))
        }
    };
    let (mut b, mut n): (Option<bool>, Option<i64>) = (None, None);
    for (key, value) in fields {
        if key.eq_ignore_ascii_case("bool") {
            match value {
                Value::Bool(v) => b = Some(*v),
                Value::Null => b = None,
                other => {
                    return Err(format!(
                        "json: cannot unmarshal {} into Go struct field .bool of type bool",
                        other.kind()
                    ))
                }
            }
        } else if key.eq_ignore_ascii_case("int") {
            match value {
                Value::Number(text) => match text.parse::<i64>() {
                    Ok(v) => n = Some(v),
                    Err(_) => return Err(format!("json: cannot unmarshal number {text} into Go struct field .int of type int")),
                },
                Value::Null => n = None,
                other => return Err(format!("json: cannot unmarshal {} into Go struct field .int of type int", other.kind())),
            }
        }
    }
    match (b, n) {
        (Some(v), _) => Ok(v),
        (None, Some(v)) => Ok(v != 0),
        (None, None) => Err("animations:enabled: no value in the answer".to_string()),
    }
}

/// `j/activewindow`: `{}` when no window has focus.
pub fn has_focus(reply: &[u8]) -> bool {
    reply.windows(9).any(|w| w == b"\"address\"")
}

/// One line of Hyprland's event socket the loop cares about.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Event {
    /// configreloaded: the theme may have changed.
    Reload,
    /// activewindowv2: whether a window has focus now.
    Focus(bool),
    /// The event socket closed: Hyprland went away.
    Gone,
}

/// The longest event line, as the Go daemon's scanner allowed.
const MAX_LINE: usize = 64 * 1024;

/// Reads the event socket until it closes, then reports Gone. Only
/// configreloaded and activewindowv2 matter. `send` returns false when the
/// loop no longer listens.
pub fn watch_events(mut conn: UnixStream, mut send: impl FnMut(Event) -> bool) {
    let mut buf: Vec<u8> = Vec::with_capacity(1024);
    let mut chunk = [0u8; 4096];
    loop {
        let n = match conn.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => n,
        };
        buf.extend_from_slice(&chunk[..n]);
        while let Some(nl) = buf.iter().position(|&b| b == b'\n') {
            let mut line = &buf[..nl];
            if line.last() == Some(&b'\r') {
                line = &line[..line.len() - 1];
            }
            if let Some(event) = parse_event(line) {
                if !send(event) {
                    return;
                }
            }
            buf.drain(..=nl);
        }
        if buf.len() >= MAX_LINE {
            send(Event::Gone);
            return;
        }
    }
    // The last line may end without a newline.
    if !buf.is_empty() {
        if let Some(event) = parse_event(&buf) {
            if !send(event) {
                return;
            }
        }
    }
    send(Event::Gone);
}

fn parse_event(line: &[u8]) -> Option<Event> {
    let sep = line.windows(2).position(|w| w == b">>")?;
    let (name, data) = (&line[..sep], &line[sep + 2..]);
    match name {
        b"configreloaded" => Some(Event::Reload),
        b"activewindowv2" => Some(Event::Focus(!data.is_empty() && data != b",")),
        _ => None,
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// Hyprland 0.56.2's `hyprctl -j animations`, cut to the leaves that
    /// matter.
    pub fn animations_json(angle: &str) -> String {
        format!(
            r#"[[
{{"name": "global", "overridden": true, "bezier": "haseenOut", "enabled": true, "speed": 4.00, "style": ""}},
{{"name": "border", "overridden": true, "bezier": "default", "enabled": false, "speed": 1.00, "style": ""}},
{angle}
],[{{"name": "linear", "X0": 0.00, "Y0": 0.00, "X1": 1.00, "Y1": 1.00}}]]"#
        )
    }

    pub const ANGLE_LOOP: &str = r#"{"name": "borderangle", "overridden": true, "bezier": "linear", "enabled": true, "speed": 100.00, "style": "loop"}"#;
    pub const ANGLE_OFF: &str = r#"{"name": "borderangle", "overridden": true, "bezier": "default", "enabled": false, "speed": 1.00, "style": ""}"#;
    const ANGLE_INHERITS: &str = r#"{"name": "borderangle", "overridden": false, "bezier": "", "enabled": true, "speed": 0.00, "style": "loop"}"#;
    const ANGLE_MISSING: &str = r#"{"name": "fadeIn", "overridden": false, "bezier": "", "enabled": true, "speed": 0.00, "style": ""}"#;

    #[test]
    fn native_loop_cases() {
        // Not overridden: the leaf's own fields are not in force, global's
        // are, and global does not loop. A build without the leaf has no
        // native wipe.
        for (leaf, want) in [
            (ANGLE_LOOP, true),
            (ANGLE_OFF, false),
            (ANGLE_INHERITS, false),
            (ANGLE_MISSING, false),
        ] {
            assert_eq!(
                native_loop(animations_json(leaf).as_bytes()),
                Ok(want),
                "{leaf}"
            );
        }
        assert!(
            native_loop(b"unknown request").is_err(),
            "an answer that is not JSON is an error"
        );
        assert_eq!(
            native_loop(b"{}").unwrap_err(),
            "json: cannot unmarshal object into Go value of type []json.RawMessage"
        );
    }

    #[test]
    fn option_and_focus_answers() {
        for (reply, want) in [
            (
                r#"{"option": "animations:enabled", "bool": true, "set": false }"#,
                true,
            ),
            (
                r#"{"option": "animations:enabled", "bool": false, "set": true }"#,
                false,
            ),
            (
                r#"{"option": "animations:enabled", "int": 1, "set": false }"#,
                true,
            ),
        ] {
            assert_eq!(animations_on(reply.as_bytes()), Ok(want), "{reply}");
        }
        assert_eq!(
            animations_on(b"{}").unwrap_err(),
            "animations:enabled: no value in the answer"
        );
        assert!(!has_focus(b"{}"));
        assert!(has_focus(br#"{"address": "0x55d0", "class": "foot"}"#));
    }

    #[test]
    fn events_that_matter() {
        assert_eq!(parse_event(b"configreloaded>>"), Some(Event::Reload));
        assert_eq!(
            parse_event(b"activewindowv2>>55d0a1b2c3"),
            Some(Event::Focus(true))
        );
        assert_eq!(parse_event(b"activewindowv2>>"), Some(Event::Focus(false)));
        assert_eq!(parse_event(b"activewindowv2>>,"), Some(Event::Focus(false)));
        assert_eq!(parse_event(b"workspace>>2"), None);
        assert_eq!(parse_event(b"configreloaded"), None);
    }
}
