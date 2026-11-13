//! PNG, a port of Go's image/png reader (Go 1.27): the same image type per
//! colour type and bit depth, tRNS handling, palette growth, Adam7, CRC and
//! chunk-order checks, and its error text. The zlib stream is pulled
//! through a 4096-byte buffer from the IDAT chunks as Go's bufio.Reader
//! pulls it, so the chunk accounting after the stream ends is Go's.

use crate::image::{nrgba_color, rgba_color, Image};
use crate::inflate::Inflater;

enum Err {
    /// io.EOF: nothing left where a read began.
    Eof,
    Msg(String),
}

fn format_error(s: &str) -> Err {
    Err::Msg(format!("png: invalid format: {s}"))
}

fn unsupported(s: &str) -> Err {
    Err::Msg(format!("png: unsupported feature: {s}"))
}

impl Err {
    fn text(self) -> String {
        match self {
            Err::Eof => "unexpected EOF".into(),
            Err::Msg(m) => m,
        }
    }
}

const HEADER: &[u8] = b"\x89PNG\r\n\x1a\n";

fn crc_table() -> &'static [u32; 256] {
    static TABLE: std::sync::OnceLock<[u32; 256]> = std::sync::OnceLock::new();
    TABLE.get_or_init(|| {
        let mut t = [0u32; 256];
        for (n, slot) in t.iter_mut().enumerate() {
            let mut c = n as u32;
            for _ in 0..8 {
                c = if c & 1 != 0 {
                    0xedb88320 ^ (c >> 1)
                } else {
                    c >> 1
                };
            }
            *slot = c;
        }
        t
    })
}

#[derive(Clone, Copy, Default)]
struct Crc(u32);

impl Crc {
    fn reset(&mut self) {
        self.0 = 0;
    }
    fn write(&mut self, data: &[u8]) {
        let t = crc_table();
        let mut c = !self.0;
        for &b in data {
            c = t[((c ^ b as u32) & 0xff) as usize] ^ (c >> 8);
        }
        self.0 = !c;
    }
}

struct Input<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Input<'a> {
    /// io.ReadFull: io.EOF when nothing is left, ErrUnexpectedEOF when
    /// only part is.
    fn read_full(&mut self, n: usize) -> Result<&'a [u8], Err> {
        let left = self.data.len() - self.pos;
        if left == 0 && n > 0 {
            return Err(Err::Eof);
        }
        if left < n {
            self.pos = self.data.len();
            return Err(Err::Msg("unexpected EOF".into()));
        }
        let s = &self.data[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Stage {
    Start,
    SeenIhdr,
    SeenPlte,
    SeenTrns,
    SeenIdat,
    SeenIend,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Cb {
    G1,
    G2,
    G4,
    G8,
    Ga8,
    Tc8,
    P1,
    P2,
    P4,
    P8,
    Tca8,
    G16,
    Ga16,
    Tc16,
    Tca16,
}

impl Cb {
    fn paletted(self) -> bool {
        matches!(self, Cb::P1 | Cb::P2 | Cb::P4 | Cb::P8)
    }
    fn true_color(self) -> bool {
        matches!(self, Cb::Tc8 | Cb::Tc16)
    }
}

/// The Go image type a pass decodes into, by its Pix layout.
#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Gray,
    Nrgba,
    Rgba,
    Paletted,
    Gray16,
    Nrgba64,
    Rgba64,
}

impl Kind {
    fn bpp(self) -> usize {
        match self {
            Kind::Gray | Kind::Paletted => 1,
            Kind::Gray16 => 2,
            Kind::Nrgba | Kind::Rgba => 4,
            Kind::Nrgba64 | Kind::Rgba64 => 8,
        }
    }
}

/// A palette entry as Go holds it: color.RGBA from PLTE (and the opaque
/// black past it), color.NRGBA once tRNS gave it an alpha.
#[derive(Clone, Copy)]
struct Entry {
    rgba: [u8; 4],
    nrgba: bool,
}

/// The file, the running CRC and the IDAT stream: what zlib pulls from
/// while the rows are being decoded.
struct Io<'a> {
    r: Input<'a>,
    crc: Crc,
    idat_length: u32,
    // bufio.Reader between the IDAT chunks and zlib
    buf: Vec<u8>,
    bpos: usize,
}

