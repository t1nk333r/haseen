//! One wallpaper to one palette, cached on the image's content hash
//! (generate.go, cache.go, decode.go and x_pixel_sampler.go's entry point).
//!
//! The cache answers one question: has this exact seed already been turned
//! into this exact palette? The key is the image's content, not its path and
//! mtime, so a wallpaper that is copied, re-downloaded or touched costs no
//! regeneration. Entries are per user, under
//! $XDG_CACHE_HOME/haseen/palette/<key>.json, written atomically.

use crate::analysis::DOMINANT_COLORS_TO_EXTRACT;
use crate::anchors::clamp_anchors;
use crate::json::{self, Value};
use crate::modes::{self, Palette};
use crate::{median_cut, sample, sha256};
use std::io::Read;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

/// Changes whenever the generator would give a seed another palette. 2 was
/// the Go generator's corrected OKLab matrix; 3 is this port, so a palette
/// the Go generator cached is never read back as this one's (plan 167).
pub const CACHE_VERSION: i64 = 3;

pub struct Generated {
    pub seed: String,
    pub mode: String,
    pub light: bool,
    pub cached: bool,
    pub palette: Palette,
    /// The surface the shell draws foreground text on.
    pub selection: String,
}

/// An io::Error as Go's os package words it: "<op> <path>: <errno text>".
pub fn path_error(op: &str, path: &str, err: &std::io::Error) -> String {
    format!("{op} {path}: {}", errno_text(err))
}

/// The C library's message, lower-cased first letter, as Go's syscall table
/// has it ("permission denied").
pub fn errno_text(err: &std::io::Error) -> String {
    let Some(code) = err.raw_os_error() else {
        return err.to_string();
    };
    let text = std::io::Error::from_raw_os_error(code).to_string();
    let text = text
        .strip_suffix(&format!(" (os error {code})"))
        .unwrap_or(&text)
        .to_string();
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().collect::<String>() + chars.as_str(),
        None => format!("errno {code}"),
    }
}

/// Go's filepath.Join: empty parts skipped, the result cleaned.
pub fn go_join(parts: &[&str]) -> String {
    let joined: Vec<&str> = parts.iter().copied().filter(|p| !p.is_empty()).collect();
    if joined.is_empty() {
        return String::new();
    }
    clean(&joined.join("/"))
}

/// Go's filepath.Clean.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let rooted = path.starts_with('/');
    let mut out: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if out.last().is_some_and(|p| *p != "..") {
                    out.pop();
                } else if !rooted {
                    out.push("..");
                }
            }
            p => out.push(p),
        }
    }
    let body = out.join("/");
    match (rooted, body.is_empty()) {
        (true, _) => format!("/{body}"),
        (false, true) => ".".into(),
        (false, false) => body,
    }
}

pub fn cache_dir() -> String {
    let var = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());
    if let Some(dir) = var("HASEEN_PALETTE_CACHE") {
        return dir;
    }
    let base = match var("XDG_CACHE_HOME") {
        Some(b) => b,
        // Go's os.UserHomeDir fails without HOME, and then there is no cache.
        None => match var("HOME") {
            Some(home) => go_join(&[&home, ".cache"]),
            None => return String::new(),
        },
    };
    go_join(&[&base, "haseen", "palette"])
}

/// The content hash of the image file.
pub fn seed_hash(path: &str) -> Result<String, String> {
    let mut f = std::fs::File::open(path).map_err(|e| path_error("open", path, &e))?;
    let mut sum = sha256::Sha256::default();
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        match f.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => sum.update(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(path_error("read", path, &e)),
        }
    }
    Ok(sha256::hex(&sum.finish()))
}

pub fn cache_key(seed: &str, mode: &str, light: bool) -> String {
    let variant = if light { "light" } else { "dark" };
    let n = seed.len().min(32);
    format!("{}-{mode}-{variant}-v{CACHE_VERSION}", &seed[..n])
}

