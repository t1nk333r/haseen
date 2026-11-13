// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! VP8L (lossless WebP), a port of golang.org/x/image/vp8l (v0.46.0). The
//! format is lossless, so the pixels are any decoder's; it is ported so the
//! errors and the NRGBA image are Go's, and so the crate has no dependency.

const COLOR_CACHE_MULTIPLIER: u32 = 0x1e35a7bd;

const DISTANCE_MAP_TABLE: [u8; 120] = [
    0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a, 0x26, 0x2a, 0x38, 0x05, 0x37, 0x39,
    0x15, 0x1b, 0x36, 0x3a, 0x25, 0x2b, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b, 0x46, 0x4a,
    0x24, 0x2c, 0x58, 0x45, 0x4b, 0x34, 0x3c, 0x03, 0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d,
    0x44, 0x4c, 0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e, 0x66, 0x6a, 0x22, 0x2e,
    0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b, 0x32, 0x3e, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f,
    0x64, 0x6c, 0x42, 0x4e, 0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b, 0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e,
    0x00, 0x74, 0x7c, 0x41, 0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d, 0x51, 0x5f, 0x40, 0x72,
    0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70,
];

fn invalid_code_lengths() -> String {
    "vp8l: invalid code lengths".into()
}

fn invalid_huffman_tree() -> String {
    "vp8l: invalid Huffman tree".into()
}

fn distance_map(w: i32, code: u32) -> i32 {
    if code as i32 > DISTANCE_MAP_TABLE.len() as i32 {
        return code as i32 - DISTANCE_MAP_TABLE.len() as i32;
    }
    let dist_code = DISTANCE_MAP_TABLE[code as usize - 1] as i32;
    let y_offset = dist_code >> 4;
    let x_offset = 8 - (dist_code & 0xf);
    let d = y_offset * w + x_offset;
    if d >= 1 {
        d
    } else {
        1
    }
}

fn n_tiles(size: i32, bits: u32) -> i32 {
    (size + (1 << bits) - 1) >> bits
}

struct Decoder<'a> {
    data: &'a [u8],
    pos: usize,
    bits: u32,
    n_bits: u32,
}

impl Decoder<'_> {
    fn read_byte(&mut self) -> Option<u8> {
        let b = self.data.get(self.pos).copied();
        if b.is_some() {
            self.pos += 1;
        }
        b
    }

    fn read(&mut self, n: u32) -> Result<u32, String> {
        while self.n_bits < n {
            let c = self.read_byte().ok_or("unexpected EOF")?;
            self.bits |= (c as u32) << self.n_bits;
            self.n_bits += 8;
        }
        let u = self.bits & ((1u64 << n) - 1) as u32;
        self.bits = self.bits.checked_shr(n).unwrap_or(0);
        self.n_bits -= n;
        Ok(u)
    }
}

const LEAF: i32 = -1;
const LUT_SIZE: u32 = 7;
const LUT_MASK: u32 = (1 << LUT_SIZE) - 1;

#[derive(Clone, Copy, Default)]
struct Node {
    symbol: u32,
    children: i32,
}

#[derive(Clone)]
struct HTree {
    nodes: Vec<Node>,
    cap: usize,
    lut: [u32; 1 << LUT_SIZE],
}

impl Default for HTree {
    fn default() -> Self {
        HTree {
            nodes: Vec::new(),
            cap: 0,
            lut: [0; 1 << LUT_SIZE],
        }
    }
}

fn reverse_bits(b: u32) -> u32 {
    (b as u8).reverse_bits() as u32
}

