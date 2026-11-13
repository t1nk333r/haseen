// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! WebP, a port of golang.org/x/image/webp and its riff reader (v0.46.0):
//! a lossy VP8 frame is a 4:2:0 YCbCr image, with an ALPH chunk an
//! NYCbCrA one; a lossless VP8L frame is NRGBA.

use crate::image::Image;
use crate::{vp8, vp8l};

fn invalid() -> String {
    "webp: invalid format".into()
}

/// A chunk: its id, its declared length, and what the file holds of it.
type Chunk<'a> = ([u8; 4], u32, &'a [u8]);

struct Riff<'a> {
    data: &'a [u8],
    pos: usize,
    total_len: u32,
    chunk_left: u32,
    padded: bool,
    err: Option<String>,
}

fn u32le(b: &[u8]) -> u32 {
    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
}

impl<'a> Riff<'a> {
    /// riff.NewReader: the form type and a reader of its chunks.
    fn new(data: &'a [u8]) -> Result<([u8; 4], Riff<'a>), String> {
        if data.len() < 8 || &data[..4] != b"RIFF" {
            return Err("riff: missing RIFF chunk header".into());
        }
        let chunk_len = u32le(&data[4..8]);
        if chunk_len < 4 {
            return Err("riff: short chunk data".into());
        }
        if data.len() < 12 {
            return Err("riff: short chunk data".into());
        }
        let form = [data[8], data[9], data[10], data[11]];
        Ok((
            form,
            Riff {
                data,
                pos: 12,
                total_len: chunk_len - 4,
                chunk_left: 0,
                padded: false,
                err: None,
            },
        ))
    }

    /// Reader.Next: skips the last chunk (its data is handed out as a slice,
    /// so all of it is left to skip, as Go's io.Copy discards the rest),
    /// then the next chunk's id, its length, and what the file holds of its
    /// data. Ok(None) is io.EOF.
    fn next(&mut self) -> Result<Option<Chunk<'a>>, String> {
        if let Some(e) = &self.err {
            return Err(e.clone());
        }
        let fail = |s: &mut Self, e: &str| -> Result<Option<Chunk<'a>>, String> {
            s.err = Some(e.to_string());
            Err(e.to_string())
        };
        if self.chunk_left != 0 {
            let avail = (self.data.len() - self.pos) as u32;
            if avail < self.chunk_left {
                self.pos = self.data.len();
                return fail(self, "riff: short chunk data");
            }
            self.pos += self.chunk_left as usize;
            self.total_len -= self.chunk_left;
            self.chunk_left = 0;
        }
        if self.padded {
            if self.total_len == 0 {
                return fail(self, "riff: list subchunk too long");
            }
            self.total_len -= 1;
            if self.pos >= self.data.len() {
                return fail(self, "riff: missing padding byte");
            }
            self.pos += 1;
        }
        if self.total_len == 0 {
            self.err = Some("EOF".into());
            return Ok(None);
        }
        if self.total_len < 8 {
            return fail(self, "riff: short chunk header");
        }
        self.total_len -= 8;
        if self.data.len() - self.pos < 8 {
            self.pos = self.data.len();
            return fail(self, "riff: short chunk header");
        }
        let h = &self.data[self.pos..self.pos + 8];
        self.pos += 8;
        let id = [h[0], h[1], h[2], h[3]];
        let len = u32le(&h[4..8]);
        if len > self.total_len {
            return fail(self, "riff: list subchunk too long");
        }
        self.chunk_left = len;
        self.padded = len & 1 == 1;
        let end = (self.pos + len as usize).min(self.data.len());
        Ok(Some((id, len, &self.data[self.pos..end])))
    }
}

enum Decoded {
    Config(usize, usize),
    Image(Image),
}

