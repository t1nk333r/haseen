//! The wire format between the haseen shell and the sidecar: one JSON object
//! per line over a unix socket.
//!
//! Shape adapted from DankMaterialShell core/internal/proto and its
//! Services/DMSService.qml client (MIT, Copyright (c) 2025 Avenge Media LLC):
//! the daemon announces its capabilities on connect and the shell gates every
//! feature on them, so an old, missing or killed daemon degrades the UI instead
//! of breaking it. haseen keeps its own Quickshell IPC for everything else; this
//! socket carries sampling and the border wipe fallback (plan 069).

use crate::json::{parse, write_str_list, Obj, Value};

/// Bumped when the wire format changes in a way a client can see.
pub const VERSION: i64 = 1;

pub const TYPE_HELLO: &str = "hello";
pub const TYPE_REPLY: &str = "reply";
pub const TYPE_EVENT: &str = "event";

pub const METHOD_SUBSCRIBE: &str = "subscribe";
/// `stream`; none = every stream of this client.
pub const METHOD_UNSUBSCRIBE: &str = "unsubscribe";
pub const METHOD_CAPABILITIES: &str = "capabilities";
pub const METHOD_STATUS: &str = "status";
pub const METHOD_SHUTDOWN: &str = "shutdown";

/// CPU, memory, GPU and the process list. Params: intervalMs, gpu
/// ("auto"/"off"/"cardN"), processes (adds `processes`) and system (adds
/// `cpuTempC`, `cpuFreqMHz`, `net` {rxBps, txBps} and `disks`).
pub const STREAM_SYSUSAGE: &str = "sysusage";
/// Turns the active border for a theme that declares border_wipe in
/// colors.toml (plan 069). Params: signature (the HYPRLAND_INSTANCE_SIGNATURE
/// to drive; default the daemon's own).
pub const STREAM_BORDER_WIPE: &str = "borderwipe";

pub const CAPABILITIES: [&str; 2] = [STREAM_SYSUSAGE, STREAM_BORDER_WIPE];

fn capabilities() -> Vec<String> {
    CAPABILITIES.iter().map(|s| s.to_string()).collect()
}

/// The first line the daemon writes. `capabilities` is the contract: a client
/// that does not find its stream there must not use it.
pub fn hello(version: &str, pid: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity(128);
    let mut o = Obj::new(&mut out);
    o.str("type", TYPE_HELLO)
        .int("protocol", VERSION)
        .str("version", version)
        .int("pid", pid as i64);
    o.raw("capabilities", |out| {
        write_str_list(out, &capabilities());
        true
    });
    o.end();
    out.push(b'\n');
    out
}

/// One answer. `capabilities` and `data` are left out when absent, `error`
/// when empty, as Go's omitempty did.
pub struct Reply {
    pub id: i64,
    pub ok: bool,
    pub error: String,
    pub capabilities: bool,
    /// The encoded `data` value (status answers {"borderwipe": ...}).
    pub data: Option<Vec<u8>>,
}

impl Reply {
    pub fn ok(id: i64) -> Reply {
        Reply {
            id,
            ok: true,
            error: String::new(),
            capabilities: false,
            data: None,
        }
    }

    pub fn error(id: i64, error: String) -> Reply {
        Reply {
            id,
            ok: false,
            error,
            capabilities: false,
            data: None,
        }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(96);
        let mut o = Obj::new(&mut out);
        o.str("type", TYPE_REPLY)
            .int("id", self.id)
            .bool("ok", self.ok);
        if !self.error.is_empty() {
            o.str("error", &self.error);
        }
        if self.capabilities {
            o.strs("capabilities", &capabilities());
        }
        if let Some(data) = &self.data {
            o.raw("data", |out| {
                out.extend_from_slice(data);
                true
            });
        }
        o.end();
        out.push(b'\n');
        out
    }
}

/// One event line around an already encoded payload.
pub fn event(stream: &str, data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + 48);
    let mut o = Obj::new(&mut out);
    o.str("type", TYPE_EVENT).str("stream", stream);
    o.raw("data", |out| {
        out.extend_from_slice(data);
        true
    });
    o.end();
    out.push(b'\n');
    out
}

/// One client call. `id` is echoed in the reply; 0 means "no reply wanted".
#[derive(Debug, Default, PartialEq)]
pub struct Request {
    pub id: i64,
    pub method: String,
    pub stream: String,
    pub params: Option<Vec<(String, Value)>>,
}

impl Request {
    /// A parameter's last value (Go's map keeps the last of repeated keys).
    pub fn param(&self, key: &str) -> Option<&Value> {
        self.params
            .as_ref()?
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v)
    }
}

/// A request line Go's decoder refused.
#[derive(Debug, PartialEq)]
pub struct BadJson;