impl HTree {
    fn insert(&mut self, symbol: u32, code: u32, mut code_length: u32) -> Result<(), String> {
        if symbol > 0xffff || code_length > 0xfe {
            return Err(invalid_huffman_tree());
        }
        let base_code;
        if code_length > LUT_SIZE {
            base_code = reverse_bits((code >> (code_length - LUT_SIZE)) & 0xff) >> (8 - LUT_SIZE);
        } else {
            base_code = reverse_bits(code & 0xff) >> (8 - code_length);
            for i in 0..(1u32 << (LUT_SIZE - code_length)) {
                self.lut[(base_code | i << code_length) as usize] = symbol << 8 | (code_length + 1);
            }
        }
        let mut n = 0usize;
        let mut jump = LUT_SIZE as i32; // an int in Go: it goes below 0
        while code_length > 0 {
            code_length -= 1;
            // Go indexes past len here and panics; this refuses instead.
            if n >= self.nodes.len() {
                return Err(invalid_huffman_tree());
            }
            match self.nodes[n].children {
                LEAF => return Err(invalid_huffman_tree()),
                0 => {
                    if self.nodes.len() == self.cap {
                        return Err(invalid_huffman_tree());
                    }
                    self.nodes[n].children = self.nodes.len() as i32;
                    self.nodes.push(Node::default());
                    self.nodes.push(Node::default());
                }
                _ => {}
            }
            n = self.nodes[n].children as usize + (1 & (code >> code_length)) as usize;
            jump -= 1;
            if jump == 0 && self.lut[base_code as usize] == 0 {
                self.lut[base_code as usize] = (n as u32) << 8;
            }
        }
        match self.nodes[n].children {
            LEAF => {}
            0 => self.nodes[n].children = LEAF,
            _ => return Err(invalid_huffman_tree()),
        }
        self.nodes[n].symbol = symbol;
        Ok(())
    }

    fn reset(&mut self, cap: usize) {
        self.nodes = Vec::with_capacity(cap);
        self.nodes.push(Node::default());
        self.cap = cap;
        self.lut = [0; 1 << LUT_SIZE];
    }

    fn build(&mut self, code_lengths: &[u32]) -> Result<(), String> {
        let mut n_symbols = 0u32;
        let mut last_symbol = 0u32;
        for (symbol, &cl) in code_lengths.iter().enumerate() {
            if cl != 0 {
                n_symbols += 1;
                last_symbol = symbol as u32;
            }
        }
        if n_symbols == 0 {
            return Err(invalid_huffman_tree());
        }
        self.reset(2 * n_symbols as usize - 1);
        if n_symbols == 1 {
            if code_lengths.len() <= last_symbol as usize {
                return Err(invalid_huffman_tree());
            }
            return self.insert(last_symbol, 0, 0);
        }
        let codes = code_lengths_to_codes(code_lengths)?;
        for (symbol, &cl) in code_lengths.iter().enumerate() {
            if cl > 0 {
                self.insert(symbol as u32, codes[symbol], cl)?;
            }
        }
        Ok(())
    }

    fn build_simple(
        &mut self,
        n_symbols: u32,
        symbols: [u32; 2],
        alphabet_size: u32,
    ) -> Result<(), String> {
        self.reset(2 * n_symbols as usize - 1);
        for i in 0..n_symbols {
            if symbols[i as usize] >= alphabet_size {
                return Err(invalid_huffman_tree());
            }
            self.insert(symbols[i as usize], i, n_symbols - 1)?;
        }
        Ok(())
    }

    fn next(&self, d: &mut Decoder) -> Result<u32, String> {
        let mut n: u32 = 0;
        let mut slow = false;
        if d.n_bits < LUT_SIZE {
            match d.read_byte() {
                Some(c) => {
                    d.bits |= (c as u32) << d.n_bits;
                    d.n_bits += 8;
                }
                None => slow = true,
            }
        }
        if !slow {
            n = self.lut[(d.bits & LUT_MASK) as usize];
            let b = n & 0xff;
            if b != 0 {
                let b = b - 1;
                d.bits >>= b;
                d.n_bits -= b;
                return Ok(n >> 8);
            }
            n >>= 8;
            d.bits >>= LUT_SIZE;
            d.n_bits -= LUT_SIZE;
        }
        let mut n = n as usize;
        while self.nodes.get(n).ok_or_else(invalid_huffman_tree)?.children != LEAF {
            if d.n_bits == 0 {
                let c = d.read_byte().ok_or("unexpected EOF")?;
                d.bits = c as u32;
                d.n_bits = 8;
            }
            n = self.nodes[n].children as usize + (1 & d.bits) as usize;
            d.bits >>= 1;
            d.n_bits -= 1;
        }
        Ok(self.nodes[n].symbol)
    }
}

