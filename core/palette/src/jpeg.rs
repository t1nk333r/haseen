//! JPEG, a port of Go's image/jpeg decoder (Go 1.27: reader.go, scan.go,
//! huffman.go and the integer IDCT of dct.go). It returns what Go returns:
//! Gray, YCbCr with Go's subsample ratios (no chroma upsampling: the scaler
//! reads the subsampled planes), RGBA for RGB files, CMYK for 4-component
//! ones. Porting the IDCT is what makes a JPEG's palette exactly Go's; a
//! libjpeg-style decoder rounds differently (plan 167). Arithmetic is int32
//! and wraps, as Go's does.

use crate::image::{ycbcr_to_rgb16, Image, Ratio, YCbCr};

const BLOCK: usize = 64;
type Block = [i32; BLOCK];

const UNZIG: [usize; BLOCK] = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20,
    13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59,
    52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
];

const SOF0: u8 = 0xc0;
const SOF1: u8 = 0xc1;
const SOF2: u8 = 0xc2;
const DHT: u8 = 0xc4;
const RST0: u8 = 0xd0;
const RST7: u8 = 0xd7;
const SOI: u8 = 0xd8;
const EOI: u8 = 0xd9;
const SOS: u8 = 0xda;
const DQT: u8 = 0xdb;
const DRI: u8 = 0xdd;
const COM: u8 = 0xfe;
const APP0: u8 = 0xe0;
const APP14: u8 = 0xee;
const APP15: u8 = 0xef;

fn format_error(s: &str) -> String {
    format!("invalid JPEG format: {s}")
}

fn unsupported(s: &str) -> String {
    format!("unsupported JPEG feature: {s}")
}

const UNEXPECTED_EOF: &str = "unexpected EOF";

fn missing_ff00() -> String {
    format_error("missing 0xff00 sequence")
}

fn short_huffman() -> String {
    format_error("short Huffman data")
}

#[derive(Clone, Copy, Default)]
struct Component {
    h: usize,
    v: usize,
    c: u8,
    tq: u8,
    expand_h: usize,
    expand_v: usize,
}

#[derive(Clone)]
struct Huffman {
    n_codes: i32,
    lut: [u16; 256],
    vals: [u8; 256],
    min_codes: [i32; 16],
    max_codes: [i32; 16],
    vals_indices: [i32; 16],
}

impl Default for Huffman {
    fn default() -> Self {
        Huffman {
            n_codes: 0,
            lut: [0; 256],
            vals: [0; 256],
            min_codes: [0; 16],
            max_codes: [0; 16],
            vals_indices: [0; 16],
        }
    }
}

#[derive(Default)]
struct Bits {
    a: u32,
    m: u32,
    n: i32,
}

struct Decoder<'a> {
    data: &'a [u8],
    i: usize,
    n_unreadable: usize,
    bits: Bits,
    width: usize,
    height: usize,
    img1: Option<(Vec<u8>, usize)>, // Pix, stride
    img3: Option<YCbCr>,
    black: Option<(Vec<u8>, usize)>,
    flex: bool,
    max_h: usize,
    max_v: usize,
    ri: usize,
    n_comp: usize,
    baseline: bool,
    progressive: bool,
    jfif: bool,
    adobe_valid: bool,
    adobe_transform: u8,
    eob_run: u16,
    comp: [Component; 4],
    prog: [Option<Vec<Block>>; 4],
    huff: Vec<Huffman>, // [tc * 4 + th]
    quant: [Block; 4],
    tmp: [u8; 2 * BLOCK],
}

impl<'a> Decoder<'a> {
    fn new(data: &'a [u8]) -> Self {
        Decoder {
            data,
            i: 0,
            n_unreadable: 0,
            bits: Bits::default(),
            width: 0,
            height: 0,
            img1: None,
            img3: None,
            black: None,
            flex: false,
            max_h: 0,
            max_v: 0,
            ri: 0,
            n_comp: 0,
            baseline: false,
            progressive: false,
            jfif: false,
            adobe_valid: false,
            adobe_transform: 0,
            eob_run: 0,
            comp: [Component::default(); 4],
            prog: [None, None, None, None],
            huff: vec![Huffman::default(); 8],
            quant: [[0; BLOCK]; 4],
            tmp: [0; 2 * BLOCK],
        }
    }

    fn unread_byte_stuffed_byte(&mut self) {
        self.i -= self.n_unreadable;
        self.n_unreadable = 0;
        if self.bits.n >= 8 {
            self.bits.a >>= 8;
            self.bits.n -= 8;
            self.bits.m >>= 8;
        }
    }

    fn read_byte(&mut self) -> Result<u8, String> {
        let x = *self.data.get(self.i).ok_or(UNEXPECTED_EOF)?;
        self.i += 1;
        self.n_unreadable = 0;
        Ok(x)
    }

    fn read_byte_stuffed_byte(&mut self) -> Result<u8, String> {
        if self.i + 2 <= self.data.len() {
            let x = self.data[self.i];
            self.i += 1;
            self.n_unreadable = 1;
            if x != 0xff {
                return Ok(x);
            }
            if self.data[self.i] != 0x00 {
                return Err(missing_ff00());
            }
            self.i += 1;
            self.n_unreadable = 2;
            return Ok(0xff);
        }
        self.n_unreadable = 0;
        let x = self.read_byte()?;
        self.n_unreadable = 1;
        if x != 0xff {
            return Ok(x);
        }
        let x = self.read_byte()?;
        self.n_unreadable = 2;
        if x != 0x00 {
            return Err(missing_ff00());
        }
        Ok(0xff)
    }

