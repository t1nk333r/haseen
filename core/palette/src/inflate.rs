// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! zlib (RFC 1950) and DEFLATE (RFC 1951) decompression for PNG, pulled a
//! byte at a time from a source so the PNG reader can feed it IDAT chunks as
//! Go's does. Lossless: any correct inflater gives the same bytes. The
//! errors read as Go's compress/zlib and compress/flate word them.

pub type Source<'a> = dyn FnMut() -> Result<Option<u8>, String> + 'a;

const MAX_BITS: usize = 15;
const FAST_BITS: u32 = 10;

struct Huffman {
    counts: [u16; MAX_BITS + 1],
    symbols: Vec<u16>,
    /// For codes of at most FAST_BITS bits: the bit-reversed code's low bits
    /// index (symbol, length); length 0 means look further.
    fast: Vec<(u16, u8)>,
}

impl Huffman {
    /// Canonical code from lengths. Incomplete sets are refused, except a
    /// single code of length 1, as Go's huffmanDecoder.init does.
    fn new(lengths: &[u8]) -> Option<Huffman> {
        let mut counts = [0u16; MAX_BITS + 1];
        for &l in lengths {
            counts[l as usize] += 1;
        }
        counts[0] = 0;
        let mut left: i32 = 1;
        let mut max = 0;
        for (len, &c) in counts.iter().enumerate().skip(1) {
            left <<= 1;
            left -= c as i32;
            if left < 0 {
                return None;
            }
            if c > 0 {
                max = len;
            }
        }
        let total: u16 = counts.iter().sum();
        if left > 0 && !(total == 1 && max == 1) && total != 0 {
            return None;
        }
        let mut offs = [0u16; MAX_BITS + 2];
        for len in 1..=MAX_BITS {
            offs[len + 1] = offs[len] + counts[len];
        }
        let mut symbols = vec![0u16; total as usize];
        for (sym, &l) in lengths.iter().enumerate() {
            if l != 0 {
                symbols[offs[l as usize] as usize] = sym as u16;
                offs[l as usize] += 1;
            }
        }
        let mut h = Huffman {
            counts,
            symbols,
            fast: vec![(0, 0); 1 << FAST_BITS],
        };
        // Fill the fast table: walk codes in canonical order.
        let mut code: u32 = 0;
        let mut index = 0usize;
        for len in 1..=MAX_BITS {
            for _ in 0..h.counts[len] {
                if len as u32 <= FAST_BITS {
                    let rev = (code.reverse_bits() >> (32 - len)) as usize;
                    let step = 1 << len;
                    let mut i = rev;
                    while i < (1 << FAST_BITS) {
                        h.fast[i] = (h.symbols[index], len as u8);
                        i += step;
                    }
                }
                code += 1;
                index += 1;
            }
            code <<= 1;
        }
        Some(h)
    }
}

pub struct Inflater<'a, 'b> {
    src: &'b mut Source<'a>,
    bits: u64,
    nbits: u32,
    read: u64,
    window: Vec<u8>,
    adler: (u32, u32),
    state: State,
    lit: Option<Huffman>,
    dist: Option<Huffman>,
    stored_left: usize,
    copy: (usize, usize), // pending (length, distance)
    last: bool,
}

#[derive(PartialEq)]
enum State {
    Header,
    Block,
    Stored,
    Codes,
    Done,
}

const WINDOW: usize = 1 << 15;

const LEN_BASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
];
const LEN_EXTRA: [u8; 29] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DIST_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const DIST_EXTRA: [u8; 30] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
];

impl<'a, 'b> Inflater<'a, 'b> {
    pub fn new(src: &'b mut Source<'a>) -> Self {
        Inflater {
            src,
            bits: 0,
            nbits: 0,
            read: 0,
            window: Vec::with_capacity(WINDOW * 2),
            adler: (1, 0),
            state: State::Header,
            lit: None,
            dist: None,
            stored_left: 0,
            copy: (0, 0),
            last: false,
        }
    }

    /// Go counts the bytes its bit reader took; this one reads ahead to
    /// fill its lookup table, so whole bytes still unread are not counted.
    fn corrupt(&self) -> String {
        format!(
            "flate: corrupt input before offset {}",
            self.read - (self.nbits / 8) as u64
        )
    }

    fn byte(&mut self) -> Result<u8, String> {
        match (self.src)()? {
            Some(b) => {
                self.read += 1;
                Ok(b)
            }
            None => Err("unexpected EOF".into()),
        }
    }

    fn need(&mut self, n: u32) -> Result<(), String> {
        while self.nbits < n {
            let b = self.byte()?;
            self.bits |= (b as u64) << self.nbits;
            self.nbits += 8;
        }
        Ok(())
    }

    fn take(&mut self, n: u32) -> Result<u32, String> {
        if n == 0 {
            return Ok(0);
        }
        self.need(n)?;
        let v = (self.bits & ((1u64 << n) - 1)) as u32;
        self.bits >>= n;
        self.nbits -= n;
        Ok(v)
    }

