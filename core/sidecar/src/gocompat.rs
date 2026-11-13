//! What the Go daemon got from its standard library and the wire, flags and
//! logs still show: Go's duration text, filepath.Join and the error strings of
//! its os and net packages (plan 167).

use std::path::PathBuf;
use std::time::Duration;

/// Go's time.ParseDuration: an optional sign, then one or more decimal numbers
/// each with a unit (`ns us µs μs ms s m h`), or a bare `0`. Returns
/// nanoseconds; a negative value is allowed (it disables the idle exit).
pub fn parse_duration(text: &str) -> Option<i64> {
    let mut s = text;
    let mut neg = false;
    if let Some(rest) = s.strip_prefix('-') {
        neg = true;
        s = rest;
    } else if let Some(rest) = s.strip_prefix('+') {
        s = rest;
    }
    if s == "0" {
        return Some(0);
    }
    if s.is_empty() {
        return None;
    }
    let mut total: f64 = 0.0;
    while !s.is_empty() {
        let digits = s
            .find(|c: char| !(c.is_ascii_digit() || c == '.'))
            .unwrap_or(s.len());
        let number = &s[..digits];
        if number.is_empty() || number == "." || number.matches('.').count() > 1 {
            return None;
        }
        let value: f64 = number.parse().ok()?;
        s = &s[digits..];
        let unit_len = s
            .find(|c: char| c.is_ascii_digit() || c == '.')
            .unwrap_or(s.len());
        let unit = match &s[..unit_len] {
            "ns" => 1.0,
            "us" | "µs" | "μs" => 1e3,
            "ms" => 1e6,
            "s" => 1e9,
            "m" => 60e9,
            "h" => 3600e9,
            _ => return None,
        };
        s = &s[unit_len..];
        total += value * unit;
    }
    if total > i64::MAX as f64 {
        return None;
    }
    let ns = total.round() as i64;
    Some(if neg { -ns } else { ns })
}

/// Go's Duration.String: `5m0s`, `1.5s`, `500ms`, `0s`.
pub fn format_duration(ns: i64) -> String {
    if ns == 0 {
        return "0s".to_string();
    }
    let neg = ns < 0;
    let u = ns.unsigned_abs();
    let mut out = String::new();
    if u < 1_000_000_000 {
        // Below a second: one unit, with a fraction.
        let (unit, div) = if u < 1_000 {
            ("ns", 1)
        } else if u < 1_000_000 {
            ("µs", 1_000)
        } else {
            ("ms", 1_000_000)
        };
        out.push_str(&fraction(u, div));
        out.push_str(unit);
    } else {
        let secs = u / 1_000_000_000;
        let frac = u % 1_000_000_000;
        let h = secs / 3600;
        let m = (secs / 60) % 60;
        let s = secs % 60;
        if h > 0 {
            out.push_str(&format!("{h}h{m}m"));
        } else if m > 0 {
            out.push_str(&format!("{m}m"));
        }
        out.push_str(&fraction(s * 1_000_000_000 + frac, 1_000_000_000));
        out.push('s');
    }
    if neg {
        out.insert(0, '-');
    }
    out
}

/// v / div with the fraction's trailing zeros dropped.
fn fraction(v: u64, div: u64) -> String {
    let whole = v / div;
    let mut rest = v % div;
    if rest == 0 {
        return whole.to_string();
    }
    let mut width = div.to_string().len() - 1;
    while rest.is_multiple_of(10) {
        rest /= 10;
        width -= 1;
    }
    format!("{whole}.{rest:0width$}")
}

/// Go's path.Clean on bytes: one slash between elements, `.` dropped, `..`
/// taken back, no trailing slash.
pub fn clean(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let rooted = path[0] == b'/';
    let mut parts: Vec<&[u8]> = Vec::new();
    for part in path.split(|&b| b == b'/') {
        match part {
            b"" | b"." => {}
            b".." => {
                if parts.last().is_some_and(|p| *p != b"..") {
                    parts.pop();
                } else if !rooted {
                    parts.push(part);
                }
            }
            _ => parts.push(part),
        }
    }
    let mut out = Vec::with_capacity(path.len());
    if rooted {
        out.push(b'/');
    }
    for (i, part) in parts.iter().enumerate() {
        if i > 0 {
            out.push(b'/');
        }
        out.extend_from_slice(part);
    }
    if out.is_empty() {
        out.push(b'.');
    }
    out
}

