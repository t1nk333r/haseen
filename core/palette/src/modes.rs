//! The palette generators, one per extraction mode, and the passes they
//! share. A port of x_palette_chromatic.go, x_palette_modes.go,
//! x_palette_monochrome.go, x_palette_moods.go, x_palette_practical.go,
//! x_palette_schemes.go, x_normalize.go and generate.go's dispatch
//! (omacom/aether, MIT, NOTICE.md).

use crate::analysis::*;
use crate::color::{self, OkLch};
use crate::gomath::{self, fmod};

pub type Palette = [String; 16];

fn empty() -> Palette {
    Default::default()
}

pub fn clamp_f(v: f64, lo: f64, hi: f64) -> f64 {
    gomath::max(lo, gomath::min(hi, v))
}

fn lch(l: f64, c: f64, h: f64) -> OkLch {
    OkLch { l, c, h }
}

/// Every mode the generator accepts (Go's validateMode), help's list first.
pub const MODES: [&str; 14] = [
    "normal",
    "monochromatic",
    "analogous",
    "pastel",
    "material",
    "colorful",
    "muted",
    "bright",
    "complementary",
    "triadic",
    "split-complementary",
    "tetradic",
    "high-contrast",
    "duotone",
];
pub const MOODS: [&str; 9] = [
    "fire",
    "ocean",
    "forest",
    "earthtone",
    "neon",
    "sunset",
    "vaporwave",
    "midnight",
    "aurora",
];

pub fn valid_mode(mode: &str) -> bool {
    MODES.contains(&mode) || MOODS.contains(&mode)
}

/// Pixel counts as shares of the total; None for no pixels.
pub fn normalize_counts(counts: &[usize]) -> Option<Vec<f64>> {
    let total: usize = counts.iter().sum();
    if total == 0 {
        return None;
    }
    Some(counts.iter().map(|&c| c as f64 / total as f64).collect())
}

pub fn generate_by_mode(
    dominant: &[String],
    weights: Option<&[f64]>,
    light: bool,
    mode: &str,
) -> Palette {
    match mode {
        "monochromatic" => monochromatic(dominant, light),
        "analogous" => analogous(dominant, light),
        "pastel" => pastel(dominant, light),
        "material" => material(dominant, light),
        "colorful" => colorful(dominant, light),
        "muted" => muted(dominant, light),
        "bright" => bright(dominant, light),
        "complementary" => complementary(dominant, light),
        "triadic" => triadic(dominant, light),
        "split-complementary" => split_complementary(dominant, light),
        "tetradic" => tetradic(dominant, light),
        "fire" => mood(dominant, light, &FIRE),
        "ocean" => mood(dominant, light, &OCEAN),
        "forest" => mood(dominant, light, &FOREST),
        "earthtone" => mood(dominant, light, &EARTHTONE),
        "neon" => mood(dominant, light, &NEON),
        "sunset" => mood(dominant, light, &SUNSET),
        "vaporwave" => mood(dominant, light, &VAPORWAVE),
        "midnight" => mood(dominant, light, &MIDNIGHT),
        "aurora" => mood(dominant, light, &AURORA),
        "high-contrast" => high_contrast(dominant, light),
        "duotone" => duotone(dominant, light),
        _ => {
            if is_monochrome_weighted(dominant, weights) {
                monochrome(dominant, light)
            } else {
                chromatic(dominant, weights, light)
            }
        }
    }
}

/// Every ANSI colour (1-6) reaches WCAG AA against the background.
pub fn normalize_brightness(mut p: Palette) -> Palette {
    for i in 1..=6 {
        if color::contrast_ratio(&p[0], &p[i]) < MIN_CONTRAST_RATIO {
            p[i] = boost_contrast_against_bg(&p[i], &p[0], MIN_CONTRAST_RATIO);
            p[i + 8] = generate_bright_version(&p[i]);
        }
    }
    p
}

// --- shared passes (x_palette_chromatic.go, x_palette_modes.go) -------------

/// Slots 8, 9-14 and 15 from 0, 1-6 and 7, then AA contrast for 1-6.
fn finalize(p: &mut Palette) {
    p[8] = comment_color(&p[0]);
    for i in 1..=6 {
        p[i + 8] = generate_bright_version(&p[i]);
    }
    p[15] = generate_bright_version(&p[7]);
    for i in 1..=6 {
        if color::contrast_ratio(&p[0], &p[i]) < MIN_CONTRAST_RATIO {
            p[i] = boost_contrast_against_bg(&p[i], &p[0], MIN_CONTRAST_RATIO);
            p[i + 8] = generate_bright_version(&p[i]);
        }
    }
}

fn pull_hue_toward(hue: f64, target: f64, strength: f64) -> f64 {
    let diff = fmod(target - hue + 540.0, 360.0) - 180.0;
    fmod(hue + diff * strength + 360.0, 360.0)
}

/// The hue of the most chromatic dominant colour (0 when all are grey).
fn dominant_hue(dominant: &[String]) -> f64 {
    let mut hue = 0.0;
    let mut best = 0.0;
    for c in dominant {
        let l = color::hex_to_oklch(c);
        if l.c > best {
            best = l.c;
            hue = l.h;
        }
    }
    hue
}