/// What the rows are decoded with, fixed once the chunks before IDAT are
/// read.
#[derive(Clone, Copy)]
struct Header {
    cb: Cb,
    depth: u8,
    use_transparent: bool,
    transparent: [u8; 6],
    pal_len: usize,
}

struct Decoder<'a> {
    io: Io<'a>,
    width: usize,
    height: usize,
    depth: u8,
    cb: Option<Cb>,
    stage: Stage,
    interlace: u8,
    use_transparent: bool,
    transparent: [u8; 6],
    /// Go's palette slice: 256 entries of backing array, len `pal_len`.
    palette: [Entry; 256],
    pal_len: usize,
    img: Option<(Kind, Vec<u8>, usize)>, // kind, Pix, palette length
}

impl<'a> Io<'a> {
    fn verify_checksum(&mut self) -> Result<(), Err> {
        let b = self.r.read_full(4)?;
        if u32::from_be_bytes([b[0], b[1], b[2], b[3]]) != self.crc.0 {
            return Err(format_error("invalid checksum"));
        }
        Ok(())
    }

    /// decoder.Read: the bytes of the current IDAT chunk, moving to the next
    /// IDAT chunk (checking the last one's CRC) when one runs out.
    fn idat_read(&mut self, max: usize) -> Result<&'a [u8], Err> {
        while self.idat_length == 0 {
            self.verify_checksum()?;
            let t = self.r.read_full(8)?;
            self.idat_length = u32::from_be_bytes([t[0], t[1], t[2], t[3]]);
            if &t[4..8] != b"IDAT" {
                return Err(format_error("not enough pixel data"));
            }
            self.crc.reset();
            self.crc.write(&t[4..8]);
        }
        let n = max
            .min(self.idat_length as usize)
            .min(self.r.data.len() - self.r.pos);
        if n == 0 {
            return Err(Err::Eof);
        }
        let s = &self.r.data[self.r.pos..self.r.pos + n];
        self.r.pos += n;
        self.crc.write(s);
        self.idat_length -= n as u32;
        Ok(s)
    }

    /// bufio.Reader.ReadByte over idat_read, 4096 bytes a fill. io.EOF is
    /// Ok(None); flate turns it into ErrUnexpectedEOF.
    fn next_byte(&mut self) -> Result<Option<u8>, String> {
        if self.bpos == self.buf.len() {
            match self.idat_read(4096) {
                Ok(s) => {
                    self.buf.clear();
                    self.buf.extend_from_slice(s);
                    self.bpos = 0;
                }
                Err(Err::Eof) => return Ok(None),
                Err(Err::Msg(m)) => return Err(m),
            }
        }
        let b = self.buf[self.bpos];
        self.bpos += 1;
        Ok(Some(b))
    }
}

const INTERLACING: [(usize, usize, usize, usize); 7] = [
    (8, 8, 0, 0),
    (8, 8, 4, 0),
    (4, 8, 0, 4),
    (4, 4, 2, 0),
    (2, 4, 0, 2),
    (2, 2, 1, 0),
    (1, 2, 0, 1),
];

impl<'a> Decoder<'a> {
    fn new(data: &'a [u8]) -> Self {
        Decoder {
            io: Io {
                r: Input { data, pos: 0 },
                crc: Crc::default(),
                idat_length: 0,
                buf: Vec::new(),
                bpos: 0,
            },
            width: 0,
            height: 0,
            depth: 0,
            cb: None,
            stage: Stage::Start,
            interlace: 0,
            use_transparent: false,
            transparent: [0; 6],
            palette: [Entry {
                rgba: [0, 0, 0, 0xff],
                nrgba: false,
            }; 256],
            pal_len: 0,
            img: None,
        }
    }

    fn cb(&self) -> Cb {
        self.cb.expect("IHDR parsed")
    }

    fn verify_checksum(&mut self) -> Result<(), Err> {
        self.io.verify_checksum()
    }

    fn check_header(&mut self) -> Result<(), Err> {
        let h = self.io.r.read_full(HEADER.len())?;
        if h != HEADER {
            return Err(format_error("not a PNG file"));
        }
        Ok(())
    }