/// Go's filepath.Join for two elements, as the sampler builds paths under
/// `--root`: an empty root leaves the path alone (cleaned).
pub fn join(root: &[u8], path: &[u8]) -> PathBuf {
    use std::os::unix::ffi::OsStringExt;
    let joined = if root.is_empty() {
        clean(path)
    } else {
        let mut both = root.to_vec();
        both.push(b'/');
        both.extend_from_slice(path);
        clean(&both)
    };
    PathBuf::from(std::ffi::OsString::from_vec(joined))
}

/// The text Go's syscall.Errno prints: the C library's message with a lower
/// case first letter ("permission denied", "invalid argument").
pub fn errno_text(errno: i32) -> String {
    // SAFETY: strerror returns a pointer to a static or thread-local string.
    let msg = unsafe {
        let p = libc::strerror(errno);
        if p.is_null() {
            return format!("errno {errno}");
        }
        std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
    };
    let mut chars = msg.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().collect::<String>() + chars.as_str(),
        None => format!("errno {errno}"),
    }
}

/// An io::Error as Go words it: "<op> <path>: <errno text>".
pub fn path_error(op: &str, path: &str, err: &std::io::Error) -> String {
    match err.raw_os_error() {
        Some(errno) => format!("{op} {path}: {}", errno_text(errno)),
        None => format!("{op} {path}: {err}"),
    }
}

/// Sleeps-free helper for the idle exit: a Duration from Go nanoseconds,
/// None for zero or less (never).
pub fn positive(ns: i64) -> Option<Duration> {
    (ns > 0).then(|| Duration::from_nanos(ns as u64))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duration_parser_is_gos() {
        assert_eq!(parse_duration("0"), Some(0));
        assert_eq!(parse_duration("5m"), Some(300_000_000_000));
        assert_eq!(parse_duration("1h30m"), Some(5_400_000_000_000));
        assert_eq!(parse_duration("1.5s"), Some(1_500_000_000));
        assert_eq!(parse_duration("300ms"), Some(300_000_000));
        assert_eq!(parse_duration("2µs"), Some(2_000));
        assert_eq!(parse_duration("-1s"), Some(-1_000_000_000));
        assert_eq!(parse_duration(""), None);
        assert_eq!(parse_duration("5"), None);
        assert_eq!(parse_duration("abc"), None);
        assert_eq!(parse_duration("1x"), None);
    }

    // What Go printed for the same durations.
    #[test]
    fn duration_text_is_gos() {
        assert_eq!(format_duration(300_000_000_000), "5m0s");
        assert_eq!(format_duration(1_000_000_000), "1s");
        assert_eq!(format_duration(1_500_000_000), "1.5s");
        assert_eq!(format_duration(500_000_000), "500ms");
        assert_eq!(format_duration(7_203_000_000_000), "2h0m3s");
        assert_eq!(format_duration(0), "0s");
        assert_eq!(format_duration(1), "1ns");
        assert_eq!(format_duration(1_500), "1.5µs");
        assert_eq!(format_duration(1_500_000), "1.5ms");
        assert_eq!(format_duration(-1_000_000_000), "-1s");
    }

    #[test]
    fn join_cleans_like_filepath() {
        assert_eq!(join(b"", b"/proc/stat"), PathBuf::from("/proc/stat"));
        assert_eq!(
            join(b"/tmp/x/", b"/proc/stat"),
            PathBuf::from("/tmp/x/proc/stat")
        );
        assert_eq!(join(b"/tmp/x", b"/"), PathBuf::from("/tmp/x"));
        assert_eq!(join(b"", b"/"), PathBuf::from("/"));
        assert_eq!(join(b"r", b"/a/../b/./c"), PathBuf::from("r/b/c"));
    }

    #[test]
    fn errno_text_is_lower_case() {
        assert_eq!(errno_text(libc::EACCES), "permission denied");
        assert_eq!(errno_text(libc::EINVAL), "invalid argument");
    }
}