/// A grey for comments (slot 8) that reads against the background.
pub fn comment_color(bg: &str) -> String {
    let bg_lab = color::hex_to_oklab(bg);
    let bg_lch = color::oklab_to_oklch(bg_lab);
    let mut target_l = if bg_lab.l < 0.5 {
        gomath::min(1.0, bg_lab.l + 0.30)
    } else {
        gomath::max(0.0, bg_lab.l - 0.30)
    };
    let chroma = 0.01;
    let mut comment = color::oklch_to_hex(lch(target_l, chroma, bg_lch.h));
    let mut contrast = color::contrast_ratio(bg, &comment);
    if contrast < MIN_COMMENT_CONTRAST {
        let step = 0.05;
        if bg_lab.l < 0.5 {
            while target_l < 0.95 && contrast < MIN_COMMENT_CONTRAST {
                target_l += step;
                comment = color::oklch_to_hex(lch(target_l, chroma, bg_lch.h));
                contrast = color::contrast_ratio(bg, &comment);
            }
        } else {
            while target_l > 0.05 && contrast < MIN_COMMENT_CONTRAST {
                target_l -= step;
                comment = color::oklch_to_hex(lch(target_l, chroma, bg_lch.h));
                contrast = color::contrast_ratio(bg, &comment);
            }
        }
    }
    comment
}

/// Steps OKLab lightness away from the background until the ratio is met.
pub fn boost_contrast_against_bg(hex: &str, bg: &str, target: f64) -> String {
    let lab = color::hex_to_oklab(hex);
    let mut l = color::oklab_to_oklch(lab);
    let bg_lab = color::hex_to_oklab(bg);
    let step = 0.03;
    if bg_lab.l < 0.5 {
        while l.l < 0.95 {
            l.l += step;
            let c = color::oklch_to_hex(l);
            if color::contrast_ratio(bg, &c) >= target {
                return c;
            }
        }
    } else {
        while l.l > 0.05 {
            l.l -= step;
            let c = color::oklch_to_hex(l);
            if color::contrast_ratio(bg, &c) >= target {
                return c;
            }
        }
    }
    color::oklch_to_hex(l)
}

// --- chromatic (x_palette_chromatic.go) --------------------------------------

/// Slots 0, 7 and 1-6 from the image; 8-15 are left for finalize.
fn extract_chromatic_hues(dominant: &[String], weights: Option<&[f64]>, light: bool) -> Palette {
    let top = dominant.len().min(12);
    let top_colors = &dominant[..top];
    let top_weights = weights.map(|w| &w[..top]);
    let (bg, bg_index) = find_background_color(top_colors, top_weights, light);
    let bg = synthesize_bg_if_too_mid(&bg, light);
    let mut used = vec![false; dominant.len()];
    used[bg_index] = true;
    let (fg, fg_index) = find_foreground_color(dominant, weights, light, &bg, &used);
    if let Some(i) = fg_index {
        used[i] = true;
    }
    let mut p = empty();
    p[0] = bg;
    p[7] = fg;
    let assignments = find_optimal_ansi_assignment(dominant, &used, light);
    for (i, a) in assignments.iter().enumerate() {
        // At least 8 colours and at most 2 taken: all six are filled.
        let pi = a.expect("every ANSI slot is assigned");
        p[i + 1] = dominant[pi].clone();
        used[pi] = true;
    }
    p
}

fn synthesize_bg_if_too_mid(bg: &str, light: bool) -> String {
    let l = color::hex_to_oklch(bg);
    if light {
        if l.l >= 0.85 {
            return bg.to_string();
        }
        return color::oklch_to_hex(lch(0.94, gomath::min(l.c, 0.04), l.h));
    }
    if l.l <= 0.20 {
        return bg.to_string();
    }
    color::oklch_to_hex(lch(0.12, gomath::min(l.c, 0.05), l.h))
}

fn chromatic(dominant: &[String], weights: Option<&[f64]>, light: bool) -> Palette {
    let mut p = extract_chromatic_hues(dominant, weights, light);
    normalize_chromatic_accents(&mut p, dominant, weights, light);
    finalize(&mut p);
    p
}

struct HueCluster {
    hue: f64,
}

/// 30-degree bands of the chromatic dominant colours, weighted by coverage,
/// that carry at least MIN_ACCENT_HUE_SUPPORT of the frame.
fn supported_hue_clusters(dominant: &[String], weights: Option<&[f64]>) -> Vec<HueCluster> {
    const BINS: usize = 12;
    let mut w_ = [0.0; BINS];
    let mut s_ = [0.0; BINS];
    let mut c_ = [0.0; BINS];
    for (k, c) in dominant.iter().enumerate() {
        let l = color::hex_to_oklch(c);
        if l.c < ACCENT_SUPPORT_CHROMA {
            continue;
        }
        let mut w = 1.0 / dominant.len() as f64;
        if let Some(ws) = weights {
            if k < ws.len() {
                w = ws[k];
            }
        }
        let mut b = (l.h / 30.0) as i64 % BINS as i64;
        if b < 0 {
            b += BINS as i64;
        }
        let b = b as usize;
        let rad = l.h * std::f64::consts::PI / 180.0;
        w_[b] += w;
        s_[b] += gomath::sin(rad) * w;
        c_[b] += gomath::cos(rad) * w;
    }
    let mut out = Vec::new();
    for b in 0..BINS {
        if w_[b] >= MIN_ACCENT_HUE_SUPPORT {
            let h = fmod(
                gomath::atan2(s_[b], c_[b]) * 180.0 / std::f64::consts::PI + 360.0,
                360.0,
            );
            out.push(HueCluster { hue: h });
        }
    }
    out
}

