//! Turns the active window border's gradient for themes that ask for a
//! clockwise wipe, when Hyprland's own borderangle animation cannot (plan
//! 069). Hyprland refuses an animation speed above 100 ds, so anything slower
//! than 10 s a turn is this loop's job. A port of the owner's
//! hypr-border-wipe.py from luna, by way of the Go daemon (plan 167): every
//! frame one `eval hl.config(...)` over Hyprland's request socket.
//!
//! One thread owns the loop; the server talks to it over a channel.

mod frame;
mod hypr;
mod theme;

pub use frame::{pace_for, Frame, Pace, MIN_FRAME};
pub use hypr::{animations_on, has_focus, native_loop, socket_paths};
pub use theme::{read_theme, Theme, ERR_BAD_COLOUR};

use crate::json::Obj;
use hypr::{Event, Hypr, REQ_ACTIVE_WINDOW, REQ_ANIMATIONS, REQ_ANIMATIONS_ON, REQ_RELOAD};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

// States, in the order a subscription usually meets them.
/// Nobody subscribed, or the theme asks for no wipe.
pub const STATE_OFF: &str = "off";
/// The theme asks, but Hyprland is not answering. Retried every gate.
pub const STATE_WAITING: &str = "waiting";
/// Hyprland's borderangle animation loops; the loop stands aside.
pub const STATE_NATIVE: &str = "native";
/// The loop is ours but holds still (game context, animations off, no focus).
pub const STATE_PAUSED: &str = "paused";
/// A frame every pace interval.
pub const STATE_RUNNING: &str = "running";

/// What the sidecar reports: as a `borderwipe` event when the state, reason or
/// pace changes, and with the angle and frame count from `status`.
#[derive(Clone, Debug, PartialEq)]
pub struct Status {
    pub state: &'static str,
    pub reason: String,
    pub seconds_per_turn: f64,
    pub angle: f64,
    pub frames: u64,
}

impl Status {
    /// Go's encoding: reason and secondsPerTurn left out when empty.
    pub fn encode(&self, out: &mut Vec<u8>) -> bool {
        let mut o = Obj::new(out);
        o.str("state", self.state);
        if !self.reason.is_empty() {
            o.str("reason", &self.reason);
        }
        if self.seconds_per_turn != 0.0 {
            o.float("secondsPerTurn", self.seconds_per_turn);
        }
        o.float("angle", self.angle).uint("frames", self.frames);
        o.end()
    }
}

#[derive(Clone)]
pub struct Options {
    /// haseen's user state: the theme is current/theme/colors.toml and the
    /// context is flags/context.
    pub state_dir: PathBuf,
    /// Holds Hyprland's sockets under hypr/<signature>/.
    pub runtime_dir: PathBuf,
    /// The instance to use when a subscriber names none.
    pub signature: String,
    /// How often a loop that is ours re-reads the context flag and
    /// animations:enabled, and how often a missing Hyprland is retried.
    /// Default 2 s, the shortest poll haseen allows (architecture §6).
    pub gate: Duration,
    /// The shortest frame; default MIN_FRAME (10 frames a second).
    pub min_frame: Duration,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            state_dir: PathBuf::new(),
            runtime_dir: PathBuf::new(),
            signature: String::new(),
            gate: Duration::from_secs(2),
            min_frame: MIN_FRAME,
        }
    }
}

pub type OnChange = Box<dyn Fn(Status) + Send>;

enum Msg {
    Set {
        active: bool,
        signature: String,
    },
    Announce,
    /// A line from the event socket of connection `conn`.
    Event {
        conn: u64,
        event: Event,
    },
    Stop,
}

