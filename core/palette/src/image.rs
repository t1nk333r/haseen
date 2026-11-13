//! Decoded images in the shapes Go's decoders return them, because the
//! scaler treats each shape differently (golang.org/x/image/draw has a fast
//! path per type, and they round differently): PNG gives Gray, Gray16,
//! RGBA, RGBA64, NRGBA, NRGBA64 or Paletted; GIF Paletted; JPEG Gray, YCbCr,
//! RGBA or CMYK; WebP YCbCr, NYCbCrA or NRGBA. Every image starts at (0, 0):
//! a GIF frame's offset inside its screen changes nothing the scaler sees.

use crate::{gif, jpeg, png, webp};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ratio {
    R444,
    R422,
    R420,
    R440,
    R411,
    R410,
}

/// Go's image.YCbCr: full-resolution Y, subsampled Cb and Cr.
pub struct YCbCr {
    pub w: usize,
    pub h: usize,
    pub y: Vec<u8>,
    pub cb: Vec<u8>,
    pub cr: Vec<u8>,
    pub y_stride: usize,
    pub c_stride: usize,
    pub ratio: Ratio,
}

impl YCbCr {
    /// Go's image.NewYCbCr for a rectangle at the origin.
    pub fn new(w: usize, h: usize, ratio: Ratio) -> YCbCr {
        let (cw, ch) = match ratio {
            Ratio::R422 => (w.div_ceil(2), h),
            Ratio::R420 => (w.div_ceil(2), h.div_ceil(2)),
            Ratio::R440 => (w, h.div_ceil(2)),
            Ratio::R411 => (w.div_ceil(4), h),
            Ratio::R410 => (w.div_ceil(4), h.div_ceil(2)),
            Ratio::R444 => (w, h),
        };
        YCbCr {
            w,
            h,
            y: vec![0; w * h],
            cb: vec![0; cw * ch],
            cr: vec![0; cw * ch],
            y_stride: w,
            c_stride: cw,
            ratio,
        }
    }

    pub fn y_offset(&self, x: usize, y: usize) -> usize {
        y * self.y_stride + x
    }

    pub fn c_offset(&self, x: usize, y: usize) -> usize {
        match self.ratio {
            Ratio::R422 => y * self.c_stride + x / 2,
            Ratio::R420 => (y / 2) * self.c_stride + x / 2,
            Ratio::R440 => (y / 2) * self.c_stride + x,
            Ratio::R411 => y * self.c_stride + x / 4,
            Ratio::R410 => (y / 2) * self.c_stride + x / 4,
            Ratio::R444 => y * self.c_stride + x,
        }
    }
}

pub enum Image {
    Gray {
        w: usize,
        h: usize,
        pix: Vec<u8>,
    },
    Gray16 {
        w: usize,
        h: usize,
        pix: Vec<u16>,
    },
    /// Premultiplied, 4 bytes a pixel.
    Rgba {
        w: usize,
        h: usize,
        pix: Vec<u8>,
    },
    /// Not premultiplied, 4 bytes a pixel.
    Nrgba {
        w: usize,
        h: usize,
        pix: Vec<u8>,
    },
    Rgba64 {
        w: usize,
        h: usize,
        pix: Vec<u16>,
    },
    Nrgba64 {
        w: usize,
        h: usize,
        pix: Vec<u16>,
    },
    /// The palette already as each entry's premultiplied RGBA() in 16 bits.
    Paletted {
        w: usize,
        h: usize,
        pix: Vec<u8>,
        palette: Vec<[u32; 4]>,
    },
    YCbCr(YCbCr),
    NYCbCrA {
        ycc: YCbCr,
        a: Vec<u8>,
        a_stride: usize,
    },
    Cmyk {
        w: usize,
        h: usize,
        pix: Vec<u8>,
    },
}

/// color.RGBA{r, g, b, a}.RGBA()
pub fn rgba_color(r: u8, g: u8, b: u8, a: u8) -> [u32; 4] {
    let x = |v: u8| v as u32 * 0x101;
    [x(r), x(g), x(b), x(a)]
}

/// color.NRGBA{r, g, b, a}.RGBA()
pub fn nrgba_color(r: u8, g: u8, b: u8, a: u8) -> [u32; 4] {
    let a32 = a as u32;
    let x = |v: u8| (v as u32 * 0x101) * a32 / 0xff;
    [x(r), x(g), x(b), a32 * 0x101]
}

/// color.YCbCr.RGBA(), 16 bits a channel.
pub fn ycbcr_to_rgb16(y: u8, cb: u8, cr: u8) -> [u32; 3] {
    let yy1 = y as i32 * 0x10101;
    let cb1 = cb as i32 - 128;
    let cr1 = cr as i32 - 128;
    let clamp = |v: i32| -> u32 {
        if (v as u32) & 0xff000000 == 0 {
            (v >> 8) as u32
        } else {
            (!(v >> 31) & 0xffff) as u32
        }
    };
    [
        clamp(yy1 + 91881 * cr1),
        clamp(yy1 - 22554 * cb1 - 46802 * cr1),
        clamp(yy1 + 116130 * cb1),
    ]
}