    fn settle_unreadable(&mut self) {
        if self.n_unreadable != 0 {
            if self.bits.n >= 8 {
                self.unread_byte_stuffed_byte();
            }
            self.n_unreadable = 0;
        }
    }

    /// readFull into tmp[..n].
    fn read_full(&mut self, n: usize) -> Result<(), String> {
        self.settle_unreadable();
        if self.data.len() - self.i < n {
            self.i = self.data.len();
            return Err(UNEXPECTED_EOF.into());
        }
        self.tmp[..n].copy_from_slice(&self.data[self.i..self.i + n]);
        self.i += n;
        Ok(())
    }

    fn read_into(&mut self, out: &mut [u8]) -> Result<(), String> {
        self.settle_unreadable();
        let n = out.len();
        if self.data.len() - self.i < n {
            self.i = self.data.len();
            return Err(UNEXPECTED_EOF.into());
        }
        out.copy_from_slice(&self.data[self.i..self.i + n]);
        self.i += n;
        Ok(())
    }

    fn ignore(&mut self, n: usize) -> Result<(), String> {
        self.settle_unreadable();
        if self.data.len() - self.i < n {
            self.i = self.data.len();
            return Err(UNEXPECTED_EOF.into());
        }
        self.i += n;
        Ok(())
    }

    // --- huffman.go ---------------------------------------------------------

    fn ensure_n_bits(&mut self, n: i32) -> Result<(), String> {
        loop {
            let c = match self.read_byte_stuffed_byte() {
                Ok(c) => c,
                Err(e) if e == UNEXPECTED_EOF => return Err(short_huffman()),
                Err(e) => return Err(e),
            };
            self.bits.a = self.bits.a << 8 | c as u32;
            self.bits.n += 8;
            if self.bits.m == 0 {
                self.bits.m = 1 << 7;
            } else {
                self.bits.m <<= 8;
            }
            if self.bits.n >= n {
                return Ok(());
            }
        }
    }

    fn receive_extend(&mut self, t: u8) -> Result<i32, String> {
        if self.bits.n < t as i32 {
            self.ensure_n_bits(t as i32)?;
        }
        self.bits.n -= t as i32;
        self.bits.m = self.bits.m.checked_shr(t as u32).unwrap_or(0);
        if t == 0 {
            // Go computes 0 here too: x is 0 and its sign term adds 0.
            return Ok(0);
        }
        let s: i32 = 1 << t;
        let x = (self.bits.a.checked_shr(self.bits.n as u32).unwrap_or(0) as i32) & (s - 1);
        let sign = (x >> (t - 1)) - 1;
        Ok(x.wrapping_add(sign & ((-1i32 << t) + 1)))
    }

    fn process_dht(&mut self, mut n: i64) -> Result<(), String> {
        while n > 0 {
            if n < 17 {
                return Err(format_error("DHT has wrong length"));
            }
            self.read_full(17)?;
            let tc = self.tmp[0] >> 4;
            if tc > 1 {
                return Err(format_error("bad Tc value"));
            }
            let th = self.tmp[0] & 0x0f;
            if th > 3 || (self.baseline && th > 1) {
                return Err(format_error("bad Th value"));
            }
            let mut n_codes = [0i32; 16];
            let mut total = 0;
            for (i, nc) in n_codes.iter_mut().enumerate() {
                *nc = self.tmp[i + 1] as i32;
                total += *nc;
            }
            let idx = tc as usize * 4 + th as usize;
            self.huff[idx].n_codes = total;
            if total == 0 {
                return Err(format_error("Huffman table has zero length"));
            }
            if total > 256 {
                return Err(format_error("Huffman table has excessive length"));
            }
            n -= total as i64 + 17;
            if n < 0 {
                return Err(format_error("DHT has wrong length"));
            }
            let mut vals = [0u8; 256];
            self.read_into(&mut vals[..total as usize])?;
            let h = &mut self.huff[idx];
            h.vals[..total as usize].copy_from_slice(&vals[..total as usize]);
            h.lut = [0; 256];
            let (mut x, mut code) = (0usize, 0u32);
            for i in 0..8u32 {
                code <<= 1;
                for _ in 0..n_codes[i as usize] {
                    let base = (code << (7 - i)) as u8;
                    let lut_value = (h.vals[x] as u16) << 8 | (2 + i) as u16;
                    for k in 0..(1u32 << (7 - i)) {
                        h.lut[(base | k as u8) as usize] = lut_value;
                    }
                    code += 1;
                    x += 1;
                }
            }
            let (mut c, mut index) = (0i32, 0i32);
            for (i, &nc) in n_codes.iter().enumerate() {
                if nc == 0 {
                    h.min_codes[i] = -1;
                    h.max_codes[i] = -1;
                    h.vals_indices[i] = -1;
                } else {
                    h.min_codes[i] = c;
                    h.max_codes[i] = c + nc - 1;
                    h.vals_indices[i] = index;
                    c += nc;
                    index += nc;
                }
                c <<= 1;
            }
        }
        Ok(())
    }