fn nearest_cluster_hue(target: f64, clusters: &[HueCluster]) -> Option<f64> {
    let mut best = f64::INFINITY;
    let mut best_hue = 0.0;
    for c in clusters {
        let d = hue_distance(target, c.hue);
        if d < best {
            best = d;
            best_hue = c.hue;
        }
    }
    (!clusters.is_empty()).then_some(best_hue)
}

/// Keeps every accent inside the image's own hue clusters, lifts chroma to
/// the image's salient saturation, then separates near-identical accents by
/// lightness.
fn normalize_chromatic_accents(
    p: &mut Palette,
    dominant: &[String],
    weights: Option<&[f64]>,
    light: bool,
) {
    let target = clamp_f(
        salient_chroma(dominant) * 0.85,
        ACCENT_CHROMA_FLOOR,
        ACCENT_CHROMA_CEIL,
    );
    let clusters = supported_hue_clusters(dominant, weights);
    for i in 1..=6 {
        let mut l = color::hex_to_oklch(&p[i]);
        let gray = l.c < NEAR_ACHROMATIC_CHROMA;
        let supported = clusters
            .iter()
            .any(|cl| hue_distance(l.h, cl.hue) <= HUE_SUPPORT_TOL);
        if gray || !supported {
            if let Some(h) = nearest_cluster_hue(OKLCH_ANSI_HUES[i - 1], &clusters) {
                l.h = h;
            } else if gray {
                l.c = 0.0;
            }
        }
        if l.c > 0.0 && l.c < target {
            l.c = target;
        }
        p[i] = color::oklch_to_hex(l);
    }
    for i in 1..=6 {
        for j in i + 1..=6 {
            if color::oklab_distance(color::hex_to_oklab(&p[i]), color::hex_to_oklab(&p[j]))
                < ACCENT_MIN_DELTA_E
            {
                let mut l = color::hex_to_oklch(&p[j]);
                l.l = if light {
                    clamp_f(l.l - 0.10, 0.20, 0.85)
                } else {
                    clamp_f(l.l + 0.10, 0.30, 0.92)
                };
                p[j] = color::oklch_to_hex(l);
            }
        }
    }
}

// --- transformed modes (x_palette_modes.go) ----------------------------------

type Rule = fn(OkLch, bool) -> OkLch;

/// Hues from the image, lightness and chroma from the mode's rules.
fn transform_chromatic(
    dominant: &[String],
    light: bool,
    bg: &dyn Fn(OkLch) -> OkLch,
    fg: &dyn Fn(OkLch) -> OkLch,
    ansi: &dyn Fn(OkLch) -> OkLch,
    offsets: [f64; 6],
) -> Palette {
    let base = extract_chromatic_hues(dominant, None, light);
    let mut p = empty();
    p[0] = color::oklch_to_hex(bg(color::hex_to_oklch(&base[0])));
    p[7] = color::oklch_to_hex(fg(color::hex_to_oklch(&base[7])));
    for i in 0..6 {
        let slot = i + 1;
        let mut shaped = ansi(color::hex_to_oklch(&base[slot]));
        shaped.l = clamp_f(shaped.l + offsets[i], 0.05, 0.95);
        p[slot] = color::oklch_to_hex(shaped);
    }
    finalize(&mut p);
    p
}

/// A mode as fixed bg and fg (L, C; hue kept), an ANSI rule and a stagger.
struct Shape {
    bg: [(f64, f64); 2], // dark, light
    fg: [(f64, f64); 2],
    ansi: Rule,
    stagger: [f64; 6],
}

fn shaped(dominant: &[String], light: bool, s: &Shape) -> Palette {
    let k = light as usize;
    let (bgl, bgc) = s.bg[k];
    let (fgl, fgc) = s.fg[k];
    let ansi = s.ansi;
    transform_chromatic(
        dominant,
        light,
        &|c| lch(bgl, bgc, c.h),
        &|c| lch(fgl, fgc, c.h),
        &|c| ansi(c, light),
        s.stagger,
    )
}

fn pastel(dominant: &[String], light: bool) -> Palette {
    shaped(
        dominant,
        light,
        &Shape {
            bg: [(0.20, 0.022), (0.96, 0.012)],
            fg: [(0.85, 0.04), (0.32, 0.05)],
            ansi: |c, light| {
                if light {
                    lch(0.55, clamp_f(c.c, 0.045, 0.07), c.h)
                } else {
                    lch(0.78, clamp_f(c.c, 0.05, 0.075), c.h)
                }
            },
            stagger: [-0.04, 0.02, 0.05, -0.03, -0.01, 0.03],
        },
    )
}

fn colorful(dominant: &[String], light: bool) -> Palette {
    shaped(
        dominant,
        light,
        &Shape {
            bg: [(0.10, 0.022), (0.97, 0.012)],
            fg: [(0.92, 0.03), (0.18, 0.04)],
            ansi: |c, light| {
                let ch = clamp_f(gomath::max(c.c, 0.14), 0.14, 0.20);
                lch(if light { 0.50 } else { 0.65 }, ch, c.h)
            },
            stagger: [-0.05, 0.02, 0.06, -0.03, -0.02, 0.04],
        },
    )
}

