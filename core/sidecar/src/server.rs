//! The sidecar: one unix socket, JSON lines, a sampler that runs only while
//! somebody is subscribed, and the border wipe loop (plan 069), likewise.
//!
//! Adapted from DankMaterialShell core/internal/server (MIT, Copyright (c) 2025
//! Avenge Media LLC) by way of the Go daemon (plan 167): a single daemon the
//! shell connects to, capabilities announced on connect, and per-stream
//! subscriptions instead of a request per frame.
//!
//! Threads: one per client reading its requests, one that owns the sampler,
//! the border wipe's, and one for the idle exit. Shared state sits behind one
//! mutex, never held while sampling or while a client is written to.

use crate::borderwipe::{self, Controller, Status, STATE_WAITING};
use crate::gocompat::{errno_text, format_duration, path_error, positive};
use crate::json::Value;
use crate::proto::{self, Reply, Request};
use crate::sysusage::Sampler;
use std::collections::BTreeMap;
use std::io::{ErrorKind, Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, RecvTimeoutError, Sender};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

/// The 3 s tick haseen.sysusage used in QML.
pub const DEFAULT_INTERVAL: Duration = Duration::from_secs(3);
const MIN_INTERVAL: Duration = Duration::from_millis(500);
/// The longest request line, as the Go daemon's scanner allowed.
const MAX_LINE: usize = 1 << 20;
const STACK: usize = 256 * 1024;

pub struct Options {
    pub socket: String,
    /// Reported in the hello frame; the installer passes share/haseen/VERSION
    /// so a stale binary is visible.
    pub version: String,
    /// Exit once the last client has been gone this long, in Go
    /// nanoseconds; zero or less never exits.
    pub idle_timeout_ns: i64,
    /// The filesystem the sampler reads (empty = this machine).
    pub root: Vec<u8>,
    /// The wipe loop's state dir, Hyprland runtime dir and default instance.
    pub border_wipe: borderwipe::Options,
}

/// A live daemon already owns the socket. The caller that started this one on
/// demand wants the socket, not this process, so it reports the socket as
/// ready and exits.
pub enum ListenError {
    AlreadyRunning,
    Failed(String),
}

struct Conn {
    stream: Mutex<UnixStream>,
}

impl Conn {
    /// Writes one line; a client that cannot take it is closed, which ends
    /// its reader and removes it.
    fn send(&self, line: &[u8]) {
        let stream = lock(&self.stream);
        if (&*stream).write_all(line).is_err() {
            let _ = stream.shutdown(Shutdown::Both);
        }
    }

    fn close(&self) {
        let _ = lock(&self.stream).shutdown(Shutdown::Both);
    }
}

struct Subscription {
    interval: Duration,
    gpu: String,
    top: bool,
    system: bool,
}

struct Client {
    conn: Arc<Conn>,
    sub: Option<Subscription>,
    /// Set while this client subscribes to the border wipe, with the Hyprland
    /// instance it named; wipe_seq orders those subscriptions.
    wipe: bool,
    wipe_sig: String,
    wipe_seq: u64,
}

struct State {
    /// By connection order, so "the last one" is well defined.
    clients: BTreeMap<u64, Client>,
    next_id: u64,
    last_go: Instant,
    wipe_seq: u64,
}

enum SamplerMsg {
    Reschedule,
    Now,
}

struct Inner {
    opts: Options,
    state: Mutex<State>,
    /// Woken when a client comes or goes, for the idle exit.
    changed: Condvar,
    sampler: Mutex<Sender<SamplerMsg>>,
    wipe: Controller,
}

pub struct Server {
    inner: Arc<Inner>,
    listener: UnixListener,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    match m.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    }
}

pub fn log(msg: &str) {
    eprintln!("haseen-sidecar: {msg}");
}

/// Go's os.MkdirAll(dir, 0700), with its error text: the component that
/// failed, and "not a directory" for a file in the way.
fn mkdir_all(dir: &Path) -> Result<(), String> {
    let shown = |p: &Path| p.display().to_string();
    match std::fs::metadata(dir) {
        Ok(meta) if meta.is_dir() => return Ok(()),
        Ok(_) => {
            return Err(format!(
                "mkdir {}: {}",
                shown(dir),
                errno_text(libc::ENOTDIR)
            ))
        }
        Err(_) => {}
    }
    if let Some(parent) = dir.parent().filter(|p| !p.as_os_str().is_empty()) {
        mkdir_all(parent)?;
    }
    match std::fs::DirBuilder::new().mode(0o700).create(dir) {
        Ok(()) => Ok(()),
        Err(_) if std::fs::symlink_metadata(dir).is_ok_and(|m| m.is_dir()) => Ok(()),
        Err(e) => Err(path_error("mkdir", &shown(dir), &e)),
    }
}