fn cache_path(dir: &str, key: &str) -> Option<PathBuf> {
    if dir.is_empty() || key.is_empty() {
        return None;
    }
    Some(PathBuf::from(go_join(&[dir, &format!("{key}.json")])))
}

/// A cached palette, if the entry is this version's and whole. Anything
/// Go's json.Unmarshal would refuse is a miss.
pub fn load_cached(dir: &str, key: &str) -> Option<Palette> {
    let raw = std::fs::read(cache_path(dir, key)?).ok()?;
    let Value::Object(fields) = json::parse(&raw)? else {
        return None;
    };
    let mut version: Option<i64> = None;
    let mut palette: Palette = Default::default();
    // Go matches keys without regard to case; the last of a repeated key wins.
    for (name, value) in &fields {
        match name.to_ascii_lowercase().as_str() {
            "version" => match value {
                Value::Number(text) => version = Some(text.parse().ok()?),
                Value::Null => {}
                _ => return None,
            },
            "seed" | "mode" => {
                if !matches!(value, Value::String(_) | Value::Null) {
                    return None;
                }
            }
            "light" => {
                if !matches!(value, Value::Bool(_) | Value::Null) {
                    return None;
                }
            }
            "palette" => match value {
                Value::Array(items) => {
                    for (i, item) in items.iter().enumerate() {
                        match item {
                            Value::String(s) if i < 16 => palette[i] = s.clone(),
                            Value::String(_) | Value::Null => {}
                            _ => return None,
                        }
                    }
                }
                Value::Null => {}
                _ => return None,
            },
            _ => {}
        }
    }
    if version != Some(CACHE_VERSION) || palette.iter().any(|c| c.is_empty()) {
        return None;
    }
    Some(palette)
}

/// Go's os.MkdirAll with its error text.
fn mkdir_all(dir: &Path, mode: u32) -> Result<(), String> {
    let shown = dir.display().to_string();
    match std::fs::metadata(dir) {
        Ok(m) if m.is_dir() => return Ok(()),
        Ok(_) => {
            return Err(path_error(
                "mkdir",
                &shown,
                &std::io::Error::from_raw_os_error(20), // ENOTDIR
            ));
        }
        Err(_) => {}
    }
    if let Some(parent) = dir.parent().filter(|p| !p.as_os_str().is_empty()) {
        mkdir_all(parent, mode)?;
    }
    match std::fs::DirBuilder::new().mode(mode).create(dir) {
        Ok(()) => Ok(()),
        Err(_) if std::fs::symlink_metadata(dir).is_ok_and(|m| m.is_dir()) => Ok(()),
        Err(e) => Err(path_error("mkdir", &shown, &e)),
    }
}

/// Written to <path>.new, then renamed: a half-written entry is never read
/// back as a palette.
fn save_cached(
    dir: &str,
    key: &str,
    seed: &str,
    mode: &str,
    light: bool,
    palette: &Palette,
) -> Result<(), String> {
    let Some(path) = cache_path(dir, key) else {
        return Ok(());
    };
    if let Some(dir) = path.parent() {
        mkdir_all(dir, 0o700)?;
    }
    let mut text = format!(
        "{{\"version\":{CACHE_VERSION},\"seed\":{},\"mode\":{},\"light\":{light},\"palette\":[",
        json::quote(seed),
        json::quote(mode)
    );
    for (i, c) in palette.iter().enumerate() {
        if i > 0 {
            text.push(',');
        }
        text.push_str(&json::quote(c));
    }
    text.push_str("]}\n");
    let tmp = format!("{}.new", path.display());
    {
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&tmp)
            .map_err(|e| path_error("open", &tmp, &e))?;
        f.write_all(text.as_bytes())
            .map_err(|e| path_error("write", &tmp, &e))?;
    }
    std::fs::rename(&tmp, &path)
        .map_err(|e| format!("rename {tmp} {}: {}", path.display(), errno_text(&e)))
}

/// The palette for one image. The cache holds the generator's own palette;
/// the anchors are clamped on every return, cached or fresh. A palette that
/// could not be cached is still returned, with the error, as Go did.
pub fn generate(image: &str, light: bool, mode: &str) -> (Option<Generated>, Option<String>) {
    generate_with_cache(image, light, mode, &cache_dir())
}

