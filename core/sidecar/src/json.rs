//! JSON as Go's encoding/json writes and reads it, which is the wire format the
//! shell, `haseen sidecar status` and the tests were written against (plan
//! 167). The encoder prints numbers and strings the way Go does; the parser is
//! strict JSON with Go's error text for the cases the border wipe reports.

use std::fmt::Write as _;

/// One parsed JSON value. Numbers keep their source text: Go decides per
/// target type whether `1.0` is acceptable (it is for a float, not an int).
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(String),
    String(String),
    Array(Vec<Value>),
    /// Keys in source order, repeats kept: Go lets the last one win.
    Object(Vec<(String, Value)>),
}

impl Value {
    /// The kind Go names in "cannot unmarshal X into ...".
    pub fn kind(&self) -> &'static str {
        match self {
            Value::Null => "null",
            Value::Bool(_) => "bool",
            Value::Number(_) => "number",
            Value::String(_) => "string",
            Value::Array(_) => "array",
            Value::Object(_) => "object",
        }
    }

    /// The last value for `key` in an object (Go's repeated-key rule).
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(fields) => fields.iter().rev().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// The number as Go's `float64` reads it into an `any`; None when Go would
    /// refuse it (out of range).
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(text) => text.parse::<f64>().ok().filter(|v| v.is_finite()),
            _ => None,
        }
    }
}

// --- the encoder ---------------------------------------------------------------

/// Go's float text: the shortest form that reads back, with no fraction for a
/// whole number, and exponent form outside 1e-6 <= |x| < 1e21 with the
/// exponent's sign always written and no leading zero (`7.6e-7`, `1e+21`).
/// Returns false for NaN and infinity, which Go refuses to encode.
pub fn write_f64(out: &mut Vec<u8>, v: f64) -> bool {
    if !v.is_finite() {
        return false;
    }
    let abs = v.abs();
    let mut text = String::new();
    if abs != 0.0 && !(1e-6..1e21).contains(&abs) {
        let _ = write!(text, "{v:e}");
        if let Some(e) = text.find('e') {
            if text.as_bytes().get(e + 1) != Some(&b'-') {
                text.insert(e + 1, '+');
            }
        }
    } else {
        let _ = write!(text, "{v}");
    }
    out.extend_from_slice(text.as_bytes());
    true
}

const HEX: &[u8; 16] = b"0123456789abcdef";

/// A JSON string as Go writes it with HTML escaping on (json.Encoder's
/// default): `<`, `>`, `&`, U+2028 and U+2029 escaped, control characters as
/// `\b \f \n \r \t` or `\u00XX`.
pub fn write_str(out: &mut Vec<u8>, s: &str) {
    out.push(b'"');
    let bytes = s.as_bytes();
    let mut start = 0;
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        let escape: Option<&[u8]> = match b {
            b'"' => Some(b"\\\""),
            b'\\' => Some(b"\\\\"),
            0x08 => Some(b"\\b"),
            0x0c => Some(b"\\f"),
            b'\n' => Some(b"\\n"),
            b'\r' => Some(b"\\r"),
            b'\t' => Some(b"\\t"),
            _ => None,
        };
        if let Some(e) = escape {
            out.extend_from_slice(&bytes[start..i]);
            out.extend_from_slice(e);
            i += 1;
            start = i;
            continue;
        }
        if b < 0x20 || b == b'<' || b == b'>' || b == b'&' {
            out.extend_from_slice(&bytes[start..i]);
            out.extend_from_slice(b"\\u00");
            out.push(HEX[(b >> 4) as usize]);
            out.push(HEX[(b & 0xf) as usize]);
            i += 1;
            start = i;
            continue;
        }
        // U+2028 and U+2029 are E2 80 A8 and E2 80 A9.
        if b == 0xe2
            && bytes.get(i + 1) == Some(&0x80)
            && matches!(bytes.get(i + 2), Some(0xa8 | 0xa9))
        {
            out.extend_from_slice(&bytes[start..i]);
            out.extend_from_slice(if bytes[i + 2] == 0xa8 {
                b"\\u2028"
            } else {
                b"\\u2029"
            });
            i += 3;
            start = i;
            continue;
        }
        i += 1;
    }
    out.extend_from_slice(&bytes[start..]);
    out.push(b'"');
}