fn muted(dominant: &[String], light: bool) -> Palette {
    shaped(
        dominant,
        light,
        &Shape {
            bg: [(0.16, 0.018), (0.94, 0.010)],
            fg: [(0.84, 0.035), (0.28, 0.045)],
            ansi: |c, light| {
                let ch = clamp_f(c.c * 0.5, 0.035, 0.065);
                lch(if light { 0.48 } else { 0.62 }, ch, c.h)
            },
            stagger: [-0.10, -0.04, 0.04, 0.10, -0.07, 0.07],
        },
    )
}

fn bright(dominant: &[String], light: bool) -> Palette {
    shaped(
        dominant,
        light,
        &Shape {
            bg: [(0.10, 0.020), (0.98, 0.010)],
            fg: [(0.92, 0.025), (0.15, 0.04)],
            ansi: |c, light| {
                let ch = clamp_f(gomath::max(c.c, 0.10), 0.10, 0.18);
                lch(if light { 0.42 } else { 0.78 }, ch, c.h)
            },
            stagger: [-0.04, 0.01, 0.06, -0.03, -0.02, 0.03],
        },
    )
}

/// Material Design's neutrals with HSL-refined accents (HSL on purpose:
/// Material specifies them so).
fn material(dominant: &[String], light: bool) -> Palette {
    let mut p = empty();
    let mut used = vec![false; dominant.len()];
    if light {
        p[0] = "#fafafa".into();
        p[7] = "#212121".into();
    } else {
        p[0] = "#121212".into();
        p[7] = "#ffffff".into();
    }
    for (i, &hue) in OKLCH_ANSI_HUES.iter().enumerate() {
        let m = find_best_color_match(hue, dominant, &used, light);
        let hsl = color::hex_to_hsl(&dominant[m]);
        let s = gomath::max(hsl.s, 35.0);
        let l = if light {
            gomath::max(35.0, gomath::min(60.0, hsl.l))
        } else {
            gomath::max(45.0, gomath::min(70.0, hsl.l))
        };
        p[i + 1] = color::hsl_to_hex(hsl.h, s, l);
        used[m] = true;
    }
    p[8] = if light { "#757575" } else { "#9e9e9e" }.into();
    for i in 1..=6 {
        let hsl = color::hex_to_hsl(&p[i]);
        let s = gomath::min(100.0, hsl.s + 8.0);
        let l = if light {
            gomath::max(30.0, hsl.l - 8.0)
        } else {
            gomath::min(75.0, hsl.l + 8.0)
        };
        p[i + 8] = color::hsl_to_hex(hsl.h, s, l);
    }
    p[15] = if light { "#000000" } else { "#ffffff" }.into();
    p
}

/// Six hues within 30 degrees of the dominant one.
fn analogous(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let sorted = sort_colors_by_lightness(dominant);
    let darkest = &sorted[0];
    let lightest = &sorted[sorted.len() - 1];
    let mut p = empty();
    if light {
        p[0] = color::oklch_to_hex(lch(gomath::max(0.92, lightest.lightness), 0.02, base));
        p[7] = color::oklch_to_hex(lch(gomath::min(0.28, darkest.lightness + 0.05), 0.04, base));
    } else {
        p[0] = color::oklch_to_hex(lch(gomath::min(0.16, darkest.lightness), 0.03, base));
        p[7] = color::oklch_to_hex(lch(
            gomath::max(0.88, lightest.lightness - 0.05),
            0.025,
            base,
        ));
    }
    let offsets = [-30.0, -18.0, -6.0, 6.0, 18.0, 30.0];
    let chroma = [0.10, 0.13, 0.09, 0.14, 0.10, 0.12];
    let stagger = [-0.06, 0.04, -0.04, 0.06, -0.05, 0.05];
    let lbase = if light { 0.50 } else { 0.62 };
    for i in 0..6 {
        let hue = fmod(base + offsets[i] + 360.0, 360.0);
        let l = clamp_f(lbase + stagger[i], 0.30, 0.85);
        p[i + 1] = color::oklch_to_hex(lch(l, chroma[i], hue));
    }
    p[8] = comment_color(&p[0]);
    for i in 0..6 {
        let hue = fmod(base + offsets[i] + 360.0, 360.0);
        let mut bl = clamp_f(lbase + stagger[i] + 0.10, 0.30, 0.92);
        if light {
            bl = clamp_f(lbase + stagger[i] - 0.10, 0.20, 0.70);
        }
        p[i + 9] = color::oklch_to_hex(lch(bl, chroma[i] + 0.02, hue));
    }
    p[15] = if light {
        color::oklch_to_hex(lch(0.10, 0.04, base))
    } else {
        color::oklch_to_hex(lch(0.97, 0.015, base))
    };
    p
}

// --- monochrome (x_palette_monochrome.go) ------------------------------------

fn synthesize_mono_bg_if_muddy(bg: &str, light: bool) -> String {
    let l = color::hex_to_oklch(bg);
    if light {
        if l.l >= 0.75 {
            return bg.to_string();
        }
        return color::oklch_to_hex(lch(0.94, gomath::min(l.c, 0.04), l.h));
    }
    if l.l <= 0.35 {
        return bg.to_string();
    }
    color::oklch_to_hex(lch(0.14, gomath::min(l.c, 0.06), l.h))
}

