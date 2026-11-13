//! VP8 (lossy WebP), a port of golang.org/x/image/vp8 (v0.46.0). VP8's
//! reconstruction is normative, so its Y, Cb and Cr planes are what any
//! conforming decoder produces; what matters here is that, like Go, it
//! returns them as a 4:2:0 YCbCr image and leaves the conversion to the
//! scaler. Go's operator precedence (`a + b>>3` is `a + (b>>3)`) is spelled
//! out with parentheses.

use crate::image::{Ratio, YCbCr};

include!("vp8_tables.rs");

const UNIFORM_PROB: u8 = 128;

#[derive(Default)]
struct Partition {
    buf: Vec<u8>,
    r: usize,
    range_m1: u32,
    bits: u32,
    n_bits: u8,
    unexpected_eof: bool,
}

impl Partition {
    fn init(buf: Vec<u8>) -> Partition {
        Partition {
            buf,
            r: 0,
            range_m1: 254,
            bits: 0,
            n_bits: 0,
            unexpected_eof: false,
        }
    }

    fn read_bit(&mut self, prob: u8) -> bool {
        if self.n_bits < 8 {
            if self.r >= self.buf.len() {
                self.unexpected_eof = true;
                return false;
            }
            let x = self.buf[self.r] as u32;
            self.bits |= x << (8 - self.n_bits);
            self.r += 1;
            self.n_bits += 8;
        }
        let split = ((self.range_m1 * prob as u32) >> 8) + 1;
        let bit = self.bits >= split << 8;
        if bit {
            self.range_m1 -= split;
            self.bits -= split << 8;
        } else {
            self.range_m1 = split - 1;
        }
        if self.range_m1 < 127 {
            let shift = LUT_SHIFT[self.range_m1 as usize];
            self.range_m1 = LUT_RANGE_M1[self.range_m1 as usize] as u32;
            self.bits <<= shift;
            self.n_bits -= shift;
        }
        bit
    }

    fn read_uint(&mut self, prob: u8, mut n: u8) -> u32 {
        let mut u = 0u32;
        while n > 0 {
            n -= 1;
            if self.read_bit(prob) {
                u |= 1 << n;
            }
        }
        u
    }

    fn read_int(&mut self, prob: u8, n: u8) -> i32 {
        let u = self.read_uint(prob, n);
        if self.read_bit(prob) {
            -(u as i32)
        } else {
            u as i32
        }
    }

    fn read_optional_int(&mut self, prob: u8, n: u8) -> i32 {
        if !self.read_bit(prob) {
            return 0;
        }
        self.read_int(prob, n)
    }
}

pub struct FrameHeader {
    pub key_frame: bool,
    pub first_partition_len: u32,
    pub width: usize,
    pub height: usize,
}

#[derive(Default)]
struct SegmentHeader {
    use_segment: bool,
    update_map: bool,
    relative_delta: bool,
    quantizer: [i8; 4],
    filter_strength: [i8; 4],
    prob: [u8; 3],
}

#[derive(Default)]
struct FilterHeader {
    simple: bool,
    level: i8,
    sharpness: u8,
    use_lf_delta: bool,
    ref_lf_delta: [i8; 4],
    mode_lf_delta: [i8; 4],
}

#[derive(Clone, Copy, Default)]
struct Mb {
    pred: [u8; 4],
    nz_mask: u8,
    nz_y16: u8,
}

#[derive(Clone, Copy, Default)]
struct Quant {
    y1: [u16; 2],
    y2: [u16; 2],
    uv: [u16; 2],
}

#[derive(Clone, Copy, Default)]
struct FilterParam {
    level: u8,
    ilevel: u8,
    hlevel: u8,
    inner: bool,
}

const PLANE_Y1_WITH_Y2: usize = 0;
const PLANE_Y2: usize = 1;
const PLANE_UV: usize = 2;
const PLANE_Y1_SANS_Y2: usize = 3;

const PRED_DC: u8 = 0;
const PRED_TM: u8 = 1;
const PRED_VE: u8 = 2;
const PRED_HE: u8 = 3;
const PRED_RD: u8 = 4;
const PRED_VR: u8 = 5;
const PRED_LD: u8 = 6;
const PRED_VL: u8 = 7;
const PRED_HD: u8 = 8;
const PRED_HU: u8 = 9;
const PRED_DC_TOP: u8 = 10;
const PRED_DC_LEFT: u8 = 11;
const PRED_DC_TOP_LEFT: u8 = 12;

const B_COEFF_BASE: usize = 16 * 16;
const R_COEFF_BASE: usize = 16 * 16 + 8 * 8;
const WHT_COEFF_BASE: usize = 16 * 16 + 2 * 8 * 8;
const YBR_YX: usize = 8;
const YBR_YY: usize = 1;
const YBR_BX: usize = 8;
const YBR_BY: usize = 18;
const YBR_RX: usize = 24;
const YBR_RY: usize = 18;

const BANDS: [usize; 17] = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0];
const CAT3456: [[u8; 12]; 4] = [
    [173, 148, 140, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [176, 155, 140, 135, 0, 0, 0, 0, 0, 0, 0, 0],
    [180, 157, 141, 134, 130, 0, 0, 0, 0, 0, 0, 0],
    [254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129, 0],
];
const ZIGZAG: [usize; 16] = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15];

const DEQUANT_DC: [u16; 128] = [
    4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15, 16, 17, 17, 18, 19, 20, 20, 21, 21, 22, 22, 23,
    23, 24, 25, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43, 44,
    45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67,
    68, 69, 70, 71, 72, 73, 74, 75, 76, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91,
    93, 95, 96, 98, 100, 101, 102, 104, 106, 108, 110, 112, 114, 116, 118, 122, 124, 126, 128, 130,
    132, 134, 136, 138, 140, 143, 145, 148, 151, 154, 157,
];
const DEQUANT_AC: [u16; 128] = [
    4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
    29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52,
    53, 54, 55, 56, 57, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92, 94,
    96, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116, 119, 122, 125, 128, 131, 134, 137, 140,
    143, 146, 149, 152, 155, 158, 161, 164, 167, 170, 173, 177, 181, 185, 189, 193, 197, 201, 205,
    209, 213, 217, 221, 225, 229, 234, 239, 245, 249, 254, 259, 264, 269, 274, 279, 284,
];

fn btou(b: bool) -> u8 {
    b as u8
}

fn pack(x: [u8; 4], shift: u32) -> u32 {
    ((x[0] as u32) | (x[1] as u32) << 1 | (x[2] as u32) << 2 | (x[3] as u32) << 3) << shift
}

fn unpack(v: u8) -> [u8; 4] {
    [v & 1, (v >> 1) & 1, (v >> 2) & 1, (v >> 3) & 1]
}

fn clip(x: i32, min: i32, max: i32) -> i32 {
    x.clamp(min, max)
}