    fn parse_ihdr(&mut self, length: u32) -> Result<(), Err> {
        if length != 13 {
            return Err(format_error("bad IHDR length"));
        }
        let t = self.io.r.read_full(13)?;
        self.io.crc.write(t);
        if t[10] != 0 {
            return Err(unsupported("compression method"));
        }
        if t[11] != 0 {
            return Err(unsupported("filter method"));
        }
        if t[12] > 1 {
            return Err(format_error("invalid interlace method"));
        }
        self.interlace = t[12];
        let w = i32::from_be_bytes([t[0], t[1], t[2], t[3]]);
        let h = i32::from_be_bytes([t[4], t[5], t[6], t[7]]);
        if w <= 0 || h <= 0 {
            return Err(format_error("non-positive dimension"));
        }
        let n = w as i64 * h as i64;
        if n.checked_mul(8).is_none() {
            return Err(unsupported("dimension overflow"));
        }
        self.depth = t[8];
        self.cb = match (t[8], t[9]) {
            (1, 0) => Some(Cb::G1),
            (1, 3) => Some(Cb::P1),
            (2, 0) => Some(Cb::G2),
            (2, 3) => Some(Cb::P2),
            (4, 0) => Some(Cb::G4),
            (4, 3) => Some(Cb::P4),
            (8, 0) => Some(Cb::G8),
            (8, 2) => Some(Cb::Tc8),
            (8, 3) => Some(Cb::P8),
            (8, 4) => Some(Cb::Ga8),
            (8, 6) => Some(Cb::Tca8),
            (16, 0) => Some(Cb::G16),
            (16, 2) => Some(Cb::Tc16),
            (16, 4) => Some(Cb::Ga16),
            (16, 6) => Some(Cb::Tca16),
            _ => None,
        };
        if self.cb.is_none() {
            return Err(unsupported(&format!(
                "bit depth {}, color type {}",
                t[8], t[9]
            )));
        }
        self.width = w as usize;
        self.height = h as usize;
        self.verify_checksum()
    }

    fn parse_plte(&mut self, length: u32) -> Result<(), Err> {
        let np = (length / 3) as usize;
        if !length.is_multiple_of(3) || np == 0 || np > 256 || np > 1usize << self.depth {
            return Err(format_error("bad PLTE length"));
        }
        let t = self.io.r.read_full(3 * np)?;
        self.io.crc.write(t);
        match self.cb() {
            Cb::P1 | Cb::P2 | Cb::P4 | Cb::P8 => {
                for i in 0..256 {
                    self.palette[i] = Entry {
                        rgba: if i < np {
                            [t[3 * i], t[3 * i + 1], t[3 * i + 2], 0xff]
                        } else {
                            [0, 0, 0, 0xff]
                        },
                        nrgba: false,
                    };
                }
                self.pal_len = np;
            }
            Cb::Tc8 | Cb::Tca8 | Cb::Tc16 | Cb::Tca16 => {}
            _ => return Err(format_error("PLTE, color type mismatch")),
        }
        self.verify_checksum()
    }

    fn parse_trns(&mut self, length: u32) -> Result<(), Err> {
        match self.cb() {
            cb @ (Cb::G1 | Cb::G2 | Cb::G4 | Cb::G8 | Cb::G16) => {
                if length != 2 {
                    return Err(format_error("bad tRNS length"));
                }
                let t = self.io.r.read_full(2)?;
                self.io.crc.write(t);
                self.transparent[..2].copy_from_slice(t);
                match cb {
                    Cb::G1 => self.transparent[1] = self.transparent[1].wrapping_mul(0xff),
                    Cb::G2 => self.transparent[1] = self.transparent[1].wrapping_mul(0x55),
                    Cb::G4 => self.transparent[1] = self.transparent[1].wrapping_mul(0x11),
                    _ => {}
                }
                self.use_transparent = true;
            }
            Cb::Tc8 | Cb::Tc16 => {
                if length != 6 {
                    return Err(format_error("bad tRNS length"));
                }
                let t = self.io.r.read_full(6)?;
                self.io.crc.write(t);
                self.transparent.copy_from_slice(t);
                self.use_transparent = true;
            }
            Cb::P1 | Cb::P2 | Cb::P4 | Cb::P8 => {
                if length > 256 {
                    return Err(format_error("bad tRNS length"));
                }
                let t = self.io.r.read_full(length as usize)?;
                self.io.crc.write(t);
                let n = t.len();
                if self.pal_len < n {
                    self.pal_len = n;
                }
                for (i, &a) in t.iter().enumerate() {
                    let e = &mut self.palette[i];
                    e.rgba[3] = a;
                    e.nrgba = true;
                }
            }
            _ => return Err(format_error("tRNS, color type mismatch")),
        }
        self.verify_checksum()
    }

