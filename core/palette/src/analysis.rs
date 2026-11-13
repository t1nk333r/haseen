//! Picking colours out of the dominant set: background and foreground,
//! monochrome detection, the ANSI slot assignment, bright variants. A port of
//! x_analysis.go and x_constants.go (omacom/aether, MIT, NOTICE.md).

use crate::color::{self, OkLch};
use crate::gomath;
use crate::gosort::sort_slice;

pub const IMAGE_SCALE_SIZE: i64 = 400;
pub const MIN_PIXELS_TO_SAMPLE: usize = 1000;
pub const MAX_PIXELS_TO_SAMPLE: i64 = 50000;
pub const DOMINANT_COLORS_TO_EXTRACT: usize = 48;

pub const CHROMA_BOOST_THRESHOLD: f64 = 0.04;
pub const CHROMA_BOOST_MAX_EXTRA: i64 = 3;
pub const CHROMA_BOOST_RAMP_CHROMA: f64 = 0.16;
pub const BACKGROUND_DOMINANCE_WEIGHT: f64 = 0.6;

pub const MONOCHROME_CHROMA_THRESHOLD: f64 = 0.04;
pub const MONOCHROME_IMAGE_THRESHOLD: f64 = 0.6;
pub const HUE_CLUSTER_MAGNITUDE_THRESHOLD: f64 = 0.85;
pub const MONO_CHROMATIC_COVERAGE_FLOOR: f64 = 0.06;
pub const AUTO_MONO_ARC_DEG: f64 = 46.0;
pub const EXPLICIT_MONO_ARC_DEG: f64 = 28.0;
pub const MONO_CHROMA_FACTOR_FLOOR: f64 = 0.4;
pub const MONO_ACCENT_MIN_L_STEP: f64 = 0.072;

pub const ACCENT_CHROMA_FLOOR: f64 = 0.05;
pub const ACCENT_CHROMA_CEIL: f64 = 0.16;
pub const NEAR_ACHROMATIC_CHROMA: f64 = 0.03;
pub const ACCENT_MIN_DELTA_E: f64 = 0.05;
pub const ACCENT_SUPPORT_CHROMA: f64 = 0.04;
pub const HUE_SUPPORT_TOL: f64 = 30.0;
pub const MIN_ACCENT_HUE_SUPPORT: f64 = 0.025;
pub const MIN_MEANINGFUL_TINT_CHROMA: f64 = 0.008;

pub const MIN_CHROMA_FOR_ANSI_MATCH: f64 = 0.035;
pub const LOW_CHROMA_THRESHOLD: f64 = 0.05;
pub const IDEAL_CHROMA_MIN: f64 = 0.06;
pub const IDEAL_CHROMA_MAX: f64 = 0.20;
pub const TOO_DARK_LIGHTNESS: f64 = 0.25;
pub const TOO_BRIGHT_LIGHTNESS: f64 = 0.87;

pub const MIN_CONTRAST_RATIO: f64 = 4.5;
pub const MIN_HIGH_CONTRAST_RATIO: f64 = 7.0;
pub const MIN_COMMENT_CONTRAST: f64 = 3.0;
pub const MIN_FG_BG_CONTRAST: f64 = 7.0;

pub const BRIGHT_COLOR_LIGHTNESS_BOOST: f64 = 0.12;
pub const BRIGHT_COLOR_SATURATION_BOOST: f64 = 1.1;

/// OKLCH hues of the six ANSI slots, from the pure sRGB primaries.
pub const OKLCH_ANSI_HUES: [f64; 6] = [29.2, 139.1, 111.3, 266.7, 326.4, 194.8];

/// The circular distance between two hues, 0 to 180.
pub fn hue_distance(h1: f64, h2: f64) -> f64 {
    let diff = (h1 - h2).abs();
    if diff > 180.0 {
        360.0 - diff
    } else {
        diff
    }
}

/// Mostly achromatic, or chromatic hues in one narrow arc; every colour
/// counts the same.
pub fn is_monochrome_image(colors: &[String]) -> bool {
    if colors.is_empty() {
        return false;
    }
    let mut low = 0;
    let (mut sin_sum, mut cos_sum) = (0.0, 0.0);
    let mut chromatic = 0;
    for c in colors {
        let lch = color::hex_to_oklch(c);
        if lch.c < MONOCHROME_CHROMA_THRESHOLD {
            low += 1;
            continue;
        }
        let rad = lch.h * std::f64::consts::PI / 180.0;
        sin_sum += gomath::sin(rad);
        cos_sum += gomath::cos(rad);
        chromatic += 1;
    }
    if low as f64 / colors.len() as f64 > MONOCHROME_IMAGE_THRESHOLD {
        return true;
    }
    if chromatic >= 4 {
        let mag = (sin_sum * sin_sum + cos_sum * cos_sum).sqrt() / chromatic as f64;
        if mag > HUE_CLUSTER_MAGNITUDE_THRESHOLD {
            return true;
        }
    }
    false
}