    fn decode(&mut self, which: bool) -> Result<u16, String> {
        // Peek what is there for the fast table; at the end of input fall
        // back to bit-by-bit.
        while self.nbits < FAST_BITS {
            match (self.src)()? {
                Some(b) => {
                    self.read += 1;
                    self.bits |= (b as u64) << self.nbits;
                    self.nbits += 8;
                }
                None => break,
            }
        }
        let h = if which {
            self.lit.as_ref()
        } else {
            self.dist.as_ref()
        };
        let h = h.expect("table built");
        let (sym, len) = h.fast[(self.bits & ((1 << FAST_BITS) - 1)) as usize];
        if len != 0 && len as u32 <= self.nbits {
            self.bits >>= len;
            self.nbits -= len as u32;
            return Ok(sym);
        }
        // Slow path, puff's canonical walk.
        let mut code: i32 = 0;
        let mut first: i32 = 0;
        let mut index: i32 = 0;
        for len in 1..=MAX_BITS {
            let h = if which {
                self.lit.as_ref()
            } else {
                self.dist.as_ref()
            }
            .expect("table built");
            let count = h.counts[len] as i32;
            let bit = self.take(1)? as i32;
            code |= bit;
            if code - count < first {
                let h = if which {
                    self.lit.as_ref()
                } else {
                    self.dist.as_ref()
                }
                .expect("table built");
                return Ok(h.symbols[(index + (code - first)) as usize]);
            }
            index += count;
            first += count;
            first <<= 1;
            code <<= 1;
        }
        Err(self.corrupt())
    }

    fn emit(&mut self, b: u8, out: &mut Vec<u8>) {
        self.window.push(b);
        out.push(b);
    }

    fn trim_window(&mut self) {
        if self.window.len() >= WINDOW * 2 {
            self.window.drain(..self.window.len() - WINDOW);
        }
    }

    fn dynamic_tables(&mut self) -> Result<(), String> {
        let nlit = self.take(5)? as usize + 257;
        let ndist = self.take(5)? as usize + 1;
        let nclen = self.take(4)? as usize + 4;
        if nlit > 286 || ndist > 30 {
            return Err(self.corrupt());
        }
        const ORDER: [usize; 19] = [
            16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
        ];
        let mut clen = [0u8; 19];
        for &o in ORDER.iter().take(nclen) {
            clen[o] = self.take(3)? as u8;
        }
        self.lit = Some(Huffman::new(&clen).ok_or_else(|| self.corrupt())?);
        let mut lengths = vec![0u8; nlit + ndist];
        let mut i = 0;
        while i < nlit + ndist {
            let sym = self.decode(true)?;
            match sym {
                0..=15 => {
                    lengths[i] = sym as u8;
                    i += 1;
                }
                16 => {
                    if i == 0 {
                        return Err(self.corrupt());
                    }
                    let prev = lengths[i - 1];
                    let n = 3 + self.take(2)? as usize;
                    if i + n > nlit + ndist {
                        return Err(self.corrupt());
                    }
                    for _ in 0..n {
                        lengths[i] = prev;
                        i += 1;
                    }
                }
                _ => {
                    let n = if sym == 17 {
                        3 + self.take(3)? as usize
                    } else {
                        11 + self.take(7)? as usize
                    };
                    if i + n > nlit + ndist {
                        return Err(self.corrupt());
                    }
                    i += n;
                }
            }
        }
        if lengths[256] == 0 {
            return Err(self.corrupt());
        }
        self.lit = Some(Huffman::new(&lengths[..nlit]).ok_or_else(|| self.corrupt())?);
        self.dist = Some(Huffman::new(&lengths[nlit..]).ok_or_else(|| self.corrupt())?);
        Ok(())
    }

    fn fixed_tables(&mut self) {
        let mut l = [0u8; 288];
        l[..144].fill(8);
        l[144..256].fill(9);
        l[256..280].fill(7);
        l[280..].fill(8);
        self.lit = Huffman::new(&l);
        // 32 codes: 30 and 31 decode, then are refused as distances.
        self.dist = Huffman::new(&[5u8; 32]);
    }