    fn decode_idat(&mut self, length: u32) -> Result<(), Err> {
        self.io.idat_length = length;
        let hdr = Header {
            cb: self.cb(),
            depth: self.depth,
            use_transparent: self.use_transparent,
            transparent: self.transparent,
            pal_len: self.pal_len,
        };
        let kind = hdr.kind();
        let (w, h, interlace) = (self.width, self.height, self.interlace);
        let io = &mut self.io;
        let mut src = || io.next_byte();
        let mut inf = Inflater::new(&mut src);
        let (pix, pal_len) = if interlace == 0 {
            hdr.read_pass(&mut inf, w, h)?
        } else {
            let bpp = kind.bpp();
            let stride = w * bpp;
            let mut pix = vec![0u8; stride * h];
            let mut pal_len = hdr.pal_len;
            for &(xf, yf, xo, yo) in &INTERLACING {
                let pw = (w + xf - 1 - xo) / xf;
                let ph = (h + yf - 1 - yo) / yf;
                if pw == 0 || ph == 0 {
                    continue;
                }
                let (pass, plen) = hdr.read_pass(&mut inf, pw, ph)?;
                // mergePassInto: a pass that grew the palette further wins.
                pal_len = pal_len.max(plen);
                let mut s = 0;
                for y in 0..ph {
                    let base = (y * yf + yo) * stride + xo * bpp;
                    for x in 0..pw {
                        let o = base + x * xf * bpp;
                        pix[o..o + bpp].copy_from_slice(&pass[s..s + bpp]);
                        s += bpp;
                    }
                }
            }
            (pix, pal_len)
        };
        // Then the zlib stream must end: one more byte is too much.
        let mut extra = Vec::new();
        let more = inf.read(&mut extra, 1);
        drop(inf);
        if let Err(e) = more {
            return Err(format_error(&e));
        }
        if !extra.is_empty() || self.io.idat_length != 0 {
            return Err(format_error("too much pixel data"));
        }
        self.img = Some((kind, pix, pal_len));
        self.verify_checksum()
    }

    fn parse_chunk(&mut self, config_only: bool) -> Result<(), Err> {
        let t = self.io.r.read_full(8)?;
        let length = u32::from_be_bytes([t[0], t[1], t[2], t[3]]);
        let name: [u8; 4] = [t[4], t[5], t[6], t[7]];
        self.io.crc.reset();
        self.io.crc.write(&name);
        match &name {
            b"IHDR" => {
                if self.stage != Stage::Start {
                    return Err(format_error("chunk out of order"));
                }
                self.stage = Stage::SeenIhdr;
                return self.parse_ihdr(length);
            }
            b"PLTE" => {
                if self.stage != Stage::SeenIhdr {
                    return Err(format_error("chunk out of order"));
                }
                self.stage = Stage::SeenPlte;
                return self.parse_plte(length);
            }
            b"tRNS" => {
                let cb = self.cb;
                if cb.is_some_and(Cb::paletted) {
                    if self.stage != Stage::SeenPlte {
                        return Err(format_error("chunk out of order"));
                    }
                } else if cb.is_some_and(Cb::true_color) {
                    if self.stage != Stage::SeenIhdr && self.stage != Stage::SeenPlte {
                        return Err(format_error("chunk out of order"));
                    }
                } else if self.stage != Stage::SeenIhdr {
                    return Err(format_error("chunk out of order"));
                }
                self.stage = Stage::SeenTrns;
                return self.parse_trns(length);
            }
            b"IDAT" => {
                if self.stage < Stage::SeenIhdr
                    || self.stage > Stage::SeenIdat
                    || (self.stage == Stage::SeenIhdr && self.cb.is_some_and(Cb::paletted))
                {
                    return Err(format_error("chunk out of order"));
                }
                if self.stage != Stage::SeenIdat {
                    self.stage = Stage::SeenIdat;
                    if config_only {
                        return Ok(());
                    }
                    return self.decode_idat(length);
                }
                // A later IDAT chunk is skipped like any other.
            }
            b"IEND" => {
                if self.stage != Stage::SeenIdat {
                    return Err(format_error("chunk out of order"));
                }
                self.stage = Stage::SeenIend;
                if length != 0 {
                    return Err(format_error("bad IEND length"));
                }
                return self.verify_checksum();
            }
            _ => {}
        }
        if length > 0x7fffffff {
            return Err(format_error(&format!("Bad chunk length: {length}")));
        }
        let mut left = length as usize;
        while left > 0 {
            let n = left.min(4096);
            let s = self.io.r.read_full(n)?;
            self.io.crc.write(s);
            left -= n;
        }
        self.verify_checksum()
    }
}