/// The chroma-weighted mean hue of mostly grey colours, if the image has a
/// cast above JPEG noise.
fn detect_monochrome_tint(colors: &[String]) -> Option<f64> {
    if colors.is_empty() {
        return None;
    }
    let (mut sin_sum, mut cos_sum, mut chroma_sum) = (0.0, 0.0, 0.0);
    for c in colors {
        let l = color::hex_to_oklch(c);
        if l.c > 0.005 {
            let w = l.c;
            let rad = l.h * std::f64::consts::PI / 180.0;
            sin_sum += gomath::sin(rad) * w;
            cos_sum += gomath::cos(rad) * w;
            chroma_sum += w;
        }
    }
    let avg = chroma_sum / colors.len() as f64;
    if avg < MIN_MEANINGFUL_TINT_CHROMA {
        return None;
    }
    let ms = sin_sum / chroma_sum;
    let mc = cos_sum / chroma_sum;
    Some(fmod(
        gomath::atan2(ms, mc) * 180.0 / std::f64::consts::PI + 360.0,
        360.0,
    ))
}

/// About the 90th percentile chroma of the dominant colours.
fn salient_chroma(colors: &[String]) -> f64 {
    if colors.is_empty() {
        return 0.0;
    }
    let mut chromas: Vec<f64> = colors.iter().map(|c| color::hex_to_oklch(c).c).collect();
    // No NaN can occur, and equal floats are interchangeable, so any sort
    // is Go's sort.Float64s here.
    chromas.sort_by(|a, b| a.total_cmp(b));
    let idx = (0.9 * (chromas.len() - 1) as f64).round() as usize;
    chromas[idx]
}

fn mean6(v: [f64; 6]) -> f64 {
    let mut sum = 0.0;
    for x in v {
        sum += x;
    }
    sum / 6.0
}

fn fold_hue_into_arc(canonical: f64, base: f64, arc: f64) -> f64 {
    let d = fmod(canonical - base + 540.0, 360.0) - 180.0;
    fmod(base + (d / 180.0) * arc + 360.0, 360.0)
}

/// Blue darkest, then red, magenta, green, cyan, yellow.
const CANONICAL_LIGHTNESS_ORDER: [usize; 6] = [3, 0, 4, 1, 5, 2];

fn mono_accent_ramp(bg: &str, light: bool) -> [f64; 6] {
    let (start, step);
    if light {
        let hi = neutral_readable_l(bg, true, MIN_CONTRAST_RATIO) - 0.02;
        start = hi;
        step = -gomath::max(MONO_ACCENT_MIN_L_STEP, (hi - 0.16) / 5.0);
    } else {
        let lo = neutral_readable_l(bg, false, MIN_CONTRAST_RATIO) + 0.02;
        start = lo;
        step = gomath::max(MONO_ACCENT_MIN_L_STEP, (0.92 - lo) / 5.0);
    }
    let mut slot_l = [0.0; 6];
    for (pos, &slot) in CANONICAL_LIGHTNESS_ORDER.iter().enumerate() {
        slot_l[slot] = clamp_f(start + step * pos as f64, 0.06, 0.97);
    }
    slot_l
}

fn ensure_mono_headroom(bg: &str, light: bool) -> String {
    let l = color::hex_to_oklch(bg);
    if light {
        if neutral_readable_l(bg, true, MIN_CONTRAST_RATIO) < 0.42 {
            return color::oklch_to_hex(lch(0.95, gomath::min(l.c, 0.04), l.h));
        }
        return bg.to_string();
    }
    if neutral_readable_l(bg, false, MIN_CONTRAST_RATIO) > 0.60 {
        return color::oklch_to_hex(lch(0.13, gomath::min(l.c, 0.06), l.h));
    }
    bg.to_string()
}

fn monochrome(colors: &[String], light: bool) -> Palette {
    match detect_monochrome_tint(colors) {
        None => grayscale_monochromatic(colors, light),
        Some(hue) => tinted_monochromatic(colors, light, hue, AUTO_MONO_ARC_DEG),
    }
}

fn monochromatic(colors: &[String], light: bool) -> Palette {
    match detect_monochrome_tint(colors) {
        None => grayscale_monochromatic(colors, light),
        Some(hue) => tinted_monochromatic(colors, light, hue, EXPLICIT_MONO_ARC_DEG),
    }
}

/// The first neutral grey lightness, scanning away from the background in
/// steps of 0.01, that reaches the ratio.
fn neutral_readable_l(bg: &str, light: bool, ratio: f64) -> f64 {
    let gray = |l: f64| color::oklch_to_hex(lch(l, 0.0, 0.0));
    if !light {
        let mut l = 0.20;
        while l <= 0.95 {
            if color::contrast_ratio(bg, &gray(l)) >= ratio {
                return l;
            }
            l += 0.01;
        }
        return 0.55;
    }
    let mut l = 0.80;
    while l >= 0.05 {
        if color::contrast_ratio(bg, &gray(l)) >= ratio {
            return l;
        }
        l -= 0.01;
    }
    0.45
}

