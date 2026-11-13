// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! The wallpaper scaled to fit 400 px with golang.org/x/image/draw's
//! CatmullRom kernel (`kernelScaler.Scale` into an NRGBA image with
//! draw.Over), then sampled (x_pixel_sampler.go, decode.go).
//!
//! The scaler is ported for exactness: its two passes in float64 in Go's
//! order, each source type's integer conversion (image::Image::rgba16),
//! premultiplied alpha, `ftou` rounding and NRGBA's SetRGBA64. draw.Over
//! into the fresh, transparent destination computes what draw.Src does
//! (the destination term is zero), so Go's choice between them by
//! `Opaque()` changes nothing and is not made here.

use crate::analysis::{IMAGE_SCALE_SIZE, MAX_PIXELS_TO_SAMPLE};
use crate::color::Rgb;
use crate::generate::path_error;
use crate::image::{self, Image};

/// A wallpaper is read and scaled before sampling, so a hostile or simply
/// enormous image must be refused from its header, before decoding.
pub const MAX_IMAGE_DIMENSION: usize = 20000;
pub const MAX_IMAGE_PIXELS: u64 = 200_000_000;

/// Header first, then pixels; aether's wallpaper.DecodeImage.
pub fn decode_image(data: &[u8]) -> Result<Image, String> {
    let (w, h) = image::decode_config(data).map_err(|e| format!("decode image header: {e}"))?;
    if w == 0
        || h == 0
        || w > MAX_IMAGE_DIMENSION
        || h > MAX_IMAGE_DIMENSION
        || (w as u64) * (h as u64) > MAX_IMAGE_PIXELS
    {
        return Err(format!("unsafe image dimensions {w}x{h}"));
    }
    image::decode(data)
}

#[derive(Clone, Copy)]
struct Source {
    i: usize,
    j: usize,
    inv_total_weight: f64,
    inv_total_weight_ffff: f64,
}

#[derive(Clone, Copy)]
struct Contrib {
    coord: usize,
    weight: f64,
}

struct Distrib {
    sources: Vec<Source>,
    contribs: Vec<Contrib>,
}

const SUPPORT: f64 = 2.0;

/// draw.CatmullRom's kernel, in its order of operations.
fn catmull_rom(t: f64) -> f64 {
    if t < 1.0 {
        return ((1.5 * t - 2.5) * t * t) + 1.0;
    }
    (((-0.5 * t + 2.5) * t) - 4.0) * t + 2.0
}

/// newDistrib: how sw source columns (or rows) spread over dw.
fn new_distrib(dw: i32, sw: i32) -> Distrib {
    let scale = sw as f64 / dw as f64;
    let (mut half_width, mut arg_scale) = (SUPPORT, 1.0);
    if scale > 1.0 {
        half_width *= scale;
        arg_scale = 1.0 / scale;
    }
    let mut spans: Vec<(i32, i32, f64)> = Vec::with_capacity(dw as usize);
    for x in 0..dw {
        let center = (x as f64 + 0.5) * scale - 0.5;
        let i = ((center - half_width).floor() as i32).max(0);
        let mut j = (center + half_width).ceil() as i32;
        if j > sw {
            j = sw;
            if j < i {
                j = i;
            }
        }
        spans.push((i, j, center));
    }
    let mut sources = Vec::with_capacity(dw as usize);
    let mut contribs = Vec::new();
    for (i, j, center) in spans {
        let mut total = 0.0;
        let start = contribs.len();
        for coord in i..j {
            let mut t = (center - coord as f64) * arg_scale;
            if t < 0.0 {
                t = -t;
            }
            if t >= SUPPORT {
                continue;
            }
            let weight = catmull_rom(t);
            if weight == 0.0 {
                continue;
            }
            total += weight;
            contribs.push(Contrib {
                coord: coord as usize,
                weight,
            });
        }
        let total = 1.0 / total;
        sources.push(Source {
            i: start,
            j: contribs.len(),
            inv_total_weight: total,
            inv_total_weight_ffff: total / 65535.0,
        });
    }
    Distrib { sources, contribs }
}

/// ftou: [0, 1] to [0, 0xffff].
fn ftou(f: f64) -> u32 {
    let i = (65535.0 * f + 0.5) as i32;
    i.clamp(0, 0xffff) as u32
}