fn code_lengths_to_codes(code_lengths: &[u32]) -> Result<Vec<u32>, String> {
    let max = code_lengths.iter().copied().max().unwrap_or(0);
    if code_lengths.is_empty() || max > 15 {
        return Err(invalid_huffman_tree());
    }
    let mut histogram = [0u32; 16];
    for &cl in code_lengths {
        histogram[cl as usize] += 1;
    }
    let mut curr = 0u32;
    let mut next_codes = [0u32; 16];
    for cl in 1..16 {
        curr = (curr.wrapping_add(histogram[cl - 1])) << 1;
        next_codes[cl] = curr;
    }
    let mut codes = vec![0u32; code_lengths.len()];
    for (symbol, &cl) in code_lengths.iter().enumerate() {
        if cl > 0 {
            codes[symbol] = next_codes[cl as usize];
            next_codes[cl as usize] += 1;
        }
    }
    Ok(codes)
}

const CODE_LENGTH_CODE_ORDER: [usize; 19] = [
    17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
];
const REPEAT_BITS: [u32; 3] = [2, 3, 7];
const REPEAT_OFFSETS: [u32; 3] = [3, 3, 11];
const ALPHABET_SIZES: [u32; 5] = [256 + 24, 256, 256, 256, 40];

#[derive(Default)]
struct Transform {
    kind: u32,
    old_width: i32,
    bits: u32,
    pix: Vec<u8>,
}