/// The sun_path limit: 108 bytes with the terminating NUL.
const SUN_PATH: usize = 108;

pub fn listen(opts: Options) -> Result<Server, ListenError> {
    if opts.socket.is_empty() {
        return Err(ListenError::Failed("no socket path".to_string()));
    }
    let socket = PathBuf::from(&opts.socket);
    if let Some(dir) = socket.parent().filter(|d| !d.as_os_str().is_empty()) {
        mkdir_all(dir).map_err(ListenError::Failed)?;
    }
    // A socket left by a daemon that died is not an owner: connect first, and
    // only remove it when nothing answers.
    if UnixStream::connect(&socket).is_ok() {
        return Err(ListenError::AlreadyRunning);
    }
    let _ = std::fs::remove_file(&socket);

    let failed =
        |what: String| ListenError::Failed(format!("listen unix {}: bind: {what}", opts.socket));
    if opts.socket.len() >= SUN_PATH {
        return Err(failed(errno_text(libc::EINVAL)));
    }
    let listener = UnixListener::bind(&socket).map_err(|e| match e.raw_os_error() {
        Some(errno) => failed(errno_text(errno)),
        None => failed(e.to_string()),
    })?;
    if let Err(e) = std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600)) {
        return Err(ListenError::Failed(path_error("chmod", &opts.socket, &e)));
    }

    let (tx, rx) = channel();
    let mut sampler = Sampler::new(&opts.root);
    let wipe_opts = opts.border_wipe.clone();
    let inner = Arc::new_cyclic(|weak: &std::sync::Weak<Inner>| {
        let weak = weak.clone();
        let wipe = Controller::start(
            wipe_opts,
            Box::new(move |status| {
                if let Some(inner) = weak.upgrade() {
                    inner.wipe_changed(status);
                }
            }),
        );
        Inner {
            opts,
            state: Mutex::new(State {
                clients: BTreeMap::new(),
                next_id: 0,
                last_go: Instant::now(),
                wipe_seq: 0,
            }),
            changed: Condvar::new(),
            sampler: Mutex::new(tx),
            wipe,
        }
    });

    let weak = Arc::downgrade(&inner);
    std::thread::Builder::new()
        .name("sampler".into())
        .stack_size(STACK)
        .spawn(move || {
            let mut deadline: Option<Instant> = None;
            loop {
                let msg = match deadline {
                    None => rx.recv().map_err(|_| RecvTimeoutError::Disconnected),
                    Some(d) => rx.recv_timeout(d.saturating_duration_since(Instant::now())),
                };
                let Some(inner) = weak.upgrade() else { return };
                match msg {
                    Ok(SamplerMsg::Reschedule) => deadline = inner.schedule(),
                    Ok(SamplerMsg::Now) => inner.sample_once(&mut sampler),
                    Err(RecvTimeoutError::Timeout) => {
                        inner.sample_once(&mut sampler);
                        deadline = inner.schedule();
                    }
                    Err(RecvTimeoutError::Disconnected) => return,
                }
            }
        })
        .map_err(|e| ListenError::Failed(e.to_string()))?;

    Ok(Server { inner, listener })
}

impl Server {
    /// Accepts clients until the process exits: on `shutdown`, the idle
    /// timeout or a signal. Returns only when accepting fails.
    pub fn serve(self) -> std::io::Error {
        if let Some(timeout) = positive(self.inner.opts.idle_timeout_ns) {
            let inner = Arc::clone(&self.inner);
            let _ = std::thread::Builder::new()
                .name("idle".into())
                .stack_size(64 * 1024)
                .spawn(move || inner.idle_watch(timeout));
        }
        loop {
            match self.listener.accept() {
                Ok((stream, _)) => {
                    let inner = Arc::clone(&self.inner);
                    let spawned = std::thread::Builder::new()
                        .name("client".into())
                        .stack_size(STACK)
                        .spawn(move || inner.handle(stream));
                    if let Err(e) = spawned {
                        log(&format!("cannot serve a client: {e}"));
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) => return e,
            }
        }
    }
}

impl Inner {
    /// Removes the socket and exits, as the Go daemon's Close did once Serve
    /// returned.
    fn close(&self) -> ! {
        let _ = std::fs::remove_file(&self.opts.socket);
        std::process::exit(0);
    }