fn grayscale_monochromatic(colors: &[String], light: bool) -> Palette {
    let sorted = sort_colors_by_lightness(colors);
    let darkest = &sorted[0];
    let lightest = &sorted[sorted.len() - 1];
    let mut p = empty();
    if light {
        p[0] = color::oklch_to_hex(lch(gomath::max(0.94, lightest.lightness), 0.0, 0.0));
        p[7] = color::oklch_to_hex(lch(gomath::min(0.22, darkest.lightness), 0.0, 0.0));
    } else {
        p[0] = color::oklch_to_hex(lch(gomath::min(0.14, darkest.lightness), 0.0, 0.0));
        p[7] = color::oklch_to_hex(lch(gomath::max(0.88, lightest.lightness), 0.0, 0.0));
    }
    p[0] = ensure_mono_headroom(&p[0], light);
    let slot_l = mono_accent_ramp(&p[0], light);
    for i in 0..6 {
        p[i + 1] = color::oklch_to_hex(lch(slot_l[i], 0.0, 0.0));
    }
    p[8] = comment_color(&p[0]);
    let bump = if light { -0.06 } else { 0.06 };
    for i in 0..6 {
        let l = gomath::max(0.05, gomath::min(0.97, slot_l[i] + bump));
        p[i + 9] = color::oklch_to_hex(lch(l, 0.0, 0.0));
    }
    p[15] = color::oklch_to_hex(lch(if light { 0.04 } else { 0.99 }, 0.0, 0.0));
    p
}

fn tinted_monochromatic(colors: &[String], light: bool, base: f64, arc: f64) -> Palette {
    let sorted = sort_colors_by_lightness(colors);
    let darkest = &sorted[0];
    let lightest = &sorted[sorted.len() - 1];
    let mut p = empty();
    if light {
        p[0] = synthesize_mono_bg_if_muddy(&lightest.color, light);
        p[7] = darkest.color.clone();
    } else {
        p[0] = synthesize_mono_bg_if_muddy(&darkest.color, light);
        p[7] = lightest.color.clone();
    }
    p[0] = ensure_mono_headroom(&p[0], light);
    if color::contrast_ratio(&p[0], &p[7]) < MIN_FG_BG_CONTRAST {
        let bg_lab = color::hex_to_oklab(&p[0]);
        let mut fg_lab = color::hex_to_oklab(&p[7]);
        fg_lab.l = if bg_lab.l < 0.5 { 0.97 } else { 0.05 };
        p[7] = color::oklab_to_hex(fg_lab);
    }
    let chroma = [0.09, 0.11, 0.13, 0.10, 0.12, 0.14];
    let bright_chroma = [0.11, 0.14, 0.16, 0.12, 0.15, 0.17];
    let factor = clamp_f(
        salient_chroma(colors) / mean6(chroma),
        MONO_CHROMA_FACTOR_FLOOR,
        1.0,
    );
    let slot_l = mono_accent_ramp(&p[0], light);
    for i in 0..6 {
        let hue = fold_hue_into_arc(OKLCH_ANSI_HUES[i], base, arc);
        p[i + 1] = color::oklch_to_hex(lch(slot_l[i], chroma[i] * factor, hue));
    }
    p[8] = comment_color(&p[0]);
    let adj = if light { -0.07 } else { 0.07 };
    for i in 0..6 {
        let hue = fold_hue_into_arc(OKLCH_ANSI_HUES[i], base, arc);
        let l = clamp_f(slot_l[i] + adj, 0.18, 0.96);
        p[i + 9] = color::oklch_to_hex(lch(l, bright_chroma[i] * factor, hue));
    }
    p[15] = if light {
        color::oklch_to_hex(lch(0.08, 0.03, base))
    } else {
        color::oklch_to_hex(lch(0.97, 0.015, base))
    };
    p
}

// --- moods (x_palette_moods.go) ----------------------------------------------

struct Mood {
    bg_dark: OkLch,
    bg_light: OkLch,
    fg_dark: OkLch,
    fg_light: OkLch,
    anchor: f64,
    tint: f64,
    cmin: f64,
    cmax: f64,
    l_dark: f64,
    l_light: f64,
    stagger: [f64; 6],
}

fn mood(dominant: &[String], light: bool, m: &Mood) -> Palette {
    let bg = if light { m.bg_light } else { m.bg_dark };
    let fg = if light { m.fg_light } else { m.fg_dark };
    let l = if light { m.l_light } else { m.l_dark };
    transform_chromatic(
        dominant,
        light,
        &|_| bg,
        &|_| fg,
        &|c| {
            let h = pull_hue_toward(c.h, m.anchor, m.tint);
            lch(l, clamp_f(c.c, m.cmin, m.cmax), h)
        },
        m.stagger,
    )
}

