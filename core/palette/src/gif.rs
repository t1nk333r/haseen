// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! GIF, a port of Go's image/gif reader and compress/lzw decoder (Go
//! 1.27): the first frame only, as image.Decode returns it, a Paletted
//! image of the frame's own size, its local or global table, the
//! transparent index as color.RGBA{}, and Go's checks and error text.

use crate::image::{rgba_color, Image};

const F_COLOR_TABLE: u8 = 1 << 7;
const F_INTERLACE: u8 = 1 << 6;
const F_COLOR_TABLE_BITS: u8 = 7;

#[derive(Clone)]
enum Err {
    Eof,
    Msg(String),
}

impl Err {
    /// io.ErrUnexpectedEOF's text for EOF: the readers convert it.
    fn text(&self) -> String {
        match self {
            Err::Eof => "unexpected EOF".into(),
            Err::Msg(m) => m.clone(),
        }
    }
}

struct Decoder<'a> {
    data: &'a [u8],
    pos: usize,
    width: usize,
    height: usize,
    image_fields: u8,
    transparent_index: u8,
    has_transparent_index: bool,
    global: Option<Vec<[u8; 3]>>,
}

impl<'a> Decoder<'a> {
    /// readFull: io.EOF becomes io.ErrUnexpectedEOF.
    fn read_full(&mut self, n: usize) -> Result<&'a [u8], Err> {
        if self.data.len() - self.pos < n {
            self.pos = self.data.len();
            return Err(Err::Msg("unexpected EOF".into()));
        }
        let s = &self.data[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }

    fn read_byte(&mut self) -> Result<u8, Err> {
        Ok(self.read_full(1)?[0])
    }

    fn header(&mut self) -> Result<(), String> {
        let t = self
            .read_full(13)
            .map_err(|e| format!("gif: reading header: {}", e.text()))?;
        let vers = &t[..6];
        if vers != b"GIF87a" && vers != b"GIF89a" {
            return Err(format!(
                "gif: can't recognize format {}",
                crate::json::go_quote_bytes(vers)
            ));
        }
        self.width = t[6] as usize | (t[7] as usize) << 8;
        self.height = t[8] as usize | (t[9] as usize) << 8;
        let fields = t[10];
        if fields & F_COLOR_TABLE != 0 {
            self.global = Some(self.color_table(fields)?);
        }
        Ok(())
    }

    fn color_table(&mut self, fields: u8) -> Result<Vec<[u8; 3]>, String> {
        let n = 1usize << (1 + (fields & F_COLOR_TABLE_BITS));
        let t = self
            .read_full(3 * n)
            .map_err(|e| format!("gif: reading color table: {}", e.text()))?;
        Ok(t.as_chunks::<3>()
            .0
            .iter()
            .map(|c| [c[0], c[1], c[2]])
            .collect())
    }

    fn read_block(&mut self) -> Result<usize, Err> {
        let n = self.read_byte()? as usize;
        if n == 0 {
            return Ok(0);
        }
        self.read_full(n)?;
        Ok(n)
    }

    fn extension(&mut self) -> Result<(), String> {
        let ext_err = |e: Err| format!("gif: reading extension: {}", e.text());
        let extension = self.read_byte().map_err(ext_err)?;
        let mut size = 0;
        match extension {
            0x01 => size = 13,
            0xF9 => return self.graphic_control(),
            0xFE => {}
            0xFF => size = self.read_byte().map_err(ext_err)? as usize,
            _ => return Err(format!("gif: unknown extension 0x{extension:02x}")),
        }
        let mut app = &[][..];
        if size > 0 {
            app = self.read_full(size).map_err(ext_err)?;
        }
        if extension == 0xFF && app == b"NETSCAPE2.0" {
            // The loop count: read, and not needed here.
            if self.read_block().map_err(ext_err)? == 0 {
                return Ok(());
            }
        }
        loop {
            if self.read_block().map_err(ext_err)? == 0 {
                return Ok(());
            }
        }
    }

    fn graphic_control(&mut self) -> Result<(), String> {
        let t = self
            .read_full(6)
            .map_err(|e| format!("gif: can't read graphic control: {}", e.text()))?;
        if t[0] != 4 {
            return Err(format!(
                "gif: invalid graphic control extension block size: {}",
                t[0]
            ));
        }
        let flags = t[1];
        if flags & 1 != 0 {
            self.transparent_index = t[4];
            self.has_transparent_index = true;
        }
        if t[5] != 0 {
            return Err(format!(
                "gif: invalid graphic control extension block terminator: {}",
                t[5]
            ));
        }
        Ok(())
    }

