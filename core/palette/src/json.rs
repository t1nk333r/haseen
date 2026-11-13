// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause, the licence
// in core/palette/LICENSE-GO).
//! The little JSON the palette needs: reading a cache entry, writing one, and
//! Go's `%q` for the --json line and colors.toml. Hand-written, as the
//! sidecar's is (plan 167): no dependency for three small jobs.

pub enum Value {
    Null,
    Bool(bool),
    /// The number's text, so an integer field can refuse "3.0" as Go does.
    Number(String),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

/// Parses one JSON value with nothing after it but white space.
pub fn parse(data: &[u8]) -> Option<Value> {
    let mut p = Parser {
        s: data,
        i: 0,
        depth: 0,
    };
    let v = p.value()?;
    p.ws();
    (p.i == data.len()).then_some(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
    depth: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }

    fn eat(&mut self, lit: &[u8]) -> bool {
        if self.s[self.i..].starts_with(lit) {
            self.i += lit.len();
            true
        } else {
            false
        }
    }

    fn value(&mut self) -> Option<Value> {
        self.ws();
        let c = *self.s.get(self.i)?;
        match c {
            b'n' => self.eat(b"null").then_some(Value::Null),
            b't' => self.eat(b"true").then_some(Value::Bool(true)),
            b'f' => self.eat(b"false").then_some(Value::Bool(false)),
            b'"' => self.string().map(Value::String),
            b'[' | b'{' => {
                self.depth += 1;
                if self.depth > 100 {
                    return None;
                }
                let v = if c == b'[' {
                    self.array()
                } else {
                    self.object()
                };
                self.depth -= 1;
                v
            }
            b'-' | b'0'..=b'9' => self.number(),
            _ => None,
        }
    }

    fn number(&mut self) -> Option<Value> {
        let start = self.i;
        self.eat(b"-");
        let digits = |p: &mut Self| {
            let s = p.i;
            while p.i < p.s.len() && p.s[p.i].is_ascii_digit() {
                p.i += 1;
            }
            p.i > s
        };
        if self.eat(b"0") {
        } else if !digits(self) {
            return None;
        }
        if self.eat(b".") && !digits(self) {
            return None;
        }
        if self.i < self.s.len() && matches!(self.s[self.i], b'e' | b'E') {
            self.i += 1;
            if !self.eat(b"+") {
                self.eat(b"-");
            }
            if !digits(self) {
                return None;
            }
        }
        Some(Value::Number(
            String::from_utf8_lossy(&self.s[start..self.i]).into_owned(),
        ))
    }

    fn hex4(&mut self) -> Option<u32> {
        let h = self.s.get(self.i..self.i + 4)?;
        let v = u32::from_str_radix(std::str::from_utf8(h).ok()?, 16).ok()?;
        self.i += 4;
        Some(v)
    }

    fn string(&mut self) -> Option<String> {
        self.i += 1;
        let mut out: Vec<u8> = Vec::new();
        loop {
            let c = *self.s.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => return Some(String::from_utf8_lossy(&out).into_owned()),
                b'\\' => {
                    let e = *self.s.get(self.i)?;
                    self.i += 1;
                    let ch = match e {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let mut v = self.hex4()?;
                            if (0xD800..0xDC00).contains(&v) && self.s[self.i..].starts_with(b"\\u")
                            {
                                let save = self.i;
                                self.i += 2;
                                let lo = self.hex4()?;
                                if (0xDC00..0xE000).contains(&lo) {
                                    v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00);
                                } else {
                                    self.i = save;
                                }
                            }
                            char::from_u32(v).unwrap_or('\u{FFFD}')
                        }
                        _ => return None,
                    };
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                0..=0x1F => return None,
                _ => out.push(c),
            }
        }
    }

    fn array(&mut self) -> Option<Value> {
        self.i += 1;
        let mut items = Vec::new();
        self.ws();
        if self.eat(b"]") {
            return Some(Value::Array(items));
        }
        loop {
            items.push(self.value()?);
            self.ws();
            if self.eat(b"]") {
                return Some(Value::Array(items));
            }
            if !self.eat(b",") {
                return None;
            }
        }
    }

    fn object(&mut self) -> Option<Value> {
        self.i += 1;
        let mut fields = Vec::new();
        self.ws();
        if self.eat(b"}") {
            return Some(Value::Object(fields));
        }
        loop {
            self.ws();
            if self.s.get(self.i) != Some(&b'"') {
                return None;
            }
            let key = self.string()?;
            self.ws();
            if !self.eat(b":") {
                return None;
            }
            fields.push((key, self.value()?));
            self.ws();
            if self.eat(b"}") {
                return Some(Value::Object(fields));
            }
            if !self.eat(b",") {
                return None;
            }
        }
    }
}

/// A JSON string as Go's encoding/json writes it (HTML characters escaped).
pub fn quote(s: &str) -> String {
    let mut out = String::from("\"");
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '<' | '>' | '&' | '\u{2028}' | '\u{2029}' => {
                out.push_str(&format!("\\u{:04x}", ch as u32))
            }
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Go's `%q` (strconv.Quote) for the strings this program prints: seeds,
/// mode names and hex colours, which are printable ASCII. Control
/// characters and DEL are escaped as Go escapes them; other characters are
/// written as they are, where Go would also escape the few non-ASCII
/// characters it does not consider printable (only a mode name the user
/// typed can hold one, in an error message).
pub fn go_quote(s: &str) -> String {
    let mut out = String::from("\"");
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{7}' => out.push_str("\\a"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{b}' => out.push_str("\\v"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// go_quote for bytes that may not be UTF-8: Go writes each invalid byte
/// as \xHH.
pub fn go_quote_bytes(b: &[u8]) -> String {
    let mut out = String::from("\"");
    for chunk in b.utf8_chunks() {
        let valid = go_quote(chunk.valid());
        out.push_str(&valid[1..valid.len() - 1]);
        for byte in chunk.invalid() {
            out.push_str(&format!("\\x{byte:02x}"));
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_cache_entry() {
        let raw = br##"{"version":3,"seed":"ab","mode":"normal","light":false,"palette":["#000000","\u0041"]}"##;
        let Some(Value::Object(f)) = parse(raw) else {
            panic!()
        };
        assert_eq!(f.len(), 5);
        match &f[4].1 {
            Value::Array(a) => match &a[1] {
                Value::String(s) => assert_eq!(s, "A"),
                _ => panic!(),
            },
            _ => panic!(),
        }
        assert!(parse(b"{\"a\":1,}").is_none());
        assert!(parse(b"{} x").is_none());
        assert!(parse(b"[1.]").is_none());
    }

    #[test]
    fn quotes_like_go() {
        assert_eq!(
            quote("a<b>&\"\\\n"),
            "\"a\\u003cb\\u003e\\u0026\\\"\\\\\\n\""
        );
        assert_eq!(go_quote("#a0b1c2"), "\"#a0b1c2\"");
        assert_eq!(go_quote("x\u{1}\u{7f}\"y"), "\"x\\x01\\x7f\\\"y\"");
        assert_eq!(go_quote_bytes(b"GIF8\xb7a"), "\"GIF8\\xb7a\"");
    }
}