    fn decode_huffman(&mut self, idx: usize) -> Result<u8, String> {
        if self.huff[idx].n_codes == 0 {
            return Err(format_error("uninitialized Huffman table"));
        }
        let mut slow = false;
        if self.bits.n < 8 {
            if let Err(e) = self.ensure_n_bits(8) {
                if e != missing_ff00() && e != short_huffman() {
                    return Err(e);
                }
                if self.n_unreadable != 0 {
                    self.unread_byte_stuffed_byte();
                }
                slow = true;
            }
        }
        if !slow {
            let v = self.huff[idx].lut[((self.bits.a >> (self.bits.n - 8) as u32) & 0xff) as usize];
            if v != 0 {
                let n = (v & 0xff) - 1;
                self.bits.n -= n as i32;
                self.bits.m >>= n;
                return Ok((v >> 8) as u8);
            }
        }
        let mut code = 0i32;
        for i in 0..16 {
            if self.bits.n == 0 {
                self.ensure_n_bits(1)?;
            }
            if self.bits.a & self.bits.m != 0 {
                code |= 1;
            }
            self.bits.n -= 1;
            self.bits.m >>= 1;
            let h = &self.huff[idx];
            if code <= h.max_codes[i] {
                return Ok(h.vals[(h.vals_indices[i] + code - h.min_codes[i]) as usize]);
            }
            code <<= 1;
        }
        Err(format_error("bad Huffman code"))
    }

    fn decode_bit(&mut self) -> Result<bool, String> {
        if self.bits.n == 0 {
            self.ensure_n_bits(1)?;
        }
        let ret = self.bits.a & self.bits.m != 0;
        self.bits.n -= 1;
        self.bits.m >>= 1;
        Ok(ret)
    }

    fn decode_bits(&mut self, n: i32) -> Result<u32, String> {
        if self.bits.n < n {
            self.ensure_n_bits(n)?;
        }
        let mut ret = self.bits.a >> (self.bits.n - n) as u32;
        ret &= (1u32 << n as u32) - 1;
        self.bits.n -= n;
        self.bits.m >>= n as u32;
        Ok(ret)
    }

    // --- reader.go ----------------------------------------------------------

    fn process_sof(&mut self, n: usize) -> Result<(), String> {
        if self.n_comp != 0 {
            return Err(format_error("multiple SOF markers"));
        }
        self.n_comp = match n {
            9 => 1,
            15 => 3,
            18 => 4,
            _ => return Err(unsupported("number of components")),
        };
        self.read_full(n)?;
        if self.tmp[0] != 8 {
            return Err(unsupported("precision"));
        }
        self.height = (self.tmp[1] as usize) << 8 | self.tmp[2] as usize;
        self.width = (self.tmp[3] as usize) << 8 | self.tmp[4] as usize;
        if self.tmp[5] as usize != self.n_comp {
            return Err(format_error("SOF has wrong length"));
        }
        let ratio_err = || unsupported("luma/chroma subsampling ratio");
        for i in 0..self.n_comp {
            self.comp[i].c = self.tmp[6 + 3 * i];
            for j in 0..i {
                if self.comp[i].c == self.comp[j].c {
                    return Err(format_error("repeated component identifier"));
                }
            }
            self.comp[i].tq = self.tmp[8 + 3 * i];
            if self.comp[i].tq > 3 {
                return Err(format_error("bad Tq value"));
            }
            let hv = self.tmp[7 + 3 * i];
            let (mut h, mut v) = ((hv >> 4) as usize, (hv & 0x0f) as usize);
            if !(1..=4).contains(&h) || !(1..=4).contains(&v) {
                return Err(format_error("luma/chroma subsampling ratio"));
            }
            if h == 3 || v == 3 {
                return Err(ratio_err());
            }
            match self.n_comp {
                1 => {
                    h = 1;
                    v = 1;
                }
                4 => match i {
                    0 => {
                        if hv != 0x11 && hv != 0x22 {
                            return Err(ratio_err());
                        }
                    }
                    1 | 2 => {
                        if hv != 0x11 {
                            return Err(ratio_err());
                        }
                    }
                    _ => {
                        if self.comp[0].h != h || self.comp[0].v != v {
                            return Err(ratio_err());
                        }
                    }
                },
                _ => {}
            }
            self.max_h = self.max_h.max(h);
            self.max_v = self.max_v.max(v);
            self.comp[i].h = h;
            self.comp[i].v = v;
        }
        if self.n_comp == 3 {
            for i in 0..3 {
                if !self.max_h.is_multiple_of(self.comp[i].h)
                    || !self.max_v.is_multiple_of(self.comp[i].v)
                {
                    return Err(ratio_err());
                }
            }
        }
        for i in 0..self.n_comp {
            self.comp[i].expand_h = self.max_h / self.comp[i].h;
            self.comp[i].expand_v = self.max_v / self.comp[i].v;
        }
        Ok(())
    }

    fn process_dqt(&mut self, mut n: i64) -> Result<(), String> {
        while n > 0 {
            n -= 1;
            let x = self.read_byte()?;
            let tq = (x & 0x0f) as usize;
            if tq > 3 {
                return Err(format_error("bad Tq value"));
            }
            match x >> 4 {
                0 => {
                    if n < BLOCK as i64 {
                        break;
                    }
                    n -= BLOCK as i64;
                    self.read_full(BLOCK)?;
                    for i in 0..BLOCK {
                        self.quant[tq][i] = self.tmp[i] as i32;
                    }
                }
                1 => {
                    if n < 2 * BLOCK as i64 {
                        break;
                    }
                    n -= 2 * BLOCK as i64;
                    self.read_full(2 * BLOCK)?;
                    for i in 0..BLOCK {
                        self.quant[tq][i] =
                            (self.tmp[2 * i] as i32) << 8 | self.tmp[2 * i + 1] as i32;
                    }
                }
                _ => return Err(format_error("bad Pq value")),
            }
        }
        if n != 0 {
            return Err(format_error("DQT has wrong length"));
        }
        Ok(())
    }