    fn image_descriptor(&mut self) -> Result<Image, String> {
        let t = self
            .read_full(9)
            .map_err(|e| format!("gif: can't read image descriptor: {}", e.text()))?;
        let left = t[0] as usize | (t[1] as usize) << 8;
        let top = t[2] as usize | (t[3] as usize) << 8;
        let width = t[4] as usize | (t[5] as usize) << 8;
        let height = t[6] as usize | (t[7] as usize) << 8;
        self.image_fields = t[8];
        if left + width > self.width || top + height > self.height {
            return Err("gif: frame bounds larger than image bounds".into());
        }
        let local = self.image_fields & F_COLOR_TABLE != 0;
        let table = if local {
            let fields = self.image_fields;
            self.color_table(fields)?
        } else {
            self.global.clone().ok_or("gif: no color table")?
        };
        let mut palette: Vec<[u8; 4]> =
            table.into_iter().map(|[r, g, b]| [r, g, b, 0xff]).collect();
        if self.has_transparent_index {
            let ti = self.transparent_index as usize;
            if ti >= palette.len() {
                palette.resize(ti + 1, [0; 4]);
            }
            palette[ti] = [0; 4];
        }
        let data_err = |e: Err| format!("gif: reading image data: {}", e.text());
        let lit_width = self.read_byte().map_err(data_err)?;
        if !(2..=8).contains(&lit_width) {
            return Err(format!(
                "gif: pixel size in decode out of range: {lit_width}"
            ));
        }
        let mut pix = vec![0u8; width * height];
        let mut lzw = Lzw::new(lit_width as u32);
        let mut br = BlockReader {
            buf: [0; 256],
            i: 0,
            j: 0,
            err: None,
        };
        // io.ReadFull(lzwr, m.Pix)
        let mut n = 0;
        while n < pix.len() {
            match lzw.read(self, &mut br, &mut pix[n..]) {
                Ok(k) => n += k,
                Err(Err::Eof) => return Err("gif: not enough image data".into()),
                Err(Err::Msg(m)) if m == "unexpected EOF" => {
                    return Err("gif: not enough image data".into())
                }
                Err(e) => return Err(data_err(e)),
            }
        }
        let mut one = [0u8; 1];
        match lzw.read(self, &mut br, &mut one) {
            Ok(0) => {}
            Ok(_) => return Err("gif: too much image data".into()),
            Err(Err::Eof) => {}
            Err(Err::Msg(m)) if m == "unexpected EOF" => {}
            Err(e) => return Err(data_err(e)),
        }
        match br.close(self) {
            Ok(()) => {}
            Err(Err::Msg(m)) if m == "gif: too much image data" => return Err(m),
            Err(e) => return Err(data_err(e)),
        }
        if palette.len() < 256 && pix.iter().any(|&p| p as usize >= palette.len()) {
            return Err("gif: invalid pixel value".into());
        }
        if self.image_fields & F_INTERLACE != 0 {
            pix = uninterlace(&pix, width, height);
        }
        Ok(Image::Paletted {
            w: width,
            h: height,
            pix,
            palette: palette
                .iter()
                .map(|&[r, g, b, a]| rgba_color(r, g, b, a))
                .collect(),
        })
    }
}

/// The data sub-blocks of one image, read as one stream.
struct BlockReader {
    buf: [u8; 256],
    i: usize,
    j: usize,
    err: Option<Err>,
}

impl BlockReader {
    fn fill(&mut self, d: &mut Decoder) {
        if self.err.is_some() {
            return;
        }
        match d.read_byte() {
            Ok(0) => {
                self.j = 0;
                self.err = Some(Err::Eof);
                return;
            }
            Ok(n) => self.j = n as usize,
            Err(e) => {
                self.j = 0;
                self.err = Some(e);
                return;
            }
        }
        self.i = 0;
        match d.read_full(self.j) {
            Ok(s) => self.buf[..s.len()].copy_from_slice(s),
            Err(e) => {
                self.err = Some(e);
                self.j = 0;
            }
        }
    }

    fn read_byte(&mut self, d: &mut Decoder) -> Result<u8, Err> {
        if self.i == self.j {
            self.fill(d);
            if let Some(e) = &self.err {
                return Err(e.clone());
            }
        }
        let c = self.buf[self.i];
        self.i += 1;
        Ok(c)
    }

    fn close(&mut self, d: &mut Decoder) -> Result<(), Err> {
        let too_much = || Err::Msg("gif: too much image data".into());
        match &self.err {
            Some(Err::Eof) => return Ok(()),
            Some(e) => return Err(e.clone()),
            None => {}
        }
        if self.i == self.j {
            self.fill(d);
            match &self.err {
                Some(Err::Eof) => return Ok(()),
                Some(e) => return Err(e.clone()),
                None if self.j > 1 => return Err(too_much()),
                None => {}
            }
        }
        self.fill(d);
        match &self.err {
            Some(Err::Eof) => Ok(()),
            Some(e) => Err(e.clone()),
            None => Err(too_much()),
        }
    }
}

const MAX_WIDTH: u32 = 12;
const INVALID: u16 = 0xffff;
const FLUSH: usize = 1 << MAX_WIDTH;

/// compress/lzw's Reader, LSB order.
struct Lzw {
    bits: u32,
    nbits: u32,
    width: u32,
    lit_width: u32,
    err: Option<Err>,
    clear: u16,
    eof: u16,
    hi: u16,
    overflow: u16,
    last: u16,
    suffix: Vec<u8>,
    prefix: Vec<u16>,
    output: Vec<u8>,
    o: usize,
    to_read: (usize, usize),
}