    fn idle_watch(&self, timeout: Duration) {
        let mut state = lock(&self.state);
        loop {
            if state.clients.is_empty() {
                let gone = state.last_go.elapsed();
                if gone > timeout {
                    log(&format!(
                        "no clients for {}, exiting",
                        format_duration(self.opts.idle_timeout_ns)
                    ));
                    drop(state);
                    self.close();
                }
                let wait = timeout - gone + Duration::from_millis(1);
                state = match self.changed.wait_timeout(state, wait) {
                    Ok((g, _)) => g,
                    Err(p) => p.into_inner().0,
                };
            } else {
                state = match self.changed.wait(state) {
                    Ok(g) => g,
                    Err(p) => p.into_inner(),
                };
            }
        }
    }

    fn tell_sampler(&self, msg: SamplerMsg) {
        let _ = lock(&self.sampler).send(msg);
    }

    fn handle(&self, stream: UnixStream) {
        let Ok(writer) = stream.try_clone() else {
            return;
        };
        let conn = Arc::new(Conn {
            stream: Mutex::new(writer),
        });
        let id = {
            let mut state = lock(&self.state);
            state.next_id += 1;
            let id = state.next_id;
            state.clients.insert(
                id,
                Client {
                    conn: Arc::clone(&conn),
                    sub: None,
                    wipe: false,
                    wipe_sig: String::new(),
                    wipe_seq: 0,
                },
            );
            id
        };
        self.changed.notify_all();

        conn.send(&proto::hello(&self.opts.version, std::process::id()));
        read_lines(stream, |line| match proto::decode_request(line) {
            Ok(req) => self.dispatch(id, &conn, req),
            Err(proto::BadJson) => conn.send(&Reply::error(0, "bad json".to_string()).encode()),
        });

        {
            let mut state = lock(&self.state);
            state.clients.remove(&id);
            state.last_go = Instant::now();
        }
        self.changed.notify_all();
        self.tell_sampler(SamplerMsg::Reschedule);
        self.sync_wipe();
        conn.close();
    }

    fn dispatch(&self, id: u64, conn: &Conn, req: Request) {
        let mut reply = Reply::ok(req.id);
        let mut sample_now = false;
        match req.method.as_str() {
            proto::METHOD_CAPABILITIES => reply.capabilities = true,
            proto::METHOD_SUBSCRIBE => match req.stream.as_str() {
                proto::STREAM_SYSUSAGE => {
                    self.subscribe_sysusage(id, &req);
                    // Answer the first sample at once: a widget that just
                    // appeared should not show "?" for a whole interval.
                    sample_now = true;
                }
                proto::STREAM_BORDER_WIPE => {
                    let sig = match req.param("signature") {
                        Some(Value::String(s)) => s.clone(),
                        _ => String::new(),
                    };
                    {
                        let mut state = lock(&self.state);
                        state.wipe_seq += 1;
                        let seq = state.wipe_seq;
                        if let Some(c) = state.clients.get_mut(&id) {
                            c.wipe = true;
                            c.wipe_sig = sig;
                            c.wipe_seq = seq;
                        }
                    }
                    self.sync_wipe();
                    // Every subscriber hears the state once it is settled,
                    // changed or not; later changes follow as events.
                    self.wipe.announce();
                }
                other => {
                    reply = Reply::error(req.id, format!("unknown stream: {other}"));
                }
            },
            proto::METHOD_UNSUBSCRIBE => {
                {
                    let mut state = lock(&self.state);
                    if let Some(c) = state.clients.get_mut(&id) {
                        if req.stream.is_empty() || req.stream == proto::STREAM_SYSUSAGE {
                            c.sub = None;
                        }
                        if req.stream.is_empty() || req.stream == proto::STREAM_BORDER_WIPE {
                            c.wipe = false;
                        }
                    }
                }
                self.tell_sampler(SamplerMsg::Reschedule);
                self.sync_wipe();
            }
            proto::METHOD_STATUS => {
                let mut data = b"{\"borderwipe\":".to_vec();
                self.wipe.status().encode(&mut data);
                data.push(b'}');
                reply.data = Some(data);
            }
            proto::METHOD_SHUTDOWN => {
                conn.send(&reply.encode());
                self.close();
            }
            other => {
                reply = Reply::error(req.id, format!("unknown method: {other}"));
            }
        }
        if req.id != 0 || !reply.ok {
            conn.send(&reply.encode());
        }
        if sample_now {
            self.tell_sampler(SamplerMsg::Now);
        }
    }