/// generate with the cache directory given ("" for none): tests pass their
/// own instead of setting HASEEN_PALETTE_CACHE across threads.
pub fn generate_with_cache(
    image: &str,
    light: bool,
    mode: &str,
    cache: &str,
) -> (Option<Generated>, Option<String>) {
    let mode = if mode.is_empty() { "normal" } else { mode };
    if !modes::valid_mode(mode) {
        return (
            None,
            Some(format!("unknown extraction mode {}", json::go_quote(mode))),
        );
    }
    let seed = match seed_hash(image) {
        Ok(s) => s,
        Err(e) => return (None, Some(format!("read {image}: {e}"))),
    };
    let key = cache_key(&seed, mode, light);
    let (generated, cached, cache_err) = match load_cached(cache, &key) {
        Some(p) => (p, true, None),
        None => {
            let (dominant, counts) =
                match extract_dominant_colors(image, DOMINANT_COLORS_TO_EXTRACT) {
                    Ok(v) => v,
                    Err(e) => return (None, Some(format!("extract colours: {e}"))),
                };
            if dominant.len() < 8 {
                return (None, Some(format!("not enough colours in {image}")));
            }
            let weights = modes::normalize_counts(&counts);
            let p = modes::normalize_brightness(modes::generate_by_mode(
                &dominant,
                weights.as_deref(),
                light,
                mode,
            ));
            let err = save_cached(cache, &key, &seed, mode, light, &p)
                .err()
                .map(|e| format!("cache palette: {e}"));
            (p, false, err)
        }
    };
    let (palette, selection) = clamp_anchors(generated, light);
    (
        Some(Generated {
            seed,
            mode: mode.to_string(),
            light,
            cached,
            palette,
            selection,
        }),
        cache_err,
    )
}

/// Dominant colours and their pixel counts, most first.
pub fn extract_dominant_colors(image: &str, n: usize) -> Result<(Vec<String>, Vec<usize>), String> {
    let pixels = sample::load_and_sample_pixels(image)?;
    median_cut::extract_from_pixels(&pixels, n)
}

impl Generated {
    /// haseen's (and Omarchy's) theme format: the 16 ANSI slots and the named
    /// keys the templates read. A function of the seed alone, so the same
    /// wallpaper under another name writes the same bytes.
    pub fn colors_toml(&self) -> String {
        let p = &self.palette;
        let q = json::go_quote;
        let mode = if self.light { "light" } else { "dark" };
        let mut b = String::new();
        let short = &self.seed[..self.seed.len().min(16)];
        b.push_str(&format!(
            "# Generated by `haseen theme wallpaper`: seed {short}, {}, {mode}.\n",
            self.mode
        ));
        b.push_str("# Regenerated only when the wallpaper's own seed changes.\n");
        b.push_str(&format!("mode = {}\n\n", q(mode)));
        b.push_str(&format!("accent = {}\n", q(&p[4])));
        b.push_str(&format!("cursor = {}\n", q(&p[7])));
        b.push_str(&format!("selection = {}\n", q(&self.selection)));
        b.push_str(&format!("selection_foreground = {}\n", q(&p[0])));
        b.push_str(&format!(
            "selection_background = {}\n\n",
            q(&self.selection)
        ));
        b.push_str(&format!("background = {}\n", q(&p[0])));
        b.push_str(&format!("foreground = {}\n\n", q(&p[7])));
        for (i, c) in p.iter().enumerate() {
            b.push_str(&format!("color{i} = {}\n", q(c)));
        }
        b
    }