impl Decoder<'_> {
    fn decode_transform(&mut self, w: i32, h: i32) -> Result<(Transform, i32), String> {
        let mut t = Transform {
            old_width: w,
            kind: self.read(2)?,
            ..Default::default()
        };
        let mut w = w;
        match t.kind {
            0 | 1 => {
                t.bits = self.read(3)? + 2;
                t.pix = self.decode_pix(n_tiles(w, t.bits), n_tiles(h, t.bits), 0, false)?;
            }
            2 => {}
            _ => {
                let n_colors = self.read(8)? + 1;
                t.bits = if n_colors <= 2 {
                    3
                } else if n_colors <= 4 {
                    2
                } else if n_colors <= 16 {
                    1
                } else {
                    0
                };
                w = n_tiles(w, t.bits);
                let mut pix = self.decode_pix(n_colors as i32, 1, 4 * 256, false)?;
                for p in (4..pix.len()).step_by(4) {
                    for k in 0..4 {
                        pix[p + k] = pix[p + k].wrapping_add(pix[p + k - 4]);
                    }
                }
                // pix[:4*256]: the capacity Go reserved is zeros.
                pix.resize(4 * 256, 0);
                t.pix = pix;
            }
        }
        Ok((t, w))
    }

    fn decode_code_lengths(&mut self, dst: &mut [u32], cl_lengths: &[u32]) -> Result<(), String> {
        let mut h = HTree::default();
        h.build(cl_lengths)?;
        let mut max_symbol = dst.len();
        if self.read(1)? != 0 {
            let n = 2 + 2 * self.read(3)?;
            let ms = self.read(n)?;
            max_symbol = ms as usize + 2;
            if max_symbol > dst.len() {
                return Err(invalid_code_lengths());
            }
        }
        let mut prev = 8u32;
        let mut symbol = 0;
        while symbol < dst.len() {
            if max_symbol == 0 {
                break;
            }
            max_symbol -= 1;
            let code_length = h.next(self)?;
            if code_length < 16 {
                dst[symbol] = code_length;
                symbol += 1;
                if code_length != 0 {
                    prev = code_length;
                }
                continue;
            }
            let k = (code_length - 16) as usize;
            let repeat = self.read(REPEAT_BITS[k])? + REPEAT_OFFSETS[k];
            if symbol + repeat as usize > dst.len() {
                return Err(invalid_code_lengths());
            }
            let cl = if code_length == 16 { prev } else { 0 };
            for _ in 0..repeat {
                dst[symbol] = cl;
                symbol += 1;
            }
        }
        Ok(())
    }

    fn decode_huffman_tree(
        &mut self,
        h: Option<&mut HTree>,
        alphabet_size: u32,
    ) -> Result<(), String> {
        if self.read(1)? != 0 {
            let n_symbols = self.read(1)? + 1;
            let first_len = 7 * self.read(1)? + 1;
            let mut symbols = [0u32; 2];
            symbols[0] = self.read(first_len)?;
            if n_symbols == 2 {
                symbols[1] = self.read(8)?;
            }
            return match h {
                None => Ok(()),
                Some(h) => h.build_simple(n_symbols, symbols, alphabet_size),
            };
        }
        let n_codes = self.read(4)? + 4;
        if n_codes as usize > CODE_LENGTH_CODE_ORDER.len() {
            return Err(invalid_huffman_tree());
        }
        let mut cl_lengths = [0u32; 19];
        for &o in CODE_LENGTH_CODE_ORDER.iter().take(n_codes as usize) {
            cl_lengths[o] = self.read(3)?;
        }
        let mut code_lengths = vec![0u32; alphabet_size as usize];
        self.decode_code_lengths(&mut code_lengths, &cl_lengths)?;
        match h {
            None => Ok(()),
            Some(h) => h.build(&code_lengths),
        }
    }

    #[allow(clippy::type_complexity)]
    fn decode_huffman_groups(
        &mut self,
        w: i32,
        h: i32,
        top_level: bool,
        cc_bits: u32,
    ) -> Result<(Vec<[HTree; 5]>, Vec<u8>, u32), String> {
        let mut mapping: Option<Vec<i16>> = None;
        let mut max_index = 0usize;
        let mut num_groups = 1usize;
        let mut h_pix = Vec::new();
        let mut h_bits = 0;
        if top_level && self.read(1)? != 0 {
            h_bits = self.read(3)? + 2;
            let tile_w = n_tiles(w, h_bits);
            let tile_h = n_tiles(h, h_bits);
            let num_tiles = tile_h * tile_w;
            h_pix = self.decode_pix(tile_w, tile_h, 0, false)?;
            for p in (0..h_pix.len()).step_by(4) {
                let i = (h_pix[p] as usize) << 8 | h_pix[p + 1] as usize;
                max_index = max_index.max(i);
            }
            if max_index >= 2600 {
                return Err("vp8l: too many Huffman trees".into());
            }
            if max_index >= 1000 || max_index as i32 >= num_tiles {
                let mut m = vec![-1i16; max_index + 1];
                num_groups = 0;
                for p in (0..h_pix.len()).step_by(4) {
                    let i = (h_pix[p] as usize) << 8 | h_pix[p + 1] as usize;
                    if m[i] == -1 {
                        m[i] = num_groups as i16;
                        num_groups += 1;
                    }
                    h_pix[p] = (m[i] >> 8) as u8;
                    h_pix[p + 1] = m[i] as u8;
                }
                mapping = Some(m);
            } else {
                num_groups = max_index + 1;
            }
        }
        let mut groups: Vec<[HTree; 5]> = (0..num_groups).map(|_| Default::default()).collect();
        for i in 0..=max_index {
            let gi = match &mapping {
                None => Some(i),
                Some(m) => (m[i] != -1).then(|| m[i] as usize),
            };
            for (j, &size) in ALPHABET_SIZES.iter().enumerate() {
                let mut size = size;
                if j == 0 && cc_bits > 0 {
                    size += 1 << cc_bits;
                }
                let dst = gi.map(|g| &mut groups[g][j]);
                self.decode_huffman_tree(dst, size)?;
            }
        }
        Ok((groups, h_pix, h_bits))
    }

    fn decode_pix(
        &mut self,
        w: i32,
        h: i32,
        _min_cap: i32,
        top_level: bool,
    ) -> Result<Vec<u8>, String> {
        let (mut cc_bits, mut cc_shift, mut cc_entries) = (0u32, 0u32, Vec::<u32>::new());
        if self.read(1)? != 0 {
            cc_bits = self.read(4)?;
            if !(1..=11).contains(&cc_bits) {
                return Err("vp8l: invalid color cache parameters".into());
            }
            cc_shift = 32 - cc_bits;
            cc_entries = vec![0; 1 << cc_bits];
        }
        let (groups, h_pix, h_bits) = self.decode_huffman_groups(w, h, top_level, cc_bits)?;
        let (mut h_mask, mut tiles_per_row) = (0i32, 0i32);
        if h_bits != 0 {
            h_mask = (1 << h_bits) - 1;
            tiles_per_row = n_tiles(w, h_bits);
        }
        let len = 4 * w as usize * h as usize;
        let mut pix = vec![0u8; len];
        let (mut p, mut cached_p) = (0usize, 0usize);
        let (mut x, mut y) = (0i32, 0i32);
        let mut hg = 0usize;
        let mut lookup = h_mask != 0;
        while p < len {
            if lookup {
                let i = 4 * (tiles_per_row * (y >> h_bits) + (x >> h_bits)) as usize;
                hg = (h_pix[i] as usize) << 8 | h_pix[i + 1] as usize;
            }
            let g = groups.get(hg).ok_or("vp8l: invalid Huffman group")?;
            let green = g[0].next(self)?;
            if green < 256 {
                let red = g[1].next(self)?;
                let blue = g[2].next(self)?;
                let alpha = g[3].next(self)?;
                pix[p] = red as u8;
                pix[p + 1] = green as u8;
                pix[p + 2] = blue as u8;
                pix[p + 3] = alpha as u8;
                p += 4;
                x += 1;
                if x == w {
                    x = 0;
                    y += 1;
                }
                lookup = h_mask != 0 && x & h_mask == 0;
            } else if green < 256 + 24 {
                let length = self.lz77_param(green - 256)?;
                let dist_sym = g[4].next(self)?;
                let dist_code = self.lz77_param(dist_sym)?;
                let dist = distance_map(w, dist_code);
                let p_end = p as i64 + 4 * length as i64;
                let q = p as i64 - 4 * dist as i64;
                let q_end = p_end - 4 * dist as i64;
                if q < 0 || (len as i64) < p_end || (len as i64) < q_end {
                    return Err("vp8l: invalid LZ77 parameters".into());
                }
                let mut q = q as usize;
                while (p as i64) < p_end {
                    pix[p] = pix[q];
                    p += 1;
                    q += 1;
                }
                x += length as i32;
                while x >= w {
                    x -= w;
                    y += 1;
                }
                lookup = h_mask != 0;
            } else {
                while cached_p < p {
                    let argb = (pix[cached_p] as u32) << 16
                        | (pix[cached_p + 1] as u32) << 8
                        | pix[cached_p + 2] as u32
                        | (pix[cached_p + 3] as u32) << 24;
                    cc_entries[(argb.wrapping_mul(COLOR_CACHE_MULTIPLIER) >> cc_shift) as usize] =
                        argb;
                    cached_p += 4;
                }
                let idx = (green - (256 + 24)) as usize;
                if idx >= cc_entries.len() {
                    return Err("vp8l: invalid color cache index".into());
                }
                let argb = cc_entries[idx];
                pix[p] = (argb >> 16) as u8;
                pix[p + 1] = (argb >> 8) as u8;
                pix[p + 2] = argb as u8;
                pix[p + 3] = (argb >> 24) as u8;
                p += 4;
                x += 1;
                if x == w {
                    x = 0;
                    y += 1;
                }
                lookup = h_mask != 0 && x & h_mask == 0;
            }
        }
        Ok(pix)
    }

    fn lz77_param(&mut self, symbol: u32) -> Result<u32, String> {
        if symbol < 4 {
            return Ok(symbol + 1);
        }
        let extra = (symbol - 2) >> 1;
        let offset = (2 + (symbol & 1)) << extra;
        let n = self.read(extra)?;
        Ok(offset + n + 1)
    }
}