/// The coverage-weighted classifier the default mode uses: colour covers
/// less than MONO_CHROMATIC_COVERAGE_FLOOR of the frame, or sits in one hue.
pub fn is_monochrome_weighted(colors: &[String], weights: Option<&[f64]>) -> bool {
    if colors.is_empty() {
        return false;
    }
    let Some(weights) = weights else {
        return is_monochrome_image(colors);
    };
    let (mut achro, mut chroma, mut sin_sum, mut cos_sum) = (0.0, 0.0, 0.0, 0.0);
    for (i, c) in colors.iter().enumerate() {
        let w = weights.get(i).copied().unwrap_or(0.0);
        let lch = color::hex_to_oklch(c);
        if lch.c < MONOCHROME_CHROMA_THRESHOLD {
            achro += w;
            continue;
        }
        chroma += w;
        let rad = lch.h * std::f64::consts::PI / 180.0;
        sin_sum += gomath::sin(rad) * w;
        cos_sum += gomath::cos(rad) * w;
    }
    let total = achro + chroma;
    if total == 0.0 {
        return false;
    }
    if chroma / total < MONO_CHROMATIC_COVERAGE_FLOOR {
        return true;
    }
    let mag = (sin_sum * sin_sum + cos_sum * cos_sum).sqrt() / chroma;
    mag > HUE_CLUSTER_MAGNITUDE_THRESHOLD
}

/// The lightest (or darkest) colour, nudged toward coverage when weights are
/// given. Returns the colour and its index.
fn by_perceptual_lightness(
    colors: &[String],
    weights: Option<&[f64]>,
    lightest: bool,
    exclude: Option<&[bool]>,
) -> (String, usize) {
    let mut best_index = 0;
    let mut best_score = f64::NEG_INFINITY;
    for (i, c) in colors.iter().enumerate() {
        if exclude.is_some_and(|e| e.get(i).copied().unwrap_or(false)) {
            continue;
        }
        let lab = color::hex_to_oklab(c);
        let mut score = if lightest { lab.l } else { 1.0 - lab.l };
        if let Some(w) = weights {
            if i < w.len() {
                score += BACKGROUND_DOMINANCE_WEIGHT * w[i];
            }
        }
        if score > best_score {
            best_score = score;
            best_index = i;
        }
    }
    (colors[best_index].clone(), best_index)
}

pub fn find_background_color(
    colors: &[String],
    weights: Option<&[f64]>,
    light: bool,
) -> (String, usize) {
    by_perceptual_lightness(colors, weights, light, None)
}

/// The foreground: the opposite extreme, then the colour with the most
/// contrast, then a synthesized one (index None) when nothing reads.
pub fn find_foreground_color(
    colors: &[String],
    weights: Option<&[f64]>,
    light: bool,
    bg: &str,
    used: &[bool],
) -> (String, Option<usize>) {
    let (fg, fg_index) = by_perceptual_lightness(colors, weights, !light, Some(used));
    let contrast = color::contrast_ratio(bg, &fg);
    if contrast >= MIN_FG_BG_CONTRAST {
        return (fg, Some(fg_index));
    }
    let mut candidates: Vec<(usize, f64)> = Vec::new();
    for (i, c) in colors.iter().enumerate() {
        if used.get(i).copied().unwrap_or(false) {
            continue;
        }
        let cr = color::contrast_ratio(bg, c);
        if cr > contrast {
            candidates.push((i, cr));
        }
    }
    sort_slice(&mut candidates, |a, b| a.1 > b.1);
    if let Some(&(i, cr)) = candidates.first() {
        if cr >= MIN_CONTRAST_RATIO {
            return (colors[i].clone(), Some(i));
        }
    }
    let bg_lab = color::hex_to_oklab(bg);
    let mut fg_lab = color::hex_to_oklab(&fg);
    fg_lab.l = if bg_lab.l < 0.5 { 0.97 } else { 0.05 };
    (color::oklab_to_hex(fg_lab), None)
}