fn clip8(i: i32) -> u8 {
    i.clamp(0, 255) as u8
}

pub struct Decoder<'a> {
    data: &'a [u8],
    n: usize, // what the chunk length still allows
    pub frame: FrameHeader,
    mbw: usize,
    mbh: usize,
    img: Option<YCbCr>,
    segment_header: SegmentHeader,
    filter_header: FilterHeader,
    per_segment_level: [i8; 4],
    fp: Partition,
    op: Vec<Partition>,
    n_op: usize,
    quant: [Quant; 4],
    token_prob: [u8; 1056],
    use_skip_prob: bool,
    skip_prob: u8,
    filter_params: [[FilterParam; 2]; 4],
    per_mb_filter_params: Vec<FilterParam>,
    segment: usize,
    left_mb: Mb,
    up_mb: Vec<Mb>,
    nz_dc_mask: u32,
    nz_ac_mask: u32,
    use_pred_y16: bool,
    pred_y16: u8,
    pred_c8: u8,
    pred_y4: [[u8; 4]; 4],
    coeff: [i16; 400],
    ybr: [[u8; 32]; 26],
}

fn tp(i: usize, j: usize, k: usize, l: usize) -> usize {
    ((i * 8 + j) * 3 + k) * 11 + l
}

impl<'a> Decoder<'a> {
    /// d.Init(chunkData, chunkLen): `data` is what the file holds of the chunk.
    pub fn new(data: &'a [u8], chunk_len: usize) -> Self {
        Decoder {
            data,
            n: chunk_len,
            frame: FrameHeader {
                key_frame: false,
                first_partition_len: 0,
                width: 0,
                height: 0,
            },
            mbw: 0,
            mbh: 0,
            img: None,
            segment_header: SegmentHeader::default(),
            filter_header: FilterHeader::default(),
            per_segment_level: [0; 4],
            fp: Partition::default(),
            op: (0..8).map(|_| Partition::default()).collect(),
            n_op: 0,
            quant: [Quant::default(); 4],
            token_prob: [0; 1056],
            use_skip_prob: false,
            skip_prob: 0,
            filter_params: [[FilterParam::default(); 2]; 4],
            per_mb_filter_params: Vec::new(),
            segment: 0,
            left_mb: Mb::default(),
            up_mb: Vec::new(),
            nz_dc_mask: 0,
            nz_ac_mask: 0,
            use_pred_y16: false,
            pred_y16: 0,
            pred_c8: 0,
            pred_y4: [[0; 4]; 4],
            coeff: [0; 400],
            ybr: [[0; 32]; 26],
        }
    }