    fn process_dri(&mut self, n: usize) -> Result<(), String> {
        if n != 2 {
            return Err(format_error("DRI has wrong length"));
        }
        self.read_full(2)?;
        self.ri = (self.tmp[0] as usize) << 8 | self.tmp[1] as usize;
        Ok(())
    }

    fn process_app0(&mut self, mut n: usize) -> Result<(), String> {
        if n < 5 {
            return self.ignore(n);
        }
        self.read_full(5)?;
        n -= 5;
        self.jfif = &self.tmp[..5] == b"JFIF\x00";
        if n > 0 {
            return self.ignore(n);
        }
        Ok(())
    }

    fn process_app14(&mut self, mut n: usize) -> Result<(), String> {
        if n < 12 {
            return self.ignore(n);
        }
        self.read_full(12)?;
        n -= 12;
        if &self.tmp[..5] == b"Adobe" {
            self.adobe_valid = true;
            self.adobe_transform = self.tmp[11];
        }
        if n > 0 {
            return self.ignore(n);
        }
        Ok(())
    }

    /// The marker loop. With config_only it stops at the first SOF of a
    /// JFIF file, or at SOS.
    fn decode(&mut self, config_only: bool) -> Result<(), String> {
        self.read_full(2)?;
        if self.tmp[0] != 0xff || self.tmp[1] != SOI {
            return Err(format_error("missing SOI marker"));
        }
        loop {
            self.read_full(2)?;
            while self.tmp[0] != 0xff {
                self.tmp[0] = self.tmp[1];
                self.tmp[1] = self.read_byte()?;
            }
            let mut marker = self.tmp[1];
            if marker == 0 {
                continue;
            }
            while marker == 0xff {
                marker = self.read_byte()?;
            }
            if marker == EOI {
                // Go then finds no image, even when asked only the size.
                if config_only {
                    return Err(format_error("missing SOS marker"));
                }
                break;
            }
            if (RST0..=RST7).contains(&marker) {
                continue;
            }
            self.read_full(2)?;
            let n = ((self.tmp[0] as i64) << 8 | self.tmp[1] as i64) - 2;
            if n < 0 {
                return Err(format_error("short segment length"));
            }
            let nu = n as usize;
            match marker {
                SOF0 | SOF1 | SOF2 => {
                    self.baseline = marker == SOF0;
                    self.progressive = marker == SOF2;
                    let r = self.process_sof(nu);
                    if config_only && self.jfif {
                        return r;
                    }
                    r?;
                }
                DHT => {
                    if config_only {
                        self.ignore(nu)?
                    } else {
                        self.process_dht(n)?
                    }
                }
                DQT => {
                    if config_only {
                        self.ignore(nu)?
                    } else {
                        self.process_dqt(n)?
                    }
                }
                SOS => {
                    if config_only {
                        return Ok(());
                    }
                    self.process_sos(nu)?;
                }
                DRI => {
                    if config_only {
                        self.ignore(nu)?
                    } else {
                        self.process_dri(nu)?
                    }
                }
                APP0 => self.process_app0(nu)?,
                APP14 => self.process_app14(nu)?,
                _ => {
                    if (APP0..=APP15).contains(&marker) || marker == COM {
                        self.ignore(nu)?;
                    } else if marker < 0xc0 {
                        return Err(format_error("unknown marker"));
                    } else {
                        return Err(unsupported("unknown marker"));
                    }
                }
            }
        }
        Ok(())
    }

    fn is_rgb(&self) -> bool {
        if self.jfif {
            return false;
        }
        if self.adobe_valid && self.adobe_transform == 0 {
            return true;
        }
        self.comp[0].c == b'R' && self.comp[1].c == b'G' && self.comp[2].c == b'B'
    }

    // --- scan.go ------------------------------------------------------------

    fn make_img(&mut self, mxx: usize, myy: usize) {
        if self.n_comp == 1 {
            self.img1 = Some((vec![0; 8 * mxx * 8 * myy], 8 * mxx));
            return;
        }
        let mut ratio = Ratio::R444;
        let c = &self.comp;
        if c[1].h != c[2].h || c[1].v != c[2].v || self.max_h != c[0].h || self.max_v != c[0].v {
            self.flex = true;
        } else {
            let hr = self.max_h / c[1].h;
            let vr = self.max_v / c[1].v;
            match hr << 4 | vr {
                0x11 => ratio = Ratio::R444,
                0x12 => ratio = Ratio::R440,
                0x21 => ratio = Ratio::R422,
                0x22 => ratio = Ratio::R420,
                0x41 => ratio = Ratio::R411,
                0x42 => ratio = Ratio::R410,
                _ => self.flex = true,
            }
        }
        let mut m = YCbCr::new(8 * self.max_h * mxx, 8 * self.max_v * myy, ratio);
        m.w = self.width;
        m.h = self.height;
        self.img3 = Some(m);
        if self.n_comp == 4 {
            let (h3, v3) = (self.comp[3].h, self.comp[3].v);
            self.black = Some((vec![0; 8 * h3 * mxx * 8 * v3 * myy], 8 * h3 * mxx));
        }
    }