/// How well a colour fits an ANSI slot's hue; lower is better.
pub fn color_score(lch: OkLch, target_hue: f64, light: bool) -> f64 {
    let hue_score = hue_distance(lch.h, target_hue) * 2.0;
    let chroma_score = if lch.c < MIN_CHROMA_FOR_ANSI_MATCH {
        80.0
    } else if lch.c < LOW_CHROMA_THRESHOLD {
        40.0
    } else if lch.c < IDEAL_CHROMA_MIN {
        15.0
    } else if lch.c <= IDEAL_CHROMA_MAX {
        0.0
    } else {
        (lch.c - IDEAL_CHROMA_MAX) * 50.0
    };
    let ideal_l = if light { 0.45 } else { 0.60 };
    let lightness_score = if lch.l < TOO_DARK_LIGHTNESS {
        (TOO_DARK_LIGHTNESS - lch.l) * 200.0
    } else if lch.l > TOO_BRIGHT_LIGHTNESS {
        (lch.l - TOO_BRIGHT_LIGHTNESS) * 150.0
    } else {
        (lch.l - ideal_l).abs() * 20.0
    };
    hue_score + chroma_score + lightness_score
}

/// The pool index that best fits a hue, skipping used ones; 0 when none.
pub fn find_best_color_match(
    target_hue: f64,
    pool: &[String],
    used: &[bool],
    light: bool,
) -> usize {
    let mut best_index: Option<usize> = None;
    let mut best_score = f64::INFINITY;
    for (i, c) in pool.iter().enumerate() {
        if used.get(i).copied().unwrap_or(false) {
            continue;
        }
        let score = color_score(color::hex_to_oklch(c), target_hue, light);
        if score < best_score {
            best_score = score;
            best_index = Some(i);
        }
    }
    best_index.unwrap_or(0)
}

/// A bright variant for slots 9-15: lighter, or more chroma when there is no
/// lightness left.
pub fn generate_bright_version(hex: &str) -> String {
    let lab = color::hex_to_oklab(hex);
    let lch = color::oklab_to_oklch(lab);
    if lab.l >= 0.78 {
        let l = gomath::min(0.94, lab.l + 0.04);
        let c = gomath::min(0.32, gomath::max(lch.c + 0.04, lch.c * 1.3));
        return color::oklch_to_hex(OkLch { l, c, h: lch.h });
    }
    let headroom = 0.92 - lab.l;
    let boost = gomath::max(
        0.04,
        gomath::min(BRIGHT_COLOR_LIGHTNESS_BOOST, headroom * 0.6),
    );
    let l = gomath::min(0.92, lab.l + boost);
    let c = gomath::min(0.30, lch.c * BRIGHT_COLOR_SATURATION_BOOST);
    color::oklch_to_hex(OkLch { l, c, h: lch.h })
}

pub struct LightnessInfo {
    pub color: String,
    pub lightness: f64,
    pub hue: f64,
}

pub fn sort_colors_by_lightness(colors: &[String]) -> Vec<LightnessInfo> {
    let mut out: Vec<LightnessInfo> = colors
        .iter()
        .map(|c| {
            let lch = color::hex_to_oklch(c);
            LightnessInfo {
                color: c.clone(),
                lightness: lch.l,
                hue: lch.h,
            }
        })
        .collect();
    sort_slice(&mut out, |a, b| a.lightness < b.lightness);
    out
}

/// Global greedy assignment of pool colours to the six ANSI slots: at each
/// step the best (slot, colour) pair left. Returns the pool index per slot.
pub fn find_optimal_ansi_assignment(
    pool: &[String],
    used: &[bool],
    light: bool,
) -> [Option<usize>; 6] {
    let mut all: Vec<Vec<(usize, f64)>> = Vec::with_capacity(6);
    for &target in OKLCH_ANSI_HUES.iter() {
        let mut cands: Vec<(usize, f64)> = pool
            .iter()
            .enumerate()
            .map(|(i, c)| {
                if used.get(i).copied().unwrap_or(false) {
                    (i, f64::INFINITY)
                } else {
                    (i, color_score(color::hex_to_oklch(c), target, light))
                }
            })
            .collect();
        sort_slice(&mut cands, |a, b| a.1 < b.1);
        all.push(cands);
    }
    let mut assignments: [Option<usize>; 6] = [None; 6];
    let mut assigned = vec![false; pool.len()];
    for (i, u) in used.iter().enumerate() {
        if *u && i < assigned.len() {
            assigned[i] = true;
        }
    }
    for _ in 0..6 {
        let mut best: Option<(usize, usize)> = None;
        let mut best_score = f64::INFINITY;
        for (a, cands) in all.iter().enumerate() {
            if assignments[a].is_some() {
                continue;
            }
            // The first unassigned candidate is the slot's best (sorted).
            if let Some(&(pi, score)) = cands.iter().find(|(pi, _)| !assigned[*pi]) {
                if score < best_score {
                    best_score = score;
                    best = Some((a, pi));
                }
            }
        }
        let Some((a, pi)) = best else { break };
        assignments[a] = Some(pi);
        assigned[pi] = true;
    }
    assignments
}