    /// The --json line: `cached` says whether this wallpaper cost any work.
    pub fn json_line(&self) -> String {
        let q = json::go_quote;
        let mut s = format!(
            "{{\"seed\":{},\"mode\":{},\"light\":{},\"cached\":{},\"palette\":[",
            q(&self.seed),
            q(&self.mode),
            self.light,
            self.cached
        );
        for (i, c) in self.palette.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push_str(&q(c));
        }
        s.push_str("]}");
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_is_gos() {
        for (input, want) in [
            ("", "."),
            ("/", "/"),
            ("a//b/./c/..", "a/b"),
            ("/../x", "/x"),
            ("../../x", "../../x"),
            ("/srv/u/.cache/", "/srv/u/.cache"),
        ] {
            assert_eq!(clean(input), want, "{input}");
        }
        assert_eq!(go_join(&["", "a", "", "b/"]), "a/b");
    }

    #[test]
    fn the_key_holds_the_version() {
        assert_eq!(
            cache_key(&"ab".repeat(32), "normal", true),
            format!("{}-normal-light-v3", "ab".repeat(16))
        );
    }
}

/// Go's palette_test.go.
#[cfg(test)]
mod go_tests {
    use super::*;
    use crate::testutil::{write_png, TempDir};

    /// A few flat bands: enough for the extractor's dominant colours.
    fn write_bands(path: &str, bands: &[[u8; 3]]) {
        let height = 120 / bands.len();
        write_png(Path::new(path), 120, 120, |_, y| {
            let b = bands[(y / height).min(bands.len() - 1)];
            [b[0], b[1], b[2], 255]
        });
    }

    fn sample_image(dir: &TempDir, name: &str) -> String {
        let path = dir.path(name);
        write_bands(
            &path,
            &[[18, 22, 40], [190, 80, 70], [60, 140, 120], [230, 210, 150]],
        );
        path
    }

    fn run(image: &str, light: bool, mode: &str, cache: &str) -> Generated {
        let (r, err) = generate_with_cache(image, light, mode, cache);
        assert!(err.is_none(), "{image} {mode}: {err:?}");
        r.expect("a palette")
    }

    #[test]
    fn generate_is_cached_by_seed() {
        let dir = TempDir::new("cached");
        let cache = dir.path("cache");
        let image = sample_image(&dir, "wall.png");
        let first = run(&image, false, "normal", &cache);
        assert!(!first.cached, "the first run cannot be a cache hit");
        for (i, c) in first.palette.iter().enumerate() {
            assert!(
                c.starts_with('#') && c.len() == 7,
                "colour {i} = {c:?}, want #rrggbb"
            );
        }
        let second = run(&image, false, "normal", &cache);
        assert!(second.cached, "the same seed must come from the cache");
        assert_eq!(
            second.palette, first.palette,
            "the cached palette differs from the generated one"
        );
    }

    #[test]
    fn seed_follows_content_not_path() {
        let dir = TempDir::new("seed");
        let cache = dir.path("cache");
        let original = sample_image(&dir, "wall.png");
        let first = run(&original, false, "normal", &cache);
        let copied = dir.path("copy-with-another-name.png");
        std::fs::copy(&original, &copied).unwrap();
        let again = run(&copied, false, "normal", &cache);
        assert!(
            again.cached,
            "a copy of the same image regenerated the palette"
        );
        assert_eq!(again.seed, first.seed);
    }

    #[test]
    fn different_image_and_mode_are_different_seeds() {
        let dir = TempDir::new("different");
        let cache = dir.path("cache");
        let first = sample_image(&dir, "a.png");
        let other = dir.path("b.png");
        write_bands(
            &other,
            &[[240, 240, 240], [20, 60, 200], [10, 10, 10], [120, 200, 90]],
        );
        let a = run(&first, false, "normal", &cache);
        let b = run(&other, false, "normal", &cache);
        assert!(
            !b.cached && a.seed != b.seed,
            "a different image must be a different seed"
        );
        assert_ne!(
            a.palette, b.palette,
            "two different images produced the same palette"
        );
        // The mode and light/dark are part of the key, not just the image.
        assert!(
            !run(&first, true, "normal", &cache).cached,
            "light mode reused the dark cache entry"
        );
        assert!(
            !run(&first, false, "monochromatic", &cache).cached,
            "another extraction mode reused the cache entry"
        );
    }