const FIRE: Mood = Mood {
    bg_dark: OkLch {
        l: 0.09,
        c: 0.045,
        h: 28.0,
    },
    bg_light: OkLch {
        l: 0.95,
        c: 0.030,
        h: 45.0,
    },
    fg_dark: OkLch {
        l: 0.90,
        c: 0.040,
        h: 55.0,
    },
    fg_light: OkLch {
        l: 0.22,
        c: 0.060,
        h: 20.0,
    },
    anchor: 30.0,
    tint: 0.28,
    cmin: 0.07,
    cmax: 0.12,
    l_dark: 0.62,
    l_light: 0.46,
    stagger: [-0.05, 0.01, 0.07, -0.04, -0.02, 0.03],
};
const OCEAN: Mood = Mood {
    bg_dark: OkLch {
        l: 0.10,
        c: 0.050,
        h: 240.0,
    },
    bg_light: OkLch {
        l: 0.96,
        c: 0.030,
        h: 215.0,
    },
    fg_dark: OkLch {
        l: 0.90,
        c: 0.035,
        h: 205.0,
    },
    fg_light: OkLch {
        l: 0.20,
        c: 0.055,
        h: 230.0,
    },
    anchor: 220.0,
    tint: 0.28,
    cmin: 0.09,
    cmax: 0.14,
    l_dark: 0.60,
    l_light: 0.44,
    stagger: [-0.05, 0.02, 0.06, -0.03, -0.01, 0.03],
};
const FOREST: Mood = Mood {
    bg_dark: OkLch {
        l: 0.13,
        c: 0.040,
        h: 145.0,
    },
    bg_light: OkLch {
        l: 0.95,
        c: 0.025,
        h: 130.0,
    },
    fg_dark: OkLch {
        l: 0.88,
        c: 0.035,
        h: 125.0,
    },
    fg_light: OkLch {
        l: 0.24,
        c: 0.050,
        h: 140.0,
    },
    anchor: 145.0,
    tint: 0.25,
    cmin: 0.06,
    cmax: 0.10,
    l_dark: 0.66,
    l_light: 0.48,
    stagger: [-0.05, 0.02, 0.07, -0.03, -0.01, 0.04],
};
const EARTHTONE: Mood = Mood {
    bg_dark: OkLch {
        l: 0.18,
        c: 0.040,
        h: 40.0,
    },
    bg_light: OkLch {
        l: 0.93,
        c: 0.025,
        h: 60.0,
    },
    fg_dark: OkLch {
        l: 0.84,
        c: 0.050,
        h: 50.0,
    },
    fg_light: OkLch {
        l: 0.26,
        c: 0.055,
        h: 35.0,
    },
    anchor: 45.0,
    tint: 0.40,
    cmin: 0.05,
    cmax: 0.09,
    l_dark: 0.58,
    l_light: 0.44,
    stagger: [-0.10, -0.04, 0.04, 0.10, -0.07, 0.07],
};
const NEON: Mood = Mood {
    bg_dark: OkLch {
        l: 0.05,
        c: 0.030,
        h: 280.0,
    },
    bg_light: OkLch {
        l: 0.97,
        c: 0.015,
        h: 280.0,
    },
    fg_dark: OkLch {
        l: 0.92,
        c: 0.045,
        h: 175.0,
    },
    fg_light: OkLch {
        l: 0.18,
        c: 0.060,
        h: 290.0,
    },
    anchor: 0.0,
    tint: 0.0,
    cmin: 0.20,
    cmax: 0.26,
    l_dark: 0.72,
    l_light: 0.50,
    stagger: [-0.03, 0.01, 0.04, -0.02, -0.01, 0.02],
};
const SUNSET: Mood = Mood {
    bg_dark: OkLch {
        l: 0.12,
        c: 0.060,
        h: 350.0,
    },
    bg_light: OkLch {
        l: 0.96,
        c: 0.030,
        h: 30.0,
    },
    fg_dark: OkLch {
        l: 0.90,
        c: 0.050,
        h: 30.0,
    },
    fg_light: OkLch {
        l: 0.24,
        c: 0.060,
        h: 350.0,
    },
    anchor: 20.0,
    tint: 0.32,
    cmin: 0.12,
    cmax: 0.18,
    l_dark: 0.70,
    l_light: 0.50,
    stagger: [-0.05, 0.02, 0.07, -0.04, -0.02, 0.04],
};
const VAPORWAVE: Mood = Mood {
    bg_dark: OkLch {
        l: 0.15,
        c: 0.060,
        h: 315.0,
    },
    bg_light: OkLch {
        l: 0.96,
        c: 0.025,
        h: 320.0,
    },
    fg_dark: OkLch {
        l: 0.90,
        c: 0.060,
        h: 190.0,
    },
    fg_light: OkLch {
        l: 0.26,
        c: 0.060,
        h: 310.0,
    },
    anchor: 320.0,
    tint: 0.28,
    cmin: 0.10,
    cmax: 0.16,
    l_dark: 0.74,
    l_light: 0.52,
    stagger: [-0.04, 0.02, 0.06, -0.03, -0.01, 0.04],
};
const MIDNIGHT: Mood = Mood {
    bg_dark: OkLch {
        l: 0.07,
        c: 0.035,
        h: 250.0,
    },
    bg_light: OkLch {
        l: 0.95,
        c: 0.020,
        h: 240.0,
    },
    fg_dark: OkLch {
        l: 0.88,
        c: 0.020,
        h: 220.0,
    },
    fg_light: OkLch {
        l: 0.22,
        c: 0.045,
        h: 250.0,
    },
    anchor: 250.0,
    tint: 0.20,
    cmin: 0.07,
    cmax: 0.12,
    l_dark: 0.62,
    l_light: 0.42,
    stagger: [-0.04, 0.01, 0.05, -0.03, -0.02, 0.03],
};
const AURORA: Mood = Mood {
    bg_dark: OkLch {
        l: 0.08,
        c: 0.045,
        h: 240.0,
    },
    bg_light: OkLch {
        l: 0.96,
        c: 0.025,
        h: 220.0,
    },
    fg_dark: OkLch {
        l: 0.92,
        c: 0.040,
        h: 175.0,
    },
    fg_light: OkLch {
        l: 0.20,
        c: 0.055,
        h: 240.0,
    },
    anchor: 160.0,
    tint: 0.42,
    cmin: 0.12,
    cmax: 0.18,
    l_dark: 0.70,
    l_light: 0.50,
    stagger: [-0.05, 0.02, 0.06, -0.03, -0.01, 0.04],
};