fn decode_header(data: &[u8]) -> Result<(Decoder<'_>, i32, i32), String> {
    let mut d = Decoder {
        data,
        pos: 0,
        bits: 0,
        n_bits: 0,
    };
    if d.read(8)? != 0x2f {
        return Err("vp8l: invalid header".into());
    }
    let w = d.read(14)? + 1;
    let h = d.read(14)? + 1;
    d.read(1)?; // the hasAlpha hint, ignored
    if d.read(3)? != 0 {
        return Err("vp8l: invalid version".into());
    }
    Ok((d, w as i32, h as i32))
}

pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    let (_, w, h) = decode_header(data)?;
    Ok((w as usize, h as usize))
}

/// The NRGBA pixels and the width and height.
pub fn decode(data: &[u8]) -> Result<(Vec<u8>, usize, usize), String> {
    let (mut d, mut w, h) = decode_header(data)?;
    let original_w = w;
    let mut transforms: Vec<Transform> = Vec::new();
    let mut seen = [false; 4];
    loop {
        if d.read(1)? == 0 {
            break;
        }
        let (t, nw) = d.decode_transform(w, h)?;
        w = nw;
        if seen[t.kind as usize] {
            return Err("vp8l: repeated transform".into());
        }
        seen[t.kind as usize] = true;
        transforms.push(t);
    }
    let mut pix = d.decode_pix(w, h, 0, true)?;
    for t in transforms.iter().rev() {
        pix = match t.kind {
            0 => inverse_predictor(t, pix, h),
            1 => inverse_cross_color(t, pix, h),
            2 => inverse_subtract_green(pix),
            _ => inverse_color_indexing(t, pix, h),
        };
    }
    Ok((pix, original_w as usize, h as usize))
}