impl Header {
    fn kind(&self) -> Kind {
        match self.cb {
            Cb::G1 | Cb::G2 | Cb::G4 | Cb::G8 => {
                if self.use_transparent {
                    Kind::Nrgba
                } else {
                    Kind::Gray
                }
            }
            Cb::Ga8 | Cb::Tca8 => Kind::Nrgba,
            Cb::Tc8 => {
                if self.use_transparent {
                    Kind::Nrgba
                } else {
                    Kind::Rgba
                }
            }
            Cb::P1 | Cb::P2 | Cb::P4 | Cb::P8 => Kind::Paletted,
            Cb::G16 => {
                if self.use_transparent {
                    Kind::Nrgba64
                } else {
                    Kind::Gray16
                }
            }
            Cb::Ga16 | Cb::Tca16 => Kind::Nrgba64,
            Cb::Tc16 => {
                if self.use_transparent {
                    Kind::Nrgba64
                } else {
                    Kind::Rgba64
                }
            }
        }
    }

    fn bits_per_pixel(&self) -> usize {
        match self.cb {
            Cb::G1 | Cb::G2 | Cb::G4 | Cb::G8 | Cb::P1 | Cb::P2 | Cb::P4 | Cb::P8 => {
                self.depth as usize
            }
            Cb::Ga8 | Cb::G16 => 16,
            Cb::Tc8 => 24,
            Cb::Tca8 | Cb::Ga16 => 32,
            Cb::Tc16 => 48,
            Cb::Tca16 => 64,
        }
    }

