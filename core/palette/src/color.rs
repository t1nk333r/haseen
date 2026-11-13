//! Colour spaces and conversions: sRGB, HSL, OKLab, OKLCH, WCAG contrast.
//! A port of the Go generator's convert.go, oklab.go, accessibility.go and
//! darken_lighten.go, themselves adapted from omacom/aether (MIT, NOTICE.md).
//! Hex colours stay strings, as in Go: the dominant colours are upper case
//! and reach the palette as they are, so the case is part of the answer.

use crate::gomath;
use std::sync::OnceLock;

/// A colour with channels 0-255 (not clamped).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb {
    pub r: f64,
    pub g: f64,
    pub b: f64,
}

/// H 0-360, S and L 0-100.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Hsl {
    pub h: f64,
    pub s: f64,
    pub l: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct OkLab {
    pub l: f64,
    pub a: f64,
    pub b: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OkLch {
    pub l: f64,
    pub c: f64,
    pub h: f64,
}

pub fn clamp_l(l: f64) -> f64 {
    gomath::max(0.0, gomath::min(100.0, l))
}

/// Clamps to 0-255 and rounds half away from zero, as Go's clampByte.
pub fn clamp_byte(v: f64) -> u8 {
    if v <= 0.0 {
        return 0;
    }
    if v >= 255.0 {
        return 255;
    }
    v.round() as u8
}

fn hex_digit(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// `#rrggbb` or `rrggbb`, either case; anything else is black, as Go's
/// regexp `(?i)^#?([a-f\d]{2}){3}$` and its fallback.
pub fn hex_to_rgb(hex: &str) -> Rgb {
    let s = hex.as_bytes();
    let s = s.strip_prefix(b"#").unwrap_or(s);
    if s.len() != 6 {
        return Rgb {
            r: 0.0,
            g: 0.0,
            b: 0.0,
        };
    }
    let mut v = [0u8; 3];
    for (i, pair) in s.chunks(2).enumerate() {
        match (hex_digit(pair[0]), hex_digit(pair[1])) {
            (Some(hi), Some(lo)) => v[i] = hi * 16 + lo,
            _ => {
                return Rgb {
                    r: 0.0,
                    g: 0.0,
                    b: 0.0,
                }
            }
        }
    }
    Rgb {
        r: v[0] as f64,
        g: v[1] as f64,
        b: v[2] as f64,
    }
}

pub fn rgb_to_hsl(r: f64, g: f64, b: f64) -> Hsl {
    let (r, g, b) = (r / 255.0, g / 255.0, b / 255.0);
    let max = gomath::max(r, gomath::max(g, b));
    let min = gomath::min(r, gomath::min(g, b));
    let mut h = 0.0;
    let mut s = 0.0;
    let l = (max + min) / 2.0;
    if max != min {
        let d = max - min;
        s = if l > 0.5 {
            d / (2.0 - max - min)
        } else {
            d / (max + min)
        };
        // Go's switch takes the first case that matches.
        if max == r {
            h = (g - b) / d;
            if g < b {
                h += 6.0;
            }
            h /= 6.0;
        } else if max == g {
            h = ((b - r) / d + 2.0) / 6.0;
        } else if max == b {
            h = ((r - g) / d + 4.0) / 6.0;
        }
    }
    Hsl {
        h: h * 360.0,
        s: s * 100.0,
        l: l * 100.0,
    }
}

fn hue2rgb(p: f64, q: f64, mut t: f64) -> f64 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * t;
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    }
    p
}

pub fn hsl_to_rgb(h: f64, s: f64, l: f64) -> Rgb {
    let (h, s, l) = (h / 360.0, s / 100.0, l / 100.0);
    let (r, g, b);
    if s == 0.0 {
        r = l;
        g = l;
        b = l;
    } else {
        let q = if l < 0.5 {
            l * (1.0 + s)
        } else {
            l + s - l * s
        };
        let p = 2.0 * l - q;
        r = hue2rgb(p, q, h + 1.0 / 3.0);
        g = hue2rgb(p, q, h);
        b = hue2rgb(p, q, h - 1.0 / 3.0);
    }
    Rgb {
        r: r * 255.0,
        g: g * 255.0,
        b: b * 255.0,
    }
}

