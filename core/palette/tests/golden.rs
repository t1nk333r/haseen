//! The Go generator's answers for the corpus (plan 167, phase 3): every
//! line of golden/palettes.txt is what Go's haseen-palette wrote for that
//! image, mode and variant (the clamped selection, then color0..color15),
//! or its error. golden/json.txt is its --json line per image (dark, normal,
//! from a warm cache), golden/png-rgb8-light-pastel.toml one whole
//! colors.toml. Recorded with Go 1.27.3 and golang.org/x/image v0.46.0 on
//! amd64 before the Go code was removed; corpus/generate.py made the
//! images. Every comparison is byte for byte: the decoders, the scaler and
//! the float functions are Go's.

use haseen_palette::anchors::clamp_anchors;
use haseen_palette::generate::{
    extract_dominant_colors, generate_with_cache, seed_hash, Generated,
};
use haseen_palette::modes::{generate_by_mode, normalize_brightness, normalize_counts};
use std::collections::BTreeMap;
use std::path::PathBuf;

fn dir(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join(name)
}

struct Case {
    mode: String,
    light: bool,
    want: String,
}

fn cases() -> BTreeMap<String, Vec<Case>> {
    let text = std::fs::read_to_string(dir("golden").join("palettes.txt")).unwrap();
    let mut by_image: BTreeMap<String, Vec<Case>> = BTreeMap::new();
    for line in text.lines() {
        let mut parts = line.splitn(4, ' ');
        let (file, mode, variant, want) = (
            parts.next().unwrap(),
            parts.next().unwrap(),
            parts.next().unwrap(),
            parts.next().unwrap(),
        );
        by_image.entry(file.to_string()).or_default().push(Case {
            mode: mode.to_string(),
            light: variant == "light",
            want: want.to_string(),
        });
    }
    by_image
}

/// What generate() computes, with the extraction done once per image: the
/// expensive part is the same for every mode.
#[test]
fn every_palette_is_gos() {
    let corpus = dir("corpus");
    let mut checked = 0;
    let mut failures = Vec::new();
    for (file, cases) in cases() {
        let path = corpus.join(&file).display().to_string();
        let extracted = extract_dominant_colors(&path, 48);
        for c in cases {
            let got = match &extracted {
                Ok((dominant, counts)) if dominant.len() >= 8 => {
                    let weights = normalize_counts(counts);
                    let raw = normalize_brightness(generate_by_mode(
                        dominant,
                        weights.as_deref(),
                        c.light,
                        &c.mode,
                    ));
                    let (p, selection) = clamp_anchors(raw, c.light);
                    format!("{selection} {}", p.join(" "))
                }
                // The errors come from the whole command, path and all.
                _ => {
                    let cache = std::env::temp_dir()
                        .join(format!("haseen-palette-golden-{}", std::process::id()));
                    let (_, err) =
                        generate_with_cache(&path, c.light, &c.mode, &cache.display().to_string());
                    let _ = std::fs::remove_dir_all(&cache);
                    let err = err.expect("an error");
                    let prefix = format!("{}/", corpus.display());
                    format!("error haseen-palette: {}", err.replace(&prefix, ""))
                }
            };
            checked += 1;
            if got != c.want {
                failures.push(format!(
                    "{file} {} {}:\n  want {}\n  got  {got}",
                    c.mode,
                    if c.light { "light" } else { "dark" },
                    c.want
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {checked} differ from Go:\n{}",
        failures.len(),
        failures.join("\n")
    );
    assert_eq!(checked, 830);
}

/// The --json line, seed (SHA-256) included, for every image.
#[test]
fn the_json_lines_are_gos() {
    let corpus = dir("corpus");
    let want = std::fs::read_to_string(dir("golden").join("json.txt")).unwrap();
    let mut files: Vec<String> = std::fs::read_dir(&corpus)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|f| !f.ends_with(".py"))
        .collect();
    files.sort();
    let mut got = String::new();
    for file in files {
        let path = corpus.join(&file).display().to_string();
        let line = match extract_dominant_colors(&path, 48) {
            Ok((dominant, counts)) if dominant.len() >= 8 => {
                let weights = normalize_counts(&counts);
                let raw = normalize_brightness(generate_by_mode(
                    &dominant,
                    weights.as_deref(),
                    false,
                    "normal",
                ));
                let (palette, selection) = clamp_anchors(raw, false);
                Generated {
                    seed: seed_hash(&path).unwrap(),
                    mode: "normal".into(),
                    light: false,
                    cached: true,
                    palette,
                    selection,
                }
                .json_line()
            }
            _ => "error".into(),
        };
        got.push_str(&line);
        got.push('\n');
    }
    assert_eq!(got, want);
}

/// One whole colors.toml, through generate() and its cache.
#[test]
fn colors_toml_is_gos() {
    let path = dir("corpus").join("png-rgb8.png").display().to_string();
    let cache = std::env::temp_dir().join(format!("haseen-palette-toml-{}", std::process::id()));
    let cache_s = cache.display().to_string();
    let (first, err) = generate_with_cache(&path, true, "pastel", &cache_s);
    assert!(err.is_none(), "{err:?}");
    let (second, err) = generate_with_cache(&path, true, "pastel", &cache_s);
    let _ = std::fs::remove_dir_all(&cache);
    assert!(err.is_none(), "{err:?}");
    let (first, second) = (first.unwrap(), second.unwrap());
    assert!(!first.cached && second.cached);
    let want = std::fs::read_to_string(dir("golden").join("png-rgb8-light-pastel.toml")).unwrap();
    assert_eq!(first.colors_toml(), want);
    assert_eq!(second.colors_toml(), want);
}