    /// One pass (or the whole image), as readImagePass. Returns the Pix of a
    /// width x height image of self.kind() and its palette length.
    fn read_pass(
        &self,
        inf: &mut Inflater,
        width: usize,
        height: usize,
    ) -> Result<(Vec<u8>, usize), Err> {
        let kind = self.kind();
        let cb = self.cb;
        let bpp_bits = self.bits_per_pixel();
        let bytes_pp = bpp_bits.div_ceil(8);
        let row_size = 1 + (bpp_bits * width).div_ceil(8);
        let stride = width * kind.bpp();
        let mut pix = vec![0u8; stride * height];
        let mut pal_len = self.pal_len;
        let mut cr: Vec<u8> = vec![0; row_size];
        let mut pr: Vec<u8> = vec![0; row_size];
        let mut row = Vec::with_capacity(row_size);
        let tr = self.transparent;
        let use_t = self.use_transparent;
        for y in 0..height {
            row.clear();
            match inf.read(&mut row, row_size) {
                Ok(()) if row.len() == row_size => {}
                Ok(()) => return Err(format_error("not enough pixel data")),
                Err(e) if e == "unexpected EOF" => {
                    return Err(format_error("not enough pixel data"))
                }
                Err(e) => return Err(Err::Msg(e)),
            }
            cr.copy_from_slice(&row);
            let (ft, cdat) = cr.split_first_mut().expect("row has a filter byte");
            let pdat = &pr[1..];
            match *ft {
                0 => {}
                1 => {
                    for i in bytes_pp..cdat.len() {
                        cdat[i] = cdat[i].wrapping_add(cdat[i - bytes_pp]);
                    }
                }
                2 => {
                    for (c, p) in cdat.iter_mut().zip(pdat) {
                        *c = c.wrapping_add(*p);
                    }
                }
                3 => {
                    for i in 0..bytes_pp {
                        cdat[i] = cdat[i].wrapping_add(pdat[i] / 2);
                    }
                    for i in bytes_pp..cdat.len() {
                        cdat[i] = cdat[i]
                            .wrapping_add(((cdat[i - bytes_pp] as u32 + pdat[i] as u32) / 2) as u8);
                    }
                }
                4 => filter_paeth(cdat, pdat, bytes_pp),
                _ => return Err(format_error("bad filter type")),
            }
            let line = &mut pix[y * stride..(y + 1) * stride];
            let set_nrgba =
                |line: &mut [u8], x: usize, c: [u8; 4]| line[x * 4..x * 4 + 4].copy_from_slice(&c);
            let set_nrgba64 = |line: &mut [u8], x: usize, c: [u16; 4]| {
                for k in 0..4 {
                    line[x * 8 + 2 * k..x * 8 + 2 * k + 2].copy_from_slice(&c[k].to_be_bytes());
                }
            };
            let be = |hi: u8, lo: u8| (hi as u16) << 8 | lo as u16;
            match cb {
                Cb::G1 | Cb::G2 | Cb::G4 => {
                    let (bits, mul) = match cb {
                        Cb::G1 => (1, 0xff),
                        Cb::G2 => (2, 0x55),
                        _ => (4, 0x11),
                    };
                    let per = 8 / bits;
                    let mut x = 0;
                    while x < width {
                        let mut b = cdat[x / per];
                        let mut x2 = 0;
                        while x2 < per && x + x2 < width {
                            let ycol = (b >> (8 - bits)).wrapping_mul(mul);
                            if use_t {
                                let a = if ycol == tr[1] { 0 } else { 0xff };
                                set_nrgba(line, x + x2, [ycol, ycol, ycol, a]);
                            } else {
                                line[x + x2] = ycol;
                            }
                            b <<= bits;
                            x2 += 1;
                        }
                        x += per;
                    }
                }
                Cb::G8 => {
                    if use_t {
                        for x in 0..width {
                            let ycol = cdat[x];
                            let a = if ycol == tr[1] { 0 } else { 0xff };
                            set_nrgba(line, x, [ycol, ycol, ycol, a]);
                        }
                    } else {
                        line.copy_from_slice(&cdat[..width]);
                    }
                }
                Cb::Ga8 => {
                    for x in 0..width {
                        let ycol = cdat[2 * x];
                        set_nrgba(line, x, [ycol, ycol, ycol, cdat[2 * x + 1]]);
                    }
                }
                Cb::Tc8 => {
                    for x in 0..width {
                        let (r, g, b) = (cdat[3 * x], cdat[3 * x + 1], cdat[3 * x + 2]);
                        let a = if use_t && r == tr[1] && g == tr[3] && b == tr[5] {
                            0
                        } else {
                            0xff
                        };
                        set_nrgba(line, x, [r, g, b, a]);
                    }
                }
                Cb::P1 | Cb::P2 | Cb::P4 => {
                    let bits = match cb {
                        Cb::P1 => 1,
                        Cb::P2 => 2,
                        _ => 4,
                    };
                    let per = 8 / bits;
                    let mut x = 0;
                    while x < width {
                        let mut b = cdat[x / per];
                        let mut x2 = 0;
                        while x2 < per && x + x2 < width {
                            let idx = b >> (8 - bits);
                            if pal_len <= idx as usize {
                                pal_len = idx as usize + 1;
                            }
                            line[x + x2] = idx;
                            b <<= bits;
                            x2 += 1;
                        }
                        x += per;
                    }
                }
                Cb::P8 => {
                    if pal_len != 256 {
                        for &c in &cdat[..width] {
                            if pal_len <= c as usize {
                                pal_len = c as usize + 1;
                            }
                        }
                    }
                    line.copy_from_slice(&cdat[..width]);
                }
                Cb::Tca8 => line.copy_from_slice(&cdat[..width * 4]),
                Cb::G16 => {
                    let ty = be(tr[0], tr[1]);
                    for x in 0..width {
                        let ycol = be(cdat[2 * x], cdat[2 * x + 1]);
                        if use_t {
                            let a = if ycol == ty { 0 } else { 0xffff };
                            set_nrgba64(line, x, [ycol, ycol, ycol, a]);
                        } else {
                            line[2 * x..2 * x + 2].copy_from_slice(&ycol.to_be_bytes());
                        }
                    }
                }
                Cb::Ga16 => {
                    for x in 0..width {
                        let ycol = be(cdat[4 * x], cdat[4 * x + 1]);
                        let a = be(cdat[4 * x + 2], cdat[4 * x + 3]);
                        set_nrgba64(line, x, [ycol, ycol, ycol, a]);
                    }
                }
                Cb::Tc16 => {
                    let (tr16, tg16, tb16) = (be(tr[0], tr[1]), be(tr[2], tr[3]), be(tr[4], tr[5]));
                    for x in 0..width {
                        let r = be(cdat[6 * x], cdat[6 * x + 1]);
                        let g = be(cdat[6 * x + 2], cdat[6 * x + 3]);
                        let b = be(cdat[6 * x + 4], cdat[6 * x + 5]);
                        let a = if use_t && r == tr16 && g == tg16 && b == tb16 {
                            0
                        } else {
                            0xffff
                        };
                        set_nrgba64(line, x, [r, g, b, a]);
                    }
                }
                Cb::Tca16 => line.copy_from_slice(&cdat[..width * 8]),
            }
            std::mem::swap(&mut cr, &mut pr);
        }
        Ok((pix, pal_len))
    }
}