/// Bytes from a file as Go turns them into a JSON string: each byte that is not
/// part of valid UTF-8 becomes one U+FFFD. (`String::from_utf8_lossy` writes
/// one U+FFFD for a whole truncated sequence.)
pub fn go_lossy(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len());
    let mut rest = bytes;
    loop {
        match std::str::from_utf8(rest) {
            Ok(s) => {
                out.push_str(s);
                return out;
            }
            Err(e) => {
                let good = e.valid_up_to();
                // from_utf8 just said this prefix is valid.
                out.push_str(std::str::from_utf8(&rest[..good]).unwrap_or_default());
                let bad = e.error_len().unwrap_or(rest.len() - good);
                for _ in 0..bad {
                    out.push('\u{fffd}');
                }
                rest = &rest[good + bad..];
            }
        }
    }
}

/// Writes one object's fields in order, commas included.
pub struct Obj<'a> {
    out: &'a mut Vec<u8>,
    first: bool,
    /// False once a float could not be encoded: Go's encoder fails the whole
    /// value then.
    pub ok: bool,
}

impl<'a> Obj<'a> {
    pub fn new(out: &'a mut Vec<u8>) -> Self {
        out.push(b'{');
        Obj {
            out,
            first: true,
            ok: true,
        }
    }

    pub fn key(&mut self, name: &str) -> &mut Vec<u8> {
        if !self.first {
            self.out.push(b',');
        }
        self.first = false;
        write_str(self.out, name);
        self.out.push(b':');
        self.out
    }

    pub fn str(&mut self, name: &str, v: &str) -> &mut Self {
        let out = self.key(name);
        write_str(out, v);
        self
    }

    pub fn int(&mut self, name: &str, v: i64) -> &mut Self {
        let out = self.key(name);
        let _ = write!(Buf(out), "{v}");
        self
    }

    pub fn uint(&mut self, name: &str, v: u64) -> &mut Self {
        let out = self.key(name);
        let _ = write!(Buf(out), "{v}");
        self
    }

    pub fn float(&mut self, name: &str, v: f64) -> &mut Self {
        let out = self.key(name);
        if !write_f64(out, v) {
            self.ok = false;
        }
        self
    }

    pub fn bool(&mut self, name: &str, v: bool) -> &mut Self {
        let out = self.key(name);
        out.extend_from_slice(if v { b"true" } else { b"false" });
        self
    }

    pub fn null(&mut self, name: &str) -> &mut Self {
        self.key(name).extend_from_slice(b"null");
        self
    }

    pub fn strs(&mut self, name: &str, list: &[String]) -> &mut Self {
        let out = self.key(name);
        write_str_list(out, list);
        self
    }

    /// A nested value written by `f`, which returns false when it could not be
    /// encoded.
    pub fn raw(&mut self, name: &str, f: impl FnOnce(&mut Vec<u8>) -> bool) -> &mut Self {
        let out = self.key(name);
        if !f(out) {
            self.ok = false;
        }
        self
    }

    pub fn end(&mut self) -> bool {
        self.out.push(b'}');
        self.ok
    }
}

pub fn write_str_list(out: &mut Vec<u8>, list: &[String]) {
    out.push(b'[');
    for (i, s) in list.iter().enumerate() {
        if i > 0 {
            out.push(b',');
        }
        write_str(out, s);
    }
    out.push(b']');
}

struct Buf<'a>(&'a mut Vec<u8>);

impl std::fmt::Write for Buf<'_> {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        self.0.extend_from_slice(s.as_bytes());
        Ok(())
    }
}

// --- the parser ----------------------------------------------------------------