/// CatmullRom.Scale of the whole image onto a dw x dh NRGBA image; its Pix.
pub fn scale(src: &Image, dw: usize, dh: usize) -> Vec<u8> {
    let (sw, sh) = src.size();
    let mut dst = vec![0u8; dw * dh * 4];
    if sw == 0 || sh == 0 || dw == 0 || dh == 0 {
        return dst;
    }
    let hz = new_distrib(dw as i32, sw as i32);
    let vt = new_distrib(dh as i32, sh as i32);
    let alpha_one = src.alpha_is_one();

    // scaleX: the source's columns spread over a dw x sh temporary image.
    let mut tmp = vec![[0f64; 4]; dw * sh];
    let mut t = 0;
    for y in 0..sh {
        for s in &hz.sources {
            let (mut pr, mut pg, mut pb, mut pa) = (0.0, 0.0, 0.0, 0.0);
            for c in &hz.contribs[s.i..s.j] {
                let p = src.rgba16(c.coord, y);
                pr += p[0] as f64 * c.weight;
                pg += p[1] as f64 * c.weight;
                pb += p[2] as f64 * c.weight;
                if !alpha_one {
                    pa += p[3] as f64 * c.weight;
                }
            }
            let inv = s.inv_total_weight_ffff;
            tmp[t] = if alpha_one {
                [pr * inv, pg * inv, pb * inv, 1.0]
            } else {
                [pr * inv, pg * inv, pb * inv, pa * inv]
            };
            t += 1;
        }
    }

    // scaleY: the temporary image's rows over the destination, then
    // NRGBA.SetRGBA64.
    for dx in 0..dw {
        for (dy, s) in vt.sources.iter().enumerate() {
            let (mut pr, mut pg, mut pb, mut pa) = (0.0, 0.0, 0.0, 0.0);
            for c in &vt.contribs[s.i..s.j] {
                let p = &tmp[c.coord * dw + dx];
                pr += p[0] * c.weight;
                pg += p[1] * c.weight;
                pb += p[2] * c.weight;
                pa += p[3] * c.weight;
            }
            if pr > pa {
                pr = pa;
            }
            if pg > pa {
                pg = pa;
            }
            if pb > pa {
                pb = pa;
            }
            let mut r = ftou(pr * s.inv_total_weight);
            let mut g = ftou(pg * s.inv_total_weight);
            let mut b = ftou(pb * s.inv_total_weight);
            let a = ftou(pa * s.inv_total_weight);
            if a != 0 && a != 0xffff {
                r = r * 0xffff / a;
                g = g * 0xffff / a;
                b = b * 0xffff / a;
            }
            let i = (dy * dw + dx) * 4;
            dst[i] = (r >> 8) as u8;
            dst[i + 1] = (g >> 8) as u8;
            dst[i + 2] = (b >> 8) as u8;
            dst[i + 3] = (a >> 8) as u8;
        }
    }
    dst
}

/// Go's math.Round(float64(a) * 400 / float64(b)) as int, at least 1.
fn fit(a: usize, b: usize) -> usize {
    let v = (a as f64 * IMAGE_SCALE_SIZE as f64 / b as f64).round();
    // Go's int(NaN) for an empty frame is less than 1 too.
    let v = if v.is_nan() { 0 } else { v as i64 };
    v.max(1) as usize
}

/// Every step-th pixel of the scaled image, skipping transparent ones
/// (alpha under 128).
pub fn load_and_sample_pixels(path: impl AsRef<std::path::Path>) -> Result<Vec<Rgb>, String> {
    let path = path.as_ref();
    let data = std::fs::read(path)
        .map_err(|e| format!("failed to open image: {}", path_error("open", path, &e)))?;
    let src = decode_image(&data).map_err(|e| format!("failed to decode image: {e}"))?;
    let (sw, sh) = src.size();
    let (dw, dh) = if sw >= sh {
        (IMAGE_SCALE_SIZE as usize, fit(sh, sw))
    } else {
        (fit(sw, sh), IMAGE_SCALE_SIZE as usize)
    };
    let dst = scale(&src, dw, dh);
    drop(src);
    let total = (dw * dh) as f64;
    let step = 1f64.max((total / MAX_PIXELS_TO_SAMPLE as f64).floor()) as usize;
    let mut colors = Vec::new();
    let mut y = 0;
    while y < dh {
        let mut x = 0;
        while x < dw {
            let o = (y * dw + x) * 4;
            if dst[o + 3] >= 128 {
                colors.push(Rgb {
                    r: dst[o] as f64,
                    g: dst[o + 1] as f64,
                    b: dst[o + 2] as f64,
                });
            }
            x += step;
        }
        y += step;
    }
    Ok(colors)
}