    fn process_sos(&mut self, n: usize) -> Result<(), String> {
        if self.n_comp == 0 {
            return Err(format_error("missing SOF marker"));
        }
        if n < 6 || 4 + 2 * self.n_comp < n || !n.is_multiple_of(2) {
            return Err(format_error("SOS has wrong length"));
        }
        self.read_full(n)?;
        let n_comp = self.tmp[0] as usize;
        if n != 4 + 2 * n_comp {
            return Err(format_error(
                "SOS length inconsistent with number of components",
            ));
        }
        let mut scan = [(0usize, 0u8, 0u8); 4]; // compIndex, td, ta
        let mut total_hv = 0;
        for i in 0..n_comp {
            let cs = self.tmp[1 + 2 * i];
            let mut comp_index: Option<usize> = None;
            for j in 0..self.n_comp {
                if cs == self.comp[j].c {
                    comp_index = Some(j);
                }
            }
            let Some(ci) = comp_index else {
                return Err(format_error("unknown component selector"));
            };
            scan[i].0 = ci;
            for j in 0..i {
                if scan[i].0 == scan[j].0 {
                    return Err(format_error("repeated component selector"));
                }
            }
            total_hv += self.comp[ci].h * self.comp[ci].v;
            scan[i].1 = self.tmp[2 + 2 * i] >> 4;
            if scan[i].1 > 3 || (self.baseline && scan[i].1 > 1) {
                return Err(format_error("bad Td value"));
            }
            scan[i].2 = self.tmp[2 + 2 * i] & 0x0f;
            if scan[i].2 > 3 || (self.baseline && scan[i].2 > 1) {
                return Err(format_error("bad Ta value"));
            }
        }
        if self.n_comp > 1 && total_hv > 10 {
            return Err(format_error("total sampling factors too large"));
        }
        let (mut zig_start, mut zig_end, mut ah, mut al) = (0i32, BLOCK as i32 - 1, 0u32, 0u32);
        if self.progressive {
            zig_start = self.tmp[1 + 2 * n_comp] as i32;
            zig_end = self.tmp[2 + 2 * n_comp] as i32;
            ah = (self.tmp[3 + 2 * n_comp] >> 4) as u32;
            al = (self.tmp[3 + 2 * n_comp] & 0x0f) as u32;
            if (zig_start == 0 && zig_end != 0) || zig_start > zig_end || BLOCK as i32 <= zig_end {
                return Err(format_error("bad spectral selection bounds"));
            }
            if zig_start != 0 && n_comp != 1 {
                return Err(format_error(
                    "progressive AC coefficients for more than one component",
                ));
            }
            if ah != 0 && ah != al + 1 {
                return Err(format_error("bad successive approximation values"));
            }
        }
        let mxx = self.width.div_ceil(8 * self.max_h);
        let myy = self.height.div_ceil(8 * self.max_v);
        if self.img1.is_none() && self.img3.is_none() {
            self.make_img(mxx, myy);
        }
        if self.progressive {
            for s in scan.iter().take(n_comp) {
                let ci = s.0;
                if self.prog[ci].is_none() {
                    self.prog[ci] = Some(vec![
                        [0; BLOCK];
                        mxx * myy * self.comp[ci].h * self.comp[ci].v
                    ]);
                }
            }
        }
        self.bits = Bits::default();
        let mut mcu = 0;
        let mut expected_rst = RST0;
        let mut dc = [0i32; 4];
        let mut block_count = 0;
        for my in 0..myy {
            for mx in 0..mxx {
                for s in scan.iter().take(n_comp) {
                    let (ci, td, ta) = *s;
                    let hi = self.comp[ci].h;
                    let vi = self.comp[ci].v;
                    for j in 0..hi * vi {
                        let (bx, by);
                        if n_comp != 1 {
                            bx = hi * mx + j % hi;
                            by = vi * my + j / hi;
                        } else {
                            let q = mxx * hi;
                            bx = block_count % q;
                            by = block_count / q;
                            block_count += 1;
                            if bx * 8 >= self.width || by * 8 >= self.height {
                                continue;
                            }
                        }
                        let mut b: Block = if self.progressive {
                            self.prog[ci].as_ref().expect("allocated")[by * mxx * hi + bx]
                        } else {
                            [0; BLOCK]
                        };
                        if ah != 0 {
                            self.refine(&mut b, 4 + ta as usize, zig_start, zig_end, 1 << al)?;
                        } else {
                            let mut zig = zig_start;
                            if zig == 0 {
                                zig += 1;
                                let value = self.decode_huffman(td as usize)?;
                                if value > 16 {
                                    return Err(unsupported("excessive DC component"));
                                }
                                let delta = self.receive_extend(value)?;
                                dc[ci] = dc[ci].wrapping_add(delta);
                                b[0] = dc[ci].wrapping_shl(al);
                            }
                            if zig <= zig_end && self.eob_run > 0 {
                                self.eob_run -= 1;
                            } else {
                                let huff = 4 + ta as usize;
                                while zig <= zig_end {
                                    let value = self.decode_huffman(huff)?;
                                    let val0 = value >> 4;
                                    let val1 = value & 0x0f;
                                    if val1 != 0 {
                                        zig += val0 as i32;
                                        if zig > zig_end {
                                            break;
                                        }
                                        let ac = self.receive_extend(val1)?;
                                        b[UNZIG[zig as usize]] = ac.wrapping_shl(al);
                                    } else {
                                        if val0 != 0x0f {
                                            self.eob_run = 1u16 << val0;
                                            if val0 != 0 {
                                                let bits = self.decode_bits(val0 as i32)?;
                                                self.eob_run |= bits as u16;
                                            }
                                            self.eob_run = self.eob_run.wrapping_sub(1);
                                            break;
                                        }
                                        zig += 0x0f;
                                    }
                                    zig += 1;
                                }
                            }
                        }
                        if self.progressive {
                            self.prog[ci].as_mut().expect("allocated")[by * mxx * hi + bx] = b;
                            continue;
                        }
                        self.reconstruct_block(&mut b, bx, by, ci)?;
                    }
                }
                mcu += 1;
                if self.ri > 0 && mcu % self.ri == 0 && mcu < mxx * myy {
                    self.read_full(2)?;
                    if self.tmp[0] != 0xff || self.tmp[1] != expected_rst {
                        self.find_rst(expected_rst)?;
                    }
                    expected_rst += 1;
                    if expected_rst == RST7 + 1 {
                        expected_rst = RST0;
                    }
                    self.bits = Bits::default();
                    dc = [0; 4];
                    self.eob_run = 0;
                }
            }
        }
        Ok(())
    }