impl Lzw {
    fn new(lit_width: u32) -> Lzw {
        let clear = 1u16 << lit_width;
        Lzw {
            bits: 0,
            nbits: 0,
            width: 1 + lit_width,
            lit_width,
            err: None,
            clear,
            eof: clear + 1,
            hi: clear + 1,
            overflow: 1 << (1 + lit_width),
            last: INVALID,
            suffix: vec![0; 1 << MAX_WIDTH],
            prefix: vec![0; 1 << MAX_WIDTH],
            output: vec![0; 2 * (1 << MAX_WIDTH)],
            o: 0,
            to_read: (0, 0),
        }
    }

    fn read(&mut self, d: &mut Decoder, br: &mut BlockReader, b: &mut [u8]) -> Result<usize, Err> {
        loop {
            let (s, e) = self.to_read;
            if s < e {
                let n = b.len().min(e - s);
                b[..n].copy_from_slice(&self.output[s..s + n]);
                self.to_read.0 += n;
                return Ok(n);
            }
            if let Some(err) = &self.err {
                return Err(err.clone());
            }
            self.decode(d, br);
        }
    }

    fn code(&mut self, d: &mut Decoder, br: &mut BlockReader) -> Result<u16, Err> {
        while self.nbits < self.width {
            let x = br.read_byte(d)?;
            self.bits |= (x as u32) << self.nbits;
            self.nbits += 8;
        }
        let code = (self.bits & ((1 << self.width) - 1)) as u16;
        self.bits >>= self.width;
        self.nbits -= self.width;
        Ok(code)
    }

    fn decode(&mut self, d: &mut Decoder, br: &mut BlockReader) {
        loop {
            let code = match self.code(d, br) {
                Ok(c) => c,
                Err(Err::Eof) => {
                    self.err = Some(Err::Msg("unexpected EOF".into()));
                    break;
                }
                Err(e) => {
                    self.err = Some(e);
                    break;
                }
            };
            if code < self.clear {
                self.output[self.o] = code as u8;
                self.o += 1;
                if self.last != INVALID {
                    self.suffix[self.hi as usize] = code as u8;
                    self.prefix[self.hi as usize] = self.last;
                }
            } else if code == self.clear {
                self.width = 1 + self.lit_width;
                self.hi = self.eof;
                self.overflow = 1 << self.width;
                self.last = INVALID;
                continue;
            } else if code == self.eof {
                self.err = Some(Err::Eof);
                break;
            } else if code <= self.hi {
                let mut c = code;
                let mut i = self.output.len() - 1;
                if code == self.hi && self.last != INVALID {
                    c = self.last;
                    while c >= self.clear {
                        c = self.prefix[c as usize];
                    }
                    self.output[i] = c as u8;
                    i -= 1;
                    c = self.last;
                }
                while c >= self.clear {
                    self.output[i] = self.suffix[c as usize];
                    i -= 1;
                    c = self.prefix[c as usize];
                }
                self.output[i] = c as u8;
                let len = self.output.len() - i;
                self.output.copy_within(i.., self.o);
                self.o += len;
                if self.last != INVALID {
                    self.suffix[self.hi as usize] = c as u8;
                    self.prefix[self.hi as usize] = self.last;
                }
            } else {
                self.err = Some(Err::Msg("lzw: invalid code".into()));
                break;
            }
            self.last = code;
            self.hi += 1;
            if self.hi >= self.overflow {
                if self.width == MAX_WIDTH {
                    self.last = INVALID;
                    self.hi -= 1;
                } else {
                    self.width += 1;
                    self.overflow = 1 << self.width;
                }
            }
            if self.o >= FLUSH {
                break;
            }
        }
        self.to_read = (0, self.o);
        self.o = 0;
    }
}

fn uninterlace(pix: &[u8], dx: usize, dy: usize) -> Vec<u8> {
    let mut out = vec![0u8; dx * dy];
    let mut offset = 0;
    for (skip, start) in [(8, 0), (8, 4), (4, 2), (2, 1)] {
        let mut n_offset = start * dx;
        let mut y = start;
        while y < dy {
            out[n_offset..n_offset + dx].copy_from_slice(&pix[offset..offset + dx]);
            offset += dx;
            n_offset += dx * skip;
            y += skip;
        }
    }
    out
}

fn decoder(data: &[u8]) -> Decoder<'_> {
    Decoder {
        data,
        pos: 0,
        width: 0,
        height: 0,
        image_fields: 0,
        transparent_index: 0,
        has_transparent_index: false,
        global: None,
    }
}

pub fn decode_config(data: &[u8]) -> Result<(usize, usize), String> {
    let mut d = decoder(data);
    d.header()?;
    Ok((d.width, d.height))
}

pub fn decode(data: &[u8]) -> Result<Image, String> {
    let mut d = decoder(data);
    d.header()?;
    loop {
        let c = d
            .read_byte()
            .map_err(|e| format!("gif: reading frames: {}", e.text()))?;
        match c {
            0x21 => d.extension()?,
            0x2C => return d.image_descriptor(),
            0x3B => return Err("gif: missing image data".into()),
            _ => return Err(format!("gif: unknown block type: 0x{c:02x}")),
        }
    }
}