    #[test]
    fn unknown_mode_and_missing_image() {
        let dir = TempDir::new("unknown");
        let cache = dir.path("cache");
        let image = sample_image(&dir, "wall.png");
        let (_, err) = generate_with_cache(&image, false, "nonsense", &cache);
        assert_eq!(err.as_deref(), Some("unknown extraction mode \"nonsense\""));
        let missing = dir.path("missing.png");
        let (_, err) = generate_with_cache(&missing, false, "normal", &cache);
        assert_eq!(
            err.unwrap(),
            format!("read {missing}: open {missing}: no such file or directory")
        );
    }

    /// A file that is not an image fails before any pixel is allocated.
    #[test]
    fn refuses_non_images() {
        let dir = TempDir::new("nonimage");
        let path = dir.path("not-an-image.png");
        std::fs::write(&path, "certainly not a png").unwrap();
        let (_, err) = generate_with_cache(&path, false, "normal", &dir.path("cache"));
        assert_eq!(
            err.as_deref(),
            Some("extract colours: failed to decode image: decode image header: image: unknown format")
        );
    }

    /// colors.toml: the 16 ANSI slots plus the named keys the templates read.
    #[test]
    fn colors_toml() {
        let dir = TempDir::new("toml");
        let result = run(
            &sample_image(&dir, "wall.png"),
            false,
            "normal",
            &dir.path("cache"),
        );
        let out = result.colors_toml();
        for key in [
            "mode = \"dark\"",
            "accent = ",
            "cursor = ",
            "selection = ",
            "background = ",
            "foreground = ",
            "color0 = ",
            "color15 = ",
        ] {
            assert!(out.contains(key), "colors.toml is missing {key:?}");
        }
        assert_eq!(out.matches("\ncolor").count(), 16);
        assert!(
            out.contains(&result.palette[0]),
            "the background colour is not in the output"
        );
        // The clamped selection, not a fresh derivation, is what gets written.
        assert!(out.contains(&format!(
            "\nselection_background = \"{}\"",
            result.selection
        )));
    }

    /// A cache entry the Go generator wrote (version 2) is not read back.
    #[test]
    fn a_go_cache_entry_is_regenerated() {
        let dir = TempDir::new("gocache");
        let cache = dir.path("cache");
        let image = sample_image(&dir, "wall.png");
        let first = run(&image, false, "normal", &cache);
        let seed = &first.seed;
        let go_key = format!("{}-normal-dark-v2", &seed[..32]);
        std::fs::write(
            Path::new(&cache).join(format!("{go_key}.json")),
            format!("{{\"version\":2,\"seed\":\"{seed}\",\"mode\":\"normal\",\"light\":false,\"palette\":[{}]}}\n",
                vec!["\"#123456\""; 16].join(",")),
        )
        .unwrap();
        std::fs::remove_file(
            Path::new(&cache).join(format!("{}.json", cache_key(seed, "normal", false))),
        )
        .unwrap();
        let again = run(&image, false, "normal", &cache);
        assert!(!again.cached, "a version 2 entry was read");
        assert_eq!(again.palette, first.palette);
        // And a version 3 entry with the wrong version number inside is a miss.
        let key = cache_key(seed, "normal", false);
        let path = Path::new(&cache).join(format!("{key}.json"));
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.starts_with("{\"version\":3,"), "{text}");
        std::fs::write(&path, text.replace("\"version\":3", "\"version\":2")).unwrap();
        assert!(load_cached(&cache, &key).is_none());
    }

    #[test]
    fn a_cache_that_cannot_be_written_is_an_error_after_the_palette() {
        let dir = TempDir::new("nocache");
        let image = sample_image(&dir, "wall.png");
        let blocker = dir.path("file");
        std::fs::write(&blocker, "").unwrap();
        let cache = format!("{blocker}/cache");
        let (r, err) = generate_with_cache(&image, false, "normal", &cache);
        assert!(r.is_some());
        assert_eq!(
            err.unwrap(),
            format!("cache palette: mkdir {blocker}: not a directory")
        );
    }
}