    fn refine(
        &mut self,
        b: &mut Block,
        h: usize,
        zig_start: i32,
        zig_end: i32,
        delta: i32,
    ) -> Result<(), String> {
        if zig_start == 0 {
            if self.decode_bit()? {
                b[0] |= delta;
            }
            return Ok(());
        }
        let mut zig = zig_start;
        if self.eob_run == 0 {
            while zig <= zig_end {
                let mut z = 0i32;
                let value = self.decode_huffman(h)?;
                let val0 = value >> 4;
                let val1 = value & 0x0f;
                match val1 {
                    0 => {
                        if val0 != 0x0f {
                            self.eob_run = 1u16 << val0;
                            if val0 != 0 {
                                let bits = self.decode_bits(val0 as i32)?;
                                self.eob_run |= bits as u16;
                            }
                            break;
                        }
                    }
                    1 => {
                        z = delta;
                        if !self.decode_bit()? {
                            z = -z;
                        }
                    }
                    _ => return Err(format_error("unexpected Huffman code")),
                }
                zig = self.refine_non_zeroes(b, zig, zig_end, val0 as i32, delta)?;
                if zig > zig_end {
                    return Err(format_error("too many coefficients"));
                }
                if z != 0 {
                    b[UNZIG[zig as usize]] = z;
                }
                zig += 1;
            }
        }
        if self.eob_run > 0 {
            self.eob_run -= 1;
            self.refine_non_zeroes(b, zig, zig_end, -1, delta)?;
        }
        Ok(())
    }

    fn refine_non_zeroes(
        &mut self,
        b: &mut Block,
        mut zig: i32,
        zig_end: i32,
        mut nz: i32,
        delta: i32,
    ) -> Result<i32, String> {
        while zig <= zig_end {
            let u = UNZIG[zig as usize];
            if b[u] == 0 {
                if nz == 0 {
                    break;
                }
                nz -= 1;
                zig += 1;
                continue;
            }
            if self.decode_bit()? {
                if b[u] >= 0 {
                    b[u] = b[u].wrapping_add(delta);
                } else {
                    b[u] = b[u].wrapping_sub(delta);
                }
            }
            zig += 1;
        }
        Ok(zig)
    }

    fn reconstruct_progressive_image(&mut self) -> Result<(), String> {
        let mxx = self.width.div_ceil(8 * self.max_h);
        for i in 0..self.n_comp {
            let Some(mut coeffs) = self.prog[i].take() else {
                continue;
            };
            let v = 8 * self.max_v / self.comp[i].v;
            let h = 8 * self.max_h / self.comp[i].h;
            let stride = mxx * self.comp[i].h;
            let mut by = 0;
            while by * v < self.height {
                let mut bx = 0;
                while bx * h < self.width {
                    let mut b = coeffs[by * stride + bx];
                    self.reconstruct_block(&mut b, bx, by, i)?;
                    coeffs[by * stride + bx] = b;
                    bx += 1;
                }
                by += 1;
            }
            self.prog[i] = Some(coeffs);
        }
        Ok(())
    }

    fn reconstruct_block(
        &mut self,
        b: &mut Block,
        mut bx: usize,
        mut by: usize,
        ci: usize,
    ) -> Result<(), String> {
        let qt = &self.quant[self.comp[ci].tq as usize];
        for zig in 0..BLOCK {
            b[UNZIG[zig]] = b[UNZIG[zig]].wrapping_mul(qt[zig]);
        }
        idct(b);
        let (mut h, mut v) = (0, 0);
        if self.flex {
            h = self.comp[ci].expand_h;
            v = self.comp[ci].expand_v;
            bx *= h;
            by *= v;
        }
        let flex = self.flex;
        let (dst, stride): (&mut [u8], usize) = if self.n_comp == 1 {
            let (pix, stride) = self.img1.as_mut().expect("made");
            let s = *stride;
            (&mut pix[8 * (by * s + bx)..], s)
        } else {
            match ci {
                0 => {
                    let m = self.img3.as_mut().expect("made");
                    let s = m.y_stride;
                    (&mut m.y[8 * (by * s + bx)..], s)
                }
                1 => {
                    let m = self.img3.as_mut().expect("made");
                    let s = m.c_stride;
                    (&mut m.cb[8 * (by * s + bx)..], s)
                }
                2 => {
                    let m = self.img3.as_mut().expect("made");
                    let s = m.c_stride;
                    (&mut m.cr[8 * (by * s + bx)..], s)
                }
                3 => {
                    let (pix, stride) = self.black.as_mut().expect("made");
                    let s = *stride;
                    (&mut pix[8 * (by * s + bx)..], s)
                }
                _ => return Err(unsupported("too many components")),
            }
        };
        let clamp = |v: i32| v.wrapping_add(128).clamp(0, 255) as u8;
        if flex {
            for y in 0..8 {
                for x in 0..8 {
                    let val = clamp(b[y * 8 + x]);
                    for yy in 0..v {
                        for xx in 0..h {
                            dst[(y * v + yy) * stride + x * h + xx] = val;
                        }
                    }
                }
            }
            return Ok(());
        }
        for y in 0..8 {
            for x in 0..8 {
                dst[y * stride + x] = clamp(b[y * 8 + x]);
            }
        }
        Ok(())
    }

