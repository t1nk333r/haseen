//! What a theme's colors.toml declares for the wipe:
//!
//! ```toml
//! border_wipe = "rgba(F25623ff) rgba(F25623cc) rgba(F2562311) rgba(F25623cc)"
//! border_wipe_seconds = 36
//! ```

use crate::gocompat::path_error;
use std::path::Path;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Theme {
    pub colors: Vec<String>,
    pub seconds: f64,
}

impl Theme {
    /// The declaration is complete: two stops to turn and a pace. One colour
    /// has no visible angle.
    pub fn wants(&self) -> bool {
        self.colors.len() >= 2 && self.seconds > 0.0
    }
}

pub const ERR_BAD_COLOUR: &str =
    "border_wipe: a colour is not rgba(RRGGBBAA), rgb(RRGGBB) or 0xAARRGGBB";

/// Each colour goes into Lua source verbatim, so only the hex forms Hyprland
/// takes are allowed: nothing in colors.toml can turn into code.
fn is_colour(c: &str) -> bool {
    let hex = |s: &str, n: usize| s.len() == n && s.bytes().all(|b| b.is_ascii_hexdigit());
    if let Some(inner) = c.strip_prefix("rgba(").and_then(|r| r.strip_suffix(')')) {
        return hex(inner, 8);
    }
    if let Some(inner) = c.strip_prefix("rgb(").and_then(|r| r.strip_suffix(')')) {
        return hex(inner, 6);
    }
    c.strip_prefix("0x").is_some_and(|h| hex(h, 8))
}

/// Reads the two keys. A missing file or missing keys is an empty Theme, not
/// an error: most themes ask for no wipe.
pub fn read_theme(path: &Path) -> Result<Theme, String> {
    let shown = path.display().to_string();
    let raw = match std::fs::read(path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Theme::default()),
        // A directory opens and fails on the first read, as Go's scanner did.
        Err(e) if e.raw_os_error() == Some(libc::EISDIR) => {
            return Err(path_error("read", &shown, &e))
        }
        Err(e) => return Err(path_error("open", &shown, &e)),
    };
    let text = String::from_utf8_lossy(&raw);
    let mut t = Theme::default();
    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim().trim_matches(|c| c == '"' || c == '\'');
        match key.trim() {
            "border_wipe" => t.colors = value.split_whitespace().map(str::to_string).collect(),
            "border_wipe_seconds" => t.seconds = value.parse().unwrap_or(0.0),
            _ => {}
        }
    }
    if t.colors.iter().any(|c| !is_colour(c)) {
        return Err(ERR_BAD_COLOUR.to_string());
    }
    Ok(t)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sysusage::tests::{write, TempDir};

    pub const WIPE_COLOURS: [&str; 4] = [
        "rgba(F25623ff)",
        "rgba(F25623cc)",
        "rgba(F2562311)",
        "rgba(F25623cc)",
    ];

    #[test]
    fn read_theme_cases() {
        let state = TempDir::new();
        let path = state.0.join("current/theme/colors.toml");

        let th = read_theme(&path).expect("no colors.toml is no error");
        assert!(!th.wants());

        write(&path, "accent = \"#F25623\"\n");
        assert!(
            !read_theme(&path).unwrap().wants(),
            "a theme without the keys asks for a wipe"
        );

        write(&path, "# wipe\nborder_wipe = \"rgba(F25623ff) rgba(F25623cc) rgba(F2562311) rgba(F25623cc)\"\nborder_wipe_seconds = 36\n");
        let th = read_theme(&path).unwrap();
        assert!(th.wants());
        assert_eq!(th.seconds, 36.0);
        assert_eq!(th.colors, WIPE_COLOURS);

        write(
            &path,
            "border_wipe = \"rgba(F25623ff)\"\nborder_wipe_seconds = 36\n",
        );
        assert!(
            !read_theme(&path).unwrap().wants(),
            "one colour has no angle to turn"
        );

        // The colours go into Lua source: anything but hex is refused.
        write(
            &path,
            "border_wipe = \"rgba(F25623ff) os.execute('x')\"\nborder_wipe_seconds = 36\n",
        );
        assert_eq!(read_theme(&path).unwrap_err(), ERR_BAD_COLOUR);
    }

    #[test]
    fn colour_forms() {
        for ok in ["rgba(F25623ff)", "rgb(a1b2c3)", "0xFFAABBCC"] {
            assert!(is_colour(ok), "{ok}");
        }
        for bad in [
            "rgba(F25623f)",
            "rgb(a1b2c3ff)",
            "0xFFAABB",
            "#F25623",
            "rgba(F25623ff))",
            "0XFFAABBCC",
        ] {
            assert!(!is_colour(bad), "{bad}");
        }
    }
}