pub fn rgb_to_hex(r: f64, g: f64, b: f64) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        clamp_byte(r),
        clamp_byte(g),
        clamp_byte(b)
    )
}

pub fn hsl_to_hex(h: f64, s: f64, l: f64) -> String {
    let rgb = hsl_to_rgb(h, s, l);
    rgb_to_hex(rgb.r, rgb.g, rgb.b)
}

pub fn hex_to_hsl(hex: &str) -> Hsl {
    let rgb = hex_to_rgb(hex);
    rgb_to_hsl(rgb.r, rgb.g, rgb.b)
}

fn srgb_to_linear_raw(c: f64) -> f64 {
    if c <= 0.04045 {
        return c / 12.92;
    }
    gomath::pow((c + 0.055) / 1.055, 2.4)
}

/// srgbToLinear(v / 255): every channel the generator converts is a whole
/// number from a pixel or a hex string, so the 256 answers are computed once.
fn channel_to_linear(v: f64) -> f64 {
    static TABLE: OnceLock<[f64; 256]> = OnceLock::new();
    if (0.0..=255.0).contains(&v) && v.fract() == 0.0 {
        let table = TABLE.get_or_init(|| {
            let mut t = [0.0; 256];
            for (k, slot) in t.iter_mut().enumerate() {
                *slot = srgb_to_linear_raw(k as f64 / 255.0);
            }
            t
        });
        return table[v as usize];
    }
    srgb_to_linear_raw(v / 255.0)
}

fn linear_to_srgb(c: f64) -> f64 {
    if c <= 0.0031308 {
        return 12.92 * c;
    }
    1.055 * gomath::pow(c, 1.0 / 2.4) - 0.055
}

pub fn rgb_to_oklab(rgb: Rgb) -> OkLab {
    let r = channel_to_linear(rgb.r);
    let g = channel_to_linear(rgb.g);
    let b = channel_to_linear(rgb.b);
    let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    let l_ = gomath::cbrt(l);
    let m_ = gomath::cbrt(m);
    let s_ = gomath::cbrt(s);
    OkLab {
        l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    }
}

/// OKLab to linear sRGB, not clamped.
pub fn oklab_to_linear_rgb(lab: OkLab) -> (f64, f64, f64) {
    let l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    let m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    let s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;
    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;
    (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )
}

pub fn oklab_to_rgb(lab: OkLab) -> Rgb {
    let (r, g, b) = oklab_to_linear_rgb(lab);
    let r = gomath::max(0.0, gomath::min(1.0, r));
    let g = gomath::max(0.0, gomath::min(1.0, g));
    let b = gomath::max(0.0, gomath::min(1.0, b));
    Rgb {
        r: (linear_to_srgb(r) * 255.0).round(),
        g: (linear_to_srgb(g) * 255.0).round(),
        b: (linear_to_srgb(b) * 255.0).round(),
    }
}

pub fn oklab_to_oklch(lab: OkLab) -> OkLch {
    let c = (lab.a * lab.a + lab.b * lab.b).sqrt();
    let mut h = gomath::atan2(lab.b, lab.a) * 180.0 / std::f64::consts::PI;
    if h < 0.0 {
        h += 360.0;
    }
    OkLch { l: lab.l, c, h }
}

pub fn oklch_to_oklab(lch: OkLch) -> OkLab {
    let rad = lch.h * std::f64::consts::PI / 180.0;
    OkLab {
        l: lch.l,
        a: lch.c * gomath::cos(rad),
        b: lch.c * gomath::sin(rad),
    }
}