fn avg2(a: u8, b: u8) -> u8 {
    ((a as i32 + b as i32) / 2) as u8
}

fn clamp_add_subtract_full(a: u8, b: u8, c: u8) -> u8 {
    (a as i32 + b as i32 - c as i32).clamp(0, 255) as u8
}

fn clamp_add_subtract_half(a: u8, b: u8) -> u8 {
    (a as i32 + (a as i32 - b as i32) / 2).clamp(0, 255) as u8
}

fn inverse_predictor(t: &Transform, mut pix: Vec<u8>, h: i32) -> Vec<u8> {
    if t.old_width == 0 || h == 0 {
        return pix;
    }
    let add = |pix: &mut Vec<u8>, p: usize, v: [u8; 4]| {
        for k in 0..4 {
            pix[p + k] = pix[p + k].wrapping_add(v[k]);
        }
    };
    let px = |pix: &Vec<u8>, i: usize| [pix[i], pix[i + 1], pix[i + 2], pix[i + 3]];
    pix[3] = pix[3].wrapping_add(0xff);
    let mut p = 4usize;
    let mask = (1i32 << t.bits) - 1;
    for _ in 1..t.old_width {
        let l = px(&pix, p - 4);
        add(&mut pix, p, l);
        p += 4;
    }
    let mut top = 0usize;
    let tiles_per_row = n_tiles(t.old_width, t.bits);
    for y in 1..h {
        let tv = px(&pix, top);
        add(&mut pix, p, tv);
        p += 4;
        top += 4;
        let mut q = 4 * ((y >> t.bits) * tiles_per_row) as usize;
        let mut mode = t.pix[q + 1] & 0x0f;
        q += 4;
        for x in 1..t.old_width {
            if x & mask == 0 {
                mode = t.pix[q + 1] & 0x0f;
                q += 4;
            }
            let l = px(&pix, p - 4);
            let tt = px(&pix, top);
            let tr = px(&pix, top + 4);
            let tl = px(&pix, top - 4);
            let v: [u8; 4] = match mode {
                0 => [0, 0, 0, 0xff],
                1 => l,
                2 => tt,
                3 => tr,
                4 => tl,
                5 => std::array::from_fn(|k| avg2(avg2(l[k], tr[k]), tt[k])),
                6 => std::array::from_fn(|k| avg2(l[k], tl[k])),
                7 => std::array::from_fn(|k| avg2(l[k], tt[k])),
                8 => std::array::from_fn(|k| avg2(tl[k], tt[k])),
                9 => std::array::from_fn(|k| avg2(tt[k], tr[k])),
                10 => std::array::from_fn(|k| avg2(avg2(l[k], tl[k]), avg2(tt[k], tr[k]))),
                11 => {
                    let d = |a: [u8; 4], b: [u8; 4]| -> i32 {
                        (0..4).map(|k| (a[k] as i32 - b[k] as i32).abs()).sum()
                    };
                    let lsum = d(tl, tt);
                    let tsum = d(tl, l);
                    if lsum < tsum {
                        l
                    } else {
                        tt
                    }
                }
                12 => std::array::from_fn(|k| clamp_add_subtract_full(l[k], tt[k], tl[k])),
                13 => std::array::from_fn(|k| clamp_add_subtract_half(avg2(l[k], tt[k]), tl[k])),
                _ => [0; 4],
            };
            add(&mut pix, p, v);
            p += 4;
            top += 4;
        }
    }
    pix
}