    fn subscribe_sysusage(&self, id: u64, req: &Request) {
        let mut sub = Subscription {
            interval: DEFAULT_INTERVAL,
            gpu: "auto".to_string(),
            top: false,
            system: false,
        };
        if let Some(v) = req.param("intervalMs").and_then(Value::as_f64) {
            if v > 0.0 {
                // Go's time.Duration(v) * time.Millisecond: truncated, and
                // wrapping where it overflows.
                let ns = (v as i64).wrapping_mul(1_000_000);
                sub.interval = if ns < MIN_INTERVAL.as_nanos() as i64 {
                    MIN_INTERVAL
                } else {
                    Duration::from_nanos(ns as u64)
                };
            }
        }
        if let Some(Value::String(g)) = req.param("gpu") {
            if !g.is_empty() {
                sub.gpu = g.clone();
            }
        }
        sub.top = matches!(req.param("processes"), Some(Value::Bool(true)));
        sub.system = matches!(req.param("system"), Some(Value::Bool(true)));
        if let Some(c) = lock(&self.state).clients.get_mut(&id) {
            c.sub = Some(sub);
        }
        self.tell_sampler(SamplerMsg::Reschedule);
    }

    /// The next sample's time: the shortest interval any subscriber asked
    /// for, from now; none while nobody is subscribed.
    fn schedule(&self) -> Option<Instant> {
        let state = lock(&self.state);
        let interval = state
            .clients
            .values()
            .filter_map(|c| c.sub.as_ref().map(|s| s.interval))
            .min()?;
        Instant::now().checked_add(interval)
    }

    /// One sample for every subscriber: two bars on two screens and the panel
    /// read the same files once. The process list and the system stats are
    /// read when anyone asks, and everyone receives them.
    fn sample_once(&self, sampler: &mut Sampler) {
        let (subs, gpu, top, system) = {
            let state = lock(&self.state);
            let mut subs = Vec::new();
            let (mut gpu, mut top, mut system) = ("off".to_string(), false, false);
            for c in state.clients.values() {
                let Some(s) = &c.sub else { continue };
                subs.push(Arc::clone(&c.conn));
                if s.gpu != "off" {
                    gpu = s.gpu.clone();
                }
                top |= s.top;
                system |= s.system;
            }
            (subs, gpu, top, system)
        };
        if subs.is_empty() {
            return;
        }
        let sample = sampler.sample(&gpu, top, system);
        let mut data = Vec::with_capacity(1024);
        if !sample.encode(&mut data) {
            // A value Go could not encode closed every subscriber.
            subs.iter().for_each(|c| c.close());
            return;
        }
        let line = proto::event(proto::STREAM_SYSUSAGE, &data);
        for c in subs {
            c.send(&line);
        }
    }

    /// Runs the border wipe while any client subscribes to it, for the
    /// Hyprland instance the latest of them named: a shell started after a
    /// Hyprland restart names the new one.
    fn sync_wipe(&self) {
        let (active, sig) = {
            let state = lock(&self.state);
            state
                .clients
                .values()
                .filter(|c| c.wipe)
                .max_by_key(|c| c.wipe_seq)
                .map_or((false, String::new()), |c| (true, c.wipe_sig.clone()))
        };
        self.wipe.set(active, &sig);
    }

    fn wipe_changed(&self, status: Status) {
        // Pausing and resuming follow focus; only trouble goes to the log.
        if status.state == STATE_WAITING {
            log(&format!("border wipe waiting: {}", status.reason));
        }
        let subs: Vec<Arc<Conn>> = {
            let state = lock(&self.state);
            state
                .clients
                .values()
                .filter(|c| c.wipe)
                .map(|c| Arc::clone(&c.conn))
                .collect()
        };
        let mut data = Vec::with_capacity(128);
        if !status.encode(&mut data) {
            return;
        }
        let line = proto::event(proto::STREAM_BORDER_WIPE, &data);
        for c in subs {
            c.send(&line);
        }
    }
}

/// Calls `f` for every non-empty line, a trailing `\r` dropped, until the
/// client closes or sends a line longer than MAX_LINE (Go's scanner stopped
/// there too). A last line without a newline still counts.
fn read_lines(mut stream: UnixStream, mut f: impl FnMut(&[u8])) {
    let mut buf: Vec<u8> = Vec::with_capacity(4096);
    let mut chunk = vec![0u8; 4096];
    let mut scanned = 0;
    loop {
        let n = match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        buf.extend_from_slice(&chunk[..n]);
        let mut start = 0;
        while let Some(off) = buf[scanned..].iter().position(|&b| b == b'\n') {
            let end = scanned + off;
            let mut line = &buf[start..end];
            if line.last() == Some(&b'\r') {
                line = &line[..line.len() - 1];
            }
            if !line.is_empty() {
                f(line);
            }
            start = end + 1;
            scanned = start;
        }
        buf.drain(..start);
        scanned = buf.len();
        if buf.len() >= MAX_LINE {
            return;
        }
    }
    let mut line = &buf[..];
    if line.last() == Some(&b'\r') {
        line = &line[..line.len() - 1];
    }
    if !line.is_empty() {
        f(line);
    }
}
