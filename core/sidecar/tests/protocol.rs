//! The daemon over a real socket: the flags, the lines on stdout, the protocol
//! and its lifecycle, run against the built binary (plan 167).

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const BIN: &str = env!("CARGO_BIN_EXE_haseen-sidecar");

/// A scratch directory short enough for a socket path (108 bytes).
struct Scratch(PathBuf);

impl Scratch {
    fn new(tag: &str) -> Scratch {
        let base = std::env::var_os("TMPDIR")
            .map(PathBuf::from)
            .filter(|p| p.as_os_str().len() < 60);
        let base = base.unwrap_or_else(|| PathBuf::from("/tmp"));
        let dir = base.join(format!("hsp-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Scratch(dir)
    }

    fn socket(&self) -> PathBuf {
        self.0.join("s.sock")
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct Daemon {
    child: Child,
    socket: PathBuf,
}

impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Starts the daemon on the scratch socket and waits for its `ready` line.
fn start(scratch: &Scratch, extra: &[&str]) -> Daemon {
    start_with(scratch, extra, |_| {})
}

/// `start`, with the daemon's environment changed by `env` first.
fn start_with(scratch: &Scratch, extra: &[&str], env: impl FnOnce(&mut Command)) -> Daemon {
    let socket = scratch.socket();
    let state = scratch.0.join("state");
    std::fs::create_dir_all(&state).unwrap();
    let mut cmd = Command::new(BIN);
    env(&mut cmd);
    let mut child = cmd
        .arg("-socket")
        .arg(&socket)
        .args(["-idle-timeout", "0", "-root"])
        .arg(scratch.0.join("root"))
        .arg("-state")
        .arg(&state)
        .args(extra)
        .env_remove("HYPRLAND_INSTANCE_SIGNATURE")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    assert_eq!(line.trim_end(), format!("ready {}", socket.display()));
    Daemon { child, socket }
}

/// A connected client that reads frames as JSON text lines.
struct Client {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
}

impl Client {
    fn connect(socket: &Path) -> Client {
        let stream = UnixStream::connect(socket).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        Client {
            writer: stream.try_clone().unwrap(),
            reader: BufReader::new(stream),
        }
    }

    fn send(&mut self, line: &str) {
        self.writer.write_all(line.as_bytes()).unwrap();
        self.writer.write_all(b"\n").unwrap();
    }

    fn frame(&mut self) -> String {
        let mut line = String::new();
        self.reader
            .read_line(&mut line)
            .expect("a frame within 5 s");
        line.trim_end().to_string()
    }

    /// The next frame that contains `needle`.
    fn until(&mut self, needle: &str) -> String {
        loop {
            let f = self.frame();
            assert!(
                !f.is_empty(),
                "the daemon closed the connection before {needle}"
            );
            if f.contains(needle) {
                return f;
            }
        }
    }
}

fn hello_shape(frame: &str) -> String {
    // pid differs per run.
    let pid_at = frame.find("\"pid\":").unwrap() + 6;
    let end = frame[pid_at..].find(',').unwrap() + pid_at;
    format!("{}PID{}", &frame[..pid_at], &frame[end..])
}

#[test]
fn flags_and_capabilities() {
    for flag in ["-capabilities", "--capabilities", "-capabilities=true"] {
        let out = Command::new(BIN).arg(flag).output().unwrap();
        assert!(out.status.success(), "{flag}");
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            "sysusage borderwipe\n",
            "{flag}"
        );
    }
    let out = Command::new(BIN).arg("-version").output().unwrap();
    assert!(out.status.success());
    assert!(!out.stdout.is_empty());

    let out = Command::new(BIN).arg("-nonsense").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(
        err.starts_with("flag provided but not defined: -nonsense\nUsage of "),
        "{err}"
    );
    assert!(err.contains("  -idle-timeout duration\n    \texit this long after the last client leaves (0 = never) (default 5m0s)\n"), "{err}");

    let out = Command::new(BIN)
        .args(["-idle-timeout", "soon"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr)
        .starts_with("invalid value \"soon\" for flag -idle-timeout: parse error\n"));
    let out = Command::new(BIN).arg("-socket").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).starts_with("flag needs an argument: -socket\n"));
    let out = Command::new(BIN).arg("-h").output().unwrap();
    assert_eq!(out.status.code(), Some(0));
}

#[test]
fn hello_replies_and_errors() {
    let scratch = Scratch::new("proto");
    let d = start(&scratch, &[]);
    let mode = std::os::unix::fs::PermissionsExt::mode(
        &std::fs::metadata(&d.socket).unwrap().permissions(),
    );
    assert_eq!(mode & 0o777, 0o600, "the socket belongs to this user only");

    let mut c = Client::connect(&d.socket);
    let hello = c.frame();
    assert_eq!(
        hello_shape(&hello),
        format!(
            r#"{{"type":"hello","protocol":1,"version":"{}","pid":PID,"capabilities":["sysusage","borderwipe"]}}"#,
            option_env!("HASEEN_VERSION").unwrap_or("dev")
        )
    );
    let cases = [
        (
            r#"{"id":1,"method":"capabilities"}"#,
            r#"{"type":"reply","id":1,"ok":true,"capabilities":["sysusage","borderwipe"]}"#,
        ),
        (
            "not json at all",
            r#"{"type":"reply","id":0,"ok":false,"error":"bad json"}"#,
        ),
        (
            r#"{"id":"1","method":"capabilities"}"#,
            r#"{"type":"reply","id":0,"ok":false,"error":"bad json"}"#,
        ),
        (
            "null",
            r#"{"type":"reply","id":0,"ok":false,"error":"unknown method: "}"#,
        ),
        (
            r#"{"id":4,"method":"nonsense"}"#,
            r#"{"type":"reply","id":4,"ok":false,"error":"unknown method: nonsense"}"#,
        ),
        (
            r#"{"id":3,"method":"subscribe","stream":"nonsense"}"#,
            r#"{"type":"reply","id":3,"ok":false,"error":"unknown stream: nonsense"}"#,
        ),
        (
            r#"{"id":5,"method":"unsubscribe"}"#,
            r#"{"type":"reply","id":5,"ok":true}"#,
        ),
        (
            r#"{"id":6,"method":"status"}"#,
            r#"{"type":"reply","id":6,"ok":true,"data":{"borderwipe":{"state":"off","reason":"nobody subscribed","angle":0,"frames":0}}}"#,
        ),
    ];
    for (req, want) in cases {
        c.send(req);
        assert_eq!(c.frame(), want, "{req}");
    }
    // id 0 gets no reply unless it failed; an empty line is skipped.
    c.send(r#"{"id":0,"method":"unsubscribe"}"#);
    c.send("");
    c.send(r#"{"id":7,"method":"capabilities"}"#);
    assert!(c.frame().starts_with(r#"{"type":"reply","id":7,"#));
}

#[test]
fn sysusage_events_from_a_fixture_root() {
    let scratch = Scratch::new("sys");
    let root = scratch.0.join("root");
    std::fs::create_dir_all(root.join("proc")).unwrap();
    std::fs::write(root.join("proc/stat"), "cpu  100 0 100 700 100 0 0 0 0 0\n").unwrap();
    std::fs::write(
        root.join("proc/meminfo"),
        "MemTotal: 1000 kB\nMemAvailable: 250 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n",
    )
    .unwrap();
    let d = start(&scratch, &[]);
    let mut c = Client::connect(&d.socket);
    c.frame();
    c.send(r#"{"id":2,"method":"subscribe","stream":"sysusage","params":{"intervalMs":3600000,"gpu":"off"}}"#);
    assert_eq!(
        c.frame(),
        r#"{"type":"reply","id":2,"ok":true}"#,
        "the reply comes before the first event"
    );
    assert_eq!(
        c.frame(),
        r#"{"type":"event","stream":"sysusage","data":{"cpu":-1,"mem":{"totalKiB":1000,"availableKiB":250,"usedKiB":750,"percent":75,"swapTotalKiB":0,"swapUsedKiB":0},"gpu":-1,"gpus":null,"gpuInfo":null,"processes":[]}}"#
    );
    // Every subscribe samples at once, also a repeated one.
    std::fs::write(root.join("proc/stat"), "cpu  150 0 150 800 100 0 0 0 0 0\n").unwrap();
    c.send(r#"{"id":0,"method":"subscribe","stream":"sysusage","params":{"intervalMs":3600000,"gpu":"off","system":true}}"#);
    let event = c.frame();
    assert!(
        event.starts_with(r#"{"type":"event","stream":"sysusage","data":{"cpu":50,"#),
        "{event}"
    );
    assert!(event.ends_with(r#""processes":[],"cpuTempC":-1,"cpuFreqMHz":-1,"net":{"rxBps":-1,"txBps":-1},"disks":[]}}"#), "{event}");
}

#[test]
fn samples_follow_the_shortest_interval() {
    let scratch = Scratch::new("tick");
    let d = start(&scratch, &[]);
    let mut c = Client::connect(&d.socket);
    c.frame();
    let t0 = Instant::now();
    c.send(r#"{"id":0,"method":"subscribe","stream":"sysusage","params":{"intervalMs":1,"gpu":"off"}}"#);
    for _ in 0..3 {
        c.until(r#""stream":"sysusage""#);
    }
    // The first at once, then the 500 ms minimum between the others.
    let took = t0.elapsed();
    assert!(
        took >= Duration::from_millis(900) && took < Duration::from_secs(3),
        "{took:?}"
    );
}

// The Go daemon crashed when two samples ran at once (PR #126). Here one
// thread owns the sampler: many clients subscribing as fast as they can all
// get well-formed events, and the daemon lives.
#[test]
fn concurrent_subscribers_are_served() {
    let scratch = Scratch::new("conc");
    let d = start(&scratch, &[]);
    let socket = d.socket.clone();
    let threads: Vec<_> = (0..8)
        .map(|_| {
            let socket = socket.clone();
            std::thread::spawn(move || {
                let mut c = Client::connect(&socket);
                c.frame();
                for _ in 0..200 {
                    c.send(r#"{"id":0,"method":"subscribe","stream":"sysusage","params":{"intervalMs":3600000,"processes":true,"system":true}}"#);
                }
                c.send(r#"{"id":9,"method":"capabilities"}"#);
                c.until(r#""id":9"#);
                let event = c.until(r#""stream":"sysusage""#);
                assert!(event.ends_with("}}"), "{event}");
            })
        })
        .collect();
    for t in threads {
        t.join().unwrap();
    }
    let mut c = Client::connect(&socket);
    assert!(
        c.frame().starts_with(r#"{"type":"hello""#),
        "the daemon still answers"
    );
}

#[test]
fn second_daemon_steps_aside_and_shutdown_ends_it() {
    let scratch = Scratch::new("life");
    let mut d = start(&scratch, &[]);
    let out = Command::new(BIN)
        .arg("-socket")
        .arg(&d.socket)
        .args(["-idle-timeout", "0"])
        .output()
        .unwrap();
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("ready {}\n", d.socket.display())
    );

    let mut c = Client::connect(&d.socket);
    c.frame();
    c.send(r#"{"id":9,"method":"shutdown"}"#);
    assert_eq!(c.frame(), r#"{"type":"reply","id":9,"ok":true}"#);
    let status = d.child.wait().unwrap();
    assert!(status.success());
    assert!(!d.socket.exists(), "shutdown takes the socket with it");
}

#[test]
fn sigterm_removes_the_socket() {
    let scratch = Scratch::new("term");
    let mut d = start(&scratch, &[]);
    // SAFETY: kill(2) on our own child.
    unsafe { libc::kill(d.child.id() as i32, libc::SIGTERM) };
    assert!(d.child.wait().unwrap().success());
    assert!(!d.socket.exists());
}

#[test]
fn idle_exit_after_the_last_client() {
    let scratch = Scratch::new("idle");
    let socket = scratch.socket();
    let mut child = Command::new(BIN)
        .arg("-socket")
        .arg(&socket)
        .args(["-idle-timeout", "300ms"])
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    while !socket.exists() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    {
        let mut c = Client::connect(&socket);
        c.frame();
        std::thread::sleep(Duration::from_millis(500));
        assert!(
            child.try_wait().unwrap().is_none(),
            "a connected client keeps it alive"
        );
    }
    let t0 = Instant::now();
    let status = child.wait().unwrap();
    assert!(status.success());
    assert!(t0.elapsed() < Duration::from_secs(2));
    assert!(!socket.exists());
    let mut err = String::new();
    std::io::Read::read_to_string(&mut child.stderr.take().unwrap(), &mut err).unwrap();
    assert!(
        err.contains("haseen-sidecar: no clients for 300ms, exiting"),
        "{err}"
    );
}

#[test]
fn a_socket_that_cannot_be_made_fails() {
    let scratch = Scratch::new("fail");
    let blocked = scratch.0.join("file");
    std::fs::write(&blocked, "").unwrap();
    let out = Command::new(BIN)
        .arg("-socket")
        .arg(blocked.join("s.sock"))
        .output()
        .unwrap();
    assert!(!out.status.success());
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.starts_with(&format!("failed mkdir {}: ", blocked.display())),
        "{stdout}"
    );
    let long = format!("/tmp/{}/s.sock", "x".repeat(110));
    let out = Command::new(BIN)
        .arg("-socket")
        .arg(&long)
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(Path::new(&long).parent().unwrap());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("failed listen unix {long}: bind: invalid argument\n")
    );
}

// A client that stops reading and then half-closes must not stop the others:
// closing it releases a write blocked on it, as closing the connection did in
// the Go daemon (found in review: the Rust daemon once waited for the writer).
#[test]
fn a_stuck_client_does_not_stop_the_others() {
    let scratch = Scratch::new("stuck");
    let d = start(&scratch, &[]);
    let mut stuck = UnixStream::connect(&d.socket).unwrap();
    let line = b"{\"id\":0,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"gpu\":\"off\"}}\n";
    // Every subscribe sends a sample it never reads, until its buffer is full
    // and the sampler waits on it.
    for _ in 0..6000 {
        stuck.write_all(line).unwrap();
    }
    std::thread::sleep(Duration::from_millis(300));
    stuck.shutdown(std::net::Shutdown::Write).unwrap();

    let mut c = Client::connect(&d.socket);
    c.frame();
    c.send(r#"{"id":1,"method":"subscribe","stream":"sysusage","params":{"intervalMs":500,"gpu":"off"}}"#);
    c.until(r#""stream":"sysusage""#);
    drop(stuck);
}

/// The pids the fake nvidia-smi wrote so far, one per start.
fn nvidia_pids(file: &Path) -> Vec<i32> {
    std::fs::read_to_string(file)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .collect()
}

fn wait_for(what: &str, mut done: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !done() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// Running, not a zombie nobody reaped.
fn running(pid: i32) -> bool {
    std::fs::read_to_string(format!("/proc/{pid}/stat"))
        .ok()
        .and_then(|s| s.rsplit_once(") ").map(|(_, rest)| !rest.starts_with('Z')))
        .unwrap_or(false)
}

// nvidia-smi -l 3 runs between samples, so it must stop when the last
// subscriber leaves, by unsubscribing or by hanging up: otherwise it polls the
// GPU for the rest of the session and keeps a hybrid laptop's dGPU awake
// (plan 199).
#[test]
fn nvidia_smi_stops_with_the_last_subscriber() {
    use std::os::unix::fs::PermissionsExt;
    let scratch = Scratch::new("nv");
    let card = scratch.0.join("root/sys/class/drm/card0/device");
    std::fs::create_dir_all(&card).unwrap();
    std::fs::write(
        card.join("uevent"),
        "DRIVER=nvidia\nPCI_SLOT_NAME=0000:01:00.0\n",
    )
    .unwrap();
    std::fs::write(card.join("boot_vga"), "1\n").unwrap();
    let bin = scratch.0.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let fake = bin.join("nvidia-smi");
    std::fs::write(
        &fake,
        "#!/bin/sh\necho $$ >>\"$NV_PIDS\"\nwhile :; do echo 42; sleep 0.2; done\n",
    )
    .unwrap();
    std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
    let pids = scratch.0.join("pids");
    let path = format!("{}:/usr/bin:/bin", bin.display());
    let d = start_with(&scratch, &[], |c| {
        c.env("PATH", &path).env("NV_PIDS", &pids);
    });

    let subscribe = r#"{"id":0,"method":"subscribe","stream":"sysusage","params":{"intervalMs":3600000,"gpu":"auto"}}"#;
    let mut c = Client::connect(&d.socket);
    c.frame();
    c.send(subscribe);
    let event = c.until(r#""stream":"sysusage""#);
    assert!(event.contains(r#""method":"nvidia""#), "{event}");
    wait_for("nvidia-smi to start", || nvidia_pids(&pids).len() == 1);
    let first = nvidia_pids(&pids)[0];
    assert!(running(first));

    c.send(r#"{"id":3,"method":"unsubscribe","stream":"sysusage"}"#);
    assert_eq!(c.until(r#""id":3"#), r#"{"type":"reply","id":3,"ok":true}"#);
    wait_for("nvidia-smi to stop after unsubscribe", || !running(first));

    // Subscribing again starts it again; hanging up stops it too.
    c.send(subscribe);
    c.until(r#""stream":"sysusage""#);
    wait_for("nvidia-smi to start again", || {
        nvidia_pids(&pids).len() == 2
    });
    let second = nvidia_pids(&pids)[1];
    assert!(running(second));
    drop(c);
    wait_for("nvidia-smi to stop after the client left", || {
        !running(second)
    });
}