// --- practical (x_palette_practical.go) --------------------------------------

/// Image hues on a hard-extreme background, ANSI at WCAG AAA.
fn high_contrast(dominant: &[String], light: bool) -> Palette {
    let mut p = shaped(
        dominant,
        light,
        &Shape {
            bg: [(0.05, 0.010), (0.99, 0.005)],
            fg: [(0.95, 0.015), (0.10, 0.020)],
            ansi: |c, light| {
                lch(
                    if light { 0.32 } else { 0.82 },
                    clamp_f(c.c, 0.10, 0.18),
                    c.h,
                )
            },
            stagger: [-0.03, 0.01, 0.04, -0.02, -0.01, 0.02],
        },
    );
    for i in 1..=6 {
        if color::contrast_ratio(&p[0], &p[i]) >= MIN_HIGH_CONTRAST_RATIO {
            continue;
        }
        p[i] = boost_contrast_against_bg(&p[i], &p[0], MIN_HIGH_CONTRAST_RATIO);
        p[i + 8] = generate_bright_version(&p[i]);
    }
    p
}

/// Two hues, the dominant one and its complement, at three lightnesses.
fn duotone(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let comp = fmod(base + 180.0, 360.0);
    let mut p = empty();
    if light {
        p[0] = color::oklch_to_hex(lch(0.97, 0.008, base));
        p[7] = color::oklch_to_hex(lch(0.20, 0.025, base));
    } else {
        p[0] = color::oklch_to_hex(lch(0.12, 0.018, base));
        p[7] = color::oklch_to_hex(lch(0.90, 0.020, base));
    }
    let levels = [-0.10, -0.10, 0.04, 0.04, 0.14, 0.14];
    let hues = [base, comp, base, comp, base, comp];
    let lbase = if light { 0.50 } else { 0.62 };
    for i in 0..6 {
        let l = clamp_f(lbase + levels[i], 0.30, 0.85);
        p[i + 1] = color::oklch_to_hex(lch(l, 0.09, hues[i]));
    }
    finalize(&mut p);
    p
}

// --- schemes (x_palette_schemes.go) ------------------------------------------

fn scheme_background(base: f64, light: bool) -> (String, String) {
    if light {
        (
            color::oklch_to_hex(lch(0.96, 0.012, base)),
            color::oklch_to_hex(lch(0.22, 0.04, base)),
        )
    } else {
        (
            color::oklch_to_hex(lch(0.13, 0.022, base)),
            color::oklch_to_hex(lch(0.88, 0.025, base)),
        )
    }
}

fn scheme(base: f64, light: bool, hues: [f64; 6], chromas: [f64; 6], offsets: [f64; 6]) -> Palette {
    let lbase = if light { 0.48 } else { 0.65 };
    let mut p = empty();
    let (bg, fg) = scheme_background(base, light);
    p[0] = bg;
    p[7] = fg;
    for i in 0..6 {
        let l = clamp_f(lbase + offsets[i], 0.30, 0.85);
        p[i + 1] = color::oklch_to_hex(lch(l, chromas[i], fmod(hues[i] + 360.0, 360.0)));
    }
    finalize(&mut p);
    p
}

fn complementary(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let comp = fmod(base + 180.0, 360.0);
    scheme(
        base,
        light,
        [base - 8.0, comp - 8.0, base, comp, base + 8.0, comp + 8.0],
        [0.14, 0.14, 0.11, 0.11, 0.16, 0.16],
        [-0.06, -0.04, 0.04, 0.02, 0.08, 0.06],
    )
}

fn triadic(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let h2 = fmod(base + 120.0, 360.0);
    let h3 = fmod(base + 240.0, 360.0);
    scheme(
        base,
        light,
        [base, h2, h3, base, h2, h3],
        [0.13, 0.13, 0.13, 0.16, 0.16, 0.16],
        [0.05, 0.05, 0.05, -0.07, -0.07, -0.07],
    )
}

fn split_complementary(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let h2 = fmod(base + 150.0, 360.0);
    let h3 = fmod(base + 210.0, 360.0);
    scheme(
        base,
        light,
        [base, h2, h3, base, h2, h3],
        [0.14, 0.13, 0.13, 0.17, 0.16, 0.16],
        [0.05, 0.05, 0.05, -0.06, -0.06, -0.06],
    )
}

fn tetradic(dominant: &[String], light: bool) -> Palette {
    let base = dominant_hue(dominant);
    let h2 = fmod(base + 90.0, 360.0);
    let h3 = fmod(base + 180.0, 360.0);
    let h4 = fmod(base + 270.0, 360.0);
    scheme(
        base,
        light,
        [base, h2, h3, h4, base, h3],
        [0.12, 0.12, 0.12, 0.12, 0.15, 0.15],
        [0.04, -0.02, 0.04, -0.02, 0.10, 0.10],
    )
}