struct Shared {
    core: Mutex<(&'static str, String, f64)>,
    tenths: AtomicI64,
    frames: AtomicU64,
}

impl Shared {
    fn status(&self) -> Status {
        let (state, reason, seconds) = match self.core.lock() {
            Ok(g) => g.clone(),
            Err(p) => p.into_inner().clone(),
        };
        Status {
            state,
            reason,
            seconds_per_turn: seconds,
            angle: self.tenths.load(Ordering::Relaxed) as f64 / 10.0,
            frames: self.frames.load(Ordering::Relaxed),
        }
    }
}

/// Owns the loop. `set` says whether anyone wants it and for which Hyprland
/// instance; the loop's thread does the rest.
pub struct Controller {
    tx: Sender<Msg>,
    shared: Arc<Shared>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl Controller {
    /// Starts the loop's thread. `on_change` runs on it when the status
    /// changes, and for every announce.
    pub fn start(mut opts: Options, on_change: OnChange) -> Controller {
        if opts.gate.is_zero() {
            opts.gate = Duration::from_secs(2);
        }
        if opts.min_frame.is_zero() {
            opts.min_frame = MIN_FRAME;
        }
        let shared = Arc::new(Shared {
            core: Mutex::new((STATE_OFF, "nobody subscribed".to_string(), 0.0)),
            tenths: AtomicI64::new(0),
            frames: AtomicU64::new(0),
        });
        let (tx, rx) = channel();
        let mut l = Loop::new(opts, Arc::clone(&shared), tx.clone(), on_change);
        let thread = std::thread::Builder::new()
            .name("borderwipe".into())
            .stack_size(128 * 1024)
            .spawn(move || l.run(rx))
            .expect("spawn the border wipe thread");
        Controller {
            tx,
            shared,
            thread: Some(thread),
        }
    }

    /// Turns the loop on for a Hyprland instance (signature "" = the default
    /// one) or off. Asking for what is already so does nothing.
    pub fn set(&self, active: bool, signature: &str) {
        let _ = self.tx.send(Msg::Set {
            active,
            signature: signature.to_string(),
        });
    }

    /// Hands the status to on_change once the requests before it are handled,
    /// changed or not: a new subscriber learns the state it joined.
    pub fn announce(&self) {
        let _ = self.tx.send(Msg::Announce);
    }

    /// The current state with the angle last sent and the frame count.
    pub fn status(&self) -> Status {
        self.shared.status()
    }
}

impl Drop for Controller {
    fn drop(&mut self) {
        let _ = self.tx.send(Msg::Stop);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

/// A ticker in the manner of Go's time.Ticker: ticks on a fixed grid, and a
/// tick missed while the loop was busy fires once, at once, not once per
/// missed slot.
struct Ticker {
    next: Instant,
    interval: Duration,
}

impl Ticker {
    fn new(interval: Duration) -> Ticker {
        // A zero interval would spin; Go's NewTicker refuses one too.
        let interval = interval.max(Duration::from_nanos(1));
        Ticker {
            next: Instant::now() + interval,
            interval,
        }
    }

    fn advance(&mut self, now: Instant) {
        self.next += self.interval;
        if self.next <= now {
            let behind = now.duration_since(self.next).as_nanos() / self.interval.as_nanos();
            self.next += self.interval * behind.min(u32::MAX as u128) as u32;
        }
    }
}

/// What the loop keeps between wake-ups. Only its thread touches it.
struct Loop {
    opts: Options,
    shared: Arc<Shared>,
    tx: Sender<Msg>,
    on_change: OnChange,

    active: bool,
    signature: String,

    hy: Option<Hypr>,
    /// The event socket and its number; events from an older one are stale.
    conn: Option<UnixStream>,
    conn_id: u64,

    theme: Theme,
    pace: Pace,
    frame_b: Option<Frame>,
    i: usize,

    state: &'static str,
    focused: bool,
    animations: bool,
    game: bool,
    /// Frames went out since the last configreloaded: a frame Hyprland took
    /// after the reload would outlive it.
    sent_since_reload: bool,

    frame_t: Option<Ticker>,
    gate_t: Option<Ticker>,
}

impl Loop {
    fn new(opts: Options, shared: Arc<Shared>, tx: Sender<Msg>, on_change: OnChange) -> Loop {
        Loop {
            opts,
            shared,
            tx,
            on_change,
            active: false,
            signature: String::new(),
            hy: None,
            conn: None,
            conn_id: 0,
            theme: Theme::default(),
            pace: Pace::default(),
            frame_b: None,
            i: 0,
            state: "",
            focused: false,
            animations: false,
            game: false,
            sent_since_reload: false,
            frame_t: None,
            gate_t: None,
        }
    }

    fn run(&mut self, rx: Receiver<Msg>) {
        loop {
            let deadline = match (&self.frame_t, &self.gate_t) {
                (Some(f), Some(g)) => Some(f.next.min(g.next)),
                (Some(f), None) => Some(f.next),
                (None, Some(g)) => Some(g.next),
                (None, None) => None,
            };
            let msg = match deadline {
                None => rx.recv().map_err(|_| RecvTimeoutError::Disconnected),
                Some(d) => rx.recv_timeout(d.saturating_duration_since(Instant::now())),
            };
            match msg {
                Ok(Msg::Stop) | Err(RecvTimeoutError::Disconnected) => break,
                Ok(Msg::Announce) => (self.on_change)(self.shared.status()),
                Ok(Msg::Set { active, signature }) => {
                    if active == self.active && signature == self.signature {
                        continue;
                    }
                    if signature != self.signature {
                        self.disconnect();
                    }
                    self.active = active;
                    self.signature = signature;
                    self.full();
                }
                Ok(Msg::Event { conn, event }) => {
                    if self.conn.is_some() && conn == self.conn_id {
                        self.event(event);
                    }
                }
                Err(RecvTimeoutError::Timeout) => {
                    let now = Instant::now();
                    if let Some(f) = self.frame_t.as_mut().filter(|f| f.next <= now) {
                        f.advance(now);
                        self.frame();
                    } else if let Some(g) = self.gate_t.as_mut().filter(|g| g.next <= now) {
                        g.advance(now);
                        self.gate();
                    }
                }
            }
        }
        self.disconnect();
    }

    fn publish(&mut self, state: &'static str, reason: &str) {
        let seconds = self.theme.seconds;
        let changed = {
            let mut core = match self.shared.core.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            let changed = core.0 != state || core.1 != reason || core.2 != seconds;
            *core = (state, reason.to_string(), seconds);
            changed
        };
        if changed {
            (self.on_change)(self.shared.status());
        }
    }

    fn set(&mut self, state: &'static str, reason: &str) {
        self.state = state;
        self.publish(state, reason);
    }

    /// Works everything out again: on (un)subscribe, after a reload, and
    /// while Hyprland is missing.
    fn full(&mut self) {
        if !self.active {
            self.disconnect();
            self.gate_t = None;
            self.theme = Theme::default();
            self.set(STATE_OFF, "nobody subscribed");
            return;
        }
        let path = self.opts.state_dir.join("current/theme/colors.toml");
        let (theme, err) = match read_theme(&path) {
            Ok(t) => (t, None),
            Err(e) => (Theme::default(), Some(e)),
        };
        if theme != self.theme {
            self.frame_t = None;
            self.i = 0;
            if theme.wants() {
                self.pace = pace_for(theme.seconds, self.opts.min_frame);
                self.frame_b = Some(Frame::new(&theme.colors));
            }
            self.theme = theme;
        }
        let connected = self.connect();
        if !self.theme.wants() {
            self.frame_t = None;
            // Without the event socket a theme switch (which reloads
            // Hyprland) would go unseen; keep trying to reach it.
            self.gate_while(!connected);
            let reason = match err {
                Some(e) => format!("colors.toml: {e}"),
                None => "the theme asks for no wipe".to_string(),
            };
            self.set(STATE_OFF, &reason);
            return;
        }
        if !connected {
            self.waiting("Hyprland is not answering");
            return;
        }
        let native = match self.request(REQ_ANIMATIONS) {
            Err(_) => return self.waiting("Hyprland is not answering"),
            Ok(reply) => native_loop(&reply),
        };
        match native {
            Err(e) => return self.waiting(&format!("hyprctl animations: {e}")),
            Ok(true) => {
                // Nothing changes the leaf but a reload, which is an event:
                // no gate.
                self.frame_t = None;
                self.gate_t = None;
                self.set(STATE_NATIVE, "Hyprland's borderangle animation turns it");
                return;
            }
            Ok(false) => {}
        }
        match self.request(REQ_ACTIVE_WINDOW) {
            Err(_) => return self.waiting("Hyprland is not answering"),
            Ok(reply) => self.focused = has_focus(&reply),
        }
        self.light();
    }

    /// Re-reads what changes without a reload: the context flag and
    /// animations:enabled (`haseen context game` and `haseen toggle
    /// animations` set it with eval).
    fn light(&mut self) {
        let flag = std::fs::read(self.opts.state_dir.join("flags/context")).unwrap_or_default();
        self.game = String::from_utf8_lossy(&flag).trim() == "game";
        let on = match self.request(REQ_ANIMATIONS_ON) {
            Err(_) => return self.waiting("Hyprland is not answering"),
            Ok(reply) => animations_on(&reply),
        };
        match on {
            Err(e) => self.waiting(&format!("hyprctl getoption: {e}")),
            Ok(on) => {
                self.animations = on;
                self.decide();
            }
        }
    }

    /// Runs or pauses a loop that is ours, from what light and the events
    /// last saw.
    fn decide(&mut self) {
        self.gate_while(true);
        if self.game {
            self.pause("game context");
        } else if !self.animations {
            self.pause("animations are off");
        } else if !self.focused {
            self.pause("no window has focus");
        } else {
            if self.frame_t.is_none() {
                self.frame_t = Some(Ticker::new(self.pace.interval));
            }
            self.set(STATE_RUNNING, "");
        }
    }

    fn pause(&mut self, reason: &str) {
        self.frame_t = None;
        self.set(STATE_PAUSED, reason);
    }

    fn waiting(&mut self, reason: &str) {
        self.disconnect();
        self.gate_while(true);
        self.set(STATE_WAITING, reason);
    }

    fn ours(&self) -> bool {
        self.state == STATE_RUNNING || self.state == STATE_PAUSED
    }

    fn gate(&mut self) {
        if self.conn.is_some() && self.ours() {
            self.light();
        } else {
            self.full();
        }
    }

    fn frame(&mut self) {
        let tenths = self.pace.tenths(self.i);
        let (Some(hy), Some(fb)) = (self.hy.as_mut(), self.frame_b.as_mut()) else {
            return self.waiting("Hyprland is not answering");
        };
        let refused = match hy.request(fb.request(tenths)) {
            Err(_) => return self.waiting("Hyprland is not answering"),
            Ok(reply) if reply.starts_with(b"error") => {
                let line = reply.split(|&b| b == b'\n').next().unwrap_or_default();
                Some(crate::json::go_lossy(line))
            }
            Ok(_) => None,
        };
        if let Some(line) = refused {
            return self.waiting(&format!("Hyprland refused the frame: {line}"));
        }
        self.i = (self.i + 1) % self.pace.frames.max(1);
        self.sent_since_reload = true;
        self.shared.tenths.store(tenths as i64, Ordering::Relaxed);
        self.shared.frames.fetch_add(1, Ordering::Relaxed);
    }

    fn event(&mut self, e: Event) {
        match e {
            Event::Gone => {
                // Waiting when the theme asks for a wipe, off when it does not.
                self.disconnect();
                self.full();
            }
            Event::Reload => {
                let sent = self.sent_since_reload;
                self.sent_since_reload = false;
                self.full();
                // The reload handed the border back (a theme without a wipe,
                // or one borderangle turns). A frame of ours in flight may
                // have landed after it, with the old theme's colours; one more
                // reload makes the new config stand as written. That reload's
                // own event finds nothing sent.
                if sent && (self.state == STATE_OFF || self.state == STATE_NATIVE) {
                    if let Some(hy) = self.hy.as_mut() {
                        let _ = hy.request(REQ_RELOAD);
                    }
                }
            }
            Event::Focus(focus) => {
                self.focused = focus;
                if self.ours() {
                    self.decide();
                }
            }
        }
    }

    /// A request whose answer is copied out, so the loop can act on it.
    fn request(&mut self, msg: &[u8]) -> Result<Vec<u8>, String> {
        match self.hy.as_mut() {
            Some(hy) => hy.request(msg).map(<[u8]>::to_vec),
            None => Err("not connected".to_string()),
        }
    }

    fn connect(&mut self) -> bool {
        if self.conn.is_some() {
            return true;
        }
        let sig = if self.signature.is_empty() {
            self.opts.signature.clone()
        } else {
            self.signature.clone()
        };
        if sig.is_empty() {
            return false;
        }
        let (request, events) = socket_paths(&self.opts.runtime_dir, &sig);
        let Ok(conn) = UnixStream::connect(&events) else {
            return false;
        };
        let Ok(reader) = conn.try_clone() else {
            return false;
        };
        self.conn_id += 1;
        let id = self.conn_id;
        let tx = self.tx.clone();
        let spawned = std::thread::Builder::new()
            .name("hypr-events".into())
            .stack_size(128 * 1024)
            .spawn(move || {
                hypr::watch_events(reader, |event| {
                    tx.send(Msg::Event { conn: id, event }).is_ok()
                });
            });
        if spawned.is_err() {
            return false;
        }
        self.conn = Some(conn);
        self.hy = Some(Hypr::new(request));
        true
    }

    fn disconnect(&mut self) {
        self.frame_t = None;
        if let Some(conn) = self.conn.take() {
            // Unblocks the reader thread; whatever it still sends carries an
            // old connection number and is dropped.
            let _ = conn.shutdown(Shutdown::Both);
        }
    }

    fn gate_while(&mut self, on: bool) {
        if !on {
            self.gate_t = None;
        } else if self.gate_t.is_none() {
            self.gate_t = Some(Ticker::new(self.opts.gate));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::hypr::tests::{animations_json, ANGLE_LOOP, ANGLE_OFF};
    use super::*;
    use crate::sysusage::tests::{write, TempDir};
    use std::io::{Read, Write};
    use std::os::unix::net::UnixListener;
    use std::sync::atomic::AtomicBool;

    fn write_theme(state: &std::path::Path, body: &str) {
        write(&state.join("current/theme/colors.toml"), body);
    }

    #[derive(Default)]
    struct FakeState {
        native: bool,
        animations: bool,
        focused: bool,
        evals: Vec<String>,
        reloads: usize,
        ev_conns: Vec<UnixStream>,
    }

    /// A Hyprland for the loop: a request socket that answers one request per
    /// connection, as Hyprland does, and an event socket.
    struct FakeHypr {
        req_path: PathBuf,
        ev_path: PathBuf,
        state: Arc<Mutex<FakeState>>,
        stop: Arc<AtomicBool>,
        threads: Vec<std::thread::JoinHandle<()>>,
    }

    impl FakeHypr {
        fn start(runtime: &std::path::Path, sig: &str) -> FakeHypr {
            let (req_path, ev_path) = socket_paths(runtime, sig);
            let state = Arc::new(Mutex::new(FakeState {
                animations: true,
                focused: true,
                ..Default::default()
            }));
            let mut f = FakeHypr {
                req_path,
                ev_path,
                state,
                stop: Arc::new(AtomicBool::new(false)),
                threads: Vec::new(),
            };
            f.listen();
            f
        }

        fn listen(&mut self) {
            std::fs::create_dir_all(self.req_path.parent().unwrap()).unwrap();
            self.stop.store(false, Ordering::SeqCst);
            let req = UnixListener::bind(&self.req_path).unwrap();
            let ev = UnixListener::bind(&self.ev_path).unwrap();
            req.set_nonblocking(true).unwrap();
            ev.set_nonblocking(true).unwrap();
            let (state, stop) = (Arc::clone(&self.state), Arc::clone(&self.stop));
            self.threads.push(std::thread::spawn(move || {
                while !stop.load(Ordering::SeqCst) {
                    match req.accept() {
                        Ok((conn, _)) => answer(conn, &state),
                        Err(_) => std::thread::sleep(Duration::from_millis(1)),
                    }
                }
            }));
            let (state, stop) = (Arc::clone(&self.state), Arc::clone(&self.stop));
            self.threads.push(std::thread::spawn(move || {
                while !stop.load(Ordering::SeqCst) {
                    match ev.accept() {
                        Ok((conn, _)) => state.lock().unwrap().ev_conns.push(conn),
                        Err(_) => std::thread::sleep(Duration::from_millis(1)),
                    }
                }
            }));
        }

        /// Writes one event line to every event-socket client.
        fn push(&self, line: &str) {
            let mut s = self.state.lock().unwrap();
            for c in &mut s.ev_conns {
                let _ = c.write_all(format!("{line}\n").as_bytes());
            }
        }

        /// Hyprland going away: both sockets close and their files go.
        fn stop(&mut self) {
            self.stop.store(true, Ordering::SeqCst);
            for t in self.threads.drain(..) {
                let _ = t.join();
            }
            let mut s = self.state.lock().unwrap();
            for c in s.ev_conns.drain(..) {
                let _ = c.shutdown(Shutdown::Both);
            }
            let _ = std::fs::remove_file(&self.req_path);
            let _ = std::fs::remove_file(&self.ev_path);
        }

        fn set(&self, f: impl FnOnce(&mut FakeState)) {
            f(&mut self.state.lock().unwrap());
        }

        fn eval_count(&self) -> usize {
            self.state.lock().unwrap().evals.len()
        }

        fn reloads(&self) -> usize {
            self.state.lock().unwrap().reloads
        }
    }

    impl Drop for FakeHypr {
        fn drop(&mut self) {
            self.stop();
        }
    }

    fn answer(mut conn: UnixStream, state: &Mutex<FakeState>) {
        conn.set_nonblocking(false).unwrap();
        let mut buf = [0u8; 4096];
        let n = conn.read(&mut buf).unwrap_or(0);
        let msg = String::from_utf8_lossy(&buf[..n]).to_string();
        let mut s = state.lock().unwrap();
        let reply = match msg.as_str() {
            "j/animations" => animations_json(if s.native { ANGLE_LOOP } else { ANGLE_OFF }),
            "j/getoption animations:enabled" => {
                format!(
                    r#"{{"option": "animations:enabled", "bool": {}, "set": false }}"#,
                    s.animations
                )
            }
            "j/activewindow" => if s.focused {
                r#"{"address": "0x55d0"}"#
            } else {
                "{}"
            }
            .to_string(),
            "reload" => {
                s.reloads += 1;
                "ok".to_string()
            }
            m if m.starts_with("eval ") => {
                s.evals.push(msg.clone());
                "ok".to_string()
            }
            _ => "unknown request".to_string(),
        };
        let _ = conn.write_all(reply.as_bytes());
    }

    fn wait_for(what: &str, mut cond: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(3);
        while !cond() {
            assert!(Instant::now() < deadline, "timed out waiting for {what}");
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    /// A theme that asks for a wipe of 3.6 s a turn (a degree every 10 ms), a
    /// fake Hyprland, and a running controller.
    struct Harness {
        c: Controller,
        fake: FakeHypr,
        state: TempDir,
        _runtime: TempDir,
    }

    fn start(native: bool) -> Harness {
        let (runtime, state) = (TempDir::new(), TempDir::new());
        write_theme(
            &state.0,
            "border_wipe = \"rgba(F25623ff) rgba(F2562311)\"\nborder_wipe_seconds = 3.6\n",
        );
        let fake = FakeHypr::start(&runtime.0, "sig");
        fake.set(|f| f.native = native);
        let c = Controller::start(
            Options {
                state_dir: state.0.clone(),
                runtime_dir: runtime.0.clone(),
                signature: String::new(),
                gate: Duration::from_millis(20),
                min_frame: Duration::from_millis(10),
            },
            Box::new(|_| {}),
        );
        c.set(true, "sig");
        Harness {
            c,
            fake,
            state,
            _runtime: runtime,
        }
    }

    impl Harness {
        fn wait_state(&self, state: &str, reason: &str) {
            wait_for(&format!("{state} {reason}"), || {
                let s = self.c.status();
                s.state == state && s.reason.contains(reason)
            });
        }
    }

    #[test]
    fn never_runs_beside_the_native_loop() {
        let h = start(true);
        h.wait_state(STATE_NATIVE, "borderangle");
        std::thread::sleep(Duration::from_millis(150));
        assert_eq!(
            h.fake.eval_count(),
            0,
            "frames sent while borderangle loops"
        );
    }

    #[test]
    fn turns_the_border_one_degree_a_frame() {
        let h = start(false);
        h.wait_state(STATE_RUNNING, "");
        wait_for("five frames", || h.fake.eval_count() >= 5);
        let evals: Vec<String> = h.fake.state.lock().unwrap().evals[..5].to_vec();
        for (i, e) in evals.iter().enumerate() {
            assert!(e.contains(&format!("angle = {i} }}")), "frame {i}: {e}");
            assert!(
                e.contains(r#"colors = {"rgba(F25623ff)", "rgba(F2562311)"}"#),
                "frame {i}: {e}"
            );
        }
        let s = h.c.status();
        assert!(s.frames >= 5 && s.seconds_per_turn == 3.6, "{s:?}");
    }

    #[test]
    fn pauses_and_resumes() {
        let h = start(false);
        h.wait_state(STATE_RUNNING, "");
        let flag = h.state.0.join("flags/context");
        std::fs::create_dir_all(flag.parent().unwrap()).unwrap();

        let still_while = |what: &str| {
            let n = h.fake.eval_count();
            std::thread::sleep(Duration::from_millis(100));
            assert_eq!(
                h.fake.eval_count(),
                n,
                "frames sent while paused for {what}"
            );
        };
        let resumes = |what: &str| {
            h.wait_state(STATE_RUNNING, "");
            let n = h.fake.eval_count();
            wait_for(&format!("frames after {what}"), || {
                h.fake.eval_count() > n + 2
            });
        };

        std::fs::write(&flag, "game\n").unwrap();
        h.wait_state(STATE_PAUSED, "game context");
        let angle = h.c.status().angle;
        still_while("the game context");
        std::fs::write(&flag, "focus\n").unwrap();
        resumes("leaving game");
        assert!(
            h.c.status().angle > angle,
            "the turn starts over after a pause"
        );

        h.fake.set(|f| f.animations = false);
        h.wait_state(STATE_PAUSED, "animations are off");
        still_while("animations off");
        h.fake.set(|f| f.animations = true);
        resumes("animations on");

        h.fake.push("activewindowv2>>");
        h.wait_state(STATE_PAUSED, "no window has focus");
        still_while("no focus");
        h.fake.push("activewindowv2>>55d0a1b2c3");
        resumes("a window took focus");
    }

    #[test]
    fn reconnects_when_hyprland_comes_back() {
        let mut h = start(false);
        h.wait_state(STATE_RUNNING, "");
        h.fake.stop();
        h.wait_state(STATE_WAITING, "not answering");
        assert!(
            !h.fake.req_path.exists(),
            "the fake's socket is still there"
        );
        h.fake.listen();
        h.wait_state(STATE_RUNNING, "");
        let n = h.fake.eval_count();
        wait_for("frames on the new socket", || h.fake.eval_count() > n + 2);
    }

    #[test]
    fn reload_hands_the_border_back() {
        let h = start(false);
        h.wait_state(STATE_RUNNING, "");
        wait_for("a frame", || h.fake.eval_count() > 0);

        // `haseen theme set` swaps the theme, then reloads Hyprland.
        write_theme(&h.state.0, "accent = \"#7aa2f7\"\n");
        h.fake.push("configreloaded>>");
        h.wait_state(STATE_OFF, "no wipe");
        wait_for("the reload that drops a late frame", || {
            h.fake.reloads() == 1
        });
        let n = h.fake.eval_count();
        // That reload's own event finds nothing sent and asks for no other.
        h.fake.push("configreloaded>>");
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(
            (h.fake.reloads(), h.fake.eval_count()),
            (1, n),
            "after the hand-back"
        );

        // Back to a wipe theme, now drawn by borderangle: still no frames.
        write_theme(
            &h.state.0,
            "border_wipe = \"rgba(F25623ff) rgba(F2562311)\"\nborder_wipe_seconds = 10\n",
        );
        h.fake.set(|f| f.native = true);
        h.fake.push("configreloaded>>");
        h.wait_state(STATE_NATIVE, "");
        assert_eq!(
            h.fake.eval_count(),
            n,
            "frames went out beside the native loop"
        );
    }

    #[test]
    fn off_without_a_subscriber() {
        let h = start(false);
        h.wait_state(STATE_RUNNING, "");
        wait_for("a frame", || h.fake.eval_count() > 0);
        h.c.set(false, "");
        h.wait_state(STATE_OFF, "nobody subscribed");
        let n = h.fake.eval_count();
        std::thread::sleep(Duration::from_millis(80));
        assert_eq!(
            h.fake.eval_count(),
            n,
            "frames after the last subscriber left"
        );
    }

    #[test]
    fn status_leaves_out_what_is_empty() {
        let mut out = Vec::new();
        let s = Status {
            state: STATE_OFF,
            reason: "nobody subscribed".into(),
            seconds_per_turn: 0.0,
            angle: 0.0,
            frames: 0,
        };
        assert!(s.encode(&mut out));
        assert_eq!(
            String::from_utf8(out).unwrap(),
            r#"{"state":"off","reason":"nobody subscribed","angle":0,"frames":0}"#
        );
        let mut out = Vec::new();
        let s = Status {
            state: STATE_RUNNING,
            reason: String::new(),
            seconds_per_turn: 36.0,
            angle: 3.6,
            frames: 7,
        };
        assert!(s.encode(&mut out));
        assert_eq!(
            String::from_utf8(out).unwrap(),
            r#"{"state":"running","secondsPerTurn":36,"angle":3.6,"frames":7}"#
        );
    }
}
