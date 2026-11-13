//! The last step before colors.toml: the foreground, the accent and the
//! selection are moved, by the least lightness that does it, until they read
//! against the background (anchors.go).

use crate::analysis::generate_bright_version;
use crate::color::{self, OkLch};
use crate::gomath;
use crate::modes::Palette;

/// Foreground text and the shell's text on `selection` are body text (WCAG
/// AA, 4.5:1); the accent marks focus rings and icons (WCAG 1.4.11, 3:1).
pub const MIN_TEXT_CONTRAST: f64 = 4.5;
pub const MIN_ACCENT_CONTRAST: f64 = 3.0;

pub const SLOT_BACKGROUND: usize = 0;
pub const SLOT_ACCENT: usize = 4;
pub const SLOT_FOREGROUND: usize = 7;

/// The selection before the clamp: a surface step off the background.
pub fn base_selection(bg: &str, light: bool) -> String {
    if light {
        color::darken_rgb(bg, 85.0)
    } else {
        color::lighten_rgb(bg, 10.0)
    }
}

/// The background stays; foreground and accent move until they meet their
/// floor (taking their bright slot with them), and the selection is derived
/// and moved until text on it reads. Idempotent.
pub fn clamp_anchors(mut p: Palette, light: bool) -> (Palette, String) {
    let bg = p[SLOT_BACKGROUND].clone();
    for (slot, target) in [
        (SLOT_FOREGROUND, MIN_TEXT_CONTRAST),
        (SLOT_ACCENT, MIN_ACCENT_CONTRAST),
    ] {
        let c = clamp_contrast(&p[slot], &bg, target);
        if c != p[slot] {
            p[slot + 8] = generate_bright_version(&c);
            p[slot] = c;
        }
    }
    let selection = clamp_contrast(
        &base_selection(&bg, light),
        &p[SLOT_FOREGROUND],
        MIN_TEXT_CONTRAST,
    );
    (p, selection)
}

/// Moves hex's OKLab lightness, hue kept, by the least amount that brings its
/// contrast against reference up to target, by bisection toward whichever
/// end (white or black) has more contrast against it.
pub fn clamp_contrast(hex: &str, reference: &str, target: f64) -> String {
    if color::contrast_ratio(hex, reference) >= target {
        return hex.to_string();
    }
    let lch = color::hex_to_oklch(hex);
    let ref_l = color::hex_to_oklab(reference).l;
    let (mut near, mut far) = (gomath::min(lch.l, ref_l), 0.0);
    if color::contrast_ratio(reference, "#ffffff") >= color::contrast_ratio(reference, "#000000") {
        near = gomath::max(lch.l, ref_l);
        far = 1.0;
    }
    let at = |l: f64| {
        color::oklch_to_hex(fit_chroma(OkLch {
            l,
            c: lch.c,
            h: lch.h,
        }))
    };
    let mut best = at(far);
    // 24 halvings resolve L far below one 8-bit step.
    for _ in 0..24 {
        let mid = (near + far) / 2.0;
        let c = at(mid);
        if color::contrast_ratio(&c, reference) >= target {
            far = mid;
            best = c;
        } else {
            near = mid;
        }
    }
    best
}