    /// Appends up to `want` more decompressed bytes to out; fewer only at
    /// the end of the stream (after its checksum was verified).
    pub fn read(&mut self, out: &mut Vec<u8>, want: usize) -> Result<(), String> {
        let goal = out.len() + want;
        if self.state == State::Header {
            let cmf = self.byte()?;
            let flg = self.byte()?;
            if cmf & 0x0f != 8
                || cmf >> 4 > 7
                || !((cmf as u16) << 8 | flg as u16).is_multiple_of(31)
            {
                return Err("zlib: invalid header".into());
            }
            if flg & 0x20 != 0 {
                return Err("zlib: invalid dictionary".into());
            }
            self.state = State::Block;
            self.read = 0; // flate counts its own offset
        }
        let start = out.len();
        while out.len() < goal {
            // A pending copy first.
            while self.copy.0 > 0 && out.len() < goal {
                let b = self.window[self.window.len() - self.copy.1];
                self.emit(b, out);
                self.copy.0 -= 1;
            }
            if out.len() >= goal {
                break;
            }
            match self.state {
                State::Header => unreachable!(),
                State::Done => break,
                State::Block => {
                    if self.last {
                        // The stream is over: the Adler-32 that follows.
                        self.bits >>= self.nbits % 8;
                        self.nbits -= self.nbits % 8;
                        let mut sum = [0u8; 4];
                        for s in sum.iter_mut() {
                            *s = if self.nbits >= 8 {
                                let v = self.bits as u8;
                                self.bits >>= 8;
                                self.nbits -= 8;
                                v
                            } else {
                                self.byte()?
                            };
                        }
                        self.adler_update(&out[start..]);
                        let (a, b) = self.adler;
                        if u32::from_be_bytes(sum) != (b << 16 | a) {
                            return Err("zlib: invalid checksum".into());
                        }
                        self.state = State::Done;
                        return Ok(());
                    }
                    self.last = self.take(1)? == 1;
                    match self.take(2)? {
                        0 => {
                            self.bits >>= self.nbits % 8;
                            self.nbits -= self.nbits % 8;
                            let len = self.take(16)?;
                            let nlen = self.take(16)?;
                            if len != !nlen & 0xffff {
                                return Err(self.corrupt());
                            }
                            self.stored_left = len as usize;
                            self.state = State::Stored;
                        }
                        1 => {
                            self.fixed_tables();
                            self.state = State::Codes;
                        }
                        2 => {
                            self.dynamic_tables()?;
                            self.state = State::Codes;
                        }
                        _ => return Err(self.corrupt()),
                    }
                }
                State::Stored => {
                    while self.stored_left > 0 && out.len() < goal {
                        let b = if self.nbits >= 8 {
                            let v = self.bits as u8;
                            self.bits >>= 8;
                            self.nbits -= 8;
                            v
                        } else {
                            self.byte()?
                        };
                        self.emit(b, out);
                        self.stored_left -= 1;
                    }
                    if self.stored_left == 0 {
                        self.state = State::Block;
                    }
                }
                State::Codes => {
                    while out.len() < goal && self.copy.0 == 0 {
                        let sym = self.decode(true)? as usize;
                        if sym < 256 {
                            self.emit(sym as u8, out);
                        } else if sym == 256 {
                            self.state = State::Block;
                            break;
                        } else {
                            let s = sym - 257;
                            if s >= 29 {
                                return Err(self.corrupt());
                            }
                            let len =
                                LEN_BASE[s] as usize + self.take(LEN_EXTRA[s] as u32)? as usize;
                            let d = self.decode(false)? as usize;
                            if d >= 30 {
                                return Err(self.corrupt());
                            }
                            let dist =
                                DIST_BASE[d] as usize + self.take(DIST_EXTRA[d] as u32)? as usize;
                            if dist > self.window.len() {
                                return Err(self.corrupt());
                            }
                            self.copy = (len, dist);
                            while self.copy.0 > 0 && out.len() < goal {
                                let b = self.window[self.window.len() - dist];
                                self.emit(b, out);
                                self.copy.0 -= 1;
                            }
                        }
                    }
                }
            }
            self.trim_window();
        }
        self.adler_update(&out[start..]);
        Ok(())
    }

    fn adler_update(&mut self, data: &[u8]) {
        let (mut a, mut b) = self.adler;
        for chunk in data.chunks(5552) {
            for &x in chunk {
                a += x as u32;
                b += a;
            }
            a %= 65521;
            b %= 65521;
        }
        self.adler = (a, b);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inflate(data: &[u8]) -> Result<Vec<u8>, String> {
        let mut i = 0;
        let mut src = || -> Result<Option<u8>, String> {
            let b = data.get(i).copied();
            i += 1;
            Ok(b)
        };
        let mut inf = Inflater::new(&mut src);
        let mut out = Vec::new();
        loop {
            let before = out.len();
            inf.read(&mut out, 1000)?;
            if out.len() == before {
                return Ok(out);
            }
        }
    }

    #[test]
    fn stored_fixed_and_dynamic_blocks() {
        // Python's zlib.compress(b"hello", 0) and (b"hello hello hello", 1).
        // Dynamic blocks are every PNG in the corpus (tests/golden.rs).
        let stored = [
            0x78, 0x01, 0x01, 0x05, 0x00, 0xfa, 0xff, b'h', b'e', b'l', b'l', b'o', 0x06, 0x2c,
            0x02, 0x15,
        ];
        assert_eq!(inflate(&stored).unwrap(), b"hello");
        let fixed = [
            0x78, 0x01, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0xc8, 0x40, 0x90, 0x00, 0x3a, 0x2e,
            0x06, 0x7d,
        ];
        assert_eq!(inflate(&fixed).unwrap(), b"hello hello hello");
        let mut bad = fixed;
        bad[15] ^= 1;
        assert_eq!(inflate(&bad).unwrap_err(), "zlib: invalid checksum");
        assert_eq!(inflate(&[0x78, 0x9d]).unwrap_err(), "zlib: invalid header");
    }
}