    fn find_rst(&mut self, expected: u8) -> Result<(), String> {
        loop {
            let mut i = 0;
            if self.tmp[0] == 0xff {
                if self.tmp[1] == expected {
                    return Ok(());
                } else if self.tmp[1] == 0xff {
                    i = 1;
                } else if self.tmp[1] != 0x00 {
                    return Err(format_error("bad RST marker"));
                }
            } else if self.tmp[1] == 0xff {
                self.tmp[0] = 0xff;
                i = 1;
            }
            self.settle_unreadable();
            if self.data.len() - self.i < 2 - i {
                self.i = self.data.len();
                return Err(UNEXPECTED_EOF.into());
            }
            for k in i..2 {
                self.tmp[k] = self.data[self.i];
                self.i += 1;
            }
        }
    }

    fn finish(mut self) -> Result<Image, String> {
        if self.progressive {
            self.reconstruct_progressive_image()?;
        }
        let (w, h) = (self.width, self.height);
        if let Some((pix, stride)) = self.img1.take() {
            let mut out = Vec::with_capacity(w * h);
            for y in 0..h {
                out.extend_from_slice(&pix[y * stride..y * stride + w]);
            }
            return Ok(Image::Gray { w, h, pix: out });
        }
        let Some(img3) = self.img3.take() else {
            return Err(format_error("missing SOS marker"));
        };
        if let Some((black, bstride)) = self.black.take() {
            return self.apply_black(img3, &black, bstride);
        }
        if self.is_rgb() {
            return self.convert_to_rgb(img3);
        }
        Ok(Image::YCbCr(img3))
    }

    fn apply_black(&self, m: YCbCr, black: &[u8], bstride: usize) -> Result<Image, String> {
        if !self.adobe_valid {
            return Err(unsupported(
                "unknown color model: 4-component JPEG doesn't have Adobe APP14 metadata",
            ));
        }
        let (w, h) = (m.w, m.h);
        let mut pix = vec![0u8; w * h * 4];
        if self.adobe_transform != 0 {
            // YCCK: imageutil.DrawYCbCr, then K inverted into alpha's place.
            for y in 0..h {
                for x in 0..w {
                    let yi = m.y_offset(x, y);
                    let ci = m.c_offset(x, y);
                    let [r, g, b] = ycbcr_to_rgb16(m.y[yi], m.cb[ci], m.cr[ci]);
                    let o = (y * w + x) * 4;
                    pix[o] = (r >> 8) as u8;
                    pix[o + 1] = (g >> 8) as u8;
                    pix[o + 2] = (b >> 8) as u8;
                    pix[o + 3] = 255 - black[y * bstride + x];
                }
            }
            return Ok(Image::Cmyk { w, h, pix });
        }
        let planes: [(&[u8], usize); 4] = [
            (&m.y, m.y_stride),
            (&m.cb, m.c_stride),
            (&m.cr, m.c_stride),
            (black, bstride),
        ];
        for (t, (src, stride)) in planes.iter().enumerate() {
            let sub = self.comp[t].h != self.comp[0].h || self.comp[t].v != self.comp[0].v;
            for y in 0..h {
                let sy = if sub { y / 2 } else { y };
                for x in 0..w {
                    let sx = if sub { x / 2 } else { x };
                    pix[(y * w + x) * 4 + t] = 255 - src[sy * stride + sx];
                }
            }
        }
        Ok(Image::Cmyk { w, h, pix })
    }

    fn convert_to_rgb(&self, m: YCbCr) -> Result<Image, String> {
        let c = &self.comp;
        let (h0, h1, h2, v0, v1, v2) = (c[0].h, c[1].h, c[2].h, c[0].v, c[1].v, c[2].v);
        if h1 != h2 || h0 % h1 != 0 || v1 != v2 || v0 % v1 != 0 {
            return Err(unsupported("luma/chroma subsampling ratio"));
        }
        let c_scale = h0 / h1;
        let (w, h) = (m.w, m.h);
        let mut pix = vec![0u8; w * h * 4];
        for y in 0..h {
            let yo = m.y_offset(0, y);
            let co = m.c_offset(0, y);
            for i in 0..w {
                let o = (y * w + i) * 4;
                pix[o] = m.y[yo + i];
                pix[o + 1] = m.cb[co + i / c_scale];
                pix[o + 2] = m.cr[co + i / c_scale];
                pix[o + 3] = 255;
            }
        }
        Ok(Image::Rgba { w, h, pix })
    }
}

// --- dct.go ---------------------------------------------------------------

const COS1: u64 = 1130768441178740757;
const SIN1: u64 = 224923827593068887;
const COS3: u64 = 958619196450722178;
const SIN3: u64 = 640528868967736374;
const SQRT2INV: u64 = 815238614083298888;
const SQRT2INV_COS6: u64 = 311978311033955632;
const SQRT2INV_SIN6: u64 = 753182269664427492;