/// Decodes a request line the way Go's json.Unmarshal filled proto.Request:
/// field names matched without regard to ASCII case, `null` for any field
/// leaves it alone, a repeated `params` object adds to the first, and any value
/// of the wrong type (`"id":"1"`, `"id":1.5`, a number out of float range in
/// params) fails the whole line, which the server answers with "bad json".
pub fn decode_request(line: &[u8]) -> Result<Request, BadJson> {
    let doc = parse(line).map_err(|_| BadJson)?;
    let mut req = Request::default();
    let fields = match doc {
        Value::Null => return Ok(req),
        Value::Object(fields) => fields,
        _ => return Err(BadJson),
    };
    let mut failed = false;
    for (key, value) in fields {
        let is = |name: &str| key.eq_ignore_ascii_case(name);
        if is("id") {
            match value {
                Value::Null => {}
                // Go's int takes an integer literal only: not 1.0 or 1e2.
                Value::Number(text) => match text.parse::<i64>() {
                    Ok(v) => req.id = v,
                    Err(_) => failed = true,
                },
                _ => failed = true,
            }
        } else if is("method") || is("stream") {
            match value {
                Value::Null => {}
                Value::String(s) => {
                    if is("method") {
                        req.method = s;
                    } else {
                        req.stream = s;
                    }
                }
                _ => failed = true,
            }
        } else if is("params") {
            match value {
                Value::Null => req.params = None,
                Value::Object(map) => {
                    if !map.iter().all(|(_, v)| floats_fit(v)) {
                        failed = true;
                    }
                    req.params.get_or_insert_with(Vec::new).extend(map);
                }
                _ => failed = true,
            }
        }
    }
    if failed {
        Err(BadJson)
    } else {
        Ok(req)
    }
}

/// Every number in a value fits a float64, as Go's `any` decoding requires.
fn floats_fit(v: &Value) -> bool {
    match v {
        Value::Number(_) => v.as_f64().is_some(),
        Value::Array(items) => items.iter().all(floats_fit),
        Value::Object(fields) => fields.iter().all(|(_, v)| floats_fit(v)),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(b: Vec<u8>) -> String {
        String::from_utf8(b).unwrap()
    }

    #[test]
    fn frames_are_gos() {
        assert_eq!(
            text(hello("dev", 42)),
            "{\"type\":\"hello\",\"protocol\":1,\"version\":\"dev\",\"pid\":42,\"capabilities\":[\"sysusage\",\"borderwipe\"]}\n"
        );
        assert_eq!(
            text(Reply::ok(1).encode()),
            "{\"type\":\"reply\",\"id\":1,\"ok\":true}\n"
        );
        assert_eq!(
            text(Reply::error(0, "bad json".into()).encode()),
            "{\"type\":\"reply\",\"id\":0,\"ok\":false,\"error\":\"bad json\"}\n"
        );
        let mut caps = Reply::ok(2);
        caps.capabilities = true;
        assert_eq!(
            text(caps.encode()),
            "{\"type\":\"reply\",\"id\":2,\"ok\":true,\"capabilities\":[\"sysusage\",\"borderwipe\"]}\n"
        );
        assert_eq!(
            text(event("sysusage", b"{}")),
            "{\"type\":\"event\",\"stream\":\"sysusage\",\"data\":{}}\n"
        );
    }

    // What Go's json.Unmarshal made of the same lines into proto.Request.
    #[test]
    fn request_decoding_is_gos() {
        let ok = |line: &str| decode_request(line.as_bytes()).expect(line);
        let bad = |line: &str| assert!(decode_request(line.as_bytes()).is_err(), "{line}");

        let r =
            ok(r#"{"id":3,"method":"subscribe","stream":"sysusage","params":{"intervalMs":500}}"#);
        assert_eq!(
            (r.id, r.method.as_str(), r.stream.as_str()),
            (3, "subscribe", "sysusage")
        );
        assert_eq!(r.param("intervalMs").and_then(Value::as_f64), Some(500.0));

        assert_eq!(ok("null"), Request::default());
        let r = ok(r#"{"ID":3,"Method":"x"}"#);
        assert_eq!((r.id, r.method.as_str()), (3, "x"));
        let r = ok(r#"{"params":{"a":1},"params":{"b":2}}"#);
        assert!(r.param("a").is_some() && r.param("b").is_some());
        assert_eq!(ok(r#"{"id":-5}"#).id, -5);
        assert_eq!(
            ok(r#"{"id":null,"method":null,"params":null}"#),
            Request::default()
        );
        assert_eq!(
            ok(r#"{"params":{"a":1e-400}}"#)
                .param("a")
                .and_then(Value::as_f64),
            Some(0.0)
        );

        bad("not json at all");
        bad(r#"{"id":"1"}"#);
        bad(r#"{"id":1.5}"#);
        bad(r#"{"id":1.0}"#);
        bad(r#"{"id":1e2}"#);
        bad(r#"{"id":1,"id":"x"}"#);
        bad(r#"{"method":5}"#);
        bad(r#"{"params":[]}"#);
        bad(r#"{"params":{"a":[1e400]}}"#);
        bad("[1]");
        bad("5");
        bad(r#"{"id":1} x"#);
    }
}