impl Image {
    pub fn size(&self) -> (usize, usize) {
        match self {
            Image::Gray { w, h, .. }
            | Image::Gray16 { w, h, .. }
            | Image::Rgba { w, h, .. }
            | Image::Nrgba { w, h, .. }
            | Image::Rgba64 { w, h, .. }
            | Image::Nrgba64 { w, h, .. }
            | Image::Paletted { w, h, .. }
            | Image::Cmyk { w, h, .. } => (*w, *h),
            Image::YCbCr(c) | Image::NYCbCrA { ycc: c, .. } => (c.w, c.h),
        }
    }

    /// Whether the scaler's horizontal pass writes alpha as the constant 1
    /// (Go's scaleX_Gray and scaleX_YCbCr444/422/420/440) instead of summing
    /// it like every other path.
    pub fn alpha_is_one(&self) -> bool {
        match self {
            Image::Gray { .. } => true,
            Image::YCbCr(c) => !matches!(c.ratio, Ratio::R411 | Ratio::R410),
            _ => false,
        }
    }

    /// The premultiplied 16-bit colour Go's scaler reads for this pixel, by
    /// the same integer arithmetic as the path it takes for this type.
    #[inline]
    pub fn rgba16(&self, x: usize, y: usize) -> [u32; 4] {
        match self {
            Image::Gray { w, pix, .. } => {
                let v = pix[y * w + x] as u32 * 0x101;
                [v, v, v, 0xffff]
            }
            Image::Gray16 { w, pix, .. } => {
                let v = pix[y * w + x] as u32;
                [v, v, v, 0xffff]
            }
            Image::Rgba { w, pix, .. } => {
                let i = (y * w + x) * 4;
                rgba_color(pix[i], pix[i + 1], pix[i + 2], pix[i + 3])
            }
            Image::Nrgba { w, pix, .. } => {
                let i = (y * w + x) * 4;
                nrgba_color(pix[i], pix[i + 1], pix[i + 2], pix[i + 3])
            }
            Image::Rgba64 { w, pix, .. } => {
                let i = (y * w + x) * 4;
                [
                    pix[i] as u32,
                    pix[i + 1] as u32,
                    pix[i + 2] as u32,
                    pix[i + 3] as u32,
                ]
            }
            Image::Nrgba64 { w, pix, .. } => {
                let i = (y * w + x) * 4;
                let a = pix[i + 3] as u32;
                [
                    pix[i] as u32 * a / 0xffff,
                    pix[i + 1] as u32 * a / 0xffff,
                    pix[i + 2] as u32 * a / 0xffff,
                    a,
                ]
            }
            Image::Paletted {
                w, pix, palette, ..
            } => {
                if palette.is_empty() {
                    return [0; 4];
                }
                palette[pix[y * w + x] as usize]
            }
            Image::YCbCr(c) => {
                let yi = c.y_offset(x, y);
                let ci = c.c_offset(x, y);
                let [r, g, b] = ycbcr_to_rgb16(c.y[yi], c.cb[ci], c.cr[ci]);
                [r, g, b, 0xffff]
            }
            Image::NYCbCrA {
                ycc: c,
                a,
                a_stride,
            } => {
                let yi = c.y_offset(x, y);
                let ci = c.c_offset(x, y);
                let [r, g, b] = ycbcr_to_rgb16(c.y[yi], c.cb[ci], c.cr[ci]);
                let a = a[y * a_stride + x] as u32 * 0x101;
                [r * a / 0xffff, g * a / 0xffff, b * a / 0xffff, a]
            }
            Image::Cmyk { w, pix, .. } => {
                let i = (y * w + x) * 4;
                let wk = 0xffff - pix[i + 3] as u32 * 0x101;
                let ch = |v: u8| (0xffff - v as u32 * 0x101) * wk / 0xffff;
                [ch(pix[i]), ch(pix[i + 1]), ch(pix[i + 2]), 0xffff]
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Png,
    Gif,
    Jpeg,
    Webp,
}

/// image.Decode's sniffing: each registered format's magic, `?` matching
/// any byte.
fn sniff(data: &[u8]) -> Option<Format> {
    let matches = |magic: &[u8]| {
        data.len() >= magic.len() && magic.iter().zip(data).all(|(m, b)| *m == b'?' || m == b)
    };
    if matches(b"GIF8?a") {
        Some(Format::Gif)
    } else if matches(b"\xff\xd8") {
        Some(Format::Jpeg)
    } else if matches(b"\x89PNG\r\n\x1a\n") {
        Some(Format::Png)
    } else if matches(b"RIFF????WEBPVP8") {
        Some(Format::Webp)
    } else {
        None
    }
}

/// image.DecodeConfig: the dimensions from the header, before any pixel.
pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    match sniff(data) {
        Some(Format::Png) => png::decode_config(data),
        Some(Format::Gif) => gif::decode_config(data),
        Some(Format::Jpeg) => jpeg::decode_config(data),
        Some(Format::Webp) => webp::decode_config(data),
        None => Err("image: unknown format".into()),
    }
}

/// image.Decode.
pub fn decode(data: &[u8]) -> Result<Image, String> {
    match sniff(data) {
        Some(Format::Png) => png::decode(data),
        Some(Format::Gif) => gif::decode(data),
        Some(Format::Jpeg) => jpeg::decode(data),
        Some(Format::Webp) => webp::decode(data),
        None => Err("image: unknown format".into()),
    }
}