    /// limitReader.ReadFull.
    fn read_full(&mut self, len: usize) -> Result<&'a [u8], String> {
        if len > self.n {
            return Err("unexpected EOF".into());
        }
        if self.data.len() < len {
            let empty = self.data.is_empty();
            self.n -= self.data.len();
            self.data = &[];
            return Err(if empty { "EOF" } else { "unexpected EOF" }.into());
        }
        let (s, rest) = self.data.split_at(len);
        self.data = rest;
        self.n -= len;
        Ok(s)
    }

    pub fn decode_frame_header(&mut self) -> Result<(), String> {
        let b = self.read_full(3)?;
        self.frame.key_frame = b[0] & 1 == 0;
        self.frame.first_partition_len =
            (b[0] as u32) >> 5 | (b[1] as u32) << 3 | (b[2] as u32) << 11;
        if !self.frame.key_frame {
            return Ok(());
        }
        let b = self.read_full(7)?;
        if b[0] != 0x9d || b[1] != 0x01 || b[2] != 0x2a {
            return Err("vp8: invalid format".into());
        }
        self.frame.width = ((b[4] & 0x3f) as usize) << 8 | b[3] as usize;
        self.frame.height = ((b[6] & 0x3f) as usize) << 8 | b[5] as usize;
        self.mbw = (self.frame.width + 0x0f) >> 4;
        self.mbh = (self.frame.height + 0x0f) >> 4;
        self.segment_header = SegmentHeader {
            prob: [0xff; 3],
            ..Default::default()
        };
        self.token_prob = DEFAULT_TOKEN_PROB;
        self.segment = 0;
        Ok(())
    }

    fn ensure_img(&mut self) {
        let mut m = YCbCr::new(16 * self.mbw, 16 * self.mbh, Ratio::R420);
        m.w = self.frame.width;
        m.h = self.frame.height;
        self.img = Some(m);
        self.per_mb_filter_params = vec![FilterParam::default(); self.mbw * self.mbh];
        self.up_mb = vec![Mb::default(); self.mbw];
    }

    fn parse_segment_header(&mut self) {
        let fp = &mut self.fp;
        let sh = &mut self.segment_header;
        sh.use_segment = fp.read_bit(UNIFORM_PROB);
        if !sh.use_segment {
            sh.update_map = false;
            return;
        }
        sh.update_map = fp.read_bit(UNIFORM_PROB);
        if fp.read_bit(UNIFORM_PROB) {
            sh.relative_delta = !fp.read_bit(UNIFORM_PROB);
            for q in sh.quantizer.iter_mut() {
                *q = fp.read_optional_int(UNIFORM_PROB, 7) as i8;
            }
            for f in sh.filter_strength.iter_mut() {
                *f = fp.read_optional_int(UNIFORM_PROB, 6) as i8;
            }
        }
        if !sh.update_map {
            return;
        }
        for p in sh.prob.iter_mut() {
            *p = if fp.read_bit(UNIFORM_PROB) {
                fp.read_uint(UNIFORM_PROB, 8) as u8
            } else {
                0xff
            };
        }
    }

    fn parse_filter_header(&mut self) {
        let fp = &mut self.fp;
        let fh = &mut self.filter_header;
        fh.simple = fp.read_bit(UNIFORM_PROB);
        fh.level = fp.read_uint(UNIFORM_PROB, 6) as i8;
        fh.sharpness = fp.read_uint(UNIFORM_PROB, 3) as u8;
        fh.use_lf_delta = fp.read_bit(UNIFORM_PROB);
        if fh.use_lf_delta && fp.read_bit(UNIFORM_PROB) {
            for d in fh.ref_lf_delta.iter_mut() {
                *d = fp.read_optional_int(UNIFORM_PROB, 6) as i8;
            }
            for d in fh.mode_lf_delta.iter_mut() {
                *d = fp.read_optional_int(UNIFORM_PROB, 6) as i8;
            }
        }
        if fh.level == 0 {
            return;
        }
        if self.segment_header.use_segment {
            for i in 0..4 {
                let mut strength = self.segment_header.filter_strength[i];
                if self.segment_header.relative_delta {
                    strength = strength.wrapping_add(fh.level);
                }
                self.per_segment_level[i] = strength;
            }
        } else {
            self.per_segment_level[0] = fh.level;
        }
        self.compute_filter_params();
    }

    fn parse_other_partitions(&mut self) -> Result<(), String> {
        let mut part_lens = [0i64; 8];
        self.n_op = 1 << self.fp.read_uint(UNIFORM_PROB, 2);
        let n = 3 * (self.n_op - 1);
        part_lens[self.n_op - 1] = self.n as i64 - n as i64;
        if part_lens[self.n_op - 1] < 0 {
            return Err("unexpected EOF".into());
        }
        if n > 0 {
            let buf = self.read_full(n)?;
            for i in 0..self.n_op - 1 {
                let pl = buf[3 * i] as i64
                    | (buf[3 * i + 1] as i64) << 8
                    | (buf[3 * i + 2] as i64) << 16;
                if pl > part_lens[self.n_op - 1] {
                    return Err("unexpected EOF".into());
                }
                part_lens[i] = pl;
                part_lens[self.n_op - 1] -= pl;
            }
        }
        if 1 << 24 <= part_lens[self.n_op - 1] {
            return Err("vp8: too much data to decode".into());
        }
        let mut buf = self.read_full(self.n)?;
        for i in 0..self.n_op {
            let (part, rest) = buf.split_at(part_lens[i] as usize);
            self.op[i] = Partition::init(part.to_vec());
            buf = rest;
        }
        Ok(())
    }

    fn parse_quant(&mut self) {
        let fp = &mut self.fp;
        let base_q0 = fp.read_uint(UNIFORM_PROB, 7) as i32;
        let dqy1_dc = fp.read_optional_int(UNIFORM_PROB, 4);
        let dqy1_ac = 0;
        let dqy2_dc = fp.read_optional_int(UNIFORM_PROB, 4);
        let dqy2_ac = fp.read_optional_int(UNIFORM_PROB, 4);
        let dquv_dc = fp.read_optional_int(UNIFORM_PROB, 4);
        let dquv_ac = fp.read_optional_int(UNIFORM_PROB, 4);
        for i in 0..4 {
            let mut q = base_q0;
            if self.segment_header.use_segment {
                if self.segment_header.relative_delta {
                    q += self.segment_header.quantizer[i] as i32;
                } else {
                    q = self.segment_header.quantizer[i] as i32;
                }
            }
            let qt = &mut self.quant[i];
            qt.y1[0] = DEQUANT_DC[clip(q + dqy1_dc, 0, 127) as usize];
            qt.y1[1] = DEQUANT_AC[clip(q + dqy1_ac, 0, 127) as usize];
            qt.y2[0] = DEQUANT_DC[clip(q + dqy2_dc, 0, 127) as usize] * 2;
            qt.y2[1] = (DEQUANT_AC[clip(q + dqy2_ac, 0, 127) as usize] as u32 * 155 / 100) as u16;
            if qt.y2[1] < 8 {
                qt.y2[1] = 8;
            }
            qt.uv[0] = DEQUANT_DC[clip(q + dquv_dc, 0, 117) as usize];
            qt.uv[1] = DEQUANT_AC[clip(q + dquv_ac, 0, 127) as usize];
        }
    }

    fn parse_token_prob(&mut self) {
        for i in 0..4 {
            for j in 0..8 {
                for k in 0..3 {
                    for l in 0..11 {
                        let idx = tp(i, j, k, l);
                        if self.fp.read_bit(TOKEN_PROB_UPDATE_PROB[idx]) {
                            self.token_prob[idx] = self.fp.read_uint(UNIFORM_PROB, 8) as u8;
                        }
                    }
                }
            }
        }
    }

    fn parse_other_headers(&mut self) -> Result<(), String> {
        let first = self.read_full(self.frame.first_partition_len as usize)?;
        self.fp = Partition::init(first.to_vec());
        if self.frame.key_frame {
            self.fp.read_bit(UNIFORM_PROB);
            self.fp.read_bit(UNIFORM_PROB);
        }
        self.parse_segment_header();
        self.parse_filter_header();
        self.parse_other_partitions()?;
        self.parse_quant();
        if !self.frame.key_frame {
            return Err("vp8: Golden / AltRef frames are not implemented".into());
        }
        self.fp.read_bit(UNIFORM_PROB);
        self.parse_token_prob();
        self.use_skip_prob = self.fp.read_bit(UNIFORM_PROB);
        if self.use_skip_prob {
            self.skip_prob = self.fp.read_uint(UNIFORM_PROB, 8) as u8;
        }
        if self.fp.unexpected_eof {
            return Err("unexpected EOF".into());
        }
        Ok(())
    }

    pub fn decode_frame(mut self) -> Result<YCbCr, String> {
        self.ensure_img();
        self.parse_other_headers()?;
        for m in self.up_mb.iter_mut() {
            *m = Mb::default();
        }
        for mby in 0..self.mbh {
            self.left_mb = Mb::default();
            for mbx in 0..self.mbw {
                let skip = self.reconstruct(mbx, mby);
                let mut fs = self.filter_params[self.segment][btou(!self.use_pred_y16) as usize];
                fs.inner = fs.inner || !skip;
                self.per_mb_filter_params[self.mbw * mby + mbx] = fs;
            }
        }
        if self.fp.unexpected_eof {
            return Err("unexpected EOF".into());
        }
        for i in 0..self.n_op {
            if self.op[i].unexpected_eof {
                return Err("unexpected EOF".into());
            }
        }
        if self.filter_header.level != 0 {
            if self.filter_header.simple {
                self.simple_filter();
            } else {
                self.normal_filter();
            }
        }
        Ok(self.img.take().expect("made"))
    }

    // --- pred.go ------------------------------------------------------------

    fn parse_pred_mode_y16(&mut self, mbx: usize) {
        let fp = &mut self.fp;
        let p = if !fp.read_bit(156) {
            if !fp.read_bit(163) {
                PRED_DC
            } else {
                PRED_VE
            }
        } else if !fp.read_bit(128) {
            PRED_HE
        } else {
            PRED_TM
        };
        for i in 0..4 {
            self.up_mb[mbx].pred[i] = p;
            self.left_mb.pred[i] = p;
        }
        self.pred_y16 = p;
    }

    fn parse_pred_mode_c8(&mut self) {
        let fp = &mut self.fp;
        self.pred_c8 = if !fp.read_bit(142) {
            PRED_DC
        } else if !fp.read_bit(114) {
            PRED_VE
        } else if !fp.read_bit(183) {
            PRED_HE
        } else {
            PRED_TM
        };
    }

    fn parse_pred_mode_y4(&mut self, mbx: usize) {
        for j in 0..4 {
            let mut p = self.left_mb.pred[j];
            for i in 0..4 {
                let base = (self.up_mb[mbx].pred[i] as usize * 10 + p as usize) * 9;
                let prob = &PRED_PROB[base..base + 9];
                let fp = &mut self.fp;
                p = if !fp.read_bit(prob[0]) {
                    PRED_DC
                } else if !fp.read_bit(prob[1]) {
                    PRED_TM
                } else if !fp.read_bit(prob[2]) {
                    PRED_VE
                } else if !fp.read_bit(prob[3]) {
                    if !fp.read_bit(prob[4]) {
                        PRED_HE
                    } else if !fp.read_bit(prob[5]) {
                        PRED_RD
                    } else {
                        PRED_VR
                    }
                } else if !fp.read_bit(prob[6]) {
                    PRED_LD
                } else if !fp.read_bit(prob[7]) {
                    PRED_VL
                } else if !fp.read_bit(prob[8]) {
                    PRED_HD
                } else {
                    PRED_HU
                };
                self.pred_y4[j][i] = p;
                self.up_mb[mbx].pred[i] = p;
            }
            self.left_mb.pred[j] = p;
        }
    }

    // --- reconstruct.go -----------------------------------------------------

    fn prepare_ybr(&mut self, mbx: usize, mby: usize) {
        let img = self.img.as_ref().expect("made");
        let ybr = &mut self.ybr;
        if mbx == 0 {
            for row in ybr.iter_mut().take(17) {
                row[7] = 0x81;
            }
            for row in ybr.iter_mut().take(26).skip(17) {
                row[7] = 0x81;
                row[23] = 0x81;
            }
        } else {
            for row in ybr.iter_mut().take(17) {
                row[7] = row[7 + 16];
            }
            for row in ybr.iter_mut().take(26).skip(17) {
                row[7] = row[15];
                row[23] = row[31];
            }
        }
        if mby == 0 {
            for x in 7..28 {
                ybr[0][x] = 0x7f;
            }
            for x in 7..16 {
                ybr[17][x] = 0x7f;
            }
            for x in 23..32 {
                ybr[17][x] = 0x7f;
            }
        } else {
            let ys = img.y_stride;
            let cs = img.c_stride;
            for i in 0..16 {
                ybr[0][8 + i] = img.y[(16 * mby - 1) * ys + 16 * mbx + i];
            }
            for i in 0..8 {
                ybr[17][8 + i] = img.cb[(8 * mby - 1) * cs + 8 * mbx + i];
            }
            for i in 0..8 {
                ybr[17][24 + i] = img.cr[(8 * mby - 1) * cs + 8 * mbx + i];
            }
            for i in 16..20 {
                let src = if mbx == self.mbw - 1 { 15 } else { i };
                ybr[0][8 + i] = img.y[(16 * mby - 1) * ys + 16 * mbx + src];
            }
        }
        for y in [4, 8, 12] {
            for k in 24..28 {
                ybr[y][k] = ybr[0][k];
            }
        }
    }

    fn parse_residuals4(
        &mut self,
        r: &mut Partition,
        plane: usize,
        context: u8,
        quant: [u16; 2],
        skip_first: bool,
        coeff_base: usize,
    ) -> u8 {
        let prob = |b: usize, c: usize| tp(plane, b, c, 0);
        let mut n = if skip_first { 1 } else { 0 };
        let mut p = prob(BANDS[n], context as usize);
        if !r.read_bit(self.token_prob[p]) {
            return 0;
        }
        while n != 16 {
            n += 1;
            if !r.read_bit(self.token_prob[p + 1]) {
                p = prob(BANDS[n], 0);
                continue;
            }
            let tpb = |k: usize| self.token_prob[p + k];
            let v: u32;
            if !r.read_bit(tpb(2)) {
                v = 1;
                p = prob(BANDS[n], 1);
            } else {
                if !r.read_bit(tpb(3)) {
                    if !r.read_bit(tpb(4)) {
                        v = 2;
                    } else {
                        v = 3 + r.read_uint(tpb(5), 1);
                    }
                } else if !r.read_bit(tpb(6)) {
                    if !r.read_bit(tpb(7)) {
                        v = 5 + r.read_uint(159, 1);
                    } else {
                        v = 7 + 2 * r.read_uint(165, 1) + r.read_uint(145, 1);
                    }
                } else {
                    let b1 = r.read_uint(tpb(8), 1);
                    let b0 = r.read_uint(tpb(9 + b1 as usize), 1);
                    let cat = 2 * b1 + b0;
                    let tab = &CAT3456[cat as usize];
                    let mut vv = 0u32;
                    let mut i = 0;
                    while tab[i] != 0 {
                        vv *= 2;
                        vv += r.read_uint(tab[i], 1);
                        i += 1;
                    }
                    v = vv + 3 + (8 << cat);
                }
                p = prob(BANDS[n], 2);
            }
            let z = ZIGZAG[n - 1];
            let mut c = (v as i32).wrapping_mul(quant[btou(z > 0) as usize] as i32);
            if r.read_bit(UNIFORM_PROB) {
                c = c.wrapping_neg();
            }
            self.coeff[coeff_base + z] = c as i16;
            if n == 16 || !r.read_bit(self.token_prob[p]) {
                return 1;
            }
        }
        1
    }

    fn parse_residuals(&mut self, mbx: usize, mby: usize) -> bool {
        let pi = mby & (self.n_op - 1);
        let mut part = std::mem::take(&mut self.op[pi]);
        let mut plane = PLANE_Y1_SANS_Y2;
        let quant = self.quant[self.segment];
        if self.use_pred_y16 {
            let ctx = self.left_mb.nz_y16 + self.up_mb[mbx].nz_y16;
            let nz =
                self.parse_residuals4(&mut part, PLANE_Y2, ctx, quant.y2, false, WHT_COEFF_BASE);
            self.left_mb.nz_y16 = nz;
            self.up_mb[mbx].nz_y16 = nz;
            self.inverse_wht16();
            plane = PLANE_Y1_WITH_Y2;
        }
        let mut nz_dc = [0u8; 4];
        let mut nz_ac = [0u8; 4];
        let mut nz_dc_mask = 0u32;
        let mut nz_ac_mask = 0u32;
        let mut coeff_base = 0;
        let mut lnz = unpack(self.left_mb.nz_mask & 0x0f);
        let mut unz = unpack(self.up_mb[mbx].nz_mask & 0x0f);
        for y in 0..4 {
            let mut nz = lnz[y];
            for x in 0..4 {
                nz = self.parse_residuals4(
                    &mut part,
                    plane,
                    nz + unz[x],
                    quant.y1,
                    self.use_pred_y16,
                    coeff_base,
                );
                unz[x] = nz;
                nz_ac[x] = nz;
                nz_dc[x] = btou(self.coeff[coeff_base] != 0);
                coeff_base += 16;
            }
            lnz[y] = nz;
            nz_dc_mask |= pack(nz_dc, y as u32 * 4);
            nz_ac_mask |= pack(nz_ac, y as u32 * 4);
        }
        let mut lnz_mask = pack(lnz, 0);
        let mut unz_mask = pack(unz, 0);
        lnz = unpack(self.left_mb.nz_mask >> 4);
        unz = unpack(self.up_mb[mbx].nz_mask >> 4);
        for c in [0, 2] {
            for y in 0..2 {
                let mut nz = lnz[y + c];
                for x in 0..2 {
                    nz = self.parse_residuals4(
                        &mut part,
                        PLANE_UV,
                        nz + unz[x + c],
                        quant.uv,
                        false,
                        coeff_base,
                    );
                    unz[x + c] = nz;
                    nz_ac[y * 2 + x] = nz;
                    nz_dc[y * 2 + x] = btou(self.coeff[coeff_base] != 0);
                    coeff_base += 16;
                }
                lnz[y + c] = nz;
            }
            nz_dc_mask |= pack(nz_dc, 16 + c as u32 * 2);
            nz_ac_mask |= pack(nz_ac, 16 + c as u32 * 2);
        }
        lnz_mask |= pack(lnz, 4);
        unz_mask |= pack(unz, 4);
        self.left_mb.nz_mask = lnz_mask as u8;
        self.up_mb[mbx].nz_mask = unz_mask as u8;
        self.nz_dc_mask = nz_dc_mask;
        self.nz_ac_mask = nz_ac_mask;
        self.op[pi] = part;
        nz_dc_mask == 0 && nz_ac_mask == 0
    }

    fn reconstruct_macroblock(&mut self, mbx: usize, mby: usize) {
        if self.use_pred_y16 {
            let p = check_top_left_pred(mbx, mby, self.pred_y16);
            self.pred16(p, 1, 8);
            for j in 0..4 {
                for i in 0..4 {
                    let n = 4 * j + i;
                    let (y, x) = (4 * j + 1, 4 * i + 8);
                    let mask = 1u32 << n;
                    if self.nz_ac_mask & mask != 0 {
                        self.inverse_dct4(y, x, 16 * n);
                    } else if self.nz_dc_mask & mask != 0 {
                        self.inverse_dct4_dc_only(y, x, 16 * n);
                    }
                }
            }
        } else {
            for j in 0..4 {
                for i in 0..4 {
                    let n = 4 * j + i;
                    let (y, x) = (4 * j + 1, 4 * i + 8);
                    self.pred4(self.pred_y4[j][i], y, x);
                    let mask = 1u32 << n;
                    if self.nz_ac_mask & mask != 0 {
                        self.inverse_dct4(y, x, 16 * n);
                    } else if self.nz_dc_mask & mask != 0 {
                        self.inverse_dct4_dc_only(y, x, 16 * n);
                    }
                }
            }
        }
        let p = check_top_left_pred(mbx, mby, self.pred_c8);
        self.pred8(p, YBR_BY, YBR_BX);
        if self.nz_ac_mask & 0x0f0000 != 0 {
            self.inverse_dct8(YBR_BY, YBR_BX, B_COEFF_BASE);
        } else if self.nz_dc_mask & 0x0f0000 != 0 {
            self.inverse_dct8_dc_only(YBR_BY, YBR_BX, B_COEFF_BASE);
        }
        self.pred8(p, YBR_RY, YBR_RX);
        if self.nz_ac_mask & 0xf00000 != 0 {
            self.inverse_dct8(YBR_RY, YBR_RX, R_COEFF_BASE);
        } else if self.nz_dc_mask & 0xf00000 != 0 {
            self.inverse_dct8_dc_only(YBR_RY, YBR_RX, R_COEFF_BASE);
        }
    }

    fn reconstruct(&mut self, mbx: usize, mby: usize) -> bool {
        if self.segment_header.update_map {
            let pr = self.segment_header.prob;
            self.segment = if !self.fp.read_bit(pr[0]) {
                self.fp.read_uint(pr[1], 1) as usize
            } else {
                self.fp.read_uint(pr[2], 1) as usize + 2
            };
        }
        let mut skip = false;
        if self.use_skip_prob {
            skip = self.fp.read_bit(self.skip_prob);
        }
        self.coeff = [0; 400];
        self.prepare_ybr(mbx, mby);
        self.use_pred_y16 = self.fp.read_bit(145);
        if self.use_pred_y16 {
            self.parse_pred_mode_y16(mbx);
        } else {
            self.parse_pred_mode_y4(mbx);
        }
        self.parse_pred_mode_c8();
        if !skip {
            skip = self.parse_residuals(mbx, mby);
        } else {
            if self.use_pred_y16 {
                self.left_mb.nz_y16 = 0;
                self.up_mb[mbx].nz_y16 = 0;
            }
            self.left_mb.nz_mask = 0;
            self.up_mb[mbx].nz_mask = 0;
            self.nz_dc_mask = 0;
            self.nz_ac_mask = 0;
        }
        self.reconstruct_macroblock(mbx, mby);
        let img = self.img.as_mut().expect("made");
        let ys = img.y_stride;
        let cs = img.c_stride;
        let mut i = (mby * ys + mbx) * 16;
        for y in 0..16 {
            img.y[i..i + 16].copy_from_slice(&self.ybr[YBR_YY + y][YBR_YX..YBR_YX + 16]);
            i += ys;
        }
        let mut i = (mby * cs + mbx) * 8;
        for y in 0..8 {
            img.cb[i..i + 8].copy_from_slice(&self.ybr[YBR_BY + y][YBR_BX..YBR_BX + 8]);
            img.cr[i..i + 8].copy_from_slice(&self.ybr[YBR_RY + y][YBR_RX..YBR_RX + 8]);
            i += cs;
        }
        skip
    }

    // --- idct.go ------------------------------------------------------------

    fn inverse_dct4(&mut self, y: usize, x: usize, mut coeff_base: usize) {
        const C1: i32 = 85627;
        const C2: i32 = 35468;
        let mut m = [[0i32; 4]; 4];
        for row in m.iter_mut() {
            let k = |o: usize| self.coeff[coeff_base + o] as i32;
            let a = k(0) + k(8);
            let b = k(0) - k(8);
            let c = ((k(4) * C2) >> 16) - ((k(12) * C1) >> 16);
            let d = ((k(4) * C1) >> 16) + ((k(12) * C2) >> 16);
            *row = [a + d, b + c, b - c, a - d];
            coeff_base += 1;
        }
        for j in 0..4 {
            let dc = m[0][j] + 4;
            let a = dc + m[2][j];
            let b = dc - m[2][j];
            let c = ((m[1][j] * C2) >> 16) - ((m[3][j] * C1) >> 16);
            let d = ((m[1][j] * C1) >> 16) + ((m[3][j] * C2) >> 16);
            let row = &mut self.ybr[y + j];
            row[x] = clip8(row[x] as i32 + ((a + d) >> 3));
            row[x + 1] = clip8(row[x + 1] as i32 + ((b + c) >> 3));
            row[x + 2] = clip8(row[x + 2] as i32 + ((b - c) >> 3));
            row[x + 3] = clip8(row[x + 3] as i32 + ((a - d) >> 3));
        }
    }

    fn inverse_dct4_dc_only(&mut self, y: usize, x: usize, coeff_base: usize) {
        let dc = (self.coeff[coeff_base] as i32 + 4) >> 3;
        for j in 0..4 {
            for i in 0..4 {
                self.ybr[y + j][x + i] = clip8(self.ybr[y + j][x + i] as i32 + dc);
            }
        }
    }

    fn inverse_dct8(&mut self, y: usize, x: usize, cb: usize) {
        self.inverse_dct4(y, x, cb);
        self.inverse_dct4(y, x + 4, cb + 16);
        self.inverse_dct4(y + 4, x, cb + 32);
        self.inverse_dct4(y + 4, x + 4, cb + 48);
    }

    fn inverse_dct8_dc_only(&mut self, y: usize, x: usize, cb: usize) {
        self.inverse_dct4_dc_only(y, x, cb);
        self.inverse_dct4_dc_only(y, x + 4, cb + 16);
        self.inverse_dct4_dc_only(y + 4, x, cb + 32);
        self.inverse_dct4_dc_only(y + 4, x + 4, cb + 48);
    }

    fn inverse_wht16(&mut self) {
        let mut m = [0i32; 16];
        let k = |c: &[i16; 400], o: usize| c[384 + o] as i32;
        for i in 0..4 {
            let a0 = k(&self.coeff, i) + k(&self.coeff, 12 + i);
            let a1 = k(&self.coeff, 4 + i) + k(&self.coeff, 8 + i);
            let a2 = k(&self.coeff, 4 + i) - k(&self.coeff, 8 + i);
            let a3 = k(&self.coeff, i) - k(&self.coeff, 12 + i);
            m[i] = a0 + a1;
            m[8 + i] = a0 - a1;
            m[4 + i] = a3 + a2;
            m[12 + i] = a3 - a2;
        }
        let mut out = 0;
        for i in 0..4 {
            let dc = m[i * 4] + 3;
            let a0 = dc + m[3 + i * 4];
            let a1 = m[1 + i * 4] + m[2 + i * 4];
            let a2 = m[1 + i * 4] - m[2 + i * 4];
            let a3 = dc - m[3 + i * 4];
            self.coeff[out] = ((a0 + a1) >> 3) as i16;
            self.coeff[out + 16] = ((a3 + a2) >> 3) as i16;
            self.coeff[out + 32] = ((a0 - a1) >> 3) as i16;
            self.coeff[out + 48] = ((a3 - a2) >> 3) as i16;
            out += 64;
        }
    }

    // --- predfunc.go --------------------------------------------------------

    fn fill(&mut self, y: usize, x: usize, n: usize, v: u8) {
        for j in 0..n {
            for i in 0..n {
                self.ybr[y + j][x + i] = v;
            }
        }
    }

    fn pred_tm(&mut self, y: usize, x: usize, n: usize) {
        let delta0 = -(self.ybr[y - 1][x - 1] as i32);
        for j in 0..n {
            let delta1 = delta0 + self.ybr[y + j][x - 1] as i32;
            for i in 0..n {
                let delta2 = delta1 + self.ybr[y - 1][x + i] as i32;
                self.ybr[y + j][x + i] = clip(delta2, 0, 255) as u8;
            }
        }
    }

    fn pred_ve(&mut self, y: usize, x: usize, n: usize) {
        for j in 0..n {
            for i in 0..n {
                self.ybr[y + j][x + i] = self.ybr[y - 1][x + i];
            }
        }
    }

    fn pred_he(&mut self, y: usize, x: usize, n: usize) {
        for j in 0..n {
            for i in 0..n {
                self.ybr[y + j][x + i] = self.ybr[y + j][x - 1];
            }
        }
    }

    fn sum_top(&self, y: usize, x: usize, n: usize) -> u32 {
        (0..n).map(|i| self.ybr[y - 1][x + i] as u32).sum()
    }

    fn sum_left(&self, y: usize, x: usize, n: usize) -> u32 {
        (0..n).map(|j| self.ybr[y + j][x - 1] as u32).sum()
    }

    /// predFunc8 and predFunc16 (Go's DCTop sums the left column: there is
    /// no top row, and the reverse for DCLeft).
    fn pred_big(&mut self, p: u8, y: usize, x: usize, n: usize) {
        let shift = if n == 8 { 3 } else { 4 };
        match p {
            PRED_DC => {
                let sum = n as u32 + self.sum_top(y, x, n) + self.sum_left(y, x, n);
                let avg = (sum >> (shift + 1)) as u8;
                self.fill(y, x, n, avg);
            }
            PRED_TM => self.pred_tm(y, x, n),
            PRED_VE => self.pred_ve(y, x, n),
            PRED_HE => self.pred_he(y, x, n),
            PRED_DC_TOP => {
                let sum = (n as u32 / 2) + self.sum_left(y, x, n);
                self.fill(y, x, n, (sum >> shift) as u8);
            }
            PRED_DC_LEFT => {
                let sum = (n as u32 / 2) + self.sum_top(y, x, n);
                self.fill(y, x, n, (sum >> shift) as u8);
            }
            _ => self.fill(y, x, n, 0x80),
        }
    }

    fn pred8(&mut self, p: u8, y: usize, x: usize) {
        self.pred_big(p, y, x, 8);
    }

    fn pred16(&mut self, p: u8, y: usize, x: usize) {
        self.pred_big(p, y, x, 16);
    }

    fn pred4(&mut self, p: u8, y: usize, x: usize) {
        let t = |z: &Self, dx: isize| z.ybr[y - 1][(x as isize + dx) as usize] as i32;
        let l = |z: &Self, dy: usize| z.ybr[y + dy][x - 1] as i32;
        let avg3 = |a: i32, b: i32, c: i32| ((a + 2 * b + c + 2) / 4) as u8;
        let avg2 = |a: i32, b: i32| ((a + b + 1) / 2) as u8;
        let mut out = [[0u8; 4]; 4];
        match p {
            PRED_DC => {
                let sum = 4 + self.sum_top(y, x, 4) + self.sum_left(y, x, 4);
                out = [[(sum / 8) as u8; 4]; 4];
            }
            PRED_TM => {
                self.pred_tm(y, x, 4);
                return;
            }
            PRED_VE => {
                let (a, b, c, d, e, f) = (
                    t(self, -1),
                    t(self, 0),
                    t(self, 1),
                    t(self, 2),
                    t(self, 3),
                    t(self, 4),
                );
                let row = [avg3(a, b, c), avg3(b, c, d), avg3(c, d, e), avg3(d, e, f)];
                out = [row; 4];
            }
            PRED_HE => {
                let (s, r, q, pp, a) =
                    (l(self, 3), l(self, 2), l(self, 1), l(self, 0), t(self, -1));
                out[0] = [avg3(a, pp, q); 4];
                out[1] = [avg3(r, q, pp); 4];
                out[2] = [avg3(s, r, q); 4];
                out[3] = [avg3(s, s, r); 4];
            }
            PRED_RD => {
                let (s, r, q, pp) = (l(self, 3), l(self, 2), l(self, 1), l(self, 0));
                let (a, b, c, d, e) = (t(self, -1), t(self, 0), t(self, 1), t(self, 2), t(self, 3));
                let srq = avg3(s, r, q);
                let rqp = avg3(r, q, pp);
                let qpa = avg3(q, pp, a);
                let pab = avg3(pp, a, b);
                let abc = avg3(a, b, c);
                let bcd = avg3(b, c, d);
                let cde = avg3(c, d, e);
                out = [
                    [pab, abc, bcd, cde],
                    [qpa, pab, abc, bcd],
                    [rqp, qpa, pab, abc],
                    [srq, rqp, qpa, pab],
                ];
            }
            PRED_VR => {
                let (r, q, pp) = (l(self, 2), l(self, 1), l(self, 0));
                let (a, b, c, d, e) = (t(self, -1), t(self, 0), t(self, 1), t(self, 2), t(self, 3));
                let ab = avg2(a, b);
                let bc = avg2(b, c);
                let cd = avg2(c, d);
                let de = avg2(d, e);
                let rqp = avg3(r, q, pp);
                let qpa = avg3(q, pp, a);
                let pab = avg3(pp, a, b);
                let abc = avg3(a, b, c);
                let bcd = avg3(b, c, d);
                let cde = avg3(c, d, e);
                out = [
                    [ab, bc, cd, de],
                    [pab, abc, bcd, cde],
                    [qpa, ab, bc, cd],
                    [rqp, pab, abc, bcd],
                ];
            }
            PRED_LD => {
                let v: Vec<i32> = (0..8).map(|i| t(self, i)).collect();
                let (a, b, c, d, e, f, g, h) = (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
                let abc = avg3(a, b, c);
                let bcd = avg3(b, c, d);
                let cde = avg3(c, d, e);
                let def = avg3(d, e, f);
                let efg = avg3(e, f, g);
                let fgh = avg3(f, g, h);
                let ghh = avg3(g, h, h);
                out = [
                    [abc, bcd, cde, def],
                    [bcd, cde, def, efg],
                    [cde, def, efg, fgh],
                    [def, efg, fgh, ghh],
                ];
            }
            PRED_VL => {
                let v: Vec<i32> = (0..8).map(|i| t(self, i)).collect();
                let (a, b, c, d, e, f, g, h) = (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
                let ab = avg2(a, b);
                let bc = avg2(b, c);
                let cd = avg2(c, d);
                let de = avg2(d, e);
                let abc = avg3(a, b, c);
                let bcd = avg3(b, c, d);
                let cde = avg3(c, d, e);
                let def = avg3(d, e, f);
                let efg = avg3(e, f, g);
                let fgh = avg3(f, g, h);
                out = [
                    [ab, bc, cd, de],
                    [abc, bcd, cde, def],
                    [bc, cd, de, efg],
                    [bcd, cde, def, fgh],
                ];
            }
            PRED_HD => {
                let (s, r, q, pp) = (l(self, 3), l(self, 2), l(self, 1), l(self, 0));
                let (a, b, c, d) = (t(self, -1), t(self, 0), t(self, 1), t(self, 2));
                let sr = avg2(s, r);
                let rq = avg2(r, q);
                let qp = avg2(q, pp);
                let pa = avg2(pp, a);
                let srq = avg3(s, r, q);
                let rqp = avg3(r, q, pp);
                let qpa = avg3(q, pp, a);
                let pab = avg3(pp, a, b);
                let abc = avg3(a, b, c);
                let bcd = avg3(b, c, d);
                out = [
                    [pa, pab, abc, bcd],
                    [qp, qpa, pa, pab],
                    [rq, rqp, qp, qpa],
                    [sr, srq, rq, rqp],
                ];
            }
            _ => {
                // PRED_HU
                let (s, r, q, pp) = (l(self, 3), l(self, 2), l(self, 1), l(self, 0));
                let pq = avg2(pp, q);
                let qr = avg2(q, r);
                let rs = avg2(r, s);
                let pqr = avg3(pp, q, r);
                let qrs = avg3(q, r, s);
                let rss = avg3(r, s, s);
                let sss = s as u8;
                out = [
                    [pq, pqr, qr, qrs],
                    [qr, qrs, rs, rss],
                    [rs, rss, sss, sss],
                    [sss, sss, sss, sss],
                ];
            }
        }
        for (j, row) in out.iter().enumerate() {
            self.ybr[y + j][x..x + 4].copy_from_slice(row);
        }
    }

    // --- filter.go ----------------------------------------------------------

    fn compute_filter_params(&mut self) {
        let fh = &self.filter_header;
        for i in 0..4 {
            let mut base_level = fh.level;
            if self.segment_header.use_segment {
                base_level = self.segment_header.filter_strength[i];
                if self.segment_header.relative_delta {
                    base_level = base_level.wrapping_add(fh.level);
                }
            }
            for j in 0..2 {
                let p = &mut self.filter_params[i][j];
                p.inner = j != 0;
                let mut level = base_level;
                if fh.use_lf_delta {
                    level = level.wrapping_add(fh.ref_lf_delta[0]);
                    if j != 0 {
                        level = level.wrapping_add(fh.mode_lf_delta[0]);
                    }
                }
                if level <= 0 {
                    p.level = 0;
                    continue;
                }
                if level > 63 {
                    level = 63;
                }
                let mut ilevel = level;
                if fh.sharpness > 0 {
                    if fh.sharpness > 4 {
                        ilevel >>= 2;
                    } else {
                        ilevel >>= 1;
                    }
                    let x = (9 - fh.sharpness as i32) as i8;
                    if ilevel > x {
                        ilevel = x;
                    }
                }
                if ilevel < 1 {
                    ilevel = 1;
                }
                p.ilevel = ilevel as u8;
                p.level = (2 * level as i32 + ilevel as i32) as u8;
                p.hlevel = if self.frame.key_frame {
                    if level < 15 {
                        0
                    } else if level < 40 {
                        1
                    } else {
                        2
                    }
                } else if level < 15 {
                    0
                } else if level < 20 {
                    1
                } else if level < 40 {
                    2
                } else {
                    3
                };
            }
        }
    }

    fn simple_filter(&mut self) {
        let img = self.img.as_mut().expect("made");
        let ys = img.y_stride;
        for mby in 0..self.mbh {
            for mbx in 0..self.mbw {
                let f = self.per_mb_filter_params[self.mbw * mby + mbx];
                if f.level == 0 {
                    continue;
                }
                let l = f.level as i32;
                let yi = (mby * ys + mbx) * 16;
                if mbx > 0 {
                    filter2(&mut img.y, l + 4, yi, ys, 1);
                }
                if f.inner {
                    for k in [4, 8, 12] {
                        filter2(&mut img.y, l, yi + k, ys, 1);
                    }
                }
                if mby > 0 {
                    filter2(&mut img.y, l + 4, yi, 1, ys);
                }
                if f.inner {
                    for k in [4, 8, 12] {
                        filter2(&mut img.y, l, yi + ys * k, 1, ys);
                    }
                }
            }
        }
    }

    fn normal_filter(&mut self) {
        let img = self.img.as_mut().expect("made");
        let (ys, cs) = (img.y_stride, img.c_stride);
        for mby in 0..self.mbh {
            for mbx in 0..self.mbw {
                let f = self.per_mb_filter_params[self.mbw * mby + mbx];
                if f.level == 0 {
                    continue;
                }
                let (l, il, hl) = (f.level as i32, f.ilevel as i32, f.hlevel as i32);
                let yi = (mby * ys + mbx) * 16;
                let ci = (mby * cs + mbx) * 8;
                if mbx > 0 {
                    filter246(&mut img.y, 16, l + 4, il, hl, yi, ys, 1, false);
                    filter246(&mut img.cb, 8, l + 4, il, hl, ci, cs, 1, false);
                    filter246(&mut img.cr, 8, l + 4, il, hl, ci, cs, 1, false);
                }
                if f.inner {
                    for k in [4, 8, 12] {
                        filter246(&mut img.y, 16, l, il, hl, yi + k, ys, 1, true);
                    }
                    filter246(&mut img.cb, 8, l, il, hl, ci + 4, cs, 1, true);
                    filter246(&mut img.cr, 8, l, il, hl, ci + 4, cs, 1, true);
                }
                if mby > 0 {
                    filter246(&mut img.y, 16, l + 4, il, hl, yi, 1, ys, false);
                    filter246(&mut img.cb, 8, l + 4, il, hl, ci, 1, cs, false);
                    filter246(&mut img.cr, 8, l + 4, il, hl, ci, 1, cs, false);
                }
                if f.inner {
                    for k in [4, 8, 12] {
                        filter246(&mut img.y, 16, l, il, hl, yi + ys * k, 1, ys, true);
                    }
                    filter246(&mut img.cb, 8, l, il, hl, ci + cs * 4, 1, cs, true);
                    filter246(&mut img.cr, 8, l, il, hl, ci + cs * 4, 1, cs, true);
                }
            }
        }
    }
}

fn check_top_left_pred(mbx: usize, mby: usize, p: u8) -> u8 {
    if p != PRED_DC {
        return p;
    }
    if mbx == 0 {
        if mby == 0 {
            return PRED_DC_TOP_LEFT;
        }
        return PRED_DC_LEFT;
    }
    if mby == 0 {
        return PRED_DC_TOP;
    }
    PRED_DC
}

fn clamp15(x: i32) -> i32 {
    x.clamp(-16, 15)
}

fn clamp127(x: i32) -> i32 {
    x.clamp(-128, 127)
}

fn clamp255(x: i32) -> u8 {
    x.clamp(0, 255) as u8
}

fn filter2(pix: &mut [u8], level: i32, mut index: usize, i_step: usize, j_step: usize) {
    for _ in 0..16 {
        let p1 = pix[index - 2 * j_step] as i32;
        let p0 = pix[index - j_step] as i32;
        let q0 = pix[index] as i32;
        let q1 = pix[index + j_step] as i32;
        if ((p0 - q0).abs() << 1) + ((p1 - q1).abs() >> 1) <= level {
            let a = 3 * (q0 - p0) + clamp127(p1 - q1);
            let a1 = clamp15((a + 4) >> 3);
            let a2 = clamp15((a + 3) >> 3);
            pix[index - j_step] = clamp255(p0 + a2);
            pix[index] = clamp255(q0 - a1);
        }
        index += i_step;
    }
}

#[allow(clippy::too_many_arguments)]
fn filter246(
    pix: &mut [u8],
    n: usize,
    level: i32,
    ilevel: i32,
    hlevel: i32,
    mut index: usize,
    i_step: usize,
    j_step: usize,
    four_not_six: bool,
) {
    for _ in 0..n {
        let at = |k: isize| pix[(index as isize + k * j_step as isize) as usize] as i32;
        let (p3, p2, p1, p0, q0, q1, q2, q3) =
            (at(-4), at(-3), at(-2), at(-1), at(0), at(1), at(2), at(3));
        let skip = ((p0 - q0).abs() << 1) + ((p1 - q1).abs() >> 1) > level
            || (p3 - p2).abs() > ilevel
            || (p2 - p1).abs() > ilevel
            || (p1 - p0).abs() > ilevel
            || (q1 - q0).abs() > ilevel
            || (q2 - q1).abs() > ilevel
            || (q3 - q2).abs() > ilevel;
        if !skip {
            let js = j_step;
            if (p1 - p0).abs() > hlevel || (q1 - q0).abs() > hlevel {
                let a = 3 * (q0 - p0) + clamp127(p1 - q1);
                let a1 = clamp15((a + 4) >> 3);
                let a2 = clamp15((a + 3) >> 3);
                pix[index - js] = clamp255(p0 + a2);
                pix[index] = clamp255(q0 - a1);
            } else if four_not_six {
                let a = 3 * (q0 - p0);
                let a1 = clamp15((a + 4) >> 3);
                let a2 = clamp15((a + 3) >> 3);
                let a3 = (a1 + 1) >> 1;
                pix[index - 2 * js] = clamp255(p1 + a3);
                pix[index - js] = clamp255(p0 + a2);
                pix[index] = clamp255(q0 - a1);
                pix[index + js] = clamp255(q1 - a3);
            } else {
                let a = clamp127(3 * (q0 - p0) + clamp127(p1 - q1));
                let a1 = (27 * a + 63) >> 7;
                let a2 = (18 * a + 63) >> 7;
                let a3 = (9 * a + 63) >> 7;
                pix[index - 3 * js] = clamp255(p2 + a3);
                pix[index - 2 * js] = clamp255(p1 + a2);
                pix[index - js] = clamp255(p0 + a1);
                pix[index] = clamp255(q0 - a1);
                pix[index + js] = clamp255(q1 - a2);
                pix[index + 2 * js] = clamp255(q2 - a3);
            }
        }
        index += i_step;
    }
}