fn filter_paeth(cdat: &mut [u8], pdat: &[u8], bpp: usize) {
    for i in 0..bpp {
        let (mut a, mut c): (i32, i32) = (0, 0);
        let mut j = i;
        while j < cdat.len() {
            let b = pdat[j] as i32;
            let mut pa = b - c;
            let mut pb = a - c;
            let pc = (pa + pb).abs();
            pa = pa.abs();
            pb = pb.abs();
            if pa <= pb && pa <= pc {
            } else if pb <= pc {
                a = b;
            } else {
                a = c;
            }
            a += cdat[j] as i32;
            a &= 0xff;
            cdat[j] = a as u8;
            c = b;
            j += bpp;
        }
    }
}

pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    let mut d = Decoder::new(data);
    d.check_header().map_err(Err::text)?;
    loop {
        d.parse_chunk(true).map_err(Err::text)?;
        if d.cb.is_some_and(Cb::paletted) {
            if d.stage >= Stage::SeenTrns {
                break;
            }
        } else if d.stage >= Stage::SeenIhdr {
            break;
        }
    }
    Ok((d.width, d.height))
}

pub fn decode(data: &[u8]) -> Result<Image, String> {
    let mut d = Decoder::new(data);
    d.check_header().map_err(Err::text)?;
    while d.stage != Stage::SeenIend {
        d.parse_chunk(false).map_err(Err::text)?;
    }
    let (kind, pix, pal_len) = d.img.take().expect("IDAT decoded before IEND");
    let (w, h) = (d.width, d.height);
    let u16s = |pix: &[u8]| -> Vec<u16> {
        pix.as_chunks::<2>()
            .0
            .iter()
            .map(|c| u16::from_be_bytes([c[0], c[1]]))
            .collect()
    };
    Ok(match kind {
        Kind::Gray => Image::Gray { w, h, pix },
        Kind::Nrgba => Image::Nrgba { w, h, pix },
        Kind::Rgba => Image::Rgba { w, h, pix },
        Kind::Gray16 => Image::Gray16 {
            w,
            h,
            pix: u16s(&pix),
        },
        Kind::Nrgba64 => Image::Nrgba64 {
            w,
            h,
            pix: u16s(&pix),
        },
        Kind::Rgba64 => Image::Rgba64 {
            w,
            h,
            pix: u16s(&pix),
        },
        Kind::Paletted => Image::Paletted {
            w,
            h,
            pix,
            palette: d.palette[..pal_len]
                .iter()
                .map(|e| {
                    let [r, g, b, a] = e.rgba;
                    if e.nrgba {
                        nrgba_color(r, g, b, a)
                    } else {
                        rgba_color(r, g, b, a)
                    }
                })
                .collect(),
        },
    })
}