/// Parses one JSON text. The error text is Go's for the cases a reason can
/// carry ("unexpected end of JSON input", "invalid character 'x' looking for
/// beginning of value").
pub fn parse(input: &[u8]) -> Result<Value, String> {
    let mut p = Parser {
        s: input,
        i: 0,
        depth: 0,
    };
    p.ws();
    let v = p.value()?;
    p.ws();
    if p.i < p.s.len() {
        return Err(format!(
            "invalid character {} after top-level value",
            quote_char(p.s[p.i])
        ));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
    depth: usize,
}

const EOF: &str = "unexpected end of JSON input";

/// How deep arrays and objects may nest.
pub const MAX_DEPTH: usize = 100;

fn quote_char(c: u8) -> String {
    match c {
        b'\'' => "'\\''".to_string(),
        b'"' => "'\"'".to_string(),
        0x20..=0x7e => format!("'{}'", c as char),
        _ => format!("'\\x{c:02x}'"),
    }
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }

    fn peek(&self) -> Result<u8, String> {
        self.s.get(self.i).copied().ok_or_else(|| EOF.to_string())
    }

    fn value(&mut self) -> Result<Value, String> {
        let c = self.peek()?;
        match c {
            b'{' => self.object(),
            b'[' => self.array(),
            b'"' => self.string().map(Value::String),
            b't' => self.literal(b"true", Value::Bool(true)),
            b'f' => self.literal(b"false", Value::Bool(false)),
            b'n' => self.literal(b"null", Value::Null),
            b'-' | b'0'..=b'9' => self.number(),
            _ => Err(format!(
                "invalid character {} looking for beginning of value",
                quote_char(c)
            )),
        }
    }

    fn nest(&mut self) -> Result<(), String> {
        self.depth += 1;
        // Go allows 10000 levels on a stack that grows; a client thread here
        // has 256 KiB, which a debug build fills at about 400, so a deeper
        // line is refused instead of overflowing it. Requests and Hyprland's
        // answers nest three deep.
        if self.depth > MAX_DEPTH {
            return Err("exceeded max depth".to_string());
        }
        Ok(())
    }

    fn object(&mut self) -> Result<Value, String> {
        self.nest()?;
        self.i += 1;
        let mut fields = Vec::new();
        self.ws();
        if self.peek()? == b'}' {
            self.i += 1;
            self.depth -= 1;
            return Ok(Value::Object(fields));
        }
        loop {
            self.ws();
            let c = self.peek()?;
            if c != b'"' {
                return Err(format!(
                    "invalid character {} looking for beginning of object key string",
                    quote_char(c)
                ));
            }
            let key = self.string()?;
            self.ws();
            let c = self.peek()?;
            if c != b':' {
                return Err(format!(
                    "invalid character {} after object key",
                    quote_char(c)
                ));
            }
            self.i += 1;
            self.ws();
            let v = self.value()?;
            fields.push((key, v));
            self.ws();
            match self.peek()? {
                b',' => self.i += 1,
                b'}' => {
                    self.i += 1;
                    self.depth -= 1;
                    return Ok(Value::Object(fields));
                }
                c => {
                    return Err(format!(
                        "invalid character {} after object key:value pair",
                        quote_char(c)
                    ))
                }
            }
        }
    }

    fn array(&mut self) -> Result<Value, String> {
        self.nest()?;
        self.i += 1;
        let mut items = Vec::new();
        self.ws();
        if self.peek()? == b']' {
            self.i += 1;
            self.depth -= 1;
            return Ok(Value::Array(items));
        }
        loop {
            self.ws();
            items.push(self.value()?);
            self.ws();
            match self.peek()? {
                b',' => self.i += 1,
                b']' => {
                    self.i += 1;
                    self.depth -= 1;
                    return Ok(Value::Array(items));
                }
                c => {
                    return Err(format!(
                        "invalid character {} after array element",
                        quote_char(c)
                    ))
                }
            }
        }
    }

    fn literal(&mut self, word: &[u8], v: Value) -> Result<Value, String> {
        for &want in word {
            let c = self.peek()?;
            if c != want {
                let w = std::str::from_utf8(word).unwrap_or_default();
                return Err(format!(
                    "invalid character {} in literal {w} (expecting '{}')",
                    quote_char(c),
                    want as char
                ));
            }
            self.i += 1;
        }
        Ok(v)
    }

    fn number(&mut self) -> Result<Value, String> {
        let start = self.i;
        let bad = |p: &Self| -> String {
            match p.s.get(p.i) {
                None => EOF.to_string(),
                Some(&c) => format!("invalid character {} in numeric literal", quote_char(c)),
            }
        };
        if self.s.get(self.i) == Some(&b'-') {
            self.i += 1;
        }
        match self.s.get(self.i) {
            Some(b'0') => self.i += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.s.get(self.i), Some(b'0'..=b'9')) {
                    self.i += 1;
                }
            }
            _ => return Err(bad(self)),
        }
        if self.s.get(self.i) == Some(&b'.') {
            self.i += 1;
            if !matches!(self.s.get(self.i), Some(b'0'..=b'9')) {
                return Err(bad(self));
            }
            while matches!(self.s.get(self.i), Some(b'0'..=b'9')) {
                self.i += 1;
            }
        }
        if matches!(self.s.get(self.i), Some(b'e' | b'E')) {
            self.i += 1;
            if matches!(self.s.get(self.i), Some(b'+' | b'-')) {
                self.i += 1;
            }
            if !matches!(self.s.get(self.i), Some(b'0'..=b'9')) {
                return Err(bad(self));
            }
            while matches!(self.s.get(self.i), Some(b'0'..=b'9')) {
                self.i += 1;
            }
        }
        let text = std::str::from_utf8(&self.s[start..self.i]).unwrap_or_default();
        Ok(Value::Number(text.to_string()))
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let mut v = 0u32;
        for _ in 0..4 {
            let c = self.peek()?;
            let d = match c {
                b'0'..=b'9' => c - b'0',
                b'a'..=b'f' => c - b'a' + 10,
                b'A'..=b'F' => c - b'A' + 10,
                _ => {
                    return Err(format!(
                        "invalid character {} in \\u hexadecimal character escape",
                        quote_char(c)
                    ))
                }
            };
            v = v * 16 + d as u32;
            self.i += 1;
        }
        Ok(v)
    }

    /// A string at a `"`. Invalid UTF-8 and lone surrogates become U+FFFD, as
    /// Go decodes them.
    fn string(&mut self) -> Result<String, String> {
        self.i += 1;
        let mut raw: Vec<u8> = Vec::new();
        loop {
            let c = self.peek()?;
            match c {
                b'"' => {
                    self.i += 1;
                    return Ok(go_lossy(&raw));
                }
                b'\\' => {
                    self.i += 1;
                    let e = self.peek()?;
                    self.i += 1;
                    match e {
                        b'"' | b'\\' | b'/' => raw.push(e),
                        b'b' => raw.push(0x08),
                        b'f' => raw.push(0x0c),
                        b'n' => raw.push(b'\n'),
                        b'r' => raw.push(b'\r'),
                        b't' => raw.push(b'\t'),
                        b'u' => {
                            let hi = self.hex4()?;
                            let mut ch = char::from_u32(hi);
                            if (0xd800..0xdc00).contains(&hi)
                                && self.s.get(self.i) == Some(&b'\\')
                                && self.s.get(self.i + 1) == Some(&b'u')
                            {
                                let save = self.i;
                                self.i += 2;
                                let lo = self.hex4()?;
                                if (0xdc00..0xe000).contains(&lo) {
                                    ch = char::from_u32(
                                        0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00),
                                    );
                                } else {
                                    self.i = save;
                                }
                            }
                            let ch = ch.unwrap_or('\u{fffd}');
                            let mut b = [0u8; 4];
                            raw.extend_from_slice(ch.encode_utf8(&mut b).as_bytes());
                        }
                        _ => {
                            return Err(format!(
                                "invalid character {} in string escape code",
                                quote_char(e)
                            ))
                        }
                    }
                }
                0x00..=0x1f => {
                    return Err(format!(
                        "invalid character {} in string literal",
                        quote_char(c)
                    ))
                }
                _ => {
                    raw.push(c);
                    self.i += 1;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f(v: f64) -> String {
        let mut out = Vec::new();
        assert!(write_f64(&mut out, v));
        String::from_utf8(out).unwrap()
    }

    fn s(v: &str) -> String {
        let mut out = Vec::new();
        write_str(&mut out, v);
        String::from_utf8(out).unwrap()
    }

    // What Go 1.27's encoding/json printed for the same values.
    #[test]
    fn number_text_is_gos() {
        assert_eq!(f(50.0), "50");
        assert_eq!(f(-1.0), "-1");
        assert_eq!(f(36.0), "36");
        assert_eq!(f(0.1), "0.1");
        assert_eq!(f(7.6e-7), "7.6e-7");
        assert_eq!(f(1e-7), "1e-7");
        assert_eq!(f(1e21), "1e+21");
        assert_eq!(f(1e20), "100000000000000000000");
        assert_eq!(f(1.5e-6), "0.0000015");
        assert_eq!(f(123456789.125), "123456789.125");
        assert_eq!(f(5e-324), "5e-324");
        assert_eq!(f(f64::MAX), "1.7976931348623157e+308");
        assert_eq!(f(0.0), "0");
        assert!(!write_f64(&mut Vec::new(), f64::NAN));
        assert!(!write_f64(&mut Vec::new(), f64::INFINITY));
    }

    #[test]
    fn string_escapes_are_gos() {
        // DEL is not escaped.
        assert_eq!(
            s("a\u{0}\u{8}\u{c}\u{1f}<>&\u{2028}\u{2029}\u{7f}"),
            "\"a\\u0000\\b\\f\\u001f\\u003c\\u003e\\u0026\\u2028\\u2029\u{7f}\""
        );
        assert_eq!(s("q\"b\\n\n\r\t"), r#""q\"b\\n\n\r\t""#);
        assert_eq!(s("é😀"), "\"é😀\"");
    }

    #[test]
    fn invalid_utf8_is_one_replacement_per_byte() {
        // Go wrote "\ufffd\ufffdA\ufffd\ufffd" for E2 82 41 FF and a real U+FFFD.
        assert_eq!(
            go_lossy(&[0xe2, 0x82, 0x41, 0xff, 0xef, 0xbf, 0xbd]),
            "\u{fffd}\u{fffd}A\u{fffd}\u{fffd}"
        );
        assert_eq!(go_lossy(b"plain"), "plain");
        assert_eq!(go_lossy(&[0xe2, 0x82]), "\u{fffd}\u{fffd}");
    }

    #[test]
    fn objects_keep_field_order_and_null() {
        let mut out = Vec::new();
        let mut o = Obj::new(&mut out);
        o.str("type", "reply")
            .int("id", 3)
            .bool("ok", true)
            .null("mem")
            .strs("args", &[])
            .float("cpu", -1.0);
        assert!(o.end());
        assert_eq!(
            String::from_utf8(out).unwrap(),
            r#"{"type":"reply","id":3,"ok":true,"mem":null,"args":[],"cpu":-1}"#
        );
    }

    #[test]
    fn parse_values() {
        assert_eq!(parse(b" null ").unwrap(), Value::Null);
        assert_eq!(
            parse(br#"{"a":[1,-2.5e3,true],"b":"x\u00e9\ud83d\ude00\ud800","a":2}"#).unwrap(),
            Value::Object(vec![
                (
                    "a".into(),
                    Value::Array(vec![
                        Value::Number("1".into()),
                        Value::Number("-2.5e3".into()),
                        Value::Bool(true)
                    ])
                ),
                ("b".into(), Value::String("xé😀\u{fffd}".into())),
                ("a".into(), Value::Number("2".into())),
            ])
        );
        assert_eq!(
            parse(br#"{"a":1,"a":2}"#).unwrap().get("a"),
            Some(&Value::Number("2".into()))
        );
    }

    // The messages Go printed for the same inputs.
    #[test]
    fn parse_errors_are_gos() {
        assert_eq!(parse(b"").unwrap_err(), "unexpected end of JSON input");
        assert_eq!(
            parse(b"x").unwrap_err(),
            "invalid character 'x' looking for beginning of value"
        );
        assert_eq!(parse(b"[1").unwrap_err(), "unexpected end of JSON input");
        assert_eq!(
            parse(br#"{"a":}"#).unwrap_err(),
            "invalid character '}' looking for beginning of value"
        );
        assert_eq!(
            parse(b"[1] x").unwrap_err(),
            "invalid character 'x' after top-level value"
        );
        assert_eq!(parse(b"tru").unwrap_err(), "unexpected end of JSON input");
        assert!(parse(b"\"\x01\"")
            .unwrap_err()
            .starts_with("invalid character '\\x01' in string"));
        assert!(parse(b"01").is_err());
        assert!(parse(b"1.").is_err());
        assert!(parse(b"-").is_err());
    }

    // A client thread's stack holds the deepest line the parser accepts.
    #[test]
    fn the_deepest_line_fits_a_client_thread() {
        let line = "[".repeat(MAX_DEPTH) + &"]".repeat(MAX_DEPTH);
        let deeper = "[".repeat(MAX_DEPTH + 1) + &"]".repeat(MAX_DEPTH + 1);
        let t = std::thread::Builder::new()
            .stack_size(256 * 1024)
            .spawn(move || {
                (
                    parse(line.as_bytes()).is_ok(),
                    parse(deeper.as_bytes()).is_err(),
                )
            })
            .unwrap();
        assert_eq!(t.join().unwrap(), (true, true));
    }

    #[test]
    fn numbers_as_go_reads_them() {
        assert_eq!(parse(b"1e-400").unwrap().as_f64(), Some(0.0));
        assert_eq!(parse(b"1e400").unwrap().as_f64(), None);
        assert_eq!(parse(b"500").unwrap().as_f64(), Some(500.0));
    }
}