fn decode_inner(data: &[u8], config_only: bool) -> Result<Decoded, String> {
    let (form, mut riff) = Riff::new(data)?;
    if &form != b"WEBP" {
        return Err(invalid());
    }
    let mut alpha: Option<(Vec<u8>, usize)> = None;
    let mut want_alpha = false;
    let mut seen_vp8x = false;
    let (mut wm1, mut hm1) = (0u32, 0u32);
    loop {
        let Some((id, len, chunk)) = riff.next()? else {
            return Err(invalid());
        };
        match &id {
            b"ALPH" => {
                if !want_alpha {
                    return Err(invalid());
                }
                want_alpha = false;
                let Some(&head) = chunk.first() else {
                    return Err(invalid());
                };
                let (mut a, stride) = read_alpha(&chunk[1..], wm1, hm1, head & 0x03)?;
                unfilter_alpha(&mut a, stride, (head >> 2) & 0x03);
                alpha = Some((a, stride));
            }
            b"VP8 " => {
                if want_alpha || (len as i32) < 0 {
                    return Err(invalid());
                }
                let mut d = vp8::Decoder::new(chunk, len as usize);
                d.decode_frame_header()?;
                if seen_vp8x
                    && (d.frame.width != wm1 as usize + 1 || d.frame.height != hm1 as usize + 1)
                {
                    return Err(invalid());
                }
                if config_only {
                    return Ok(Decoded::Config(d.frame.width, d.frame.height));
                }
                let m = d.decode_frame()?;
                return Ok(Decoded::Image(match alpha {
                    Some((a, a_stride)) => Image::NYCbCrA {
                        ycc: m,
                        a,
                        a_stride,
                    },
                    None => Image::YCbCr(m),
                }));
            }
            b"VP8L" => {
                if alpha.is_some() {
                    return Err(invalid());
                }
                if config_only {
                    let (w, h) = vp8l::decode_config(chunk)?;
                    return Ok(Decoded::Config(w, h));
                }
                if seen_vp8x {
                    if chunk.len() < 5 {
                        return Err(if chunk.is_empty() {
                            invalid()
                        } else {
                            "unexpected EOF".into()
                        });
                    }
                    let (w, h) = vp8l::decode_config(&chunk[..5])?;
                    if w != wm1 as usize + 1 || h != hm1 as usize + 1 {
                        return Err(invalid());
                    }
                }
                let (pix, w, h) = vp8l::decode(chunk)?;
                return Ok(Decoded::Image(Image::Nrgba { w, h, pix }));
            }
            b"VP8X" => {
                if seen_vp8x {
                    return Err(invalid());
                }
                seen_vp8x = true;
                if len != 10 {
                    return Err(invalid());
                }
                if chunk.len() < 10 {
                    // io.ReadFull: EOF when nothing came, as Go words it.
                    return Err(if chunk.is_empty() {
                        "EOF"
                    } else {
                        "unexpected EOF"
                    }
                    .into());
                }
                let b = chunk;
                want_alpha = b[0] & (1 << 4) != 0;
                wm1 = b[4] as u32 | (b[5] as u32) << 8 | (b[6] as u32) << 16;
                hm1 = b[7] as u32 | (b[8] as u32) << 8 | (b[9] as u32) << 16;
                let (w, h) = (wm1 as u64 + 1, hm1 as u64 + 1);
                if w * h > (1 << 31) - 1 {
                    return Err(invalid());
                }
                if config_only {
                    return Ok(Decoded::Config(w as usize, h as usize));
                }
            }
            _ => {}
        }
    }
}

fn read_alpha(
    rest: &[u8],
    wm1: u32,
    hm1: u32,
    compression: u8,
) -> Result<(Vec<u8>, usize), String> {
    match compression {
        0 => {
            let (w, h) = (wm1 as usize + 1, hm1 as usize + 1);
            if rest.len() < w * h {
                return Err(if rest.is_empty() {
                    "EOF"
                } else {
                    "unexpected EOF"
                }
                .into());
            }
            Ok((rest[..w * h].to_vec(), w))
        }
        1 => {
            if wm1 > 0x3fff || hm1 > 0x3fff {
                return Err(invalid());
            }
            let mut stream = vec![
                0x2f,
                wm1 as u8,
                ((wm1 >> 8) as u8) | ((hm1 << 6) as u8),
                (hm1 >> 2) as u8,
                (hm1 >> 10) as u8,
            ];
            stream.extend_from_slice(rest);
            let (pix, _, _) = vp8l::decode(&stream)?;
            let a = pix.as_chunks::<4>().0.iter().map(|p| p[1]).collect();
            Ok((a, wm1 as usize + 1))
        }
        _ => Err(invalid()),
    }
}

fn unfilter_alpha(alpha: &mut [u8], stride: usize, filter: u8) {
    if alpha.is_empty() || stride == 0 {
        return;
    }
    match filter {
        1 => {
            for i in 1..stride {
                alpha[i] = alpha[i].wrapping_add(alpha[i - 1]);
            }
            let mut i = stride;
            while i < alpha.len() {
                alpha[i] = alpha[i].wrapping_add(alpha[i - stride]);
                for j in 1..stride {
                    alpha[i + j] = alpha[i + j].wrapping_add(alpha[i + j - 1]);
                }
                i += stride;
            }
        }
        2 => {
            for i in 1..stride {
                alpha[i] = alpha[i].wrapping_add(alpha[i - 1]);
            }
            for i in stride..alpha.len() {
                alpha[i] = alpha[i].wrapping_add(alpha[i - stride]);
            }
        }
        3 => {
            for i in 1..stride {
                alpha[i] = alpha[i].wrapping_add(alpha[i - 1]);
            }
            let mut i = stride;
            while i < alpha.len() {
                alpha[i] = alpha[i].wrapping_add(alpha[i - stride]);
                for j in 1..stride {
                    let c = alpha[i + j - stride - 1] as i32;
                    let b = alpha[i + j - stride] as i32;
                    let a = alpha[i + j - 1] as i32;
                    let x = (a + b - c).clamp(0, 255);
                    alpha[i + j] = alpha[i + j].wrapping_add(x as u8);
                }
                i += stride;
            }
        }
        _ => {}
    }
}

pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    match decode_inner(data, true)? {
        Decoded::Config(w, h) => Ok((w, h)),
        Decoded::Image(_) => unreachable!("config_only returns a size"),
    }
}

pub fn decode(data: &[u8]) -> Result<Image, String> {
    match decode_inner(data, false)? {
        Decoded::Image(m) => Ok(m),
        Decoded::Config(..) => unreachable!("a decode returns an image"),
    }
}