/// A 60-bit fixed-point constant rounded to `bits` bits.
const fn c(x: u64, bits: u32) -> i32 {
    ((x + (1 << (59 - bits))) >> (60 - bits)) as i32
}

#[inline]
fn dct_box(x0: i32, x1: i32, kcos: i32, ksin: i32) -> (i32, i32) {
    let ksum = kcos.wrapping_mul(x0.wrapping_add(x1));
    (
        ksum.wrapping_add(ksin.wrapping_sub(kcos).wrapping_mul(x1)),
        ksum.wrapping_sub(kcos.wrapping_add(ksin).wrapping_mul(x0)),
    )
}

fn idct(b: &mut Block) {
    idct_rows(b);
    idct_cols(b);
}

fn idct_rows(b: &mut Block) {
    for i in 0..8 {
        let x = &mut b[8 * i..8 * i + 8];
        let (mut x0, mut x7, mut x2, mut x5, mut x1, mut x6, mut x3, mut x4) =
            (x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7]);
        x0 = x0.wrapping_shl(17);
        x1 = x1.wrapping_shl(17);
        (x0, x1) = (x0.wrapping_add(x1), x0.wrapping_sub(x1));
        (x2, x3) = dct_box(x2, x3, c(SQRT2INV_COS6, 18), -c(SQRT2INV_SIN6, 18));
        (x1, x2) = (x1.wrapping_add(x2), x1.wrapping_sub(x2));
        (x0, x3) = (x0.wrapping_add(x3), x0.wrapping_sub(x3));
        x4 = x4.wrapping_shl(7);
        x7 = x7.wrapping_shl(7);
        (x7, x4) = (x7.wrapping_add(x4), x7.wrapping_sub(x4));
        x6 = x6.wrapping_mul(c(SQRT2INV, 8));
        x5 = x5.wrapping_mul(c(SQRT2INV, 8));
        (x7, x5) = (x7.wrapping_add(x5), x7.wrapping_sub(x5));
        (x4, x6) = (x4.wrapping_add(x6), x4.wrapping_sub(x6));
        (x4, x7) = dct_box(x4 >> 2, x7 >> 2, c(COS3, 12), -c(SIN3, 12));
        (x5, x6) = dct_box(x5 >> 2, x6 >> 2, c(COS1, 12), -c(SIN1, 12));
        (x0, x7) = (x0.wrapping_add(x7), x0.wrapping_sub(x7));
        (x1, x6) = (x1.wrapping_add(x6), x1.wrapping_sub(x6));
        (x2, x5) = (x2.wrapping_add(x5), x2.wrapping_sub(x5));
        (x3, x4) = (x3.wrapping_add(x4), x3.wrapping_sub(x4));
        x.copy_from_slice(&[x0, x1, x2, x3, x4, x5, x6, x7]);
    }
}

fn idct_cols(b: &mut Block) {
    for i in 0..8 {
        let (mut x0, mut x7, mut x2, mut x5, mut x1, mut x6, mut x3, mut x4) = (
            b[i],
            b[8 + i],
            b[16 + i],
            b[24 + i],
            b[32 + i],
            b[40 + i],
            b[48 + i],
            b[56 + i],
        );
        x0 = x0.wrapping_add(1 << 19);
        (x0, x1) = (x0.wrapping_add(x1) >> 2, x0.wrapping_sub(x1) >> 2);
        (x2, x3) = dct_box(
            x2 >> 13,
            x3 >> 13,
            c(SQRT2INV_COS6, 12),
            -c(SQRT2INV_SIN6, 12),
        );
        (x1, x2) = (x1.wrapping_add(x2), x1.wrapping_sub(x2));
        (x0, x3) = (x0.wrapping_add(x3), x0.wrapping_sub(x3));
        (x7, x4) = (x7.wrapping_add(x4), x7.wrapping_sub(x4));
        x5 = (x5 >> 13).wrapping_mul(c(SQRT2INV, 14));
        x6 = (x6 >> 13).wrapping_mul(c(SQRT2INV, 14));
        (x7, x5) = (x7.wrapping_add(x5), x7.wrapping_sub(x5));
        (x4, x6) = (x4.wrapping_add(x6), x4.wrapping_sub(x6));
        (x4, x7) = dct_box(x4 >> 14, x7 >> 14, c(COS3, 12), -c(SIN3, 12));
        (x5, x6) = dct_box(x5 >> 14, x6 >> 14, c(COS1, 12), -c(SIN1, 12));
        (x0, x7) = (x0.wrapping_add(x7), x0.wrapping_sub(x7));
        (x1, x6) = (x1.wrapping_add(x6), x1.wrapping_sub(x6));
        (x2, x5) = (x2.wrapping_add(x5), x2.wrapping_sub(x5));
        (x3, x4) = (x3.wrapping_add(x4), x3.wrapping_sub(x4));
        let out = [x0, x1, x2, x3, x4, x5, x6, x7];
        for (k, v) in out.iter().enumerate() {
            b[k * 8 + i] = v >> 18;
        }
    }
}

pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    let mut d = Decoder::new(data);
    d.decode(true)?;
    match d.n_comp {
        1 | 3 | 4 => Ok((d.width, d.height)),
        _ => Err(format_error("missing SOF marker")),
    }
}

pub fn decode(data: &[u8]) -> Result<Image, String> {
    let mut d = Decoder::new(data);
    d.decode(false)?;
    d.finish()
}