/// Lowers chroma only as far as it must to land inside sRGB; clipping
/// channels would shift the hue.
pub fn fit_chroma(mut lch: OkLch) -> OkLch {
    if in_gamut(lch) {
        return lch;
    }
    let (mut lo, mut hi) = (0.0, lch.c);
    for _ in 0..20 {
        let mid = (lo + hi) / 2.0;
        if in_gamut(OkLch {
            l: lch.l,
            c: mid,
            h: lch.h,
        }) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    lch.c = lo;
    lch
}

pub fn in_gamut(lch: OkLch) -> bool {
    const EPS: f64 = 1e-6; // matrix round-off at the gamut edge, e.g. white
    let (r, g, b) = color::oklab_to_linear_rgb(color::oklch_to_oklab(lch));
    (-EPS..=1.0 + EPS).contains(&r)
        && (-EPS..=1.0 + EPS).contains(&g)
        && (-EPS..=1.0 + EPS).contains(&b)
}

/// Go's anchors_test.go.
#[cfg(test)]
mod go_tests {
    use super::*;
    use crate::color::{hex_to_oklab, hex_to_oklch, hsl_to_rgb, oklab_to_hex, oklch_to_hex};
    use crate::generate::{cache_key, generate_with_cache, load_cached};
    use crate::modes::{MODES, MOODS};
    use crate::testutil::{write_png, TempDir};
    use std::path::Path;

    fn all_modes() -> Vec<&'static str> {
        MODES.iter().chain(MOODS.iter()).copied().collect()
    }

    type Pix = fn(usize, usize) -> [u8; 4];

    fn rgb(h: f64, s: f64, l: f64) -> [u8; 4] {
        let c = hsl_to_rgb(h, s, l);
        // Go's uint8(float) truncates.
        [c.r as u8, c.g as u8, c.b as u8, 255]
    }

    fn hue_wash(x: usize, y: usize, lo: f64, span: f64) -> [u8; 4] {
        rgb(x as f64 * 360.0 / 96.0, 15.0, lo + y as f64 * span / 96.0)
    }

    /// Wallpapers that leave the generator little contrast to work with.
    const LOW_CONTRAST: [(&str, Pix); 5] = [
        ("mid-grey", |x, y| {
            let v = (118 + (x + y) % 22) as u8;
            [v, v, v + (x % 3) as u8, 255]
        }),
        ("pastel", |x, y| {
            rgb(x as f64 * 360.0 / 96.0, 35.0, 82.0 + (y % 8) as f64)
        }),
        ("mid-tone", |x, y| {
            rgb(
                (x * 3 + y) as f64 * 360.0 / 384.0,
                30.0,
                45.0 + (y % 10) as f64,
            )
        }),
        ("grey-wash", |x, y| hue_wash(x, y, 42.5, 15.0)),
        ("pale-wash", |x, y| hue_wash(x, y, 40.0, 40.0)),
    ];

    fn assert_readable(p: &Palette, selection: &str, what: &str) {
        let (bg, fg, accent) = (&p[SLOT_BACKGROUND], &p[SLOT_FOREGROUND], &p[SLOT_ACCENT]);
        let c = color::contrast_ratio(fg, bg);
        assert!(
            c >= MIN_TEXT_CONTRAST,
            "{what}: foreground {fg} on background {bg}: {c:.2}:1"
        );
        let c = color::contrast_ratio(accent, bg);
        assert!(
            c >= MIN_ACCENT_CONTRAST,
            "{what}: accent {accent} on background {bg}: {c:.2}:1"
        );
        let c = color::contrast_ratio(fg, selection);
        assert!(
            c >= MIN_TEXT_CONTRAST,
            "{what}: foreground {fg} on selection {selection}: {c:.2}:1"
        );
    }

    /// OKLab hue difference 2·√(C1·C2)·sin(Δh/2).
    fn hue_shift(a: &str, b: &str) -> f64 {
        let (x, y) = (hex_to_oklch(a), hex_to_oklch(b));
        2.0 * (x.c * y.c).sqrt() * ((x.h - y.h) * std::f64::consts::PI / 360.0).sin().abs()
    }

    const MAX_HUE_SHIFT: f64 = 0.01;

    #[test]
    fn generated_themes_keep_anchor_contrast() {
        let dir = TempDir::new("anchors");
        let cache = dir.path("cache");
        let mut clamped = 0;
        for (name, pix) in LOW_CONTRAST {
            let path = dir.path(&format!("{name}.png"));
            write_png(Path::new(&path), 96, 96, pix);
            for light in [false, true] {
                for mode in all_modes() {
                    let what = format!("{name} light={light} {mode}");
                    let (r, err) = generate_with_cache(&path, light, mode, &cache);
                    assert!(err.is_none(), "{what}: {err:?}");
                    let r = r.unwrap();
                    assert_readable(&r.palette, &r.selection, &what);
                    let raw = load_cached(&cache, &cache_key(&r.seed, mode, light))
                        .expect("a cache entry");
                    assert_eq!(
                        r.palette[SLOT_BACKGROUND], raw[SLOT_BACKGROUND],
                        "{what}: the background moved"
                    );
                    let raw_selection = base_selection(&raw[SLOT_BACKGROUND], light);
                    for (role, a, b) in [
                        (
                            "foreground",
                            &raw[SLOT_FOREGROUND],
                            &r.palette[SLOT_FOREGROUND],
                        ),
                        ("accent", &raw[SLOT_ACCENT], &r.palette[SLOT_ACCENT]),
                        ("selection", &raw_selection, &r.selection),
                    ] {
                        let d = hue_shift(a, b);
                        assert!(
                            d <= MAX_HUE_SHIFT,
                            "{what}: {role} {a} -> {b} shifted hue by {d:.4}"
                        );
                    }
                    if r.palette != raw || r.selection != raw_selection {
                        clamped += 1;
                    }
                    let (again, err) = generate_with_cache(&path, light, mode, &cache);
                    let again = again.unwrap();
                    assert!(
                        err.is_none()
                            && again.cached
                            && again.palette == r.palette
                            && again.selection == r.selection,
                        "{what}: the cached run differs from the fresh one"
                    );
                }
            }
        }
        // Keeps the images honest: they must still need the clamp.
        assert!(
            clamped > 0,
            "no generated palette needed the clamp; pick lower-contrast images"
        );
    }

    #[test]
    fn clamp_anchors_on_low_contrast_sets() {
        let cases = [
            (
                "dark mid-grey",
                "#6e6e6e",
                "#9a9a9a",
                "#7a8cb0",
                false,
                true,
                true,
            ),
            (
                "light pastel",
                "#e9dff0",
                "#c9b8d6",
                "#a9c7e8",
                true,
                false,
                false,
            ),
            (
                "fg on the near side",
                "#5a5a5a",
                "#4a4060",
                "#4c5a80",
                false,
                true,
                true,
            ),
            (
                "saturated accent",
                "#202020",
                "#3a3a3a",
                "#1030ff",
                false,
                true,
                true,
            ),
        ];
        for (name, bg, fg, accent, light, want_fg_up, want_acc_up) in cases {
            let mut p: Palette = std::array::from_fn(|_| bg.to_string());
            p[SLOT_FOREGROUND] = fg.into();
            p[SLOT_ACCENT] = accent.into();
            let (got, selection) = clamp_anchors(p, light);
            assert_readable(&got, &selection, name);
            for (role, a, b) in [
                ("foreground", fg.to_string(), got[SLOT_FOREGROUND].clone()),
                ("accent", accent.to_string(), got[SLOT_ACCENT].clone()),
                ("selection", base_selection(bg, light), selection.clone()),
            ] {
                let d = hue_shift(&a, &b);
                assert!(
                    d <= MAX_HUE_SHIFT,
                    "{name}: {role} {a} -> {b} shifted hue by {d:.4}"
                );
            }
            assert_eq!(
                hex_to_oklab(&got[SLOT_FOREGROUND]).l > hex_to_oklab(fg).l,
                want_fg_up,
                "{name}: foreground"
            );
            assert_eq!(
                hex_to_oklab(&got[SLOT_ACCENT]).l > hex_to_oklab(accent).l,
                want_acc_up,
                "{name}: accent"
            );
            assert_eq!(
                got[SLOT_FOREGROUND + 8],
                generate_bright_version(&got[SLOT_FOREGROUND])
            );
            assert_eq!(
                got[SLOT_ACCENT + 8],
                generate_bright_version(&got[SLOT_ACCENT])
            );
            // Least move: one step back toward the original fails.
            for (orig, moved, target) in [
                (fg, &got[SLOT_FOREGROUND], MIN_TEXT_CONTRAST),
                (accent, &got[SLOT_ACCENT], MIN_ACCENT_CONTRAST),
            ] {
                let mut lch = hex_to_oklch(moved);
                lch.l += 0.01_f64.copysign(hex_to_oklab(orig).l - lch.l);
                let back = oklch_to_hex(fit_chroma(lch));
                assert!(
                    color::contrast_ratio(&back, bg) < target,
                    "{name}: {moved} overshot: {back} also passes"
                );
            }
            // Idempotent.
            let (again, sel) = clamp_anchors(got.clone(), light);
            assert!(
                again == got && sel == selection,
                "{name}: a second clamp changed the palette"
            );
        }
    }

    #[test]
    fn clamp_anchors_keeps_passing_colours() {
        for light in [false, true] {
            let mut p: Palette = [
                "#1a1b26", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff",
                "#c0caf5", "#414868", "#ff7a93", "#b9f27c", "#ff9e64", "#7da6ff", "#bb9af7",
                "#0db9d7", "#e6ebff",
            ]
            .map(String::from);
            if light {
                p[SLOT_BACKGROUND] = "#f4f4f6".into();
                p[SLOT_FOREGROUND] = "#343b58".into();
                p[SLOT_ACCENT] = "#34548a".into();
            }
            let (got, selection) = clamp_anchors(p.clone(), light);
            assert_eq!(got, p, "light={light}: a passing palette changed");
            assert_eq!(selection, base_selection(&p[SLOT_BACKGROUND], light));
        }
    }

    /// White and black are the only in-gamut colours at their lightness.
    #[test]
    fn fit_chroma_keeps_hue() {
        for h in [0.0, 29.0, 110.0, 142.0, 264.0, 330.0] {
            for l in [0.2, 0.5, 0.8] {
                let lch = fit_chroma(OkLch { l, c: 0.4, h });
                assert!(
                    in_gamut(lch) && lch.c > 0.0 && lch.c < 0.4,
                    "L={l} H={h}: fitted chroma {}",
                    lch.c
                );
            }
            assert_eq!(
                oklch_to_hex(fit_chroma(OkLch { l: 1.0, c: 0.2, h })),
                "#ffffff"
            );
        }
        assert_eq!(oklab_to_hex(hex_to_oklab("#7aa2f7")), "#7aa2f7");
    }
}