fn inverse_cross_color(t: &Transform, mut pix: Vec<u8>, h: i32) -> Vec<u8> {
    let (mut g2r, mut g2b, mut r2b) = (0i32, 0i32, 0i32);
    let mut p = 0usize;
    let mask = (1i32 << t.bits) - 1;
    let tiles_per_row = n_tiles(t.old_width, t.bits);
    for y in 0..h {
        let mut q = 4 * ((y >> t.bits) * tiles_per_row) as usize;
        for x in 0..t.old_width {
            if x & mask == 0 {
                r2b = t.pix[q] as i8 as i32;
                g2b = t.pix[q + 1] as i8 as i32;
                g2r = t.pix[q + 2] as i8 as i32;
                q += 4;
            }
            let mut red = pix[p];
            let green = pix[p + 1];
            let mut blue = pix[p + 2];
            red = red.wrapping_add(((g2r.wrapping_mul(green as i8 as i32)) as u32 >> 5) as u8);
            blue = blue.wrapping_add(((g2b.wrapping_mul(green as i8 as i32)) as u32 >> 5) as u8);
            blue = blue.wrapping_add(((r2b.wrapping_mul(red as i8 as i32)) as u32 >> 5) as u8);
            pix[p] = red;
            pix[p + 2] = blue;
            p += 4;
        }
    }
    pix
}

fn inverse_subtract_green(mut pix: Vec<u8>) -> Vec<u8> {
    for p in (0..pix.len()).step_by(4) {
        let green = pix[p + 1];
        pix[p] = pix[p].wrapping_add(green);
        pix[p + 2] = pix[p + 2].wrapping_add(green);
    }
    pix
}

fn inverse_color_indexing(t: &Transform, mut pix: Vec<u8>, h: i32) -> Vec<u8> {
    if t.bits == 0 {
        for p in (0..pix.len()).step_by(4) {
            let i = 4 * pix[p + 1] as usize;
            pix[p..p + 4].copy_from_slice(&t.pix[i..i + 4]);
        }
        return pix;
    }
    let bits_per_pixel = 8 >> t.bits;
    let (v_mask, x_mask): (u32, i32) = match t.bits {
        1 => (0x0f, 0x01),
        2 => (0x03, 0x03),
        _ => (0x01, 0x07),
    };
    let mut dst = vec![0u8; 4 * t.old_width as usize * h as usize];
    let (mut d, mut p, mut v) = (0usize, 0usize, 0u32);
    for _ in 0..h {
        for x in 0..t.old_width {
            if x & x_mask == 0 {
                v = pix[p + 1] as u32;
                p += 4;
            }
            let i = 4 * (v & v_mask) as usize;
            dst[d..d + 4].copy_from_slice(&t.pix[i..i + 4]);
            d += 4;
            v >>= bits_per_pixel;
        }
    }
    dst
}