pub fn hex_to_oklab(hex: &str) -> OkLab {
    rgb_to_oklab(hex_to_rgb(hex))
}

pub fn hex_to_oklch(hex: &str) -> OkLch {
    oklab_to_oklch(hex_to_oklab(hex))
}

pub fn oklab_to_hex(lab: OkLab) -> String {
    let rgb = oklab_to_rgb(lab);
    rgb_to_hex(rgb.r, rgb.g, rgb.b)
}

pub fn oklch_to_hex(lch: OkLch) -> String {
    oklab_to_hex(oklch_to_oklab(lch))
}

pub fn oklab_distance(a: OkLab, b: OkLab) -> f64 {
    let dl = a.l - b.l;
    let da = a.a - b.a;
    let db = a.b - b.b;
    (dl * dl + da * da + db * db).sqrt()
}

/// WCAG 2.0 relative luminance.
fn relative_luminance(hex: &str) -> f64 {
    let rgb = hex_to_rgb(hex);
    0.2126 * channel_to_linear(rgb.r)
        + 0.7152 * channel_to_linear(rgb.g)
        + 0.0722 * channel_to_linear(rgb.b)
}

/// WCAG 2.0 contrast ratio, 1 to 21.
pub fn contrast_ratio(hex1: &str, hex2: &str) -> f64 {
    let l1 = relative_luminance(hex1);
    let l2 = relative_luminance(hex2);
    let lighter = gomath::max(l1, l2);
    let darker = gomath::min(l1, l2);
    (lighter + 0.05) / (darker + 0.05)
}

/// Each channel times percent/100: 0 is black, 100 unchanged.
pub fn darken_rgb(hex: &str, percent: f64) -> String {
    let rgb = hex_to_rgb(hex);
    rgb_to_hex(
        (rgb.r * percent / 100.0).round(),
        (rgb.g * percent / 100.0).round(),
        (rgb.b * percent / 100.0).round(),
    )
}

/// Each channel blended toward white: 0 unchanged, 100 white.
pub fn lighten_rgb(hex: &str, percent: f64) -> String {
    let rgb = hex_to_rgb(hex);
    rgb_to_hex(
        (rgb.r + (255.0 - rgb.r) * percent / 100.0).round(),
        (rgb.g + (255.0 - rgb.g) * percent / 100.0).round(),
        (rgb.b + (255.0 - rgb.b) * percent / 100.0).round(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    // Go's TestOKLabRoundTrip.
    #[test]
    fn oklab_round_trip() {
        for hex in [
            "#0000ff", "#1030ff", "#7aa2f7", "#ff0000", "#00ff00", "#808080", "#ffffff", "#000000",
            "#e9dff0",
        ] {
            assert_eq!(oklab_to_hex(hex_to_oklab(hex)), hex);
        }
    }

    #[test]
    fn hex_parsing_is_gos() {
        assert_eq!(
            hex_to_rgb("#A0b1C2"),
            Rgb {
                r: 160.0,
                g: 177.0,
                b: 194.0
            }
        );
        assert_eq!(
            hex_to_rgb("a0b1c2"),
            Rgb {
                r: 160.0,
                g: 177.0,
                b: 194.0
            }
        );
        for bad in ["#abc", "#abcdeg", "##abcdef", "#abcdef0", ""] {
            assert_eq!(
                hex_to_rgb(bad),
                Rgb {
                    r: 0.0,
                    g: 0.0,
                    b: 0.0
                },
                "{bad}"
            );
        }
        assert_eq!(rgb_to_hex(-3.0, 127.5, 300.0), "#0080ff");
    }

    #[test]
    fn the_table_is_the_formula() {
        for k in 0..=255 {
            let v = k as f64;
            assert_eq!(
                channel_to_linear(v).to_bits(),
                srgb_to_linear_raw(v / 255.0).to_bits()
            );
        }
    }
}
