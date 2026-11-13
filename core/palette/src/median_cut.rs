//! Median-cut quantisation in OKLab: the image's dominant colours and how
//! many sampled pixels each stands for. A port of x_median_cut.go
//! (omacom/aether, MIT, NOTICE.md).

use crate::analysis::{
    CHROMA_BOOST_MAX_EXTRA, CHROMA_BOOST_RAMP_CHROMA, CHROMA_BOOST_THRESHOLD, MIN_PIXELS_TO_SAMPLE,
};
use crate::color::{self, OkLab, Rgb};
use crate::gosort::sort_slice;

struct Bucket {
    colors: Vec<OkLab>,
    ranges: [[f64; 2]; 3],
}

fn axis(c: &OkLab, axis: usize) -> f64 {
    match axis {
        0 => c.l,
        1 => c.a,
        _ => c.b,
    }
}

impl Bucket {
    fn new(colors: Vec<OkLab>) -> Bucket {
        let mut ranges = [[0.0; 2]; 3];
        if let Some(first) = colors.first() {
            ranges = [[first.l, first.l], [first.a, first.a], [first.b, first.b]];
            for c in &colors {
                let vals = [c.l, c.a, c.b];
                for ch in 0..3 {
                    if vals[ch] < ranges[ch][0] {
                        ranges[ch][0] = vals[ch];
                    }
                    if vals[ch] > ranges[ch][1] {
                        ranges[ch][1] = vals[ch];
                    }
                }
            }
        }
        Bucket { colors, ranges }
    }

    fn range(&self, axis: usize) -> f64 {
        self.ranges[axis][1] - self.ranges[axis][0]
    }

    /// Lightness weighs a little more: it is what the eye sees first.
    fn longest_axis(&self) -> usize {
        let l = self.range(0) * 1.2;
        let a = self.range(1);
        let b = self.range(2);
        if l >= a && l >= b {
            return 0;
        }
        if a >= b {
            1
        } else {
            2
        }
    }

    fn split(mut self) -> (Bucket, Bucket) {
        let ax = self.longest_axis();
        sort_slice(&mut self.colors, |p, q| axis(p, ax) < axis(q, ax));
        let mid = self.colors.len() / 2;
        let right = self.colors.split_off(mid);
        (Bucket::new(self.colors), Bucket::new(right))
    }

    fn average(&self) -> (OkLab, usize) {
        let n = self.colors.len();
        if n == 0 {
            return (OkLab::default(), 0);
        }
        let (mut l, mut a, mut b) = (0.0, 0.0, 0.0);
        for c in &self.colors {
            l += c.l;
            a += c.a;
            b += c.b;
        }
        let nf = n as f64;
        (
            OkLab {
                l: l / nf,
                a: a / nf,
                b: b / nf,
            },
            n,
        )
    }

    fn volume(&self) -> f64 {
        self.range(0) * self.range(1) * self.range(2) * self.colors.len() as f64
    }
}

pub struct Entry {
    pub hex: String,
    pub count: usize,
}

/// Splits the bucket of largest volume until there are n; the average of
/// each, in bucket order.
pub fn median_cut(colors: Vec<OkLab>, n: usize) -> Vec<Entry> {
    if colors.is_empty() {
        return Vec::new();
    }
    if colors.len() <= n {
        return deduplicate(&colors);
    }
    let mut buckets = vec![Bucket::new(colors)];
    while buckets.len() < n {
        let mut max_volume = 0.0;
        let mut split: Option<usize> = None;
        for (i, b) in buckets.iter().enumerate() {
            if b.colors.len() > 1 {
                let v = b.volume();
                if v > max_volume {
                    max_volume = v;
                    split = Some(i);
                }
            }
        }
        let Some(i) = split else { break };
        let (left, right) = buckets.remove(i).split();
        buckets.insert(i, right);
        buckets.insert(i, left);
    }
    buckets
        .iter()
        .filter_map(|b| {
            let (avg, count) = b.average();
            (count > 0).then(|| Entry {
                hex: color::oklab_to_hex(avg),
                count,
            })
        })
        .collect()
}

fn deduplicate(colors: &[OkLab]) -> Vec<Entry> {
    const THRESHOLD: f64 = 0.01;
    let mut unique: Vec<Entry> = Vec::new();
    for c in colors {
        let dup = unique
            .iter()
            .any(|u| color::oklab_distance(*c, color::hex_to_oklab(&u.hex)) < THRESHOLD);
        if !dup {
            unique.push(Entry {
                hex: color::oklab_to_hex(*c),
                count: 1,
            });
        }
    }
    unique
}

/// Extra copies of vivid pixels, graded by chroma: one at the threshold, up
/// to CHROMA_BOOST_MAX_EXTRA, so a small saturated highlight is not drowned
/// by a large muted background.
fn boost_chromatic(pixels: &[OkLab]) -> Vec<OkLab> {
    let mut out = Vec::with_capacity(pixels.len() * 2);
    for px in pixels {
        out.push(*px);
        let chroma = (px.a * px.a + px.b * px.b).sqrt();
        if chroma <= CHROMA_BOOST_THRESHOLD {
            continue;
        }
        let t = (chroma - CHROMA_BOOST_THRESHOLD) / CHROMA_BOOST_RAMP_CHROMA;
        let extra =
            ((t * CHROMA_BOOST_MAX_EXTRA as f64).round() as i64).clamp(1, CHROMA_BOOST_MAX_EXTRA);
        for _ in 0..extra {
            out.push(*px);
        }
    }
    out
}

/// Dominant colours (upper case hex) and their pixel counts, most first.
pub fn extract_from_pixels(pixels: &[Rgb], n: usize) -> Result<(Vec<String>, Vec<usize>), String> {
    if pixels.len() < MIN_PIXELS_TO_SAMPLE / 10 {
        return Err("not enough pixels to extract colors".into());
    }
    let lab: Vec<OkLab> = pixels.iter().map(|p| color::rgb_to_oklab(*p)).collect();
    let mut quantized = median_cut(boost_chromatic(&lab), n);
    if quantized.is_empty() {
        return Err("no colors extracted from image".into());
    }
    sort_slice(&mut quantized, |a, b| a.count > b.count);
    let hex = quantized.iter().map(|e| e.hex.to_uppercase()).collect();
    let counts = quantized.iter().map(|e| e.count).collect();
    Ok((hex, counts))
}
